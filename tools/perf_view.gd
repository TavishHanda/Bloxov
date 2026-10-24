extends SceneTree
## What a frame costs to draw on Bloxov Battlegrounds (0.18.12, owner: "the whole game just feels kinda laggy"). Runs a
## real raid (player, AI, HUD), stands the player at a few places, turns round, and prints draw calls, objects,
## triangles and frame time for each view; then, at the busiest view, how much each kind of thing costs (hidden one
## at a time). Frame times under xvfb are the CPU drawing (llvmpipe): compare them with each other, not with a GPU.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 -s tools/perf_view.gd
## look=res://assets/looks/<name>.tres measures with that look. Not part of the smoke test.

## Map metres (Godot + 175): the town square, the busy main street, the train station, a field looking at town.
const SPOTS := {"square": Vector2(83, 172), "street": Vector2(60, 93), "station": Vector2(290, 290),
	"field": Vector2(175, 60)}
const YAWS := 8

var main: Node
var player: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RaidMap.scene_path = "res://scenes/maps/old_bloxov.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("look="): Look.current = a.substr(5)
	root.size = Vector2i(1280, 720)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 90:
		await process_frame
	player = main.get_node("Player")
	var sun_light := main.get_node("Sun") as DirectionalLight3D
	for a in OS.get_cmdline_user_args():   # (trying settings: shadow=<max metres> splits=<0 1 or 2 mode>)
		if a.begins_with("shadow="):
			sun_light.directional_shadow_max_distance = float(a.substr(7))
		if a.begins_with("splits="):
			sun_light.directional_shadow_mode = int(a.substr(7))
	print("sun shadows: %d m, mode %d" % [sun_light.directional_shadow_max_distance, sun_light.directional_shadow_mode])
	player.set_physics_process(false)
	player.get("health").max_health = 1000000
	player.get("health").heal(1000000)
	var worst := [0, Vector2.ZERO, 0.0]
	for spot: String in SPOTS:
		var line := "%-8s" % spot
		for i in YAWS:
			var yaw := TAU * i / YAWS
			var info := await _view(SPOTS[spot], yaw)
			line += "  %4d/%5.1fms" % [info[0], info[3]]
			if info[0] > worst[0]:
				worst = [info[0], SPOTS[spot], yaw]
		print(line)
	var at: Vector2 = worst[1]
	var base := await _view(at, worst[2])
	print("busiest view %s yaw %d: %d draw calls, %d objects, %dk triangles, %.1f ms" % [at, roundi(rad_to_deg(worst[2])),
		base[0], base[1], base[2] / 1000, base[3]])
	var sun := main.get_node("Sun") as DirectionalLight3D
	sun.shadow_enabled = false
	var no_shadow := await _view(at, worst[2])
	sun.shadow_enabled = true
	print("  %-14s -%4d draw calls  -%5.1f ms" % ["sun shadows", base[0] - no_shadow[0], base[3] - no_shadow[3]])
	var parts := {
		"buildings": _buildings(), "cars": [main.find_child("Cars", true, false)],
		"outdoor": [main.find_child("Outdoor", true, false)], "trees": [main.find_child("Trees", true, false)],
		"bushes": [main.find_child("Bushes", true, false)], "tufts": [main.find_child("Tufts", true, false)],
		"loot": get_nodes_in_group("loot_containers"), "doors": _doors(), "ai": get_nodes_in_group("enemies"),
		"map blocks": _block_meshes(),
	}
	for part: String in parts:
		var nodes: Array = parts[part].filter(func(n: Node) -> bool: return n is Node3D)
		for n: Node3D in nodes:
			n.visible = false
		var without := await _view(at, worst[2])
		for n: Node3D in nodes:
			n.visible = true
		print("  %-14s -%4d draw calls  -%5.1f ms  (%d nodes)" % [part, base[0] - without[0], base[3] - without[3],
			nodes.size()])
	quit(0)


## [draw calls, objects, triangles, ms a frame] standing at `at` (map metres) facing `yaw`.
func _view(at: Vector2, yaw: float) -> Array:
	var ground: Variant = main.find_child("Blocks", true, false)
	var y := 0.0
	if ground != null and ground.has_method("ground_height"):
		y = ground.ground_height(Vector3(at.x - 175, 0, at.y - 175))
	player.global_position = Vector3(at.x - 175, y + 0.1, at.y - 175)
	player.rotation.y = yaw
	for i in 6:
		await process_frame
	var start := Time.get_ticks_usec()
	for i in 10:
		await RenderingServer.frame_post_draw
	var ms := (Time.get_ticks_usec() - start) / 10000.0
	var rs := RenderingServer
	return [rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), ms]


func _buildings() -> Array:
	var models := main.find_child("Models", true, false)
	return models.get_children().filter(func(n: Node) -> bool: return not String(n.name) in ["Cars", "Outdoor"])


func _doors() -> Array:
	var out := []
	for name: String in ["Doors", "KeyDoors"]:
		var n := main.find_child(name, true, false)
		if n != null:
			out.append_array(n.get_children())
	return out


func _block_meshes() -> Array:
	var blocks := main.find_child("Blocks", true, false)
	return blocks.get_children().filter(func(n: Node) -> bool: return n is GeometryInstance3D)
