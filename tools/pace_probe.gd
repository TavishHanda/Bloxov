extends SceneTree
## Frame pacing (perf thread 2026-11-21): walks the player forward at a steady speed on a high refresh screen
## (run with --fixed-fps 144, or 60) and prints how evenly the camera moves from one drawn frame to the next.
## A perfectly smooth view moves the same distance every frame (spread 0%). Physics runs 60 times a second, so
## without smoothing a 144 Hz screen shows the camera stand still on some frames and jump on others.
##   godot --headless --fixed-fps 144 -s tools/pace_probe.gd
var _steps: PackedFloat32Array = []
var _last := Vector3.INF
var _camera: Camera3D
var _frames := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RaidMap.scene_path = ""
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	# (the HUD pauses the game while the mouse isn't captured, always in headless, as in the smoke test)
	main.get_node("HUD").process_mode = Node.PROCESS_MODE_DISABLED
	paused = false
	var spawner := main.get_node_or_null("EnemySpawner")
	if spawner != null:
		spawner.queue_free()
	for i in 120:
		await process_frame
	var player := main.get_node("Player")
	player.teleport_to(Vector3(0, 1, 0))
	_camera = player.get_node("Head/Recoil/Camera3D")
	Input.action_press("move_forward")
	for i in 60:
		await process_frame
	# (a node that runs after everything else each frame: what the screen would show)
	var sampler := Node.new()
	var code := GDScript.new()
	code.source_code = "extends Node\nvar on_frame: Callable\nfunc _process(_d: float) -> void:\n\ton_frame.call()\n"
	code.reload()
	sampler.set_script(code)
	sampler.process_priority = 100000
	sampler.process_mode = Node.PROCESS_MODE_ALWAYS
	sampler.set("on_frame", _sample)
	root.add_child(sampler)
	for i in roundi(1.5 / root.get_process_delta_time()):   # (a second and a half, whatever the frame rate)
		await process_frame
	sampler.queue_free()
	Input.action_release("move_forward")
	var mean := 0.0
	for s in _steps:
		mean += s
	mean /= _steps.size()
	var dev := 0.0
	var still := 0
	for s in _steps:
		dev += (s - mean) * (s - mean)
		if s < mean * 0.25:
			still += 1
	dev = sqrt(dev / _steps.size())
	print("PACE fps=%d frames=%d move/frame=%.4f m spread=%.0f%% frames standing still=%d" % [roundi(1.0 / maxf(root.get_process_delta_time(), 1e-6)), _steps.size(), mean, 100.0 * dev / maxf(mean, 1e-6), still])
	quit()


func _sample() -> void:
	var p := _camera.global_position
	p.y = 0.0
	if _last != Vector3.INF:
		_steps.append(p.distance_to(_last))
		if OS.has_environment("PACE_LOG") and _steps.size() < 40: print("step %.4f frac %.3f" % [_steps[-1], Engine.get_physics_interpolation_fraction()])
	_last = p
