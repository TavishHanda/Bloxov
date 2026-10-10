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
## How far away you can hear an AI's footsteps and its callouts (0.12.32, owner: you could hear every AI on the map
## walking, "like 30 crunching steps"). Gunshots still carry across the map.
const STEP_HEAR_RANGE := 30.0
const BARK_HEAR_RANGE := 50.0
const BASH_SOUND := preload("res://audio/swing.wav")
const HEAL_SOUND := preload("res://audio/mag_out.wav")
const FLASH_MATERIAL := preload("res://materials/flash_white.tres")
## Callouts (0.12.12; 0.12.27, owner: cartoony gibberish, no real voice lines): barks from tools/gen_voice_placeholders.py,
## 3 takes per kind (audio/voice/<kind>.wav, <kind>_2.wav, <kind>_3.wav).
const VOICE := {
	"spotted": preload("res://audio/voice/spotted.wav"), "lost": preload("res://audio/voice/lost.wav"),
	"cover": preload("res://audio/voice/cover.wav"), "flank": preload("res://audio/voice/flank.wav"),
	"hurt": preload("res://audio/voice/hurt.wav"), "man_down": preload("res://audio/voice/man_down.wav"),
	"help": preload("res://audio/voice/help.wav"), "push": preload("res://audio/voice/push.wav"),
	"heal": preload("res://audio/voice/heal.wav"),
}
const STEP_SOUNDS: Array[AudioStream] = [
	preload("res://audio/step1.wav"), preload("res://audio/step2.wav"), preload("res://audio/step3.wav")]

@export_group("Movement")
@export var move_speed := 3.6
## (0.12.7, owner: players on hills shot scavs that never noticed them: 50 m before.)
@export var sight_range := 75.0
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
## (0.12.6, owner: scavs should be pretty aware and spot you fairly easily: 0.25 / 1.2 s before.
## 0.12.7: far is now at 75 m instead of 50, so 1.0 s there keeps 50 m at about 0.7 s.)
@export var spot_time_near := 0.15
@export var spot_time_far := 1.0
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
## A friend dying this close (meters) gets its attention too: it turns toward roughly where the shots came from
## (0.12.7). Up to `buddy_hear_radius` it notices anyway; farther, only if it can see the body.
@export var buddy_see_radius := 35.0
@export var buddy_hear_radius := 12.0

@export_group("Hearing")
## Sounds this loud (noise radius, meters; gunshots) alarm it: it jogs over instead of walking (0.12.7).
@export var alarm_noise := 30.0
## How far off a heard sound's spot can be (meters): it investigates *roughly* where the sound came from.
@export var noise_uncertainty := 3.0
## Walks at this fraction of move_speed while investigating.
@export var investigate_speed := 0.6
## Seconds spent looking around at a spot (a sound it investigated, or where it lost you) before giving up.
@export var search_time := 5.0
## Lost you in a fight: it hunts for you this long (seconds) around where it last saw you, walking to spots within
## hunt_radius (indoor ones first, each searcher picking a different one), then patrols again, wary for wary_time
## (quicker to spot you). (0.12.14, owner: smarter search, about 30 s.)
@export var hunt_time := 30.0
@export var hunt_radius := 18.0
@export var wary_time := 30.0

@export_group("Shooting")
## Fires at you from this far; beyond it, it closes in first.
## (0.12.8, owner: far-off scavs just looked at you, then went for cover: 40 m before. Far shots rarely hit.)
## (0.12.12: 75 m in 0.12.8-0.12.11, owner: "lower by 5".)
@export var shoot_range := 70.0
## Delay between spotting the player and starting to aim. Gives you a moment to react.
## (0.12.30, owner: "reaction time is still really slow": spotted -> first shot was 0.65 s, now 0.35 s.)
@export var reaction_time := 0.15
## Getting shot (or a bullet whizzing past) while unaware startles it: it turns and starts aiming after only this
## long, so whoever sees first gets the first shots, not a free kill (0.11.16: before, it died before it reacted).
@export var startle_reaction_time := 0.15
@export var aim_time := 0.2
## The longest burst. Each burst is a random length: longer up close, short taps far away (0.12.6, owner: not
## always 3). 1 = single shots (snipers).
@export var burst_size := 3
@export var burst_interval := 0.13
@export var burst_cooldown_min := 0.75
@export var burst_cooldown_max := 1.0
## Time to kill: 15 = an unarmored player (100 HP) dies in 7 hits (9 with light armor, 12 with heavy).
@export var shot_damage := 15
## Chance each bullet hits: accuracy_near up close, accuracy_far at accuracy_range, then down to accuracy_long at
## shoot_range (0.12.8, owner: "at far their accuracy should be even worse ... a gradient, as they get closer it's better").
@export var accuracy_near := 0.6
@export var accuracy_far := 0.2
@export var accuracy_range := 28.0
## (0.12.9, owner: too low; scavs bottom out at about 10%.)
@export var accuracy_long := 0.1
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
## Closer than this (meters) it fights back first and only takes cover within close_cover_radius (0.12.30, owner).
@export var close_fight_range := 12.0
@export var close_cover_radius := 3.0
@export var cover_hold_time := 1.2
## At most one new cover spot per this many seconds. (0.12.10: 5 s before; owner: they kept running sideways in
## the open instead of hiding.)
@export var cover_cooldown := 2.5
## Each peek lasts this long (seconds, random), then it ducks back in; after this many peeks it re-thinks
## (a new spot, or chasing you if you've gone).
@export var peek_time_min := 1.5
@export var peek_time_max := 3.0
@export var peeks := 5

@export_group("Teamwork")
## Smarter fights (Scavs 2.0, owner: AI were "too dumb"). When it starts a fight it calls for help: unaware AI
## within this many meters jog over to where the fight is. 0 = never.
@export var help_radius := 35.0
## At most this many AI in a raid head over to a fight they heard or were called to at once; the rest go on alert
## where they are (0.12.11, owner: a friend in town had to fight 8-9 at once, they grouped up a LOT).
@export var max_responders := 4
## Sticks to its patrol area (Bon and his guards, 0.12.12, owner): ignores calls and sounds from outside it, and
## gives up a chase once it's more than `leash` meters past the edge of its area, heading back to patrol.
@export var stays_home := false
## Suppress and push (0.12.15, owner): you duck out of sight mid-fight and another AI is fighting you too: it keeps
## shooting at where you were for suppress_time seconds (pinning you in cover) while the nearest other one flanks.
## Chance it happens each time it loses you (Raiders always).
@export var suppress_chance := 0.5
@export var suppress_time := 5.0
@export var leash := 40.0
## Scavs and Raiders are rivals (0.12.17, owner): they ignore each other, but never answer the other side's calls
## for help, warn it or team up with it. raider.tscn and boss.tscn are "raider".
@export var faction := &"scav"

