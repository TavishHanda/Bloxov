extends SceneTree
## Measures what the AI cost per frame on Bloxov Frontlines (0.14.4). Runs a raid with the player at its spawn,
## then the same raid with the AI switched off, and prints the difference. Not part of the smoke test:
##   godot --headless --fixed-fps 60 -s tests/perf_check.gd
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	RaidMap.scene_path = "res://scenes/maps/old_bloxov.tscn"
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	main.get_node("HUD").process_mode = Node.PROCESS_MODE_DISABLED
	for i in 120:
		await physics_frame
	var player := main.get_node("Player") as Player
	player.health.max_health = 1000000
	player.health.heal(1000000)
	var ai := get_nodes_in_group("enemies")
	Scav.lod_enabled = false
	var full := await _measure(player)
	Scav.lod_enabled = true
	await _measure(player)
	var with_ai := await _measure(player)
	var stats := {}
	for e in ai:
		var sc := e as Scav
		if is_instance_valid(sc):
			var k: String = Scav.State.keys()[sc.state] + ("/far" if sc.get("_lod_far") else "")
			stats[k] = stats.get(k, 0) + 1
	for e in ai:
		if is_instance_valid(e):
			e.process_mode = Node.PROCESS_MODE_DISABLED
	var without := await _measure(player)
	print("PERF %d AI: AI cost %.2f ms a frame (%.2f with every AI at full rate); %.2f ms without AI; %s; states %s" % [ai.size(), with_ai - without, full - without, without, ProjectSettings.get_setting("physics/3d/physics_engine"), stats])
	quit(0)

func _measure(player: Player) -> float:
	var total := 0
	for f in 600:
		var t := Time.get_ticks_usec()
		await physics_frame
		total += Time.get_ticks_usec() - t
		player.health.heal(1000000)
	return total / 600.0 / 1000.0
