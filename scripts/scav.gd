class_name Scav
extends CharacterBody3D
## Scav: armed scavenger. Wanders until it spots (or hears) the player, radios it in,
## then shoots in short bursts. Closes distance when it can't get a shot.
## Dumb on purpose: no cover or pathfinding yet (that's Phase 4).

enum State { IDLE, ALERT, ENGAGE, DEAD }

const SHOT_SOUND := preload("res://audio/shot.wav")
const ALERT_SOUND := preload("res://audio/alert.wav")
const POP_SOUND := preload("res://audio/pop.wav")
const FLASH_MATERIAL := preload("res://materials/flash_white.tres")

@export_group("Movement")
@export var move_speed := 3.6
@export var sight_range := 40.0
## Seconds without seeing the player before giving up.
@export var give_up_time := 6.0

@export_group("Shooting")
@export var shoot_range := 28.0
## Delay between spotting the player and starting to aim. Gives you a moment to react.
@export var reaction_time := 0.6
@export var aim_time := 0.45
@export var burst_size := 3
@export var burst_interval := 0.13
@export var burst_cooldown_min := 1.0
@export var burst_cooldown_max := 1.8
@export var shot_damage := 8
## Chance each bullet hits, up close vs. at max range.
@export var accuracy_near := 0.85
@export var accuracy_far := 0.25
## Accuracy lost when the player is moving fast (sprinting).
@export var moving_target_penalty := 0.25

@export_group("Loot")
@export var min_drops := 1
@export var max_drops := 3

@export_group("Look")
@export var burst_color := Color(0.33, 0.38, 0.24)

@onready var health: Health = $Health
@onready var model: Node3D = $Model
@onready var leg_l: Node3D = $Model/LegL
@onready var leg_r: Node3D = $Model/LegR
@onready var muzzle: Marker3D = $Model/Gun/Muzzle
@onready var muzzle_flash: Node3D = $Model/Gun/Muzzle/Flash

var state := State.IDLE

var _target: Player
var _state_time := 0.0
var _lost_sight_time := 0.0
var _can_see := false
var _sight_check_time := 0.0
var _fire_timer := 0.0
var _shots_left := 0
var _knockback := Vector3.ZERO
var _wander_dir := Vector3.ZERO
var _wander_time := 0.0
var _strafe_dir := 0.0
var _strafe_time := 0.0
var _hit_flash_time := 0.0
var _muzzle_flash_time := 0.0
var _walk_time := 0.0
var _side := 1.0


func _ready() -> void:
	add_to_group("enemies")
	_side = 1.0 if randf() < 0.5 else -1.0
	muzzle_flash.visible = false
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


## Called by the player's gun (via the "enemies" group) on every shot.
func hear_noise(pos: Vector3, radius: float) -> void:
	if state == State.IDLE and global_position.distance_to(pos) <= radius:
		_alert()


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
	if _target != null and not _target.controls_locked():
		to_target = _target.global_position - global_position
		to_target.y = 0.0
		dist = to_target.length()

	_sight_check_time -= delta
	if _sight_check_time <= 0.0:
		_sight_check_time = 0.1
		_can_see = dist < sight_range and _has_line_of_sight()

	var desired := Vector3.ZERO
	match state:
		State.IDLE:
			desired = _wander(delta)
			if _can_see:
				_alert()
		State.ALERT:
			_face(to_target, delta)
			if _state_time >= reaction_time:
				_set_state(State.ENGAGE)
				_fire_timer = aim_time
		State.ENGAGE:
			if dist == INF:
				_set_state(State.IDLE)
			else:
				_face(to_target, delta)
				_lost_sight_time = 0.0 if _can_see else _lost_sight_time + delta
				if _lost_sight_time > give_up_time:
					_set_state(State.IDLE)
				elif _can_see and dist <= shoot_range:
					desired = _strafe(delta, to_target)
					_update_shooting(delta, dist)
				else:
					# No shot: move in. Re-aim when we get one.
					desired = to_target.normalized() * move_speed
					if is_on_wall():
						desired = desired.rotated(Vector3.UP, PI * 0.4 * _side)
					_shots_left = 0
					_fire_timer = maxf(_fire_timer, aim_time)

	_knockback = _knockback.lerp(Vector3.ZERO, minf(delta * 8.0, 1.0))
	velocity.x = desired.x + _knockback.x
	velocity.z = desired.z + _knockback.z
	move_and_slide()


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	_walk_time += delta * speed * 2.5
	var swing := sin(_walk_time) * 0.6 * minf(speed / 2.0, 1.0)
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing

	_muzzle_flash_time -= delta
	muzzle_flash.visible = _muzzle_flash_time > 0.0

	_hit_flash_time -= delta
	var overlay: Material = FLASH_MATERIAL if _hit_flash_time > 0.0 else null
	for child in model.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).material_overlay = overlay


