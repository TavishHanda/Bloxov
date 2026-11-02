extends SceneTree
# Screenshots of the touch controls (0.29.9) in the raid scene's test map, at a phone's shape (1560x720):
# the controls while playing (thumb on the stick, FIRE held), the item wheel, and the layout editor.
# xvfb-run -a godot --rendering-driver opengl3 --resolution 1560x720 -s tools/touch_view.gd -- out=/tmp/touch
# Writes <out>-play.png, <out>-wheel.png, <out>-edit.png.

func _initialize() -> void:
	_run.call_deferred()


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	Input.parse_input_event(event)


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	Input.parse_input_event(event)


func _run() -> void:
	var out := "/tmp/touch"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	root.size = Vector2i(1560, 720)
	RaidMap.scene_path = ""
	TouchInput.layout = {}
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 5: await process_frame
	main.get_node("EnemySpawner").queue_free()
	for node in get_nodes_in_group("enemies"):
		node.queue_free()
	var player := main.get_node("Player") as Player
	player.inventory.add("bandage", 2)
	player.inventory.add("medkit", 1)
	player.inventory.add("grenade", 2)
	player.inventory.add("energy_drink", 1)
	var hud := main.get_node("HUD")
	var touch: TouchControls = hud.touch
	TouchInput.set_active(true)
	TouchInput.paused = false
	for i in 30: await process_frame
	var size := touch.size
	# A thumb on the stick, pushed up and right, and FIRE held.
	var stick := Vector2(size.x * 0.15, size.y * 0.72)
	_touch(0, stick, true)
	await process_frame
	_drag(0, stick + Vector2(30, -50), Vector2(30, -50))
	for i in 10: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "-play.png")
	_touch(0, stick + Vector2(30, -50), false)
	# The item wheel.
	var item := touch.button_center("item")
	_touch(1, item, true)
	await process_frame
	_touch(1, item, false)
	for i in 4: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "-wheel.png")
	_touch(2, Vector2(10, size.y * 0.5), true)   # (taps off the wheel)
	_touch(2, Vector2(10, size.y * 0.5), false)
	# The layout editor, with FIRE picked.
	touch.start_edit()
	for i in 3: await process_frame
	var fire := touch.button_center("fire")
	_touch(3, fire, true)
	for i in 3: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "-edit.png")
	print("saved ", out, "-play/-wheel/-edit.png")
	quit()
