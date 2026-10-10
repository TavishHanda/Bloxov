class_name Scav
extends CharacterBody3D
## Scav: armed scavenger. Patrols until it spots a player, then shoots in short bursts.
## Senses: seeing you = knows where you are. Hearing you = walks over to investigate roughly where the sound was.
## Losing sight of you = goes to where it last saw you, searches for a bit, then goes back to wandering.
## Moves along navigation paths (scripts/nav_baker.gd builds the map's walkable area at raid start), so it walks
## around buildings and crates.
## Raiders (the tougher AI faction, scenes/raider.tscn) use this script too, with tougher numbers and the
## "Raider behavior" settings on. (Real PMCs will be players, with multiplayer.)

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
@export var sight_range := 50.0
## While unaware, a scav only spots you inside this field of view (degrees); it can still hear you.
## Once alerted it tracks you in any direction.
@export var view_angle_deg := 180.0
## Chasing a player it can't see: gives up on the last-seen spot after this long and starts searching.
@export var give_up_time := 6.0

@export_group("Patrol")
## Unaware scavs walk between destinations at this fraction of move_speed (0.55 x 3.6 = about 2 m/s),
## pausing this long (seconds) at each one.
@export var patrol_speed := 0.55
@export var patrol_pause_min := 1.0
@export var patrol_pause_max := 3.0
## Like a player: at a loot spot it stops and "searches" the container for a while (it doesn't take anything;
## owner, 0.6.8). While searching it's distracted: slower to notice you.
@export var loot_time_min := 2.0
@export var loot_time_max := 4.0
@export var spot_looting_mult := 1.6
## Chance a patrol leg is a jog instead of a walk, and the jog speed (fraction of move_speed, ~3 m/s).
@export var jog_chance := 0.33
@export var jog_speed := 0.85

@export_group("Spotting")
## Seconds a scav needs you in view before it notices you: quick up close, slow far away.
## (0.12.6, owner: scavs should be pretty aware and spot you fairly easily: 0.25 / 1.2 s before.)
@export var spot_time_near := 0.15
@export var spot_time_far := 0.7
## Crouching or standing still makes you slower to notice; sprinting faster (multipliers on spot time).
@export var spot_crouch_mult := 1.4
@export var spot_still_mult := 1.0
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
## Fires at you from this far; beyond it, it closes in first.
@export var shoot_range := 40.0
## Delay between spotting the player and starting to aim. Gives you a moment to react.
@export var reaction_time := 0.3
## Getting shot (or a bullet whizzing past) while unaware startles it: it turns and starts aiming after only this
## long, so whoever sees first gets the first shots, not a free kill (0.11.16: before, it died before it reacted).
@export var startle_reaction_time := 0.15
@export var aim_time := 0.35
## The longest burst. Each burst is a random length: longer up close, short taps far away (0.12.6, owner: not
## always 3). 1 = single shots (snipers).
@export var burst_size := 3
@export var burst_interval := 0.13
@export var burst_cooldown_min := 1.0
@export var burst_cooldown_max := 1.8
## Time to kill: 15 = an unarmored player (100 HP) dies in 7 hits (9 with light armor, 12 with heavy).
@export var shot_damage := 15
## Chance each bullet hits, up close vs. at accuracy_range and beyond.
@export var accuracy_near := 0.7
@export var accuracy_far := 0.2
@export var accuracy_range := 28.0
## Accuracy lost when the player is moving fast (sprinting).
@export var moving_target_penalty := 0.25
## Point blank (closer than this, meters): shots almost always hit.
@export var point_blank_range := 4.0
@export var point_blank_accuracy := 0.9
## Keeps at least this far from its target: closer and it backs off while shooting.
@export var min_distance := 3.0

@export_group("Cover")
## Fights from cover (0.12.6, owner: a scav ran at him sideways with cover right beside it). In a fight it gets to
## a nearby spot you can't see, holds briefly, peeks out to where it can see you for a burst or two, ducks back,
## and repeats. It also ducks in a lull (this many seconds with no threat).
@export var lull_time := 2.0
@export var cover_search_radius := 12.0
@export var cover_hold_time := 1.2
## At most one new cover spot per this many seconds.
@export var cover_cooldown := 5.0
## Each peek lasts this long (seconds, random), then it ducks back in; after this many peeks it re-thinks
## (a new spot, or chasing you if you've gone).
@export var peek_time_min := 1.5
@export var peek_time_max := 3.0
@export var peeks := 3

