extends SceneTree
## Long sightlines on Riptide (map 2). Every 5 m over the map, finds the open-air spots a player can stand on (the
## top surface, on the AI's walkable area), then counts, for each, how many of the others it can see from far away
## (FAR_MIN..FAR_MAX metres, standing eye to chest, through walls, cover and doors). A spot seen from many far spots
## is a place you get shot from across the map. Prints a report by area and writes a heat map (red = seen a lot).
##   godot --headless -s tools/riptide_sight.gd -- out=/tmp/sight

const STEP := 5.0
const FAR_MIN := 60.0
const FAR_MAX := 260.0
const EYE := 1.6
const BODY := 1.1
const MASK := 1 | 16          # the world and doors: what stops a shot
const FROM := Vector3(-110, 2.5, 0)   # the plaza: every walkable spot is reached from here
const EXPOSED := 30           # seen from at least this many far spots = "exposed"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "/tmp/sight"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	RaidMap.scene_path = "res://scenes/maps/riptide.tscn"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var baker: NavBaker = null
	for n in main.find_children("*", "NavigationRegion3D", true, false):
		if n is NavBaker: baker = n
	if not baker.is_baked: await baker.baked
	var spawner := main.get_node_or_null("EnemySpawner")
	if spawner != null: spawner.queue_free()
	for node in get_nodes_in_group("enemies"): node.queue_free()
	(main.get_node("Player") as Node3D).global_position = Vector3(0, -200, 0)
	for i in 5: await physics_frame
	var map_rid := baker.get_navigation_map()
	var size := 440.0
	var offset := -220.0
	var level := main.find_child("Riptide", true, false)
	if level != null and level.has_meta("minimap"):
		size = float(level.get_meta("minimap")["size"])
		offset = float(level.get_meta("minimap")["offset"])
	var space := (main as Node3D).get_world_3d().direct_space_state
	# 1. The open-air standing spots
	var pts: Array[Vector3] = []
	var x := offset
	while x <= offset + size:
		var z := offset
		while z <= offset + size:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -40, z), 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and hit.position.y > 0.6:
				var p: Vector3 = hit.position
				var near := NavigationServer3D.map_get_closest_point(map_rid, p)
				if absf(near.y - p.y) < 0.6 and Vector2(near.x - p.x, near.z - p.z).length() < 1.5:
					# only spots you can walk to (not roofs or the tops of stacks): a path from the plaza gets there
					var path := _path(map_rid, FROM, near)
					if path.size() > 0 and path[path.size() - 1].distance_to(near) < 1.0:
						pts.append(p)
			z += STEP
		x += STEP
	print("sight: %d open-air spots" % pts.size())
	# 2. Far views between them
	var seen := PackedInt32Array()
	seen.resize(pts.size())
	var rays := 0
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var d := pts[i].distance_to(pts[j])
			if d < FAR_MIN or d > FAR_MAX: continue
			rays += 1
			var a := pts[i] + Vector3(0, EYE, 0)
			var b := pts[j] + Vector3(0, BODY, 0)
			var q1 := PhysicsRayQueryParameters3D.create(a, b, MASK)
			if not space.intersect_ray(q1).is_empty(): continue
			var q2 := PhysicsRayQueryParameters3D.create(pts[j] + Vector3(0, EYE, 0), pts[i] + Vector3(0, BODY, 0), MASK)
			if not space.intersect_ray(q2).is_empty(): continue
			seen[i] += 1
			seen[j] += 1
	# 3. Report by area
	var areas := {"shore": [], "crossings": [], "ship (open decks)": [], "all": []}
	for i in pts.size():
		var p := pts[i]
		var area := "shore" if p.x < -29.0 else ("ship (open decks)" if p.x > 29.5 and p.x < 66.5 and p.z > -105 and p.z < 111 else "crossings")
		areas[area].append(seen[i])
		areas["all"].append(seen[i])
	for area in areas:
		var list: Array = areas[area]
		if list.is_empty(): continue
		var total := 0
		var exposed := 0
		for v in list:
			total += v
			if v >= EXPOSED: exposed += 1
		print("  %-18s %4d spots, seen from %5.1f far spots on average, %3d%% exposed (seen from %d+)" % [area, list.size(),
			float(total) / list.size(), 100 * exposed / list.size(), EXPOSED])
	print("sight: %d rays" % rays)
	# 4. Heat map: 2 px per metre
	var px := 2.0
	var img := Image.create(int(size * px), int(size * px), false, Image.FORMAT_RGB8)
	img.fill(Color(0.1, 0.18, 0.24))
	for i in pts.size():
		var t := clampf(seen[i] / 60.0, 0.0, 1.0)
		var c := Color(0.2, 0.75, 0.3).lerp(Color(1.0, 0.85, 0.1), minf(t * 2.0, 1.0)) if t < 0.5 else Color(1.0, 0.85, 0.1).lerp(Color(0.9, 0.1, 0.1), (t - 0.5) * 2.0)
		var cx := int((pts[i].x - offset) * px)
		var cz := int((pts[i].z - offset) * px)
		img.fill_rect(Rect2i(cx - int(STEP), cz - int(STEP), int(STEP * px), int(STEP * px)), c)
	img.save_png(out + ".png")
	print("sight: heat map -> %s.png" % out)
	quit()


func _path(map_rid: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	# (map_get_path gives up after 4096 polygons, which a path across this map passes)
	var q := NavigationPathQueryParameters3D.new()
	q.map = map_rid
	q.start_position = from
	q.target_position = to
	q.path_search_max_polygons = 0
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	return r.path
