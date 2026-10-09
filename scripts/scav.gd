class_name Scav
extends CharacterBody3D
## Scav: armed scavenger. Wanders until it spots a player (radios it in, then shoots in short bursts).
## Senses: seeing you = knows where you are. Hearing you = walks over to investigate roughly where the sound was.
## Losing sight of you = goes to where it last saw you, searches for a bit, then goes back to wandering.
## Moves along navigation paths (scripts/nav_baker.gd builds the map's walkable area at raid start), so it walks
## around buildings and crates. No cover yet (see docs/SCAVS_PLAN.md).
## PMCs use this script too (scenes/pmc.tscn) with tougher numbers, until they become real players.

enum State { IDLE, ALERT, ENGAGE, DEAD, INVESTIGATE, SEARCH }

const SHOT_SOUND := preload("res://audio/shot.wav")
const ALERT_SOUND := preload("res://audio/alert.wav")
const POP_SOUND := preload("res://audio/pop.wav")
const BASH_SOUND := preload("res://audio/swing.wav")
const HEAL_SOUND := preload("res://audio/mag_out.wav")
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

@export_group("Patrol")
## Unaware scavs walk between destinations at this fraction of move_speed (0.55 x 3.6 = about 2 m/s),
## pausing this long (seconds) at each one.
@export var patrol_speed := 0.55
@export var patrol_pause_min := 2.0
@export var patrol_pause_max := 6.0
## Like a player: at a loot spot it stops and "searches" the container for a while (it doesn't take anything;
## owner, 0.6.8). While searching it's distracted: slower to notice you.
@export var loot_time_min := 3.0
@export var loot_time_max := 6.0
@export var spot_looting_mult := 1.6
## Chance a patrol leg is a jog instead of a walk, and the jog speed (fraction of move_speed, ~3 m/s).
@export var jog_chance := 0.33
@export var jog_speed := 0.85

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
## Point blank (closer than this, meters): shots almost always hit.
@export var point_blank_range := 4.0
@export var point_blank_accuracy := 0.9
## Keeps at least this far from its target: closer and it backs off while shooting.
@export var min_distance := 3.0

@export_group("Cover")
## Fighting comes first (owner, 0.6.9). Cover is for breaks: after this many seconds with no threat (you haven't
## fired, hit it, or sent a bullet past it) it moves to a nearby spot you can't see, holds briefly, then peeks out.
@export var lull_time := 2.0
@export var cover_search_radius := 7.0
@export var cover_hold_time := 1.5
## At most one move to cover per this many seconds.
@export var cover_cooldown := 10.0

@export_group("Healing")
## Badly hurt (below this fraction of max health), it falls back to cover and patches up (owner: scavs can heal).
## Getting hit while healing interrupts it (and wastes nothing: it can try again a few seconds later).
@export var hurt_fraction := 0.4
@export var heal_amount := 40
@export var heal_time := 4.0
## How many times per life it can heal.
@export var heals := 1

