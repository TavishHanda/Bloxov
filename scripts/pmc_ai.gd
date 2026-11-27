class_name PmcAI
extends Scav
## AI PMC brain (0.36.5, AI PMCs piece 6a): what a bot does when it isn't fighting. scenes/pmc_ai.tscn uses it; scavs,
## Raiders, snipers and Bon never do (their behaviour is locked, owner), so all of this lives here as overrides.
## Raid plan: it waits a moment, then loots 2-4 places (buildings, by their containers' `place`), the nearest first,
## then picked by what their loot is worth (best ~3x as likely as poorest), searching 2-4 containers at each.
## 0.36.14 (owner's pick, 2026-11-17): "steer around AI, fight if they meet". Unaware, it keeps apart from other AI
## as in 0.36.9 (`_keep_apart`, the "Keep apart" section: non-bot AI 30-40 m, other bots 60 m, for the places it
## picks, the way there, while moving and looting, the noises it walks over to and the extract it takes). When one does
## meet it, it fights with the 0.36.10-13 rules: the Scav brain, its shots heard like a player's (`_shot_noise`), and
## against AI only (never with a real player in the fight, `_player_in_fight`): threat by kind (THREAT_*), no fight
## started with a group it spots (`_group_to_avoid`) or with a far scav (`_far_to_leave`), and outnumbered or hurt it
## breaks off (`_check_break_off`, Plan.FLEE, `_run_off`), heals and plans again. Never the boss's area.
## 0.36.7: a finished search opens the container's lid and takes one item (`_on_search_done`); at its leave time, or
## hurt with no heals left, it jogs to an extract, stands in it and is gone (`wants_to_leave`, `_leave_raid`).

## (0.36.5, owner approved) The raid plan.
const START_WAIT_MIN := 3.0
const START_WAIT_MAX := 8.0
const PLACES_MIN := 2
const PLACES_MAX := 4
const SEARCHES_MIN := 2
const SEARCHES_MAX := 4
const SEARCH_TIME_MIN := 4.0
const SEARCH_TIME_MAX := 8.0
## Walks (not jogs) this close to where it's going, once it's indoors.
const WALK_NEAR := 15.0
## A place's pick weight runs from this (poorest loot) to VALUE_WEIGHT_MAX (best).
const VALUE_WEIGHT_MIN := 1.0
const VALUE_WEIGHT_MAX := 3.0
## (0.36.12, numbers pending the owner's OK) How much threat each other living AI is: what it weighs when it spots a
## group or counts the enemies in a fight.
const THREAT_SCAV := 1.0
const THREAT_RAIDER := 2.0
const THREAT_SNIPER := 1.0
const THREAT_BOSS := 2.0
const THREAT_BOT := 1.0
## (0.36.12, pending) Unaware, it doesn't start a fight with a group it spots (other AI with GROUP_THREAT or more within
## GROUP_SPREAD m of the one it spotted) that isn't after it yet.
const GROUP_THREAT := 2.0
const GROUP_SPREAD := 15.0
## (0.36.12, pending) Breaking off a fight with AI (never with a player in it: then it fights as before). Outnumbered
## (the enemies fighting it, or within BREAK_NEAR m in its view, weigh BREAK_THREAT or more) or hurt (under BREAK_HURT
## of its health, with someone fighting it), it runs at full speed to a spot FLEE_MIN-FLEE_MAX m from them that keeps
## FLEE_CLEAR m from every other AI (out of their sight if it can), heals there, and plans again.
const BREAK_THREAT := 2.0
const BREAK_NEAR := 30.0
const BREAK_HURT := 0.5
const FLEE_MIN := 40.0
const FLEE_MAX := 70.0
const FLEE_CLEAR := 30.0
## (0.36.12, pending) Running off, it only turns to fight an enemy it sees within FLEE_FIGHT m, or a shot from that
## close; then it fights that fight out (no breaking off again until it is over). A run lasts at most FLEE_GIVE_UP s,
## and after one it doesn't break off again for BREAK_COOLDOWN s.
const FLEE_FIGHT := 12.0
## (0.39.14, owner OK pending) It doesn't break off at all while one this close has it in sight: running with its back to
## a shooter that near got it killed (5 of 18 bot deaths in a raid check were bots shot running off); it fights.
const NO_BREAK_NEAR := 30.0
const FLEE_GIVE_UP := 30.0
const BREAK_COOLDOWN := 10.0
## (0.36.12, pending) Got there with someone still after it within FLEE_MIN m: it runs on to another spot, at most
## FLEE_LEGS runs in all; it only patches up once nobody after it is that close.
const FLEE_LEGS := 3
## (0.36.12, tuning) A real player within its sight range, or one that hit it in the last PLAYER_MEMORY s, means a
## player is in the fight: none of the new fight rules apply. It looks at the fight every BREAK_CHECK s.
## Unaware, it doesn't open fire on a scav, Raider, sniper or Bon farther than this that isn't after it (0.36.13).
const BOT_OPEN_FIRE := 25.0
## Hits from scavs, Raiders, snipers and Bon do this share of their damage to an AI PMC (0.36.13; players' and other
## bots' hits are untouched). A hidden handicap so a lone bot lasts among ~36 AI. PENDING THE OWNER'S OK.
const AI_DAMAGE_TO_BOT := 1.0
static var ai_damage_to_bot := -1.0   # (the raid report's override for every map; -1 = the map's own, MAP_TUNING)
const PLAYER_MEMORY := 10.0
const BREAK_CHECK := 0.25
## Steering around other AI (0.36.14, owner: "steer around AI, fight if they meet"; the 0.36.9 keep-apart numbers).
const AI_PLACE_CLEAR := 40.0     # no non-bot AI this close to a place it picks
const BOT_CLEAR := 60.0          # other bots: places, routes and on the move
const AI_ROUTE_CLEAR := 30.0     # no non-bot AI this close to the way there
const AI_NEAR := 30.0            # on the move / looting: a non-bot AI this close and it turns away
const AFTER_FIGHT_CLEAR := 40.0  # after a fight: a non-bot AI this close and it moves away first
const ROUTE_STEP := 5.0
const ESCAPE_GAIN := 0.5
const PASS_FLOOR := 20.0
const PASS_FLOOR_BOT := 40.0
const HELD_UP := 10.0
## How far either side of the middle of its chest cover has to hide it (its body is 0.8 m wide).
const COVER_SHOULDER := 0.35
## (0.39.2 fix: in playtests and the raid report a bot boxed in by other AI could stand on one spot for minutes, every
## place and way "too busy") Held up this long, it stops steering round AI for COMMIT_TIME s and goes to a place
## anyway, fighting whoever it meets (the owner's rule: "steer around AI, fight if they meet"). Tuning, not the
## owner's numbers.
const HOLD_GIVE_UP := 12.0
const COMMIT_TIME := 30.0
const LOOK_AHEAD := 3.0
const HURRY_TIME := 6.0
const CHECK_EVERY := 1.0         # seconds between its looks at whether it is indoors
const SHOT_CARE_RANGE := 80.0    # gunshots this close: curious bots go, cautious ones steer away
const CURIOUS_CHANCE := 0.5
## Awareness (0.39.21, owner approved 2026-11-22; PMC bots only, noises a PLAYER made). Gunshots reach PLAYER_SHOT_HEARING
## times the gun's noise (AK 35 -> ~88 m, sniper 60 -> 150 m, a suppressor halves it); steps PLAYER_STEP_HEARING times
## (walk 20 m, sprint 56 m, crouch 3 m; under SILENT_BELOW, prone, nothing). Reloads, doors and heals: Network.QUIET_NOISES.
const PLAYER_SHOT_HEARING := 2.5
const PLAYER_STEP_HEARING := 2.0
const SILENT_BELOW := 1.0
const THROUGH_WALL := 0.6         # a wall in the way: the noise carries this share as far
const GUESS_PER_M := 0.1          # how far off its guess of the spot is, per meter away (at least GUESS_MIN)
const GUESS_MIN := 0.5
const TURN_LOOK := 0.65           # Scav's look-at-sound timer: >0.6 is the "huh?" pause, so ~0.05 s, then it turns
const SHOT_REACT_RANGE := 50.0    # a player's shot this close: every bot reacts (cover + watch; curious ones go look)
const WATCH_SHOT := 8.0
const STEP_HOLD_RANGE := 20.0     # steps coming its way this close: it stops and aims that way
const STEP_MEMORY := 3.0
const WATCH_STEPS := 6.0
const EAR_TIME := 20.0            # after hearing a player, spots toward that noise EAR_SPOT_MULT as long
const EAR_SPOT_MULT := 0.5
const EAR_CONE_COS := 0.766       # within 40 degrees of the noise
const COVER_LOOK := 10.0
## Shot at (0.39.21, owner picked "suppression + hide", 2026-11-22). A player's bullet passing within near_miss_radius
## (5 m, pmc_ai.tscn) or hitting it pins it down for SUPPRESS_TIME s: it ducks into cover first, stays down there
## instead of peeking, and its shots land SUPPRESSED_AIM as often. Hit by someone it can't see, it gets into cover
## from them and waits HIDE_WAIT s watching that way, instead of walking toward them in the open.
const SUPPRESS_TIME := 3.0
const SUPPRESSED_AIM := 0.7
const HIDE_WAIT := 10.0
## Routes (0.39.29, owner 2026-11-23: "a bunch of paths then randomizing between them"; PmcRoutes). A bot takes one at
## random of those starting within ROUTE_START_NEAR m of where it spawned (none: the nearest start's), walks it, loots its
## stops and leaves by its extract. Other AI in the way: it waits in cover (within ROUTE_HIDE m) up to ROUTE_WAIT s, then
## carries on. A stop it can't reach after ROUTE_TRIES goes is skipped.
const ROUTE_START_NEAR := 80.0
const ROUTE_WAIT := 20.0
const ROUTE_HIDE := 12.0
const ROUTE_TRIES := 3
const ROUTE_STOP_REACHED := 6.0
## In a fight with another AI (not a player), it doesn't run after it more than CHASE_LEASH m from where the fight
## started: it fights from there, from cover (owner 2026-11-23: fight and kill them, but no runs across the open).
const CHASE_LEASH := 15.0
## Every foe farther than this (m): it hides from them instead of breaking off across the open (snipers).
const BREAK_FAR := 45.0
## Tuning (not the owner's numbers): a wait of RETRY_WAIT s when nowhere is open, containers of one place within
## PLACE_SPREAD m of each other form one place.
const RETRY_WAIT := 3.0
const PLACE_SPREAD := 25.0
const SHOT_MEMORY := 60.0
const _PLACES_META := &"pmc_places"
## (0.36.7, owner approved) Looting: one whole stack per container, the most valuable one, at most this many a raid.
const MAX_TAKEN := 4
## (0.36.7, owner approved) Extracting: it leaves between these shares of the raid's full length (a raid without a
## known length counts as DEFAULT_RAID_LENGTH s from its spawn), or early when under LEAVE_HURT of its health with no
## heals left and not in a fight. It heads for the nearest open extract.
const LEAVE_MIN := 0.50
const LEAVE_MAX := 0.85
static var leave_window := Vector2(LEAVE_MIN, LEAVE_MAX)   # (the raid report tries others: BOT_LEAVE=min,max)
const LEAVE_HURT := 0.4
## (0.36.15, pending the owner's OK) A raid this hot sends it home: after breaking off this many fights with AI it heads
## for an extract, as a player would (0 = off). The raid report tries values with BOT_BREAKS=n.
const BREAKS_TO_LEAVE := 0
static var breaks_to_leave := -1   # (the raid report's override for every map; -1 = the map's own, MAP_TUNING)
## (0.36.15, pending the owner's OK) Per-map tuning, by the map's `map_name`: a busy map (Frontlines, 36 AI) gets the
## hidden damage handicap and the leave-after-breaks rule; other maps use AI_DAMAGE_TO_BOT and BREAKS_TO_LEAVE.
const MAP_TUNING := {"Bloxov Frontlines": {"ai_damage": 0.6, "breaks_to_leave": 2}}
## This bot's own values (set in `_ready` from MAP_TUNING and the report's overrides).
var ai_damage := AI_DAMAGE_TO_BOT
var leave_after_breaks := BREAKS_TO_LEAVE
## (0.36.15 trials) The keep-apart steering on (true) or off (the 0.36.13 walk-straight-in). Report: BOT_APART=0.
static var keep_apart := true
const DEFAULT_RAID_LENGTH := 600.0
## Tuning (not the owner's numbers): wait this long before looking for an extract again after finding none, and give
## up on a walk to one after this long.
const EXIT_RETRY := 5.0
const EXIT_GIVE_UP := 120.0

