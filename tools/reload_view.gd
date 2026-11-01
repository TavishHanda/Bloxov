extends SceneTree
# Renders each gun's reload (GunViewModels.reload_hold / reload_pose, each gun its own since 0.25.29) in the real raid
# scene, the player holding it, as frames for checking them.
# xvfb-run -a godot --rendering-driver opengl3 -s tools/reload_view.gd -- out=/tmp/reload [guns=ak,sniper] [steps=10] [empty]
# Writes <out>-<weapon>-<nn>.png (640x360): the gun at rest, then `steps` frames through the reload.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "/tmp/reload"
	var guns := ["ak", "pistol", "smg", "shotgun", "sniper"]
	var steps := 10
	var empty := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("guns="): guns = Array(a.substr(5).split(","))
		if a.begins_with("steps="): steps = int(a.substr(6))
		if a == "empty": empty = true
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
	player.teleport_to(Vector3(0, 0.1, -10))
	player.rotation.y = PI
	var gun := player.gun
	for id: String in guns:
		gun._apply_weapon(ItemStack.new(id))
		player.inventory.add(gun.ammo_id, 200)
		for i in 60: await process_frame   # raised and settled
		gun.in_mag = 0 if empty else maxi(gun.mag_size - 2, 0)
		_shot(out, id, 0)
		await RenderingServer.frame_post_draw
		_shot(out, id, 0)
		gun.start_reload()
		var length := gun.reload_time
		for k in steps:
			var until := length * float(k + 1) / float(steps + 1)
			while gun.is_reloading and length - gun._reload_left < until:
				await process_frame
			await RenderingServer.frame_post_draw
			_shot(out, id, k + 1)
		while gun.is_reloading:
			await process_frame
	quit()


func _shot(out: String, id: String, n: int) -> void:
	var img := root.get_texture().get_image()
	img.resize(640, 360)
	img.save_png("%s-%s-%02d.png" % [out, id, n])
