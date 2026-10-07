extends Node3D
## Keeps a few enemies alive on the map, spawning them at child Marker3D points away from the player.

@export var enemy_scene: PackedScene
@export var max_alive := 6
@export var initial_count := 4
@export var spawn_interval := 5.0
@export var min_distance_from_player := 18.0

var _timer := 0.0


func _ready() -> void:
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
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var points: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D:
			var marker := child as Marker3D
			if player == null or marker.global_position.distance_to(player.global_position) >= min_distance_from_player:
				points.append(marker)
	if points.is_empty():
		return
	var enemy := enemy_scene.instantiate() as Node3D
	get_parent().add_child(enemy)
	enemy.global_position = points.pick_random().global_position