@export_group("Voice")
## Callouts: how deep its voice is (Raiders and Bon lower) and at most one callout per this many seconds.
@export var voice_pitch := 1.0
@export var bark_cooldown := 4.0
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
## Badly hurt (below this fraction of max health; scavs 30%, Raiders and Bon 40%) it plays safer: no pushing or
## flanking, cover whenever it can. It doesn't run away (0.12.32, owner: "reposition and fight"); it patches up once
## the fight goes quiet (quiet_heal_time). Getting hit while healing interrupts it (it can try again later).
@export var hurt_fraction := 0.3
## Patches up only after this long with no sight of anyone and nothing shot at it (and only if it's lost a fair bit).
@export var quiet_heal_time := 5.0
## Wounded (below this fraction of max health, 0.12.13, owner): it limps (this fraction of its speed), stops pushing
## and flanking, and when it first gets this low it calls for help and falls back to cover.
@export var wounded_fraction := 0.35
@export var wounded_speed := 0.7
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
## Heals left this life, and time left on the current heal.
var _heals_left := 0
var _heal_left := 0.0
## How long since it last had a line of sight to its target (for patching up once things go quiet).
var _unseen_time := 0.0
## Where it last heard something, and how long it still stands looking that way first.
var _heard_at := Vector3.ZERO
var _look_at_sound_left := 0.0
## Its patrol area (Scavs 2.0, owner: AI stays where players learn to expect it). Set by the spawner from the
## map's AI zones: while unaware it only patrols within `home_radius` meters of `home_center`. 0 = roams the
## whole map (the few random roamers, and every AI on the test map). Fights can still pull it out.
var home_center := Vector3.ZERO
var home_radius := 0.0
## Parts of its area it keeps out of: Vector3(x, radius, z) circles (0.12.31, owner: the town's scavs stay away
## from the town hall and the bank, where Bon's guards and the Raiders are), and how far out (fraction of
## home_radius) its open-ground patrol stops sit (the town's scavs patrol round the edges of town).
var home_avoid: Array = []
var home_edge := 0.0
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
## Said a callout (VOICE key); online the server sends it on so players hear it.
signal barked(kind: String)
const NET_LEAN_IN := 1
const NET_WINDUP := 2
const NET_LUNGE := 4
const NET_SNEAK := 8
const NET_AIM := 16
const NET_CROUCH := 32
const NET_WOUNDED := 64
## Crouched behind low cover (a tent, a car, a low wall): the model and hitboxes shrink to this fraction of its
## height (0.12.10).
const CROUCH_HEIGHT := 0.6
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
	_voice = voice_pitch * randf_range(0.92, 1.08)
	# Its own copies of the hit shapes, so crouching this one doesn't shrink every scav.
	for shape_node: CollisionShape3D in [$BodyShape, $HeadShape]:
		shape_node.shape = shape_node.shape.duplicate()
	_body_rest = ($BodyShape as CollisionShape3D).position
	_body_size = (($BodyShape as CollisionShape3D).shape as BoxShape3D).size
	_head_rest = ($HeadShape as CollisionShape3D).position
	if glint:
		_make_glint()


## Called via the "enemies" group by anything that makes noise (shots, footsteps, knife, searching).
## Unaware scavs walk over to investigate; scavs already fighting ignore it.
func hear_noise(pos: Vector3, radius: float) -> void:
	if puppet:
		return
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH] or global_position.distance_to(pos) > radius * hearing_mult:
		return
	if stays_home and not _near_home(pos):
		return
	if radius >= alarm_noise and not _is_responding() and _responders() >= max_responders:
		_hold_alert(pos)
		return
	var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf() * noise_uncertainty
	_goal = pos + offset
	# First it snaps round to look where the sound came from (0.12.30, owner: walking right past them, they never
	# looked); then it walks over. (Not again for every footstep it's already looking toward.)
	var to_sound := _flat(pos - global_position)
	if state != State.INVESTIGATE or (to_sound.length() > 0.1 and _flat(-global_basis.z).normalized().dot(to_sound.normalized()) < 0.5):
		_heard_at = pos
		_look_at_sound_left = 0.85
	if state != State.INVESTIGATE:
		_set_state(State.INVESTIGATE)
	if radius >= alarm_noise:
		_alarmed = true


func _physics_process(delta: float) -> void:
	if state == State.DEAD or puppet:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	_state_time += delta
	_melee_cooldown_left -= delta
	_since_threat += delta
	_cover_cooldown_left -= delta
	_bark_left -= delta
	# Crouched only while hiding at low cover (holding, or patching up there); up again to peek or move.
	_crouched = _cover_low and state == State.ENGAGE and _cover_phase in [Cover.HOLDING, Cover.HEALING]

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
	_unseen_time = 0.0 if _can_see else _unseen_time + delta

	# Chased you too far from its area: give up and head back (it won't re-spot you for a few seconds unless shot).
	_home_return_left -= delta
	_wary_left -= delta
	if stays_home and state in [State.ALERT, State.ENGAGE, State.INVESTIGATE] and not _near_home(global_position):
		_cover_phase = Cover.NONE
		_hold_fire()
		_set_state(State.IDLE)
		_wander_dir = Vector3.ZERO
		_wander_time = 0.0
		_home_return_left = 6.0

	var desired := Vector3.ZERO
	match state:
		State.IDLE:
			desired = _scan(delta) if holds_position else _wander(delta)
			if _home_return_left <= 0.0 and _spotting(delta, to_target, dist, spot_suspicious_mult if _wary_left > 0.0 else 1.0):
				_alert(_target.global_position)
		State.INVESTIGATE:
			# Walk over to where the sound was, looking that way.
			if holds_position:   # look toward the noise from the perch
				_face(_flat(_goal - global_position), delta, 3.0)
				if _state_time > 3.0:
					_set_state(State.SEARCH)
			else:
				_look_at_sound_left -= delta
				if _look_at_sound_left > 0.6:
					pass   # a moment to register it ("huh?")
				elif _look_at_sound_left > 0.0:
					_face(_flat(_heard_at - global_position), delta, 14.0)
				else:
					desired = _path_velocity(_goal, move_speed * (jog_speed if _answering_call or _alarmed else investigate_speed))
					_face(desired, delta)
			if _spotting(delta, to_target, dist, spot_suspicious_mult):
				_alert(_target.global_position)
			elif _arrived(_goal) or _state_time > 15.0:
				_set_state(State.SEARCH)
		State.SEARCH:
			if _hunting and not holds_position:
				desired = _hunt(delta)
			else:
				# Look around the spot, then go back to wandering.
				rotation.y += delta * 1.2 * _side
			if _spotting(delta, to_target, dist, spot_suspicious_mult):
				_alert(_target.global_position)
			elif _state_time > (hunt_time if _hunting else search_time):
				if _hunting:
					_wary_left = wary_time
				_set_state(State.IDLE)
		State.ALERT:
			# Turn toward you if it can see you, else toward where it knows you were.
			_face(to_target if _can_see else _flat(_last_seen - global_position), delta)
			if _state_time >= _reaction:
				_set_state(State.ENGAGE)
				_fire_timer = aim_time
				# Out of range (you're far off): get to cover first. In range it shoots first and takes cover
				# after its first burst (0.12.8, owner: far-off scavs just looked at you, then went for cover).
				if not holds_position and dist > shoot_range and dist < INF and _cover_cooldown_left <= 0.0:
					_try_take_cover()
		State.ENGAGE:
			# Keeps tracking you while it can see you; once it has lost you for a moment it has to re-spot you.
			var sees := _can_see and (_lost_sight_time < reacquire_grace or _spotting(delta, to_target, dist, spot_reacquire_mult))
			if dist == INF:
				_set_state(State.IDLE)
			else:
				desired = _fight(delta, sees, to_target, dist) + _separation(delta)

	# The fight's gone quiet (out of sight a while, nothing shooting at it): patch up where it is.
	if _cover_phase == Cover.HEALING and state != State.ENGAGE:
		desired = Vector3.ZERO
		_tick_heal(delta)
	elif _quiet_enough_to_heal():
		_start_heal()
	if holds_position and home_radius > 0.0 and not _in_home(global_position + desired * delta * 4.0):
		desired = Vector3.ZERO   # the edge of its perch
	if _sneaking():
		desired *= 0.55
	if is_wounded():
		desired *= wounded_speed
	if BoxMap.is_wading(self):   # slower through water, like players (0.11.20)
		desired *= 0.6
	_knockback = _knockback.lerp(Vector3.ZERO, minf(delta * 8.0, 1.0))
	velocity.x = desired.x + _knockback.x
	velocity.z = desired.z + _knockback.z
	move_and_slide()
	_check_stuck(delta, desired)
	_update_footsteps(delta)


