class_name PmcAI
extends Scav
## AI PMC brain (0.36.5, AI PMCs piece 6a): what a bot does when it isn't fighting. scenes/pmc_ai.tscn uses it; scavs,
## Raiders, snipers and Bon never do (their behaviour is locked, owner), so all of this lives here as overrides.
## Raid plan: it waits a moment, then loots 2-4 places (buildings, by their containers' `place`), the nearest first,
## then picked by what their loot is worth (best ~3x as likely as poorest), searching 2-4 containers at each.
## 0.36.11 (owner): no keep-apart rule any more, since AI fight AI now. It walks straight to its places and out by the
## nearest open extract, and a fight on the way is the Scav brain's. Only these cautions are left: never the boss's
## area, not a place another bot is going to. Its shots are heard like a player's (`_shot_noise`), and it hears the others'.
## 0.36.12 ("smarter bots", owner's pick; numbers pending the owner's OK), against AI only: other AI weigh as threat
## (THREAT_*); it doesn't pick a place with PLACE_THREAT near it (`threat_near`); unaware, a group ahead or near its place
## makes it drop the place (`_look_ahead`) and it doesn't start a fight with a group it spots (`_group_to_avoid`);
## in a fight with AI, outnumbered or hurt, it breaks off (`_check_break_off`, Plan.FLEE, `_run_off`), heals and plans
## again. With a real player in the fight (`_player_in_fight`) none of this applies: the 0.36.11 brain fights.
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
## (0.36.11, owner approved) The reach around a place in which other AI count against it (0.36.12: by threat, below).
const CROWD_RANGE := 40.0
## (0.36.12, numbers pending the owner's OK) How much threat each other living AI is: what it weighs when it picks a
## place, notices a group on its way, or counts the enemies in a fight.
const THREAT_SCAV := 1.0
const THREAT_RAIDER := 2.0
const THREAT_SNIPER := 1.0
const THREAT_BOSS := 2.0
const THREAT_BOT := 1.0
## (0.36.12, pending) It doesn't pick a place with this much threat within CROWD_RANGE m of it (every place over: the
## least threatening one).
const PLACE_THREAT := 2.0
## (0.36.12, pending) On its way or at a place, unaware: a group (other AI with this much threat within GROUP_SPREAD m
## of one of them) that it can see, or that is within GROUP_NOTICE m of it, ahead of it on its way or within
## CROWD_RANGE m of its place, makes it drop that place (not picked again for AVOID_TIME s) and pick another.
const GROUP_THREAT := 2.0
const GROUP_SPREAD := 15.0
const GROUP_NOTICE := 40.0
const AVOID_TIME := 90.0
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
static var ai_damage_to_bot := AI_DAMAGE_TO_BOT   # (the raid report tries other values through this)
const PLAYER_MEMORY := 10.0
const BREAK_CHECK := 0.25
const CHECK_EVERY := 1.0         # seconds between its looks at whether it is indoors
const SHOT_CARE_RANGE := 80.0    # gunshots this close: curious bots go, cautious ones steer away
const CURIOUS_CHANCE := 0.5
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
const LEAVE_HURT := 0.4
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
var _indoor_left := 0.0
var _seen_state := State.IDLE
var _shot_at := Vector3.INF
var _shot_age := 0.0
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
var _avoid := {}
var _flee_from: Array[Scav] = []
var _flee_repicked := false
var _flee_legs := 0
var _holding_ground := false
var _break_cooldown := 0.0
var _break_check := 0.0
var _since_player_hit := INF
var _hit_now := false
var drops := 0
var breaks := 0


func _ready() -> void:
	super()
	if puppet:
		return
	add_to_group(&"pmc_bots")   # (0.36.10: how every other AI finds the bots it may fight, Scav._closest_rival)
	curious = randf() < CURIOUS_CHANCE
	_places_left = randi_range(PLACES_MIN, PLACES_MAX)
	_plan_wait = randf_range(START_WAIT_MIN, START_WAIT_MAX)
	_indoor_left = randf() * CHECK_EVERY
	_roll_leave_time()


