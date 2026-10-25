class_name HideoutWalker
extends CharacterBody3D
## You in the walkable hideout (0.21.0): walk, sprint, jump and look round. No gun, no health, no inventory: the
## hideout is safe, and everything you'd do there opens the hideout menu. Same speeds and feel as in a raid.

const WALK_SPEED := 3.4
const SPRINT_SPEED := 5.6
const JUMP_VELOCITY := 4.4
const ACCELERATION := 16.0
const DECELERATION := 20.0
const EYE_HEIGHT := 1.6
const BASE_SENSITIVITY := 0.0025

## True while the menu is open (no walking or looking).
var locked := false
var camera: Camera3D
var _pitch := 0.0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 75.0
	camera.near = 0.05
	add_child(camera)
	camera.current = true
	floor_snap_length = 0.3


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	var input := Vector2.ZERO
	if not locked:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") and input.y < -0.5 else WALK_SPEED
	var wish := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized() * speed
	var flat := Vector2(velocity.x, velocity.z)
	var target := Vector2(wish.x, wish.z)
	flat = flat.move_toward(target, (ACCELERATION if target.length() > 0.1 else DECELERATION) * delta)
	velocity.x = flat.x
	velocity.z = flat.y
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).relative * BASE_SENSITIVITY * GameSettings.sensitivity
		look(motion.x, motion.y)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not GameSettings.is_phone():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Turns the view: yaw right by `yaw`, pitch down by `pitch` (radians).
func look(yaw: float, pitch: float) -> void:
	rotate_y(-yaw)
	_pitch = clampf(_pitch - pitch, -1.45, 1.45)
	camera.rotation.x = _pitch


## Where you're looking, flat on the ground.
func facing() -> Vector3:
	return -transform.basis.z
