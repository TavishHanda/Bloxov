class_name RemotePlayer
extends CharacterBody3D
## Another player in an online raid, as this machine sees them: a body moved by the states the server relays
## (no camera, no input). Shows where they are and look, crouching, leaning, aiming, sprinting, walking legs,
## and lying down when dead. Drawn slightly in the past (INTERP_DELAY), smoothly between the last updates,
## so 20 updates a second look like continuous movement.

## A state is [position, yaw, pitch, lean, flags] (see capture()). Flags and hitbox sizes live in Hitbox.
const FLAG_CROUCH := Hitbox.FLAG_CROUCH
const FLAG_AIM := Hitbox.FLAG_AIM
const FLAG_SPRINT := Hitbox.FLAG_SPRINT
const FLAG_DEAD := Hitbox.FLAG_DEAD
const FLAG_EXTRACTED := Hitbox.FLAG_EXTRACTED
const FLAG_ARMED := Hitbox.FLAG_ARMED
## How far in the past other players are drawn (two updates' worth, so there's always one to move toward).
const INTERP_DELAY := 0.1
## The head tilts around the neck (just below the head box). Its parts are the model's Head/Hat/Eyes/Mask nodes.
const NECK_HEIGHT := 1.38
const HEAD_PARTS := ["Head__", "Hat__", "Eyes__", "Mask__"]

@onready var model: Node3D = $Model
@onready var gun_model: Node3D = $Model/Gun
@onready var leg_l: Node3D = $Model/LegL
@onready var leg_r: Node3D = $Model/LegR
@onready var body_shape: CollisionShape3D = $BodyShape
@onready var head_shape: CollisionShape3D = $HeadShape

var peer_id := 0
var player_name := ""
## In our party: gets a name tag (friendly fire is on, so you need to tell them apart). Others get none.
var teammate := false
## The state being shown right now.
var shown: Array = []
## [arrival seconds, state], oldest first.
var _buffer: Array = []
var _walk_time := 0.0
var _crouch := 0.0
var _lean := 0.0
var _down := 0.0
var _gun_rest: Vector3
## Pivot at the neck that the head parts are moved under, so looking up and down tilts the head.
var head_pivot: Node3D


## What other players need to draw us.
static func capture(player: Player) -> Array:
	var flags := 0
	if player.is_crouching:
		flags |= FLAG_CROUCH
	if player.gun.is_aiming():
		flags |= FLAG_AIM
	if player.is_sprinting():
		flags |= FLAG_SPRINT
	if player.is_dead:
		flags |= FLAG_DEAD
	if player.extracted:
		flags |= FLAG_EXTRACTED
	if player.gun.weapon != null:
		flags |= FLAG_ARMED
	return [player.global_position, player.rotation.y, player.head.rotation.x, player.lean, flags]


func _ready() -> void:
	_gun_rest = gun_model.position
	head_pivot = Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position.y = NECK_HEIGHT
	model.add_child(head_pivot)
	for part in model.get_children():
		if HEAD_PARTS.any(func(prefix: String) -> bool: return part.name.begins_with(prefix)):
			part.reparent(head_pivot)
	# Each body gets its own shapes so crouching one doesn't shrink the others.
	body_shape.shape = body_shape.shape.duplicate()
	if teammate:
		# A small name tag over a teammate's head (owner: small; other players get none, PvP). Just a marker: the
		# HUD draws it crisp in the pixel font (WorldLabelsHUD, 0.8.16).
		var tag := Node3D.new()
		tag.name = "NameTag"
		tag.set_meta("label_kind", "name")
		tag.set_meta("label_text", player_name)
		tag.add_to_group(Effects.WORLD_LABELS)
		tag.position.y = 2.25
		add_child(tag)


## Adds a state that arrived now (`at` = seconds, for the test).
func push_state(state: Array, at := -1.0) -> void:
	if at < 0.0:
		at = Time.get_ticks_msec() / 1000.0
	if shown.is_empty():
		shown = state
		global_position = state[0]
		rotation.y = state[1]
	_buffer.append([at, state])
	if _buffer.size() > 20:
		_buffer.pop_front()


func _process(delta: float) -> void:
	if _buffer.is_empty():
		return
	update_view(Time.get_ticks_msec() / 1000.0 - INTERP_DELAY, delta)


## Puts the body where it was at `time` (between the two buffered states around it) and animates it.
func update_view(time: float, delta: float) -> void:
	while _buffer.size() > 2 and _buffer[1][0] <= time:
		_buffer.pop_front()
	var a: Array = _buffer[0]
	var b: Array = _buffer[1] if _buffer.size() > 1 else a
	var t := 1.0 if b[0] <= a[0] else clampf((time - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	var from: Array = a[1]
	var to: Array = b[1]
	var old_position := global_position
	global_position = (from[0] as Vector3).lerp(to[0], t)
	rotation.y = lerp_angle(from[1], to[1], t)
	var pitch := lerpf(from[2], to[2], t)
	shown = to
	var flags: int = to[4]
	visible = not flags & FLAG_EXTRACTED
	var step := minf(delta * 10.0, 1.0)
	_crouch = lerpf(_crouch, 1.0 if flags & FLAG_CROUCH else 0.0, step)
	_lean = lerpf(from[3], to[3], t)
	_down = lerpf(_down, 1.0 if flags & FLAG_DEAD else 0.0, step)
	_pose(pitch, flags, (global_position - old_position).length() / maxf(delta, 0.001), delta)


func _pose(pitch: float, flags: int, speed: float, delta: float) -> void:
	var height := Hitbox.height_scale(_crouch)
	model.scale = Vector3(1.0, height, 1.0)
	# Lean tips the whole body around the feet; the dead fall over backward. (The model faces -Z.)
	model.rotation.z = -_lean * Hitbox.LEAN_ANGLE
	# Negative X tips it forward (sprinting), positive backward (lying on its back when dead).
	model.rotation.x = lerpf(-0.15 if flags & FLAG_SPRINT else 0.0, 1.5, _down)
	# Looking up and down tilts the head (owner: the head, not the gun), limited so it stays on the shoulders.
	head_pivot.rotation.x = clampf(pitch, -0.7, 0.7)
	# The model's built-in rifle only shows while they hold a gun (until guns are separate models: BACKLOG).
	gun_model.visible = flags & FLAG_ARMED != 0
	gun_model.position = _gun_rest + (Vector3(0, 0.12, 0.08) if flags & FLAG_AIM else Vector3.ZERO)
	if speed > 0.3 and _down < 0.5:
		_walk_time += delta * speed * 2.5
	var swing := sin(_walk_time) * 0.6 * minf(speed / 2.0, 1.0)
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	# Hitboxes follow the pose (crouched = shorter, leaning = head off to the side), same as the server's (Hitbox).
	(body_shape.shape as BoxShape3D).size = Hitbox.body_size(_crouch)
	body_shape.position = Hitbox.body_center(_crouch)
	head_shape.position = Hitbox.head_center(_crouch, _lean)
	body_shape.disabled = _down > 0.5
	head_shape.disabled = _down > 0.5
