extends SceneTree
## Pictures of your corner (lively hideout) with each spot's options, and the picker. Changes the profile in memory
## only (never saved: Decor.pick isn't used).
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/hideout_decor_view.gd -- [out=/some/dir]
var out := "/tmp/hideout_decor/"


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
	for i in 100:
		await process_frame
	world.close_menu()
	if world.tutorial != null:
		world.tutorial.queue_free()
		world.tutorial = null
	world._hud.visible = false
	Profile.stats["raids"] = 999
	Profile.stats["extracts"] = 999
	Profile.stats["earned"] = 9999999
	Profile.trader_levels = {"guns": 4, "supplies": 4, "valuables": 4, "ming": 4, "meds": 4}
	Profile.quests_done.assign(["big_game", "a", "b", "c", "d", "e", "f", "g", "h", "i"])
	var corner: HideoutDecor = world.decor
	var cam := Camera3D.new()
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	# One picture per "set": the n-th option of every spot (the last one where a spot has fewer).
	for n in 6:
		for spot: String in Decor.SPOTS:
			var list: Array = Decor.SPOTS[spot]
			var entry: Array = list[mini(n, list.size() - 1)]
			Profile.decor[spot] = entry[0]
		corner.refresh()
		cam.global_position = corner.global_transform * Vector3(-0.2, 1.75, 27.3)
		cam.look_at(corner.global_transform * Vector3(-3.4, 0.7, 29.0))
		for i in 8:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out + "set%d.png" % n)
	# The picker, over the corner, with a few things still locked.
	Profile.stats["raids"] = 7
	Profile.stats["extracts"] = 4
	Profile.stats["earned"] = 20000
	Profile.trader_levels = {}
	Profile.quests_done.assign(["a"])
	Profile.decor = {"poster": "nova", "flag": "bloxov", "rug": "olive", "lamp": "desk", "plant": "cactus", "blanket": "red"}
	corner.refresh()
	world._hud.visible = true
	world.open_decor()
	world.decor_picker.show_spot("poster")
	cam.global_position = corner.global_transform * Vector3(-1.3, 1.6, 28.6)
	cam.look_at(corner.global_transform * Vector3(-3.9, 0.9, 29.2))
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "picker.png")
	print("saved corner pictures to ", out)
	quit()
