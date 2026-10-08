class_name Scav
extends CharacterBody3D
## Scav: armed scavenger. Wanders until it spots a player (radios it in, then shoots in short bursts).
## Senses: seeing you = knows where you are. Hearing you = walks over to investigate roughly where the sound was.
## Losing sight of you = goes to where it last saw you, searches for a bit, then goes back to wandering.
## No cover or pathfinding yet (see docs/SCAVS_PLAN.md).
## PMCs use this script too (scenes/pmc.tscn) with tougher numbers, until they become real players.

enum State { IDLE, ALERT, ENGAGE, DEAD, INVESTIGATE, SEARCH }

const SHOT_SOUND := preload("res://audio/shot.wav")
const ALERT_SOUND := preload("res://audio/alert.wav")
const POP_SOUND := preload("res://audio/pop.wav")
const FLASH_MATERIAL := preload("res://materials/flash_white.tres")
const STEP_SOUNDS: Array[AudioStream] = [
	preload("res://audio/step1.wav"), preload("res://audio/step2.wav"), preload("res://audio/step3.wav")]

@export_group("Movement")
@export var move_speed := 3.6
@export var sight_range := 40.0
## While unaware, a scav only spots you inside this field of view (degrees); it can still hear you.
## Once alerted it tracks you in any direction.
@export var view_angle_deg := 180.0
## Chasing a player it can't see: gives up on the last-seen spot after this long and starts searching.
@export var give_up_time := 6.0

@export_group("Spotting")
## Seconds a scav needs you in view before it notices you: quick up close, slow far away.
@export var spot_time_near := 0.25
@export var spot_time_far := 1.8
## Crouching or standing still makes you slower to notice; sprinting faster (multipliers on spot time).
@export var spot_crouch_mult := 1.6
@export var spot_still_mult := 1.4
@export var spot_sprint_mult := 0.6
## Already suspicious (investigating/searching) or re-finding someone it was fighting: notices faster.
@export var spot_suspicious_mult := 0.6
@export var spot_reacquire_mult := 0.4
## After losing sight this briefly, it still keeps tracking you (it was just looking at you).
@export var reacquire_grace := 0.3
## A bullet passing this close (meters) gets its attention, even if it's too far to hear the shot.
@export var near_miss_radius := 2.5

@export_group("Hearing")
## How far off a heard sound's spot can be (meters): it investigates *roughly* where the sound came from.
@export var noise_uncertainty := 3.0
## Walks at this fraction of move_speed while investigating.
@export var investigate_speed := 0.6
## Seconds spent looking around at a spot (a sound it investigated, or where it lost you) before giving up.
@export var search_time := 5.0

@export_group("Shooting")
@export var shoot_range := 28.0
## Delay between spotting the player and starting to aim. Gives you a moment to react.
@export var reaction_time := 0.6
@export var aim_time := 0.45
@export var burst_size := 3
@export var burst_interval := 0.13
@export var burst_cooldown_min := 1.0
@export var burst_cooldown_max := 1.8
## Time to kill: 15 = an unarmored player (100 HP) dies in 7 hits (9 with light armor, 12 with heavy).
@export var shot_damage := 15
## Chance each bullet hits, up close vs. at max range.
@export var accuracy_near := 0.7
@export var accuracy_far := 0.2
## Accuracy lost when the player is moving fast (sprinting).
@export var moving_target_penalty := 0.25

@export_group("Flinch")
## Getting shot throws a scav off: it stops firing for a moment and aims worse for a while.
## Mirrors the player's flinch, so whoever lands the first hit has the edge.
@export var flinch_fire_delay := 0.35
@export var flinch_time := 0.8
@export var flinch_accuracy_penalty := 0.4

@export_group("Loot")
@export var min_drops := 1
@export var max_drops := 3
## Loot table in ItemDB.LOOT_TABLES, and the name on the body bag.
@export var loot_table := "scav"
@export var body_name := "Scav Body"

@export_group("Look")
@export var burst_color := Color(0.33, 0.38, 0.24)

@onready var health: Health = $Health
@onready var model: Node3D = $Model
@onready var leg_l: Node3D = $Model/LegL
@onready var leg_r: Node3D = $Model/LegR
@onready var muzzle: Node3D = $Model/Gun/Muzzle
@onready var muzzle_flash: Node3D = $MuzzleFlash

var state := State.IDLE

var _target: Player
## Where the target was last seen (or where a hit came from), and where a heard sound came from.
var _last_seen := Vector3.ZERO
var _goal := Vector3.ZERO
## 0..1: how close it is to noticing you (fills while you're in view, drains when you're not).
var _spot := 0.0
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
## Whether the hit-flash overlay is on right now (so the meshes are only touched when it changes).
var _flashing := false
var _flinch_left := 0.0
var _muzzle_flash_time := 0.0
var _walk_time := 0.0
var _side := 1.0
var _stride_left := 0.0
var _meshes: Array[Node] = []


