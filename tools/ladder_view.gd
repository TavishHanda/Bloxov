extends SceneTree
# First-person screenshots on a ladder (0.32.1): climbing (looking ahead and up), and getting on at the top.
# xvfb-run -a godot --rendering-driver opengl3 -s tools/ladder_view.gd -- out=/tmp/ladder
# Writes <out>-climb.png, <out>-up.png, <out>-top.png (no HUD).

func _initialize() -> void:
	_run.call_deferred()


func _shot(path: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)


func _run() -> void:
	var out := "/tmp/ladder"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	root.size = Vector2i(1280, 720)
	RaidMap.scene_path = ""
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	main.get_node("HUD").process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("HUD").visible = false
	paused = false
	for i in 5: await process_frame
	main.get_node("EnemySpawner").queue_free()
	for node in get_nodes_in_group("enemies"):
		node.queue_free()
	var player := main.get_node("Player") as Player
	var spot := Vector3(30, 0, 30)
	var block := CSGBox3D.new()
	block.size = Vector3(3, 4, 3)
	block.use_collision = true
	main.add_child(block)
	block.global_position = spot + Vector3(0, 2, -1.5)
	var ladder := (load("res://scenes/ladder.tscn") as PackedScene).instantiate() as Ladder
	ladder.height = 4.0
	main.add_child(ladder)
	ladder.global_position = spot
	player.teleport_to(spot + Vector3(0.6, 0.1, 2.0))
	player.rotation.y = 0.3
	for i in 20: await physics_frame
	player.teleport_to(spot + Vector3(0, 0.1, 1.0))
	player.rotation.y = 0.0
	for i in 10: await physics_frame
	Input.action_press("move_forward")
	for i in 40: await physics_frame
	await _shot(out + "-climb.png")
	player.head.rotation.x = 0.6
	player.rotation.y = 0.5
	for i in 10: await physics_frame
	await _shot(out + "-up.png")
	Input.action_release("move_forward")
	player.head.rotation.x = 0.0
	player.rotation.y = 0.0
	player.teleport_to(spot + Vector3(0.2, 4.1, -1.0))
	player.rotation.y = PI
	player.head.rotation.x = -0.5
	for i in 20: await physics_frame
	Input.action_press("interact")
	await physics_frame
	await physics_frame
	Input.action_release("interact")
	for i in 40: await physics_frame
	await _shot(out + "-top.png")
	quit()