enum Plan { START, TRAVEL, SEARCH, HOLD, EXIT, EXTRACT, FLEE }
var plan := Plan.START
var _plan_wait := 0.0
## The place it's at or heading to ({} = none: a spot away from someone, or holding).
var place := {}
var _place_container: Node3D = null
var _searches_left := 0
var _places_left := 0
## Every place it has started on this raid (for checks and the proof tool), and the containers it has searched.
var visited: Array[String] = []
var _searched := {}
var _bad := {}
## Rolled once: walks over to gunshots (true) or steers clear of them.
var curious := true
var _indoors := false
var _apart_left := 0.0
var _route_check_left := 0.0
var _fought := false
## Which of the six characters it is (0.38.8, owner 2026-11-20/21): Characters.ai_pick(character_seed), which gives
## its character, skin and level (5-15). Its own id (the server's AI), unless it is a puppet given the server's id
## (`dress_as_character`) so it wears the same character. `character` is that pick.
var character_seed := 0
var character := {}
## Its character's search time (KORR searches faster).
var search_mult := 1.0
var _dressed := false
var _seeded := false

var turned_away := 0
var _last_gap := INF
var _flee_wait_left := 0.0
var _held_for := 0.0
var _commit_left := 0.0
var _hurry_left := 0.0
var _indoor_left := 0.0
var _seen_state := State.IDLE
var _shot_at := Vector3.INF
var _shot_age := 0.0
## Awareness (0.39.21): its own dice (not the global ones), where it last heard a player and for how long it's sharp that
## way, the last step's distance, and the spot it's stopped to watch.
var _ears := RandomNumberGenerator.new()
var _ear_at := Vector3.ZERO
var _ear_left := 0.0
var _step_dist := INF
var _step_age := INF
var _watch_at := Vector3.ZERO
var _watch_left := 0.0
var _look_after := false
var _step_trait := 1.0   # its character's "hearing" (footsteps) trait
var _suppressed_left := 0.0
var _hit_far_left := 0.0      # just hit by an AI farther than BREAK_FAR (a sniper): hide from it
var _hit_unseen_left := 0.0   # just hit by a player it couldn't see: hide from them (for this long it still may)
## Its route (0.39.29): the map's name, the route ({} = none: it plans as before), its stops ({pos} or {pos, place}),
## the stop it's on and how many goes it has had at it, its extract, the cover spot it waits at while blocked (INF =
## none), whether it's waiting, and where its current fight started (CHASE_LEASH).
var _map_name := ""
var route := {}
var _route_stops: Array = []
var _route_i := 0
var _route_tries := 0
var _route_extract: Node3D = null
var _route_picked := false
var _hide_spot := Vector3.INF
var _route_blocked := false
var _fight_at := Vector3.INF
## 0.36.7: the raid's full length in seconds (the server sets it; 0 = DEFAULT_RAID_LENGTH), the seed of its leave
## roll (0 = unseeded), and when it leaves: seconds after it spawned.
var raid_length := 0.0
var leave_seed := 0
var leave_at := -1.0
var _age := 0.0
var _taken := 0
var _exit_retry := 0.0
## The extract it's heading to or standing in, and how much of its time is left.
var extract: Node3D = null
var _extract_left := 0.0
## It walked out of the raid through an extract (tests, the proof tool).
var left_raid := false
## 0.36.12: places it dropped (id -> its age when it may pick them again), the fight it broke off (the enemies it ran
## from), and counts for tests and the report: places dropped, fights broken off.
var _flee_from: Array[Scav] = []
var _flee_repicked := false
var _flee_legs := 0
var _holding_ground := false
var _break_cooldown := 0.0
var _break_check := 0.0
var _since_player_hit := INF
var _hit_now := false
var drops := 0   # (0.36.12 place drops: always 0 since 0.36.14, kept for the raid report)
var breaks := 0


## Its character's traits on the AI's own numbers (a player's stat -> the AI's nearest one). The AI has no stamina,
## doesn't reload, jump or swap guns, so those traits do nothing on it; passives other than VEGA's Light Feet (in
## "steps") and PATCH's rank-3 med speed (in "heal_time") don't either.
func apply_character(mult: Dictionary) -> void:
	var m := func(stat: String) -> float: return float(mult.get(stat, 1.0))
	move_speed *= m.call("move") * m.call("sprint")   # (its move speed is its run; walking and patrol are shares of it)
	hearing_mult *= m.call("hearing")
	_step_trait = m.call("hearing")   # (0.39.21: a player's steps too)
	aim_time *= m.call("ads")
	# More recoil / spread = fewer hits: its hit chance goes down by the same share (and up for less).
	accuracy_near = minf(accuracy_near / (m.call("recoil") * m.call("hip_spread")), 1.0)
	accuracy_far /= m.call("recoil") * m.call("aim_spread")
	accuracy_long /= m.call("recoil") * m.call("aim_spread")
	burst_interval /= m.call("auto_rate")
	heal_time *= m.call("heal_time")
	search_mult *= m.call("search")
	footstep_range *= m.call("steps")


# ---- Fighting like a player (0.39.14, owner 2026-11-22: "standing still, not shooting back that much, not taking
# proper cover (like cover over a tree)"). Hooks of the scav brain; scavs, Raiders and bosses keep theirs. ----------

## Cover has to hide its head and both shoulders, not just the middle of its chest (a tree trunk did, with both
## shoulders showing). 2 standing, 1 crouched, 0 not hidden.
func _hides_at(space: PhysicsDirectSpaceState3D, eyes: Vector3, spot: Vector3) -> int:
	var side := _flat(spot - eyes).normalized().cross(Vector3.UP) * COVER_SHOULDER
	var hidden := func(points: Array) -> bool:
		for p: Vector3 in points:
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(eyes, p, 1)).is_empty():
				return false
		return true
	var chest := spot + Vector3(0, 1.3, 0)
	if hidden.call([chest, chest + side, chest - side, spot + Vector3(0, 1.65, 0)]):
		return 2
	var low_head := spot + Vector3(0, 1.71 * CROUCH_HEIGHT + 0.2, 0)
	var low_chest := spot + Vector3(0, 1.71 * CROUCH_HEIGHT - 0.3, 0)
	if hidden.call([low_head, low_chest + side, low_chest - side, spot + Vector3(0, 0.5, 0)]):
		return 1
	return 0


## It keeps shooting at you while it runs to cover.
func _fires_on_cover_runs() -> bool:
	return true


## Hurt and lost sight of you: it gets into cover first instead of waiting out in the open.
func _wait_for_target(delta: float) -> Vector3:
	if is_hurt() and not holds_position and _cover_cooldown_left <= 0.0 and is_instance_valid(_target):
		_try_take_cover()
		if _cover_phase != Cover.NONE:
			return Vector3.ZERO   # (the cover steps take over from the next frame)
	return super(delta)


## Puppets (looks only, never on the server): wear the character the server's AI with id `seed_value` is. Call before
## it joins the tree (its model is swapped for that character's).
func dress_as_character(seed_value: int) -> void:
	character_seed = seed_value
	_seeded = true
	var pick := Characters.ai_pick(seed_value)
	PlayableModels.replace(self, pick["id"], pick["skin"])
	_dressed = true


## Dressed as its character: that model's skin is its whole look (no operator outfit on top).
func pick_look(seed_value: int) -> void:
	if not _dressed:
		super(seed_value)


func _ready() -> void:
	if not _seeded:
		character_seed = get_instance_id()
	character = Characters.ai_pick(character_seed)
	apply_character(Characters.multipliers(character["state"], character["id"]))
	super()
	if puppet:
		return
	_ears.seed = hash(character_seed) ^ 0x5eed   # (0.39.21: its hearing's own dice)
	add_to_group(&"pmc_bots")   # (0.36.10: how every other AI finds the bots it may fight, Scav._closest_rival)
	curious = randf() < CURIOUS_CHANCE
	_places_left = randi_range(PLACES_MIN, PLACES_MAX)
	_plan_wait = randf_range(START_WAIT_MIN, START_WAIT_MAX)
	_indoor_left = randf() * CHECK_EVERY
	_roll_leave_time()
	_apply_map_tuning()


