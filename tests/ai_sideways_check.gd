extends SceneTree
## Real-map check that AI don't run sideways in fights (0.12.28, owner: "the AI was just moving sideways again").
## Puts the player 12-30 m from up to 14 AI on Bloxov Battlegrounds, one at a time, and measures how long each one
## moves sideways (perpendicular to where it's facing). Slow (a few minutes), so not part of the smoke test:
##   godot --headless --fixed-fps 60 -s tests/ai_sideways_check.gd
## Prints SIDEWAYS CHECK: PASSED when no AI runs sideways for 2 s or more at a time. (Before 0.12.28: up to 6.5 s.)
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	RaidMap.scene_path = "res://scenes/maps/old_bloxov.tscn"
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	main.get_node("HUD").process_mode = Node.PROCESS_MODE_DISABLED
	for i in 60:
		await physics_frame
	var player := main.get_node("Player") as Player
	player.health.max_health = 1000000
	player.health.heal(1000000)
	var space: PhysicsDirectSpaceState3D = (main as Node3D).get_world_3d().direct_space_state
	var all := []
	for e in get_nodes_in_group("enemies"):
		all.append(e)
	var tot := {}
	var n := 0
	var worst := 0.0
	for e in all:
		var sc := e as Scav
		if not is_instance_valid(sc) or sc.holds_position or n >= 14:
			continue
		# park everyone else far away so they don't join
		for o in all:
			if is_instance_valid(o) and o != sc:
				o.process_mode = Node.PROCESS_MODE_DISABLED
		sc.process_mode = Node.PROCESS_MODE_INHERIT
		var placed := false
		for attempt in 30:
			var spot: Vector3 = sc.global_position + Vector3([12.0, 20.0, 30.0].pick_random(), 0, 0).rotated(Vector3.UP, randf() * TAU)
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 40, spot + Vector3.DOWN * 40, 1))
			if hit.is_empty() or hit.position.y > sc.global_position.y + 3 or hit.position.y < sc.global_position.y - 3:
				continue
			var los: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(sc.global_position + Vector3.UP * 1.5, hit.position + Vector3.UP * 1.5, 1))
			if not los.is_empty():
				continue
			player.teleport_to(hit.position + Vector3.UP * 0.1)
			placed = true
			break
		if not placed:
			continue
		n += 1
		sc._target = player
		sc._alert(player.global_position)
		var modes := {}
		var side := 0
		var frames := 0
		var longest := 0
		var run := 0
		for f in 60 * 15:
			await physics_frame
			if not is_instance_valid(sc):
				break
			frames += 1
			var v := Vector3(sc.velocity.x, 0, sc.velocity.z)
			var to := player.global_position - sc.global_position
			to.y = 0
			var mode: String = "%s/%s" % [Scav.State.keys()[sc.state], Scav.Cover.keys()[sc._cover_phase]]
			var fwd := -sc.global_basis.z
			fwd.y = 0
			if v.length() > 1.0 and absf(v.normalized().dot(fwd.normalized())) < 0.5:
				side += 1
				run += 1
				longest = maxi(longest, run)
				modes[mode] = modes.get(mode, 0) + 1
			else:
				run = 0
			player.health.heal(1000000)
		var kind: String = sc.scene_file_path.get_file()
		print("SIDE %s %s at (%.0f,%.0f) d=%.0f: sideways %.0f%%, longest run %.1f s, by mode %s" % [kind, sc.name, sc.global_position.x + 175, sc.global_position.z + 175, sc.global_position.distance_to(player.global_position), 100.0 * side / maxi(frames, 1), longest / 60.0, modes])
		worst = maxf(worst, longest / 60.0)
		for k in modes:
			tot[k] = tot.get(k, 0) + modes[k]
		sc.queue_free()
	print("SIDE TOTAL ", tot)
	print("SIDEWAYS CHECK: %s (longest sideways run %.1f s)" % ["PASSED" if worst < 2.0 else "FAILED", worst])
	quit(0 if worst < 2.0 else 1)