@export_group("Teamwork")
## Smarter fights (Scavs 2.0, owner: AI were "too dumb"). When it starts a fight it calls for help: unaware AI
## within this many meters jog over to where the fight is. 0 = never.
@export var help_radius := 35.0
## Spotting you farther away than this, it heads for cover first instead of trading shots in the open.
@export var cover_at_range := 20.0
## While you reload or heal it pushes toward you (this fraction of move_speed) instead of strafing in place.
@export var push_speed := 0.8

@export_group("Raider behavior")
## Off for scavs except flanking (0.12.3, less often than Raiders); raider.tscn turns these on (owner, 0.6.13: harder to fight).
## Hears gunshots from this many times farther away, so it comes toward fights.
@export var hearing_mult := 1.0
## Chance (per lull in a fight) to flank: circle around to hit you from the side instead of trading shots.
@export var flank_chance := 0.0
## Moves quietly (slower, silent footsteps) within this distance of where it thinks you are. 0 = never.
@export var sneak_range := 0.0

@export_group("Sniper")
## Snipers (Scavs 2.0, scenes/sniper.tscn, owner): stays on its perch (within home_radius): never chases, takes
## cover or walks over to a noise; scans the area instead of patrolling.
@export var holds_position := false
## A scope glint you can see from far away when it's looking your way (bright while it aims at you), so you can
## spot it and shoot back (owner: visible, not hidden).
@export var glint := false
## Its shot sound (snipers: deeper, louder and heard farther than a scav's, owner: "different for sure").
@export var shot_pitch := 0.8
@export var shot_volume_db := -3.0
@export var shot_unit_size := 6.0
## What the server tells players' games this is (0 scav, 1 Raider, 2 sniper, 3 boss: which puppet scene to show).
@export var net_kind := 0

@export_group("Healing")
## Badly hurt (below this fraction of max health; scavs 30%, owner 0.6.14), it falls back to cover and patches up (owner: scavs can heal).
## Getting hit while healing interrupts it (and wastes nothing: it can try again a few seconds later).
@export var hurt_fraction := 0.3
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
## Mirrors the player's flinch, so whoever lands the first hit has the edge. Only the first hit of a flinch holds
## its fire (0.11.16): a steady stream of hits used to keep it from ever shooting back.
@export var flinch_fire_delay := 0.35
@export var flinch_time := 0.8
@export var flinch_accuracy_penalty := 0.4

@export_group("Loot")
@export var min_drops := 1
@export var max_drops := 3
## Loot table in ItemDB.LOOT_TABLES, and the name on the body bag.
@export var loot_table := "scav"
@export var body_name := "Scav Body"
## Chance its gun ends up on its body too (in the Primary slot) (owner, 0.11.11: Raiders sometimes drop their AK).
@export_range(0.0, 1.0) var weapon_drop_chance := 0.0
## Always on its body, on top of the rolled loot (Bon, the boss: heavy armor, owner).
@export var extra_drops := PackedStringArray()
## Item id of that gun.
@export var weapon_drop := ""

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
## How long it takes in ALERT before it starts aiming (reaction_time, or startle_reaction_time when shot at).
var _reaction := 0.0
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
enum Cover { NONE, MOVING, HOLDING, HEALING, FLANKING, PEEKING }
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
## Its patrol area (Scavs 2.0, owner: AI stays where players learn to expect it). Set by the spawner from the
## map's AI zones: while unaware it only patrols within `home_radius` meters of `home_center`. 0 = roams the
## whole map (the few random roamers, and every AI on the test map). Fights can still pull it out.
var home_center := Vector3.ZERO
var home_radius := 0.0
## Duo partner or boss guard: who it follows around while patrolling (null = it leads itself), and where it
## walks relative to them (right/back in their facing).
var leader: Scav = null
var follow_offset := Vector3(2.0, 0.0, 1.5)
## > 0 while winding up a bash.
var _windup_left := 0.0
var _lunge_left := 0.0
var _muzzle_flash_time := 0.0
var _walk_time := 0.0
var _side := 1.0
var _stride_left := 0.0
var _meshes: Array[Node] = []