## Its map's MAP_TUNING (the raid's root carries the map's `map_name` meta, RaidMap.load_map), then the report's overrides.
func _apply_map_tuning() -> void:
	var node: Node = self
	while node != null and not node.has_meta("map_name"):
		node = node.get_parent()
	_map_name = String(node.get_meta("map_name")) if node != null else ""
	var tuning: Dictionary = MAP_TUNING.get(_map_name, {})
	ai_damage = float(tuning.get("ai_damage", AI_DAMAGE_TO_BOT))
	leave_after_breaks = int(tuning.get("breaks_to_leave", BREAKS_TO_LEAVE))
	if ai_damage_to_bot >= 0.0:
		ai_damage = ai_damage_to_bot
	if breaks_to_leave >= 0:
		leave_after_breaks = breaks_to_leave


func _physics_process(delta: float) -> void:
	if state != State.DEAD and not puppet:
		_age += delta
		_exit_retry -= delta
		_shot_age += delta
		_indoor_left -= delta
		if _indoor_left <= 0.0:
			_indoor_left = CHECK_EVERY
			_look_indoors()
		_hurry_left -= delta
		_commit_left -= delta
		if state in [State.ALERT, State.ENGAGE]:
			_fought = true
		_apart_left -= delta
		if _apart_left <= 0.0:
			_apart_left = CHECK_EVERY
			_keep_apart()
		_break_cooldown -= delta
		_since_player_hit += delta
		_break_check -= delta
		if _break_check <= 0.0:
			_break_check = BREAK_CHECK
			_check_break_off()
	super(delta)
	if not puppet and state != State.DEAD:
		_update_watch(delta)
		_update_shot_at(delta)
	if state != _seen_state and not puppet:
		if state == State.IDLE and _seen_state != State.IDLE:
			_holding_ground = false
			_set_plan(Plan.HOLD, 0.3)   # (back from a fight or a noise: plans again)
		_seen_state = state


## A PMC (0.36.10, owner): it fights every other AI, bots too, and every other AI fights it.
func counts_as_pmc() -> bool:
	return true


func out_of_fight() -> bool:
	return left_raid or super()


## A noise it hears (0.36.11: shots from every other AI too). Curious bots go and look like any scav; cautious ones, and
## any on their way out, note where it was and steer away from there when they pick a place.
## 0.39.21 (owner: "really good awareness"): a noise a PLAYER made goes to `_hear_player` instead (sharper ears, see
## "Awareness"); noises from other AI are heard exactly as before.
func hear_noise(pos: Vector3, radius: float, gunshot := false) -> void:
	if puppet:
		return
	if _player_made(pos):
		if radius >= SILENT_BELOW:
			_hear_player(pos, radius * (PLAYER_SHOT_HEARING if gunshot else PLAYER_STEP_HEARING * _step_trait), gunshot)
		return
	var loud := gunshot or radius >= alarm_noise
	if plan == Plan.FLEE and state == State.IDLE:   # (0.36.12: running off, it doesn't go and look at anything)
		if loud:
			FightBudget.stir(self, pos)
		return
	if loud and (not curious or plan in [Plan.EXIT, Plan.EXTRACT]):   # (0.36.7: on its way out it doesn't go and look)
		FightBudget.stir(self, pos)
		if global_position.distance_to(pos) <= SHOT_CARE_RANGE:
			_shot_at = pos
			_shot_age = 0.0
		return
	super(pos, radius, gunshot)


## A player's quieter noise that only the AI PMCs listen for (0.39.21): a reload, a door, a heal. `reach` is in meters.
func hear_player_noise(pos: Vector3, reach: float) -> void:
	if puppet:
		return
	_hear_player(pos, reach, false)


# --- Awareness (0.39.21, owner approved 2026-11-22): what it does with a noise a player made --------------------------

## A player is standing where the noise came from (their steps, shots, knife; the server's proxies count).
func _player_made(pos: Vector3) -> bool:
	for node in RaidScope.nodes(self, &"player"):
		var body := node as Node3D
		if body != null and _flat(body.global_position - pos).length() < 1.5 and absf(body.global_position.y - pos.y) < 2.5:
			return true
	return false


## Heard a player `reach` meters off at most (less through a wall). It snaps round, then: a gunshot close by gets it into
## cover watching that way (curious ones go and look instead); steps coming its way make it stop and aim that way; any
## other noise it jogs over to check. Where it thinks the noise was is off by about 1 m per 10 m.
func _hear_player(pos: Vector3, reach: float, gunshot: bool) -> void:
	var dist := global_position.distance_to(pos)
	if dist > reach:
		return
	if dist > reach * THROUGH_WALL and _wall_between(pos):
		return
	if gunshot:
		FightBudget.stir(self, pos)
	if plan == Plan.FLEE and state == State.IDLE:
		return
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		return
	var spread := maxf(GUESS_MIN, dist * GUESS_PER_M)
	var guess := pos + Vector3(_ears.randf_range(-1.0, 1.0), 0.0, _ears.randf_range(-1.0, 1.0)).normalized() * _ears.randf() * spread
	_ear_at = guess
	_ear_left = EAR_TIME
	_looting_left = 0.0
	if gunshot:
		var leaving := plan in [Plan.EXIT, Plan.EXTRACT]
		if curious and not leaving:
			_go_look(guess)
		elif dist <= SHOT_REACT_RANGE:
			_watch(guess, WATCH_SHOT, false, true)
		else:
			_shot_at = pos
			_shot_age = 0.0
		return
	var closing := _step_age < STEP_MEMORY and dist < _step_dist - 0.3
	_step_dist = dist
	_step_age = 0.0
	if _watch_left > 0.0:
		_watch_at = guess   # (already stopped and watching: it keeps its aim on the noise)
		return
	if closing and dist <= STEP_HOLD_RANGE:
		_watch(guess, WATCH_STEPS, true, false)
		return
	_go_look(guess)


## Jogs over to check where it heard something, after a quick turn toward it.
func _go_look(guess: Vector3) -> void:
	_watch_left = 0.0
	_goal = guess
	var to_sound := _flat(guess - global_position)
	if state != State.INVESTIGATE or (to_sound.length() > 0.1 and _flat(-global_basis.z).normalized().dot(to_sound.normalized()) < 0.5):
		_heard_at = guess
		_look_at_sound_left = TURN_LOOK
	if state != State.INVESTIGATE:
		_set_state(State.INVESTIGATE)
	_alarmed = true   # (jogs, not the scavs' slow walk)


## Stops (or first gets into cover, `cover`) and watches `at` for `time` s, quicker to spot anyone there; then it goes and
## looks (`then_look`) or carries on with its plan.
func _watch(at: Vector3, time: float, then_look: bool, cover: bool) -> void:
	_watch_at = at
	_watch_left = time
	_look_after = then_look
	_heard_at = at
	_look_at_sound_left = TURN_LOOK
	var spot := _cover_from(at) if cover else Vector3.INF
	if spot != Vector3.INF:
		_goal = spot
		if state != State.INVESTIGATE:
			_set_state(State.INVESTIGATE)
		_alarmed = true
		return
	_goal = at
	if state != State.SEARCH:
		_set_state(State.SEARCH)


## Each frame (after the brain): while watching, it stands facing the noise instead of the scavs' look-around spin.
func _update_watch(delta: float) -> void:
	_ear_left -= delta
	_step_age += delta
	if _watch_left <= 0.0:
		return
	if state == State.INVESTIGATE:
		return   # (still on its way to cover)
	if state != State.SEARCH:
		_watch_left = 0.0
		return
	_watch_left -= delta
	_face(_flat(_watch_at - global_position), delta, 12.0)
	if _watch_left <= 0.0:
		if _look_after:
			_go_look(_watch_at)
		else:
			_set_state(State.IDLE)


## A spot within COVER_LOOK m that hides it from someone at `threat` (the far side of a wall, trunk, car...), nearest
## walk first; INF if there isn't one.
func _cover_from(threat: Vector3) -> Vector3:
	var eyes := threat + Vector3(0, 1.6, 0)
	var space := get_world_3d().direct_space_state
	var away := _flat(global_position - threat).normalized()
	var chest := global_position + Vector3(0, 1.0, 0)
	var best := Vector3.INF
	var best_walk := INF
	for i in 16:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 16.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + dir * COVER_LOOK, 1, [get_rid()]))
		if hit.is_empty():
			continue
		var behind: Vector3 = hit.position + away * 0.9 - dir * 0.3
		var spot := AINav.closest(self, Vector3(behind.x, global_position.y, behind.z))
		if spot == Vector3.ZERO or _flat(spot - behind).length() > 1.5:
			continue
		var hides := _hides_at(space, eyes, spot)
		if hides == 0:
			continue
		var walk := AINav.path_length(AINav.path(self, global_position, spot)) + (3.0 if hides == 1 else 0.0)
		if walk <= COVER_LOOK * 1.6 and walk < best_walk:
			best = spot
			best_walk = walk
	return best


## A wall (or a shut door) between its head and the noise: the noise only carries THROUGH_WALL as far.
func _wall_between(pos: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.6, 0), pos + Vector3(0, 1.0, 0), 1 | Door.LAYER, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Pinned down or hit from out of sight (see SUPPRESS_TIME): runs after the brain each frame.
func _update_shot_at(delta: float) -> void:
	_suppressed_left -= delta
	_hit_unseen_left -= delta
	_hit_far_left -= delta
	if state != State.ENGAGE or _target == null or not is_instance_valid(_target):
		return
	if ((_hit_unseen_left > 0.0 and not _can_see) or _hit_far_left > 0.0) and _cover_phase == Cover.NONE:
		_hit_unseen_left = 0.0
		_hit_far_left = 0.0
		_hide_from_unseen()
		return
	if _suppressed_left <= 0.0:
		return
	match _cover_phase:
		Cover.HOLDING:
			_cover_hold_left = maxf(_cover_hold_left, 0.2)   # stays down while the bullets keep coming
		Cover.PEEKING:
			if _shots_left <= 0:
				_cover_phase = Cover.MOVING   # ducks back in
		Cover.NONE:
			if _cover_cooldown_left <= 0.0:
				_try_take_cover()
				if _cover_phase != Cover.NONE:
					tactic = Tactic.COVER


## Hit by someone it can't see: cover from them (farther off is fine), then it waits there HIDE_WAIT s watching where
## the shot came from before it goes looking (the scavs' "sniped from beyond its range" run, for any distance).
func _hide_from_unseen() -> void:
	var spot := _find_cover(cover_search_radius * 2.0)
	if spot == Vector3.INF:
		return
	_cover_point = spot
	_cover_low = _found_low
	_cover_phase = Cover.MOVING
	_peeks_left = 0
	_peek_point = global_position
	_note_move_start()
	_bark("cover", 0.35)
	_fled_left = HIDE_WAIT
	_cover_cooldown_left = cover_cooldown
	tactic = Tactic.COVER


