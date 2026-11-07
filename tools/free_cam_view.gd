extends SceneTree
# Screenshots of the recording tools (0.31.12) in a raid: the pause menu's HIDE HUD / FREE CAMERA row, the free
# camera looking back at your character (touch buttons, then HUD hidden), and first person with the HUD hidden.
# xvfb-run -a godot --rendering-driver opengl3 --resolution 1560x720 -s tools/free_cam_view.gd -- out=/tmp/cam [test_map]
# Writes <out>-menu.png, <out>-free.png, <out>-touch.png, <out>-hidden.png.

func _initialize() -> void:
	_run.call_deferred()


func _shot(path: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(path)


func _run() -> void:
	var out := "/tmp/cam"
	var test_map := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a == "test_map": test_map = true
	root.size = Vector2i(1560, 720)
	if test_map:
		RaidMap.scene_path = ""
	TouchInput.layout = {}
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 10: await process_frame
	var spawner := main.get_node_or_null("EnemySpawner")
	if spawner != null:
		spawner.queue_free()
	for node in get_nodes_in_group("enemies"):
		node.queue_free()
	var player := main.get_node("Player") as Player
	var hud := main.get_node("HUD")
	var cam: FreeCam = hud.free_cam
	for i in 60: await process_frame
	# The pause menu (the mouse isn't captured).
	_shot(out + "-menu.png")
	# Free camera, looking back at yourself from the side.
	# (touch on: headless-ish runs can't capture the mouse, and a free mouse means the pause menu)
	TouchInput.set_active(true)
	TouchInput.paused = false
	TouchInput.screen_free = true
	for i in 3: await process_frame
	hud.toggle_free_cam()
	var head := player.global_position + Vector3(0, 1.2, 0)
	var spot := head + player.global_basis * Vector3(2.4, 0.6, -2.6)
	cam.camera.global_position = spot
	var look := Basis.looking_at(head - spot)
	var euler := look.get_euler(EULER_ORDER_YXZ)
	cam.yaw = euler.y
	cam.pitch = euler.x
	cam.look_by(0.0, 0.0)
	cam._want_yaw = cam.yaw
	cam._want_pitch = cam.pitch
	for i in 40: await process_frame
	_shot(out + "-touch.png")
	hud.toggle_hud()
	for i in 200: await process_frame   # (the note fades)
	_shot(out + "-free.png")
	hud.toggle_hud()
	# First person, HUD hidden.
	cam.stop()
	hud.toggle_hud()
	for i in 200: await process_frame   # (the note fades)
	_shot(out + "-hidden.png")
	print("saved ", out, "-menu/-free/-touch/-hidden.png")
	quit()