## Online (0.7.8): the AI runs on the server; each player sees a puppet copy that only shows what the server's
## scav does (moved by net_push, no thinking of its own). The server sends net_capture() and these events.
signal fired(end: Vector3)
signal alerted
signal bash_started
const NET_LEAN_IN := 1
const NET_WINDUP := 2
const NET_LUNGE := 4
const NET_SNEAK := 8
const NET_AIM := 16
var puppet := false
## Times it has been hit (sent to puppets so they flash when it goes up).
var hits_taken := 0
## Puppet only: [arrival seconds, state] buffer, drawn RemotePlayer.INTERP_DELAY in the past like other players.
var _net_buffer: Array = []
var _net_flags := 0
var _net_hits := 0


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
	if glint:
		_make_glint()


## Called via the "enemies" group by anything that makes noise (shots, footsteps, knife, searching).
## Unaware scavs walk over to investigate; scavs already fighting ignore it.
func hear_noise(pos: Vector3, radius: float) -> void:
	if puppet:
		return
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH] or global_position.distance_to(pos) > radius * hearing_mult:
		return
	var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf() * noise_uncertainty
	_goal = pos + offset
	if state != State.INVESTIGATE:
		_set_state(State.INVESTIGATE)


func _physics_process(delta: float) -> void:
	if state == State.DEAD or puppet:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	_state_time += delta
	_melee_cooldown_left -= delta
	_since_threat += delta
	_cover_cooldown_left -= delta
	_heal_retry_left -= delta

	if _target == null or not is_instance_valid(_target) or _target.out_of_fight():
		_target = _pick_target()

	var to_target := Vector3.ZERO
	var dist := INF
	if _target != null and not _target.out_of_fight():
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
			desired = _scan(delta) if holds_position else _wander(delta)
			if _spotting(delta, to_target, dist, 1.0):
				_alert(_target.global_position)
		State.INVESTIGATE:
			# Walk over to where the sound was, looking that way.
			if holds_position:   # look toward the noise from the perch
				_face(_flat(_goal - global_position), delta, 3.0)
				if _state_time > 3.0:
					_set_state(State.SEARCH)
			else:
				desired = _path_velocity(_goal, move_speed * (jog_speed if _answering_call else investigate_speed))
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
			if _state_time >= _reaction:
				_set_state(State.ENGAGE)
				_fire_timer = aim_time
				# Seen from far off and out in the open: get to cover first, shooting on the way if it can.
				if not holds_position and dist > cover_at_range and dist < INF and _cover_cooldown_left <= 0.0:
					_try_take_cover()
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
					# You're reloading or healing: push in on you (still shooting); otherwise strafe.
					var pushing := _target_busy() and not holds_position and dist > min_distance + 2.0
					if pushing:
						desired = _path_velocity(_target.global_position, move_speed * push_speed)
					else:
						desired = _clear_of_walls(_strafe(delta, to_target))
					_update_shooting(delta, dist)
					# Out in the open: get to cover and fight from there (between bursts, or right away when
					# hit). Sometimes, in a lull, circle round to flank instead.
					if not pushing and not holds_position and _cover_cooldown_left <= 0.0 and (_shots_left <= 0 or _flinch_left > 0.0):
						if _since_threat > lull_time and randf() < flank_chance:
							_try_flank(to_target, dist)
						else:
							_try_take_cover()
				elif holds_position:   # out of range: keep watching, don't leave the perch
					_hold_fire()
				else:
					desired = _path_velocity(_target.global_position, move_speed)
					_hold_fire()
			else:
				# Lost sight: go to where it last saw you (it doesn't know where you went), then search.
				_lost_sight_time += delta
				_hold_fire()
				if _arrived(_last_seen) or _lost_sight_time > give_up_time:
					_set_state(State.SEARCH)
				elif holds_position:
					_face(_flat(_last_seen - global_position), delta)
				else:
					desired = _path_velocity(_last_seen, move_speed)
					_face(desired, delta)

	if holds_position and home_radius > 0.0 and not _in_home(global_position + desired * delta * 4.0):
		desired = Vector3.ZERO   # the edge of its perch
	if _sneaking():
		desired *= 0.55
	if BoxMap.is_wading(self):   # slower through water, like players (0.11.20)
		desired *= 0.6
	_knockback = _knockback.lerp(Vector3.ZERO, minf(delta * 8.0, 1.0))
	velocity.x = desired.x + _knockback.x
	velocity.z = desired.z + _knockback.z
	move_and_slide()
	_update_footsteps(delta)


