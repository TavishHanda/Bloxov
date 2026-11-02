extends SceneTree
## Times each load step (title, hideout, raid) and their first frames (0.29.3). Not part of the smoke test. Real
## frames: xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 -s tools/load_probe.gd
## (clear user://shader_cache first for a first-time load; llvmpipe times: compare runs with each other only).

func _initialize() -> void:
	_run.call_deferred()

func _ms(t: int) -> String:
	return "%d ms" % ((Time.get_ticks_usec() - t) / 1000)

func _frames(n: int, label: String) -> void:
	var worst := 0
	var times: Array = []
	for i in n:
		var t := Time.get_ticks_usec()
		await process_frame
		var d := (Time.get_ticks_usec() - t) / 1000
		times.append(d)
		worst = maxi(worst, d)
	print("%s: %d frames, worst %d ms, first ten %s" % [label, n, worst, str(times.slice(0, 10))])

func _swap(path: String, label: String) -> Node:
	var t := Time.get_ticks_usec()
	var ps := load(path) as PackedScene
	print("%s load: %s" % [label, _ms(t)])
	t = Time.get_ticks_usec()
	var n := ps.instantiate()
	print("%s instantiate: %s" % [label, _ms(t)])
	if current_scene != null:
		current_scene.free()
	t = Time.get_ticks_usec()
	root.add_child(n)
	current_scene = n
	print("%s add_child (_ready): %s" % [label, _ms(t)])
	t = Time.get_ticks_usec()
	var marks := {}
	var mark := func(k: String) -> void:
		if not marks.has(k): marks[k] = (Time.get_ticks_usec() - t) / 1000
	physics_frame.connect(mark.bind("physics"), CONNECT_ONE_SHOT)
	process_frame.connect(mark.bind("process"), CONNECT_ONE_SHOT)
	RenderingServer.frame_pre_draw.connect(mark.bind("pre_draw"), CONNECT_ONE_SHOT)
	RenderingServer.frame_post_draw.connect(mark.bind("post_draw"), CONNECT_ONE_SHOT)
	if DisplayServer.get_name() == "headless":
		await process_frame
	else:
		await RenderingServer.frame_post_draw
	print("%s first frame: %s  %s" % [label, _ms(t), str(marks)])
	return n

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var t0 := Time.get_ticks_usec()
	await _swap("res://scenes/title.tscn", "title")
	await _frames(30, "title")
	await _swap("res://scenes/hideout_world.tscn", "hideout_world")
	await _frames(60, "hideout_world")
	RaidMap.scene_path = "res://scenes/maps/old_bloxov.tscn"
	var main := await _swap("res://scenes/main.tscn", "raid")
	await _frames(240, "raid")
	print("total %s" % _ms(t0))
	quit()
