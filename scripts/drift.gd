extends Node3D
## Paper blowing about in town and leaves coming down off the trees (0.28.0, owner: give the world some life). Paper:
## a few scraps tumbling along the wind round the camera while you're outside in town. Leaves (0.28.10, owner: they
## "look really bad and show up way too often ... make sure they actually come down from trees"): now and then one
## comes loose from a leafy tree near you and flutters down, a little leaf shape in autumn colours, until it's on the
## ground. None away from the trees. Looks only: nothing hits them, nothing is sent online and the game server never
## draws them.

const WIND := Vector3(0.64, 0.0, 0.77)
const LEAF_COLOURS := [Color(0.62, 0.42, 0.14), Color(0.72, 0.55, 0.18), Color(0.48, 0.3, 0.12), Color(0.45, 0.5, 0.2)]
const TREES := preload("res://scripts/trees.gd")
const LEAF_REACH := 30.0         # metres: trees farther than this from the camera drop nothing you'd see
const LEAF_EVERY := Vector2(4.0, 10.0)  # seconds between leaves, near trees (owner: way too often before)
const FALL := 0.75               # m/s down, fluttering
const LEAFY := [0, 2]            # broadleaf and birch (pines, dead trees and ferns don't drop leaves)
const LEAVES := 16               # at most this many coming down at once

@export var town := Rect2()   # in Godot x, z: where paper blows about too

var leaves: MultiMeshInstance3D   # (one draw call for all of them)
var paper: CPUParticles3D
var crowns := PackedVector4Array()   # leafy trees: x, top of the trunk, z, canopy width
var leaves_dropped := 0
var _falling: Array[Dictionary] = []   # per leaf: at, drift (m/s), turn, spin, phase, floor (where it stops), colour
var _check := 0.0
var _next_leaf := 1.0
var _ground := 0.0   # how far below the camera the ground is (looked up now and then)


func _ready() -> void:
	if not Reacts.wanted(self):
		return
	leaves = _leaves()
	paper = _blowing(8, Vector3(0.18, 0.005, 0.24), Color(0.82, 0.8, 0.72))
	paper.name = "Paper"
	paper.emitting = false
	_find_trees.call_deferred()


## The leafy trees in this raid's map (scripts/trees.gd's data).
func _find_trees() -> void:
	var top := get_parent()   # (the map's Level: the trees are under it)
	if top == null:
		return
	for node in top.find_children("*", "Node3D", true, false):
		if node.get_script() != TREES:
			continue
		var data: PackedFloat32Array = node.get(&"data")
		var at := (node as Node3D).global_transform
		for i in range(0, data.size(), TREES.STRIDE):
			if int(data[i + 5]) in LEAFY:
				var p := at * Vector3(data[i], data[i + 1] + data[i + 3], data[i + 2])
				crowns.append(Vector4(p.x, p.y, p.z, data[i + 4]))


## One leaf: a little pointed oval, folded down its middle, seen from both sides.
func _leaves() -> MultiMeshInstance3D:
	var verts := PackedVector3Array([Vector3(0, 0, -0.06), Vector3(0.028, 0.004, -0.02), Vector3(0.03, 0.004, 0.02),
		Vector3(0, 0, 0.055), Vector3(-0.03, 0.004, 0.02), Vector3(-0.028, 0.004, -0.02), Vector3(0, -0.006, 0.0),
		Vector3(0, 0, 0.075)])
	var shade := PackedColorArray([Color(0.85, 0.85, 0.85), Color.WHITE, Color.WHITE, Color(0.85, 0.85, 0.85),
		Color(0.92, 0.92, 0.92), Color(0.92, 0.92, 0.92), Color(0.7, 0.7, 0.7), Color(0.55, 0.45, 0.35)])
	var index := PackedInt32Array([0, 1, 6, 1, 2, 6, 2, 3, 6, 3, 4, 6, 4, 5, 6, 5, 0, 6, 3, 7, 6])   # (7: the stalk)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = shade
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	mesh.surface_set_material(0, material)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = LEAVES
	multi.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "Leaves"
	mi.multimesh = multi
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0   # (it sits at the world's middle; the leaves are wherever the trees are)
	add_child(mi)
	return mi