## Pinned down, its shots land SUPPRESSED_AIM as often.
func hit_chance(dist: float) -> float:
	return super(dist) * (SUPPRESSED_AIM if _suppressed_left > 0.0 else 1.0)


## For EAR_TIME s after hearing a player, it spots anyone toward that noise twice as fast.
func _spotting(delta: float, to_target: Vector3, dist: float, mult: float) -> bool:
	if _ear_left > 0.0 and _target != null:
		var to_ear := _flat(_ear_at - global_position)
		var flat_target := _flat(to_target)
		if to_ear.length() > 0.1 and flat_target.length() > 0.1 and flat_target.normalized().dot(to_ear.normalized()) > EAR_CONE_COS:
			mult *= EAR_SPOT_MULT
	return super(delta, to_target, dist, mult)


# --- Routes (0.39.29) -------------------------------------------------------------------------------------------------

## Picks its route: one of the map's routes that start near it, at random (its own dice); none on a map without routes.
func _pick_route() -> void:
	_route_picked = true
	var routes := PmcRoutes.for_map(_map_name)
	if routes.is_empty():
		return
	var near: Array = []
	var best_d := INF
	for r: Dictionary in routes:
		var first: Array = r["points"][0]
		best_d = minf(best_d, _flat(Vector3(first[0], 0, first[1]) - global_position).length())
	for r: Dictionary in routes:
		var first: Array = r["points"][0]
		var d := _flat(Vector3(first[0], 0, first[1]) - global_position).length()
		if d <= ROUTE_START_NEAR or d <= best_d + 1.0:
			near.append(r)
	var dice := RandomNumberGenerator.new()
	dice.seed = hash(leave_seed if leave_seed != 0 else get_instance_id()) ^ 0x2007e
	route = near[dice.randi_range(0, near.size() - 1)]
	_route_stops.clear()
	var all_places := places(self)
	for i in range(1, (route["points"] as Array).size()):
		var pt: Array = route["points"][i]
		var at := AINav.closest(self, Vector3(pt[0], 0, pt[1]))
		if at == Vector3.ZERO:
			continue
		var stop := {"pos": at}
		if pt.size() > 2:
			var best: Dictionary = {}
			var best_gap := 40.0
			for p: Dictionary in all_places:
				if String(p["name"]).get_slice("@", 0) == String(pt[2]):
					var gap := _flat(p["center"] - Vector3(pt[0], 0, pt[1])).length()
					if gap < best_gap:
						best_gap = gap
						best = p
			if best.is_empty():
				continue   # (that place has no loot this raid, or it's the boss's: just a turn on the way)
			stop["place"] = best
		_route_stops.append(stop)
	for node in RaidScope.nodes(self, &"extracts"):
		if String(node.name) == String(route["extract"]):
			_route_extract = node as Node3D
	_route_i = 0
	_route_tries = 0


## Its next leg along the route: the next turn, the next loot stop's containers, or at the end (or at its leave time)
## the route's extract. False when the route has nothing left for it (it then plans as before).
func _route_next() -> bool:
	if wants_to_leave():
		_route_i = _route_stops.size()   # (time to go: straight to the route's extract)
	while _route_i < _route_stops.size():
		var stop: Dictionary = _route_stops[_route_i]
		if _route_tries >= ROUTE_TRIES:
			_route_advance()
			continue
		if stop.has("place"):
			var p: Dictionary = stop["place"]
			if place.is_empty() or place["id"] != p["id"]:
				_route_tries += 1
				if _try_place(p, [], true):
					return true
				_route_advance()
				continue
			if _searches_left > 0 and _try_place(p, []):
				return true
			place = {}
			_route_advance()
			continue
		if _flat(stop["pos"] - global_position).length() < ROUTE_STOP_REACHED:
			_route_advance()
			continue
		_route_tries += 1
		_go_to(stop["pos"], null)
		return true
	if is_instance_valid(_route_extract) and bool(_route_extract.get("is_open")) and _route_tries < ROUTE_TRIES:
		_route_tries += 1
		if _in_extract(_route_extract, global_position):
			_begin_extract(_route_extract)
			return true
		var spot := AINav.closest(self, _route_extract.global_position)
		if spot != Vector3.ZERO:
			_go_exit(_route_extract, spot)
			return true
	route = {}   # (its extract is shut or out of reach: it carries on as before and finds another)
	_leave_soon()
	return false


func _route_advance() -> void:
	_route_i += 1
	_route_tries = 0


## At the end of its route it leaves (the old plan picks the nearest open extract).
func _leave_soon() -> void:
	leave_at = minf(leave_at, _age) if leave_at >= 0.0 else _age


## On a route, other AI near: it doesn't turn round and wander off; it waits in cover close by (ROUTE_HIDE) for up to
## ROUTE_WAIT s, then carries on (_wander's HOLD commits after that). Clear again: it goes on at once.
func _route_keep_apart() -> void:
	if plan in [Plan.EXIT, Plan.EXTRACT]:
		return
	var others := _others_at()
	var threat := _nearest_threat(others)
	if threat[1] == INF:
		if _route_blocked and plan == Plan.HOLD:
			_plan_wait = 0.0
			_hide_spot = Vector3.INF
		_route_blocked = false
		return
	if _route_blocked or state != State.IDLE:
		return
	_route_blocked = true
	turned_away += 1
	_held_for = 0.0
	var spot := _cover_from(threat[0])
	_hide_spot = spot if spot != Vector3.INF and _flat(spot - global_position).length() <= ROUTE_HIDE else Vector3.INF
	_set_plan(Plan.HOLD, ROUTE_WAIT)


## A fight with another AI (never a player): it doesn't go more than CHASE_LEASH m from where the fight started to get
## at it (no chasing, pushing or closing in across the open; the scavs' Bon-leash hook). Players: as before.
func _strays_from_guards(goal: Vector3) -> bool:
	if super(goal):
		return true
	if _fight_at == Vector3.INF or _target == null or not is_instance_valid(_target) or _target is Player:
		return false
	var off := _flat(goal - _fight_at).length()
	return off > CHASE_LEASH and off > _flat(global_position - _fight_at).length()


## Its shots are a gunshot noise to every other AI in the raid, the way a player's are (0.36.11, owner): the same
## `hear_noise(pos, radius, true)`, with the radius of the gun it carries (ItemDB's "noise", 25 if unknown, as the
## server takes for a player's shot). Hearing, the fight budget and the limit of 4 per fight work as for a player.
func _shot_noise() -> void:
	var radius := float(ItemDB.ITEMS.get(carried_gun, {}).get("noise", 25.0))
	for node in RaidScope.nodes(self, &"enemies"):
		var other := node as Scav
		if other == null or other == self:
			continue
		if other.counts_as_pmc():
			other.hear_noise(global_position, radius, true)
		else:
			other.hear_bot_shot(global_position, radius)   # (0.36.13: one of them comes, the rest heard nothing)


## A search of `container` just finished (0.36.7): its lid opens and stays open (every player's screen sees it), and
## the bot takes its most valuable whole stack, if it has room in its quota and no player has it open.
func _on_search_done(container: Node3D) -> void:
	var box := container as LootContainer
	if box == null or not is_instance_valid(box) or box.has_meta("locked"):
		return
	var world := get_viewport() as RaidWorld
	box.set_open(true)
	if world != null:
		world.bot_opened_lid(box)
	else:
		box.set_meta(RaidWorld.BOT_LID, true)
	if _taken >= MAX_TAKEN or (world != null and world.is_open_by_player(String(box.name))):
		return
	var best: ItemStack = null
	var best_worth := -1
	for stack in box.grid.stacks:
		if not _takeable(stack.id):
			continue
		var worth := ItemDB.value(stack.id) * stack.count
		if worth > best_worth:
			best_worth = worth
			best = stack
	if best == null:
		return
	box.grid.remove(best)
	best.mark_found()
	carried_loot.append(best)
	_taken += 1


## Never keys, nor anything marked special (quest and boss items, dog tags): those aren't for bots.
static func _takeable(id: String) -> bool:
	return ItemDB.ITEMS.has(id) and ItemDB.kind(id) != "key" and not ItemDB.ITEMS[id].get("special", false)


## Time to leave: its rolled leave time has come, or it is hurt (under LEAVE_HURT of its health) with no heals left.
## (Whether it is free to go, not in a fight, is the plan's business: it only asks when it is unaware.)
func wants_to_leave() -> bool:
	if puppet or state == State.DEAD:
		return false
	if _age >= leave_at or (leave_after_breaks > 0 and breaks >= leave_after_breaks):
		return true
	return health.current < health.max_health * LEAVE_HURT and _heals_left <= 0


## Rolls the leave time: LEAVE_MIN to LEAVE_MAX of the raid's length, from the seed the server gave it.
func _roll_leave_time() -> void:
	if leave_at >= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	if leave_seed != 0:
		rng.seed = leave_seed
	else:
		rng.randomize()
	leave_at = rng.randf_range(leave_window.x, leave_window.y) * (raid_length if raid_length > 0.0 else DEFAULT_RAID_LENGTH)


# ---- The raid plan ------------------------------------------------------------------------------------------------

func _set_plan(new_plan: Plan, wait := 0.0) -> void:
	plan = new_plan
	_plan_wait = wait
	_looting_left = 0.0
	if new_plan != Plan.TRAVEL:
		_wander_dir = Vector3.ZERO


