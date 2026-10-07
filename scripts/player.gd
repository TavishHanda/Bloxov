extends CharacterBody3D
## First-person controller: WASD to move, mouse to look, Shift to sprint, Space to jump.

@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 4.8
@export var mouse_sensitivity := 0.0025
## How quickly we reach target speed. Higher = snappier.
@export var acceleration := 12.0
## Falling below this height respawns the player.
@export var kill_height := -20.0

@onready var head: Node3D = $Head

var _spawn_position: Vector3


func _ready() -> void:
	_spawn_position = global_position


func _unhandled_input(event: InputEvent) -> void:
	# Browsers only allow mouse capture after a click, so capture on click.
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
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