## Scav footsteps, so you can hear them coming.
func _update_footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if (not puppet and not is_on_floor()) or speed < 0.5:
		return
	_stride_left -= speed * delta
	if _stride_left <= 0.0:
		_stride_left = 1.4
		if _sneaking() or _net_flags & NET_SNEAK:
			return  # sneaking up: no footstep sounds
		Effects.sound_at(get_tree().current_scene, STEP_SOUNDS.pick_random(), global_position, -6.0, 0.1, 0.9, 2.5)


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	if puppet:
		_puppet_update(delta)
	var speed := Vector2(velocity.x, velocity.z).length()
	_walk_time += delta * speed * 2.5
	var swing := sin(_walk_time) * 0.6 * minf(speed / 2.0, 1.0)
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing

	_muzzle_flash_time -= delta
	muzzle_flash.visible = _muzzle_flash_time > 0.0
	_update_glint()

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
		if puppet:
			_windup_left -= delta
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
	# (No target: everyone left, died or extracted since the last sight check.)
	if _target == null or not (_can_see and _in_view(to_target)):
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
	if puppet:
		return
	_since_threat = 0.0
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		return
	# The farther the shooter, the rougher its guess.
	var spread := global_position.distance_to(shooter_pos) * 0.15
	var guess := shooter_pos + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * spread
	_alert(guess, startle_reaction_time)


## Spotted (or got shot by) someone at `known_pos`: get ready to fight, starting to aim after `reaction` seconds
## (-1 = reaction_time).
func _alert(known_pos: Vector3, reaction := -1.0) -> void:
	# (Ones that came because of a call don't call again, so one fight doesn't pull in the whole map.)
	if state in [State.IDLE, State.INVESTIGATE, State.SEARCH] and not _answering_call:
		_call_for_help(known_pos)
	_reaction = reaction_time if reaction < 0.0 else reaction
	_cover_phase = Cover.NONE
	_spot = 0.0
	_looting_left = 0.0
	_last_seen = known_pos
	_set_state(State.ALERT)
	alerted.emit()
	net_alerted()


## A fight starts: unaware AI nearby (its zone-mates, mostly) come over to help.
func _call_for_help(known_pos: Vector3) -> void:
	if help_radius <= 0.0 or puppet:
		return
	for node in RaidScope.nodes(self, &"enemies"):
		var ally := node as Scav
		if ally != null and ally != self and global_position.distance_to(ally.global_position) <= help_radius:
			ally.answer_call(known_pos)


## Another AI called for help: if unaware, jog over toward where the fight is (not exactly where you are).
func answer_call(pos: Vector3) -> void:
	if puppet or holds_position or state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		return
	_goal = pos + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf() * noise_uncertainty
	_looting_left = 0.0
	_answering_call = true
	_set_state(State.INVESTIGATE)


## The target is reloading or healing (a moment to push).
func _target_busy() -> bool:
	return _target != null and is_instance_valid(_target) and (_target.is_healing() or (_target.gun != null and _target.gun.is_reloading))


## The closest player who can still be fought (co-op ready: never assumes a single player).
func _pick_target() -> Player:
	var best: Player = null
	var best_dist := INF
	for node in RaidScope.nodes(self, &"player"):
		var player := node as Player
		if player == null or player.out_of_fight():
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
		bash_started.emit()
		_hold_fire()
		net_bash_started()
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
	if puppet:
		return
	_since_threat = 0.0


## Looks for a walkable spot nearby that the target can't see; starts moving there if it finds one.
func _try_take_cover() -> void:
	_cover_cooldown_left = cover_cooldown
	var spot := _find_cover()
	if spot != Vector3.INF:
		_cover_point = spot
		_cover_phase = Cover.MOVING
		# Where it stands now can see you: that's where it peeks out from.
		_peek_point = global_position
		_peeks_left = peeks
	else:
		_cover_cooldown_left = 3.0  # nothing nearby: keep fighting, look again soon


## Raiders closing in on where they think you are (investigating, or chasing without seeing you) move quietly.
func _sneaking() -> bool:
	if sneak_range <= 0.0:
		return false
	var spot := Vector3.INF
	if state == State.INVESTIGATE:
		spot = _goal
	elif state == State.ENGAGE and not _can_see and _cover_phase == Cover.NONE:
		spot = _last_seen
	return spot != Vector3.INF and _flat(spot - global_position).length() < sneak_range


