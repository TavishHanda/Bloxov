extends SceneTree
## Pictures of the hideout's trophy shelf (lively hideout): empty, part way, and full. Changes the profile in memory
## only (never saved).   xvfb-run -a godot --rendering-driver opengl3 -s tools/hideout_trophy_view.gd -- [out=/some/dir]
var out := "/tmp/hideout_trophies/"


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
	var shelf: HideoutTrophies = world.trophies
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	cam.make_current()
	var stages := {
		"empty": [0, 0, 0, {}, [], 1],
		"some": [14, 9, 30000, {"guns": 2, "supplies": 3}, ["a", "b", "c", "d"], 2],
		"full": [140, 104, 1200000, {"guns": 4, "supplies": 4, "valuables": 3, "ming": 3, "meds": 4},
			["big_game", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s"], 99],
	}
	for name: String in stages:
		var s: Array = stages[name]
		Profile.stats["raids"] = s[0]
		Profile.stats["extracts"] = s[1]
		Profile.stats["earned"] = s[2]
		Profile.trader_levels = s[3]
		Profile.quests_done.assign(s[4])
		Profile.bench_level = mini(s[5], Crafting.max_level())
		shelf.refresh()
		cam.global_transform = shelf.global_transform.translated_local(Vector3(0.0, 1.25, -2.6))
		cam.look_at(shelf.global_transform * Vector3(0.0, 1.1, 0.0))
		for i in 10:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out + name + ".png")
	# And from the room, next to the record board.
	cam.global_transform = shelf.global_transform.translated_local(Vector3(-2.5, 1.7, -3.8))
	cam.look_at(shelf.global_transform * Vector3(-1.2, 1.1, 0.0))
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "room.png")
	print("saved trophy pictures to ", out)
	quit()
