class_name RemotePlayer
extends CharacterBody3D
## Another player in an online raid, as this machine sees them: a body moved by the states the server relays
## (no camera, no input). Shows where they are and look, crouching, leaning, aiming, sprinting, walking legs,
## and lying down when dead. Drawn slightly in the past (INTERP_DELAY), smoothly between the last updates,
## so 20 updates a second look like continuous movement.

## A state is [position, yaw, pitch, lean, flags] (see capture()).
const FLAG_CROUCH := 1
const FLAG_AIM := 2
const FLAG_SPRINT := 4
const FLAG_DEAD := 8
const FLAG_EXTRACTED := 16
## How far in the past other players are drawn (two updates' worth, so there's always one to move toward).
const INTERP_DELAY := 0.1
## Same as the local player (player.gd: lean_distance 0.35 m at head height): the angle the body tips by.
const LEAN_ANGLE := 0.21
const CROUCH_SCALE := 0.67
const BODY_HEIGHT := 1.35
const HEAD_HEIGHT := 1.71

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
	return [player.global_position, player.rotation.y, player.head.rotation.x, player.lean, flags]


func _ready() -> void:
	_gun_rest = gun_model.position
	# Each body gets its own shapes so crouching one doesn't shrink the others.
	body_shape.shape = body_shape.shape.duplicate()
	if teammate:
		var tag := Label3D.new()
		tag.name = "NameTag"
		tag.text = player_name
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.pixel_size = 0.0015
		tag.modulate = Color(0.55, 1.0, 0.55)
		tag.outline_size = 8
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
	var height := lerpf(1.0, CROUCH_SCALE, _crouch)
	model.scale = Vector3(1.0, height, 1.0)
	# Lean tips the whole body around the feet; the dead fall over backward. (The model faces -Z.)
	model.rotation.z = -_lean * LEAN_ANGLE
	# Negative X tips it forward (sprinting), positive backward (lying on its back when dead).
	model.rotation.x = lerpf(-0.15 if flags & FLAG_SPRINT else 0.0, 1.5, _down)
	gun_model.rotation.x = pitch
	gun_model.position = _gun_rest + (Vector3(0, 0.12, 0.08) if flags & FLAG_AIM else Vector3.ZERO)
	if speed > 0.3 and _down < 0.5:
		_walk_time += delta * speed * 2.5
	var swing := sin(_walk_time) * 0.6 * minf(speed / 2.0, 1.0)
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	# Hitboxes follow the pose (crouched = shorter, leaning = head off to the side), ready for shooting (0.7.3).
	(body_shape.shape as BoxShape3D).size.y = BODY_HEIGHT * height
	body_shape.position.y = BODY_HEIGHT * height * 0.5
	head_shape.position = Vector3(sin(_lean * LEAN_ANGLE) * HEAD_HEIGHT * height, cos(_lean * LEAN_ANGLE) * HEAD_HEIGHT * height, 0)
	body_shape.disabled = _down > 0.5
	head_shape.disabled = _down > 0.5
