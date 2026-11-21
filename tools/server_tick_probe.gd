extends SceneTree
## Server frame time (perf thread 2026-11-21): runs N raid worlds on a map like the live server, with player bodies
## standing at spawn and AI PMCs, and prints how long each server frame takes (process + physics), as percentiles.
##   godot --headless -s tools/server_tick_probe.gd -- [raids=1] [map=0] [seconds=60]
var _raids := 1
var _map := 0
var _seconds := 60.0
var _worlds: Array = []
var _frame := 0
var _times: PackedFloat32Array = []
var _last_us := 0
var _started := false
var _elapsed := 0.0
var _proc := 0.0
var _phys := 0.0
var _nav := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: _raids = int(args[0])
	if args.size() > 1: _map = int(args[1])
	if args.size() > 2: _seconds = float(args[2])


func _make() -> void:
	var world_script: Script = load("res://scripts/raid_world.gd")
	var map_script: Script = load("res://scripts/raid_map.gd")
	var maps: Array = map_script.get_script_constant_map()["MAPS"]
	for i in _raids:
		map_script.set("scene_path", maps[_map][1])
		var world: Node = world_script.new()
		root.add_child(world)
		_worlds.append(world)


func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_make()
	if _frame == 3:
		for world in _worlds:
			for peer in 4:
				world.update_proxy(peer + 1, [Vector3(randf() * 20.0, 0.0, randf() * 20.0), 0.0, 0.0, 0.0, 0])
			world.spawn_bots(3, randi(), [0], ["Tester"])
	if _frame == 240:
		_started = true
		_last_us = Time.get_ticks_usec()
		return false
	if _started:
		var now := Time.get_ticks_usec()
		_times.append((now - _last_us) / 1000.0)
		_last_us = now
		_elapsed += delta
		_proc += Performance.get_monitor(Performance.TIME_PROCESS)
		_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		_nav += Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS)
		if _frame % 60 == 0:
			for world in _worlds:
				world.enemy_states()
		if _elapsed >= _seconds:
			var s := _times.duplicate()
			s.sort()
			var n := s.size()
			var bodies := 0
			for world in _worlds:
				bodies += world.raid.find_children("*", "CharacterBody3D", true, false).size()
			var over := 0
			for t in s:
				if t > 16.7: over += 1
			print("SERVER TICK raids=%d map=%d bodies=%d frames=%d  p50=%.2f p90=%.2f p99=%.2f max=%.2f ms  over16.7ms=%d (%.1f%%)" % [
				_raids, _map, bodies, n, s[n / 2], s[n * 9 / 10], s[n * 99 / 100], s[n - 1], over, 100.0 * over / n])
			print("  average per frame: process %.2f ms, physics %.2f ms, navigation %.2f ms" % [_proc * 1000.0 / n, _phys * 1000.0 / n, _nav * 1000.0 / n])
			return true
	return false
