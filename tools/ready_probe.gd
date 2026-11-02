extends SceneTree
## Which nodes' _ready take longest when the raid scene goes in (0.29.3; the time between one node's ready and the
## next's, so a parent's own _ready shows on its first child built there). Not part of the smoke test.
var _last := 0
var _gaps: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _on_added(n: Node) -> void:
	n.ready.connect(_on_ready.bind(n), CONNECT_ONE_SHOT)

func _on_ready(n: Node) -> void:
	var now := Time.get_ticks_usec()
	_gaps.append([now - _last, str(n.get_path()), n.get_class(), (n.get_script().resource_path if n.get_script() else "")])
	_last = now

func _run() -> void:
	root.size = Vector2i(1280, 720)
	RaidMap.scene_path = "res://scenes/maps/old_bloxov.tscn"
	var ps := load("res://scenes/main.tscn") as PackedScene
	var n := ps.instantiate()
	node_added.connect(_on_added)
	for c in _all(n): _on_added(c)
	_last = Time.get_ticks_usec()
	var t := _last
	root.add_child(n)
	current_scene = n
	print("add_child total ", (Time.get_ticks_usec() - t) / 1000, " ms")
	node_added.disconnect(_on_added)
	_gaps.sort_custom(func(a, b): return a[0] > b[0])
	for g in _gaps.slice(0, 25):
		print("%7.1f ms  %s  %s %s" % [g[0] / 1000.0, g[1], g[2], g[3]])
	quit()

func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children(): out.append_array(_all(c))
	return out
