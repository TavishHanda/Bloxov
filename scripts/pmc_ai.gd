class_name PmcAI
extends Scav
## AI PMC brain (0.36.5, AI PMCs piece 6a): what a bot does when it isn't fighting. scenes/pmc_ai.tscn uses it; scavs,
## Raiders, snipers and Bon never do (their behaviour is locked, owner), so all of this lives here as overrides.
## Raid plan: it waits a moment, then loots 2-4 places (buildings, by their containers' `place`), the nearest first,
## then picked by what their loot is worth (best ~3x as likely as poorest), searching 2-4 containers at each.
## 0.36.11 (owner): no keep-apart rule any more, since AI fight AI now. It walks straight to its places and out by the
## nearest open extract, and a fight on the way is the Scav brain's. Only these cautions are left: it doesn't PICK a
## place with 3 or more other AI within 40 m of it (none left: the one with the fewest), never the boss's area, and
## not one another bot is going to. Its shots are heard like a player's (`_shot_noise`), and it hears the others'.
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
## (0.36.11, owner approved) It doesn't pick a place with this many other AI (bots or not) within CROWD_RANGE m of it.
const CROWD_AI := 3
const CROWD_RANGE := 40.0
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

enum Plan { START, TRAVEL, SEARCH, HOLD, EXIT, EXTRACT }
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
	super(delta)
	if state != _seen_state and not puppet:
		if state == State.IDLE and _seen_state != State.IDLE:
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
	_noise_to(&"enemies")


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
		Plan.START, Plan.HOLD:
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
	var open := fresh.filter(func(p: Dictionary) -> bool: return _ai_near(p) < CROWD_AI)
	if not open.is_empty():
		return open
	var fewest := []
	var least := INF
	for p: Dictionary in fresh:
		var n := _ai_near(p)
		if n < least:
			least = n
			fewest = []
		if n == least:
			fewest.append(p)
	return fewest


## How many other living AI (bots or not) are within CROWD_RANGE m of the place (past its own reach).
func _ai_near(p: Dictionary) -> int:
	var n := 0
	for other in _others():
		if other.global_position.distance_to(p["center"]) < CROWD_RANGE + float(p["radius"]):
			n += 1
	return n


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
