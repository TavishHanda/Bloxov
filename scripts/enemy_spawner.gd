class_name EnemySpawner
extends Node3D
## Spawns a limited number of enemies per raid, spread over the raid, at child Marker3D points
## away from (and out of sight of) every player. At the raid start it is stricter: nothing comes in near or in
## sight of a player's start (see START_GUARD), so a player still loading in can't be shot before they can move.
## Scavs: a few at the start, then one every scav_interval seconds until the budget runs out.
## Raiders (the tougher AI faction): arrive at set times (later in the raid = late-raid pressure). Dead enemies don't come back.

@export var enemy_scene: PackedScene
@export var raider_scene: PackedScene
@export var sniper_scene: PackedScene = preload("res://scenes/sniper.tscn")
@export var boss_scene: PackedScene = preload("res://scenes/boss.tscn")
## Total enemies for the whole raid (owner, 0.6.5: 20 + 5 for now; tune once the maps exist).
@export var scav_budget := 20
@export var raider_budget := 5
## Scavs at the start of the raid (part of scav_budget).
@export var initial_count := 3
## Never more than this many alive at once (a spawn that's due waits for a slot).
@export var max_alive := 5
## Seconds between scav spawns after the start (random in this range).
@export var scav_interval_min := 25.0
@export var scav_interval_max := 35.0
## When each Raider arrives (seconds into the raid). A 10-minute raid: minutes 2, 3.5, 5, 6.5 and 8.
@export var raider_times: PackedFloat32Array = [120.0, 210.0, 300.0, 390.0, 480.0]
@export var min_distance_from_player := 18.0
## Chance a Raider arrives with a partner that sticks with it (both count toward raider_budget).
@export_range(0.0, 1.0) var raider_duo_chance := 0.15
## AI zones (Scavs 2.0; a map sets these, the test map has none). Each is a Dictionary: "name", "center"
## (Vector3), "radius" (m), optional "avoid" (Vector3(x, radius, z) circles its AI keep out of) and "edge" (patrol
## stops sit at least this fraction of the radius out), "scavs" and "raiders" (how many start there), "trickle" (how likely later arrivals
## come here; hot zones get the most). Markers with metadata `zone` = that name are its spawn spots. AI that
## spawns in a zone patrols only that zone. With zones, initial_count is ignored and raider_times are only the
## later Raiders (the zones' own start at 0:00).
@export var zones: Array = []
## With zones: this many scavs roam the whole map instead of one zone (they start at any marker).
@export var roamers := 0
## With zones: chance a zone's AI starts at one of its spots inside a building (markers with metadata `indoor`)
## rather than outside (0.12.23, owner: some AI inside, so you have to clear buildings; 0.20.14: 2 in 3, and they
## patrol that building's rooms, see Scav.indoor_rooms).
@export_range(0.0, 1.0) var indoor_chance := 0.67
## Sniper scavs at the start (Scavs 2.0, owner): each on its own perch, picked from the markers with metadata
## `perch` (high spots: roofs, the bell tower), preferring perches no player is in sight of. They don't count
## toward the scav budget.
@export var snipers := 0
## How far a sniper can move around on its perch.
@export var perch_radius := 3.0
## The boss (Scavs 2.0, owner): a Raider commander and its Raider guards in one zone (the town hall and bunker),
## guarding the best loot. "zone" = the zone's name in `zones`, "guards" = how many, "chance" = how often a raid
## has it (owner: every raid while testing, a chance later). Empty = no boss. Not part of the budgets.
@export var boss := {}
## More bosses (0.35.34, owner: Riptide has three, Raijin in the lab and Ace and Orbit in the lower hull), each a
## Dictionary like `boss`, in its own zone. A boss start marker with metadata `boss_zone` is only for that zone's boss.
@export var bosses: Array = []
## The map's own look for its AI (0.35.34, owner: Riptide's scavs are Deckhands and its Raiders Exion Troopers):
## {"scav": scene path, "raider": scene path}. Same AI, other clothes and names.
@export var looks := {}
## Keys this map's scavs sometimes carry (0.38.7, Riptide's Impound Key): {item id: chance per scav}.
@export var scav_keys := {}

