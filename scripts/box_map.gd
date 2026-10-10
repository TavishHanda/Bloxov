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

const STRIDE := 10

@export var boxes := PackedFloat32Array()
@export var colors := PackedColorArray()
@export var terrain_xs := PackedFloat32Array()
@export var terrain_zs := PackedFloat32Array()
@export var terrain_heights := PackedFloat32Array()
@export var terrain_holes := PackedInt32Array()
@export var terrain_colour := 0

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
		mesh_node.mesh = mesh
		add_child(mesh_node)
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
	var holes := {}
	for cell in terrain_holes:
		holes[cell] = true
	var indices := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			if holes.has(j * (nx - 1) + i):
				continue
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			indices.append_array([a, b, d, a, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = tints
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
