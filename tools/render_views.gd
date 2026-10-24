extends SceneTree
# Renders a few views of Bloxov Battlegrounds with the raid lighting, for checking art and lighting changes.
# xvfb-run -a godot --rendering-driver opengl3 -s tools/render_views.gd -- out=/tmp/shot  (writes /tmp/shot-<view>.png)
# look=res://assets/looks/<name>.tres renders with that look instead of the current one (Look update).
var views := [
	["town", Vector3(-55, 15, -45), Vector3(-90, 2, -100)],
	["street", Vector3(-115, 1.7, -82), Vector3(-85, 2, -100)],
	["gas", Vector3(122, 7, 182), Vector3(140, 2, 152)],
	["gastown", Vector3(-72, 5, -42), Vector3(-88, 2, -62)],
	["overview", Vector3(120, 110, 160), Vector3(0, 0, 0)],
]
func _initialize() -> void:
	var out := "/tmp/shot"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("look="): Look.current = a.substr(5)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var keep := ["WorldEnvironment", "Sun", "Clouds", "Level", "Loot"]
	for c in main.get_children():
		if not c.name in keep:
			main.remove_child(c); c.free()
	main.set_script(null)
	root.add_child(main)
	var cam := Camera3D.new(); cam.far = 2000; main.add_child(cam); cam.current = true
	root.size = Vector2i(1280, 720)
	for v in views:
		cam.look_at_from_position(v[1], v[2])
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s-%s.png" % [out, v[0]])
	quit()