@export_group("Melee")
## Get this close (meters) and it bashes you with its rifle butt instead of shooting.
@export var melee_range := 1.6
@export var melee_damage := 20
## Visible wind-up before the bash lands (you can react), then a cooldown before the next one.
@export var melee_windup := 0.3
@export var melee_cooldown := 1.5
## How hard the bash shoves you (m/s), and how long you can't aim down sights after it.
@export var melee_shove := 6.0
@export var melee_aim_block := 0.6

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
## Current navigation path (to _path_goal) and the waypoint it's walking to.
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF
var _repath_left := 0.0
## Where an idle scav is patrolling to (only used while _wander_dir isn't zero), and for how long.
var _wander_point := Vector3.ZERO
var _patrol_time := 0.0
## The loot container this patrol leg heads to (null = just a spot), whether it's jogging, and how long it
## has left searching a container.
var _patrol_container: Node3D = null
var _patrol_jog := false
var _looting_left := 0.0
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
var _melee_cooldown_left := 0.0
## Cover: seconds since the last threat, where it's heading/holding, and the cooldown.
enum Cover { NONE, MOVING, HOLDING, HEALING }
var _since_threat := 0.0
var _cover_phase := Cover.NONE
var _cover_point := Vector3.ZERO
var _cover_hold_left := 0.0
var _cover_cooldown_left := 0.0
## Heals left this life, whether it's hurt and wants to fall back, and time left on the current heal.
var _heals_left := 0
var _wants_heal := false
var _heal_left := 0.0
var _heal_retry_left := 0.0
var _heal_after_move := false
## > 0 while winding up a bash.
var _windup_left := 0.0
var _lunge_left := 0.0
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
	_heals_left = heals


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
	_melee_cooldown_left -= delta
	_since_threat += delta
	_cover_cooldown_left -= delta
	_heal_retry_left -= delta

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
			desired = _path_velocity(_goal, move_speed * investigate_speed)
			_face(desired, delta)
			if _spotting(delta, to_target, dist, spot_suspicious_mult):
				_alert(_target.global_position)
			elif _arrived(_goal) or _state_time > 15.0:
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
			elif _cover_phase != Cover.NONE:
				desired = _update_cover(delta, sees, to_target, dist)
			elif _wants_heal and _heal_retry_left <= 0.0:
				_fall_back_to_heal()
			elif sees:
				_last_seen = _target.global_position
				_lost_sight_time = 0.0
				_spot = 0.0
				_face(to_target, delta)
				if _windup_left > 0.0 or (dist < melee_range and _melee_cooldown_left <= 0.0):
					_update_melee(delta, dist)
				elif dist < min_distance:
					# Too close: back off (with a bit of sideways movement) while shooting.
					desired = _clear_of_walls(-to_target.normalized() * move_speed * 0.7 + _strafe(delta, to_target) * 0.5)
					_update_shooting(delta, dist)
				elif dist <= shoot_range:
					desired = _clear_of_walls(_strafe(delta, to_target))
					_update_shooting(delta, dist)
					# A break in the fight (between its bursts, nothing coming its way): reposition to cover.
					if _since_threat > lull_time and _cover_cooldown_left <= 0.0 and _shots_left <= 0:
						_try_take_cover()
				else:
					desired = _path_velocity(_target.global_position, move_speed)
					_hold_fire()
			else:
				# Lost sight: go to where it last saw you (it doesn't know where you went), then search.
				_lost_sight_time += delta
				_hold_fire()
				if _arrived(_last_seen) or _lost_sight_time > give_up_time:
					_set_state(State.SEARCH)
				else:
					desired = _path_velocity(_last_seen, move_speed)
					_face(desired, delta)

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
	_lunge_left -= delta
	# Visible jolt when hit: the body snaps back and settles. Bash: leans back to wind up, then lunges.
	# (The model faces -Z, so a positive X rotation tips it backward and a negative one forward.)
	var tilt := 0.3 * maxf(_flinch_left - (flinch_time - 0.25), 0.0) / 0.25
	if (_looting_left > 0.0 and state == State.IDLE) or _cover_phase == Cover.HEALING:
		tilt -= 0.35  # leaning in: searching a container, or patching itself up
	if _windup_left > 0.0:
		tilt += 0.35 * (1.0 - _windup_left / melee_windup)
	elif _lunge_left > 0.0:
		tilt -= 0.4
	model.rotation.x = tilt
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
	if _looting_left > 0.0:
		t *= spot_looting_mult
	if _target.is_sprinting():
		t *= spot_sprint_mult
	elif _target.horizontal_speed() < 0.5:
		t *= spot_still_mult
	_spot += delta / maxf(t * mult, 0.01)
	return _spot >= 1.0


## A bullet from `shooter_pos` passed close by: unaware scavs turn toward roughly where it came from.
func notice_near_miss(shooter_pos: Vector3) -> void:
	_since_threat = 0.0
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		return
	# The farther the shooter, the rougher its guess.
	var spread := global_position.distance_to(shooter_pos) * 0.15
	var guess := shooter_pos + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * spread
	_alert(guess)


