extends SceneTree
## Pictures for a hideout tidy pass (0.39.13): a free camera at the spots given in shots.txt-style args.
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/hideout_tidy_view.gd -- out=/dir shots=/file
## shots file: one per line "name px py pz tx ty tz [fov]".
var out := "/tmp/hideout_tidy/"
var shots_file := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4).trim_suffix("/") + "/"
		elif a.begins_with("shots="):
			shots_file = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var world: Node3D = (load("res://scenes/hideout_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 120:
		await process_frame
	Profile.characters["picked"] = true                 # (no first-pick screen in the way)
	world.close_menu()
	if world.tutorial != null:
		world.tutorial.queue_free()
		world.tutorial = null
	world._click_hint.visible = false
	for n: Node in world.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var walker: HideoutWalker = world.walker
	walker.locked = true
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.near = 0.05
	for line in FileAccess.get_file_as_string(shots_file).split("\n"):
		var p := line.strip_edges().split(" ", false)
		if p.size() < 7 or p[0].begins_with("#"):
			continue
		cam.fov = float(p[7]) if p.size() > 7 else 70.0
		cam.global_position = Vector3(float(p[1]), float(p[2]), float(p[3]))
		cam.look_at(Vector3(float(p[4]), float(p[5]), float(p[6])))
		for i in 6:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out + p[0] + ".png")
		print("saved ", out + p[0] + ".png")
	quit()