## Circle around the target: a reachable spot off to one side at about the same distance (Raiders, scavs since 0.12.3).
func _try_flank(to_target: Vector3, dist: float) -> void:
	_cover_cooldown_left = cover_cooldown
	var side := to_target.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	var target_pos := _target.global_position
	var spot := target_pos - to_target.normalized() * dist * 0.4 + side * dist * 0.8
	spot = AINav.closest(self, spot)
	if spot == Vector3.ZERO:
		return
	_cover_point = spot
	_cover_phase = Cover.FLANKING


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
	var eyes := _target.eye_position()
	var space := get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_walk := INF
	for radius in [3.0, 5.0, cover_search_radius]:
		for i in 12:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 12.0)
			var spot := AINav.closest(self, global_position + dir * radius)
			if spot == Vector3.ZERO or _flat(spot - global_position).length() > radius + 1.0:
				continue
			var query := PhysicsRayQueryParameters3D.create(eyes, spot + Vector3(0, 1.3, 0), 1)
			if space.intersect_ray(query).is_empty():
				continue  # the target could see it there
			# Judge by walking distance: a spot inside a building may be close in a straight line but far around.
			var walk := AINav.path_length(AINav.path(self, global_position, spot))
			if walk <= radius * 1.6 and walk < best_walk:
				best = spot
				best_walk = walk
		if best != Vector3.INF:
			break
	return best


## True if it's not getting anywhere (e.g. the last bit of the path is blocked by another scav).
func _cover_stuck(move: Vector3) -> bool:
	return move.length() < 0.05 or (get_real_velocity().length() < 0.1 and _flat(_cover_point - global_position).length() < 1.2)


## Moving to cover (still shooting if it has a shot), then holding a moment; after that it goes back to the fight
## (if it can't see you from cover, it heads to where it last saw you = peeking out).
func _update_cover(delta: float, sees: bool, to_target: Vector3, dist: float) -> Vector3:
	if _cover_phase == Cover.FLANKING:
		var flank_move := _path_velocity(_cover_point, move_speed)
		if sees and dist <= shoot_range:
			_face(to_target, delta)
			_update_shooting(delta, dist)
		else:
			_face(flank_move, delta)
			_hold_fire()
		if _arrived(_cover_point) or _cover_stuck(flank_move):
			_cover_phase = Cover.NONE
			_lost_sight_time = 0.0
		return flank_move
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
	if _cover_phase == Cover.PEEKING:
		return _update_peek(delta, sees, to_target, dist)
	if _target_busy():
		_cover_hold_left = 0.0   # you're reloading or healing: come out now
	_face(_flat(_last_seen - global_position), delta)
	_hold_fire()
	if _cover_hold_left <= 0.0:
		_lost_sight_time = 0.0
		if _peeks_left > 0 and _peek_point != Vector3.INF and not _target_busy():
			_peeks_left -= 1
			_cover_phase = Cover.PEEKING
			_peek_left = randf_range(peek_time_min, peek_time_max)
			_peek_blind = 0.0
		else:
			_cover_phase = Cover.NONE   # done peeking (or you're reloading): back to the open fight / chase
	return Vector3.ZERO


## Peeking out of cover: step to where it could see you, shoot while it can, then duck back into cover.
## If it gets there and you're gone, it stops hiding and goes after you.
func _update_peek(delta: float, sees: bool, to_target: Vector3, dist: float) -> Vector3:
	var move := Vector3.ZERO
	if not sees:
		move = _path_velocity(_peek_point, move_speed * 0.8)
		_face(_flat(_last_seen - global_position), delta)
		_hold_fire()
		if _arrived(_peek_point) or _cover_stuck(move):
			_peek_blind += delta
			if _peek_blind > 1.0:
				_cover_phase = Cover.NONE   # you moved: find you
				_lost_sight_time = 0.0
		return move
	_peek_blind = 0.0
	_face(to_target, delta)
	if dist <= shoot_range:
		_update_shooting(delta, dist)
	_peek_left -= delta
	# Done (and between bursts), or getting hit: duck back in.
	if (_peek_left <= 0.0 or _flinch_left > 0.0) and _shots_left <= 0:
		_cover_phase = Cover.MOVING
	return move


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
		_path = AINav.path(self, global_position, goal)
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
	if new_state != State.INVESTIGATE:
		_answering_call = false
	state = new_state
	_state_time = 0.0
	_lost_sight_time = 0.0


func _update_shooting(delta: float, dist: float) -> void:
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	if _shots_left <= 0:
		_shots_left = _burst_length(dist)
	_fire_at_target(dist)
	_shots_left -= 1
	if _shots_left > 0:
		_fire_timer = burst_interval
	else:
		_fire_timer = randf_range(burst_cooldown_min, burst_cooldown_max)


