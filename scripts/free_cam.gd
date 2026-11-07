class_name FreeCam
extends Node
## Recording tools (0.31.12, owner: clips for videos). A free camera you fly round the raid with, solo raids only:
## online it would let you look through walls and round corners, so it's off there (the hide-HUD key works anywhere).
##
## While it's on, your character stands where you left them (a body like other players see, so you're in the shot),
## takes no input, and can still be shot: scavs keep going. Fly with the move keys (where you look), jump / crouch
## go straight up / down, sprint goes faster, the mouse wheel picks the speed, aim zooms in. The camera eases into
## moves and turns so clips come out smooth. Its key (T by default) slows time down, then stops it, then back.
## Touch: the stick flies, dragging looks, UP / DOWN / SLOW / CAM buttons (TouchControls, group "cam").
## Not for scouting (0.31.13, owner: "make sure it's not exploitable"): it stays within LEASH of your character and
## can't go through walls, doors, windows or the ground, and must keep your character in sight (no round corners or
## in through doors), so it can't find scavs or loot you couldn't see from where you stand.

## Flying speeds (m/s); the mouse wheel steps through them.
const SPEEDS: Array[float] = [1.0, 2.5, 5.0, 10.0, 20.0]
const START_SPEED := 2
## Sprint held: this much faster.
const FAST := 3.0
## How quickly flying and turning catch up with the keys and mouse (higher = snappier, lower = smoother).
const MOVE_EASE := 5.0
const TURN_EASE := 12.0
## Aim held: the view zooms to this field of view.
const ZOOM_FOV := 30.0
## Slow motion's speed.
const SLOW_SCALE := 0.25
## A render layer the player's own first-person gun and hands go on while the camera is away, so it doesn't see
## them floating where your eyes were.
const VIEW_LAYER := 1 << 19
## How far from your character's head it can go (m).
const LEASH := 25.0
## What stops it: the world (ground, walls), doors, barred and glazed windows.
const SOLID_MASK := 1 | 16 | 128 | 256
## How close to a wall it can get (m).
const WALL_GAP := 0.25

enum TimeMode { NORMAL, SLOW, FROZEN }

const STAND_IN_SCENE := preload("res://scenes/remote_player.tscn")

var player: Player
var camera: Camera3D
var active := false
var time_mode := TimeMode.NORMAL
var speed_index := START_SPEED
## Where the camera is turned (radians), and where the mouse says it should be (it eases toward that).
var yaw := 0.0
var pitch := 0.0
var _want_yaw := 0.0
var _want_pitch := 0.0
var _velocity := Vector3.ZERO
var _fov := 80.0
## Your character as the camera sees it.
var stand_in: RemotePlayer
## First-person visuals moved onto VIEW_LAYER -> their old layers.
var _moved_layers := {}


func _init(owner_player: Player) -> void:
	player = owner_player
	name = "FreeCam"
	# Runs while time is stopped (and while the HUD pauses the game).
	process_mode = Node.PROCESS_MODE_ALWAYS


## The free camera can be used here: solo raids only (owner's security rules: no seeing round walls online).
static func allowed() -> bool:
	return not Network.main.in_online_raid()


func can_start() -> bool:
	return allowed() and player != null and player.is_inside_tree() and not player.controls_locked()


func toggle() -> void:
	if active:
		stop()
	else:
		start()


## Takes the view off the player. False if it can't be used here or now.
func start() -> bool:
	if active or not can_start():
		return false
	active = true
	player.camera_away = true
	camera = Camera3D.new()
	camera.name = "FreeCamera"
	_fov = player.base_fov
	camera.fov = _fov
	camera.near = 0.05
	camera.far = player.camera.far
	camera.cull_mask = player.camera.cull_mask & ~VIEW_LAYER
	player.get_parent().add_child(camera)
	var from := player.camera.global_transform
	# A little behind and above your eyes, so the first thing you see is yourself.
	var euler := from.basis.get_euler(EULER_ORDER_YXZ)
	yaw = euler.y
	pitch = clampf(euler.x, -1.45, 1.45)
	_want_yaw = yaw
	_want_pitch = pitch
	var back := Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ).z
	camera.global_position = from.origin
	camera.global_position = blocked_move(from.origin, from.origin + back * 1.6 + Vector3.UP * 0.4)
	_apply_turn()
	camera.make_current()
	_velocity = Vector3.ZERO
	_hide_first_person()
	_add_stand_in()
	return true


func stop() -> void:
	if not active:
		return
	active = false
	set_time(TimeMode.NORMAL)
	if is_instance_valid(player):
		player.camera_away = false
		player.camera.make_current()
	for node in _moved_layers:
		if is_instance_valid(node):
			(node as GeometryInstance3D).layers = _moved_layers[node]
	_moved_layers.clear()
	if is_instance_valid(stand_in):
		stand_in.queue_free()
	stand_in = null
	if is_instance_valid(camera):
		camera.queue_free()
	camera = null


## Normal speed, slow motion or stopped.
func set_time(mode: TimeMode) -> void:
	time_mode = mode
	Engine.time_scale = SLOW_SCALE if mode == TimeMode.SLOW else 1.0


func cycle_time() -> void:
	if active:
		set_time(((time_mode + 1) % 3) as TimeMode)