## Where the raid's players start (0.38.10, owner: online a sniper scav and a zone's scavs shot players before they could
## move). The server makes its AI before any player is in the raid world, so it never knew where they'd stand:
## RaidWorld sets this before the AI comes in (offline the player is already there). These spots count as players
## for the first START_GUARD seconds: no AI starts near one (min_distance_from_player) or where one can see it, and
## snipers take perches that don't look down on one. (0.39.34) The guard stays on past that while someone in the
## raid is still loading in (no body yet), so a slow first load isn't the one raid the old 60 s didn't cover.
var player_starts: Array[Vector3] = []
const START_GUARD := 60.0
## The start guard never runs longer than this, even if a player never reports in (a crashed or closed game).
const START_GUARD_MAX := 120.0
## Spawned so far this raid.
var scavs_spawned := 0
var raiders_spawned := 0
var _elapsed := 0.0
var _next_scav := 0.0
## Bosses held back because their room could be seen from a start (spawned once the guard is over).
var _pending_bosses: Array[Dictionary] = []
## When to try the snipers held back at the start again.
var _next_sniper_try := 0.0
## Perches a sniper is already on (a held-back sniper never takes a used one).
var _used_perches: Array[Marker3D] = []
## With zones: how many of raider_times have come up.
var _raider_wave := 0
var snipers_spawned := 0
## The boss of this raid (null if none).
var boss_spawned: Scav = null
## Every boss of this raid (boss_spawned is the first).
var bosses_spawned: Array[Scav] = []
## Where the guards walk around the boss (right/back in its facing), the first three; more get random spots.
const GUARD_OFFSETS: Array[Vector3] = [Vector3(2.5, 0, 1.5), Vector3(-2.5, 0, 1.5), Vector3(0, 0, 3.5)]


func _ready() -> void:
	_next_scav = randf_range(scav_interval_min, scav_interval_max)
	if snipers > 0:
		_spawn_snipers.call_deferred()
	if looks.has("scav"):
		enemy_scene = load(String(looks["scav"])) as PackedScene
	if looks.has("raider"):
		raider_scene = load(String(looks["raider"])) as PackedScene
	var all_bosses := ([boss] if not boss.is_empty() else []) + bosses
	for b: Dictionary in all_bosses:
		if randf() < float(b.get("chance", 1.0)):
			_spawn_boss.call_deferred(b)
	if not zones.is_empty():
		_spawn_zones.call_deferred()
		return
	for i in mini(initial_count, scav_budget):
		_spawn.call_deferred(enemy_scene)


## Puts the snipers on their perches: random ones, but not where a player is already in its sights. During the start
## guard a perch that looks down on a player's start waits (a player still loading in can't move out of its sights).
func _spawn_snipers() -> void:
	var players := RaidScope.nodes(self, &"player")
	var guard := _start_guard_on()
	var perches: Array[Marker3D] = []
	var watched: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D and child.get_meta("perch", false) and not _used_perches.has(child):
			if _perch_sees_player(child as Marker3D, players):
				watched.append(child as Marker3D)
			else:
				perches.append(child as Marker3D)
	perches.shuffle()
	if not guard:
		watched.shuffle()
		perches.append_array(watched)
	for perch in perches.slice(0, snipers - snipers_spawned):
		var sniper := sniper_scene.instantiate() as Scav
		get_parent().add_child(sniper)
		sniper.global_position = perch.global_position
		var face: Vector3 = perch.get_meta("face", Vector3.FORWARD)
		sniper.rotation.y = atan2(-face.x, -face.z)
		sniper.home_center = perch.global_position
		sniper.home_radius = perch_radius
		snipers_spawned += 1
		_used_perches.append(perch)
	if snipers_spawned < snipers:
		# (0.39.34: try again once the guard is over; no perch left at all means never)
		_next_sniper_try = maxf(_next_sniper_try, START_GUARD) if guard else INF


func _perch_sees_player(perch: Marker3D, players: Array[Node]) -> bool:
	var space := get_world_3d().direct_space_state
	var spots := _starts()
	for player in players:
		if player is Node3D:
			spots.append((player as Node3D).global_position)
	for spot in spots:
		if perch.global_position.distance_to(spot) < 120.0:
			var query := PhysicsRayQueryParameters3D.create(perch.global_position + Vector3(0, 1.6, 0),
				spot + Vector3(0, 1.4, 0), 1)
			if space.intersect_ray(query).is_empty():
				return true
	return false


## The players' start spots while they still count: START_GUARD, or longer while someone is still loading in.
func _starts() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _start_guard_on():
		out.assign(player_starts)
	return out


