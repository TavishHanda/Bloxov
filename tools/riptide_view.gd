extends SceneTree
# Pictures of the Riptide gray box (map 2) from fixed spots, plus a check that every player spawn stands on
# something.
# xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 -s tools/riptide_view.gd -- out=/tmp/rip
# Writes <out>-<view>.png.

const VIEWS := {
	"mid": [Vector3(-12, 22, 60), Vector3(-34, 2, 100)],
	"stern": [Vector3(46.5, 3.2, 121), Vector3(48, 0.8, 106)],
	"aft-top": [Vector3(48, 45, 75), Vector3(48, 4, 40)],
	"overview": [Vector3(-215, 150, 175), Vector3(-30, -10, 0)],
	"overview-ship": [Vector3(130, 90, -150), Vector3(10, 0, 20)],
	"road": [Vector3(-160, 4.2, -2), Vector3(-60, 4, 0)],
	"terminal": [Vector3(-136, 4.2, -99.4), Vector3(-60, 4, -99.4)],
	"apron": [Vector3(-36, 4.2, -66), Vector3(-36, 4, 60)],
	"plaza": [Vector3(-66, 4.2, 30), Vector3(-108, 14, -20)],
	"gallery": [Vector3(-34, 15.6, 43.5), Vector3(20, 15.6, 43.5)],
	"from-quay": [Vector3(-34, 4.2, 30), Vector3(48, 8, 0)],
	"mole": [Vector3(-26, 4.1, -121), Vector3(40, 3, -116)],
	"barges": [Vector3(-26, 2.8, 124.5), Vector3(50, 2, 116)],
	"fore-deck": [Vector3(39, 5.6, -87), Vector3(50, 6, 0)],
	"drill-floor": [Vector3(33, 13.6, -12.5), Vector3(62, 13, 12)],
	"aft-deck": [Vector3(62, 5.6, 70), Vector3(40, 5, 18)],
	"shipyard": [Vector3(-40, 12, 128), Vector3(-100, 3, 150)],
	"hold": [Vector3(48, -2.5, -88), Vector3(48, -3, 0)],
	"moon-pool": [Vector3(39, -6.3, -7.7), Vector3(56, -17, 4)],
	"moon-pool-up": [Vector3(44, -20.4, 4), Vector3(50, 6, -4)],
	"core": [Vector3(48, -10.6, 39), Vector3(48, -17, 56)],
	"moon": [Vector3(39.5, -6.3, -7.5), Vector3(52, -12, 6)],
	"dock": [Vector3(48, -10.5, 4), Vector3(48, -11.5, 26)],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "/tmp/rip"
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("view="): only = a.substr(5)
	RaidMap.scene_path = "res://scenes/maps/riptide.tscn"
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
		hud.process_mode = Node.PROCESS_MODE_DISABLED   # (it pauses the raid with nobody at the keys; the rain needs time to run)
		paused = false
		for c in hud.get_children():
			if c is CanvasItem: c.visible = false
			if c is CanvasLayer: c.visible = false
	var player := main.get_node("Player") as Node3D
	# Every player spawn: drop the player there and see where they end up.
	var spawns := main.get_node("PlayerSpawns").get_children()
	for s: Node3D in spawns:
		player.global_position = s.global_position + Vector3(0, 0.2, 0)
		player.set("velocity", Vector3.ZERO)
		for i in 40: await physics_frame
		var fell := s.global_position.y - player.global_position.y
		print("spawn %s at %s -> y %.2f%s" % [s.name, s.global_position, player.global_position.y, "  FELL" if fell > 1.0 else ""])
	player.global_position = Vector3(-170, 3, -100)
	var cam := Camera3D.new()
	cam.far = 900.0
	main.add_child(cam)
	cam.current = true
	for view: String in VIEWS:
		if only != "" and view != only:
			continue
		var at: Vector3 = VIEWS[view][0]
		var target: Vector3 = VIEWS[view][1]
		cam.global_position = at
		cam.look_at(target)
		for i in 8: await process_frame
		if main.get_node_or_null("Rain") != null: await create_timer(1.2).timeout   # (time for the rain to fall into view)
		root.get_viewport().get_texture().get_image().save_png("%s-%s.png" % [out, view])
		var rain := main.get_node_or_null("Rain")
		print("saved ", view, "" if rain == null else "  (rain %s)" % ("falling" if rain.get_child(0).emitting else "stopped: under cover"))
	quit()