## Trying to move but not getting anywhere (pressed against a wall, sliding along it) for a while: gives up on
## where it was going (0.12.8, owner: one hugged a building for 20 seconds).
func _check_stuck(delta: float, desired: Vector3) -> void:
	var want := _flat(desired)
	if want.length() < 0.5:
		_stuck_time = 0.0
		return
	var progress := _flat(get_real_velocity()).dot(want.normalized())
	if progress < want.length() * 0.3:
		_stuck_time += delta
	else:
		_stuck_time = maxf(_stuck_time - delta * 2.0, 0.0)
	if _stuck_time < 1.5:
		return
	_stuck_time = 0.0
	_path.clear()
	_side = -_side
	if _cover_phase in [Cover.MOVING, Cover.FLANKING, Cover.PEEKING]:
		_cover_phase = Cover.NONE
		_cover_cooldown_left = cover_cooldown
	elif state == State.IDLE and leader != null:
		_follow_direct_left = 4.0
	elif state == State.IDLE:
		_wander_dir = Vector3.ZERO
		_wander_time = 0.0
	elif state == State.INVESTIGATE:
		_set_state(State.SEARCH)
	elif state == State.ENGAGE and not _can_see:
		_set_state(State.SEARCH)


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
		Effects.sound_at(get_tree().current_scene, STEP_SOUNDS.pick_random(), global_position, -6.0, 0.1, 0.9, 2.5, STEP_HEAR_RANGE)


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
	# Limping: the body dips to one side with every other step.
	_limp = move_toward(_limp, 1.0 if is_wounded() else 0.0, delta * 3.0)
	model.rotation.z = _limp * maxf(sin(_walk_time), 0.0) * 0.18 * minf(speed / 1.5, 1.0)
	_update_crouch(delta)
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
	if state in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		if not _answering_call and _call_for_help(known_pos):
			_bark("help")
		else:
			_bark("spotted", 0.7)
	_reaction = reaction_time if reaction < 0.0 else reaction
	_cover_phase = Cover.NONE
	_spot = 0.0
	_looting_left = 0.0
	_last_seen = known_pos
	_set_state(State.ALERT)
	alerted.emit()
	net_alerted()


## A fight starts: unaware AI nearby (its zone-mates, mostly) come over to help.
## True if anyone was in earshot.
func _call_for_help(known_pos: Vector3) -> bool:
	if help_radius <= 0.0 or puppet:
		return false
	var called := false
	for node in RaidScope.nodes(self, &"enemies"):
		var ally := node as Scav
		if ally != null and ally != self and ally.faction == faction and global_position.distance_to(ally.global_position) <= help_radius:
			ally.answer_call(known_pos)
			called = true
	return called


## Another AI called for help: if unaware, jog over toward where the fight is (not exactly where you are).
func answer_call(pos: Vector3) -> void:
	if puppet or holds_position or state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		return
	if stays_home and not _near_home(pos):
		return
	if not _is_responding() and _responders() >= max_responders:
		_hold_alert(pos)
		return
	_goal = pos + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf() * noise_uncertainty
	_looting_left = 0.0
	_answering_call = true
	_set_state(State.INVESTIGATE)


## Within `leash` meters of its patrol area (always true without one).
func _near_home(point: Vector3) -> bool:
	return home_radius <= 0.0 or _flat(point - home_center).length() <= home_radius + leash


## Lost you mid-fight: start hunting around where it last saw you.
func _start_hunt() -> void:
	_hunting = true
	_hunt_point = Vector3.INF
	_hunt_pause = 0.0
	_hunted.clear()


## Hunting: walk to a spot near where it lost you, look around there a moment, pick the next.
func _hunt(delta: float) -> Vector3:
	if _hunt_point == Vector3.INF or _hunt_pause > 0.0:
		rotation.y += delta * 1.5 * _side
		_hunt_pause -= delta
		if _hunt_pause <= 0.0:
			_hunt_point = _pick_hunt_point()
			if _hunt_point == Vector3.INF:
				_hunt_pause = 1.0
		return Vector3.ZERO
	var move := _path_velocity(_hunt_point, move_speed * investigate_speed * 1.2)
	_face(move, delta, 5.0)
	if _arrived(_hunt_point):
		_hunted.append(_hunt_point)
		_hunt_point = Vector3.INF
		_hunt_pause = randf_range(1.5, 2.5)
	return move


## The next place to check: a walkable spot near where it lost you that it hasn't checked, isn't where another
## searcher is heading, and is preferably indoors (something overhead) where you'd hide.
func _pick_hunt_point() -> Vector3:
	var space := get_world_3d().direct_space_state
	var others: Array[Vector3] = []
	for node in RaidScope.nodes(self, &"enemies"):
		var ally := node as Scav
		if ally != null and ally != self and ally._hunting and ally._hunt_point != Vector3.INF:
			others.append(ally._hunt_point)
	var best := Vector3.INF
	var best_score := -INF
	for i in 10:
		var offset := Vector3(hunt_radius * sqrt(randf()), 0, 0).rotated(Vector3.UP, randf() * TAU)
		var spot := AINav.closest(self, _last_seen + offset)
		if spot == Vector3.ZERO or _flat(spot - global_position).length() < 3.0:
			continue
		if stays_home and not _near_home(spot):
			continue
		var score := randf() * 2.0
		var up := spot + Vector3(0, 1.0, 0)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(up, up + Vector3(0, 8, 0), 1)).is_empty():
			score += 5.0   # indoors
		for p in others + _hunted:
			if _flat(p - spot).length() < 6.0:
				score -= 8.0
		if score > best_score:
			best_score = score
			best = spot
	return best


