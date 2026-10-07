class_name Player
extends CharacterBody3D
## First-person controller: WASD to move, mouse to look, Shift to sprint, Space to jump.

const HURT_SOUND := preload("res://audio/hurt.wav")
const HEAL_SOUND := preload("res://audio/mag_out.wav")

@export_group("Movement")
## Meters per second. For reference, a real jog is ~3, a run ~5.
@export var walk_speed := 3.4
## Sprint only works moving forward, and lowers your gun.
@export var sprint_speed := 5.6
## Speed multipliers when walking backwards / sideways.
@export var backward_multiplier := 0.7
@export var strafe_multiplier := 0.85
## How fast you speed up and slow down on the ground (m/s per second). Lower = heavier.
@export var ground_acceleration := 16.0
@export var ground_deceleration := 20.0
## How much you can steer in the air (m/s per second). Low = jumps commit you.
@export var air_control := 2.5
## About 0.6 m high.
@export var jump_velocity := 3.6
@export var jump_cooldown := 0.45
## Landing from a jump or fall slows you briefly.
@export var landing_slowdown_time := 0.3
@export var landing_slowdown := 0.5

@export_group("Camera")
@export var mouse_sensitivity := 0.0025
@export var base_fov := 80.0
## Extra field of view while sprinting, for a sense of speed.
@export var sprint_fov_boost := 6.0
## Head bob strength (meters) when walking / sprinting.
@export var walk_bob := 0.03
@export var sprint_bob := 0.055
## Camera lean when strafing (degrees).
@export var strafe_tilt := 1.5

@export_group("Other")
## How quickly the camera settles back after recoil.
@export var recoil_recovery := 9.0
## Mouse movements bigger than this (in pixels, in one event) are treated as glitches and ignored.
## Works around a Chrome bug where captured-mouse input sometimes reports a huge bogus jump.
@export var max_mouse_delta := 200.0
## Falling below this height respawns the player.
@export var kill_height := -20.0

@onready var head: Node3D = $Head
@onready var recoil: Node3D = $Head/Recoil
@onready var camera: Camera3D = $Head/Recoil/Camera3D
@onready var gun: Gun = $Head/Recoil/Camera3D/Gun
@onready var health: Health = $Health
@onready var inventory: Inventory = $Inventory
@onready var interactor: Interactor = $Interactor

var is_dead := false
## True once the player has extracted (raid over, controls off).
var extracted := false

## Seconds left on the current heal, and the item being used.
var heal_time_left := 0.0
var heal_duration := 0.0
var _heal_item := ""

var _spawn_position: Vector3
var _trauma := 0.0
var _sprinting := false
var _jump_cooldown_left := 0.0
var _landing_left := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _bob_time := 0.0
var _landing_dip := 0.0
var _move_input := Vector2.ZERO
var _roll := 0.0

# Mouse debug stats, shown by the HUD's F3 overlay.
var debug_recent_dx: Array[int] = []
var debug_max_delta := 0.0
var debug_spikes_dropped := 0


func _ready() -> void:
	add_to_group("player")
	_spawn_position = global_position
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func controls_locked() -> bool:
	return is_dead or extracted


func is_healing() -> bool:
	return heal_time_left > 0.0


## True while actually sprinting (holding Shift, moving forward, on the ground).
func is_sprinting() -> bool:
	return _sprinting


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func teleport_to(pos: Vector3) -> void:
	global_position = pos
	_spawn_position = pos
	velocity = Vector3.ZERO


func face_towards(point: Vector3) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		rotation.y = atan2(-dir.x, -dir.z)


## Called by the Raid when you make it out.
func extract() -> void:
	extracted = true
	heal_time_left = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## H key: use the heal item that best fits how hurt you are.
func try_heal() -> void:
	var index := inventory.find_heal(health.max_health - health.current)
	if index >= 0:
		use_item(index)


## Use a heal item from the backpack. Takes a few seconds; you can't shoot meanwhile.
func use_item(index: int) -> void:
	if controls_locked() or is_healing() or health.current >= health.max_health:
		return
	var id := inventory.items[index]
	if ItemDB.kind(id) != "heal":
		return
	_heal_item = inventory.remove_at(index)
	heal_duration = ItemDB.item(id)["use_time"]
	heal_time_left = heal_duration
	Effects.sound(get_tree().current_scene, HEAL_SOUND, -4.0)


func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	recoil.rotation.x += deg_to_rad(pitch_deg)
	recoil.rotation.y += deg_to_rad(yaw_deg)