## Unaware (IDLE): the plan instead of the scav patrol.
func _wander(delta: float) -> Vector3:
	if plan in [Plan.SEARCH, Plan.TRAVEL] and _exit_retry <= 0.0 and wants_to_leave():
		_set_plan(Plan.HOLD)   # (time to go: it plans its way out instead)
	match plan:
		Plan.EXIT:
			return _walk_to_extract(delta)
		Plan.EXTRACT:
			return _stand_in_extract(delta)
		Plan.FLEE:
			return _run_off(delta)
		Plan.START, Plan.HOLD:
			if _cover_phase == Cover.HEALING:
				return Vector3.ZERO   # (0.36.12: patching up after breaking off a fight; it plans once that's done)
			_plan_wait -= delta
			_held_for += delta
			if _hide_spot != Vector3.INF and plan == Plan.HOLD:
				if _arrived(_hide_spot):
					_hide_spot = Vector3.INF
				else:
					var hide := _path_velocity(_hide_spot, move_speed * jog_speed)
					_face(hide, delta, 4.0)
					return hide
			if _held_for > (ROUTE_WAIT if _route_blocked else HOLD_GIVE_UP) and _commit_left <= 0.0:
				_commit_left = COMMIT_TIME   # (boxed in too long: it goes anyway, see HOLD_GIVE_UP)
				_plan_wait = 0.0
			if _plan_wait <= 0.0:
				_next_destination()
			return Vector3.ZERO
		Plan.SEARCH:
			_looting_left -= delta
			if is_instance_valid(_place_container):
				_face(_flat(_place_container.global_position - global_position), delta, 4.0)
			if _looting_left <= 0.0:
				_searched[_place_container.get_instance_id() if is_instance_valid(_place_container) else 0] = true
				_on_search_done(_place_container)
				_searches_left -= 1
				_set_plan(Plan.HOLD, 0.5)
			return Vector3.ZERO
	# TRAVEL. (Stuck on the way, or the scav code dropped the leg: that spot is out and it plans again.)
	if _wander_dir == Vector3.ZERO:
		if is_instance_valid(_place_container):
			_bad[_place_container.get_instance_id()] = true
		_set_plan(Plan.HOLD, 0.5)
		return Vector3.ZERO
	_patrol_time += delta
	if _arrived(_wander_point) or _patrol_time > 90.0:
		if is_instance_valid(_place_container) and _flat(_place_container.global_position - global_position).length() < 3.5 \
				and _patrol_time <= 90.0:
			plan = Plan.SEARCH
			_wander_dir = Vector3.ZERO
			_looting_left = randf_range(SEARCH_TIME_MIN, SEARCH_TIME_MAX) * search_mult
		else:
			if is_instance_valid(_place_container):
				_bad[_place_container.get_instance_id()] = true
			_set_plan(Plan.HOLD, 0.5)
		return Vector3.ZERO
	var near := _flat(_wander_point - global_position).length() < WALK_NEAR and _indoors
	var move := _path_velocity(_wander_point, move_speed * (1.0 if _hurry_left > 0.0 else (patrol_speed if near else jog_speed)))
	_face(move, delta, 4.0)
	return move


func _go_to(spot: Vector3, container: Node3D) -> void:
	plan = Plan.TRAVEL
	_held_for = 0.0
	_place_container = container
	_patrol_container = container
	_wander_point = spot
	_wander_dir = _flat(spot - global_position).normalized()
	if _wander_dir == Vector3.ZERO:
		_wander_dir = Vector3.FORWARD
	_patrol_time = 0.0
	_patrol_jog = true
	_path.clear()


## Where next: another container at this place, a new place, a spot away from someone, or a short wait.
## `away_from` (INF = nothing): someone it's turning away from, so the next place has to lie the other way.
func _next_destination(away_from := Vector3.INF) -> void:
	if not AINav.ready(self):
		_set_plan(Plan.HOLD, RETRY_WAIT)
		return
	if not _route_picked:
		_pick_route()
	if not route.is_empty() and _route_next():
		return
	var others := _others_at()
	if _exit_retry <= 0.0 and wants_to_leave():
		if _go_extract(others):
			return
		_exit_retry = EXIT_RETRY   # (no extract it can reach: it carries on looting and tries again)
	if away_from == Vector3.INF and _fought:
		var close := _nearest_non_bot(others, global_position)
		if close[1] < AFTER_FIGHT_CLEAR:
			away_from = close[0]
	_fought = false
	# The same place again while it has searches left and it's still clear.
	if away_from == Vector3.INF and not place.is_empty() and _searches_left > 0 and _place_clear(place, others):
		if _try_place(place, others):
			return
	if away_from == Vector3.INF and not place.is_empty() and _searches_left <= 0:
		place = {}
	var options := _allowed_places(others)
	if away_from != Vector3.INF:
		var flee_dir := _flat(global_position - away_from).normalized()
		options = options.filter(func(p: Dictionary) -> bool:
			return _flat(p["center"] - global_position).normalized().dot(flee_dir) > 0.3)
	# The first place is the nearest one it may go to; then weighted by loot.
	if visited.is_empty() and away_from == Vector3.INF:
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["center"].distance_squared_to(global_position) < b["center"].distance_squared_to(global_position))
		for p: Dictionary in options.slice(0, 3):
			if _try_place(p, others, true):
				return
	for attempt in 5:
		var p := _weighted_pick(options)
		if p.is_empty():
			break
		options.erase(p)
		if _try_place(p, others, true):
			return
	if away_from != Vector3.INF or _nearest_threat(others)[1] < INF:
		var threat: Vector3 = away_from if away_from != Vector3.INF else _nearest_threat(others)[0]
		var spot := _away_spot(threat, others)
		if spot != Vector3.ZERO:
			place = {}
			_go_to(spot, null)
			return
	_set_plan(Plan.HOLD, RETRY_WAIT)


## Starts on `p` (a container there it hasn't searched, whose way passes the checks). False if none does.
func _try_place(p: Dictionary, others: Array, fresh := false) -> bool:
	var boxes: Array = (p["containers"] as Array).filter(func(c: Node) -> bool:
		return is_instance_valid(c) and not _bad.has(c.get_instance_id()))
	var unsearched := boxes.filter(func(c: Node) -> bool: return not _searched.has(c.get_instance_id()))
	if not unsearched.is_empty():
		boxes = unsearched
	elif not fresh:
		return false
	boxes.shuffle()
	for c: Node3D in boxes.slice(0, 3):
		var spot := AINav.closest(self, c.global_position)
		if spot == Vector3.ZERO:
			continue
		var route := AINav.path(self, global_position, spot)
		# (held up a while, every way out blocked: a way that keeps PASS_FLOOR m off them will do)
		if not _route_clear(route, others) and not (_held_for > HELD_UP and _route_floor_ok(route, others)):
			continue
		if fresh:
			place = p
			_searches_left = mini(randi_range(SEARCHES_MIN, SEARCHES_MAX), (p["containers"] as Array).size())
			visited.append(String(p["name"]))
			_places_left -= 1
		_go_to(spot, c)
		return true
	return false


## Places it may pick now: clear of other AI and bots, not where another bot is going, not its own last ones while
## it has places left.
func _allowed_places(others: Array = []) -> Array:
	if others.is_empty():
		others = _others_at()
	var out := []
	for p: Dictionary in places(self):
		if not place.is_empty() and p["id"] == place["id"]:
			continue
		if _places_left > 0 and visited.has(String(p["name"])):
			continue
		if _place_clear(p, others):
			out.append(p)
	if out.is_empty() and _places_left > 0:
		# (every place it hasn't been to is busy: any clear one will do)
		for p: Dictionary in places(self):
			if (place.is_empty() or p["id"] != place["id"]) and _place_clear(p, others):
				out.append(p)
	return out


## (0.36.12) How much threat another AI is (THREAT_*): by its kind (net_kind: 0 scav, 1 Raider, 2 sniper, 3 Bon).
static func threat_of(other: Scav) -> float:
	if other is PmcAI:
		return THREAT_BOT
	match other.net_kind:
		1:
			return THREAT_RAIDER
		2:
			return THREAT_SNIPER
		3:
			return THREAT_BOSS
	return THREAT_SCAV


## Another bot is going to, or looting, this place now.
func _bot_going_to(p: Dictionary) -> bool:
	for other in _others():
		var bot := other as PmcAI
		if bot != null and not bot.place.is_empty() and bot.place["id"] == p["id"]:
			return true
	return false


## A weighted pick by loot value; a cautious bot that heard shots lately mostly picks places the other way.
func _weighted_pick(options: Array) -> Dictionary:
	if options.is_empty():
		return {}
	var weights: Array[float] = []
	var total := 0.0
	for p: Dictionary in options:
		var w: float = p["weight"]
		if _shot_at != Vector3.INF and _shot_age < SHOT_MEMORY:
			var to_place := _flat(p["center"] - global_position)
			if to_place.dot(_flat(_shot_at - global_position)) > 0.0 or (p["center"] as Vector3).distance_to(_shot_at) < SHOT_CARE_RANGE:
				w *= 0.1
		weights.append(w)
		total += w
	var roll := randf() * total
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			return options[i]
	return options[options.size() - 1]


## A real player is in this fight (the new fight rules are for AI only, owner): its target is a player, a player hit
## it in the last PLAYER_MEMORY s, or a player is within its sight range.
func _player_in_fight() -> bool:
	if (is_instance_valid(_target) and _target is Player) or _since_player_hit < PLAYER_MEMORY:
		return true
	for node in RaidScope.nodes(self, &"player"):
		var someone := node as Player
		if someone != null and not someone.out_of_fight() and someone.global_position.distance_to(global_position) < sight_range:
			return true
	return false


## The AI in this fight with it: those fighting it, and the ones it may fight within BREAK_NEAR m that it can see.
func _foes() -> Array[Scav]:
	var foes: Array[Scav] = []
	for other in _others():
		if not _may_fight(other) or other.out_of_fight():
			continue
		var on_me := other._target == self and other.state in [State.ALERT, State.ENGAGE]
		if on_me or (_flat(other.global_position - global_position).length() < BREAK_NEAR and _sees_body(other)):
			foes.append(other)
	return foes


## The AI after it (fighting it) within FLEE_MIN m.
func _chasers() -> Array[Scav]:
	var out: Array[Scav] = []
	for other in _others():
		if other._target == self and other.state in [State.ALERT, State.ENGAGE] \
				and _flat(other.global_position - global_position).length() < FLEE_MIN:
			out.append(other)
	return out


## Every BREAK_CHECK s in a fight with AI: outnumbered (its foes weigh BREAK_THREAT or more) or hurt (under BREAK_HURT,
## with someone fighting it), it breaks off. Never with a player in the fight, never while patching up, never again in
## a fight it turned back to (`_holding_ground`), nor for BREAK_COOLDOWN s after a run. Running off with a player
## turning up: it stops running (and the usual brain takes it from there).
func _check_break_off() -> void:
	if plan == Plan.FLEE:
		if state == State.IDLE and _player_in_fight():
			_end_flee(false)
		return
	if state not in [State.ALERT, State.ENGAGE] or _holding_ground or _break_cooldown > 0.0 or _cover_phase == Cover.HEALING:
		return
	if not is_instance_valid(_target) or not _target is Scav or _player_in_fight():
		return
	var foes := _foes()
	if foes.is_empty():
		return
	var threat := 0.0
	for foe in foes:
		threat += threat_of(foe)
		if foe._target == self and foe._can_see and _flat(foe.global_position - global_position).length() < NO_BREAK_NEAR:
			return   # (cornered: one this close has it in sight, so it fights; it looks again in a moment)
	if threat >= BREAK_THREAT or health.current < health.max_health * BREAK_HURT:
		# (0.39.29) Every foe far off (a sniper on a roof): running across the open in its sight is what killed them;
		# it gets into cover from them instead and waits there.
		if state == State.ENGAGE and _cover_phase == Cover.NONE and foes.all(func(f: Scav) -> bool:
				return _flat(f.global_position - global_position).length() > BREAK_FAR):
			_hide_from_unseen()
			if _cover_phase != Cover.NONE:
				_break_cooldown = BREAK_COOLDOWN
				return
		_break_off(foes)


