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
	"moon-pool-up": [Vector3(44, -10.6, 4), Vector3(50, 6, -4)],
	"core": [Vector3(48, -15.6, 41), Vector3(48, -17, 56)],
	"moon": [Vector3(39.5, -6.3, -7.5), Vector3(52, -12, 6)],
	"dock": [Vector3(48, -10.5, 4), Vector3(48, -11.5, 26)],
	# the Leviathan's outside (art step 1)
	"ship-bow": [Vector3(100, 12, -135), Vector3(56, 3, -96)],
	"ship-bow-west": [Vector3(12, 7, -120), Vector3(34, 3, -94)],
	"ship-east": [Vector3(120, 12, -40), Vector3(60, 2, -10)],
	"ship-stern": [Vector3(80, 10, 150), Vector3(48, 2, 105)],
	"ship-west": [Vector3(4, 8, -70), Vector3(30, 3, -40)],
	"ship-deck-fore": [Vector3(48, 22, -100), Vector3(48, 2, -40)],
	"ship-deck-aft": [Vector3(30, 20, 72), Vector3(52, 3, 30)],
	"ship-derrick": [Vector3(80, 30, -30), Vector3(48, 22, 0)],
	"ship-crane": [Vector3(42, 6, -55), Vector3(36, 10, -62)],
	"ship-under-drill": [Vector3(60, 5.6, -20), Vector3(40, 7, 6)],
	"ship-containers": [Vector3(56, 6, -40), Vector3(44, 6, -70)],
	"ship-drill-top": [Vector3(52, 14, -12), Vector3(44, 14, 11)],
	# its signs close up (every sign gets a close-up before it ships)
	"sign-drill-w": [Vector3(36.6, 13.4, -18.5), Vector3(36.6, 12.7, -14)],
	"sign-drill-e": [Vector3(59.4, 13.4, 18.5), Vector3(59.4, 12.7, 14)],
	"sign-driller": [Vector3(40.5, 14.4, 11), Vector3(43.8, 14.6, 11)],
	"sign-shack": [Vector3(49.9, 13.4, 5.5), Vector3(49.9, 13.2, 8.3)],
	"sign-focsle": [Vector3(36.6, 5.5, -85.5), Vector3(36.6, 5.4, -90)],
	"sign-draft": [Vector3(71, 1.6, -99.5), Vector3(66, 1.2, -102.4)],
	"sign-stern": [Vector3(48, 3.8, 121), Vector3(48, 3.2, 110)],
	"sign-name-e": [Vector3(80, 3, -73), Vector3(66, 2.5, -73)],
	"ship-top-bow": [Vector3(48, 55, -62), Vector3(48, 0, -100)],
	"ship-top-stern": [Vector3(48, 45, 72), Vector3(48, 0, 106)],
	"ship-high": [Vector3(150, 100, -190), Vector3(48, 0, -30)],
	"ship-bow-high": [Vector3(100, 38, -142), Vector3(46, 0, -92)],
	"ship-stern-high": [Vector3(98, 30, 150), Vector3(48, 0, 100)],
	"focsle": [Vector3(36, 10.5, -90.5), Vector3(52, 7.5, -104)],
	"fore-peak": [Vector3(48, -1.5, -93), Vector3(36, -3, -101)],
	"bow-store": [Vector3(48, 5.8, -91), Vector3(42, 4.5, -103)],
	"aft-corner": [Vector3(56, 7.5, 107.5), Vector3(66, 4.5, 107)],
	# the bridge tower (art step 2)
	"tower-front": [Vector3(48, 14, 48), Vector3(48, 10, 80)],
	"tower-sea": [Vector3(92, 16, 78), Vector3(58, 10, 92)],
	"tower-stern": [Vector3(76, 16, 134), Vector3(48, 10, 102)],
	"tower-port": [Vector3(6, 14, 104), Vector3(34, 10, 88)],
	"tower-helideck": [Vector3(36, 21, 104), Vector3(58, 17.5, 78)],
	"in-armory": [Vector3(43, 5.7, 86), Vector3(35, 4.8, 75)],
	"in-store": [Vector3(45, 5.7, 86), Vector3(56, 4.8, 74.5)],
	"in-workshop": [Vector3(35, 5.7, 94), Vector3(58, 4.8, 105)],
	"in-mess": [Vector3(35, 9.2, 86), Vector3(43.5, 8, 75)],
	"in-galley": [Vector3(45, 9.2, 86), Vector3(56, 8, 75)],
	"in-cabins": [Vector3(35, 9.2, 94), Vector3(58, 8, 105.5)],
	"in-corridor": [Vector3(34.6, 9.2, 90), Vector3(60, 8.6, 90)],
	"in-sickbay": [Vector3(43, 12.7, 86), Vector3(35, 11.5, 75)],
	"in-office": [Vector3(45, 12.7, 86), Vector3(56, 11.5, 75)],
	"in-officers": [Vector3(35, 12.7, 94), Vector3(58, 11.5, 105.5)],
	"in-bridge": [Vector3(43, 16.2, 86), Vector3(36, 15.2, 74)],
	"in-bridge-e": [Vector3(45, 16.2, 86), Vector3(56, 15.2, 74)],
	"in-chart": [Vector3(35, 16.2, 94), Vector3(58, 15.2, 105.5)],
	# below decks (art step 3)
	"in-hold-fore": [Vector3(38, -1.4, -90), Vector3(50, -3.5, -50)],
	"in-hold-mid": [Vector3(40, -1.6, 22), Vector3(50, -3.5, 50)],
	"in-hold-aft": [Vector3(48, -1.6, 72), Vector3(48, -3, 20)],
	"in-passage-w": [Vector3(33, -2.3, -90), Vector3(33, -3, -20)],
	"in-passage-e": [Vector3(63, -2.3, 72), Vector3(63, -3, 0)],
	"in-workshop-w": [Vector3(40, -2.3, 75), Vector3(40, -3, 96)],
	"in-workshop-e": [Vector3(46, -2.3, 76), Vector3(56, -3.5, 98)],
	"in-pump": [Vector3(53, -6.3, -58), Vector3(40, -7.5, -90)],
	"in-pump-e": [Vector3(40, -6.3, -90), Vector3(58, -7.5, -62)],
	"in-bilge": [Vector3(35, -6.3, -54), Vector3(48, -7, 10)],
	"in-engine": [Vector3(48, -6.3, 32), Vector3(48, -7, 90)],
	"in-engine-close": [Vector3(48, -6.3, 52), Vector3(40, -7.2, 62)],
	"in-tank": [Vector3(36, -6.3, -30), Vector3(50, -7.5, -5)],
	"in-bow-stairs": [Vector3(45.5, -2.3, -76.5), Vector3(50, -5, -86)],
	"bow-head": [Vector3(36, 6.5, -62), Vector3(48, 5, -82)],
	"in-lathe": [Vector3(33, -2.3, 92.5), Vector3(36.5, -3.6, 85)],
	"in-engine-back": [Vector3(60, -6.3, 100), Vector3(44, -7, 40)],
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
	var spawns := [] if "nospawn" in OS.get_cmdline_user_args() else main.get_node("PlayerSpawns").get_children()
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
	if "norain" in OS.get_cmdline_user_args() and main.get_node_or_null("Rain") != null:
		main.get_node("Rain").free()   # (clearer pictures of the art)
	await create_timer(2.0).timeout   # (the raid's opening fade)
	for view: String in VIEWS:
		if only != "" and not view in only.split(","):
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
