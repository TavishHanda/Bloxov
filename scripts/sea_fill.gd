class_name SeaFill
extends MeshInstance3D
## Bits of the sea's flat surface (y 0) the map's rectangular sea pieces can't cover: Riptide's corners round the
## Leviathan's shaped bow and rounded stern (0.36.17, owner: the hull was "too square"). Each polygon is (x, z) points
## in the map's space; the mesh is made when the map loads. Looks only: the water you swim in is SwimZone boxes.

@export var polygons: Array[PackedVector2Array] = []


func _ready() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for poly in polygons:
		var tris := Geometry2D.triangulate_polygon(poly)
		for i in range(0, tris.size(), 3):
			# (Godot draws a triangle's front where its corners go clockwise: from above, x east and z south)
			var a := poly[tris[i]]
			var b := poly[tris[i + 1]]
			var c := poly[tris[i + 2]]
			if (b - a).cross(c - a) < 0.0:
				var swap := b
				b = c
				c = swap
			for p: Vector2 in [a, b, c]:
				st.set_normal(Vector3.UP)
				st.set_uv(p)
				st.add_vertex(Vector3(p.x, 0.0, p.y))
	mesh = st.commit()