## Breaks off: off to a spot away from `foes` at full speed (no spot to run to: it fights this one out).
func _break_off(foes: Array[Scav]) -> void:
	var spot := _flee_spot(foes)
	if spot == Vector3.INF:
		_holding_ground = true
		return
	_flee_from = foes
	if _cover_phase != Cover.NONE:
		_cover_phase = Cover.NONE
	_hold_fire()
	_set_state(State.IDLE)
	_seen_state = State.IDLE
	place = {}
	_place_container = null
	_patrol_container = null
	plan = Plan.FLEE
	_looting_left = 0.0
	_flee_repicked = false
	_flee_legs = 1
	_run_to(spot)
	breaks += 1


func _run_to(spot: Vector3) -> void:
	_wander_point = spot
	_wander_dir = _flat(spot - global_position).normalized()
	if _wander_dir == Vector3.ZERO:
		_wander_dir = Vector3.FORWARD
	_patrol_time = 0.0
	_path.clear()


## Where to run: a walkable spot FLEE_MIN-FLEE_MAX m from every foe, FLEE_CLEAR m from every other AI (if there's no
## such spot, only from the foes), the more out of the foes' sight and the more straight away from them the better,
## whose way there doesn't pass close by a foe it isn't already close to. INF if there is none.
func _flee_spot(foes: Array[Scav]) -> Vector3:
	var live: Array[Scav] = []
	for foe in foes:
		if is_instance_valid(foe) and not foe.out_of_fight():
			live.append(foe)
	foes = live
	if foes.is_empty() or not AINav.ready(self):
		return Vector3.INF
	var center := Vector3.ZERO
	for foe in foes:
		center += foe.global_position
	center /= foes.size()
	var away := _flat(global_position - center)
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var others := _others()
	var space := get_world_3d().direct_space_state
	for strict in [true, false]:
		var scored := []
		for i in 16:
			var dir := away.rotated(Vector3.UP, i * TAU / 16.0)
			for r: float in [FLEE_MIN * 0.75, FLEE_MIN, (FLEE_MIN + FLEE_MAX) * 0.5]:
				var spot := AINav.closest(self, global_position + dir * r)
				if spot == Vector3.ZERO:
					continue
				var near_foe := INF
				for foe in foes:
					near_foe = minf(near_foe, _flat(spot - foe.global_position).length())
				if near_foe < FLEE_MIN or near_foe > FLEE_MAX:
					continue
				var crowded := false
				if strict:
					for other in others:
						if not foes.has(other) and _flat(spot - other.global_position).length() < FLEE_CLEAR:
							crowded = true
							break
				if crowded:
					continue
				var hidden := 0
				for foe in foes:
					var query := PhysicsRayQueryParameters3D.create(foe.eye_position(), spot + Vector3(0, 1.3, 0), 1)
					if not space.intersect_ray(query).is_empty():
						hidden += 1
				scored.append([2.0 * hidden / foes.size() + dir.dot(away) - 0.5 * r / FLEE_MAX, spot])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		for entry: Array in scored.slice(0, 4):
			if _flee_way_ok(entry[1], foes):
				return entry[1]
	return Vector3.INF


## The walk to `spot` exists and never comes within FLEE_FIGHT m of a foe it isn't already that close to.
func _flee_way_ok(spot: Vector3, foes: Array[Scav]) -> bool:
	var way := AINav.path(self, global_position, spot)
	if way.size() < 2 or AINav.path_length(way) > FLEE_MAX * 2.0:
		return false
	for foe in foes:
		var limit := minf(FLEE_FIGHT, _flat(global_position - foe.global_position).length() - 1.0)
		for k in way.size() - 1:
			var a := way[k]
			var b := way[k + 1]
			var steps := maxi(int(a.distance_to(b) / 3.0), 1)
			for j in steps + 1:
				if _flat(a.lerp(b, float(j) / steps) - foe.global_position).length() < limit:
					return false
	return true


## Running off (Plan.FLEE, unaware as far as the brain goes): full speed to the spot, then patch up there and plan
## again. Stuck on the way it looks for another spot once; after FLEE_GIVE_UP s it stops wherever it is.
func _run_off(delta: float) -> Vector3:
	if _wander_dir == Vector3.ZERO:
		if not _flee_repicked:
			_flee_repicked = true
			var again := _flee_spot(_flee_from)
			if again != Vector3.INF:
				_run_to(again)
				return Vector3.ZERO
		_end_flee()
		return Vector3.ZERO
	_patrol_time += delta
	if _arrived(_wander_point) or _patrol_time > FLEE_GIVE_UP:
		var chasers := _chasers()
		if not chasers.is_empty() and _flee_legs < FLEE_LEGS:
			var on := _flee_spot(chasers)
			if on != Vector3.INF:
				_flee_legs += 1
				_run_to(on)
				return Vector3.ZERO
		_end_flee()
		return Vector3.ZERO
	var move := _path_velocity(_wander_point, move_speed)
	_face(move, delta, 8.0)
	return move


## The run is over: it patches up if it has heals and lost enough to need one, then plans again (another place, or
## out of the raid if it is hurt with no heals left: `wants_to_leave`).
func _end_flee(heal := true) -> void:
	_flee_from.clear()
	_break_cooldown = BREAK_COOLDOWN
	if heal and _chasers().is_empty() and _heals_left > 0 and health.current <= health.max_health - heal_amount / 2 and _cover_phase == Cover.NONE:
		_start_heal()
	_set_plan(Plan.HOLD, 0.5)


## Running off, it doesn't turn back for an enemy it glimpses, or a shot, from farther than FLEE_FIGHT m: only one that
## close (cornered) or a player makes it fight, and that fight it fights out.
## Unaware, it doesn't start a fight with AI it spots in a group it shouldn't take on (GROUP_THREAT or more, none of
## them after it yet, farther than FLEE_FIGHT m): it lets them be (`_look_ahead` takes it somewhere else if they are
## in its way; looking into a noise, it gives that up). A lone scav it fights as before.
func _alert(known_pos: Vector3, reaction := -1.0) -> void:
	if not puppet and not _hit_now and state in [State.IDLE, State.INVESTIGATE, State.SEARCH] and plan != Plan.FLEE \
			and (_group_to_avoid(known_pos) or _far_to_leave(known_pos)):
		_spot = 0.0
		if state != State.IDLE:
			_set_state(State.IDLE)   # (plans again: the hook in _physics_process)
		return
	if plan == Plan.FLEE and state == State.IDLE and not puppet:
		if _flat(known_pos - global_position).length() > FLEE_FIGHT and not _player_in_fight():
			return
		_holding_ground = true
		_flee_from.clear()
		_break_cooldown = BREAK_COOLDOWN
		_set_plan(Plan.HOLD, 0.3)
	if state in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		_fight_at = global_position
	super(known_pos, reaction)


## A hit from a scav, Raider, sniper or Bon does `ai_damage` of its damage (0.36.13; 0.36.15: per map).
func take_hit_from(attacker: Node3D, amount: int, head: bool) -> void:
	var ai := attacker as Scav
	if ai != null and not ai.counts_as_pmc() and ai_damage != 1.0:
		amount = maxi(1, roundi(amount * ai_damage))
	super(attacker, amount, head)


## Running off it doesn't stop to patch up on the way (it does once it gets there, `_end_flee`).
func _quiet_enough_to_heal() -> bool:
	return plan != Plan.FLEE and super()


## Hit: a hit that isn't another AI's is a player's (the new fight rules step aside for PLAYER_MEMORY s).
func _on_damaged(amount: int, source_position: Vector3) -> void:
	if _hit_by != null and is_instance_valid(_hit_by) and _flat(_hit_by.global_position - global_position).length() > BREAK_FAR:
		_hit_far_left = 1.5   # (0.39.29: shot from far off by an AI, a sniper on a roof: into cover, not trading shots)
	if _hit_by == null:
		_since_player_hit = 0.0
		_suppressed_left = SUPPRESS_TIME
		if not _can_see:
			_hit_unseen_left = 1.5
			if state == State.ENGAGE:
				_last_seen = source_position   # (where the shot came from: it watches that way from cover)
	_hit_now = true
	super(amount, source_position)
	_hit_now = false


## A shot that just missed: as a hit, never a group it can let be.
func notice_near_miss(shooter_pos: Vector3) -> void:
	if not puppet and _player_made(shooter_pos):
		_suppressed_left = SUPPRESS_TIME
	_hit_now = true
	super(shooter_pos)
	_hit_now = false


## The one it just spotted is a scav, Raider, sniper or Bon farther than BOT_OPEN_FIRE that isn't after it (0.36.13,
## owner: "bots don't shoot first at far scavs"): it lets it be and carries on. Players and other bots: never.
func _far_to_leave(known_pos: Vector3) -> bool:
	if not is_instance_valid(_target):
		return false
	var spotted := _target as Scav
	if spotted == null or spotted.counts_as_pmc() or _player_in_fight():
		return false
	if _flat(known_pos - global_position).length() <= BOT_OPEN_FIRE:
		return false
	return not (spotted._target == self and spotted.state in [State.ALERT, State.ENGAGE])


## The one it just spotted (its target, at `known_pos`) is an AI in a group it shouldn't take on that isn't after it yet.
func _group_to_avoid(known_pos: Vector3) -> bool:
	if not is_instance_valid(_target):
		return false
	var spotted := _target as Scav
	if spotted == null or _player_in_fight() \
			or _flat(known_pos - global_position).length() <= FLEE_FIGHT:
		return false
	var threat := 0.0
	for other in _others():
		if other.global_position.distance_to(spotted.global_position) >= GROUP_SPREAD:
			continue
		if other._target == self and other.state in [State.ALERT, State.ENGAGE]:
			return false   # (they're onto it already: it's a fight)
		threat += threat_of(other)
	return threat >= GROUP_THREAT


# ---- Steering around other AI (0.36.5-0.36.9, back in 0.36.14 on top of the fighting) ----------------------------

