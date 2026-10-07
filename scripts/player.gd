extends CharacterBody3D
## First-person controller: WASD to move, mouse to look, Shift to sprint, Space to jump.

@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 4.8
@export var mouse_sensitivity := 0.0025
## How quickly we reach target speed. Higher = snappier.
@export var acceleration := 12.0
## Mouse movements bigger than this (in pixels, in one event) are treated as glitches and ignored.
## Works around a Chrome bug where captured-mouse input sometimes reports a huge bogus jump.
@export var max_mouse_delta := 200.0
## Falling below this height respawns the player.
@export var kill_height := -20.0

@onready var head: Node3D = $Head

var _spawn_position: Vector3

# Mouse debug stats, shown by the HUD's F3 overlay.
var debug_recent_dx: Array[int] = []
var debug_max_delta := 0.0
var debug_spikes_dropped := 0


func _ready() -> void:
	_spawn_position = global_position


func _unhandled_input(event: InputEvent) -> void:
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


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var weight := minf(acceleration * delta, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * speed, weight)

	move_and_slide()

	if global_position.y < kill_height:
		global_position = _spawn_position
		velocity = Vector3.ZERO
