extends SceneTree
## Pictures of the hideout's life (lively hideout): the generator's fan and exhaust, the dripping tap, grit off the
## roof after a shell. Writes PNGs to the folder given (default /tmp/hideout_life/).
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/hideout_life_view.gd -- [out=/some/dir]
var out := "/tmp/hideout_life/"


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
	var life: Node3D = world.get_node("Level/Life")
	var gen: Vector3 = life.get_meta(&"generator")
	await _shot(world, "generator", gen + Vector3(-3.2, 1.7, 2.2), gen + Vector3(-0.3, 0.9, 0.0), 60)
	var drip: Vector3 = life.get_meta(&"drip")
	await _shot(world, "tap", drip + Vector3(0.6, 0.45, -1.1), drip + Vector3(0, -0.1, 0), 10)
	life.start_rat()
	life._rat_pause = 0.0
	var rat_at: Vector3 = life.get_meta(&"rat")
	var rat_to: Vector3 = life.get_meta(&"rat_to")
	await _shot(world, "rat", rat_at.lerp(rat_to, 0.5) + Vector3(0.3, 1.0, -1.6), rat_at.lerp(rat_to, 0.5), 30)
	var spawn: Vector3 = (world.get_node("Level/Spawn") as Node3D).global_position
	world.walker.global_position = spawn
	await _shot(world, "before_shell", spawn + Vector3(0, 1.6, 0), spawn + Vector3(0, 1.4, -6), 10)
	world.walker.rotation.y = 0.0
	world.war.shell()
	await _shot(world, "shell", spawn + Vector3(0, 1.6, 0), spawn + Vector3(0, 3.0, -6), 50)
	await _shot(world, "shell_later", spawn + Vector3(0, 1.6, 0), spawn + Vector3(0, 2.0, -6), 50)
	quit()
