extends SceneTree
# Renders a few views from inside buildings with the raid lighting (indoor brightness checks, 0.20.10).
# xvfb-run -a godot --rendering-driver opengl3 -s tools/render_indoors.gd -- out=/tmp/in [look=res://assets/looks/<name>.tres]
# Views are taken next to searchable spots that have a roof over them, so they land inside rooms.
func _initialize() -> void:
	var out := "/tmp/in"
	var count := 6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("look="): Look.current = a.substr(5)
		if a.begins_with("count="): count = int(a.substr(6))
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var keep := ["WorldEnvironment", "Sun", "Clouds", "Level", "Loot"]
	for c in main.get_children():
		if not c.name in keep:
			main.remove_child(c); c.free()
	main.set_script(null)
	root.add_child(main)
	var cam := Camera3D.new(); cam.far = 2000; cam.fov = 80; main.add_child(cam); cam.current = true
	root.size = Vector2i(960, 540)
	for i in 4: await physics_frame
	var space := main.get_viewport().world_3d.direct_space_state
	var spots: Array[Vector3] = []
	for n in main.find_children("*", "Node3D", true, false):
		if not (n is Node3D) or n.get_script() == null or not str(n.get_script().resource_path).ends_with("loot_container.gd"):
			continue
		var p: Vector3 = (n as Node3D).global_position
		var up := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, 30, 0), 1)
		if space.intersect_ray(up).is_empty():
			continue
		if spots.any(func(s: Vector3) -> bool: return s.distance_to(p) < 25.0):
			continue
		spots.append(p)
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x + a.z * 0.37 < b.x + b.z * 0.37)
	var step := maxi(1, spots.size() / count)
	var k := 0
	for i in range(0, spots.size(), step):
		var p := spots[i]
		# stand back from the spot in the most open direction, eye height
		var best := Vector3.ZERO
		var best_d := 0.0
		for a in 8:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, a * TAU / 8.0)
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.6, 0), p + Vector3(0, 1.6, 0) + dir * 4.0, 1)
			var hit := space.intersect_ray(q)
			var d: float = 4.0 if hit.is_empty() else ((hit.position as Vector3) - (p + Vector3(0, 1.6, 0))).length()
			if d > best_d: best_d = d; best = dir
		var eye := p + Vector3(0, 1.6, 0) + best * maxf(best_d - 0.4, 0.5)
		cam.look_at_from_position(eye, p + Vector3(0, 0.6, 0))
		for f in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s-%d.png" % [out, k])
		k += 1
	quit()