func _place_clear(p: Dictionary, others: Array) -> bool:
	var center: Vector3 = p["center"]
	var reach: float = p["radius"]
	for o: Array in others:
		var limit := BOT_CLEAR if o[1] else AI_PLACE_CLEAR
		if (o[0] as Vector3).distance_to(center) < limit + reach:
			return false
		if o[1] and o[2] is PmcAI and not (o[2] as PmcAI).place.is_empty() and (o[2] as PmcAI).place["id"] == p["id"]:
			return false
	return true


# ---- Keep apart ---------------------------------------------------------------------------------------------------

## The other AI in this raid: [position, is a bot, node], living ones only.
func _others_at() -> Array:
	var out := []
	if not keep_apart or _commit_left > 0.0:
		return out
	for node in RaidScope.nodes(self, &"enemies"):
		var other := node as Scav
		if other == null or other == self or other.state == State.DEAD or other.health.is_dead:
			continue
		out.append([other.global_position, other is PmcAI, other, other.global_position + _flat(other.velocity) * LOOK_AHEAD])
	return out


func _non_bot_near(pos: Vector3, dist: float) -> bool:
	for o: Array in _others_at():
		if not o[1] and (o[0] as Vector3).distance_to(pos) < dist:
			return true
	return false


## [position, distance] of the nearest non-bot AI to `pos` (INF if none).
func _nearest_non_bot(others: Array, pos: Vector3) -> Array:
	var best := [Vector3.INF, INF]
	for o: Array in others:
		var d := (o[0] as Vector3).distance_to(pos)
		if not o[1] and d < best[1]:
			best = [o[0], d]
	return best


## [position, distance] of the closest AI too close right now (non-bot within AI_NEAR, bot within BOT_CLEAR), else INF.
func _nearest_threat(others: Array) -> Array:
	var best := [Vector3.INF, INF]
	for o: Array in others:
		# (where it'll be in a moment counts too: one walking this way is turned from before it's inside the line)
		var d := minf((o[0] as Vector3).distance_to(global_position), (o[3] as Vector3).distance_to(global_position) if o.size() > 3 else INF)
		if d < (BOT_CLEAR if o[1] else AI_NEAR) and d < best[1]:
			best = [o[0], d]
	return best


## The way along `route` keeps clear of other AI: no sample within AI_ROUTE_CLEAR of a non-bot (BOT_CLEAR of a bot).
## Someone it's already closer to than that only fails it where the way doesn't gain distance from them fast enough
## (ESCAPE_GAIN m per m walked), so it can still walk away, but not alongside them.
func _route_clear(route: PackedVector3Array, others: Array, from := 0) -> bool:
	return _route_score(route, others, from) >= 0.0


## How clear the way is: the least room (m) any sample leaves past what it needs; negative fails (-INF: no way).
func _route_score(route: PackedVector3Array, others: Array, from := 0) -> float:
	if from > 0:
		# (the rest of the way, from where it stands now)
		var rest := PackedVector3Array([global_position])
		rest.append_array(route.slice(mini(from, route.size() - 1)))
		route = rest
	if route.size() < 2:
		return -INF
	var watch := []
	for o: Array in others:
		var now := (o[0] as Vector3).distance_to(global_position)
		var limit := BOT_CLEAR if o[1] else AI_ROUTE_CLEAR
		if now < limit + 200.0:
			watch.append([o[0], limit, now - 1.0])
			# (0.36.9: where a walking one will be in a moment counts along the way too)
			if o.size() > 3 and (o[3] as Vector3).distance_to(o[0]) > 1.0:
				watch.append([o[3], limit, (o[3] as Vector3).distance_to(global_position) - 1.0])
	var worst := INF
	var walked := 0.0
	var left := 0.0
	for i in range(1, route.size()):
		var a := route[i - 1]
		var b := route[i]
		var seg := a.distance_to(b)
		var t := left
		while t <= seg:
			var at := a.lerp(b, t / seg) if seg > 0.0 else b
			for w: Array in watch:
				var need := minf(w[1], w[2] + (walked + t) * ESCAPE_GAIN)
				worst = minf(worst, (w[0] as Vector3).distance_to(at) - need)
			t += ROUTE_STEP
		left = t - seg
		walked += seg
	for w: Array in watch:
		var need_end := minf(w[1], w[2] + walked * ESCAPE_GAIN)
		worst = minf(worst, (w[0] as Vector3).distance_to(route[route.size() - 1]) - need_end)
	return worst


## Once a second: someone too close, or the place or way ahead gone busy, and it isn't fighting: it turns away.
func _keep_apart() -> void:
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH] or plan == Plan.FLEE:
		return
	if _ear_left > 0.0 and state != State.IDLE:
		return   # (0.39.21: hunting a player it heard beats keeping away from other AI)
	if not route.is_empty():
		_route_keep_apart()
		return
	var others := _others_at()
	var threat := _nearest_threat(others)
	_flee_wait_left -= CHECK_EVERY
	if threat[1] < INF:
		var gap: float = threat[1]
		var last := _last_gap
		_last_gap = gap
		# Already on its way out from them along a clear way, and the gap is growing: carry on.
		if state == State.IDLE and plan in [Plan.TRAVEL, Plan.EXIT] and _path.size() > 1 and _route_clear(_path, others, _path_index) \
				and (gap > last + 0.3 or (last == INF and _wander_point.distance_to(threat[0]) > gap)):
			return
		if state == State.IDLE and plan == Plan.HOLD and _flee_wait_left > 0.0:
			return   # (nowhere better a moment ago: it waits before looking again)
		turned_away += 1
		_hurry_left = HURRY_TIME
		if plan in [Plan.EXIT, Plan.EXTRACT]:
			# (0.36.8: someone came near on its way out or in the extract: it moves off first and tries again)
			extract = null
			_exit_retry = EXIT_RETRY
		if state != State.IDLE:
			_set_state(State.IDLE)
			_seen_state = State.IDLE
		_next_destination(threat[0])
		if plan == Plan.HOLD:
			_flee_wait_left = 2.0
		return
	_last_gap = INF
	if state != State.IDLE or plan == Plan.HOLD or plan == Plan.START:
		return
	# The place it's going to or looting got busy, or (every few seconds) someone came near the way ahead.
	if not place.is_empty() and not _place_clear(place, others):
		_bad_place_now()
		return
	_route_check_left -= CHECK_EVERY
	if plan in [Plan.TRAVEL, Plan.EXIT] and _route_check_left <= 0.0 and _path.size() > 1:
		_route_check_left = 1.0
		if not _route_clear(_path, others, _path_index):
			_next_destination()


func _bad_place_now() -> void:
	place = {}
	_next_destination()


## Where to go to get away from `threat`: a walkable spot 30-100 m off (away first, then round the compass) whose
## way passes the checks. Cornered (none does): the roomiest spot whose way never comes within PASS_FLOOR m of a
## non-bot AI (PASS_FLOOR_BOT of a bot); failing that, the way that leaves the most room along it, if it beats
## standing still. ZERO if none.
func _away_spot(threat: Vector3, others: Array) -> Vector3:
	var away := _flat(global_position - threat).normalized()
	if away == Vector3.ZERO:
		away = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var room_now := _room_at(global_position, others)
	var best := Vector3.ZERO
	var best_room := 0.0
	var last := Vector3.ZERO
	var last_room := room_now + 8.0
	for turn: float in [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9, PI]:
		for reach: float in [randf_range(45.0, 70.0), 30.0, 100.0]:
			var spot := AINav.closest(self, global_position + away.rotated(Vector3.UP, turn) * reach)
			if spot == Vector3.ZERO or _flat(spot - global_position).length() < 8.0:
				continue
			var route := AINav.path(self, global_position, spot)
			if _route_score(route, others) >= 0.0:
				return spot
			if route.size() < 2:
				continue
			var room := _room_at(route[route.size() - 1], others)
			if room >= best_room and _route_floor_ok(route, others):
				best_room = room
				best = spot
			elif best == Vector3.ZERO and room > last_room and _route_room(route, others) > room_now - 3.0:
				last_room = room
				last = spot
	return best if best != Vector3.ZERO else last


## The least room (past the keep-apart distances) anywhere along the way.
func _route_room(route: PackedVector3Array, others: Array) -> float:
	var worst := INF
	for i in range(1, route.size()):
		var a := route[i - 1]
		var b := route[i]
		var seg := a.distance_to(b)
		var t := 0.0
		while t <= seg:
			worst = minf(worst, _room_at(a.lerp(b, t / seg) if seg > 0.0 else b, others))
			t += ROUTE_STEP
	return worst


## Room at `pos` past the keep-apart distances (negative: someone is too close there).
func _room_at(pos: Vector3, others: Array) -> float:
	var worst := INF
	for o: Array in others:
		worst = minf(worst, (o[0] as Vector3).distance_to(pos) - (BOT_CLEAR if o[1] else AI_NEAR))
	return worst


## No sample of the way comes within PASS_FLOOR of a non-bot AI (PASS_FLOOR_BOT of a bot).
func _route_floor_ok(route: PackedVector3Array, others: Array) -> bool:
	if route.size() < 2:
		return false
	for i in range(1, route.size()):
		var a := route[i - 1]
		var b := route[i]
		var seg := a.distance_to(b)
		var t := 0.0
		while t <= seg:
			var at := a.lerp(b, t / seg) if seg > 0.0 else b
			for o: Array in others:
				if (o[0] as Vector3).distance_to(at) < (PASS_FLOOR_BOT if o[1] else PASS_FLOOR):
					return false
			t += ROUTE_STEP
	return true


# ---- Extracting (0.36.7) ------------------------------------------------------------------------------------------

## The extracts it may use: open ones (a zone that waits for its switch is shut until it's thrown).
func _usable_extracts() -> Array[Node3D]:
	var zones: Array[Node3D] = []
	for node in RaidScope.nodes(self, &"extracts"):
		var zone := node as Node3D
		if zone != null and zone.is_inside_tree() and bool(zone.get("is_open")):
			zones.append(zone)
	return zones


## Whether `pos` is inside the extract's box (the same test the server uses for players, RaidWorld.extract_at).
func _in_extract(zone: Node3D, pos: Vector3) -> bool:
	var shape := zone.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null or not shape.shape is BoxShape3D:
		return _flat(zone.global_position - pos).length() < 2.0
	var size := (shape.shape as BoxShape3D).size
	var local := shape.global_transform.affine_inverse() * (pos + Vector3(0, 0.9, 0))
	return AABB(-size * 0.5, size).has_point(local)