## Below hurt_fraction (or wounded): plays safer, no pushing, flanking or chasing (0.12.32).
func is_hurt() -> bool:
	return is_wounded() or (not health.is_dead and health.current <= health.max_health * hurt_fraction)


## Badly hurt: limps (puppets: the server's scav is).
func is_wounded() -> bool:
	if puppet:
		return (_net_flags & NET_WOUNDED) != 0
	return not health.is_dead and health.current <= health.max_health * wounded_fraction


## Heading over to a fight it heard or was called to.
func _is_responding() -> bool:
	return state == State.INVESTIGATE and (_answering_call or _alarmed)


## How many AI in this raid are heading over to a fight right now.
func _responders() -> int:
	var count := 0
	for node in RaidScope.nodes(self, &"enemies"):
		var ally := node as Scav
		if ally != null and ally != self and ally._is_responding():
			count += 1
	return count


## Enough others are already going: it stays put, on alert, looking toward the trouble (quicker to spot you).
func _hold_alert(pos: Vector3) -> void:
	_looting_left = 0.0
	_goal = pos
	if state != State.SEARCH:
		_set_state(State.SEARCH)
	if _flat(pos - global_position).length() > 0.5:
		look_at(Vector3(pos.x, global_position.y, pos.z), Vector3.UP)


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


## Shot by someone other than who it's fighting (co-op): it turns on the one shooting it (0.12.31; it used to keep
## its eyes on the closest player while someone else shot it).
func _target_shooter(source_position: Vector3) -> void:
	for node in RaidScope.nodes(self, &"player"):
		var player := node as Player
		if player != null and player != _target and not player.out_of_fight() \
				and player.global_position.distance_to(source_position) < 2.5:
			_target = player
			_lost_sight_time = 0.0
			return


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


## Crouching behind low cover: shorter model and hitboxes (puppets follow the server's flag).
func _update_crouch(delta: float) -> void:
	var want := (_net_flags & NET_CROUCH) != 0 if puppet else _crouched
	var amount := move_toward(_crouch_amount, 1.0 if want else 0.0, delta * 5.0)
	if amount == _crouch_amount:
		return
	_crouch_amount = amount
	var height := lerpf(1.0, CROUCH_HEIGHT, amount)
	model.scale.y = height
	var body := $BodyShape as CollisionShape3D
	(body.shape as BoxShape3D).size = Vector3(_body_size.x, _body_size.y * height, _body_size.z)
	body.position = _body_rest * height
	($HeadShape as CollisionShape3D).position = _head_rest * height


## The fight brain (0.12.29, owner: the AI felt "cluttered and messy"; built like shipped shooters' AI). It picks
## ONE plan (a Tactic) and sticks to it until the plan is done or something real changes (it gets shot in the open,
## loses sight of you, you start reloading, you get out of range); every move it makes serves that plan.
## Before, each behavior grabbed control on its own every frame, so plans flip-flopped.
## Reflexes still come first: a bash up close, backing off when you're in its face.
enum Tactic { NONE, COVER, STAND, PUSH, FLANK, ADVANCE, PURSUE, SUPPRESS }
var tactic := Tactic.NONE
var _tactic_time := 0.0
## STAND: how long it trades shots in the open before looking for cover (or a flank) again.
var _stand_time := 0.0
## Got shot since it last decided (makes a plan in the open rethink).
var _hit_since_decide := false
## A quick sidestep after getting shot in the open (the only sideways move it makes there).
var _dodge_left := 0.0
var _dodge_dir := 0.0


func _fight(delta: float, sees: bool, to_target: Vector3, dist: float) -> Vector3:
	_tactic_time += delta
	_dodge_left -= delta
	# The cover plans (cover + peeking, flanking, falling back to heal) run their own steps until they end.
	if _cover_phase != Cover.NONE:
		var move := _update_cover(delta, sees, to_target, dist)
		if _cover_phase == Cover.NONE:
			tactic = Tactic.NONE   # done: decide again next frame
		return move
	if sees:
		_suppress_left = 0.0
		_may_suppress = true
		_last_seen = _target.global_position
		_lost_sight_time = 0.0
		_spot = 0.0
		# Reflexes.
		if _windup_left > 0.0 or (dist < melee_range and _melee_cooldown_left <= 0.0):
			_face(to_target, delta)
			_update_melee(delta, dist)
			return Vector3.ZERO
		if dist < min_distance:
			_face(to_target, delta)
			_update_shooting(delta, dist)
			return _clear_of_walls(-to_target.normalized() * move_speed * 0.7)
	else:
		_lost_sight_time += delta
	if tactic == Tactic.NONE or _should_rethink(sees, dist):
		_decide(sees, to_target, dist)
		if _cover_phase != Cover.NONE:
			return _update_cover(delta, sees, to_target, dist)
	match tactic:
		Tactic.STAND:
			# Trades shots where it stands; the only sideways move is a quick dodge right after being hit.
			_face(to_target, delta)
			_update_shooting(delta, dist)
			if _dodge_left > 0.0 and not holds_position:
				return _clear_of_walls(to_target.normalized().cross(Vector3.UP) * _dodge_dir * move_speed * 0.8)
			return Vector3.ZERO
		Tactic.PUSH:
			_face(to_target, delta)
			_update_shooting(delta, dist)
			return _path_velocity(_target.global_position, move_speed * push_speed)
		Tactic.ADVANCE:
			_hold_fire()
			if holds_position:
				_face(to_target, delta)
				return Vector3.ZERO
			return _close_in(delta, _target.global_position, to_target)
		Tactic.SUPPRESS:
			# Pinning you down: keeps firing at where you ducked out of sight.
			_suppress_left -= delta
			_face(_flat(_last_seen - global_position), delta)
			_update_shooting(delta, global_position.distance_to(_last_seen), true)
			return Vector3.ZERO
		Tactic.PURSUE:
			# Lost sight: go to where it last saw you (it doesn't know where you went), then search.
			if _arrived(_last_seen) or _lost_sight_time > give_up_time:
				_set_state(State.SEARCH)
				_start_hunt()
				_bark("lost", 0.6)
				return Vector3.ZERO
			if holds_position or is_hurt():   # (badly hurt: it doesn't come after you, it waits for you to show)
				_face(_flat(_last_seen - global_position), delta)
				return Vector3.ZERO
			if _flat(_last_seen - global_position).length() > shoot_range:
				return _close_in(delta, _last_seen, _flat(_last_seen - global_position))
			var move := _path_velocity(_last_seen, move_speed)
			_face(move, delta)
			return move
	return Vector3.ZERO