## A burst's length: random, longer up close (up to burst_size + 2 inside 10 m), short taps far away.
func _burst_length(dist: float) -> int:
	if burst_size <= 1:
		return 1
	if dist < 10.0:
		return randi_range(burst_size, burst_size + 2)
	if dist < 25.0:
		return randi_range(2, burst_size + 1)
	return randi_range(1, maxi(burst_size - 1, 1))


func _fire_at_target(dist: float) -> void:
	# The bullet's path starts inside the scav's own body (excluded), not the gun barrel: with someone right
	# in its face, a ray from the barrel tip would start past them and miss. Chest height normally; from the
	# eyes when the chest's line is blocked (over a hill crest, a windowsill), since the eyes are what saw them.
	var space := get_world_3d().direct_space_state
	var chest_from := global_position + Vector3(0, 1.3, 0)
	var eyes := global_position + Vector3(0, 1.65, 0)
	var chest := _target.global_position + Vector3(0, _target.chest_height(), 0)
	var head := _target.eye_position() - Vector3(0, 0.1, 0)
	# Peeking around cover (leaning) or over a crest: aim at whatever part of them has a clear line.
	var from := chest_from
	var picked := false
	for option in [[chest_from, chest], [eyes, chest], [eyes, head]]:
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(option[0], option[1], 1, [get_rid()])).is_empty():
			from = option[0]
			chest = option[1]
			picked = true
			break
	if not picked:
		return  # no clear shot (seen over the crest, but every line hits the ground): don't shoot the hill

	var chance := lerpf(accuracy_near, accuracy_far, clampf(dist / accuracy_range, 0.0, 1.0))
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
	var result := space.intersect_ray(query)
	var end := to
	if not result.is_empty():
		end = result.position
		if result.collider == _target:
			_target.health.take_damage(shot_damage, global_position)
		else:
			Effects.impact(get_tree().current_scene, end, result.normal, Color(0.85, 0.8, 0.6))

	fired.emit(end)
	net_fired(end)  # the tracer and sound still come from the gun


func _strafe(delta: float, to_target: Vector3) -> Vector3:
	_strafe_time -= delta
	if _strafe_time <= 0.0:
		_strafe_time = randf_range(0.8, 2.0)
		_strafe_dir = [-1.0, 0.0, 0.0, 1.0].pick_random()
	var side := to_target.normalized().cross(Vector3.UP) * _strafe_dir
	return side * move_speed * 0.5


## Patrolling while unaware: walk to a destination in its area (`home_radius`; the whole map for a roamer), mostly
## loot spots, which are in and around buildings, sometimes anywhere reachable. Pause there, then pick the next one.
## `_wander_dir` is zero while pausing (`_wander_time` counts the pause down).
func _wander(delta: float) -> Vector3:
	# A duo partner sticks with its leader instead of picking its own patrol.
	if leader != null and is_instance_valid(leader) and leader.state != State.DEAD:
		var spot := leader.global_position + leader.global_basis.x * follow_offset.x + leader.global_basis.z * follow_offset.z
		if _flat(spot - global_position).length() < 1.5:
			_wander_dir = Vector3.ZERO
			return Vector3.ZERO
		_wander_dir = _flat(spot - global_position).normalized()
		var follow := _path_velocity(spot, move_speed * (jog_speed if leader._patrol_jog else patrol_speed) * 1.1)
		_face(follow, delta, 4.0)
		return follow
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
	var spots := RaidScope.nodes(self, &"loot_containers")
	if home_radius > 0.0:
		spots = spots.filter(func(c: Node) -> bool: return _in_home((c as Node3D).global_position))
		# Out of its area (after a fight): head straight back in.
		if not _in_home(global_position):
			_patrol_container = null
			var back := AINav.closest(self, home_center)
			if back != Vector3.ZERO:
				return back
	_patrol_jog = randf() < jog_chance
	for attempt in 8:
		var spot: Vector3
		_patrol_container = null
		if not spots.is_empty() and randf() < 0.65:
			_patrol_container = spots.pick_random() as Node3D
			# Walk up next to it (the closest walkable point to the container).
			spot = AINav.closest(self, _patrol_container.global_position)
		elif home_radius > 0.0:
			var offset := Vector3(home_radius * sqrt(randf()), 0, 0).rotated(Vector3.UP, randf() * TAU)
			spot = AINav.closest(self, home_center + offset)
		else:
			spot = AINav.random_point(self)
		if spot != Vector3.ZERO and _flat(spot - global_position).length() > 6.0 and (home_radius <= 0.0 or _in_home(spot)):
			return spot
	# No navigation map yet: somewhere a few meters ahead.
	return global_position + _flat(-global_basis.z).normalized().rotated(Vector3.UP, randf_range(-1.2, 1.2)) * 6.0