## Is the start guard still on? For START_GUARD seconds, and past that until every player has a body in the raid
## (online a player still loading in has none), never longer than START_GUARD_MAX.
func _start_guard_on() -> bool:
	if player_starts.is_empty():
		return false
	if _elapsed < START_GUARD:
		return true
	if _elapsed >= START_GUARD_MAX:
		return false
	return _loading_players()


## True while someone in this raid has a start spot but no body yet (their game is still loading in). Offline the
## real player is here from the start, so no one is loading.
func _loading_players() -> bool:
	var bodies := RaidScope.nodes(self, &"player")
	if not bodies.is_empty() and bodies.all(func(p: Node) -> bool: return not bool(p.get("proxy"))):
		return false
	return bodies.size() < player_starts.size()


## The boss and its guards, at a spot in its zone: inside its building if the map has start spots for it (markers
## with metadata `boss_start`; owner, 0.12.18). They patrol the zone together; guards follow the boss and carry on
## patrolling the zone on their own if it dies.
func _spawn_boss(b: Dictionary = {}) -> void:
	if b.is_empty():
		b = boss
	var zone := {}
	for z in zones:
		if z.get("name", "") == b.get("zone", ""):
			zone = z
	var spots: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D and child.get_meta("boss_start", false) \
				and String(child.get_meta("boss_zone", zone.get("name", ""))) == String(zone.get("name", "")):
			spots.append(child as Marker3D)
	if spots.is_empty():
		for child in get_children():
			if child is Marker3D and String(child.get_meta("zone", "")) == String(zone.get("name", "")):
				spots.append(child as Marker3D)
	if zone.is_empty() or spots.is_empty() or boss_scene == null:
		return
	var players := RaidScope.nodes(self, &"player")
	if _start_guard_on():
		var safe: Array[Marker3D] = []
		for marker in spots:
			# (hidden from every start: a boss can be close by in its own room, but not in a loading player's sight)
			if not _seen_from_any(marker.global_position, players):
				safe.append(marker)
		if safe.is_empty():
			# (0.39.34: its room can be seen from where someone starts; it comes in once the guard is over)
			if not _pending_bosses.has(b):
				_pending_bosses.append(b)
			return
		spots = safe
	var spot := spots.pick_random().global_position as Vector3
	# (0.33.4: a map's boss can be its own scene, "scene": Riptide's Raijin)
	var scene := load(String(b["scene"])) as PackedScene if b.has("scene") else boss_scene
	var the_boss := scene.instantiate() as Scav
	if boss_spawned == null:
		boss_spawned = the_boss
	bosses_spawned.append(the_boss)
	get_parent().add_child(the_boss)
	the_boss.global_position = on_floor(spot)
	the_boss.home_center = zone.get("center", spot)
	the_boss.home_radius = float(zone.get("radius", 0.0))
	the_boss.home_height = float(zone.get("height", 0.0))
	for i in int(b.get("guards", 0)):
		# (0.35.6: a map's boss can bring its own guards, "guard_scene", and name them, "guard_names")
		var guard_scene := load(String(b["guard_scene"])) as PackedScene if b.has("guard_scene") else raider_scene
		var guard := guard_scene.instantiate() as Scav
		get_parent().add_child(guard)
		var offset := GUARD_OFFSETS[i] if i < GUARD_OFFSETS.size() else Vector3(randf_range(-4, 4), 0, randf_range(2, 5))
		guard.follow_offset = offset
		var guard_pos := clear_spot_near(spot, offset)
		if _start_guard_on() and _seen_from_any(guard_pos, players):
			guard_pos = the_boss.global_position
		guard.global_position = guard_pos
		guard.follow(the_boss)
		guard.home_center = the_boss.home_center
		guard.home_radius = the_boss.home_radius
		guard.home_height = the_boss.home_height
		var names: Array = b.get("guard_names", [])
		guard.body_name = String(names[i]) if i < names.size() else the_boss.body_name + "'s Guard"   # (owner, 0.12.39)
		guard.stays_home = true   # (owner: Bon and his guards patrol their area, they don't run to every gunshot)
		guard.leash = the_boss.leash


## Raid start with zones: each zone's own scavs and Raiders, then the roamers.
func _spawn_zones() -> void:
	for zone in zones:
		for i in int(zone.get("raiders", 0)):
			if raiders_spawned < raider_budget:
				_spawn(raider_scene, zone, false)
		for i in int(zone.get("scavs", 0)):
			if scavs_spawned < scav_budget:
				_spawn(enemy_scene, zone)
	for i in roamers:
		if scavs_spawned < scav_budget:
			_spawn(enemy_scene, {})