## Spotted (or got shot by) someone at `known_pos`: radio it in and get ready to fight.
func _alert(known_pos: Vector3) -> void:
	_cover_phase = Cover.NONE
	_spot = 0.0
	_looting_left = 0.0
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


## Rifle-butt bash: wind up (visible), then hit if the target is still in reach.
func _update_melee(delta: float, dist: float) -> void:
	if _windup_left <= 0.0:
		_windup_left = melee_windup
		_hold_fire()
		Effects.sound_at(get_tree().current_scene, BASH_SOUND, global_position, -4.0, 0.1, 0.8)
		return
	_windup_left -= delta
	if _windup_left > 0.0:
		return
	_melee_cooldown_left = melee_cooldown
	_lunge_left = 0.15
	if dist <= melee_range + 0.5:
		_target.take_bash(melee_damage, global_position, melee_shove, melee_aim_block)


## Something threatened it (a shot fired, a hit, a near miss): no break in the fight right now.
func notice_threat() -> void:
	_since_threat = 0.0


## Looks for a walkable spot nearby that the target can't see; starts moving there if it finds one.
func _try_take_cover() -> void:
	_cover_cooldown_left = cover_cooldown
	var spot := _find_cover()
	if spot != Vector3.INF:
		_cover_point = spot
		_cover_phase = Cover.MOVING
	else:
		_cover_cooldown_left = 3.0  # nothing nearby: keep fighting, look again soon


## Hurt: get to cover (or patch up where it stands if there's none) and heal.
func _fall_back_to_heal() -> void:
	_wants_heal = false
	var spot := _find_cover()
	if spot != Vector3.INF:
		_cover_point = spot
		_cover_phase = Cover.MOVING
		_heal_after_move = true
	else:
		_start_heal()


func _start_heal() -> void:
	_cover_phase = Cover.HEALING
	_heal_left = heal_time
	_hold_fire()
	Effects.sound_at(get_tree().current_scene, HEAL_SOUND, global_position, -6.0, 0.1)


## The closest walkable spot within cover_search_radius (by walking distance) the target can't see; INF if none.
func _find_cover() -> Vector3:
	var map := get_world_3d().navigation_map
	var eyes := _target.eye_position()
	var space := get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_walk := INF
	for radius in [3.0, 5.0, cover_search_radius]:
		for i in 12:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 12.0)
			var spot := NavigationServer3D.map_get_closest_point(map, global_position + dir * radius)
			if spot == Vector3.ZERO or _flat(spot - global_position).length() > radius + 1.0:
				continue
			var query := PhysicsRayQueryParameters3D.create(eyes, spot + Vector3(0, 1.3, 0), 1)
			if space.intersect_ray(query).is_empty():
				continue  # the target could see it there
			# Judge by walking distance: a spot inside a building may be close in a straight line but far around.
			var walk := _path_length(NavigationServer3D.map_get_path(map, global_position, spot, true))
			if walk <= radius * 1.6 and walk < best_walk:
				best = spot
				best_walk = walk
		if best != Vector3.INF:
			break
	return best


## True if it's not getting anywhere (e.g. the last bit of the path is blocked by another scav).
func _cover_stuck(move: Vector3) -> bool:
	return move.length() < 0.05 or (get_real_velocity().length() < 0.1 and _flat(_cover_point - global_position).length() < 1.2)


func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total if path.size() > 1 else INF


