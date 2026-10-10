class_name BoxMap
extends StaticBody3D
## A gray-box map made of plain boxes (0.10.0): walls, floors, ramps, cover. The boxes come from a generator
## (`tools/gen_old_bloxov.py` writes them into the map scene), and this node turns them into one mesh (one draw
## call, which matters on the web) and one collision shape when the raid loads. Thousands of separate CSG nodes
## would cost a draw call and a physics body each.
## Each box is STRIDE floats: center x, y, z, size x, y, z, yaw and pitch (degrees; ramps are pitched), colour
## index (into `colors`), solid (1 = has collision, 0 = looks only: roads, tree tops, water).
## The ground (0.11.17, hills) is a height grid: `terrain_heights` has one height per grid point, row by row
## (`terrain_zs` rows of `terrain_xs` points; the spacing can vary), and `terrain_holes` lists the cells left open
## (the trench, the bunker ramp). Each cell is two triangles split from its north-west to its south-east corner (the
## generator puts things on the ground with the same split).
## Water (0.11.20, the creek): `water_points` is its middle line (x, water level, z); it's drawn as a see-through
## ribbon `water_width` wide (the banks hide its edges) and wading through it slows you down (`WADE_META`).

const STRIDE := 10
## Players and AI standing in water get this meta (how many water areas they're in); they move slower while it's set.
const WADE_META := &"wading"
## Wading counts from this deep (feet this far below the surface).
const WADE_DEPTH := 0.05

@export var boxes := PackedFloat32Array()
@export var colors := PackedColorArray()
@export var terrain_xs := PackedFloat32Array()
@export var terrain_zs := PackedFloat32Array()
@export var terrain_heights := PackedFloat32Array()
@export var terrain_holes := PackedInt32Array()
@export var terrain_colour := 0
## Cells covered by something on top of them (building floors, yards: 0.11.21): still solid, just not drawn.
@export var terrain_hidden := PackedInt32Array()
@export var water_points := PackedVector3Array()
@export var water_width := 8.0
@export var water_colour := 0

## The solid boxes' triangles (local space), for the collision shape and the navigation baker.
var collision_faces := PackedVector3Array()


func _ready() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var box_faces := BoxMesh.new().get_faces()  # a 1 m cube, 36 vertices
	for i in range(0, boxes.size(), STRIDE):
		var xf := Transform3D(
			Basis(Vector3.UP, deg_to_rad(boxes[i + 6])) * Basis(Vector3.RIGHT, deg_to_rad(boxes[i + 7]))
				* Basis.from_scale(Vector3(boxes[i + 3], boxes[i + 4], boxes[i + 5])),
			Vector3(boxes[i], boxes[i + 1], boxes[i + 2]))
		var colour := colors[int(boxes[i + 8])] if int(boxes[i + 8]) < colors.size() else Color.MAGENTA
		var solid := boxes[i + 9] > 0.5
		var normal_basis := xf.basis.inverse().transposed()
		for v in range(0, box_faces.size(), 3):
			var a := xf * box_faces[v]
			var b := xf * box_faces[v + 1]
			var c := xf * box_faces[v + 2]
			# The cube face's own direction: the axis all three corners share.
			var local := Vector3.ZERO
			for k in 3:
				if is_equal_approx(box_faces[v][k], box_faces[v + 1][k]) and is_equal_approx(box_faces[v][k], box_faces[v + 2][k]):
					local[k] = signf(box_faces[v][k])
			var normal := (normal_basis * local).normalized()
			# Slightly darker sides than tops, so walls read in flat light.
			var shade := colour.darkened(0.0 if absf(normal.y) > 0.5 else 0.12)
			for p in [a, b, c]:
				tool.set_color(shade)
				tool.set_normal(normal)
				tool.add_vertex(p)
			if solid:
				faces.append_array([a, b, c])
	var ground := _terrain_arrays()
	if not ground.is_empty():
		var points: PackedVector3Array = ground[Mesh.ARRAY_VERTEX]
		for index in ground[Mesh.ARRAY_INDEX] as PackedInt32Array:
			faces.append(points[index])
		ground[Mesh.ARRAY_INDEX] = _terrain_indices(terrain_hidden)
	collision_faces = faces
	if DisplayServer.get_name() != "headless":
		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "Mesh"
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.roughness = 1.0
		tool.set_material(material)
		var mesh := tool.commit()
		if not ground.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ground)
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
		if water_points.size() >= 2:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _water_arrays())
			mesh.surface_set_material(mesh.get_surface_count() - 1, _water_material())
		mesh_node.mesh = mesh
		add_child(mesh_node)
	if water_points.size() >= 2:
		add_child(_wading_area())
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	add_child(collider)


