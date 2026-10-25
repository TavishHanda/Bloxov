extends CharacterBody3D
## The AI's settings (everything set per scene: scav, Raider, sniper, Bon) and shared state, plus small helpers.
## The AI is one object built from a chain of scripts, each adding one part (split up in 0.14.6, no behaviour change):
## scav_base.gd -> scav_senses.gd (seeing, hearing, alerting others, voice) -> scav_movement.gd (paths, patrols,
## level of detail) -> scav_fight.gd (tactics, cover, shooting, melee, healing) -> scav.gd (class Scav: the
## per-frame brain, damage and death, online). Each part can use everything from the parts before it.

enum State { IDLE, ALERT, ENGAGE, DEAD, INVESTIGATE, SEARCH }

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
## After losing sight of you in a fight it still knows where you are for this long (seconds; heard you, saw you
## move): it heads for where you really are and spots you again the moment you're in view, e.g. through a window
## (0.12.36, owner: indoors it lost you as soon as you broke line of sight).
@export var track_time := 5.0
@export var track_range := 35.0
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
@export var accuracy_far := 0.27
@export var accuracy_range := 28.0
## (0.12.9, owner: too low; scavs bottom out at about 10%. 0.13.1, owner: far range buffed to 30% / 18%. 0.20.25, owner:
## "nerf the scav accuracy from far ... by like 10%, close is fine": 27% / 16%.)
@export var accuracy_long := 0.16
## Accuracy lost when the player is moving fast (sprinting).
@export var moving_target_penalty := 0.25
## Point blank (closer than this, meters): shots almost always hit.
@export var point_blank_range := 4.0
@export var point_blank_accuracy := 0.9
## Keeps at least this far from its target: closer and it backs off while shooting.
@export var min_distance := 1.5

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
## Never takes cover (Bon, 0.17.3, owner: "more aggro, never runs to cover"): no ducking to reload or when shot,
## no hiding when sniped, no playing safe when hurt; it walks at you shooting. It doesn't chase non-stop though
## (owner: "there needs to be some break"): after chase_burst_min-max seconds of chasing it stops for
## chase_pause_min-max seconds, standing and firing or (reposition_chance of the time) stepping a few meters to one
## side while firing (never just standing there: it keeps shooting), then comes on again.
@export var never_cover := false
## Bon (0.21.18, owner: he mustn't stray too far from his guards, or he can be lured off alone): while any of his
## guards are alive he won't chase, push or go after you more than this many metres from the nearest one; he stands
## and fires from there until they catch up. 0 = no such leash.
@export var guard_leash := 0.0
## Its first burst in a fight may kill you outright (Bon, 0.21.18; his guards too, through their leader). Everyone
## else's opening burst can't, bar a small chance (Player.opening_kill_chance).
@export var opening_can_kill := false
@export var chase_burst_min := 3.0
@export var chase_burst_max := 5.0
@export var chase_pause_min := 1.5
@export var chase_pause_max := 2.5
@export var reposition_chance := 0.5

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
## Trips out of its area (Bon and his guards, 0.12.36, owner: "maybe go into the bank or other buildings in town
## from time to time, once or twice per raid"): this many at most per raid, each to a loot spot in another building
## within excursion_range meters (the bank more often than not), then back home. The second one only happens
## second_excursion_chance of the time.
@export var excursions := 0
@export var excursion_range := 75.0
@export var second_excursion_chance := 0.5
## Share of its open-ground patrol stops just outside its area (0.12.36, owner: guards should patrol outside too).
@export var outside_patrol := 0.0
## Started inside a building (0.20.14, owner: AI spawn inside buildings and patrol around): this share of its patrol
## stops are that building's rooms (or a loot spot in it, on any floor); the rest are just outside round the
## building, so now and then it steps out and comes back.
@export var indoor_patrol := 0.8
## Scavs and Raiders are rivals (0.12.17, owner): they ignore each other, but never answer the other side's calls
## for help, warn it or team up with it. raider.tscn and boss.tscn are "raider".
@export var faction := &"scav"

@export_group("Voice")
## Callouts: how deep its voice is (Raiders and Bon lower) and at most one callout per this many seconds.
@export var voice_pitch := 1.0
@export var bark_cooldown := 4.0
## Its own set of callouts (0.20.4): audio/voice/<voice_set>/ ("bon"); "" = everyone's.
@export var voice_set := ""
## While you reload or heal it pushes toward you (this fraction of move_speed) instead of strafing in place.
@export var push_speed := 0.8
## Chasing (0.12.33, owner: "they never push when in range to actually shoot"; cover is for when it sees you but
## you're too far to hit). Within chase_range it walks at you shooting (push_speed), all the way in (0.12.36,
## owner: "chase all the way into you"; the 0.12.34 dash-and-stop is gone: "they can just be walking and
## shooting"). Only chase_cover_chance of the time it runs to cover instead, and from cover in this range it peeks
## once, then comes out to chase. Badly hurt AI don't chase: they fight from cover.
@export var chase_range := 30.0
@export var chase_stop := 2.0
@export var chase_cover_chance := 0.1

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
## The shot sound (its gun's: GunSounds, set from the loadout).
var shot_sound: AudioStream = GunSounds.DEFAULT_SHOT
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
## Always on its body, on top of the rolled loot (Bon, the boss: the bunker key).
@export var extra_drops := PackedStringArray()
## Gear it wears (ItemDB ids, "" = none; 0.14.2, owner): the armor protects its body and the helmet its head the same
## way they protect a player, wear down from hits the same way, and end up on its body as they are.
@export var armor := ""
@export var helmet := ""
## Item id of that gun.
@export var weapon_drop := ""
## What it carries (0.15.5, AILoadouts): a loadout table ("scav", "raider": a random gun each spawn) or a gun id.
## The gun changes how it shoots (AILoadouts.STYLES) and becomes its weapon_drop. "" = keep the scene's numbers.
@export var loadout := ""
## Attachments its gun always has when dropped (Bon: a scope and a grip), and the chance of one random extra.
@export var drop_parts := PackedStringArray()
@export_range(0.0, 1.0) var drop_part_chance := 0.0

