class_name EnemySpawner
extends Node3D
## Spawns a limited number of enemies per raid, spread over the raid, at child Marker3D points
## away from (and out of sight of) every player.
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
## rather than outside (0.12.23, owner: some AI inside, so you have to clear buildings).
@export_range(0.0, 1.0) var indoor_chance := 0.5
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

## Spawned so far this raid.
var scavs_spawned := 0
var raiders_spawned := 0
var _elapsed := 0.0
var _next_scav := 0.0
## With zones: how many of raider_times have come up.
var _raider_wave := 0
var snipers_spawned := 0
## The boss of this raid (null if none).
var boss_spawned: Scav = null
## Where the guards walk around the boss (right/back in its facing), the first three; more get random spots.
const GUARD_OFFSETS: Array[Vector3] = [Vector3(2.5, 0, 1.5), Vector3(-2.5, 0, 1.5), Vector3(0, 0, 3.5)]


func _ready() -> void:
	_next_scav = randf_range(scav_interval_min, scav_interval_max)
	if snipers > 0:
		_spawn_snipers.call_deferred()
	if not boss.is_empty() and randf() < float(boss.get("chance", 1.0)):
		_spawn_boss.call_deferred()
	if not zones.is_empty():
		_spawn_zones.call_deferred()
		return
	for i in mini(initial_count, scav_budget):
		_spawn.call_deferred(enemy_scene)


## Puts the snipers on their perches: random ones, but not where a player is already in its sights.
func _spawn_snipers() -> void:
	var players := RaidScope.nodes(self, &"player")
	var perches: Array[Marker3D] = []
	var watched: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D and child.get_meta("perch", false):
			if _perch_sees_player(child as Marker3D, players):
				watched.append(child as Marker3D)
			else:
				perches.append(child as Marker3D)
	perches.shuffle()
	watched.shuffle()
	perches.append_array(watched)
	for perch in perches.slice(0, snipers):
		var sniper := sniper_scene.instantiate() as Scav
		get_parent().add_child(sniper)
		sniper.global_position = perch.global_position
		var face: Vector3 = perch.get_meta("face", Vector3.FORWARD)
		sniper.rotation.y = atan2(-face.x, -face.z)
		sniper.home_center = perch.global_position
		sniper.home_radius = perch_radius
		snipers_spawned += 1


func _perch_sees_player(perch: Marker3D, players: Array[Node]) -> bool:
	var space := get_world_3d().direct_space_state
	for player in players:
		if player is Node3D and perch.global_position.distance_to((player as Node3D).global_position) < 120.0:
			var query := PhysicsRayQueryParameters3D.create(perch.global_position + Vector3(0, 1.6, 0),
				(player as Node3D).global_position + Vector3(0, 1.4, 0), 1)
			if space.intersect_ray(query).is_empty():
				return true
	return false