## Time is stopped (the HUD pauses the game for it).
func frozen() -> bool:
	return active and time_mode == TimeMode.FROZEN


func speed() -> float:
	return SPEEDS[speed_index]


func change_speed(step: int) -> void:
	speed_index = clampi(speed_index + step, 0, SPEEDS.size() - 1)


func _exit_tree() -> void:
	# (never leave the game in slow motion: leaving the raid, the end screen)
	Engine.time_scale = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := player.mouse_sensitivity * GameSettings.sensitivity * camera.fov / player.base_fov
		look_by(-event.screen_relative.y * sens, -event.screen_relative.x * sens)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
			change_speed(1 if button == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()


## Turns the camera (radians), like the mouse does.
func look_by(pitch_by: float, yaw_by: float) -> void:
	_want_yaw += yaw_by
	_want_pitch = clampf(_want_pitch + pitch_by, -1.45, 1.45)


## A finger dragged on the look side (touch), like Player.touch_look.
func touch_look(delta: Vector2) -> void:
	var sens := Player.TOUCH_LOOK * GameSettings.sensitivity * camera.fov / player.base_fov
	look_by(-delta.y * sens, -delta.x * sens)


func _process(delta: float) -> void:
	# Unslowed time: the camera flies at the same speed in slow motion and with time stopped (a paused game still
	# gives this node its frames).
	var dt := minf(delta / maxf(Engine.time_scale, 0.01), 0.1)
	if not active:
		return
	if not is_instance_valid(player) or player.controls_locked() or not allowed():
		stop()   # (died, extracted, the raid ended)
		return
	fly(dt)
	if is_instance_valid(stand_in):
		stand_in.push_state(RemotePlayer.capture(player))


## One step of flying, `dt` real seconds.
func fly(dt: float) -> void:
	var input := Vector2.ZERO
	var rise := 0.0
	var fast := false
	var zoom := false
	if TouchInput.playing():
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		rise = Input.get_action_strength("jump") - Input.get_action_strength("crouch")
		fast = Input.is_action_pressed("sprint")
		zoom = Input.is_action_pressed("aim")
	var look := Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
	var want := (look * Vector3(input.x, 0.0, input.y)) + Vector3.UP * rise
	want = want.limit_length(1.0) * speed() * (FAST if fast else 1.0)
	_velocity = _velocity.lerp(want, 1.0 - exp(-MOVE_EASE * dt))
	var old := camera.global_position
	var moved := blocked_move(old, old + _velocity * dt)
	if not moved.is_equal_approx(old + _velocity * dt):
		_velocity = (moved - old) / maxf(dt, 0.0001)   # (sliding along whatever stopped it)
	camera.global_position = moved
	var turn := 1.0 - exp(-TURN_EASE * dt)
	yaw = lerpf(yaw, _want_yaw, turn)
	pitch = lerpf(pitch, _want_pitch, turn)
	_apply_turn()
	camera.fov = lerpf(camera.fov, ZOOM_FOV if zoom else _fov, 1.0 - exp(-8.0 * dt))


## Where a move from `from` to `to` really ends: short of walls (sliding along them), within LEASH of your head, and
## in sight of it (otherwise it stays at `from`).
func blocked_move(from: Vector3, to: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var target := to
	for i in 2:   # (a second try slides along the first wall)
		var step := target - from
		if step.length() < 0.0001:
			break
		var reach := target + step.normalized() * WALL_GAP
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, reach, SOLID_MASK))
		if hit.is_empty():
			break
		var normal: Vector3 = hit.normal
		var stop: Vector3 = hit.position + normal * WALL_GAP
		target = stop + (target - stop).slide(normal) if i == 0 else stop
		if i == 1:
			break
	var head := player.global_position + Vector3.UP * 1.5
	if target.distance_to(head) > LEASH:
		target = head + (target - head).normalized() * LEASH
	# Only where it still sees your character from: no going round a corner or in through a door to look about.
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(target, head, SOLID_MASK)).is_empty():
		return from
	return target


func _apply_turn() -> void:
	camera.global_basis = Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)


## Moves the first-person gun, knife and hands (everything under the player's head) onto VIEW_LAYER.
func _hide_first_person() -> void:
	_moved_layers.clear()
	var todo: Array[Node] = [player.head]
	while not todo.is_empty():
		var node: Node = todo.pop_back()
		if node is GeometryInstance3D:
			_moved_layers[node] = (node as GeometryInstance3D).layers
			(node as GeometryInstance3D).layers = VIEW_LAYER
		todo.append_array(node.get_children())


## A body for you, the one other players would see, posed from your own state each frame. Looks only: no collision,
## no footsteps, not one of the raid's other players.
func _add_stand_in() -> void:
	stand_in = STAND_IN_SCENE.instantiate() as RemotePlayer
	stand_in.name = "FreeCamStandIn"
	stand_in.quiet = true
	stand_in.collision_layer = 0
	stand_in.collision_mask = 0
	player.get_parent().add_child(stand_in)
	stand_in.remove_from_group(RemotePlayer.GROUP)
	var pixel := stand_in.model as PixelModel
	if pixel != null:
		pixel.pick_outfit(Profile.look)
	stand_in.push_state(RemotePlayer.capture(player))
