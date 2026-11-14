extends SceneTree
## Runs real raids inside the stripped server pack (0.30.9): models and textures are placeholders there, so this
## catches server code that needs them. Run from OUTSIDE the project folder, with the pack as the game:
##   godot --headless --main-pack build/server/bloxov_server.pck -s "$PWD/tools/server_pack_check.gd" -- [raids] [map]
## Raids alternate between the maps (RaidMap.MAPS); `map` (0, 1...) puts them all on that one, to measure it.
## Prints each raid's AI count and the process memory, and `SERVER PACK: OK` at the end. CI fails on any ERROR.

var _raids := 2
var _worlds: Array = []
var _frame := 0
var _only_map := -1


func _rss_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return 0.0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmRSS"):
			return float(line.split(":")[1].strip_edges().split(" ", false)[0]) / 1024.0
	return 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_raids = int(args[0])
	if not ResourceLoader.exists("res://scripts/raid_world.gd"):
		push_error("no raid_world.gd: run this with --main-pack <server pack>")
		quit(1)
		return
	if args.size() > 1:
		_only_map = int(args[1])


## The raids, made once the tree is running (a raid reads its map as it enters the tree, so each needs its map set
## just before it, as Network does). Every other raid on the next map (0.35.0), so each map is checked in the pack.
func _make_raids() -> void:
	var world_script: Script = load("res://scripts/raid_world.gd")
	var map_script: Script = load("res://scripts/raid_map.gd")
	var maps: Array = map_script.get_script_constant_map()["MAPS"]
	if _only_map >= 0:
		maps = [maps[_only_map]]
	for i in _raids:
		map_script.set("scene_path", maps[i % maps.size()][1])
		var world: Node = world_script.new()
		root.add_child(world)
		_worlds.append(world)
		print("server pack: raid %d on %s" % [i + 1, maps[i % maps.size()][0]])


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_make_raids()
	if _frame == 3:
		# Six player bodies in each raid and two minutes of the spawner, like a busy raid.
		for world in _worlds:
			for peer in 6:
				world.update_proxy(peer + 1, [Vector3(randf() * 20.0, 0.0, randf() * 20.0), 0.0, 0.0, 0.0, 0])
			# Three AI PMCs, spawned as the server does (0.36.2: at the free player spawn points, with names).
			var bots: Array = world.spawn_bots(3, randi(), [0], ["Tester"])
			if bots.size() != 3:
				push_error("raid made %d AI PMCs, not 3" % bots.size())
			var spawner: Node = world.raid.get_node_or_null("EnemySpawner")
			if spawner != null:
				for t in 120:
					spawner.tick(1.0)
	if _frame < 120:
		return false
	var ai := 0
	for world in _worlds:
		ai += world.raid.find_children("*", "CharacterBody3D", true, false).size()
	print("server pack: %d raids, %d bodies, %.0f MB" % [_raids, ai, _rss_mb()])
	if ai < _raids * 6:
		push_error("raids came up without their bodies")
		return true
	print("SERVER PACK: OK")
	return true