func _physics_process(delta: float) -> void:
	tick(delta)


## Advances the raid clock by `delta` seconds and spawns whatever is due (the smoke test calls this directly).
func tick(delta: float) -> void:
	_elapsed += delta
	# (0.39.34: snipers and bosses held back at the start come in once the guard is over)
	if not _start_guard_on():
		if snipers_spawned < snipers and _elapsed >= _next_sniper_try:
			_spawn_snipers()
			_next_sniper_try = _elapsed + 10.0
		if not _pending_bosses.is_empty():
			var waiting := _pending_bosses.duplicate()
			_pending_bosses.clear()
			for b: Dictionary in waiting:
				_spawn_boss(b)
	# (AI PMCs, 0.36.2, aren't the spawner's: they never take a scav's or Raider's place)
	if RaidScope.nodes(self, &"enemies").filter(func(e: Node) -> bool: return not e.get("loner")).size() >= max_alive:
		return
	if zones.is_empty():
		if raiders_spawned < mini(raider_budget, raider_times.size()) and _elapsed >= raider_times[raiders_spawned]:
			_spawn(raider_scene)
		elif scavs_spawned < scav_budget and _elapsed >= _next_scav:
			if _spawn(enemy_scene):
				_next_scav = _elapsed + randf_range(scav_interval_min, scav_interval_max)
			elif _start_guard_on():
				_next_scav = _elapsed + 5.0   # (no safe spot yet: look again shortly, not every frame)
		return
	# With zones, later arrivals go to a zone picked by its "trickle" weight (mostly the hot zones).
	if _raider_wave < raider_times.size() and raiders_spawned < raider_budget and _elapsed >= raider_times[_raider_wave]:
		if _spawn(raider_scene, _trickle_zone("raiders")):
			_raider_wave += 1
	elif scavs_spawned < scav_budget and _elapsed >= _next_scav:
		if _spawn(enemy_scene, _trickle_zone("scavs")):
			_next_scav = _elapsed + randf_range(scav_interval_min, scav_interval_max)
		elif _start_guard_on():
			_next_scav = _elapsed + 5.0


## A zone for a later arrival, picked by "trickle" weight among zones that start with that kind of AI.
func _trickle_zone(kind: String) -> Dictionary:
	var total := 0.0
	for zone in zones:
		if int(zone.get(kind, 0)) > 0:
			total += float(zone.get("trickle", 0.0))
	var roll := randf() * total
	for zone in zones:
		if int(zone.get(kind, 0)) > 0 and float(zone.get("trickle", 0.0)) > 0.0:
			roll -= float(zone.get("trickle", 0.0))
			if roll <= 0.0:
				return zone
	return {}