func _physics_process(delta: float) -> void:
	if state != State.DEAD and not puppet:
		_age += delta
		_exit_retry -= delta
		_shot_age += delta
		_indoor_left -= delta
		if _indoor_left <= 0.0:
			_indoor_left = CHECK_EVERY
			_look_indoors()
			_look_ahead()
		_break_cooldown -= delta
		_since_player_hit += delta
		_break_check -= delta
		if _break_check <= 0.0:
			_break_check = BREAK_CHECK
			_check_break_off()
	super(delta)
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
func hear_noise(pos: Vector3, radius: float, gunshot := false) -> void:
	if puppet:
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
	if _age >= leave_at:
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
	leave_at = rng.randf_range(LEAVE_MIN, LEAVE_MAX) * (raid_length if raid_length > 0.0 else DEFAULT_RAID_LENGTH)


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
			_looting_left = randf_range(SEARCH_TIME_MIN, SEARCH_TIME_MAX)
		else:
			if is_instance_valid(_place_container):
				_bad[_place_container.get_instance_id()] = true
			_set_plan(Plan.HOLD, 0.5)
		return Vector3.ZERO
	var near := _flat(_wander_point - global_position).length() < WALK_NEAR and _indoors
	var move := _path_velocity(_wander_point, move_speed * (patrol_speed if near else jog_speed))
	_face(move, delta, 4.0)
	return move


func _go_to(spot: Vector3, container: Node3D) -> void:
	plan = Plan.TRAVEL
	_place_container = container
	_patrol_container = container
	_wander_point = spot
	_wander_dir = _flat(spot - global_position).normalized()
	if _wander_dir == Vector3.ZERO:
		_wander_dir = Vector3.FORWARD
	_patrol_time = 0.0
	_patrol_jog = true
	_path.clear()


## Where next: another container at this place, a new place, or a short wait.
func _next_destination() -> void:
	if not AINav.ready(self):
		_set_plan(Plan.HOLD, RETRY_WAIT)
		return
	if _exit_retry <= 0.0 and wants_to_leave():
		if _go_extract():
			return
		_exit_retry = EXIT_RETRY   # (no extract it can reach: it carries on looting and tries again)
	# The same place again while it has searches left.
	if not place.is_empty() and _searches_left > 0:
		if _try_place(place):
			return
	if not place.is_empty() and _searches_left <= 0:
		place = {}
	var options := _allowed_places()
	# The first place is the nearest one it may go to; then weighted by loot.
	if visited.is_empty():
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["center"].distance_squared_to(global_position) < b["center"].distance_squared_to(global_position))
		for p: Dictionary in options.slice(0, 3):
			if _try_place(p, true):
				return
	for attempt in 5:
		var p := _weighted_pick(options)
		if p.is_empty():
			break
		options.erase(p)
		if _try_place(p, true):
			return
	_set_plan(Plan.HOLD, RETRY_WAIT)


## Starts on `p` (a container there it hasn't searched that it can walk to). False if none.
func _try_place(p: Dictionary, fresh := false) -> bool:
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
		if AINav.path(self, global_position, spot).size() < 2:
			continue
		if fresh:
			place = p
			_searches_left = mini(randi_range(SEARCHES_MIN, SEARCHES_MAX), (p["containers"] as Array).size())
			visited.append(String(p["name"]))
			_places_left -= 1
		_go_to(spot, c)
		return true
	return false


## Places it may pick now: not its own last ones while it has places left, not where another bot is going, and not
## crowded (CROWD_AI or more other AI near it). If every one is crowded, those with the fewest AI near. (The boss's
## area is never a place: `_build_places` leaves it out.)
func _allowed_places() -> Array:
	var pool := []
	var fresh := []
	for p: Dictionary in places(self):
		if (not place.is_empty() and p["id"] == place["id"]) or _bot_going_to(p):
			continue
		pool.append(p)
		if _places_left <= 0 or not visited.has(String(p["name"])):
			fresh.append(p)
	if fresh.is_empty() and _places_left > 0:
		fresh = pool   # (every place it hasn't been to is taken or shut: any other will do)
	var not_dropped := fresh.filter(func(p: Dictionary) -> bool: return float(_avoid.get(p["id"], -INF)) <= _age)
	if not not_dropped.is_empty():
		fresh = not_dropped   # (0.36.12: a place it dropped for a group near it waits AVOID_TIME s, unless it's all there is)
	var open := fresh.filter(func(p: Dictionary) -> bool: return threat_near(p) < PLACE_THREAT)
	if not open.is_empty():
		return open
	var fewest := []
	var least := INF
	for p: Dictionary in fresh:
		var n := threat_near(p)
		if n < least:
			least = n
			fewest = []
		if n == least:
			fewest.append(p)
	return fewest