## In a fight, friends keep a step apart instead of standing inside each other (Bon's guards can walk through him
## on patrol, so they don't box him in): a gentle push away from anyone closer than 1.5 m (0.12.29).
var _apart := Vector3.ZERO
var _apart_check_left := 0.0
func _separation(delta: float) -> Vector3:
	_apart_check_left -= delta
	if _apart_check_left <= 0.0:
		_apart_check_left = 0.2
		_apart = Vector3.ZERO
		for node in RaidScope.nodes(self, &"enemies"):
			var other := node as Scav
			if other == null or other == self or other.state == State.DEAD:
				continue
			var away := _flat(global_position - other.global_position)
			var d := away.length()
			if d < 1.5:
				_apart += (away / d if d > 0.01 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)) * (1.5 - d) * 2.0
	return _apart


## Whether the current plan no longer fits (something real changed).
func _should_rethink(sees: bool, dist: float) -> bool:
	match tactic:
		Tactic.STAND:
			return (not sees or dist > shoot_range or _can_push(dist) or _tactic_time > _stand_time
				or (_hit_since_decide and _dodge_left <= 0.0))
		Tactic.PUSH:
			return not sees or not _can_push(dist)
		Tactic.ADVANCE:
			return not sees or dist <= shoot_range
		Tactic.SUPPRESS:
			return sees or _suppress_left <= 0.0
		Tactic.PURSUE:
			return sees
	return true


## Picks the plan, in order: lost you: pin you down (if a friend can flank) or go after you; too far: move up;
## you're reloading or healing: push; otherwise get to cover (sometimes flank in a lull), and only with no cover
## anywhere near, trade shots in the open. Badly hurt it never pushes or flanks, and it never runs away: it
## repositions to cover and keeps fighting (0.12.32, owner), patching up once the fight goes quiet.
func _decide(sees: bool, to_target: Vector3, dist: float) -> void:
	_tactic_time = 0.0
	_hit_since_decide = false
	if not sees:
		if _suppress_left > 0.0 or _try_suppress():
			tactic = Tactic.SUPPRESS
		else:
			tactic = Tactic.PURSUE
		return
	if dist > shoot_range:
		tactic = Tactic.ADVANCE
		return
	if _can_push(dist):
		tactic = Tactic.PUSH
		_bark("push")
		return
	if not holds_position and _cover_cooldown_left <= 0.0:
		# Up close (inside a building, round a corner) its first instinct is to shoot back: it only ducks into cover
		# that's a step or two away (0.12.30, owner: one ran around looking for cover while he shot it).
		if dist < close_fight_range:
			_try_take_cover(close_cover_radius)
		elif _since_threat > lull_time and randf() < flank_chance and not is_hurt():
			_try_flank(to_target, dist)   # (takes cover instead if there's no hidden spot to flank to)
		else:
			_try_take_cover()
		if _cover_phase != Cover.NONE:
			tactic = Tactic.FLANK if _cover_phase == Cover.FLANKING else Tactic.COVER
			return
	tactic = Tactic.STAND
	_stand_time = randf_range(2.0, 3.0) * (0.5 if is_hurt() else 1.0)   # badly hurt: looks for cover again sooner


## You're reloading or healing and it's not hurt: worth rushing you.
func _can_push(dist: float) -> bool:
	return _target_busy() and not holds_position and not is_hurt() and dist > min_distance + 2.0


## Too far away to shoot (e.g. you're up on a hill): it moves up cover to cover (0.12.7, owner: they went into
## cover, then just walked at him in the open). With no cover ahead it waits where it is, out of sight if it can.
func _close_in(delta: float, goal: Vector3, to_goal: Vector3) -> Vector3:
	_advance_check_left -= delta
	if _advance_check_left <= 0.0:
		_advance_check_left = 0.6
		var spot := _find_advance_cover(goal)
		if spot != Vector3.INF:
			_cover_point = spot
			_cover_low = false
			_cover_phase = Cover.MOVING
			_peek_point = Vector3.INF
			_peeks_left = 0
			return _path_velocity(spot, move_speed)
		if _can_see and _cover_cooldown_left <= 0.0:
			_try_take_cover()   # nothing closer: at least get out of your sight
			if _cover_phase != Cover.NONE:
				return Vector3.ZERO
	_face(to_goal, delta)
	if _can_see and _lost_sight_time <= 0.0 and _no_cover_around():
		# Out in the open with nowhere to hide: rush straight in.
		return _path_velocity(goal, move_speed)
	return Vector3.ZERO


## True when it already checked and there's no cover near here worth going to.
func _no_cover_around() -> bool:
	return _cover_cooldown_left > 0.0 and _cover_phase == Cover.NONE


## The next spot of cover toward `goal`: a few meters closer to it and out of its view, or INF if there's none.
func _find_advance_cover(goal: Vector3) -> Vector3:
	var eyes := goal + Vector3(0, 1.6, 0)
	if _target != null and _can_see:
		eyes = _target.eye_position()
	var to_goal := _flat(goal - global_position)
	var dist := to_goal.length()
	if dist < 1.0:
		return Vector3.INF
	var forward := to_goal / dist
	var space := get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_left := dist - 5.0   # must gain at least 5 m
	for radius in [8.0, 13.0, 18.0]:
		for i in 7:
			var dir := forward.rotated(Vector3.UP, deg_to_rad(-60.0 + i * 20.0))
			var spot := AINav.closest(self, global_position + dir * radius)
			if spot == Vector3.ZERO:
				continue
			var left := _flat(goal - spot).length()
			if left >= best_left or left < shoot_range * 0.5:
				continue
			var query := PhysicsRayQueryParameters3D.create(eyes, spot + Vector3(0, 1.3, 0), 1)
			if space.intersect_ray(query).is_empty():
				continue  # it would be in view there
			if AINav.path_length(AINav.path(self, global_position, spot)) > radius * 1.6:
				continue
			best = spot
			best_left = left
	return best


## Looks for a walkable spot nearby that the target can't see; starts moving there if it finds one.
func _try_take_cover(radius := -1.0) -> void:
	_cover_cooldown_left = cover_cooldown
	var spot := _find_cover(radius)
	if spot != Vector3.INF:
		_cover_point = spot
		_cover_low = _found_low
		_cover_phase = Cover.MOVING
		_bark("cover", 0.35)
		# Where it stands now can see you: that's where it peeks out from.
		_peek_point = global_position
		# (Too far to shoot back from there: no point peeking out, it moves up cover to cover instead.)
		_peeks_left = peeks if _target != null and global_position.distance_to(_target.global_position) <= shoot_range else 0
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
## A flank (0.12.28-0.12.29, owner: no sideways runs across your view, no messy loops): it circles to a spot
## 50-90 degrees round from where it is now, 10-20 m from where it knows you are, that you can't see, along a path
## that's not too long and doesn't pass close to you. With no such spot it takes cover instead.
func _try_flank(to_target: Vector3, dist: float) -> void:
	_cover_cooldown_left = cover_cooldown
	var center := global_position + _flat(to_target)
	var eyes := _target.eye_position()
	var space := get_world_3d().direct_space_state
	var back := -_flat(to_target).normalized()   # from you toward it
	var radius := clampf(dist, 10.0, 20.0)
	var first := 1.0 if randf() < 0.5 else -1.0
	for side_sign: float in [first, -first]:
		for angle: float in [70.0, 50.0, 90.0]:
			var spot := AINav.closest(self, center + back.rotated(Vector3.UP, deg_to_rad(angle) * side_sign) * radius)
			if spot == Vector3.ZERO or _flat(spot - global_position).length() < 4.0:
				continue
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.5, eyes, 1)).is_empty():
				continue   # you'd see it get there
			var route := AINav.path(self, global_position, spot)
			var length := AINav.path_length(route)
			if length > 30.0 or length > _flat(spot - global_position).length() * 2.0:
				continue   # a long loop round
			var too_close := false
			for point in route:
				if _flat(point - center).length() < 6.0:
					too_close = true
					break
			if too_close:
				continue   # the way there runs right past you
			_cover_point = spot
			_cover_low = false
			_cover_phase = Cover.FLANKING
			_bark("flank")
			return
	_cover_cooldown_left = 0.0
	_try_take_cover()