func _alert() -> void:
	_set_state(State.ALERT)
	Effects.sound_at(get_tree().current_scene, ALERT_SOUND, global_position, -2.0, 0.05)


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_lost_sight_time = 0.0


func _update_shooting(delta: float, dist: float) -> void:
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	if _shots_left <= 0:
		_shots_left = burst_size
	_fire_at_target(dist)
	_shots_left -= 1
	if _shots_left > 0:
		_fire_timer = burst_interval
	else:
		_fire_timer = randf_range(burst_cooldown_min, burst_cooldown_max)


func _fire_at_target(dist: float) -> void:
	var world := get_tree().current_scene
	var from := muzzle.global_position
	var chest := _target.global_position + Vector3(0, 1.2, 0)

	var chance := lerpf(accuracy_near, accuracy_far, clampf(dist / shoot_range, 0.0, 1.0))
	if _target.is_sprinting():
		chance -= moving_target_penalty
	var hit := randf() < chance

	var aim_point := chest
	if not hit:
		# Miss close enough that you see and hear it go by.
		var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.8), randf_range(-1.0, 1.0))
		aim_point = chest + offset.normalized() * randf_range(0.7, 1.5)

	var dir := (aim_point - from).normalized()
	var to := from + dir * (shoot_range + 20.0)
	# Missed shots ignore the player's hitbox so a "miss" can't land by accident.
	var mask := (1 | 2) if hit else 1
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var end := to
	if not result.is_empty():
		end = result.position
		if result.collider == _target:
			_target.health.take_damage(shot_damage, global_position)
		else:
			Effects.impact(world, end, result.normal, Color(0.85, 0.8, 0.6))

	Effects.tracer(world, from, end)
	Effects.sound_at(world, SHOT_SOUND, from, -3.0, 0.06, 0.8)
	_muzzle_flash_time = 0.05


func _strafe(delta: float, to_target: Vector3) -> Vector3:
	_strafe_time -= delta
	if _strafe_time <= 0.0:
		_strafe_time = randf_range(0.8, 2.0)
		_strafe_dir = [-1.0, 0.0, 0.0, 1.0].pick_random()
	var side := to_target.normalized().cross(Vector3.UP) * _strafe_dir
	return side * move_speed * 0.5


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


func _has_line_of_sight() -> bool:
	if _target == null:
		return false
	var eyes := global_position + Vector3(0, 1.65, 0)
	var target_eyes := _target.global_position + Vector3(0, 1.5, 0)
	var query := PhysicsRayQueryParameters3D.create(eyes, target_eyes, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_damaged(_amount: int, source_position: Vector3) -> void:
	_hit_flash_time = 0.08
	var push := global_position - source_position
	push.y = 0.0
	if push.length() > 0.01:
		_knockback = push.normalized() * 3.0
	if state == State.IDLE:
		_alert()


func _on_died() -> void:
	state = State.DEAD
	remove_from_group("enemies")
	var world := get_tree().current_scene
	Effects.burst(world, global_position + Vector3(0, 0.9, 0), burst_color)
	Effects.sound_at(world, POP_SOUND, global_position)
	var drops: Array[String] = []
	for i in randi_range(min_drops, max_drops):
		drops.append(ItemDB.roll("scav"))
	LootContainer.spawn_bag(world, global_position, "Scav Body", drops, 1.0)
	queue_free()