## Heads for an extract: the nearest usable one whose way passes the keep-apart checks and whose surroundings are
## clear (no other AI within 40 m, a bot 60 m). If none is, the nearest whose way passes and that has no other AI
## within 30 m (a bot 60 m) will do. False if there is none (0.36.8: it no longer takes a busy one; it carries on and
## tries again).
func _go_extract(others: Array) -> bool:
	var zones := _usable_extracts()
	zones.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
	var fallback: Array = []
	for zone in zones:
		var clear := _place_clear({"id": -1, "center": zone.global_position, "radius": 0.0}, others)
		var roomy := clear or _room_at(zone.global_position, others) >= 0.0
		if _in_extract(zone, global_position):
			if roomy:
				_begin_extract(zone)
				return true
			continue
		if not roomy:
			continue
		var spot := AINav.closest(self, zone.global_position)
		if spot == Vector3.ZERO:
			continue
		var route := AINav.path(self, global_position, spot)
		if route.size() < 2 or _route_score(route, others) < 0.0:
			continue
		if clear:
			_go_exit(zone, spot)
			return true
		if fallback.is_empty():
			fallback = [zone, spot]
	if not fallback.is_empty():
		_go_exit(fallback[0], fallback[1])
		return true
	return false


func _go_exit(zone: Node3D, spot: Vector3) -> void:
	place = {}
	_place_container = null
	_patrol_container = null
	extract = zone
	plan = Plan.EXIT
	_looting_left = 0.0
	_wander_point = spot
	_wander_dir = _flat(spot - global_position).normalized()
	if _wander_dir == Vector3.ZERO:
		_wander_dir = Vector3.FORWARD
	_patrol_time = 0.0
	_patrol_jog = true
	_path.clear()


func _begin_extract(zone: Node3D) -> void:
	place = {}
	extract = zone
	plan = Plan.EXTRACT
	_looting_left = 0.0
	_wander_dir = Vector3.ZERO
	_extract_left = float(zone.get("extract_time"))


## Jogging to the extract; once inside, it stands.
func _walk_to_extract(delta: float) -> Vector3:
	if not is_instance_valid(extract) or not bool(extract.get("is_open")) or _wander_dir == Vector3.ZERO:
		extract = null
		_exit_retry = 0.0
		_set_plan(Plan.HOLD, 0.5)
		return Vector3.ZERO
	if _in_extract(extract, global_position):
		_begin_extract(extract)
		return Vector3.ZERO
	_patrol_time += delta
	if _patrol_time > EXIT_GIVE_UP:
		extract = null
		_exit_retry = EXIT_RETRY
		_set_plan(Plan.HOLD, 0.5)
		return Vector3.ZERO
	if _arrived(_wander_point):
		# (at the nearest walkable spot but not inside the box: a step towards its middle)
		var toward := _flat(extract.global_position - global_position)
		if toward.length() < 0.2:
			_begin_extract(extract)
			return Vector3.ZERO
		_face(toward, delta, 4.0)
		return toward.normalized() * move_speed * patrol_speed
	var move := _path_velocity(_wander_point, move_speed * jog_speed)
	_face(move, delta, 4.0)
	return move


## Standing in the extract for its extract_time, then gone. Pushed out of it, it walks back in.
func _stand_in_extract(delta: float) -> Vector3:
	if not is_instance_valid(extract) or not bool(extract.get("is_open")):
		extract = null
		_set_plan(Plan.HOLD, 0.5)
		return Vector3.ZERO
	if not _in_extract(extract, global_position):
		_go_exit(extract, AINav.closest(self, extract.global_position))
		return Vector3.ZERO
	_extract_left -= delta
	if _extract_left <= 0.0:
		_leave_raid()
	return Vector3.ZERO


## Out of the raid, quietly (0.36.7): no body, no loot bag, no kill feed line, no kill credit, no death sound. On the
## server RaidWorld tells the raid's screens it left ("left", not "died") and forgets its name.
func _leave_raid() -> void:
	state = State.DEAD
	remove_from_group("enemies")
	set_meta(RaidWorld.BOT_LEFT, true)
	left_raid = true
	set_physics_process(false)
	queue_free()


# ---- Other AI -----------------------------------------------------------------------------------------------------

## The other living AI in this raid (bots or not), never itself.
func _others() -> Array[Scav]:
	var out: Array[Scav] = []
	for node in RaidScope.nodes(self, &"enemies"):
		var other := node as Scav
		if other == null or other == self or other.state == State.DEAD or other.health.is_dead:
			continue
		out.append(other)
	return out


## Once a second while unaware: whether it is under a roof (it walks, not jogs, the last 15 m to a spot indoors).
func _look_indoors() -> void:
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		return
	var up := global_position + Vector3(0, 1.0, 0)
	_indoors = not get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(up, up + Vector3(0, 8, 0), 1)).is_empty()


# ---- Places and what they're worth (once per raid) ----------------------------------------------------------------

## This raid's places: [{id, name, center, radius, containers, value, weight}], built once and kept on the raid's
## viewport (like FightBudget), so every bot in the raid shares it.
static func places(node: Node) -> Array:
	var viewport := node.get_viewport()
	if viewport.has_meta(_PLACES_META):
		return viewport.get_meta(_PLACES_META)
	var list := _build_places(node)
	viewport.set_meta(_PLACES_META, list)
	return list


## Tests: forget this raid's places (new containers).
static func reset_places(node: Node) -> void:
	node.get_viewport().remove_meta(_PLACES_META)


static func _build_places(node: Node) -> Array:
	var boss_zone := _boss_zone(node)
	var groups: Array = []
	for c in RaidScope.nodes(node, &"loot_containers"):
		var box := c as LootContainer
		if box == null or box.has_meta("locked") or box.loot_table == "":
			continue
		var pname := String(box.get_meta("place", ""))
		var at := box.global_position
		var home: Dictionary = {}
		for g: Dictionary in groups:
			if g["name"] == pname and (g["first"] as Vector3).distance_to(at) < PLACE_SPREAD:
				home = g
				break
		if home.is_empty():
			home = {"name": pname, "first": at, "containers": []}
			groups.append(home)
		home["containers"].append(box)
	var list := []
	for g: Dictionary in groups:
		var center := Vector3.ZERO
		var value := 0.0
		for box: LootContainer in g["containers"]:
			center += box.global_position
			value += container_value(box)
		center /= (g["containers"] as Array).size()
		if not boss_zone.is_empty():
			var zc: Vector3 = boss_zone["center"]
			if Vector2(center.x - zc.x, center.z - zc.z).length() <= float(boss_zone["radius"]) and absf(center.y - zc.y) < 12.0:
				continue   # (Bon's place, or Zero's: never)
		var reach := 0.0
		for box: LootContainer in g["containers"]:
			reach = maxf(reach, box.global_position.distance_to(center))
		var label := String(g["name"]) if String(g["name"]) != "" else "spot"
		list.append({"id": list.size(), "name": "%s@%d,%d" % [label, roundi(center.x), roundi(center.z)], "center": center,
			"radius": reach, "containers": g["containers"], "value": value, "weight": VALUE_WEIGHT_MIN})
	# Weight by rank: the poorest place VALUE_WEIGHT_MIN, the best VALUE_WEIGHT_MAX, the rest in between.
	var ranked := list.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] < b["value"])
	for i in ranked.size():
		var share := float(i) / float(ranked.size() - 1) if ranked.size() > 1 else 1.0
		ranked[i]["weight"] = lerpf(VALUE_WEIGHT_MIN, VALUE_WEIGHT_MAX, share)
	return list


## The spawner's boss zone ({} if the map has none).
static func _boss_zone(node: Node) -> Dictionary:
	var spawner := node.get_viewport().find_child("EnemySpawner", true, false) as EnemySpawner
	if spawner == null or spawner.boss.is_empty():
		return {}
	for zone: Dictionary in spawner.zones:
		if zone.get("name", "") == spawner.boss.get("zone", ""):
			return zone
	return {}


static var _table_values := {}

## What a container's loot is worth on average, from its loot table and place (ItemDB's odds; not what it holds).
static func container_value(box: LootContainer) -> float:
	var key := "%s|%s|%s" % [box.loot_table, String(box.get_meta("place", "")), box.name]
	if _table_values.has(key):
		return _table_values[key]
	var per_roll := roll_value(box.loot_table, String(box.get_meta("place", "")))
	var value := per_roll * (box.min_items + box.max_items) / 2.0
	var extras: Dictionary = ItemDB.TABLE_CHANCES.get(box.loot_table, {})
	for id: String in extras:
		value += ItemDB.value(id) * float(extras[id])
	var special: Dictionary = ItemDB.SPECIAL_FINDS.get(String(box.name), {})
	for id: String in special:
		value += ItemDB.value(id) * float(special[id])
	_table_values[key] = value
	return value


## The average worth of one ItemDB.roll(table, place).
static func roll_value(table: String, place_name := "") -> float:
	var key := "roll|%s|%s" % [table, place_name]
	if _table_values.has(key):
		return _table_values[key]
	var weights: Dictionary = (ItemDB.LOOT_TABLES[table] as Dictionary).duplicate()
	if ItemDB.PLACE_LOOT.has(place_name):
		for k: String in ItemDB.PLACE_LOOT[place_name]:
			var key_item := ItemDB.ITEMS.has(k) and ItemDB.kind(k) == "key"
			weights[k] = weights.get(k, 0) + ItemDB.PLACE_LOOT[place_name][k] * (1 if key_item else ItemDB.PLACE_BOOST)
	var total := 0.0
	var sum := 0.0
	for k: String in weights:
		total += weights[k]
		sum += weights[k] * _item_worth(k)
	var value := sum / total if total > 0.0 else 0.0
	_table_values[key] = value
	return value


## One rolled entry's worth: an item times its usual count, or the average valuable of a rarity.
static func _item_worth(key: String) -> float:
	if ItemDB.ITEMS.has(key):
		var counts := {"rifle_ammo": 40.0, "pistol_ammo": 27.5, "smg_ammo": 27.5, "shells": 8.5, "sniper_ammo": 6.5, "bandage": 1.5}
		return ItemDB.value(key) * float(counts.get(key, 1.0))
	var total := 0.0
	var n := 0
	for id: String in ItemDB.ITEMS:
		var item: Dictionary = ItemDB.ITEMS[id]
		if item["kind"] == "valuable" and item["rarity"] == key and not item.get("special", false):
			total += float(item["value"])
			n += 1
	return total / n if n > 0 else 0.0