## Spawns one enemy (plus maybe a Raider partner). `zone` = {} for no zone: it roams the whole map (with zones
## set, a roamer). `duo` false = never brings a Raider partner (a zone's start count is exact).
func _spawn(scene: PackedScene, zone: Dictionary = {}, duo := true) -> bool:
	if scene == null:
		return false
	var players := RaidScope.nodes(self, &"player")
	var zone_name := String(zone.get("name", ""))
	var candidates: Array[Marker3D] = []
	for child in get_children():
		if not child is Marker3D or child.get_meta("perch", false) or child.get_meta("boss_start", false):
			continue
		if zone_name != "" and String(child.get_meta("zone", "")) != zone_name:
			continue
		candidates.append(child as Marker3D)
	# Inside or outside, when the zone has both (the other kind if none of the picked kind is usable).
	var inside := candidates.filter(func(m: Marker3D) -> bool: return m.get_meta("indoor", false))
	var outside := candidates.filter(func(m: Marker3D) -> bool: return not m.get_meta("indoor", false))
	var points: Array[Marker3D] = []
	var bots := _living_bots()
	if zone_name != "" and not inside.is_empty() and not outside.is_empty():
		var first := inside if randf() < indoor_chance else outside
		points = _usable_points(first, players, bots)
		if points.is_empty():
			points = _usable_points(outside if first == inside else inside, players, bots)
	else:
		points = _usable_points(candidates, players, bots)
	if points.is_empty() and not bots.is_empty() and _elapsed <= 0.0:
		# (the raid's own start: a zone still gets its AI, the bots turn away from them, PmcAI)
		points = _usable_points(candidates, players)
	if points.is_empty():
		return false
	# ...and a point nobody is standing on: two spawned on one spot got stuck in each other for good.
	var enemies := RaidScope.nodes(self, &"enemies")
	var free := points.filter(func(m: Marker3D) -> bool:
		return enemies.all(func(e: Node) -> bool: return (e as Node3D).global_position.distance_to(m.global_position) > 2.5))
	var picked: Marker3D = (free if not free.is_empty() else points).pick_random()
	var spot := picked.global_position
	if free.is_empty():
		spot = clear_spot_near(spot, Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0)))
	var enemy := scene.instantiate() as Scav
	get_parent().add_child(enemy)
	enemy.global_position = on_floor(spot)
	# Facing any way, and a short random wait before its first patrol stop (0.15.23, owner: the town's AI looked like
	# they ran the same patrol every raid; they all set off at the same moment).
	enemy.rotation.y = randf() * TAU
	enemy._wander_time = randf_range(0.0, 8.0)
	if zone_name != "":
		enemy.home_center = zone.get("center", spot)
		enemy.home_radius = float(zone.get("radius", 0.0))
		enemy.home_height = float(zone.get("height", 0.0))
		enemy.home_avoid = zone.get("avoid", [])
		enemy.home_edge = float(zone.get("edge", 0.0))
	if picked.has_meta("building"):
		enemy.indoor_rooms = building_rooms(String(picked.get_meta("building")))
	if scene == raider_scene:
		raiders_spawned += 1
		# Sometimes a duo: a partner right next to it that follows it around.
		if duo and raiders_spawned < raider_budget and randf() < raider_duo_chance:
			var partner := raider_scene.instantiate() as Scav
			get_parent().add_child(partner)
			partner.global_position = clear_spot_near(enemy.global_position, Vector3(1.5, 0, 1.0))
			partner.follow(enemy)
			partner.home_center = enemy.home_center
			partner.home_radius = enemy.home_radius
			partner.home_height = enemy.home_height
			partner.home_avoid = enemy.home_avoid
			partner.home_edge = enemy.home_edge
			raiders_spawned += 1
	else:
		scavs_spawned += 1
		for id in scav_keys:
			if randf() < float(scav_keys[id]):
				enemy.extra_drops = enemy.extra_drops + PackedStringArray([id])
	return true


## The room spots (indoor markers) of the building called `building`.
func building_rooms(building: String) -> Array[Vector3]:
	var rooms: Array[Vector3] = []
	for child in get_children():
		if child is Marker3D and String(child.get_meta("building", "")) == building:
			rooms.append((child as Marker3D).global_position)
	return rooms


## A spot `offset` from `origin` (a spawn point) with room to stand: same floor, nothing in the way, a clear line
## back to `origin`, headroom. Tries the offset, then the same distance in other directions, then closer in;
## `origin` itself if nothing fits. (0.12.31, owner: a Raider's partner spawned inside a building stuck in the
## roof: its fixed offset had put it on a shelf right under the ceiling.)
## `spot` set down on the floor under it (0.12.38, owner: scavs spawned with their heads in the ceiling: indoor
## markers were 1.2 m up, so a 1.9 m AI's head started inside the floor above and got pushed up through it).
func on_floor(spot: Vector3) -> Vector3:
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(spot + Vector3(0, 0.3, 0), spot + Vector3(0, -3.0, 0), 1))
	return Vector3(spot.x, (hit.position as Vector3).y + 0.05, spot.z) if not hit.is_empty() else spot


func clear_spot_near(origin: Vector3, offset: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var body := CapsuleShape3D.new()
	body.radius = 0.45
	body.height = 1.9
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin + Vector3(0, 0.5, 0), origin + Vector3(0, -3, 0), 1))
	var floor_y: float = floor_hit.position.y if not floor_hit.is_empty() else origin.y - 0.1
	var reach := maxf(Vector2(offset.x, offset.z).length(), 1.0)
	for r: float in [reach, reach * 0.6, 1.0]:
		for turn in 8:
			var flat := Vector3(offset.x, 0, offset.z).normalized() if Vector2(offset.x, offset.z).length() > 0.01 else Vector3.RIGHT
			var p := origin + flat.rotated(Vector3.UP, turn * PI / 4.0 * (1 if turn % 2 == 0 else -1)) * r
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, floor_y + 0.6, p.z), Vector3(p.x, floor_y - 1.0, p.z), 1))
			if down.is_empty():
				continue
			var y: float = down.position.y
			if absf(y - floor_y) > 0.4:
				continue   # a step up onto furniture or down a drop
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = body
			q.collision_mask = 1 | 2 | 4   # (not inside a wall, a player or another AI: 0.12.35, they stacked up)
			q.transform = Transform3D(Basis(), Vector3(p.x, y + 0.05 + body.height / 2.0, p.z))
			if not space.intersect_shape(q, 1).is_empty():
				continue
			var line := PhysicsRayQueryParameters3D.create(origin + Vector3(0, 1.0, 0), Vector3(p.x, y + 1.0, p.z), 1)
			if not space.intersect_ray(line).is_empty():
				continue   # through a wall
			return Vector3(p.x, maxf(origin.y, y + 0.1), p.z)
	return origin


