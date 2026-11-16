extends SceneTree
## Fight report for the AI PMCs (0.36.11; it was the keep-apart proof, tests/bot_apart_check.gd, until the owner took
## that rule out): full-length raids on the real maps, run as the server runs them (RaidWorld, the normal AI spawns
## plus 3 bots, no players), five at a time. Slow (several minutes), so not part of the smoke test:
##   godot --headless --fixed-fps 60 -s tests/bot_raid_report.gd -- [raids per map, default 10] [maps, e.g. 0,1] [out file]
## Per map it reports: bots still in the raid at 5:00 and at the end, extracted, and killed (and by what kind: bot,
## scav, Raider, sniper, Bon, other); non-bot AI killed by bots per raid (by kind) and non-bot AI alive at the end;
## containers searched, items taken and places visited per bot; seconds a bot spends fighting (ALERT / ENGAGE) per raid;
## bot bodies carrying taken loot (and its average value); and the wall-clock milliseconds per simulated physics frame
## of one raid (a rough server-load figure), over the whole raid and over its first 30 s. No pass or fail marks.
## The summary goes to the output and to [out file] when given.

const BOTS := 3
const AT_ONCE := 5
const MID := 300.0
const EARLY := 30.0
const KINDS := ["bot", "scav", "raider", "sniper", "boss", "other"]

var _per_map := 10
var _maps: Array[int] = [0, 1]
var _out := ""


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
	lines.append("AI PMC raid report (v%s): %d raids per map, %d bots each, normal AI spawns, no players" % [
		ProjectSettings.get_setting("application/config/version"), _per_map, BOTS])
	for map_index in _maps:
		var entry: Array = RaidMap.MAPS[map_index]
		var probe := (load(String(entry[1])) as PackedScene).instantiate()
		var raid_time := float((probe.get_meta("raid", {}) as Dictionary).get("raid_time", 600.0))
		probe.free()
		var st := {"bots": 0, "mid": 0, "end": 0, "left": 0, "dead": 0, "killed_by": _zero_kinds(), "ai_killed": _zero_kinds(),
			"ai_end": 0, "places": 0, "searched": 0, "taken": 0, "fight": 0.0, "bodies": 0, "body_value": 0,
			"us_all": 0, "frames_all": 0, "us_early": 0, "frames_early": 0}
		var done := 0
		while done < _per_map:
			var batch := mini(AT_ONCE, _per_map - done)
			await _run_batch(String(entry[1]), raid_time, batch, done, st)
			done += batch
			print("  %s: %d/%d raids" % [entry[0], done, _per_map])
		var n := float(_per_map)
		var b := maxf(st["bots"], 1.0)
		lines.append("%s (%d s raids, %d bots):" % [entry[0], raid_time, st["bots"]])
		lines.append("  bots in the raid at 5:00 %d (%.0f%%), at the end %d (%.0f%%); extracted %d; killed %d" % [
			st["mid"], 100.0 * st["mid"] / b, st["end"], 100.0 * st["end"] / b, st["left"], st["dead"]])
		lines.append("  bots killed by: %s" % _kinds_text(st["killed_by"]))
		lines.append("  non-bot AI killed by bots per raid: %.1f (%s); non-bot AI alive at the end per raid: %.1f" % [
			_kinds_total(st["ai_killed"]) / n, _kinds_text(st["ai_killed"], n), st["ai_end"] / n])
		lines.append("  per bot: %.1f containers searched, %.1f items taken, %.1f places visited; %.0f s fighting (ALERT/ENGAGE) per raid" % [
			st["searched"] / b, st["taken"] / b, st["places"] / b, st["fight"] / b])
		lines.append("  bot bodies carrying taken loot: %d, average worth $%.0f" % [st["bodies"], float(st["body_value"]) / maxf(st["bodies"], 1.0)])
		lines.append("  server load: %.2f ms per physics frame of one raid over the whole raid, %.2f ms over its first %d s" % [
			st["us_all"] / 1000.0 / maxf(st["frames_all"], 1.0), st["us_early"] / 1000.0 / maxf(st["frames_early"], 1.0), int(EARLY)])
	for line in lines:
		print(line)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(lines) + "\n")
			f.close()
	quit(0)


func _zero_kinds() -> Dictionary:
	var d := {}
	for k: String in KINDS:
		d[k] = 0
	return d


func _kinds_total(d: Dictionary) -> float:
	var t := 0.0
	for k: String in d:
		t += d[k]
	return t


func _kinds_text(d: Dictionary, per := 1.0) -> String:
	var parts: PackedStringArray = []
	for k: String in KINDS:
		parts.append(("%s %.1f" if per != 1.0 else "%s %d") % [k, d[k] / per if per != 1.0 else d[k]])
	return ", ".join(parts)


