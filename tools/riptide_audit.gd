extends SceneTree
## Riptide's map audit (0.35.16, owner: "make sure all these kinks are worked out"): looks for places a player or
## the AI can't use. Checks that every loot container, extract, switch and AI spawn can be walked to from the shore
## (navigation), that every player spawn and AI spawn stands on a floor in free space, that every ladder has free
## room at its foot and a floored, free spot at its top, and that nothing a player stands on is under the kill height.
##   godot --headless --fixed-fps 60 -s tools/riptide_audit.gd
## Prints one line per problem and "AUDIT: OK" or "AUDIT: n to look at". Then climbs every dry ladder as a player would
## (up only: coming back down is the ladder code's business, not the map's).


## Places you only reach by a ladder (the AI doesn't climb): no walking route is expected. Sniper perches too.
const LADDER_ONLY := ["SternLadder"]


func _initialize() -> void:
	_run.call_deferred()


func _free(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.95, 0))
	q.collision_mask = 1 | 128 | 256 | 512
	return space.intersect_shape(q, 1).is_empty()


func _floor(space: PhysicsDirectSpaceState3D, at: Vector3, reach := 0.8) -> bool:
	return not space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.5, 0), at - Vector3(0, reach, 0), 1)).is_empty()


func _run() -> void:
	RaidMap.scene_path = "res://scenes/maps/riptide.tscn"
	var main: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var spawner := main.get_node_or_null("EnemySpawner")
	var marks: Array[Node] = spawner.get_children() if spawner != null else []
	var baker: NavBaker = null
	for n in main.find_children("*", "NavigationRegion3D", true, false):
		if n is NavBaker: baker = n
	if not baker.is_baked: await baker.baked
	for i in 10: await physics_frame
	var space := main.get_world_3d().direct_space_state
	var map := baker.get_navigation_map()
	var start := (main.get_node("PlayerSpawns").get_child(0) as Node3D).global_position
	var kill := float(main.get_meta("kill_height", -20.0))
	var bad := 0
	var things: Array = []   # [what, name, position]
	for n in get_nodes_in_group("loot_containers"): things.append(["loot", "%s (%s)" % [n.name, n.get_meta("place", "")], (n as Node3D).global_position])
	for n in get_nodes_in_group("extracts"): things.append(["extract", n.name, (n as Node3D).global_position])
	for n in main.find_children("*", "StaticBody3D", true, false):
		if n is MapSwitch: things.append(["switch", n.name, (n as Node3D).global_position])
	for n in marks:
		if n is Marker3D: things.append(["AI spawn", n.name, (n as Node3D).global_position])
	for n in main.get_node("PlayerSpawns").get_children(): things.append(["player spawn", n.name, (n as Node3D).global_position])
	for t: Array in things:
		var at: Vector3 = t[2]
		var near := NavigationServer3D.map_get_closest_point(map, at)
		var flat := Vector2(near.x - at.x, near.z - at.z).length()
		var problem := ""
		if at.y < kill + 2.0:
			problem = "under the kill height"
		elif flat > 2.2 or absf(near.y - at.y) > 1.6:
			problem = "no floor the AI can walk on within reach (nearest %.1f m away, %.1f m up)" % [flat, near.y - at.y]
		else:
			var q := NavigationPathQueryParameters3D.new()
			q.map = map; q.start_position = start; q.target_position = near; q.path_search_max_polygons = 0
			var r := NavigationPathQueryResult3D.new()
			NavigationServer3D.query_path(q, r)
			var ladder_only: bool = t[1] in LADDER_ONLY or (t[0] == "AI spawn" and String(t[1]).begins_with("Perch"))
			if not ladder_only and (r.path.is_empty() or r.path[r.path.size() - 1].distance_to(near) > 0.8):
				problem = "no walking route from the shore"
		if problem == "" and t[0] in ["AI spawn", "player spawn"]:
			if not _free(space, at): problem = "something solid in the way"
			elif not _floor(space, at): problem = "no floor under it"
		if problem != "":
			bad += 1
			print("%-12s %-28s %s  %s" % [t[0], t[1], at.snappedf(0.1), problem])
	# Climb every dry ladder for real: walk into its foot, hold forward, and see that you end up standing at the top
	var hud := main.get_node_or_null("HUD")
	if hud != null: hud.process_mode = Node.PROCESS_MODE_DISABLED
	if spawner != null: spawner.queue_free()
	for node in get_nodes_in_group("enemies"): node.queue_free()
	paused = false
	var player := main.get_node("Player") as Player
	var only := ""          # (one ladder place only, with more detail: `-- only=Bow`)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("only="): only = arg.substr(5)
	for ladder: Ladder in get_nodes_in_group("ladders"):
		if String(ladder.get_meta("place", "")) == "Water": continue   # (tools/riptide_swim.gd swims these)
		if only != "" and String(ladder.get_meta("place", "")) != only: continue
		var foot := ladder.global_position - ladder.into() * 1.0
		foot.y += 0.1
		var roomy := _free(space, foot)
		player.teleport_to(foot)
		player.rotation.y = atan2(-ladder.into().x, -ladder.into().z)
		for i in 20: await physics_frame
		Input.action_press("move_forward")
		var frames := 0
		while frames < 1200 and not (player.is_on_floor() and player.global_position.y > ladder.top_y() - 0.2):
			await physics_frame
			frames += 1
		Input.action_release("move_forward")
		var out := player.is_on_floor() and player.global_position.y > ladder.top_y() - 0.2
		if only != "": print("  %s up: out %s at %s" % [ladder.name, out, player.global_position.snappedf(0.01)])
		if not (roomy and out):
			bad += 1
			print("%-12s %-28s %s  %s" % ["ladder", "%s (%s)" % [ladder.name, ladder.get_meta("place", "")], ladder.global_position.snappedf(0.1),
				("no room at the foot" if not roomy else "can't climb out at the top (ended at %s)" % player.global_position.snappedf(0.1))])
	print("AUDIT: %s (%d things, %d ladders)" % ["OK" if bad == 0 else "%d to look at" % bad, things.size(), get_nodes_in_group("ladders").size()])
	quit()
