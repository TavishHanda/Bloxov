class_name Player
extends CharacterBody3D
## First-person controller: WASD to move, mouse to look, Shift to sprint, Space to jump.

const HURT_SOUND := preload("res://audio/hurt.wav")

@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 4.8
@export var mouse_sensitivity := 0.0025
## How quickly we reach target speed. Higher = snappier.
@export var acceleration := 12.0
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

var is_dead := false
var dead_for := 0.0

var _spawn_position: Vector3
var _trauma := 0.0

# Mouse debug stats, shown by the HUD's F3 overlay.
var debug_recent_dx: Array[int] = []
var debug_max_delta := 0.0
var debug_spikes_dropped := 0


func _ready() -> void:
	add_to_group("player")
	_spawn_position = global_position
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	recoil.rotation.x += deg_to_rad(pitch_deg)
	recoil.rotation.y += deg_to_rad(yaw_deg)


## Screen shake. Amounts stack up to 1.0 and fade out.
func add_shake(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		if event is InputEventMouseButton and event.pressed and dead_for > 1.0:
			get_tree().reload_current_scene()
		return
	# Browsers only allow mouse capture after a click, so capture on click.
	# Only request it when not already captured; re-locking mid-game can glitch in browsers.
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
		rotate_y(-event.screen_relative.x * mouse_sensitivity)
		head.rotate_x(-event.screen_relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))


func _process(delta: float) -> void:
	recoil.rotation = recoil.rotation.lerp(Vector3.ZERO, minf(recoil_recovery * delta, 1.0))
	_trauma = maxf(_trauma - delta * 1.8, 0.0)
	var shake := _trauma * _trauma
	camera.h_offset = randf_range(-1.0, 1.0) * 0.06 * shake
	camera.v_offset = randf_range(-1.0, 1.0) * 0.06 * shake
	camera.rotation.z = randf_range(-1.0, 1.0) * 0.05 * shake
	if is_dead:
		dead_for += delta


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir := Vector2.ZERO
	var speed := walk_speed
	if not is_dead:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_pressed("sprint"):
			speed = sprint_speed

	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var weight := minf(acceleration * delta, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * speed, weight)

	move_and_slide()

	if global_position.y < kill_height:
		global_position = _spawn_position
		velocity = Vector3.ZERO


func _on_damaged(_amount: int, source_position: Vector3) -> void:
	add_shake(0.55)
	Effects.sound(get_tree().current_scene, HURT_SOUND, 0.0, 0.1)
	var push := global_position - source_position
	push.y = 0.0
	if push.length() > 0.01:
		velocity += push.normalized() * 6.0
		velocity.y = maxf(velocity.y, 2.0)


func _on_died() -> void:
	is_dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(head, "rotation:z", 1.2, 0.6)
