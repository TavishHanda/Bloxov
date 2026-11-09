extends SceneTree
# Pictures of the Riptide gray box (map 2) from fixed spots, plus a check that every player spawn stands on
# something.
# xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 -s tools/riptide_view.gd -- out=/tmp/rip
# Writes <out>-<view>.png.

const VIEWS := {
	"overview": [Vector3(-150, 140, 150), Vector3(30, -10, 0)],
	"shore": [Vector3(-165, 9, 30), Vector3(-90, 2, -10)],
	"pier": [Vector3(-90, 5, -6), Vector3(30, 4, 2)],
	"ship-side": [Vector3(-10, 22, -60), Vector3(48, 4, 10)],
	"deck": [Vector3(34, 9, -84), Vector3(52, 4, 40)],
	"tower": [Vector3(20, 26, 130), Vector3(48, 10, 90)],
	"bow": [Vector3(0, 10, -150), Vector3(48, 4, -100)],
	"barges": [Vector3(-60, 8, 145), Vector3(40, 2, 112)],
	"hold": [Vector3(48, 1.5, -88), Vector3(48, -3, 0)],
	"lab-ring": [Vector3(33, -26.4, 34), Vector3(33, -27, 66)],
	"core": [Vector3(48, -20.4, 39), Vector3(48, -27, 56)],
	"cutaway": [Vector3(-40, -10, 30), Vector3(48, -12, 30)],
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
		root.get_viewport().get_texture().get_image().save_png("%s-%s.png" % [out, view])
		print("saved ", view)
	quit()