## Moving to cover (still shooting if it has a shot), then holding a moment; after that it goes back to the fight
## (if it can't see you from cover, it heads to where it last saw you = peeking out).
func _update_cover(delta: float, sees: bool, to_target: Vector3, dist: float) -> Vector3:
	if _cover_phase == Cover.MOVING:
		var move := _path_velocity(_cover_point, move_speed)
		if sees and dist <= shoot_range:
			_face(to_target, delta)
			_update_shooting(delta, dist)
		else:
			_face(move, delta)
			_hold_fire()
		# Get all the way in (normal arriving allows 1.2 m, which can leave it peeking past the corner).
		if _flat(_cover_point - global_position).length() < 0.4 or _cover_stuck(move):
			if _heal_after_move:
				_heal_after_move = false
				_start_heal()
			else:
				_cover_phase = Cover.HOLDING
				_cover_hold_left = cover_hold_time
		return move
	if _cover_phase == Cover.HEALING:
		_heal_left -= delta
		_face(_flat(_last_seen - global_position), delta)
		_hold_fire()
		if _heal_left <= 0.0:
			health.heal(heal_amount)
			_heals_left -= 1
			_cover_phase = Cover.NONE
			_lost_sight_time = 0.0
		return Vector3.ZERO
	_cover_hold_left -= delta
	_face(_flat(_last_seen - global_position), delta)
	_hold_fire()
	if _cover_hold_left <= 0.0:
		_cover_phase = Cover.NONE
		_lost_sight_time = 0.0
	return Vector3.ZERO


## No shot right now: drop the burst and re-aim when a shot comes back.
func _hold_fire() -> void:
	_shots_left = 0
	_fire_timer = maxf(_fire_timer, aim_time)


## Velocity toward `goal` along a navigation path (around buildings and crates). Re-paths when the goal moves
## more than a meter or every second. If the goal can't be reached, the path ends at the closest point it can.
## Without a navigation map (e.g. before it's built) it walks straight, sliding off walls.
func _path_velocity(goal: Vector3, speed: float) -> Vector3:
	_repath_left -= get_physics_process_delta_time()
	if _path.is_empty() or _flat(goal - _path_goal).length() > 1.0 or _repath_left <= 0.0:
		_path_goal = goal
		_repath_left = 1.0
		_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, goal, true)
		_path_index = 1
	if _path.size() < 2:
		var direct := _flat(goal - global_position)
		if direct.length() < 0.1:
			return Vector3.ZERO
		var straight := direct.normalized() * speed
		return straight.rotated(Vector3.UP, PI * 0.4 * _side) if is_on_wall() else straight
	while _path_index < _path.size() - 1 and _flat(_path[_path_index] - global_position).length() < 0.6:
		_path_index += 1
	var to_next := _flat(_path[_path_index] - global_position)
	if to_next.length() < 0.1:
		return Vector3.ZERO
	return to_next.normalized() * speed


## Reached `goal` (or the closest reachable point to it, if the path ended short).
func _arrived(goal: Vector3) -> bool:
	if _flat(goal - global_position).length() < 1.2:
		return true
	return (not _path.is_empty() and _flat(goal - _path_goal).length() <= 1.0
		and _flat(_path[_path.size() - 1] - global_position).length() < 1.2)


## Short fight moves (strafing, backing off): don't push into a wall; try the other side instead.
func _clear_of_walls(move: Vector3) -> Vector3:
	if move.length() < 0.1 or not _blocked(move):
		return move
	_strafe_dir = -_strafe_dir
	var flipped := Vector3(-move.x, 0.0, -move.z)
	return Vector3.ZERO if _blocked(flipped) else flipped


