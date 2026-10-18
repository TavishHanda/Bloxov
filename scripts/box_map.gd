@tool
class_name BoxMap
extends StaticBody3D
## A gray-box map made of plain boxes (0.10.0): walls, floors, ramps, cover. The boxes come from a generator
## (`tools/gen_old_bloxov.py` writes them into the map scene), and this node turns them into one mesh (one draw
## call, which matters on the web) and one collision shape when the raid loads. Thousands of separate CSG nodes
## would cost a draw call and a physics body each.
## Each box is STRIDE floats: center x, y, z, size x, y, z, yaw and pitch (degrees; ramps are pitched), colour
## index (into `colors`), solid (1 = has collision, 0 = looks only: roads, tree tops, water; 2 / 3 = the same but not
## drawn, because a building model draws it: World art 0.17, see `tools/gen_old_bloxov.py` `modeled`).
## The ground (0.11.17, hills) is a height grid: `terrain_heights` has one height per grid point, row by row
## (`terrain_zs` rows of `terrain_xs` points; the spacing can vary), and `terrain_holes` lists the cells left open
## (the trench, the bunker ramp). Each cell is two triangles split from its north-west to its south-east corner (the
## generator puts things on the ground with the same split).
## Water (0.11.20, the creek): `water_points` is its middle line (x, water level, z); it's drawn as a see-through
## ribbon `water_width` wide (the banks hide its edges) and wading through it slows you down (`WADE_META`).
## In the editor (`@tool`, World art 0.17) it only draws the mesh, so the map shows up there; nothing is saved.

const STRIDE := 10
## Tree tops (0.17.13, owner: the AI saw and shot through the leaves): no collision for people or bullets, but a
## body of their own on this layer (6) that the AI's sight and shots check, so leaves hide you from the AI.
const LEAVES_LAYER := 32
## The generator's "leaves" colour: boxes in it without collision are tree tops (bushes are solid already).
const LEAVES_COLOUR := Color(0.3, 0.5, 0.26)
## Players and AI standing in water get this meta (how many water areas they're in); they move slower while it's set.
const WADE_META := &"wading"
## Wading counts from this deep (feet this far below the surface).
const WADE_DEPTH := 0.05
## Points across the water ribbon (so the shader knows the depth across it).
const WATER_ACROSS := 9

@export var boxes := PackedFloat32Array()
@export var colors := PackedColorArray()
@export var terrain_xs := PackedFloat32Array()
@export var terrain_zs := PackedFloat32Array()
@export var terrain_heights := PackedFloat32Array()
@export var terrain_holes := PackedInt32Array()
@export var terrain_colour := 0
## Cells covered by something on top of them (building floors, yards: 0.11.21): still solid, just not drawn.
@export var terrain_hidden := PackedInt32Array()
## The ground's material (World art 0.17, outdoor step 2: assets/materials/ground.tres, textured grass, earth, gravel);
## without one the ground is drawn in `terrain_colour`.
@export var ground_material: Material
## Roads (World art 0.17, outdoor step 3): drawn as one smooth ribbon per road from the generator's `road_points`
## (two per section, left then right; `road_sections` sections per road, `road_widths` wide) with `road_material`.
## UV = (across from the middle line, along) in metres, UV2.x = the width, COLOR.r = 1 inside a junction (no lines
## there; `road_junctions` 1), COLOR.g = 1 at a car park's way in (no edge line there; `road_junctions` 2). The road
## strips in `road_colour` aren't drawn then. Without a material the strips are drawn as before.
@export var road_material: Material
@export var road_colour := -1
@export var road_points := PackedVector3Array()
@export var road_uvs := PackedVector2Array()
@export var road_junctions := PackedFloat32Array()
@export var road_sections := PackedInt32Array()
@export var road_widths := PackedFloat32Array()
## Car parks (and their ways in): boxes in `lot_colour` drawn with `lot_material`, UVs in metres in the box's own
## frame (x across from its middle, y along), UV2 = (width, length), so the shader can paint the bays.
@export var lot_material: Material
@export var lot_colour := -1
@export var water_points := PackedVector3Array()
@export var water_width := 8.0
@export var water_colour := 0
## The water's look (World art 0.17: assets/materials/water.tres); without one, a flat see-through colour.
@export var water_material: Material
## A little stream (World art 0.17: from the waterfall down to the creek): drawn like the water, too shallow to wade.
@export var stream_points := PackedVector3Array()
@export var stream_width := 1.0