func _ready() -> void:
	add_to_group("enemies")
	_side = 1.0 if randf() < 0.5 else -1.0
	# The model is an imported .glb, so the flash lives in this scene and moves onto its muzzle here.
	muzzle_flash.reparent(muzzle, false)
	muzzle_flash.visible = false
	_meshes = model.find_children("*", "GeometryInstance3D", true, false)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


## Called via the "enemies" group by anything that makes noise (shots, footsteps, knife, searching).
## Unaware scavs walk over to investigate; scavs already fighting ignore it.
func hear_noise(pos: Vector3, radius: float) -> void:
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH] or global_position.distance_to(pos) > radius:
		return
	var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf() * noise_uncertainty
	_goal = pos + offset
	if state != State.INVESTIGATE:
		_set_state(State.INVESTIGATE)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	_state_time += delta

	if _target == null or not is_instance_valid(_target) or _target.controls_locked():
		_target = _pick_target()

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
			if _spotting(delta, to_target, dist, 1.0):
				_alert(_target.global_position)
		State.INVESTIGATE:
			# Walk over to where the sound was, looking that way.
			var to_goal := _flat(_goal - global_position)
			_face(to_goal, delta)
			desired = _steer(to_goal.normalized() * move_speed * investigate_speed)
			if _spotting(delta, to_target, dist, spot_suspicious_mult):
				_alert(_target.global_position)
			elif to_goal.length() < 1.2 or _state_time > 15.0:
				_set_state(State.SEARCH)
		State.SEARCH:
			# Look around the spot, then go back to wandering.
			rotation.y += delta * 1.2 * _side
			if _spotting(delta, to_target, dist, spot_suspicious_mult):
				_alert(_target.global_position)
			elif _state_time > search_time:
				_set_state(State.IDLE)
		State.ALERT:
			# Turn toward you if it can see you, else toward where it knows you were.
			_face(to_target if _can_see else _flat(_last_seen - global_position), delta)
			if _state_time >= reaction_time:
				_set_state(State.ENGAGE)
				_fire_timer = aim_time
		State.ENGAGE:
			# Keeps tracking you while it can see you; once it has lost you for a moment it has to re-spot you.
			var sees := _can_see and (_lost_sight_time < reacquire_grace or _spotting(delta, to_target, dist, spot_reacquire_mult))
			if dist == INF:
				_set_state(State.IDLE)
			elif sees:
				_last_seen = _target.global_position
				_lost_sight_time = 0.0
				_spot = 0.0
				_face(to_target, delta)
				if dist <= shoot_range:
					desired = _strafe(delta, to_target)
					_update_shooting(delta, dist)
				else:
					desired = _steer(to_target.normalized() * move_speed)
					_hold_fire()
			else:
				# Lost sight: go to where it last saw you (it doesn't know where you went), then search.
				_lost_sight_time += delta
				_hold_fire()
				var to_last := _flat(_last_seen - global_position)
				if to_last.length() < 1.2 or _lost_sight_time > give_up_time:
					_set_state(State.SEARCH)
				else:
					_face(to_last, delta)
					desired = _steer(to_last.normalized() * move_speed)

	_knockback = _knockback.lerp(Vector3.ZERO, minf(delta * 8.0, 1.0))
	velocity.x = desired.x + _knockback.x
	velocity.z = desired.z + _knockback.z
	move_and_slide()
	_update_footsteps(delta)


## Scav footsteps, so you can hear them coming.
func _update_footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or speed < 0.5:
		return
	_stride_left -= speed * delta
	if _stride_left <= 0.0:
		_stride_left = 1.4
		Effects.sound_at(get_tree().current_scene, STEP_SOUNDS.pick_random(), global_position, -6.0, 0.1, 0.9, 2.5)


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
	_flinch_left -= delta
	# Visible jolt: the body snaps back and settles.
	model.rotation.x = -0.3 * maxf(_flinch_left - (flinch_time - 0.25), 0.0) / 0.25
	var flashing := _hit_flash_time > 0.0
	if flashing != _flashing:
		_flashing = flashing
		var overlay: Material = FLASH_MATERIAL if flashing else null
		for mesh in _meshes:
			(mesh as GeometryInstance3D).material_overlay = overlay