## Screen shake. Amounts stack up to 1.0 and fade out.
func add_shake(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if controls_locked():
		return
	# Capturing the mouse (click to play) is handled by the HUD's pause menu.
	if event.is_action_pressed("heal"):
		try_heal()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var delta_len: float = event.screen_relative.length()
		debug_max_delta = maxf(debug_max_delta, delta_len)
		debug_recent_dx.append(roundi(event.screen_relative.x))
		if debug_recent_dx.size() > 12:
			debug_recent_dx.pop_front()
		if delta_len > max_mouse_delta:
			debug_spikes_dropped += 1
			return
		var sens := mouse_sensitivity * GameSettings.sensitivity
		rotate_y(-event.screen_relative.x * sens)
		head.rotate_x(-event.screen_relative.y * sens)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))


func _process(delta: float) -> void:
	recoil.rotation = recoil.rotation.lerp(Vector3.ZERO, minf(recoil_recovery * delta, 1.0))
	_trauma = maxf(_trauma - delta * 1.8, 0.0)
	var shake := _trauma * _trauma
	camera.h_offset = randf_range(-1.0, 1.0) * 0.06 * shake
	camera.v_offset = randf_range(-1.0, 1.0) * 0.06 * shake
	_update_camera_motion(delta, shake)
	if heal_time_left > 0.0:
		heal_time_left -= delta
		if heal_time_left <= 0.0:
			heal_time_left = 0.0
			health.heal(ItemDB.item(_heal_item)["heal"])


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity += get_gravity() * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	_jump_cooldown_left -= delta
	_landing_left -= delta

	var input_dir := Vector2.ZERO
	if not controls_locked():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and on_floor and _jump_cooldown_left <= 0.0:
			velocity.y = jump_velocity
			_jump_cooldown_left = jump_cooldown
	_move_input = input_dir

	# Sprint: only forward-ish, on the ground, not while healing.
	_sprinting = (not controls_locked() and on_floor and not is_healing()
		and Input.is_action_pressed("sprint") and input_dir.y < -0.5)

	var target := _target_velocity(input_dir)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor:
		var rate := ground_acceleration if target.length() > horizontal.length() else ground_deceleration
		horizontal = horizontal.move_toward(target, rate * delta)
	else:
		# In the air you keep your momentum and can only nudge it.
		horizontal = horizontal.move_toward(target, air_control * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()

	# Landing.
	if is_on_floor() and not _was_on_floor and _fall_speed > 2.0:
		_landing_left = landing_slowdown_time
		_landing_dip = clampf(_fall_speed * 0.02, 0.03, 0.15)
	if is_on_floor():
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()

	if global_position.y < kill_height:
		global_position = _spawn_position
		velocity = Vector3.ZERO


func _target_velocity(input_dir: Vector2) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO
	var speed := sprint_speed if _sprinting else walk_speed
	if is_healing():
		speed = walk_speed * 0.5
	if _landing_left > 0.0:
		speed *= landing_slowdown
	# Slower backwards and sideways.
	var scaled := Vector2(input_dir.x * strafe_multiplier, input_dir.y * (backward_multiplier if input_dir.y > 0.0 else 1.0))
	var local := Vector3(scaled.x, 0.0, scaled.y) * speed
	if local.length() > speed:
		local = local.normalized() * speed
	return transform.basis * local


## Head bob, strafe lean, landing dip and sprint FOV.
func _update_camera_motion(delta: float, shake: float) -> void:
	var speed := horizontal_speed() if is_on_floor() else 0.0
	_bob_time += delta * speed * (1.9 if _sprinting else 2.2)
	var bob_amount := (sprint_bob if _sprinting else walk_bob) * minf(speed / walk_speed, 1.0)
	_landing_dip = lerpf(_landing_dip, 0.0, minf(delta * 8.0, 1.0))
	var bob := Vector3(cos(_bob_time * 0.5) * bob_amount * 0.6, -absf(sin(_bob_time * 0.5)) * bob_amount - _landing_dip, 0.0)
	camera.position = camera.position.lerp(bob, minf(delta * 12.0, 1.0))

	var tilt := deg_to_rad(-_move_input.x * strafe_tilt)
	_roll = lerpf(_roll, tilt, minf(delta * 8.0, 1.0))
	camera.rotation.z = _roll + randf_range(-1.0, 1.0) * 0.05 * shake

	var target_fov := base_fov + (sprint_fov_boost if _sprinting and speed > walk_speed else 0.0)
	camera.fov = lerpf(camera.fov, target_fov, minf(delta * 6.0, 1.0))


func _on_damaged(_amount: int, source_position: Vector3) -> void:
	add_shake(0.55)
	Effects.sound(get_tree().current_scene, HURT_SOUND, 0.0, 0.1)
	var push := global_position - source_position
	push.y = 0.0
	if push.length() > 0.01:
		velocity += push.normalized() * 2.5


func _on_died() -> void:
	is_dead = true
	heal_time_left = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(head, "rotation:z", 1.2, 0.6)
