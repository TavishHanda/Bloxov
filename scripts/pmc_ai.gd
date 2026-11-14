class_name PmcAI
extends Scav
## AI PMC brain (0.36.5, AI PMCs piece 6a): what a bot does when it isn't fighting. scenes/pmc_ai.tscn uses it; scavs,
## Raiders, snipers and Bon never do (their behaviour is locked, owner), so all of this lives here as overrides.
## Raid plan: it waits a moment, then loots 2-4 places (buildings, by their containers' `place`), the nearest first,
## then picked by what their loot is worth (best ~3x as likely as poorest), searching 2-4 containers at each.
## Keep-apart rule (owner): it stays away from every other AI (non-bot 30-40 m, other bots 60 m) when picking where to
## go, the way there, while moving and looting, and which noises it walks over to. Its fight brain is the Scav's.
## Hooks for the next pieces: `_on_search_done` (take items, open lids) and `wants_to_leave` (extracting).

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
## (0.36.5, owner approved) The keep-apart rule, in meters.
const AI_PLACE_CLEAR := 40.0     # no non-bot AI this close to a place it picks
const BOT_CLEAR := 60.0          # other bots: places, routes and on the move
const AI_ROUTE_CLEAR := 30.0     # no non-bot AI this close to the way there
const AI_NEAR := 30.0            # on the move / looting: a non-bot AI this close and it turns away
const CHECK_EVERY := 1.0         # seconds between those checks
const NOISE_AI_CLEAR := 40.0     # never walks over to a noise with a non-bot AI this close to it
const SHOT_CARE_RANGE := 80.0    # gunshots this close: curious bots go, cautious ones steer away
const CURIOUS_CHANCE := 0.5
const AFTER_FIGHT_CLEAR := 40.0  # after a fight: a non-bot AI this close and it moves away first
## How the checks are done (tuning, not the owner's numbers): route samples every ROUTE_STEP m, a wait of
## RETRY_WAIT s when nowhere passes, containers of one place within PLACE_SPREAD m of each other form one place.
const ROUTE_STEP := 5.0
const RETRY_WAIT := 3.0
const PLACE_SPREAD := 25.0
const SHOT_MEMORY := 60.0
const _PLACES_META := &"pmc_places"

enum Plan { START, TRAVEL, SEARCH, HOLD }
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
var _apart_left := 0.0
var _route_check_left := 0.0
var _indoors := false
var _seen_state := State.IDLE
var _fought := false
var _shot_at := Vector3.INF
var _shot_age := 0.0
## How many times it turned away from someone (tests, the proof tool).
var turned_away := 0


func _ready() -> void:
	super()
	if puppet:
		return
	curious = randf() < CURIOUS_CHANCE
	_places_left = randi_range(PLACES_MIN, PLACES_MAX)
	_plan_wait = randf_range(START_WAIT_MIN, START_WAIT_MAX)
	_apart_left = randf() * CHECK_EVERY


func _physics_process(delta: float) -> void:
	if state != State.DEAD and not puppet:
		_shot_age += delta
		if state in [State.ALERT, State.ENGAGE]:
			_fought = true
		_apart_left -= delta
		if _apart_left <= 0.0:
			_apart_left = CHECK_EVERY
			_keep_apart()
	super(delta)
	if state != _seen_state and not puppet:
		if state == State.IDLE and _seen_state != State.IDLE:
			_set_plan(Plan.HOLD, 0.3)   # (back from a fight or a noise: plans again)
		_seen_state = state


## Bots never take part in a fight's noise budget the scav way, and keep away from other AI's noises (0.36.5).
func hear_noise(pos: Vector3, radius: float, gunshot := false) -> void:
	if puppet:
		return
	var loud := gunshot or radius >= alarm_noise
	if _non_bot_near(pos, NOISE_AI_CLEAR):
		if loud:
			FightBudget.stir(self, pos)
		return
	if loud and not curious:
		FightBudget.stir(self, pos)
		if global_position.distance_to(pos) <= SHOT_CARE_RANGE:
			_shot_at = pos
			_shot_age = 0.0
		return
	super(pos, radius, gunshot)


## Hook for the next piece (looting): a search of `container` just finished. Today's search is pretend.
func _on_search_done(_container: Node3D) -> void:
	pass


## Hook for the next piece (extracting): asked before every new destination. Never yet.
func wants_to_leave() -> bool:
	return false


# ---- The raid plan ------------------------------------------------------------------------------------------------

func _set_plan(new_plan: Plan, wait := 0.0) -> void:
	plan = new_plan
	_plan_wait = wait
	_looting_left = 0.0
	if new_plan != Plan.TRAVEL:
		_wander_dir = Vector3.ZERO


## Unaware (IDLE): the plan instead of the scav patrol.
func _wander(delta: float) -> Vector3:
	match plan:
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