## Fills the spot meter while the target is in view (by distance, stance, movement); true once it's noticed.
func _spotting(delta: float, to_target: Vector3, dist: float, mult: float) -> bool:
	if not (_can_see and _in_view(to_target)):
		_spot = maxf(_spot - delta * 0.5, 0.0)
		return false
	var t := lerpf(spot_time_near, spot_time_far, clampf((dist - 5.0) / maxf(sight_range - 5.0, 1.0), 0.0, 1.0))
	if _target.is_crouching:
		t *= spot_crouch_mult
	if _target.is_sprinting():
		t *= spot_sprint_mult
	elif _target.horizontal_speed() < 0.5:
		t *= spot_still_mult
	_spot += delta / maxf(t * mult, 0.01)
	return _spot >= 1.0


## A bullet from `shooter_pos` passed close by: unaware scavs turn toward roughly where it came from.
func notice_near_miss(shooter_pos: Vector3) -> void:
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		return
	# The farther the shooter, the rougher its guess.
	var spread := global_position.distance_to(shooter_pos) * 0.15
	var guess := shooter_pos + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * spread
	_alert(guess)


## Spotted (or got shot by) someone at `known_pos`: radio it in and get ready to fight.
func _alert(known_pos: Vector3) -> void:
	_spot = 0.0
	_last_seen = known_pos
	_set_state(State.ALERT)
	Effects.sound_at(get_tree().current_scene, ALERT_SOUND, global_position, -2.0, 0.05)


## The closest player who can still be fought (co-op ready: never assumes a single player).
func _pick_target() -> Player:
	var best: Player = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Player
		if player == null or player.controls_locked():
			continue
		var d := global_position.distance_to(player.global_position)
		if d < best_dist:
			best = player
			best_dist = d
	return best


## No shot right now: drop the burst and re-aim when a shot comes back.
func _hold_fire() -> void:
	_shots_left = 0
	_fire_timer = maxf(_fire_timer, aim_time)


## Crude wall handling until pathfinding (step 3): slide off to one side when blocked.
func _steer(desired: Vector3) -> Vector3:
	if is_on_wall():
		return desired.rotated(Vector3.UP, PI * 0.4 * _side)
	return desired


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


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
	var chest := _target.global_position + Vector3(0, _target.chest_height(), 0)

	var chance := lerpf(accuracy_near, accuracy_far, clampf(dist / shoot_range, 0.0, 1.0))
	if _target.is_sprinting():
		chance -= moving_target_penalty
	if _flinch_left > 0.0:
		chance -= flinch_accuracy_penalty
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
	# Calm on purpose: changes its mind every few seconds, mostly small turns, and turns slowly
	# (so sneaking up behind one is possible).
	_wander_time -= delta
	if _wander_time <= 0.0:
		_wander_time = randf_range(3.5, 8.0)
		if randf() < 0.5:
			_wander_dir = Vector3.ZERO
		else:
			var facing := -global_basis.z
			_wander_dir = _flat(facing).normalized().rotated(Vector3.UP, randf_range(-1.2, 1.2))
	if _wander_dir != Vector3.ZERO:
		_face(_wander_dir, delta, 2.0)
	return _wander_dir * move_speed * 0.3


func _face(dir: Vector3, delta: float, turn_speed := 10.0) -> void:
	if dir.length_squared() < 0.0001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(delta * turn_speed, 1.0))


func _in_view(to_target: Vector3) -> bool:
	if to_target.length_squared() < 0.0001:
		return true
	var facing := -global_basis.z
	facing.y = 0.0
	return facing.normalized().dot(to_target.normalized()) >= cos(deg_to_rad(view_angle_deg * 0.5))


func _has_line_of_sight() -> bool:
	if _target == null:
		return false
	var eyes := global_position + Vector3(0, 1.65, 0)
	var target_eyes := _target.global_position + Vector3(0, _target.eye_height(), 0)
	var query := PhysicsRayQueryParameters3D.create(eyes, target_eyes, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_damaged(_amount: int, source_position: Vector3) -> void:
	_hit_flash_time = 0.08
	_flinch_left = flinch_time
	_fire_timer = maxf(_fire_timer, flinch_fire_delay)
	var push := global_position - source_position
	push.y = 0.0
	if push.length() > 0.01:
		_knockback = push.normalized() * 3.0
	# Getting shot while unaware: it knows roughly where that came from.
	if state in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		_alert(source_position)


func _on_died() -> void:
	state = State.DEAD
	remove_from_group("enemies")
	var world := get_tree().current_scene
	Effects.burst(world, global_position + Vector3(0, 0.9, 0), burst_color)
	Effects.sound_at(world, POP_SOUND, global_position)
	var drops: Array = []
	for i in randi_range(min_drops, max_drops):
		var id := ItemDB.roll(loot_table)
		drops.append([id, ItemDB.roll_count(id)])
	LootContainer.spawn_bag(world, global_position, body_name, drops, 1.0)
	queue_free()
