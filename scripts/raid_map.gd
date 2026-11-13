class_name RaidMap
extends Node3D
## The raid scene (main.tscn) holds everything a raid needs (player, HUD, raid rules, spawner) plus a small built-in
## test map. Real maps (0.10.0: Bloxov Frontlines) are their own scenes in `scenes/maps/`: when a raid scene is made, the
## chosen map's pieces replace the test map's (the contents of Level, Loot, Extracts, PlayerSpawns and the
## spawner's markers move in; the nodes themselves stay, so everything that points at them keeps working).
## This runs as soon as the raid scene is instantiated (before anything is ready), on players' games and on the
## server's raid copies alike, so both always use the same map.

## The map every raid uses. "" = the built-in test map (the smoke test uses that, its checks are built around it).
static var scene_path := FRONTLINES

const FRONTLINES := "res://scenes/maps/old_bloxov.tscn"
## The maps a raid can be on (map 2, Riptide: a gray box for now). Solo: the hideout's MAP button. Online (0.33.8):
## the party leader picks, the server runs each raid on its map. The order is the map's number on the network:
## only add to the end.
const MAPS := [["FRONTLINES", FRONTLINES], ["RIPTIDE", "res://scenes/maps/riptide.tscn"]]

## Nodes of the raid scene whose contents come from the map.
const SLOTS := ["Level", "Loot", "Extracts", "PlayerSpawns"]
## The map's enemy spawn markers (they become the EnemySpawner's children).
const ENEMY_SPAWNS := "EnemySpawns"


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		ShaderWarm.stop()   # (the raid builds whatever is left itself)
		Look.apply(self)
		load_map(self, scene_path)
		LoadingScreen.cover(self)


## Swaps the test map in `raid` for the map scene at `path`. A map's `spawner` metadata (a Dictionary of
## EnemySpawner settings) tunes the AI for its size.
static func load_map(raid: Node, path: String) -> void:
	if path == "":
		return
	var map := (load(path) as PackedScene).instantiate()
	for slot in SLOTS:
		_move_contents(map.get_node_or_null(slot), raid.get_node_or_null(slot))
	# What the in-raid map (M, MapHUD) draws.
	for key in ["minimap", "map_name"]:
		if map.has_meta(key):
			raid.set_meta(key, map.get_meta(key))
	var spawner := raid.get_node_or_null("EnemySpawner")
	_move_contents(map.get_node_or_null(ENEMY_SPAWNS), spawner)
	if spawner != null:
		var settings: Dictionary = map.get_meta("spawner", {})
		for key in settings:
			spawner.set(key, settings[key])
	# A map's `raid` metadata tunes the raid itself (Riptide: a 15-minute clock, owner 2026-11-09).
	var raid_node := raid.get_node_or_null("Raid")
	if raid_node != null:
		var raid_settings: Dictionary = map.get_meta("raid", {})
		for key in raid_settings:
			raid_node.set(key, raid_settings[key])
	# A map can have its own look and weather (Riptide: the storm, owner 2026-11-09). Looks only.
	if map.has_meta("look"):
		Look.apply(raid, String(map.get_meta("look")))
	if map.get_meta("rain", false) and DisplayServer.get_name() != "headless":
		var rain := Rain.new()
		rain.name = "Rain"
		raid.add_child(rain)
	# Anything else the map has (e.g. its key-door markers) goes straight under the raid.
	for child in map.get_children():
		if not SLOTS.has(String(child.name)) and child.name != ENEMY_SPAWNS:
			_set_owner(child, null)
			map.remove_child(child)
			raid.add_child(child)
			_set_owner(child, raid)
	# The test map's practice target isn't part of a real map.
	var dummy := raid.get_node_or_null("TargetDummy")
	if dummy != null:
		raid.remove_child(dummy)
		dummy.free()
	map.free()


## Frees what's in `into` and moves everything from `from` into it (same names, same places).
static func _move_contents(from: Node, into: Node) -> void:
	if from == null or into == null:
		return
	for old in into.get_children():
		into.remove_child(old)
		old.free()
	for child in from.get_children():
		_set_owner(child, null)
		from.remove_child(child)
		into.add_child(child)
		_set_owner(child, into.owner if into.owner != null else into)


## Map nodes keep belonging to a scene (the raid's), except the insides of instanced scenes (loot containers),
## which stay their own.
static func _set_owner(node: Node, new_owner: Node) -> void:
	node.owner = new_owner
	if node.scene_file_path != "":
		return
	for child in node.get_children():
		_set_owner(child, new_owner)