## (0.36.12) The threat of the other living AI (bots or not) within CROWD_RANGE m of the place (past its own reach).
func threat_near(p: Dictionary) -> float:
	var n := 0.0
	for other in _others():
		if other.global_position.distance_to(p["center"]) < CROWD_RANGE + float(p["radius"]):
			n += threat_of(other)
	return n


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


# ---- Danger it can know about (0.36.12) ---------------------------------------------------------------------------

## Once a second while unaware on its way to a place or searching there: a group of other AI (GROUP_THREAT or more
## within GROUP_SPREAD m of one of them) that it can see, or that is within GROUP_NOTICE m of it, and that is ahead of
## it on its way or within CROWD_RANGE m of its place, makes it drop the place and pick another (`_drop_place`).
## One look, no steering: it never turns away from anyone, it only changes where it is going.
func _look_ahead() -> void:
	if state != State.IDLE or plan not in [Plan.TRAVEL, Plan.SEARCH] or place.is_empty():
		return
	var goal: Vector3 = place["center"]
	var reach := CROWD_RANGE + float(place["radius"])
	var to_goal := _flat(goal - global_position)
	var others := _others()
	for other in others:
		var to_other := _flat(other.global_position - global_position)
		var d := to_other.length()
		var near_place := other.global_position.distance_to(goal) < reach
		var ahead := to_goal.length() > 0.1 and d < to_goal.length() + GROUP_SPREAD \
			and to_other.normalized().dot(to_goal.normalized()) > 0.5
		if not near_place and not ahead:
			continue
		if d > GROUP_NOTICE and (d > sight_range or not _in_view(to_other) or not _sees_body(other)):
			continue
		var threat := 0.0
		for near in others:
			if near.global_position.distance_to(other.global_position) < GROUP_SPREAD:
				threat += threat_of(near)
		if threat >= GROUP_THREAT:
			_drop_place()
			return


## Leaves its place for another (it isn't picked again for AVOID_TIME s unless nothing else is left).
func _drop_place() -> void:
	if not place.is_empty():
		_avoid[place["id"]] = _age + AVOID_TIME
	place = {}
	drops += 1
	_set_plan(Plan.HOLD, 0.3)


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
		if foe._target == self and foe._can_see and _flat(foe.global_position - global_position).length() < FLEE_FIGHT:
			return   # (cornered: one this close has it in sight, so it fights; it looks again in a moment)
	if threat >= BREAK_THREAT or health.current < health.max_health * BREAK_HURT:
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
	if not place.is_empty():
		_avoid[place["id"]] = _age + AVOID_TIME
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
	super(known_pos, reaction)


## A hit from a scav, Raider, sniper or Bon does AI_DAMAGE_TO_BOT of its damage (0.36.13).
func take_hit_from(attacker: Node3D, amount: int, head: bool) -> void:
	var ai := attacker as Scav
	if ai != null and not ai.counts_as_pmc() and ai_damage_to_bot != 1.0:
		amount = maxi(1, roundi(amount * ai_damage_to_bot))
	super(attacker, amount, head)


## Running off it doesn't stop to patch up on the way (it does once it gets there, `_end_flee`).
func _quiet_enough_to_heal() -> bool:
	return plan != Plan.FLEE and super()


## Hit: a hit that isn't another AI's is a player's (the new fight rules step aside for PLAYER_MEMORY s).
func _on_damaged(amount: int, source_position: Vector3) -> void:
	if _hit_by == null:
		_since_player_hit = 0.0
	_hit_now = true
	super(amount, source_position)
	_hit_now = false


## A shot that just missed: as a hit, never a group it can let be.
func notice_near_miss(shooter_pos: Vector3) -> void:
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


## Heads for the nearest usable extract it can walk to (or is already standing in). False if there is none.
func _go_extract() -> bool:
	var zones := _usable_extracts()
	zones.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
	for zone in zones:
		if _in_extract(zone, global_position):
			_begin_extract(zone)
			return true
		var spot := AINav.closest(self, zone.global_position)
		if spot == Vector3.ZERO or AINav.path(self, global_position, spot).size() < 2:
			continue
		_go_exit(zone, spot)
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