func _blowing(amount: int, size: Vector3, colour: Color) -> CPUParticles3D:   # (the paper)
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	mesh.material = material
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.randomness = 0.5
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14.0, 0.5, 14.0)
	p.direction = WIND + Vector3.UP * 0.2
	p.spread = 25.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0.0, -0.05, 0.0)
	p.damping_min = 0.1
	p.damping_max = 0.3
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.particle_flag_rotate_y = false
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	add_child(p)
	return p


func _process(delta: float) -> void:
	if leaves == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	_next_leaf -= delta
	if _next_leaf <= 0.0:
		_next_leaf = randf_range(LEAF_EVERY.x, LEAF_EVERY.y)
		drop_leaf(eye)
	_fall(delta)
	# (upwind of the camera, about knee height over the ground: paper blows past you)
	paper.global_position = Vector3(eye.x, eye.y - _ground + 0.7, eye.z) - WIND * 5.0
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	var space := get_world_3d().direct_space_state
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + Vector3.DOWN * 4.0, 1))
	_ground = eye.y - down.position.y if down else 1.6
	var outside := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + Vector3.UP * 25.0, 1)).is_empty()
	paper.emitting = outside and town.has_point(Vector2(eye.x, eye.z))


## Lets a leaf go from a leafy tree near `eye`, if there's one (true if it did).
func drop_leaf(eye: Vector3) -> bool:
	var near := PackedInt32Array()
	for i in crowns.size():
		var c := crowns[i]
		if Vector2(c.x - eye.x, c.z - eye.z).length() < LEAF_REACH:
			near.append(i)
	if near.is_empty():
		return false
	var c := crowns[near[randi() % near.size()]]
	var r := c.w * 0.45 * sqrt(randf())
	var a := randf() * TAU
	var at := Vector3(c.x + cos(a) * r, c.y + randf_range(0.2, 1.2), c.z + sin(a) * r)
	if _falling.size() >= LEAVES:
		return false
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 40.0, 1))
	_falling.append({"at": at, "drift": WIND * randf_range(0.15, 0.4), "spin": randf_range(1.5, 3.5) * signf(randf() - 0.5),
		"turn": randf() * TAU, "phase": randf() * TAU, "floor": (hit.position.y + 0.02) if hit else at.y - 8.0,
		"colour": LEAF_COLOURS[randi() % LEAF_COLOURS.size()], "size": randf_range(1.1, 1.6), "rest": 0.0})
	leaves_dropped += 1
	return true


## Moves the falling leaves: down at FALL, swinging side to side and rocking as they go (a leaf's flutter), turning
## slowly; a leaf on the ground lies there a few seconds, then it's gone.
func _fall(delta: float) -> void:
	var multi := leaves.multimesh
	var k := 0
	var t := Time.get_ticks_msec() / 1000.0
	for leaf: Dictionary in _falling.duplicate():
		var at: Vector3 = leaf.at
		var ph: float = leaf.phase
		var down := at.y <= float(leaf.floor)
		if down:
			leaf.rest = float(leaf.rest) + delta
			if float(leaf.rest) > 4.0:
				_falling.erase(leaf)
				continue
		else:
			var sway := sin(t * 2.2 + ph)
			at += ((leaf.drift as Vector3) + Vector3(cos(ph) * sway * 0.5, -FALL * (0.75 + 0.35 * absf(sway)), sin(ph) * sway * 0.5)) * delta
			at.y = maxf(at.y, float(leaf.floor))
			leaf.at = at
			leaf.turn = float(leaf.turn) + float(leaf.spin) * delta
		var rock := 0.0 if down else 0.7 * sin(t * 2.2 + ph)
		var basis := Basis(Vector3.UP, float(leaf.turn)) * Basis(Vector3.RIGHT, rock) * Basis(Vector3.BACK, 0.3 * rock)
		multi.set_instance_transform(k, Transform3D(basis.scaled(Vector3.ONE * float(leaf.size)), at))
		multi.set_instance_color(k, leaf.colour)
		k += 1
	multi.visible_instance_count = k
