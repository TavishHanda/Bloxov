extends SceneTree
## Pictures of the mess (0.36.37): the tables with the crew sat at them, from the tunnel's mouth and from above.
## Writes PNGs to the folder given (default /tmp/hideout_mess/).
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/hideout_mess_view.gd -- [out=/some/dir]
var out := "/tmp/hideout_mess/"


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
	for n: Node in world.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var crew: HideoutCrew = world.crew
	var them := crew.members.filter(func(m: Dictionary) -> bool: return m.has("act"))
	var k := 0
	for act: Dictionary in crew.acts:   # the crew into the mess's seats, as many as there are
		var at: Vector3 = act["at"]
		if act["seat"] == null or at.z < 13.0 or at.z > 23.0 or absf(at.x) > 2.5 or k >= them.size():
			continue
		var m: Dictionary = them[k]
		k += 1
		crew._leave(m)
		m["path"] = PackedVector3Array()
		crew._arrive(m, act)
		m["settle"] = 1.0
		m["wait"] = 9999.0
		(m["model"] as Node3D).position = at
		(m["model"] as Node3D).rotation.y = act["turn"]
	var walker: HideoutWalker = world.walker
	walker.locked = true
	for shot: Array in [["mess_view", Vector3(-3.2, 2.3, 12.6), Vector3(0.6, 0.3, 19.0)],
			["mess_side", Vector3(-4.0, 2.2, 19.0), Vector3(1.0, 0.4, 19.0)],
			["mess_above", Vector3(3.6, 5.0, 12.8), Vector3(0.2, 0.0, 18.8)]]:
		walker.global_position = (shot[1] as Vector3) - Vector3.UP * walker.camera.position.y
		walker.camera.look_at(shot[2])
		for i in 30:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out + shot[0] + ".png")
		print("saved ", out + shot[0] + ".png")
	quit()
