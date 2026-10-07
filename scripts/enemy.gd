class_name Enemy
extends CharacterBody3D
## Rusher: spots the player, runs straight at them and punches. Dumb on purpose for Phase 1.
## (Real pathfinding comes in Phase 4.)

enum State { IDLE, CHASE, WINDUP, RECOVER, DEAD }

const GROWL_SOUND := preload("res://audio/growl.wav")
const POP_SOUND := preload("res://audio/pop.wav")
const FLASH_MATERIAL := preload("res://materials/flash_white.tres")
const WINDUP_MATERIAL := preload("res://materials/flash_red.tres")

@export var move_speed := 4.2
@export var sight_range := 28.0
@export var attack_range := 1.7
## The punch lands if the player is still this close when the windup finishes.
@export var attack_hit_range := 2.4
@export var attack_damage := 20
@export var windup_time := 0.4
@export var recover_time := 0.6
## Seconds without seeing the player before giving up the chase.
@export var give_up_time := 5.0
@export var burst_color := Color(0.55, 0.35, 0.8)

@onready var health: Health = $Health
@onready var model: Node3D = $Model
@onready var leg_l: Node3D = $Model/LegL
@onready var leg_r: Node3D = $Model/LegR

var state := State.IDLE

var _target: Player
var _state_time := 0.0
var _lost_sight_time := 0.0
var _knockback := Vector3.ZERO
var _wander_dir := Vector3.ZERO
var _wander_time := 0.0
var _flash_time := 0.0
var _walk_time := 0.0
var _side := 1.0


func _ready() -> void:
	add_to_group("enemies")
	_side = 1.0 if randf() < 0.5 else -1.0
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


## Called by the gun (via the "enemies" group) whenever the player fires.
func hear_noise(pos: Vector3, radius: float) -> void:
	if state == State.IDLE and global_position.distance_to(pos) <= radius:
		_set_state(State.CHASE)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	_state_time += delta

	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as Player

	var to_target := Vector3.ZERO
	var dist := INF
	if _target != null and not _target.is_dead:
		to_target = _target.global_position - global_position
		to_target.y = 0.0
		dist = to_target.length()

	var desired := Vector3.ZERO
	match state:
		State.IDLE:
			desired = _wander(delta)
			if dist < sight_range and _can_see_target():
				_set_state(State.CHASE)
		State.CHASE:
			if dist == INF:
				_set_state(State.IDLE)
			else:
				if _can_see_target():
					_lost_sight_time = 0.0
				else:
					_lost_sight_time += delta
				if _lost_sight_time > give_up_time:
					_set_state(State.IDLE)
				elif dist < attack_range:
					_set_state(State.WINDUP)
					Effects.sound_at(get_tree().current_scene, GROWL_SOUND, global_position, 0.0, 0.15)
				else:
					desired = to_target.normalized() * move_speed
					if is_on_wall():
						# Head-on into a wall: sidestep instead of grinding.
						desired = desired.rotated(Vector3.UP, PI * 0.4 * _side)
			_face(to_target, delta)
		State.WINDUP:
			_face(to_target, delta)
			if _state_time >= windup_time:
				if dist < attack_hit_range:
					_target.health.take_damage(attack_damage, global_position)
				_set_state(State.RECOVER)
		State.RECOVER:
			if _state_time >= recover_time:
				_set_state(State.CHASE)

	_knockback = _knockback.lerp(Vector3.ZERO, minf(delta * 8.0, 1.0))
	velocity.x = desired.x + _knockback.x
	velocity.z = desired.z + _knockback.z
	move_and_slide()


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	# Goofy walk cycle.
	var speed := Vector2(velocity.x, velocity.z).length()
	_walk_time += delta * speed * 2.5
	var swing := sin(_walk_time) * 0.6 * minf(speed / 2.0, 1.0)
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing

	# Windup telegraph: lean back and glow red.
	var lean := -0.35 if state == State.WINDUP else 0.0
	model.rotation.x = lerpf(model.rotation.x, lean, minf(delta * 12.0, 1.0))

	_flash_time -= delta
	if _flash_time > 0.0:
		_set_overlay(FLASH_MATERIAL)
	elif state == State.WINDUP:
		_set_overlay(WINDUP_MATERIAL)
	else:
		_set_overlay(null)


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_lost_sight_time = 0.0


func _wander(delta: float) -> Vector3:
	_wander_time -= delta
	if _wander_time <= 0.0:
		_wander_time = randf_range(1.5, 4.0)
		if randf() < 0.4:
			_wander_dir = Vector3.ZERO
		else:
			_wander_dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	if _wander_dir != Vector3.ZERO:
		_face(_wander_dir, delta)
	return _wander_dir * move_speed * 0.3


func _face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(delta * 10.0, 1.0))


func _can_see_target() -> bool:
	if _target == null:
		return false
	var eyes := global_position + Vector3(0, 1.6, 0)
	var target_eyes := _target.global_position + Vector3(0, 1.5, 0)
	var query := PhysicsRayQueryParameters3D.create(eyes, target_eyes, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _set_overlay(mat: Material) -> void:
	for child in model.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).material_overlay = mat


func _on_damaged(_amount: int, source_position: Vector3) -> void:
	_flash_time = 0.08
	var push := global_position - source_position
	push.y = 0.0
	if push.length() > 0.01:
		_knockback = push.normalized() * 3.5
	if state == State.IDLE:
		_set_state(State.CHASE)


func _on_died() -> void:
	state = State.DEAD
	remove_from_group("enemies")
	var world := get_tree().current_scene
	Effects.burst(world, global_position + Vector3(0, 0.9, 0), burst_color)
	Effects.sound_at(world, POP_SOUND, global_position)
	queue_free()
