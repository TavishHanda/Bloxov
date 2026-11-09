extends SceneTree
## Pictures of the hideout's cat (lively hideout) in each of its poses, and one at home by the stove.
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/hideout_cat_view.gd -- [out=/some/dir]
var out := "/tmp/hideout_cat/"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4).trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var world: Node3D = (load("res://scenes/hideout_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 120:
		await process_frame
	world.close_menu()
	if world.tutorial != null:
		world.tutorial.queue_free()
		world.tutorial = null
	world._click_hint.visible = false
	world._hud.visible = false
	var cat: HideoutCat = world.cat
	var walker: HideoutWalker = world.walker
	walker.locked = true
	# At home by the stove, from the room.
	var home := cat.global_position
	walker.global_position = home + Vector3(-3.0, 0.0, 1.5)
	walker.camera.look_at(home + Vector3.UP * 0.3)
	for i in 30:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "home.png")
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	cam.make_current()
	# Each pose, close up from its front-left side.
	for what: String in ["sit", "groom", "loaf", "sleep", "petted", "walk"]:
		cat.rotation.y = 0.0
		cat._start(what, 999.0)
		if what == "walk":
			cat.target = cat.position + Vector3(0, 0, -0.01)
			cat._left = 999.0
			cat.set_physics_process(false)
		for i in 60:
			if what == "walk":
				cat._phase += 0.12
				cat._pose(1.0 / 60.0)
			await process_frame
		cam.global_position = cat.global_position + Vector3(-0.85, 0.55, -1.05)
		cam.look_at(cat.global_position + Vector3.UP * 0.25)
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(out + what + ".png")
		cat.set_physics_process(true)
	print("saved cat pictures to ", out)
	quit()
