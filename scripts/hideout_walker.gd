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
const FOV := 75.0
const BASE_SENSITIVITY := 0.0025
## Footsteps (0.25.22, owner: the hideout was "really quiet"): the raid's steps (Surfaces), as loud and as far apart.
const WALK_STRIDE := 1.5
const SPRINT_STRIDE := 1.9
const WALK_STEP_DB := -9.0
const SPRINT_STEP_DB := -4.0

## True while the menu is open (no walking or looking).
var locked := false
## True while sitting or playing darts (0.21.7): you stay put but can still look round.
var pinned := false
var camera: Camera3D
var _pitch := 0.0
var _stride_left := 0.0
## Footsteps taken so far (the smoke test counts them).
var steps_taken := 0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = FOV
	camera.near = 0.05
	add_child(camera)
	camera.current = true
	floor_snap_length = 0.3
	add_to_group(Reacts.MOVER)


func _physics_process(delta: float) -> void:
	if pinned:
		velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	var input := Vector2.ZERO
	if not locked:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	var sprinting := Input.is_action_pressed("sprint") and input.y < -0.5
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	var wish := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized() * speed
	var flat := Vector2(velocity.x, velocity.z)
	var target := Vector2(wish.x, wish.z)
	flat = flat.move_toward(target, (ACCELERATION if target.length() > 0.1 else DECELERATION) * delta)
	velocity.x = flat.x
	velocity.z = flat.y
	var fall_speed := -velocity.y if not is_on_floor() else 0.0
	move_and_slide()
	if fall_speed > 2.0 and is_on_floor():
		# Landing, as in a raid.
		_step(4.0)
		WorldSounds.own(self, WorldSounds.LAND, clampf(-16.0 + fall_speed * 1.2, -14.0, 0.0))
	_footsteps(delta, sprinting)


func _footsteps(delta: float, sprinting: bool) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or speed < 0.5:
		_stride_left = minf(_stride_left, 0.3)
		return
	_stride_left -= speed * delta
	if _stride_left > 0.0:
		return
	var fast := sprinting and speed > WALK_SPEED + 0.2
	_stride_left = SPRINT_STRIDE if fast else WALK_STRIDE
	_step(SPRINT_STEP_DB if fast else WALK_STEP_DB)


func _step(db: float) -> void:
	steps_taken += 1
	Surfaces.step(self, db)


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
