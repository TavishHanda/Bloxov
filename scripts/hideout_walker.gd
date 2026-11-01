class_name HideoutWalker
extends CharacterBody3D
## You in the walkable hideout (0.21.0): walk, sprint, jump, crouch, go prone (0.28.3, owner) and look round. No
## gun, no health, no inventory: the hideout is safe, and everything you'd do there opens the hideout menu. Same speeds and feel as in a raid.

const WALK_SPEED := 3.1
const SPRINT_SPEED := 5.15
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
## Crouching and prone (0.28.3, owner: "allow proning and crouching in the hideout"): the raid's keys, speeds and
## heights (player_base.gd), the same toggles (crouch from prone gets you to a crouch, jump stands you up).
const CROUCH_SPEED := 2.2
const PRONE_SPEED := 1.0
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const PRONE_HEIGHT := 0.8
const CROUCH_EYE := 1.0
const PRONE_EYE := 0.4
const EYE_SPEED := 6.0      # how fast the view drops or rises (per second, a share of the way)

## True while the menu is open (no walking or looking).
var locked := false
## True while sitting or playing darts (0.21.7): you stay put but can still look round.
var pinned := false
var camera: Camera3D
var _pitch := 0.0
var _stride_left := 0.0
## Footsteps taken so far (the smoke test counts them).
var steps_taken := 0
var is_crouching := false
var is_prone := false
var _capsule: CapsuleShape3D
var _shape: CollisionShape3D


func _ready() -> void:
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_shape = shape
	_capsule = capsule
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
			if is_prone or is_crouching:
				set_crouching(false)   # (jump stands you up first, as in a raid)
			else:
				velocity.y = JUMP_VELOCITY
		if Input.is_action_just_pressed("crouch"):
			set_crouching(is_prone or not is_crouching)
		elif Input.is_action_just_pressed("prone"):
			set_prone(not is_prone)
	var low := is_prone or is_crouching
	var sprinting := Input.is_action_pressed("sprint") and input.y < -0.5 and not low
	var speed := PRONE_SPEED if is_prone else (CROUCH_SPEED if is_crouching else (SPRINT_SPEED if sprinting else WALK_SPEED))
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
	var eye := PRONE_EYE if is_prone else (CROUCH_EYE if is_crouching else EYE_HEIGHT)
	camera.position.y = lerpf(camera.position.y, eye, minf(1.0, EYE_SPEED * delta))


## Crouch (or get up from it); from prone, to a crouch (true) or standing. Not if there's no room over you.
func set_crouching(crouch: bool) -> void:
	if is_prone:
		if _ceiling_blocked(CROUCH_HEIGHT if crouch else STAND_HEIGHT):
			return
		is_prone = false
		is_crouching = crouch
	elif crouch != is_crouching:
		if not crouch and _ceiling_blocked(STAND_HEIGHT):
			return
		is_crouching = crouch
	_set_capsule()


## Lie down, or get up (standing if there's room, else crouched).
func set_prone(on: bool) -> void:
	if on == is_prone:
		return
	if not on:
		set_crouching(false)
		if is_prone:
			set_crouching(true)
		return
	is_prone = true
	is_crouching = true
	_set_capsule()
	WorldSounds.own(self, WorldSounds.PRONE, -8.0)


## Straight up at once, whatever's over you (sitting down on a seat).
func straighten() -> void:
	is_prone = false
	is_crouching = false
	_set_capsule()
	camera.position.y = EYE_HEIGHT


func _set_capsule() -> void:
	_capsule.height = PRONE_HEIGHT if is_prone else (CROUCH_HEIGHT if is_crouching else STAND_HEIGHT)
	_shape.position.y = _capsule.height * 0.5


func _ceiling_blocked(height: float) -> bool:
	var from := global_position + Vector3(0, 0.2, 0)
	var query := PhysicsRayQueryParameters3D.create(from, global_position + Vector3(0, height + 0.05, 0), 1, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


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
	if is_prone:
		return   # (crawling makes no steps)
	_step(SPRINT_STEP_DB if fast else (WALK_STEP_DB - 6.0 if is_crouching else WALK_STEP_DB))


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
