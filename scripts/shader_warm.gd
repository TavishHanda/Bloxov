class_name ShaderWarm
extends SubViewport
## Builds the raid's and the hideout's shaders ahead of time (0.29.5, owner: "i just want the first time you load
## into raid not to take so long, it took like 30 seconds first time").
## A browser builds a shader the first time something using it is drawn, and keeps it for next time. With nothing
## kept yet (a first visit, or after a Godot update changed every shader) the first raid built ~220 of them while it
## loaded. This draws one stand-in per shader (listed by tools/gen_shader_warm.gd in assets/warm/) in a tiny hidden
## view with the raid's light and look, a few each frame, while you're on the title screen and in the hideout, so
## the raid finds them built. Looks only; never on servers or headless runs.

const LISTS := ["res://assets/warm/raid_warm.tscn", "res://assets/warm/hideout_warm.tscn"]
## Stand-ins drawn per frame (each new shader can take ~0.1 s to build in a browser on Windows).
const PER_FRAME := 1

static var _running: ShaderWarm
static var _done := false

var _queue: Array[GeometryInstance3D] = []
var _shown: Array[GeometryInstance3D] = []
var _world: Node3D


## Starts building in the background (once per game session; later calls do nothing).
static func start(tree: SceneTree) -> void:
	if _done or _running != null or DisplayServer.get_name() == "headless" or tree == null:
		return
	_running = ShaderWarm.new()
	_running.name = "ShaderWarm"
	tree.root.add_child.call_deferred(_running)


## Stops (the raid is loading: it builds whatever is left itself).
static func stop() -> void:
	if _running != null:
		_running.queue_free()
		_running = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = Vector2i(64, 64)
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	_world.add_child(environment)
	var sun := DirectionalLight3D.new()   # (as the raid's: main.tscn's Sun)
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	_world.add_child(sun)
	Look.apply(_world)
	var camera := Camera3D.new()
	camera.current = true
	_world.add_child(camera)
	for path in LISTS:
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var list := scene.instantiate()
		_world.add_child(list)
		for child in list.get_children():
			if child is GeometryInstance3D:
				child.visible = false
				child.position = Vector3(0, 0, -3)
				_queue.append(child)


func _process(_delta: float) -> void:
	for node in _shown:
		node.queue_free()
	_shown.clear()
	if _queue.is_empty():
		_done = true
		_running = null
		queue_free()
		return
	for i in mini(PER_FRAME, _queue.size()):
		var node: GeometryInstance3D = _queue.pop_front()
		node.visible = true
		_shown.append(node)