## Where next: another container at this place, a new place, a spot away from someone, or a short wait.
## `away_from` (INF = nothing): someone it's turning away from, so the next place has to lie the other way.
func _next_destination(away_from := Vector3.INF) -> void:
	if wants_to_leave():
		pass   # (the extracting piece goes here)
	if not AINav.ready(self):
		_set_plan(Plan.HOLD, RETRY_WAIT)
		return
	var others := _others()
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
		var spot := _flee_spot(threat, others)
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
		if spot == Vector3.ZERO or not _route_clear(AINav.path(self, global_position, spot), others):
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
func _allowed_places(others: Array) -> Array:
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


# ---- Keep apart ---------------------------------------------------------------------------------------------------

## The other AI in this raid: [position, is a bot, node], living ones only.
func _others() -> Array:
	var out := []
	for node in RaidScope.nodes(self, &"enemies"):
		var other := node as Scav
		if other == null or other == self or other.state == State.DEAD or other.health.is_dead:
			continue
		out.append([other.global_position, other is PmcAI, other])
	return out


func _non_bot_near(pos: Vector3, dist: float) -> bool:
	for o: Array in _others():
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
		var d := (o[0] as Vector3).distance_to(global_position)
		if d < (BOT_CLEAR if o[1] else AI_NEAR) and d < best[1]:
			best = [o[0], d]
	return best


## The way along `route` keeps clear of other AI: no sample within AI_ROUTE_CLEAR of a non-bot (BOT_CLEAR of a bot).
## (Someone it's already closer to than that only fails it where the way gets closer to them than it is now, so it
## can still walk away.)
func _route_clear(route: PackedVector3Array, others: Array, from := 0) -> bool:
	if route.size() < 2:
		return false
	var watch := []
	for o: Array in others:
		var now := (o[0] as Vector3).distance_to(global_position)
		var limit := BOT_CLEAR if o[1] else AI_ROUTE_CLEAR
		watch.append([o[0], minf(limit, now - 1.0)])
	var left := 0.0
	for i in range(maxi(from, 1), route.size()):
		var a := route[i - 1]
		var b := route[i]
		var seg := a.distance_to(b)
		var t := left
		while t <= seg:
			var at := a.lerp(b, t / seg) if seg > 0.0 else b
			for w: Array in watch:
				if (w[0] as Vector3).distance_to(at) < w[1]:
					return false
			t += ROUTE_STEP
		left = t - seg
	for w: Array in watch:
		if (w[0] as Vector3).distance_to(route[route.size() - 1]) < w[1]:
			return false
	return true


## Once a second: someone too close, or the place or way ahead gone busy, and it isn't fighting: it turns away.
func _keep_apart() -> void:
	if state not in [State.IDLE, State.INVESTIGATE, State.SEARCH]:
		return
	var up := global_position + Vector3(0, 1.0, 0)
	_indoors = not get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(up, up + Vector3(0, 8, 0), 1)).is_empty()
	var others := _others()
	var threat := _nearest_threat(others)
	if threat[1] < INF:
		# Already on its way out from them along a clear way: carry on.
		if state == State.IDLE and plan == Plan.TRAVEL and _path.size() > 1 and _route_clear(_path, others, _path_index) \
				and _wander_point.distance_to(threat[0]) > (threat[0] as Vector3).distance_to(global_position):
			return
		turned_away += 1
		if state != State.IDLE:
			_set_state(State.IDLE)
			_seen_state = State.IDLE
		_next_destination(threat[0])
		return
	if state != State.IDLE or plan == Plan.HOLD or plan == Plan.START:
		return
	# The place it's going to or looting got busy, or (every few seconds) someone came near the way ahead.
	if not place.is_empty() and not _place_clear(place, others):
		_bad_place_now()
		return
	_route_check_left -= CHECK_EVERY
	if plan == Plan.TRAVEL and _route_check_left <= 0.0 and _path.size() > 1:
		_route_check_left = 2.0
		if not _route_clear(_path, others, _path_index):
			_next_destination()


func _bad_place_now() -> void:
	place = {}
	_next_destination()


## A walkable spot about 45-70 m away from `threat` whose way there passes the checks (ZERO if none).
func _flee_spot(threat: Vector3, others: Array) -> Vector3:
	var away := _flat(global_position - threat).normalized()
	if away == Vector3.ZERO:
		away = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	for turn: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
		var spot := AINav.closest(self, global_position + away.rotated(Vector3.UP, turn) * randf_range(45.0, 70.0))
		if spot == Vector3.ZERO or _flat(spot - global_position).length() < 8.0:
			continue
		if _route_clear(AINav.path(self, global_position, spot), others):
			return spot
	return Vector3.ZERO


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
