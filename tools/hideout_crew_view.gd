extends SceneTree
## Pictures of the hideout crew at each thing they do (HideoutCrew.acts) and one walking. Writes PNGs to the folder
## given (default /tmp/hideout_crew/).
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/hideout_crew_view.gd -- [out=/some/dir]
var out := "/tmp/hideout_crew/"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4).trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _shot(world: Node3D, name: String, eye: Vector3, at: Vector3, wait := 20) -> void:
	var walker: HideoutWalker = world.walker
	walker.locked = true
	walker.global_position = eye - Vector3.UP * walker.camera.position.y
	walker.camera.look_at(at)
	for i in wait:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("saved ", out + name + ".png")


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
	var crew: HideoutCrew = world.crew
	var them := crew.members.filter(func(m: Dictionary) -> bool: return m.has("act"))
	var k := 0
	for act: Dictionary in crew.acts:
		var m: Dictionary
		if not act["by"].is_empty():
			m = act["by"]
		else:
			m = them[k % them.size()]
			k += 1
			crew._leave(m)
			m["path"] = PackedVector3Array()
			(m["model"] as Node3D).position = act["at"]
			crew._arrive(m, act)
		m["settle"] = 1.0
		m["wait"] = 9999.0
		var model: Node3D = m["model"]
		model.position = act["at"]
		model.rotation.y = act["turn"]
		var at := model.global_position + Vector3.UP * 0.8
		var eye := at + model.global_basis * Vector3(0.9, 0.7, -2.3)
		if act["kind"] == "sleep":
			eye = at + model.global_basis * Vector3(-1.6, 0.2, 0.4)
		await _shot(world, "act_" + String(act["name"]), eye, at, 25)
	var w: Dictionary = them[0]
	for a: Dictionary in crew.acts:
		if a["by"].is_empty():
			crew._leave(w)
			w["path"] = crew.route((w["model"] as Node3D).position, a["at"])
			w["act"] = a
			a["by"] = w
			w["best"] = INF
			w["stuck"] = 0.0
			break
	for i in 40:
		await process_frame
	var wm: Node3D = w["model"]
	var wat := wm.global_position + Vector3.UP * 0.9
	await _shot(world, "walking", wat + wm.global_basis * Vector3(1.2, 0.5, -2.6), wat, 3)
	quit()
