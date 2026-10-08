extends Node3D
## Keeps a few enemies alive on the map, spawning them at child Marker3D points away from every player.
## Mostly scavs (enemy_scene), sometimes a PMC (pmc_scene).

@export var enemy_scene: PackedScene
@export var pmc_scene: PackedScene
## Chance each spawn is a PMC instead of a scav.
@export_range(0.0, 1.0) var pmc_chance := 0.25
@export var max_alive := 6
@export var initial_count := 4
@export var spawn_interval := 5.0
@export var min_distance_from_player := 18.0

var _timer := 0.0


func _ready() -> void:
	# The first top-up comes one interval in, so a raid starts with exactly initial_count enemies.
	_timer = spawn_interval
	for i in initial_count:
		_spawn_one.call_deferred()


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = spawn_interval
	if get_tree().get_nodes_in_group("enemies").size() < max_alive:
		_spawn_one()


func _spawn_one() -> void:
	var players := get_tree().get_nodes_in_group("player")
	var points: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D and _far_from_players(child as Marker3D, players):
			points.append(child as Marker3D)
	if points.is_empty():
		return
	var scene := pmc_scene if pmc_scene != null and randf() < pmc_chance else enemy_scene
	var enemy := scene.instantiate() as Node3D
	get_parent().add_child(enemy)
	enemy.global_position = points.pick_random().global_position


func _far_from_players(marker: Marker3D, players: Array[Node]) -> bool:
	for player in players:
		if player is Node3D and marker.global_position.distance_to((player as Node3D).global_position) < min_distance_from_player:
			return false
	return true
