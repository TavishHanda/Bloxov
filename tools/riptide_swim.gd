extends SceneTree
## Riptide's swimming (0.33.6): checks every ladder out of the sea (place "Water") has free water at its foot and a
## free, floored spot to step onto at its top, then drops the player in the sea and has them swim to one and climb out.
##   godot --headless --fixed-fps 60 -s tools/riptide_swim.gd


func _initialize() -> void:
	_run.call_deferred()


func _free(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.9, 0))
	q.collision_mask = 1 | 128 | 256 | 512
	return space.intersect_shape(q, 1).is_empty()


func _run() -> void:
	RaidMap.scene_path = "res://scenes/maps/riptide.tscn"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var spawner := main.get_node_or_null("EnemySpawner")
	if spawner != null: spawner.queue_free()
	for i in 10: await physics_frame
	for node in get_nodes_in_group("enemies"): node.queue_free()
	var hud := main.get_node_or_null("HUD")
	if hud != null: hud.process_mode = Node.PROCESS_MODE_DISABLED
	paused = false
	var space := (main as Node3D).get_world_3d().direct_space_state
	var player := main.get_node("Player") as Player
	var bad := 0
	var ladders: Array[Ladder] = []
	for ladder: Ladder in get_nodes_in_group("ladders"):
		if String(ladder.get_meta("place", "")) != "Water": continue
		ladders.append(ladder)
		var foot := ladder.global_position
		var water := foot - ladder.into() * 0.7
		water.y = -1.3
		var top := foot + ladder.into() * 0.7
		top.y = ladder.top_y() + 0.05
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top + Vector3(0, 0.5, 0), top - Vector3(0, 0.6, 0), 1))
		var ok := _free(space, water) and _free(space, top) and not floor_hit.is_empty()
		if not ok: bad += 1
		print("%s %s  water %s  top %s  floor %s" % ["ok  " if ok else "BAD ", ladder.name, _free(space, water), _free(space, top), not floor_hit.is_empty()])
	# Swim to each ladder and climb out
	for ladder in ladders:
		var start := ladder.global_position - ladder.into() * 3.0
		start.y = 0.5
		player.teleport_to(start)
		player.rotation.y = atan2(-ladder.into().x, -ladder.into().z)   # facing into the ladder
		for i in 180: await physics_frame   # (the plunge, then bobbing up to floating height)
		var swam := player.is_swimming() and absf(player.global_position.y + 1.3) < 0.15 and not player.hands_free()
		Input.action_press("move_forward")
		var frames := 0
		while frames < 900 and not (player.is_on_floor() and player.global_position.y > ladder.top_y() - 0.2):
			await physics_frame
			frames += 1
		Input.action_release("move_forward")
		var out := player.is_on_floor() and player.global_position.y > ladder.top_y() - 0.2 and not player.is_swimming()
		if not (swam and out): bad += 1
		print("%s %s  swims %s  out in %.1f s at %s" % ["ok  " if swam and out else "BAD ", ladder.name, swam, frames / 60.0, player.global_position])
	print("SWIM: %s (%d ladders)" % ["OK" if bad == 0 else "%d BAD" % bad, ladders.size()])
	quit()