func _blocked(move: Vector3) -> bool:
	var from := global_position + Vector3(0, 0.6, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + move.normalized() * 1.0, 1, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


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
	var muzzle_pos := muzzle.global_position
	# The bullet's path starts at the scav's own chest (its body is excluded), not the gun barrel:
	# with someone right in its face, a ray from the barrel tip would start past them and miss.
	var from := global_position + Vector3(0, 1.3, 0)
	var chest := _target.global_position + Vector3(0, _target.chest_height(), 0)
	# Peeking around cover (leaning): if the chest is hidden, aim at the head it can see.
	var cover_check := PhysicsRayQueryParameters3D.create(from, chest, 1, [get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(cover_check).is_empty():
		chest = _target.eye_position() - Vector3(0, 0.1, 0)

	var chance := lerpf(accuracy_near, accuracy_far, clampf(dist / shoot_range, 0.0, 1.0))
	if dist < point_blank_range:
		chance = maxf(chance, point_blank_accuracy)
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
	query.hit_from_inside = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var end := to
	if not result.is_empty():
		end = result.position
		if result.collider == _target:
			_target.health.take_damage(shot_damage, global_position)
		else:
			Effects.impact(world, end, result.normal, Color(0.85, 0.8, 0.6))

	# The tracer and sound still come from the gun.
	Effects.tracer(world, muzzle_pos, end)
	Effects.sound_at(world, SHOT_SOUND, muzzle_pos, -3.0, 0.06, 0.8)
	_muzzle_flash_time = 0.05


func _strafe(delta: float, to_target: Vector3) -> Vector3:
	_strafe_time -= delta
	if _strafe_time <= 0.0:
		_strafe_time = randf_range(0.8, 2.0)
		_strafe_dir = [-1.0, 0.0, 0.0, 1.0].pick_random()
	var side := to_target.normalized().cross(Vector3.UP) * _strafe_dir
	return side * move_speed * 0.5


## Patrolling while unaware: walk to a destination across the map (mostly loot spots, which are in and around
## buildings, sometimes anywhere reachable), pause there for a few seconds, then pick the next one.
## `_wander_dir` is zero while pausing (`_wander_time` counts the pause down).
func _wander(delta: float) -> Vector3:
	if _wander_dir == Vector3.ZERO:
		_wander_time -= delta
		_looting_left -= delta
		if _looting_left > 0.0 and is_instance_valid(_patrol_container):
			_face(_flat(_patrol_container.global_position - global_position), delta, 4.0)
		if _wander_time > 0.0:
			return Vector3.ZERO
		_wander_point = _pick_patrol_point()
		_wander_dir = _flat(_wander_point - global_position).normalized()
		_patrol_time = 0.0
		if _wander_dir == Vector3.ZERO:
			_wander_time = 1.0
		return Vector3.ZERO
	_patrol_time += delta
	if _arrived(_wander_point) or _patrol_time > 45.0:
		_wander_dir = Vector3.ZERO
		if is_instance_valid(_patrol_container) and _flat(_patrol_container.global_position - global_position).length() < 3.5:
			# At a container: search it for a while, like a player would.
			_looting_left = randf_range(loot_time_min, loot_time_max)
			_wander_time = _looting_left + 0.5
		else:
			_wander_time = randf_range(patrol_pause_min, patrol_pause_max)
		return Vector3.ZERO
	var move := _path_velocity(_wander_point, move_speed * (jog_speed if _patrol_jog else patrol_speed))
	_face(move, delta, 4.0)
	return move


func _pick_patrol_point() -> Vector3:
	var map := get_world_3d().navigation_map
	var spots := get_tree().get_nodes_in_group("loot_containers")
	_patrol_jog = randf() < jog_chance
	for attempt in 6:
		var spot: Vector3
		_patrol_container = null
		if not spots.is_empty() and randf() < 0.65:
			_patrol_container = spots.pick_random() as Node3D
			# Walk up next to it (the closest walkable point to the container).
			spot = NavigationServer3D.map_get_closest_point(map, _patrol_container.global_position)
		else:
			spot = NavigationServer3D.map_get_random_point(map, 1, false)
		if spot != Vector3.ZERO and _flat(spot - global_position).length() > 6.0:
			return spot
	# No navigation map yet: somewhere a few meters ahead.
	return global_position + _flat(-global_basis.z).normalized().rotated(Vector3.UP, randf_range(-1.2, 1.2)) * 6.0


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
	var query := PhysicsRayQueryParameters3D.create(eyes, _target.eye_position(), 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_damaged(_amount: int, source_position: Vector3) -> void:
	_since_threat = 0.0
	if _cover_phase == Cover.HEALING:
		# Interrupted: back to fighting; it can try again in a few seconds.
		_cover_phase = Cover.NONE
		_wants_heal = true
		_heal_retry_left = 4.0
	elif not health.is_dead and _heals_left > 0 and health.current <= health.max_health * hurt_fraction:
		_wants_heal = true
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
