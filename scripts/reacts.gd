class_name Reacts
## The world reacts (0.22.0): looks-only reactions each client works out for itself, never sent online and never
## run on the game server. Hanging lamps swing when bumped, shot near or caught in a blast (swing_lamps.gd), bushes
## and curtains part round whoever walks through them (bushes.gd, cloth.gd), cans and bottles get kicked about
## (kickables.gd). None of it collides with anything or changes how the game plays.
##
## Shots and blasts reach the reacting nodes through `shot` and `blast`; `movers` and `pushers` say who's moving
## through the world near the camera.

const GROUP := &"reacts"
## The groups whose members push things about (anything else that should can join MOVER: the hideout's walker).
const MOVER := &"reacts_mover"
const MOVER_GROUPS: Array[StringName] = [&"player", &"remote_players", &"enemies", MOVER]
## How many bodies bushes and curtains part round at once (the shaders' `pushers` array).
const PUSHERS := 4
const PUSH_REACH := 30.0

static var _frame := -1
static var _movers: Array[Dictionary] = []
static var _last: Dictionary = {}       # instance id -> last position (for the speed of bodies without a velocity)
static var _pushers := PackedVector4Array()


## Whether reactions run here: never on the game server (headless), unless a test asks for them.
static func wanted(node: Node) -> bool:
	return DisplayServer.get_name() != "headless" or bool(node.get_meta(&"force_reacts", false))


## A shot from `from` to `to` (every tracer drawn: yours, other players', scavs').
static func shot(world: Node, from: Vector3, to: Vector3) -> void:
	if world == null or not world.is_inside_tree():
		return
	for node in RaidScope.nodes(world, GROUP):
		if node.has_method(&"on_shot"):
			node.on_shot(from, to)


## A blast at `at` that hurts out to `radius`.
static func blast(world: Node, at: Vector3, radius: float) -> void:
	if world == null or not world.is_inside_tree():
		return
	for node in RaidScope.nodes(world, GROUP):
		if node.has_method(&"on_blast"):
			node.on_blast(at, radius)


## The bodies moving about in `node`'s world this frame: [{pos, vel, height}], worked out once a frame.
static func movers(node: Node) -> Array[Dictionary]:
	var frame := Engine.get_physics_frames()
	if frame == _frame:
		return _movers
	_frame = frame
	_movers = []
	var dt := 1.0 / maxf(1.0, Engine.physics_ticks_per_second)
	var seen := {}
	for group in MOVER_GROUPS:
		for other in RaidScope.nodes(node, group):
			var body := other as Node3D
			if body == null or not body.is_visible_in_tree():
				continue
			var id := body.get_instance_id()
			var pos := body.global_position
			var vel := Vector3.ZERO
			if body is CharacterBody3D:
				vel = (body as CharacterBody3D).velocity
			elif _last.has(id):
				vel = (pos - (_last[id] as Vector3)) / dt
			seen[id] = pos
			var height := 1.8
			if body.has_method(&"stance_height"):
				height = body.call(&"stance_height")
			_movers.append({"pos": pos, "vel": vel, "height": height})
	_last = seen
	_pushers = PackedVector4Array()
	var cam := node.get_viewport().get_camera_3d() if node.is_inside_tree() else null
	var near := _movers.duplicate()
	if cam != null:
		var eye := cam.global_position
		near = near.filter(func(m: Dictionary) -> bool: return (m.pos as Vector3).distance_to(eye) < PUSH_REACH)
		near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a.pos as Vector3).distance_squared_to(eye) < (b.pos as Vector3).distance_squared_to(eye))
	for m: Dictionary in near.slice(0, PUSHERS):
		var v := m.vel as Vector3
		var p := m.pos as Vector3
		_pushers.append(Vector4(p.x, p.y, p.z, clampf(Vector2(v.x, v.z).length() / 3.0, 0.0, 1.5) + 0.5))
	while _pushers.size() < PUSHERS:
		_pushers.append(Vector4(0.0, -1000.0, 0.0, 0.0))
	return _movers


## The bodies bushes and curtains part round this frame (x, y, z of the feet; w how hard, 0 for none).
static func pushers(node: Node) -> PackedVector4Array:
	movers(node)
	return _pushers