## Lost sight of everyone a while and nothing's shooting at it: worth patching up (if it's lost a fair bit).
func _quiet_enough_to_heal() -> bool:
	return (_heals_left > 0 and _cover_phase != Cover.HEALING and state in [State.ENGAGE, State.SEARCH, State.IDLE]
		and health.current <= health.max_health - heal_amount / 2 and _since_threat >= quiet_heal_time
		and _unseen_time >= quiet_heal_time and _windup_left <= 0.0)


## Patching up: true when done (healed).
func _tick_heal(delta: float) -> bool:
	_heal_left -= delta
	_hold_fire()
	if _heal_left > 0.0:
		return false
	health.heal(heal_amount)
	_heals_left -= 1
	_was_wounded = is_wounded()
	_cover_phase = Cover.NONE
	_lost_sight_time = 0.0
	return true


func _start_heal() -> void:
	_cover_phase = Cover.HEALING
	_heal_left = heal_time
	_hold_fire()
	_bark("heal")
	Effects.sound_at(get_tree().current_scene, HEAL_SOUND, global_position, -6.0, 0.1, 1.0, 6.0, 20.0)


## The closest walkable spot within `radius` (by walking distance) the target can't see; INF if none. Retreating
## (`farther` > 0), only spots at least that much farther from the target than it is now count.
func _find_cover(radius := -1.0, farther := 0.0) -> Vector3:
	if radius < 0.0:
		radius = cover_search_radius
	var my_dist := _flat(global_position - _target.global_position).length()
	var eyes := _target.eye_position()
	var space := get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_walk := INF
	_found_low = false
	# First the far side of things right around it (a tree trunk, a tent, a car, a wall corner, a hillside): the
	# circle samples below easily miss something as thin as a trunk (0.12.10, owner: one didn't hide behind the
	# tents or trees at the camp).
	var away := _flat(global_position - _target.global_position).normalized()
	var chest := global_position + Vector3(0, 1.0, 0)
	for i in 16:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 16.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + dir * radius, 1, [get_rid()]))
		if hit.is_empty():
			continue
		var behind: Vector3 = hit.position + away * 0.9 - dir * 0.3
		var spot := AINav.closest(self, Vector3(behind.x, global_position.y, behind.z))
		if spot == Vector3.ZERO or _flat(spot - behind).length() > 1.5:
			continue
		var hides := _hides_at(space, eyes, spot)
		if hides == 0 or _spot_taken(spot) or _flat(spot - _target.global_position).length() < my_dist + farther:
			continue  # the target could see it there, or a friend is already hiding there
		# (Low cover, where it has to crouch, counts as a few meters farther: it prefers a spot it can stand at.)
		var walk := AINav.path_length(AINav.path(self, global_position, spot))
		if walk <= radius * 1.6 and walk + (3.0 if hides == 1 else 0.0) < best_walk:
			best = spot
			best_walk = walk + (3.0 if hides == 1 else 0.0)
			_found_low = hides == 1
	if best != Vector3.INF:
		return best
	for ring: float in [3.0, 5.0, radius]:
		for i in 12:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 12.0)
			var spot := AINav.closest(self, global_position + dir * ring)
			if spot == Vector3.ZERO or _flat(spot - global_position).length() > ring + 1.0:
				continue
			var query := PhysicsRayQueryParameters3D.create(eyes, spot + Vector3(0, 1.3, 0), 1)
			if space.intersect_ray(query).is_empty() or _spot_taken(spot) or _flat(spot - _target.global_position).length() < my_dist + farther:
				continue  # the target could see it there, or a friend is already hiding there
			# Judge by walking distance: a spot inside a building may be close in a straight line but far around.
			var walk := AINav.path_length(AINav.path(self, global_position, spot))
			if walk <= ring * 1.6 and walk < best_walk:
				best = spot
				best_walk = walk
		if best != Vector3.INF:
			break
	return best


## A friend is at (or heading to) cover within 2 m of `spot`: each AI gets its own spot, so they don't bunch up
## behind the same box (0.12.29).
func _spot_taken(spot: Vector3) -> bool:
	for node in RaidScope.nodes(self, &"enemies"):
		var other := node as Scav
		if other == null or other == self or other.state == State.DEAD:
			continue
		if _flat(other.global_position - spot).length() < 2.0:
			return true
		if other._cover_phase != Cover.NONE and _flat(other._cover_point - spot).length() < 2.0:
			return true
	return false


## Whether `spot` is hidden from `eyes`: 2 standing up, 1 only crouched (low cover), 0 not at all.
func _hides_at(space: PhysicsDirectSpaceState3D, eyes: Vector3, spot: Vector3) -> int:
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eyes, spot + Vector3(0, 1.3, 0), 1)).is_empty():
		return 2
	var head := spot + Vector3(0, 1.71 * CROUCH_HEIGHT + 0.2, 0)
	if (not space.intersect_ray(PhysicsRayQueryParameters3D.create(eyes, head, 1)).is_empty()
			and not space.intersect_ray(PhysicsRayQueryParameters3D.create(eyes, spot + Vector3(0, 0.5, 0), 1)).is_empty()):
		return 1
	return 0


## True if it's not getting anywhere (e.g. the last bit of the path is blocked by another scav).
func _cover_stuck(move: Vector3) -> bool:
	return move.length() < 0.05 or (get_real_velocity().length() < 0.1 and _flat(_cover_point - global_position).length() < 1.2)


