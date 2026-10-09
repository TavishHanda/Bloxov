class_name Spectator
extends Control
## Dead in an online raid while a teammate is still in it (owner, 0.9.5): watch them instead of going straight back.
## A camera follows them over the shoulder (pulled in so walls don't block it); at the top, a gunmetal plate says
## SPECTATING and their name, with a BACK TO HIDEOUT button under it. Once they're out (extracted, dead, left),
## `finished` brings the end-of-raid screen back.

signal finished

const PLATE_SIZE := Vector2(320, 40)
const PLATE_TOP := 62.0
## Over the shoulder: this far behind their head, this much above it.
const BACK := 2.6
const UP := 0.5

var watching: RemotePlayer = null
var camera: Camera3D
var _plate: Control
var _button: Button


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_plate = Control.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.draw.connect(_draw_plate)
	add_child(_plate)
	_button = Button.new()
	_button.text = "BACK TO HIDEOUT"
	_button.focus_mode = Control.FOCUS_NONE
	LootUI.style_button(_button, 20)
	_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/hideout.tscn"))
	add_child(_button)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_plate.offset_left = -PLATE_SIZE.x * 0.5
	_plate.offset_right = PLATE_SIZE.x * 0.5
	_plate.offset_top = PLATE_TOP
	_plate.offset_bottom = PLATE_TOP + PLATE_SIZE.y
	_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_button.offset_left = -110
	_button.offset_right = 110
	_button.offset_top = PLATE_TOP + PLATE_SIZE.y + 10
	_button.offset_bottom = PLATE_TOP + PLATE_SIZE.y + 50


## A teammate we could watch (in the raid, not dead or extracted; downed is fine), or 0.
static func watchable_teammate() -> int:
	if not Network.main.in_online_raid():
		return 0
	for peer in Network.main.teammates:
		var state: Array = Network.main.states.get(peer, [])
		if not state.is_empty() and int(state[4]) & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED) == 0:
			return peer
	return 0


## The body we see for a peer (null if they aren't shown).
func body_of(peer: int) -> RemotePlayer:
	for node in RaidScope.nodes(self, RemotePlayer.GROUP):
		var body := node as RemotePlayer
		if body != null and body.peer_id == peer:
			return body
	return null


## Starts watching `peer`. False if they can't be watched.
func start(peer: int) -> bool:
	var body := body_of(peer)
	if body == null or not _can_watch(body):
		return false
	watching = body
	if camera == null:
		camera = Camera3D.new()
		camera.name = "SpectatorCamera"
		camera.fov = 80.0
		body.get_parent().add_child(camera)
	update_camera()
	camera.make_current()
	visible = true
	_plate.queue_redraw()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


func stop() -> void:
	if not visible:
		return
	visible = false
	watching = null
	finished.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	if watching == null or not is_instance_valid(watching) or not _can_watch(watching):
		stop()
		return
	update_camera()


func _can_watch(body: RemotePlayer) -> bool:
	return not body.shown.is_empty() and int(body.shown[4]) & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED) == 0


## Puts the camera behind the watched player's head, looking where they look (pulled in front of walls).
func update_camera() -> void:
	if camera == null or watching == null:
		return
	var flags: int = watching.shown[4]
	var eye := 1.6
	if flags & Hitbox.FLAG_DOWNED:
		eye = 0.5
	elif flags & Hitbox.FLAG_CROUCH:
		eye = 1.1
	var head := watching.global_position + Vector3(0, eye, 0)
	var pitch := clampf(float(watching.shown[2]), -0.6, 0.6)
	var forward := Basis(Vector3.UP, watching.rotation.y) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
	var spot := head - forward * BACK + Vector3(0, UP, 0)
	var query := PhysicsRayQueryParameters3D.create(head, spot, 1)
	var hit := watching.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		spot = hit.position + (head - hit.position).normalized() * 0.25
	camera.global_transform = Transform3D(Basis.looking_at(head + forward * 3.0 - spot), spot)


func _draw_plate() -> void:
	if watching == null or not is_instance_valid(watching):
		return
	var rect := Rect2(Vector2.ZERO, _plate.size)
	HudStyle.draw_plate(_plate, rect)
	var title := "SPECTATING"
	var name_text := watching.player_name.to_upper()
	var gap := 12.0
	var title_w := HudStyle.text_width(title, 20) - 1.0
	var name_w := HudStyle.text_width(name_text, 30) - 1.0
	var x := roundf(rect.get_center().x - (title_w + gap + name_w) * 0.5)
	HudStyle.draw_text(_plate, title, Vector2(x, HudStyle.centered_baseline(rect.get_center().y, 20)), 20, HudStyle.INK_DIM)
	HudStyle.draw_text(_plate, name_text, Vector2(x + title_w + gap, HudStyle.centered_baseline(rect.get_center().y, 30)), 30, WorldLabelsHUD.TEAMMATE)