static func _kind_of(ai: Node) -> String:
	if ai is PmcAI:
		return "bot"
	var file := String(ai.scene_file_path).get_file().get_basename()
	return file if file in ["scav", "raider", "sniper"] else ("boss" if file == "boss" else "other")


func _run_batch(path: String, raid_time: float, count: int, first: int, st: Dictionary) -> void:
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
	# Per raid: instance id -> kind of every AI seen (killers may be gone by the time we look), a death hook on each, and
	# a note per bot (updated each second while it is there).
	var kinds: Array[Dictionary] = []
	var seen: Array[Dictionary] = []
	var notes: Array[Dictionary] = []
	var killed_by: Array[Array] = []   # [victim id, victim kind, killer id]
	for i in count:
		kinds.append({})
		seen.append({})
		notes.append({})
		killed_by.append([])
	var watch := func(i: int) -> void:
		for node in RaidScope.nodes(worlds[i].raid, &"enemies"):
			var ai := node as Scav
			if ai == null or seen[i].has(ai.get_instance_id()):
				continue
			var id := ai.get_instance_id()
			seen[i][id] = true
			kinds[i][id] = _kind_of(ai)
			ai.health.died.connect(func() -> void: killed_by[i].append([id, kinds[i][id], ai.killer_ai_id]))
	var t := 0.0
	var mid_done := false
	var us_all := 0
	var us_early := 0
	while t < raid_time:
		var began := Time.get_ticks_usec()
		for f in 60:
			if f % 15 == 0:
				for i in count:
					watch.call(i)
			await physics_frame
		var spent := Time.get_ticks_usec() - began
		us_all += spent
		if t < EARLY:
			us_early += spent
		t += 1.0
		for i in count:
			for entry in bots[i]:
				if not is_instance_valid(entry) or (entry as Scav).state == Scav.State.DEAD:
					continue
				var bot := entry as PmcAI
				var worth := 0
				for stack: ItemStack in bot.carried_loot:
					worth += ItemDB.value(stack.id) * stack.count
				var note: Dictionary = notes[i].get(bot.get_instance_id(), {"fight": 0.0})
				note["places"] = bot.visited.size()
				note["searched"] = bot._searched.size()
				note["taken"] = bot._taken
				note["worth"] = worth
				if bot.state in [Scav.State.ALERT, Scav.State.ENGAGE]:
					note["fight"] += 1.0
				notes[i][bot.get_instance_id()] = note
		if not mid_done and t >= MID:
			mid_done = true
			for i in count:
				for entry in bots[i]:
					if is_instance_valid(entry) and (entry as Scav).state != Scav.State.DEAD and not (entry as PmcAI).left_raid:
						st["mid"] += 1
	st["us_all"] += us_all
	st["frames_all"] += int(raid_time) * 60
	st["us_early"] += us_early
	st["frames_early"] += int(EARLY) * 60
	for i in count:
		var dead_bot_ids := {}
		for entry in bots[i]:
			st["bots"] += 1
			var alive := is_instance_valid(entry) and (entry as Scav).state != Scav.State.DEAD
			if alive:
				st["end"] += 1
		for death: Array in killed_by[i]:
			var killer_kind: String = kinds[i].get(death[2], "other") if death[2] != 0 else "other"
			if death[1] == "bot":
				st["dead"] += 1
				st["killed_by"][killer_kind] += 1
				dead_bot_ids[death[0]] = true
			elif killer_kind == "bot":
				st["ai_killed"][death[1]] += 1
		# (a bot gone with no body and no death note extracted)
		st["left"] += BOTS - int(dead_bot_ids.size()) - _alive_count(bots[i])
		for id: int in notes[i]:
			var note: Dictionary = notes[i][id]
			st["places"] += note["places"]
			st["searched"] += note["searched"]
			st["taken"] += note["taken"]
			st["fight"] += note["fight"]
			if dead_bot_ids.has(id) and note["worth"] > 0:
				st["bodies"] += 1
				st["body_value"] += note["worth"]
		for node in RaidScope.nodes(worlds[i].raid, &"enemies"):
			var ai := node as Scav
			if ai != null and not ai is PmcAI and ai.state != Scav.State.DEAD:
				st["ai_end"] += 1
		worlds[i].queue_free()
	await physics_frame
	await physics_frame


func _alive_count(list: Array) -> int:
	var n := 0
	for entry in list:
		if is_instance_valid(entry) and (entry as Scav).state != Scav.State.DEAD:
			n += 1
	return n