## The spawn points far enough from every player, preferring ones no player can see. With AI PMCs in the raid
## (`bots`, 0.36.5): only points at least BOT_CLEAR from every living bot and out of its sight. During the start
## guard only points no player's start can see, and none near one: a visible point is never a fallback then.
func _usable_points(markers: Array, players: Array[Node], bots: Array[Node] = []) -> Array[Marker3D]:
	var far: Array[Marker3D] = []
	var hidden: Array[Marker3D] = []
	var guard := _start_guard_on()
	for marker: Marker3D in markers:
		if not bots.is_empty() and not _clear_of_bots(marker, bots):
			continue
		if guard:
			if _start_safe(marker.global_position, players):
				far.append(marker)
				hidden.append(marker)
			continue
		if not _far_from_players(marker, players):
			continue
		far.append(marker)
		if not _seen_by_players(marker, players):
			hidden.append(marker)
	return hidden if not hidden.is_empty() else far


## During the start guard: no AI starts near a player's start (min_distance_from_player) and none where one can see it.
func _start_safe(pos: Vector3, players: Array[Node]) -> bool:
	for spot in _starts():
		if pos.distance_to(spot) < min_distance_from_player:
			return false
	return _far_from(pos, players) and not _seen_from_any(pos, players)


func _far_from_players(marker: Marker3D, players: Array[Node]) -> bool:
	return _far_from(marker.global_position, players)


func _far_from(pos: Vector3, players: Array[Node]) -> bool:
	for player in players:
		if player is Node3D and pos.distance_to((player as Node3D).global_position) < min_distance_from_player:
			return false
	for spot in _starts():
		if pos.distance_to(spot) < min_distance_from_player:
			return false
	return true


func _seen_by_players(marker: Marker3D, players: Array[Node]) -> bool:
	return _seen_from_any(marker.global_position, players)


func _seen_from_any(pos: Vector3, players: Array[Node]) -> bool:
	var space := get_world_3d().direct_space_state
	for player in players:
		if not player is Player:
			continue
		var eyes := (player as Player).camera.global_position
		var query := PhysicsRayQueryParameters3D.create(eyes, pos + Vector3(0, 1.4, 0), 1)
		if space.intersect_ray(query).is_empty():
			return true
	for spot in _starts():
		var query := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 1.6, 0), pos + Vector3(0, 1.4, 0), 1)
		if space.intersect_ray(query).is_empty():
			return true
	return false


## Later arrivals keep away from AI PMCs the way they keep away from players (0.36.5, owner approved): not within
## BOT_CLEAR m of a living bot, not where one can see. (No bots in the raid: nothing changes.)
const BOT_CLEAR := 40.0


## The living AI PMCs in this raid (each one is a loner: always alone).
func _living_bots() -> Array[Node]:
	var out: Array[Node] = []
	for node in RaidScope.nodes(self, &"enemies"):
		var bot := node as Scav
		if bot != null and bot.loner and bot.state != Scav.State.DEAD and not bot.health.is_dead:
			out.append(bot)
	return out


func _clear_of_bots(marker: Marker3D, bots: Array[Node]) -> bool:
	var space := get_world_3d().direct_space_state
	for node in bots:
		var bot := node as Scav
		var d := marker.global_position.distance_to(bot.global_position)
		if d < BOT_CLEAR:
			return false
		if d < bot.sight_range + 20.0:
			var eyes := bot.global_position + Vector3(0, 1.65, 0)
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(eyes, marker.global_position + Vector3(0, 1.4, 0), 1)).is_empty():
				return false
	return true
