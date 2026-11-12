class_name ShaderWarm
extends Node
## Builds the raid's and the hideout's shaders ahead of time (0.29.5, owner: "i just want the first time you load
## into raid not to take so long, it took like 30 seconds first time").
## A browser builds a shader the first time something using it is drawn, and keeps it for next time. With nothing
## kept yet (a first visit, or after a Godot update changed every shader) the first raid built ~220 of them while it
## loaded. This draws one stand-in per shader (listed by tools/gen_shader_warm.gd in assets/warm/) in tiny hidden
## views, so the raid and the hideout find them built. Looks only; never on servers or headless runs.
## 0.30.8 (owner: "people keep lagging when entering the game, in the hideout, and in raid"): it runs behind the title
## screen's loading bar now, as fast as the machine builds them, instead of one a frame while you were already
## clicking round the title screen and walking the hideout. And each list is drawn the way it's really lit: a shader is
## built again for different light, so the hideout's (no sun) were built for the raid's sunlight and the hideout built
## them all over again as you walked in, and on LOW graphics (no sun shadows) the raid's were built for shadows.
## 0.34.13 (owner: "its the getting ready that takes a long time"): the hideout's come first now, so the title screen
## only waits for those (a few seconds) and the raid's finish behind the buttons. Leaving the title stops the rest:
## the hideout and the raid build whatever's left themselves, as before.

const RAID_LIST := "res://assets/warm/raid_warm.tscn"
const HIDEOUT_LIST := "res://assets/warm/hideout_warm.tscn"
## Built in this order: the title screen waits for the hideout's, then PLAY comes up while the raid's follow.
const LISTS := [HIDEOUT_LIST, RAID_LIST]
## Frames should take about this long while it builds (ms): it draws more stand-ins a frame while frames are quicker,
## fewer while slower, so the loading bar keeps moving.
const TARGET_MS := 90.0
const MAX_PER_FRAME := 16

static var _running: ShaderWarm
static var _done := false
## True once the lists above have been queued (the hideout's are queued first, then the raid's).
static var _started := false
## How many stand-ins the hideout's share has: once that many are drawn, the title screen can come up.
static var _ready_total := 0
static var _total := 0
static var _drawn := 0

var _queue: Array[GeometryInstance3D] = []
var _shown: Array[GeometryInstance3D] = []
var _per_frame := 1
var _last_usec := 0


## Starts building (once per game session; later calls do nothing).
static func start(tree: SceneTree) -> void:
	if _done or _running != null or tree == null:
		return
	if DisplayServer.get_name() == "headless":
		_done = true
		return
	_running = ShaderWarm.new()
	_running.name = "ShaderWarm"
	tree.root.add_child.call_deferred(_running)


## Stops (leaving the title: the hideout and the raid build whatever's left themselves).
static func stop() -> void:
	if _running != null:
		_running.queue_free()
		_running = null


static func is_done() -> bool:
	return _done


## True once the hideout's shaders are built: what the title screen waits for before showing PLAY (0.34.13). The
## raid's keep building behind the buttons.
static func is_ready() -> bool:
	return _done or (_started and _drawn >= _ready_total)


## How far along the hideout's share is, 0-1 (1 once it's built, or when there's nothing to build).
static func ready_progress() -> float:
	if _done or (_started and _ready_total == 0):
		return 1.0
	return 0.0 if not _started else clampf(float(_drawn) / _ready_total, 0.0, 1.0)


## How far along it is, 0-1 (1 once done, or when there's nothing to build).
static func progress() -> float:
	if _done:
		return 1.0
	return 0.0 if _total == 0 else clampf(float(_drawn) / _total, 0.0, 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The hideout first (0.34.13): the title screen waits only for these, so PLAY comes up in a few seconds. Its
	# light: underground, no sun (Look.hideout_environment).
	var hideout := _view("Hideout")
	(hideout.get_node("WorldEnvironment") as WorldEnvironment).environment = Look.hideout_environment()
	_add_list(hideout, HIDEOUT_LIST)
	_ready_total = _queue.size()
	# The raid: its look and its sun, with the graphics setting's shadows (main.tscn's Sun).
	var raid := _view("Raid")
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	raid.add_child(sun)
	Look.apply(raid)   # (its light, and GameSettings.shadows_on for the sun)
	_add_list(raid, RAID_LIST)
	_total = _queue.size()
	_started = true
	_last_usec = Time.get_ticks_usec()


## A tiny hidden view of its own world; returns the node to put things in.
func _view(view_name: String) -> Node3D:
	var view := SubViewport.new()
	view.name = view_name
	view.size = Vector2i(64, 64)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var world := Node3D.new()
	world.name = "World"
	view.add_child(world)
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.current = true
	world.add_child(camera)
	return world


func _add_list(world: Node3D, path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var list := scene.instantiate()
	world.add_child(list)
	for child in list.get_children():
		if child is GeometryInstance3D:
			child.visible = false
			child.position = Vector3(0, 0, -3)
			_queue.append(child)


func _process(_delta: float) -> void:
	# (the last frame's time includes building the shaders drawn in it)
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	if frame_ms < TARGET_MS * 0.6:
		_per_frame = mini(_per_frame * 2, MAX_PER_FRAME)
	elif frame_ms > TARGET_MS * 1.6:
		_per_frame = maxi(_per_frame / 2, 1)
	for node in _shown:
		node.queue_free()
	_drawn += _shown.size()
	_shown.clear()
	if _queue.is_empty():
		_done = true
		_running = null
		queue_free()
		return
	for i in mini(_per_frame, _queue.size()):
		var node: GeometryInstance3D = _queue.pop_front()
		node.visible = true
		_shown.append(node)
