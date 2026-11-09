extends SceneTree
## Screenshots of the burning wrecks' smoke on Bloxov Frontlines (0.32.3), close and from across the map.
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/smoke_view.gd -- out=/tmp/smoke
## Writes <out>-near.png, <out>-far.png and <out>-low.png (looking up the column from beside the wreck).

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "/tmp/smoke"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	root.size = Vector2i(1280, 720)
	RaidMap.scene_path = "res://scenes/maps/old_bloxov.tscn"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 10: await process_frame
	var spawner := main.get_node_or_null("EnemySpawner")
	if spawner != null:
		spawner.queue_free()
	for node in get_nodes_in_group("enemies"):
		node.queue_free()
	var hud := main.get_node_or_null("HUD")
	if hud != null:
		hud.visible = false
	var smoke: Node3D = null
	for n in main.find_children("Smoke*", "", true, false):
		if n is CPUParticles3D:
			smoke = n
			break
	var cam := Camera3D.new()
	cam.fov = 70.0
	main.add_child(cam)
	cam.make_current()
	var at := smoke.global_position
	for view in [["near", Vector3(14, 3, 10), 6.0], ["far", Vector3(55, 8, 40), 9.0], ["low", Vector3(4, 1.2, 3), 7.0]]:
		cam.global_position = at + view[1]
		cam.look_at(at + Vector3(0, view[2], 0))
		for i in 30: await process_frame
		root.get_viewport().get_texture().get_image().save_png(out + "-" + view[0] + ".png")
	print("saved ", out, "-near/-far/-low.png")
	quit()