## The solid boxes' triangles (local space), for the collision shape and the navigation baker.
var collision_faces := PackedVector3Array()


func _ready() -> void:
	var editor := Engine.is_editor_hint()
	if not editor:
		add_to_group(&"box_maps")
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lot_tool := SurfaceTool.new()
	lot_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lot_count := 0
	var ribbons := road_material != null and not road_sections.is_empty()
	var faces := PackedVector3Array()
	var box_faces := BoxMesh.new().get_faces()  # a 1 m cube, 36 vertices
	for i in range(0, boxes.size(), STRIDE):
		var xf := Transform3D(
			Basis(Vector3.UP, deg_to_rad(boxes[i + 6])) * Basis(Vector3.RIGHT, deg_to_rad(boxes[i + 7]))
				* Basis.from_scale(Vector3(boxes[i + 3], boxes[i + 4], boxes[i + 5])),
			Vector3(boxes[i], boxes[i + 1], boxes[i + 2]))
		var colour := colors[int(boxes[i + 8])] if int(boxes[i + 8]) < colors.size() else Color.MAGENTA
		var flag := int(boxes[i + 9])
		var solid := flag == 1 or flag == 2
		if flag >= 2:
			if solid:
				for v in box_faces:
					faces.append(xf * v)
			continue
		var normal_basis := xf.basis.inverse().transposed()
		if ribbons and int(boxes[i + 8]) == road_colour:
			continue   # (drawn by the ribbons; roads have no collision)
		var lot := lot_material != null and int(boxes[i + 8]) == lot_colour
		if lot:
			lot_count += 1
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
			if lot:
				for k in 3:
					var unit := box_faces[v + k]
					lot_tool.set_uv(Vector2(unit.x * boxes[i + 3], unit.z * boxes[i + 5]))
					lot_tool.set_uv2(Vector2(boxes[i + 3], boxes[i + 5]))
					lot_tool.set_normal(normal)
					lot_tool.add_vertex([a, b, c][k])
			else:
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
		if lot_count:
			lot_tool.set_material(lot_material)
			lot_tool.commit(mesh)
		if ribbons:
			_road_tool().commit(mesh)
		if not ground.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ground)
			mesh.surface_set_material(mesh.get_surface_count() - 1, ground_material if ground_material else material)
		for line in [[water_points, water_width], [stream_points, stream_width]]:
			if (line[0] as PackedVector3Array).size() >= 2:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _water_arrays(line[0], line[1]))
				mesh.surface_set_material(mesh.get_surface_count() - 1, _water_material())
		mesh_node.mesh = mesh
		add_child(mesh_node)
	if editor:
		return
	if water_points.size() >= 2:
		add_child(_wading_area())
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	add_child(collider)
	_add_leaves()


