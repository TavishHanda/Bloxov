extends SceneTree
## Times each step of loading a raid on each map (0.39.32): the map scene's load, the raid scene's, the collision
## shape (BoxMap.prebuild), then the raid going in and its first frames. Not part of the smoke test.
## godot --headless -s tools/map_load_probe.gd -- map=old_bloxov   (or map=riptide; xvfb + opengl3 for real frames;
## hide=Trees,Models hides nodes by name before the first frame, to see what that frame spends its time on)

func _initialize() -> void:
	_run.call_deferred()

func _ms(t: int) -> int:
	return (Time.get_ticks_usec() - t) / 1000

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var map := "old_bloxov"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="): map = a.substr(4)
	var path := "res://scenes/maps/%s.tscn" % map
	if not ResourceLoader.exists(path): path = "res://scenes/maps/%s.scn" % map
	var t0 := Time.get_ticks_usec()
	var t := t0
	var ps := load(path) as PackedScene
	print("%s map load: %d ms" % [map, _ms(t)])
	t = Time.get_ticks_usec()
	var raid := load("res://scenes/main.tscn") as PackedScene
	print("%s raid scene load: %d ms" % [map, _ms(t)])
	t = Time.get_ticks_usec()
	var held := BoxMap.prebuild(ps)
	print("%s prebuild: %d ms" % [map, _ms(t)])
	RaidMap.scene_path = path
	t = Time.get_ticks_usec()
	var n := raid.instantiate()
	root.add_child(n)
	current_scene = n
	print("%s raid add_child: %d ms" % [map, _ms(t)])
	t = Time.get_ticks_usec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("hide="):
			for want in a.substr(5).split(","):
				for x in n.find_children(want, "Node3D", true, false):
					(x as Node3D).visible = false
	var t1 := Time.get_ticks_usec()
	var marks := {}
	var mark := func(k: String) -> void:
		if not marks.has(k): marks[k] = (Time.get_ticks_usec() - t1) / 1000
	physics_frame.connect(mark.bind("physics_start"), CONNECT_ONE_SHOT)
	process_frame.connect(mark.bind("process_start"), CONNECT_ONE_SHOT)
	RenderingServer.frame_pre_draw.connect(mark.bind("pre_draw"), CONNECT_ONE_SHOT)
	RenderingServer.frame_post_draw.connect(mark.bind("post_draw"), CONNECT_ONE_SHOT)
	var fr := []
	for i in 6:
		var f := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw if DisplayServer.get_name() != "headless" else process_frame
		fr.append(_ms(f))
	print("%s first frames: %s  marks %s" % [map, str(fr), str(marks)])
	print("%s TOTAL: %d ms" % [map, _ms(t0)])
	BoxMap.let_go(held)
	quit()