## Inside its patrol area (a little slack at the edge); always true for a roamer.
func _in_home(point: Vector3) -> bool:
	return home_radius <= 0.0 or _flat(point - home_center).length() <= home_radius + (0.0 if holds_position else 4.0)


## A sniper on its perch, unaware: slowly sweeps its view one way, then the other, with the odd pause.
func _scan(delta: float) -> Vector3:
	_wander_time -= delta
	if _wander_time <= 0.0:
		_wander_time = randf_range(3.0, 7.0)
		_scan_dir = [-1.0, 0.0, 1.0].pick_random()
	rotation.y += delta * 0.35 * _scan_dir
	return Vector3.ZERO


var _glint: MeshInstance3D = null
var _scan_dir := 1.0
## Fighting from cover: where it peeks out from, how long this peek has left, how many peeks before it re-thinks,
## and how long it's stood at the peek spot without seeing you.
var _peek_point := Vector3.INF
var _peek_left := 0.0
var _peeks_left := 0
var _peek_blind := 0.0
## Heading over because another AI called for help (jogs instead of walking).
var _answering_call := false


## The scope glint: a bright spot by the head that always faces the camera.
func _make_glint() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.98, 0.8, 1.0)
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	# A solid bright core with a soft edge (an additive glow vanished against the bright sky).
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.22, Color(1, 1, 1, 1))
	grad.add_point(0.5, Color(1, 0.8, 0.25, 0.9))
	tex.gradient = grad
	mat.albedo_texture = tex
	quad.material = mat
	_glint = MeshInstance3D.new()
	_glint.mesh = quad
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.position = Vector3(0.12, 1.72, -0.45)
	_glint.visible = false
	add_child(_glint)


## How bright its scope glint looks from `eye` (0 = none): full while it aims your way, a faint flicker as its
## scan sweeps past you, nothing when it faces away or you're right next to it.
func glint_strength(eye: Vector3) -> float:
	if not glint or state == State.DEAD:
		return 0.0
	var to_eye := _flat(eye - global_position)
	if to_eye.length() < 12.0:
		return 0.0
	var facing := _flat(-global_basis.z).normalized()
	var angle := rad_to_deg(facing.angle_to(to_eye.normalized()))
	var aiming := (_net_flags & NET_AIM) != 0 if puppet else state in [State.ALERT, State.ENGAGE]
	if aiming:
		return clampf((40.0 - angle) / 15.0, 0.0, 1.0)
	return clampf((14.0 - angle) / 8.0, 0.0, 1.0) * 0.5


func _update_glint() -> void:
	if _glint == null:
		return
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var strength := glint_strength(camera.global_position) if camera != null else 0.0
	_glint.visible = strength > 0.0
	if _glint.visible:
		# Grows with distance so it still reads as a bright dot far away, and twinkles a little.
		var dist := camera.global_position.distance_to(_glint.global_position)
		var size := clampf(dist * 0.06, 0.8, 8.0) * strength * randf_range(0.8, 1.15)
		_glint.scale = Vector3.ONE * size


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
	hits_taken += 1
	_since_threat = 0.0
	if _cover_phase == Cover.HEALING:
		# Interrupted: back to fighting; it can try again in a few seconds.
		_cover_phase = Cover.NONE
		_wants_heal = true
		_heal_retry_left = 4.0
	elif not health.is_dead and _heals_left > 0 and health.current <= health.max_health * hurt_fraction:
		_wants_heal = true
	_hit_flash_time = 0.08
	if _flinch_left <= 0.0:
		_fire_timer = maxf(_fire_timer, flinch_fire_delay)
	_flinch_left = flinch_time
	var push := global_position - source_position
	push.y = 0.0
	if push.length() > 0.01:
		_knockback = push.normalized() * 3.0
	# Getting shot while unaware: it knows roughly where that came from.
	if state in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		_alert(source_position, startle_reaction_time)