func _road_tool() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(road_material)
	var base := 0
	for r in road_sections.size():
		var n := road_sections[r]
		for k in n - 1:
			var l0 := base + k * 2
			# (left, right, next right; left, next right, next left)
			for idx in [l0, l0 + 1, l0 + 3, l0, l0 + 3, l0 + 2]:
				st.set_uv(road_uvs[idx])
				st.set_uv2(Vector2(road_widths[r], 0.0))
				st.set_color(Color(1.0 if road_junctions[idx] == 1.0 else 0.0, 1.0 if road_junctions[idx] == 2.0 else 0.0, 0.0, 1.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(road_points[idx])
		base += n * 2
	return st


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


## The ground's height (world y) under world point `pos`, or NAN off the grid or over a hole (bunker ramp, trench).
func ground_height(pos: Vector3) -> float:
	var local := to_local(pos)
	var nx := terrain_xs.size()
	var nz := terrain_zs.size()
	if nx < 2 or nz < 2 or terrain_heights.size() != nx * nz:
		return NAN
	var i := terrain_xs.bsearch(local.x) - 1
	var j := terrain_zs.bsearch(local.z) - 1
	if i < 0 or j < 0 or i >= nx - 1 or j >= nz - 1 or terrain_holes.has(j * (nx - 1) + i):
		return NAN
	var u := (local.x - terrain_xs[i]) / maxf(terrain_xs[i + 1] - terrain_xs[i], 0.001)
	var v := (local.z - terrain_zs[j]) / maxf(terrain_zs[j + 1] - terrain_zs[j], 0.001)
	var ha := terrain_heights[j * nx + i]
	var hb := terrain_heights[j * nx + i + 1]
	var hc := terrain_heights[(j + 1) * nx + i]
	var hd := terrain_heights[(j + 1) * nx + i + 1]
	# (the same split as the triangles: north-west to south-east corner)
	var h := ha + u * (hb - ha) + v * (hd - hb) if u >= v else ha + v * (hc - ha) + u * (hd - hc)
	return to_global(Vector3(local.x, h, local.z)).y


## Under the ground (0.12.35, owner's screenshot: a squadmate spawned on a slope ended up below the hills, and the
## ground is solid from below too, so they were stuck there): `pos` lifted onto the ground if it's below it.
## Underground rooms (the bunker) have their own ceiling: only lifted when the first thing above is the ground itself.
static func above_ground(node: Node3D, pos: Vector3, margin := 0.3) -> Vector3:
	for map in RaidScope.nodes(node, &"box_maps"):
		var ground := map as BoxMap
		var h := ground.ground_height(pos)
		if is_nan(h) or pos.y >= h - margin:
			continue
		var query := PhysicsRayQueryParameters3D.create(pos, Vector3(pos.x, h + 0.5, pos.z), 1)
		var hit := node.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider == ground and absf((hit.position as Vector3).y - h) < 0.05:
			return Vector3(pos.x, h + 0.1, pos.z)
	return pos


## True while `body` stands in water.
static func is_wading(body: Node) -> bool:
	return int(body.get_meta(WADE_META, 0)) > 0


## A water line pushed out sideways (half the width each way) at point k: [left, right].
func _water_sides(line: PackedVector3Array, k: int, half: float) -> Array[Vector3]:
	var a := line[maxi(k - 1, 0)]
	var b := line[mini(k + 1, line.size() - 1)]
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var side := Vector3(along.z, 0.0, -along.x) * half
	return [line[k] + side, line[k] - side]


## A water surface (the creek, the stream): one ribbon along its middle line (no overlapping pieces, so it's evenly see-through), a row of
## WATER_ACROSS points across. UV: metres across from the middle line, metres downstream; UV2.x: how deep the water is
## there (down to the ground), for the water shader's shallows and foam.
func _water_arrays(line: PackedVector3Array, width: float) -> Array:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var depths := PackedVector2Array()
	var indices := PackedInt32Array()
	var along := 0.0
	var half := width / 2.0
	for k in line.size():
		var sides := _water_sides(line, k, half)
		if k > 0:
			along += Vector2(line[k].x - line[k - 1].x, line[k].z - line[k - 1].z).length()
		for c in WATER_ACROSS:
			var f := float(c) / (WATER_ACROSS - 1)
			var p := sides[0].lerp(sides[1], f)
			var ground := ground_height(to_global(p))
			points.append(p)
			normals.append(Vector3.UP)
			uvs.append(Vector2(half * (1.0 - 2.0 * f), along))
			depths.append(Vector2(1.0 if is_nan(ground) else to_global(p).y - ground, 0.0))
			if k > 0 and c > 0:
				var i := k * WATER_ACROSS + c
				var up := i - WATER_ACROSS
				indices.append_array([up - 1, i - 1, up, up, i - 1, i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = depths
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _water_material() -> Material:
	if water_material:
		return water_material
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


## The tree tops' own body on LEAVES_LAYER only (nothing collides with it; only the AI's rays look for it).
func _add_leaves() -> void:
	var leaf_faces := PackedVector3Array()
	var box_faces := BoxMesh.new().get_faces()
	for i in range(0, boxes.size(), STRIDE):
		var index := int(boxes[i + 8])
		# (non-solid leaves: drawn here, or hidden under a model (3), like the walk-through bushes of World art 0.17)
		if int(boxes[i + 9]) not in [0, 3] or index >= colors.size() or not colors[index].is_equal_approx(LEAVES_COLOUR):
			continue
		var xf := Transform3D(
			Basis(Vector3.UP, deg_to_rad(boxes[i + 6])) * Basis(Vector3.RIGHT, deg_to_rad(boxes[i + 7]))
				* Basis.from_scale(Vector3(boxes[i + 3], boxes[i + 4], boxes[i + 5])),
			Vector3(boxes[i], boxes[i + 1], boxes[i + 2]))
		for v in box_faces:
			leaf_faces.append(xf * v)
	if leaf_faces.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "Leaves"
	body.collision_layer = LEAVES_LAYER
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(leaf_faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