## The boss and its guards, at a spot in its zone: inside its building if the map has start spots for it (markers
## with metadata `boss_start`; owner, 0.12.18). They patrol the zone together; guards follow the boss and carry on
## patrolling the zone on their own if it dies.
func _spawn_boss() -> void:
	var zone := {}
	for z in zones:
		if z.get("name", "") == boss.get("zone", ""):
			zone = z
	var spots: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D and child.get_meta("boss_start", false):
			spots.append(child as Marker3D)
	if spots.is_empty():
		for child in get_children():
			if child is Marker3D and String(child.get_meta("zone", "")) == String(zone.get("name", "")):
				spots.append(child as Marker3D)
	if zone.is_empty() or spots.is_empty() or boss_scene == null:
		return
	var spot := spots.pick_random().global_position as Vector3
	boss_spawned = boss_scene.instantiate() as Scav
	get_parent().add_child(boss_spawned)
	boss_spawned.global_position = spot
	boss_spawned.home_center = zone.get("center", spot)
	boss_spawned.home_radius = float(zone.get("radius", 0.0))
	for i in int(boss.get("guards", 0)):
		var guard := raider_scene.instantiate() as Scav
		get_parent().add_child(guard)
		var offset := GUARD_OFFSETS[i] if i < GUARD_OFFSETS.size() else Vector3(randf_range(-4, 4), 0, randf_range(2, 5))
		guard.follow_offset = offset
		guard.global_position = clear_spot_near(spot, offset)
		guard.follow(boss_spawned)
		guard.home_center = boss_spawned.home_center
		guard.home_radius = boss_spawned.home_radius
		guard.stays_home = true   # (owner: Bon and his guards patrol their area, they don't run to every gunshot)
		guard.leash = boss_spawned.leash


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
	if RaidScope.nodes(self, &"enemies").size() >= max_alive:
		return
	if zones.is_empty():
		if raiders_spawned < mini(raider_budget, raider_times.size()) and _elapsed >= raider_times[raiders_spawned]:
			_spawn(raider_scene)
		elif scavs_spawned < scav_budget and _elapsed >= _next_scav:
			if _spawn(enemy_scene):
				_next_scav = _elapsed + randf_range(scav_interval_min, scav_interval_max)
		return
	# With zones, later arrivals go to a zone picked by its "trickle" weight (mostly the hot zones).
	if _raider_wave < raider_times.size() and raiders_spawned < raider_budget and _elapsed >= raider_times[_raider_wave]:
		if _spawn(raider_scene, _trickle_zone("raiders")):
			_raider_wave += 1
	elif scavs_spawned < scav_budget and _elapsed >= _next_scav:
		if _spawn(enemy_scene, _trickle_zone("scavs")):
			_next_scav = _elapsed + randf_range(scav_interval_min, scav_interval_max)


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
	if zone_name != "" and not inside.is_empty() and not outside.is_empty():
		var first := inside if randf() < indoor_chance else outside
		points = _usable_points(first, players)
		if points.is_empty():
			points = _usable_points(outside if first == inside else inside, players)
	else:
		points = _usable_points(candidates, players)
	if points.is_empty():
		return false
	# ...and a point nobody is standing on: two spawned on one spot got stuck in each other for good.
	var enemies := RaidScope.nodes(self, &"enemies")
	var free := points.filter(func(m: Marker3D) -> bool:
		return enemies.all(func(e: Node) -> bool: return (e as Node3D).global_position.distance_to(m.global_position) > 2.5))
	var spot: Vector3 = (free if not free.is_empty() else points).pick_random().global_position
	if free.is_empty():
		spot = clear_spot_near(spot, Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0)))
	var enemy := scene.instantiate() as Scav
	get_parent().add_child(enemy)
	enemy.global_position = spot
	if zone_name != "":
		enemy.home_center = zone.get("center", spot)
		enemy.home_radius = float(zone.get("radius", 0.0))
		enemy.home_avoid = zone.get("avoid", [])
		enemy.home_edge = float(zone.get("edge", 0.0))
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
			partner.home_avoid = enemy.home_avoid
			partner.home_edge = enemy.home_edge
			raiders_spawned += 1
	else:
		scavs_spawned += 1
	return true


## A spot `offset` from `origin` (a spawn point) with room to stand: same floor, nothing in the way, a clear line
## back to `origin`, headroom. Tries the offset, then the same distance in other directions, then closer in;
## `origin` itself if nothing fits. (0.12.31, owner: a Raider's partner spawned inside a building stuck in the
## roof: its fixed offset had put it on a shelf right under the ceiling.)
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
			q.collision_mask = 1
			q.transform = Transform3D(Basis(), Vector3(p.x, y + 0.05 + body.height / 2.0, p.z))
			if not space.intersect_shape(q, 1).is_empty():
				continue
			var line := PhysicsRayQueryParameters3D.create(origin + Vector3(0, 1.0, 0), Vector3(p.x, y + 1.0, p.z), 1)
			if not space.intersect_ray(line).is_empty():
				continue   # through a wall
			return Vector3(p.x, maxf(origin.y, y + 0.1), p.z)
	return origin


## The spawn points far enough from every player, preferring ones no player can see.
func _usable_points(markers: Array, players: Array[Node]) -> Array[Marker3D]:
	var far: Array[Marker3D] = []
	var hidden: Array[Marker3D] = []
	for marker: Marker3D in markers:
		if _far_from_players(marker, players):
			far.append(marker)
			if not _seen_by_players(marker, players):
				hidden.append(marker)
	return hidden if not hidden.is_empty() else far


func _far_from_players(marker: Marker3D, players: Array[Node]) -> bool:
	for player in players:
		if player is Node3D and marker.global_position.distance_to((player as Node3D).global_position) < min_distance_from_player:
			return false
	return true


func _seen_by_players(marker: Marker3D, players: Array[Node]) -> bool:
	var space := get_world_3d().direct_space_state
	for player in players:
		if not player is Player:
			continue
		var eyes := (player as Player).camera.global_position
		var query := PhysicsRayQueryParameters3D.create(eyes, marker.global_position + Vector3(0, 1.4, 0), 1)
		if space.intersect_ray(query).is_empty():
			return true
	return false
