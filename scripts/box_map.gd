class_name BoxMap
extends StaticBody3D
## A gray-box map made of plain boxes (0.10.0): walls, floors, ramps, cover. The boxes come from a generator
## (`tools/gen_old_bloxov.py` writes them into the map scene), and this node turns them into one mesh (one draw
## call, which matters on the web) and one collision shape when the raid loads. Thousands of separate CSG nodes
## would cost a draw call and a physics body each.
## Each box is STRIDE floats: center x, y, z, size x, y, z, yaw and pitch (degrees; ramps are pitched), colour
## index (into `colors`), solid (1 = has collision, 0 = looks only: roads, tree tops, water).

const STRIDE := 10

@export var boxes := PackedFloat32Array()
@export var colors := PackedColorArray()

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
	collision_faces = faces
	if DisplayServer.get_name() != "headless":
		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "Mesh"
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.roughness = 1.0
		tool.set_material(material)
		mesh_node.mesh = tool.commit()
		add_child(mesh_node)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	add_child(collider)
