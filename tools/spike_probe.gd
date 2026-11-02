extends SceneTree
## Frame-time spikes in a raid (0.29.3): moves the player round the map and prints every slow frame, with the nodes
## added in it. SPIKE_US=<microseconds> sets what counts as slow (25 ms). Not part of the smoke test.
const SPOTS := [Vector2(83, 172), Vector2(60, 93), Vector2(290, 290), Vector2(175, 60), Vector2(250, 120), Vector2(120, 260), Vector2(200, 200)]
var _added: Dictionary = {}
func _initialize() -> void:
	_run.call_deferred()
func _on_added(n: Node) -> void:
	var k: String = n.get_class() + ":" + (n.get_script().resource_path.get_file() if n.get_script() else "") + ":" + String(n.name).left(12)
	_added[k] = _added.get(k, 0) + 1
func _run() -> void:
	RaidMap.scene_path = "res://scenes/maps/old_bloxov.tscn"
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 180: await process_frame
	var player := main.get_node("Player") as Node3D
	node_added.connect(_on_added)
	var spikes := []
	var total := 0
	var frames := 0
	for s in SPOTS.size() * 40:
		if s % 40 == 0:
			var p: Vector2 = SPOTS[s / 40] - Vector2(175, 175)
			player.global_position = Vector3(p.x, 40, p.y)
			player.get("health").heal(1000000)
		player.get("health").heal(1000000)
		_added.clear()
		var t := Time.get_ticks_usec()
		await process_frame
		var d := Time.get_ticks_usec() - t
		total += d; frames += 1
		if d > int(OS.get_environment("SPIKE_US") if OS.get_environment("SPIKE_US") != "" else "25000"): spikes.append("%5.1f s  %5.1f ms  %s" % [s / 40.0, d / 1000.0, str(_added).left(300)])
	print("SPIKES avg %.1f ms over %d frames, %d over 25 ms" % [total / 1000.0 / frames, frames, spikes.size()])
	for l in spikes.slice(0, 40): print(l)
	quit()
