class_name EnemySpawner
extends Node3D
## Spawns a limited number of enemies per raid, spread over the raid, at child Marker3D points
## away from (and out of sight of) every player.
## Scavs: a few at the start, then one every scav_interval seconds until the budget runs out.
## Raiders (the tougher AI faction): arrive at set times (later in the raid = late-raid pressure). Dead enemies don't come back.

@export var enemy_scene: PackedScene
@export var raider_scene: PackedScene
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

## Spawned so far this raid.
var scavs_spawned := 0
var raiders_spawned := 0
var _elapsed := 0.0
var _next_scav := 0.0


func _ready() -> void:
	_next_scav = randf_range(scav_interval_min, scav_interval_max)
	for i in mini(initial_count, scav_budget):
		_spawn.call_deferred(enemy_scene)


func _physics_process(delta: float) -> void:
	tick(delta)


## Advances the raid clock by `delta` seconds and spawns whatever is due (the smoke test calls this directly).
func tick(delta: float) -> void:
	_elapsed += delta
	if get_tree().get_nodes_in_group("enemies").size() >= max_alive:
		return
	if raiders_spawned < mini(raider_budget, raider_times.size()) and _elapsed >= raider_times[raiders_spawned]:
		_spawn(raider_scene)
	elif scavs_spawned < scav_budget and _elapsed >= _next_scav:
		if _spawn(enemy_scene):
			_next_scav = _elapsed + randf_range(scav_interval_min, scav_interval_max)


func _spawn(scene: PackedScene) -> bool:
	if scene == null:
		return false
	var players := get_tree().get_nodes_in_group("player")
	var far: Array[Marker3D] = []
	var hidden: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D and _far_from_players(child as Marker3D, players):
			far.append(child as Marker3D)
			if not _seen_by_players(child as Marker3D, players):
				hidden.append(child as Marker3D)
	# Prefer points no player can see; any far point if none are hidden.
	var points := hidden if not hidden.is_empty() else far
	if points.is_empty():
		return false
	var enemy := scene.instantiate() as Node3D
	get_parent().add_child(enemy)
	enemy.global_position = points.pick_random().global_position
	if scene == raider_scene:
		raiders_spawned += 1
		# Sometimes a duo: a partner right next to it that follows it around.
		if raiders_spawned < raider_budget and randf() < raider_duo_chance:
			var partner := raider_scene.instantiate() as Scav
			get_parent().add_child(partner)
			partner.global_position = enemy.global_position + Vector3(1.5, 0, 1.0)
			partner.leader = enemy as Scav
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
