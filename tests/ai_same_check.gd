extends SceneTree
## Same-seed check for the AI brain (0.36.10): proof that a change to the shared AI code leaves scavs, Raiders,
## snipers and Bon behaving exactly as before against real players. Runs raids as the server runs them (RaidWorld,
## the map's normal AI spawns, NO AI PMCs) with fixed seeds and two scripted player bodies (proxies, which never
## die: the server passes their hits on): one standing in the first AI zone, one walking between the next two.
## Every second it logs each AI's state, plan, cover phase, position, facing, health, target and shots, and the hits
## on the players. Run it before and after a change and diff the logs: they must match line for line.
##   godot --headless --fixed-fps 60 -s tests/ai_same_check.gd -- <out file> [seconds per raid, default 120] [seeds]
## Prints AI SAME CHECK: WROTE <file> (<lines> lines).

const SEEDS: Array[int] = [101, 202]
const MAPS: Array[int] = [0, 1]

var _out := "user://ai_same.log"
var _seconds := 120
var _seeds: Array[int] = SEEDS.duplicate()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_seconds = int(args[1])
	if args.size() > 2:
		_seeds.clear()
		for s in String(args[2]).split(","):
			_seeds.append(int(s))
	_run.call_deferred()


func _run() -> void:
	var lines: PackedStringArray = []
	for map_index in MAPS:
		for s in _seeds:
			lines.append_array(await _one_raid(map_index, s))
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("AI SAME CHECK: WROTE %s (%d lines)" % [_out, lines.size()])
	quit(0)


func _one_raid(map_index: int, seed_value: int) -> PackedStringArray:
	var lines: PackedStringArray = []
	var entry: Array = RaidMap.MAPS[map_index]
	lines.append("== %s seed %d" % [entry[0], seed_value])
	seed(seed_value)
	# (the AI's mutter timer has its own dice: seeded too, so its chatter can't shift anything)
	Scav._mutter_dice.seed = seed_value
	RaidMap.scene_path = String(entry[1])
	var world := RaidWorld.new()
	root.add_child(world)
	await physics_frame
	await physics_frame
	var spawner := world.raid.get_node_or_null("EnemySpawner") as EnemySpawner
	var spots: Array[Vector3] = []
	for zone: Dictionary in spawner.zones:
		spots.append(spawner.on_floor(zone["center"]))
	while spots.size() < 3:
		spots.append(spots[0] + Vector3(10, 0, 0))
	var hits := [0]
	world.player_hit.connect(func(_peer: int, _amount: int, _from: Vector3, _head: bool, _burst: int) -> void: hits[0] += 1)
	world.player_bashed.connect(func(_peer: int, _amount: int, _from: Vector3, _shove: float, _block: float) -> void: hits[0] += 1)
	var shots := {}
	var labels := {}
	var walk_t := 0.0
	var frame := 0
	for second in _seconds:
		for f in 60:
			frame += 1
			# Player 1 stands still; player 2 walks back and forth between two zones at 3 m/s.
			world.update_proxy(1, [spots[0] + Vector3(2, 0, 2), 0.0, 0.0, 0.0, 0])
			walk_t += 1.0 / 60.0
			var leg := spots[1].distance_to(spots[2])
			var along := fmod(walk_t * 3.0, leg * 2.0)
			var u := along / leg if along <= leg else 2.0 - along / leg
			var at := spots[1].lerp(spots[2], u)
			world.update_proxy(2, [at, 0.0, 0.0, 0.0, 0])
			for node in RaidScope.nodes(world.raid, &"enemies"):
				var id := node.get_instance_id()
				if not labels.has(id):
					labels[id] = "%s#%d" % [String(node.scene_file_path).get_file().get_basename(), labels.size()]
					shots[id] = 0
					node.fired.connect(func(_end: Vector3) -> void: shots[id] += 1)
			await physics_frame
		for node in RaidScope.nodes(world.raid, &"enemies"):
			var ai := node as Scav
			var id := ai.get_instance_id()
			var target := "-"
			if ai._target != null and is_instance_valid(ai._target):
				target = String(ai._target.name)
			var p := ai.global_position
			lines.append("t=%d %s st=%s tac=%s cov=%d pos=(%.2f,%.2f,%.2f) yaw=%.3f hp=%d tgt=%s shots=%d" % [
				second + 1, labels[id], Scav.State.keys()[ai.state], Scav.Tactic.keys()[ai.tactic], ai._cover_phase,
				p.x, p.y, p.z, wrapf(ai.rotation.y, -PI, PI), ai.health.current, target, shots[id]])
		lines.append("t=%d hits=%d ai=%d" % [second + 1, hits[0], RaidScope.nodes(world.raid, &"enemies").size()])
	world.queue_free()
	await physics_frame
	await physics_frame
	return lines
