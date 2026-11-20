extends SceneTree
## Pictures of the traders at their counters in the walkable hideout (HideoutCrew), seen from where you'd stand to
## trade: one still per trader, plus frames every `step` seconds for `secs` seconds (for a clip or a contact sheet).
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/trader_idle_view.gd -- [out=/some/dir] [secs=12] [step=0.1]
##   [only=guns] [beats]   (beats: a still of each thing they do, <out>/<trader>_<beat>.png)
##     (frames are <out>/<trader>/f0000.png ...; ffmpeg turns them into a clip)
var out := "/tmp/trader_idle/"
var secs := 0.0
var step := 0.1
var only := ""
var beats := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4).trim_suffix("/") + "/"
		elif a.begins_with("secs="):
			secs = float(a.substr(5))
		elif a.begins_with("step="):
			step = float(a.substr(5))
		elif a == "beats":
			beats = true
		elif a.begins_with("only="):
			only = a.substr(5)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(960, 720)
	var world: Node3D = (load("res://scenes/hideout_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 120:
		await process_frame
	world.close_menu()
	if world.tutorial != null:
		world.tutorial.queue_free()
		world.tutorial = null
	world._click_hint.visible = false
	var crew: HideoutCrew = world.crew
	var walker: HideoutWalker = world.walker
	walker.locked = true
	for m: Dictionary in crew.members:
		var id := String(m["id"])
		if not id.begins_with("trader_") or (only != "" and id != "trader_" + only):
			continue
		var model: Node3D = m["model"]
		var at := model.global_position + Vector3.UP * 1.15
		var eye := at + model.global_basis * Vector3(0.3, 0.5, -2.1)
		walker.global_position = eye - Vector3.UP * walker.camera.position.y
		walker.camera.look_at(at)
		crew.set_process(true)
		for i in 90:
			await process_frame
		var name := id.trim_prefix("trader_")
		root.get_viewport().get_texture().get_image().save_png(out + name + ".png")
		print("saved ", out + name + ".png")
		var idle: TraderIdle = m.get("idle")
		m["near"] = false
		crew.walker = null   # (from here on they don't see you: they get on with things)
		crew.set_process(false)
		if beats:   # each thing they do, settled into
			for b: String in ["work", "lean", "tap", "fold", "think", "shelf"]:
				idle._go(b)
				for i in 30:
					crew._process(0.1)
				await process_frame
				await process_frame
				root.get_viewport().get_texture().get_image().save_png(out + name + "_" + b + ".png")
		crew.walker = walker
		crew.set_process(true)
		if secs <= 0.0:
			continue
		crew.walker = null
		DirAccess.make_dir_recursive_absolute(out + name)
		var frames := int(secs / step)
		crew.set_process(false)   # (fixed steps: the clip plays at real speed whatever the render rate)
		var order: Array = TraderIdle.BEATS[name].keys() if idle != null else []
		for f in frames:
			if idle != null and f % int(3.0 / step) == 0:   # (a clip shows a bit of each: 3 s at each thing they do)
				idle._go(order[(f / int(3.0 / step)) % order.size()])
			crew._process(step)
			await process_frame
			root.get_viewport().get_texture().get_image().save_png(out + name + "/f%04d.png" % f)
		crew.walker = walker
		crew.set_process(true)
	quit()