@export_group("Look")
## Which gun model it holds (HeldGun.MODELS key; "" = the one drawn into its model).
@export var held_model := ""
## The gun it carries (from its loadout; "" = the scene's own numbers). Sent to puppets online.
var carried_gun := ""
@export var burst_color := Color(0.33, 0.38, 0.24)

@onready var health: Health = $Health
@onready var model: Node3D = $Model
@onready var leg_l: Node3D = $Model/LegL
@onready var leg_r: Node3D = $Model/LegR
@onready var muzzle: Node3D = $Model/Gun/Muzzle
@onready var muzzle_flash: Node3D = $MuzzleFlash

var state := State.IDLE
var _state_time := 0.0
var _lost_sight_time := 0.0
## Its patrol area (Scavs 2.0, owner: AI stays where players learn to expect it). Set by the spawner from the
## map's AI zones: while unaware it only patrols within `home_radius` meters of `home_center`. 0 = roams the
## whole map (the few random roamers, and every AI on the test map). Fights can still pull it out.
var home_center := Vector3.ZERO
var home_radius := 0.0
## Parts of its area it keeps out of: Vector3(x, radius, z) circles (0.12.31, owner: the town's scavs stay away
## from the town hall and the bank, where Bon's guards and the Raiders are), and how far out (fraction of
## home_radius) its open-ground patrol stops sit (the town's scavs patrol round the edges of town).
var home_avoid: Array = []
## The room spots of the building it started in (the spawner's indoor markers with its `building`); empty = none.
var indoor_rooms: Array[Vector3] = []
## Duo partner or boss guard: who it follows around while patrolling (null = it leads itself), and where it
## walks relative to them (right/back in their facing).
var leader: Scav = null
const NET_WOUNDED := 64
var puppet := false
var _net_flags := 0


## Within `leash` meters of its patrol area (always true without one).
func _near_home(point: Vector3) -> bool:
	var boss := leader if leader != null and is_instance_valid(leader) else self
	if boss._trip_point != Vector3.INF and _flat(point - boss._trip_point).length() <= leash:
		return true   # out on a trip (a fight there doesn't send it straight home)
	return home_radius <= 0.0 or _flat(point - home_center).length() <= home_radius + leash


## Below hurt_fraction (or wounded): plays safer, no pushing, flanking or chasing (0.12.32).
func is_hurt() -> bool:
	if never_cover:
		return false   # (never plays safe)
	return is_wounded() or (not health.is_dead and health.current <= health.max_health * hurt_fraction)


## Badly hurt: limps (puppets: the server's scav is).
func is_wounded() -> bool:
	if puppet:
		return (_net_flags & NET_WOUNDED) != 0
	return not health.is_dead and health.current <= health.max_health * wounded_fraction


## The fight brain (0.12.29, owner: the AI felt "cluttered and messy"; built like shipped shooters' AI). It picks
## ONE plan (a Tactic) and sticks to it until the plan is done or something real changes (it gets shot in the open,
## loses sight of you, you start reloading, you get out of range); every move it makes serves that plan.
## Before, each behavior grabbed control on its own every frame, so plans flip-flopped.
## Reflexes still come first: a bash up close, backing off when you're in its face.
enum Tactic { NONE, COVER, STAND, PUSH, FLANK, ADVANCE, PURSUE, SUPPRESS, CHASE }
var tactic := Tactic.NONE


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## A fight just started and it hasn't fired its first volley yet: whatever it sees first, it shoots at
## (0.17.9, owner: a Raider ran off the moment it saw him; "first instinct should always be shoot").
var _opening := false
## Who it has fired its opening burst at in this fight (scav_fight.gd _start_burst).
var _opened_on: Node = null


func _set_state(new_state: State) -> void:
	_hunting = false
	tactic = Tactic.NONE
	if new_state != State.INVESTIGATE:
		_answering_call = false
		_alarmed = false
	state = new_state
	_state_time = 0.0
	_opening = new_state == State.ENGAGE
	if _opening:
		_opened_on = null   # (a new fight: its next burst is an opening one again, scav_fight.gd)
	_lost_sight_time = 0.0


## Inside its patrol area (a little slack at the edge); always true for a roamer.
func _in_home(point: Vector3) -> bool:
	if home_radius <= 0.0:
		return true
	for circle: Vector3 in home_avoid:
		if Vector2(point.x - circle.x, point.z - circle.z).length() <= circle.y:
			return false
	return _flat(point - home_center).length() <= home_radius + (0.0 if holds_position else 4.0)
var _hunting := false
## Heading over because another AI called for help (jogs instead of walking).
var _answering_call := false
## Investigating a gunshot: hurries.
var _alarmed := false


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