func _on_died() -> void:
	state = State.DEAD
	remove_from_group("enemies")
	var world := get_tree().current_scene
	Effects.burst(world, global_position + Vector3(0, 0.9, 0), burst_color)
	Effects.sound_at(world, POP_SOUND, global_position)
	if puppet:
		queue_free()  # its body (and loot) is the server's
		return
	var drops: Array = []
	if weapon_drop != "" and randf() < weapon_drop_chance:
		drops.append([weapon_drop, 1])
	for id in extra_drops:
		drops.append([id, 1])
	for i in randi_range(min_drops, max_drops):
		var id := ItemDB.roll(loot_table)
		drops.append([id, ItemDB.roll_count(id)])
	# Into the raid it died in (on the server, that's one of several raids, and there's no current scene).
	LootContainer.spawn_bag(get_parent(), global_position, body_name, drops, 1.0, true)
	queue_free()


# --- Online ------------------------------------------------------------------------

## What puppets need to show this scav: [position, yaw, flags, hits_taken].
func net_capture() -> Array:
	var flags := 0
	if (_looting_left > 0.0 and state == State.IDLE) or _cover_phase == Cover.HEALING:
		flags |= NET_LEAN_IN
	if _windup_left > 0.0:
		flags |= NET_WINDUP
	if _lunge_left > 0.0:
		flags |= NET_LUNGE
	if _sneaking():
		flags |= NET_SNEAK
	if state in [State.ALERT, State.ENGAGE]:
		flags |= NET_AIM
	return [global_position, rotation.y, flags, hits_taken]


## Puppet: a new state from the server (`at` = arrival time in seconds).
func net_push(net_state: Array, at := -1.0) -> void:
	if at < 0.0:
		at = Time.get_ticks_msec() / 1000.0
	if _net_buffer.is_empty():
		global_position = net_state[0]
		rotation.y = net_state[1]
		_net_hits = net_state[3]
	_net_buffer.append([at, net_state])
	if _net_buffer.size() > 20:
		_net_buffer.pop_front()


## Tracer, sound and flash from the gun for a shot ending at `end` (puppets: one the server's scav fired).
func net_fired(end: Vector3) -> void:
	var muzzle_pos := muzzle.global_position
	Effects.tracer(get_tree().current_scene, muzzle_pos, end)
	Effects.sound_at(get_tree().current_scene, SHOT_SOUND, muzzle_pos, shot_volume_db, 0.06, shot_pitch, shot_unit_size)
	_muzzle_flash_time = 0.05


## Puppet: the server's scav died (pop into voxels, like offline; its body bag comes from the server).
func net_died() -> void:
	if state != State.DEAD:
		_on_died()


## Alert sound (puppets: the server's scav spotted someone).
func net_alerted() -> void:
	Effects.sound_at(get_tree().current_scene, ALERT_SOUND, global_position, -2.0, 0.05)


## Bash wind-up sound (puppets: the server's scav started one).
func net_bash_started() -> void:
	Effects.sound_at(get_tree().current_scene, BASH_SOUND, global_position, -4.0, 0.1, 0.8)


func _puppet_update(delta: float) -> void:
	if _net_buffer.is_empty():
		return
	var time := Time.get_ticks_msec() / 1000.0 - RemotePlayer.INTERP_DELAY
	while _net_buffer.size() > 2 and _net_buffer[1][0] <= time:
		_net_buffer.pop_front()
	var a: Array = _net_buffer[0]
	var b: Array = _net_buffer[1] if _net_buffer.size() > 1 else a
	var t := 1.0 if b[0] <= a[0] else clampf((time - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	var old := global_position
	global_position = (a[1][0] as Vector3).lerp(b[1][0], t)
	rotation.y = lerp_angle(a[1][1], b[1][1], t)
	velocity = (global_position - old) / maxf(delta, 0.001)
	var flags: int = b[1][2]
	# Rising edges start the same animations the server's scav is playing.
	if flags & NET_WINDUP and not _net_flags & NET_WINDUP:
		_windup_left = melee_windup
	if flags & NET_LUNGE and not _net_flags & NET_LUNGE:
		_lunge_left = 0.15
	if not flags & NET_WINDUP:
		_windup_left = 0.0
	_net_flags = flags
	_looting_left = 1.0 if flags & NET_LEAN_IN else 0.0
	if b[1][3] > _net_hits:
		_net_hits = b[1][3]
		_hit_flash_time = 0.08
		_flinch_left = flinch_time
	_update_footsteps(delta)