## Moving to cover (still shooting if it has a shot), then holding a moment; after that it goes back to the fight
## (if it can't see you from cover, it heads to where it last saw you = peeking out).
func _update_cover(delta: float, sees: bool, to_target: Vector3, dist: float) -> Vector3:
	if _cover_phase == Cover.FLANKING:
		# Runs there facing where it's going (not sideways while shooting at you); shot on the way: fights back.
		var flank_move := _path_velocity(_cover_point, move_speed)
		_face(flank_move, delta)
		_hold_fire()
		# Done, stuck, shot at, or it runs into you up close: back to deciding (and fighting).
		if _arrived(_cover_point) or _cover_stuck(flank_move) or (sees and (_flinch_left > 0.0 or dist < 10.0)):
			_cover_phase = Cover.NONE
			_lost_sight_time = 0.0
		return flank_move
	if _cover_phase == Cover.MOVING:
		# Runs to cover facing where it's going; it only shoots on the way if you're roughly ahead of it, so it
		# doesn't walk sideways to cover while shooting at you (0.12.28, owner: "just moving sideways").
		var move := _path_velocity(_cover_point, move_speed)
		var ahead := move.length() < 0.5 or _flat(move).normalized().dot(_flat(to_target).normalized()) > 0.5
		if sees and dist <= shoot_range and ahead:
			_face(to_target, delta)
			_update_shooting(delta, dist)
		else:
			_face(move, delta)
			_hold_fire()
		# Shot up close on the way, with the cover still a way off: turns and fights instead of running with its
		# back to you (0.12.31).
		if (sees and _hit_since_decide and dist < close_fight_range
				and _flat(_cover_point - global_position).length() > 2.0):
			_cover_phase = Cover.NONE
			_cover_cooldown_left = cover_cooldown
			return Vector3.ZERO
		# Get all the way in (normal arriving allows 1.2 m, which can leave it peeking past the corner).
		if _flat(_cover_point - global_position).length() < 0.4 or _cover_stuck(move):
			_cover_phase = Cover.HOLDING
			_cover_hold_left = cover_hold_time * (1.5 if is_hurt() else 1.0)   # badly hurt: stays down a bit longer
		return move
	if _cover_phase == Cover.HEALING:
		_face(_flat(_last_seen - global_position), delta)
		_tick_heal(delta)
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
		# The last step or two out it faces you, ready to shoot; farther than that it walks there facing ahead
		# (0.12.30: no long sideways walks out of cover).
		var out_left := _flat(_peek_point - global_position).length()
		_face(_flat(_last_seen - global_position) if out_left < 2.0 else move, delta)
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


## Short fight moves (a dodge, backing off): don't push into a wall; try the other side instead.
func _clear_of_walls(move: Vector3) -> Vector3:
	if move.length() < 0.1 or not _blocked(move):
		return move
	_dodge_dir = -_dodge_dir
	var flipped := Vector3(-move.x, 0.0, -move.z)
	return Vector3.ZERO if _blocked(flipped) else flipped


func _blocked(move: Vector3) -> bool:
	var from := global_position + Vector3(0, 0.6, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + move.normalized() * 1.0, 1, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _set_state(new_state: State) -> void:
	_hunting = false
	tactic = Tactic.NONE
	if new_state != State.INVESTIGATE:
		_answering_call = false
		_alarmed = false
	state = new_state
	_state_time = 0.0
	_lost_sight_time = 0.0


func _update_shooting(delta: float, dist: float, suppressing := false) -> void:
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	if _shots_left <= 0:
		_shots_left = _burst_length(dist)
	if suppressing:
		_fire_at_point(_last_seen + Vector3(0, 1.1, 0))
	else:
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

	var chance := hit_chance(dist)
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


## Suppressing: a shot at roughly `point` (where you were); it hits you only if you're in the way.
func _fire_at_point(point: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.65, 0)
	var aim := point + Vector3(randf_range(-0.8, 0.8), randf_range(-0.4, 0.6), randf_range(-0.8, 0.8))
	var to := from + (aim - from).normalized() * (shoot_range + 20.0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [get_rid()])
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
	net_fired(end)


## Just lost you: if another AI is fighting you too and nobody's suppressing yet, it pins you down and sends the
## nearest other one around to flank you. True if it's suppressing now.
func _try_suppress() -> bool:
	if not _may_suppress or _lost_sight_time > 1.0:
		return false
	_may_suppress = false   # (decided once each time it loses you)
	if randf() > suppress_chance or global_position.distance_to(_last_seen) > shoot_range * 0.8:
		return false
	var flanker: Scav = null
	var best := 40.0
	for node in RaidScope.nodes(self, &"enemies"):
		var ally := node as Scav
		if ally == null or ally == self or ally.faction != faction or ally.state != State.ENGAGE or ally._target != _target:
			continue
		if ally._suppress_left > 0.0:
			return false   # someone already is
		var d := ally.global_position.distance_to(global_position)
		if d < best and not ally.holds_position and not ally.is_wounded() and ally._cover_phase in [Cover.NONE, Cover.HOLDING]:
			best = d
			flanker = ally
	if flanker == null:
		return false
	_suppress_left = suppress_time
	_bark_left = 0.0
	_bark("push")
	var to_target := _flat(_last_seen - flanker.global_position)
	flanker._try_flank(to_target, to_target.length())
	flanker._bark_left = 0.0
	flanker._bark("flank")
	return true


## Patrolling while unaware: walk to a destination in its area (`home_radius`; the whole map for a roamer), mostly
## loot spots, which are in and around buildings, sometimes anywhere reachable. Pause there, then pick the next one.
## `_wander_dir` is zero while pausing (`_wander_time` counts the pause down).
func _wander(delta: float) -> Vector3:
	# A duo partner sticks with its leader instead of picking its own patrol.
	if leader != null and is_instance_valid(leader) and leader.state != State.DEAD:
		var spot := leader.global_position + leader.global_basis.x * follow_offset.x + leader.global_basis.z * follow_offset.z
		_follow_direct_left -= delta
		if _follow_direct_left > 0.0:
			spot = leader.global_position   # (stuck getting to its own spot: just follow the leader's steps)
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


## Starts following `new_leader` (a boss's guard, a Raider's partner). Followers and their leader walk through each
## other (0.12.20: Bon's guards boxed him into a corner of the town hall and none of them could move).
func follow(new_leader: Scav) -> void:
	leader = new_leader
	for node in RaidScope.nodes(self, &"enemies"):
		var other := node as Scav
		if other != null and other != self and (other == new_leader or other.leader == new_leader):
			add_collision_exception_with(other)
			other.add_collision_exception_with(self)


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
	# Open-ground stops prefer a spot next to a wall or other cover (0.12.7, owner: patrol behind cover, not out
	# in the open where anyone on a hill can pick them off).
	var fallback := Vector3.INF
	for attempt in 8:
		var spot: Vector3
		_patrol_container = null
		# (Loot spots, inside buildings, 45% of the time: 0.12.24, owner: patrol a lot, not go for loot.)
		if not spots.is_empty() and randf() < 0.45:
			_patrol_container = spots.pick_random() as Node3D
			# Walk up next to it (the closest walkable point to the container).
			spot = AINav.closest(self, _patrol_container.global_position)
		elif home_radius > 0.0:
			var offset := Vector3(home_radius * lerpf(home_edge, 1.0, sqrt(randf())), 0, 0).rotated(Vector3.UP, randf() * TAU)
			spot = AINav.closest(self, home_center + offset)
		else:
			spot = AINav.random_point(self)
		if spot != Vector3.ZERO and _flat(spot - global_position).length() > 6.0 and (home_radius <= 0.0 or _in_home(spot)):
			if _patrol_container != null or _has_cover_at(spot):
				return spot
			if fallback == Vector3.INF:
				fallback = spot
	_patrol_container = null
	if fallback != Vector3.INF:
		return fallback
	# No navigation map yet: somewhere a few meters ahead.
	return global_position + _flat(-global_basis.z).normalized().rotated(Vector3.UP, randf_range(-1.2, 1.2)) * 6.0


## Something solid (a wall, crate, car) right next to `spot`, about chest high.
func _has_cover_at(spot: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := spot + Vector3(0, 1.0, 0)
	for i in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 8.0)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 2.5, 1)).is_empty():
			return true
	return false