## The ground mesh's arrays (vertices, normals, colours, indices), or [] if the map has no height grid.
func _terrain_arrays() -> Array:
	var nx := terrain_xs.size()
	var nz := terrain_zs.size()
	if nx < 2 or nz < 2 or terrain_heights.size() != nx * nz:
		return []
	var grass := colors[terrain_colour] if terrain_colour < colors.size() else Color.MAGENTA
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var tints := PackedColorArray()
	points.resize(nx * nz)
	normals.resize(nx * nz)
	tints.resize(nx * nz)
	for j in nz:
		for i in nx:
			var h := terrain_heights[j * nx + i]
			points[j * nx + i] = Vector3(terrain_xs[i], h, terrain_zs[j])
			# Smooth shading from the neighbours' heights; hilltops a touch lighter, hollows and slopes darker, so the
			# shape reads from a distance even in flat light.
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, nx - 1)
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, nz - 1)
			var dx := (terrain_heights[j * nx + i1] - terrain_heights[j * nx + i0]) / maxf(terrain_xs[i1] - terrain_xs[i0], 0.01)
			var dz := (terrain_heights[j1 * nx + i] - terrain_heights[j0 * nx + i]) / maxf(terrain_zs[j1] - terrain_zs[j0], 0.01)
			normals[j * nx + i] = Vector3(-dx, 1.0, -dz).normalized()
			var tint := grass.lightened(clampf(h * 0.015, 0.0, 0.12)) if h > 0.0 else grass.darkened(clampf(-h * 0.04, 0.0, 0.15))
			tints[j * nx + i] = tint.darkened(clampf(Vector2(dx, dz).length() * 0.6, 0.0, 0.25))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = tints
	arrays[Mesh.ARRAY_INDEX] = _terrain_indices()
	return arrays


## The ground's triangles (two per grid cell), leaving out the holes and the cells in `skip`.
func _terrain_indices(skip := PackedInt32Array()) -> PackedInt32Array:
	var nx := terrain_xs.size()
	var nz := terrain_zs.size()
	var left_out := {}
	for cell in terrain_holes + skip:
		left_out[cell] = true
	var indices := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			if left_out.has(j * (nx - 1) + i):
				continue
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			indices.append_array([a, b, d, a, d, c])
	return indices


## True while `body` stands in water.
static func is_wading(body: Node) -> bool:
	return int(body.get_meta(WADE_META, 0)) > 0


## The water's middle line pushed out sideways (half the width each way) at point k: [left, right].
func _water_sides(k: int, half: float) -> Array[Vector3]:
	var a := water_points[maxi(k - 1, 0)]
	var b := water_points[mini(k + 1, water_points.size() - 1)]
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var side := Vector3(along.z, 0.0, -along.x) * half
	return [water_points[k] + side, water_points[k] - side]


## The water surface: one ribbon along the middle line (no overlapping pieces, so it's evenly see-through).
func _water_arrays() -> Array:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for k in water_points.size():
		points.append_array(_water_sides(k, water_width / 2.0))
		normals.append_array([Vector3.UP, Vector3.UP])
		if k > 0:
			var a := (k - 1) * 2
			indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _water_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var colour := colors[water_colour] if water_colour < colors.size() else Color.MAGENTA
	material.albedo_color = Color(colour.darkened(0.2), 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.2
	material.metallic_specular = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## An area along the water (a box per stretch, from the bed up to just under the surface) that marks players and AI
## in it as wading.
func _wading_area() -> Area3D:
	var area := Area3D.new()
	area.name = "Water"
	area.collision_layer = 0
	area.collision_mask = 2 | 4   # players, enemies
	area.monitorable = false
	for k in water_points.size() - 1:
		var a := water_points[k]
		var b := water_points[k + 1]
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		var top := minf(a.y, b.y) - WADE_DEPTH
		var shape := BoxShape3D.new()
		# only as wide as the water really is (the ribbon is wider, its edges under the banks)
		shape.size = Vector3(water_width * 0.6, 2.0, length + 0.5)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = Vector3((a.x + b.x) / 2.0, top - 1.0, (a.z + b.z) / 2.0)
		collider.rotation.y = atan2(b.x - a.x, b.z - a.z)
		area.add_child(collider)
	area.body_entered.connect(func(body: Node) -> void: body.set_meta(WADE_META, int(body.get_meta(WADE_META, 0)) + 1))
	area.body_exited.connect(func(body: Node) -> void: body.set_meta(WADE_META, maxi(int(body.get_meta(WADE_META, 0)) - 1, 0)))
	return area
