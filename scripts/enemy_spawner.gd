class_name EnemySpawner
extends Node3D
## Spawns a limited number of enemies per raid, spread over the raid, at child Marker3D points
## away from (and out of sight of) every player.
## Scavs: a few at the start, then one every scav_interval seconds until the budget runs out.
## Raiders (the tougher AI faction): arrive at set times (later in the raid = late-raid pressure). Dead enemies don't come back.

@export var enemy_scene: PackedScene
@export var raider_scene: PackedScene
@export var sniper_scene: PackedScene = preload("res://scenes/sniper.tscn")
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
## (Vector3), "radius" (m), "scavs" and "raiders" (how many start there), "trickle" (how likely later arrivals
## come here; hot zones get the most). Markers with metadata `zone` = that name are its spawn spots. AI that
## spawns in a zone patrols only that zone. With zones, initial_count is ignored and raider_times are only the
## later Raiders (the zones' own start at 0:00).
@export var zones: Array = []
## With zones: this many scavs roam the whole map instead of one zone (they start at any marker).
@export var roamers := 0
## Sniper scavs at the start (Scavs 2.0, owner): each on its own perch, picked from the markers with metadata
## `perch` (high spots: roofs, the bell tower), preferring perches no player is in sight of. They don't count
## toward the scav budget.
@export var snipers := 0
## How far a sniper can move around on its perch.
@export var perch_radius := 3.0

## Spawned so far this raid.
var scavs_spawned := 0
var raiders_spawned := 0
var _elapsed := 0.0
var _next_scav := 0.0
## With zones: how many of raider_times have come up.
var _raider_wave := 0
var snipers_spawned := 0


func _ready() -> void:
	_next_scav = randf_range(scav_interval_min, scav_interval_max)
	if snipers > 0:
		_spawn_snipers.call_deferred()
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
	var far: Array[Marker3D] = []
	var hidden: Array[Marker3D] = []
	for child in get_children():
		if not child is Marker3D or child.get_meta("perch", false):
			continue
		if zone_name != "" and String(child.get_meta("zone", "")) != zone_name:
			continue
		if _far_from_players(child as Marker3D, players):
			far.append(child as Marker3D)
			if not _seen_by_players(child as Marker3D, players):
				hidden.append(child as Marker3D)
	# Prefer points no player can see; any far point if none are hidden.
	var points := hidden if not hidden.is_empty() else far
	if points.is_empty():
		return false
	# ...and a point nobody is standing on: two spawned on one spot got stuck in each other for good.
	var enemies := RaidScope.nodes(self, &"enemies")
	var free := points.filter(func(m: Marker3D) -> bool:
		return enemies.all(func(e: Node) -> bool: return (e as Node3D).global_position.distance_to(m.global_position) > 2.5))
	var spot: Vector3 = (free if not free.is_empty() else points).pick_random().global_position
	if free.is_empty():
		spot += Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
	var enemy := scene.instantiate() as Scav
	get_parent().add_child(enemy)
	enemy.global_position = spot
	if zone_name != "":
		enemy.home_center = zone.get("center", spot)
		enemy.home_radius = float(zone.get("radius", 0.0))
	if scene == raider_scene:
		raiders_spawned += 1
		# Sometimes a duo: a partner right next to it that follows it around.
		if duo and raiders_spawned < raider_budget and randf() < raider_duo_chance:
			var partner := raider_scene.instantiate() as Scav
			get_parent().add_child(partner)
			partner.global_position = enemy.global_position + Vector3(1.5, 0, 1.0)
			partner.leader = enemy
			partner.home_center = enemy.home_center
			partner.home_radius = enemy.home_radius
			raiders_spawned += 1
	else:
		scavs_spawned += 1
	return true


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