## Inside its patrol area (a little slack at the edge); always true for a roamer.
func _in_home(point: Vector3) -> bool:
	if home_radius <= 0.0:
		return true
	for circle: Vector3 in home_avoid:
		if Vector2(point.x - circle.x, point.z - circle.z).length() <= circle.y:
			return false
	return _flat(point - home_center).length() <= home_radius + (0.0 if holds_position else 4.0)


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
var _advance_check_left := 0.0
var _stuck_time := 0.0
var _follow_direct_left := 0.0
var _bark_left := 0.0
var _voice := 1.0
var _home_return_left := 0.0
var _hunting := false
var _suppress_left := 0.0
var _may_suppress := true
var _hunt_point := Vector3.INF
var _hunt_pause := 0.0
var _hunted: Array[Vector3] = []
var _wary_left := 0.0
var _was_wounded := false
var _limp := 0.0
## The cover spot it's heading for is low (only hides it crouched); it's crouching there now; how crouched it looks.
var _cover_low := false
var _found_low := false
var _crouched := false
var _crouch_amount := 0.0
var _body_rest := Vector3.ZERO
var _body_size := Vector3.ONE
var _head_rest := Vector3.ZERO
var _peek_blind := 0.0
## Heading over because another AI called for help (jogs instead of walking).
var _answering_call := false
## Investigating a gunshot: hurries.
var _alarmed := false
## Where the last hit on it came from (friends nearby turn that way when it dies).
var _last_hit_from := Vector3.INF


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


## Chance a bullet hits at `dist` meters (before point blank, sprinting and flinch adjustments).
func hit_chance(dist: float) -> float:
	if dist <= accuracy_range:
		return lerpf(accuracy_near, accuracy_far, dist / maxf(accuracy_range, 0.01))
	return lerpf(accuracy_far, accuracy_long, clampf((dist - accuracy_range) / maxf(shoot_range - accuracy_range, 1.0), 0.0, 1.0))


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
	_target_shooter(source_position)
	_since_threat = 0.0
	_last_hit_from = source_position
	if _cover_phase == Cover.HEALING:
		_cover_phase = Cover.NONE   # interrupted: back to fighting (it patches up again once it's quiet)
	_hit_flash_time = 0.08
	if _flinch_left <= 0.0:
		_fire_timer = maxf(_fire_timer, flinch_fire_delay)
	_flinch_left = flinch_time
	_hit_since_decide = true
	if tactic == Tactic.STAND and _cover_phase == Cover.NONE and _dodge_left <= 0.0:
		_dodge_left = 0.35
		_dodge_dir = -1.0 if randf() < 0.5 else 1.0
	if not health.is_dead and is_wounded() and not _was_wounded:
		# Just got badly hurt: shout for help and get into cover (close by if you're close).
		_was_wounded = true
		_bark_left = 0.0
		_bark("help")
		if _target != null:
			_call_for_help(_target.global_position)
		if not holds_position and _cover_phase == Cover.NONE and state == State.ENGAGE:
			_try_take_cover(close_cover_radius if _can_see and _target != null and global_position.distance_to(_target.global_position) < close_fight_range else -1.0)
			_hit_since_decide = false   # (this hit is why it's going: don't count it as being shot on the way)
	elif not health.is_dead:
		_bark("hurt", 0.5)
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
	if not puppet and _last_hit_from != Vector3.INF:
		_warn_friends()
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


## Just died: unaware friends close by, or ones that see it go down, turn toward roughly where it was shot from.
func _warn_friends() -> void:
	var space := get_world_3d().direct_space_state
	var chest := global_position + Vector3(0, 1.2, 0)
	var said := false   # (one "man down" is enough)
	for node in RaidScope.nodes(self, &"enemies"):
		var friend := node as Scav
		if friend == null or friend == self or friend.puppet or friend.faction != faction or friend.state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
			continue
		var d := friend.global_position.distance_to(global_position)
		if d > buddy_see_radius:
			continue
		if d > buddy_hear_radius:
			var eyes := friend.global_position + Vector3(0, 1.65, 0)
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eyes, chest, 1)).is_empty():
				continue
		friend.notice_near_miss(_last_hit_from)
		if not said:
			said = true
			friend._bark("man_down")


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
	if _crouched:
		flags |= NET_CROUCH
	if is_wounded():
		flags |= NET_WOUNDED
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
## Says a callout (`chance` of it, at most one per bark_cooldown); online the server passes it on to players.
func _bark(kind: String, chance := 1.0) -> void:
	if puppet or _bark_left > 0.0 or randf() > chance:
		return
	_bark_left = bark_cooldown
	play_bark(kind)
	barked.emit(kind)


## The callout's sound (puppets: the server's scav said it).
func play_bark(kind: String) -> void:
	var stream := _voice_line(kind)
	if stream != null and is_inside_tree():
		Effects.sound_at(get_tree().current_scene, stream, global_position + Vector3(0, 1.6, 0), -1.0, 0.03, _voice, 8.0, BARK_HEAR_RANGE)


## A random take of a callout: audio/voice/<kind>.wav, plus <kind>_2.wav, <kind>_3.wav... if they exist.
static var _voice_takes := {}


static func _voice_line(kind: String) -> AudioStream:
	if not _voice_takes.has(kind):
		var takes: Array[AudioStream] = []
		if VOICE.has(kind):
			takes.append(VOICE[kind])
		for i in range(2, 9):
			var path := "res://audio/voice/%s_%d.wav" % [kind, i]
			if not ResourceLoader.exists(path):
				break
			takes.append(load(path))
		_voice_takes[kind] = takes
	var options: Array[AudioStream] = _voice_takes[kind]
	return options.pick_random() if not options.is_empty() else null


func net_alerted() -> void:
	Effects.sound_at(get_tree().current_scene, ALERT_SOUND, global_position, -2.0, 0.05, 1.0, 6.0, BARK_HEAR_RANGE)


## Bash wind-up sound (puppets: the server's scav started one).
func net_bash_started() -> void:
	Effects.sound_at(get_tree().current_scene, BASH_SOUND, global_position, -4.0, 0.1, 0.8, 6.0, 30.0)


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
