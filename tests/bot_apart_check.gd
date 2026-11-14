extends SceneTree
## Proof for the AI PMCs' keep-apart rule (0.36.5): full-length raids on the real maps, run as the server runs them
## (RaidWorld, the normal AI spawns plus 3 bots, no players), sampling every second each bot's distance to the nearest
## non-bot AI and to the nearest other bot. Slow (several minutes), so not part of the smoke test:
##   godot --headless --fixed-fps 60 -s tests/bot_apart_check.gd -- [raids per map, default 10] [maps, e.g. 0,1] [out file]
## PASS marks (owner's brief): bots spend under 1% of raid time within 30 m of non-bot AI, and never within 15 m.
## Prints a summary per map and BOT APART CHECK: PASSED / FAILED; the summary also goes to [out file] when given.

const BOTS := 3
const AT_ONCE := 5
const NEAR := 30.0
const NEVER := 15.0

var _per_map := 10
var _maps: Array[int] = [0, 1]
var _out := ""
var _diag := OS.get_environment("DIAG") != ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_per_map = int(args[0])
	if args.size() > 1:
		_maps.clear()
		for m in String(args[1]).split(","):
			_maps.append(int(m))
	if args.size() > 2:
		_out = args[2]
	_run.call_deferred()


func _run() -> void:
	var lines: PackedStringArray = []
	var passed := true
	lines.append("AI PMC keep-apart check (v%s): %d raids per map, %d bots each, normal AI spawns, no players" % [
		ProjectSettings.get_setting("application/config/version"), _per_map, BOTS])
	for map_index in _maps:
		var entry: Array = RaidMap.MAPS[map_index]
		var probe := (load(String(entry[1])) as PackedScene).instantiate()
		var raid_time := float((probe.get_meta("raid", {}) as Dictionary).get("raid_time", 600.0))
		probe.free()
		var stats := {"samples": 0, "near": 0, "min_ai": INF, "min_bot": INF, "visits": 0, "top": 0, "bots": 0,
			"places": [], "turned": 0, "ai": 0, "searches": 0}
		var done := 0
		while done < _per_map:
			var batch := mini(AT_ONCE, _per_map - done)
			await _run_batch(String(entry[1]), raid_time, batch, done, stats)
			done += batch
			print("  %s: %d/%d raids" % [entry[0], done, _per_map])
		var share := float(stats["near"]) / maxf(stats["samples"], 1.0)
		var ok: bool = share < 0.01 and stats["min_ai"] >= NEVER
		passed = passed and ok
		var per_bot: Array = stats["places"]
		per_bot.sort()
		var avg := 0.0
		for n: int in per_bot:
			avg += n
		avg /= maxf(per_bot.size(), 1.0)
		lines.append("%s (%d s raids): time within %d m of non-bot AI %.2f%% (%d of %d bot-seconds); closest ever to non-bot AI %.1f m, to another bot %.1f m; %s" % [
			entry[0], raid_time, NEAR, share * 100.0, stats["near"], stats["samples"], stats["min_ai"], stats["min_bot"], "PASS" if ok else "FAIL"])
		lines.append("  places visited per bot: average %.1f, min %d, max %d (%d bots); visits to top-third-value places %.0f%% (%d of %d); %.1f containers searched per bot; turned away %d times; %.0f AI per raid at the end" % [
			avg, per_bot[0] if not per_bot.is_empty() else 0, per_bot[-1] if not per_bot.is_empty() else 0, stats["bots"],
			100.0 * stats["top"] / maxf(stats["visits"], 1.0), stats["top"], stats["visits"], float(stats["searches"]) / maxf(stats["bots"], 1.0), stats["turned"], float(stats["ai"]) / _per_map])
	lines.append("BOT APART CHECK: %s" % ("PASSED" if passed else "FAILED"))
	for line in lines:
		print(line)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(lines) + "\n")
			f.close()
	quit(0 if passed else 1)


func _run_batch(path: String, raid_time: float, count: int, first: int, stats: Dictionary) -> void:
	var worlds: Array[RaidWorld] = []
	var bots: Array = []
	for i in count:
		seed(7000 + first + i)
		RaidMap.scene_path = path
		var world := RaidWorld.new()
		root.add_child(world)
		worlds.append(world)
		# (as the server does: in the frame the raid starts, before the spawner's own deferred start)
		bots.append(world.spawn_bots(BOTS, 7000 + first + i, [], []))
	var t := 0.0
	while t < raid_time:
		for f in 60:
			await physics_frame
		t += 1.0
		for i in count:
			for bot: Node in bots[i]:
				if not is_instance_valid(bot) or (bot as Scav).state == Scav.State.DEAD:
					continue
				var me := (bot as Node3D).global_position
				var near_ai := INF
				var near_bot := INF
				var who: Scav = null
				for node in RaidScope.nodes(worlds[i].raid, &"enemies"):
					var other := node as Scav
					if other == null or other == bot or other.state == Scav.State.DEAD:
						continue
					var d := other.global_position.distance_to(me)
					if other is PmcAI:
						near_bot = minf(near_bot, d)
					elif d < near_ai:
						near_ai = d
						who = other
				if _diag and near_ai < NEAR:
					var pmc := bot as PmcAI
					print("DIAG r%d t=%d bot%d %s/%s at %s | %s %s at %s d=%.1f" % [first + i, t, bot.get_instance_id() % 1000,
						Scav.State.keys()[pmc.state], PmcAI.Plan.keys()[pmc.plan], me.snapped(Vector3.ONE), who.scene_file_path.get_file(),
						Scav.State.keys()[who.state], who.global_position.snapped(Vector3.ONE), near_ai])
				stats["samples"] += 1
				if near_ai < NEAR:
					stats["near"] += 1
				stats["min_ai"] = minf(stats["min_ai"], near_ai)
				stats["min_bot"] = minf(stats["min_bot"], near_bot)
	for i in count:
		var list := PmcAI.places(worlds[i].raid)
		var values: Array = list.map(func(p: Dictionary) -> float: return p["value"])
		values.sort()
		var cut: float = values[int(values.size() * 2 / 3)] if not values.is_empty() else 0.0
		var by_name := {}
		for p: Dictionary in list:
			by_name[p["name"]] = p
		stats["ai"] += RaidScope.nodes(worlds[i].raid, &"enemies").size()
		for bot: Node in bots[i]:
			if not is_instance_valid(bot):
				continue
			var pmc := bot as PmcAI
			stats["bots"] += 1
			stats["places"].append(pmc.visited.size())
			stats["turned"] += pmc.turned_away
			stats["searches"] += pmc._searched.size()
			for n in pmc.visited:
				stats["visits"] += 1
				if by_name.has(n) and float(by_name[n]["value"]) >= cut:
					stats["top"] += 1
		worlds[i].queue_free()
	await physics_frame
	await physics_frame
