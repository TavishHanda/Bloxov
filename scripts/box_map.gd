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
## Bushes (0.18.3, owner: "make them all walk-throughable ... but slows movement"; a friend: they stopped the scavs'
## shots like walls): boxes in this colour never collide with people or bullets; the AI can't see through them
## (a body of their own on this layer, 7, that only the AI's eyes check, not its shots), and anyone in one moves slower.
const BUSH_COLOUR := Color(0.3, 0.5, 0.27)
const BUSH_LAYER := 64
## Barred and boarded-up windows (0.18.3, owner: "make sure windows that are barred up ... arent jumpable"): a box per
## window on this layer (8) stops players (their collision mask has it) and vaulting, not bullets or eyes.
const BARS_LAYER := 128
## Windows still glazed (0.18.8, owner: "make windows breakable"): the map draws and collides these, not the
## building models (art_source/buildings/<name>_panes.json). A pane is on this layer (9): it stops people until it's
## broken, and nobody's shots (a shot passing through breaks it instead). Online, breaks are sent by pane number.
const WINDOW_LAYER := 256
## Players and AI inside a bush get this meta (how many bushes they're in); they move slower while it's set.
const BUSH_META := &"in_bush"
## Players and AI standing in water get this meta (how many water areas they're in); they move slower while it's set.
const WADE_META := &"wading"
## Wading counts from this deep (feet this far below the surface).
const WADE_DEPTH := 0.05
## Points across the water ribbon (so the shader knows the depth across it).
const WATER_ACROSS := 9
## What feet stand on (0.20.0): the ground (today's steps), wood, metal, concrete/tile, water.
const SURFACE_GROUND := 0
const SURFACE_WOOD := 1
const SURFACE_METAL := 2
const SURFACE_CONCRETE := 3
const SURFACE_WATER := 4
## Box colours with a sound of their own; the rest (slabs, walls, roofs) sound like their building, or the ground.
const SURFACE_BY_COLOUR := {
	"wood": SURFACE_WOOD, "rail": SURFACE_WOOD, "boxcar": SURFACE_WOOD, "deadwood": SURFACE_WOOD, "trunk": SURFACE_WOOD,
	"metal": SURFACE_METAL, "car_a": SURFACE_METAL, "car_b": SURFACE_METAL, "rust": SURFACE_METAL,
	"keydoor": SURFACE_METAL,
	"road": SURFACE_CONCRETE, "pavement": SURFACE_CONCRETE, "concrete": SURFACE_CONCRETE, "bunker": SURFACE_CONCRETE,
	"stone": SURFACE_CONCRETE, "lot": SURFACE_CONCRETE,
}
## Colours nobody stands on (tree tops, bushes, water, the map's edge).
const SURFACE_SKIP := ["leaves", "bush", "water", "boundary"]
const SURFACE_CELL := 8.0

@export var boxes := PackedFloat32Array()
@export var colors := PackedColorArray()
## Footsteps by surface (Sound update 0.20.0, see `surface_at` and scripts/surfaces.gd): each colour's name (the
## generator's COLOURS), and each building's footprint with its floor's sound (x0, z0, x1, z1, surface; local space).
@export var colour_names := PackedStringArray()
@export var floor_rects := PackedFloat32Array()
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
## Rocks standing in the creek (Godot x, z, radius, 0): the water shader draws foam rings round them (up to 16).
@export var water_rocks: PackedVector4Array

## Collision shaped like the drawing (0.18.3, owner: "match hitboxes to the models"): triangles (local space; three
## indices into `shaped_points` each) for the outdoor pieces that aren't box-shaped (boulders, earth banks, crater
## rims, rubble, the derailed train), from art_source/scripts/make_outdoor.py; their own boxes don't collide then.
## Collision only, never drawn.
## The barred windows' boxes (BARS_LAYER): x, y, z, size x, y, z, yaw (degrees) each. They stop people (players and
## the AI) and vaulting, never shots or eyes; since 0.19.8 also open railings, cell bars and the outdoor pieces whose
## shots hit their drawing (shelters, fences, stands...).
@export var bar_boxes := PackedFloat32Array()
## The glazed windows (WINDOW_LAYER): x, y, z, width, height, yaw (degrees) each; the pane faces along its yaw.
@export var window_panes := PackedFloat32Array()
@export var shaped_points := PackedVector3Array()
@export var shaped_indices := PackedInt32Array()
## What shots and eyes hit on the see-through pieces (0.19.8, owner: "i cannot shoot through these cracks in the bus
## stop"; 0.19.9 car windows, under tables): their drawings' triangles (like `shaped_points`), cut to their
## `bar_boxes`, which stop people. World layer, but nobody can reach them past those boxes; not in the navigation bake.
@export var shot_points := PackedVector3Array()
@export var shot_indices := PackedInt32Array()

## The solid boxes' triangles (local space), for the collision shape and the navigation baker.
var collision_faces := PackedVector3Array()
## The bar boxes' triangles (local space): they stop people, so the navigation baker counts them too (0.19.8).
var people_faces := PackedVector3Array()
## Where the shaped triangles sit in `collision_faces` (corner numbers): they're wound the other way round from the
## boxes' and the ground's, so their outsides are worked out the other way (inside_solid).
var _shaped_from := 0
var _shaped_to := 0
## ...and the shot triangles right after them (wound like them), up to here.
var _shots_to := 0
## surface_at's lookup: boxes near each SURFACE_CELL square (Vector2i -> PackedInt32Array of box starts), and each
## box's inverse transform.
var _surface_cells := {}
var _surface_inverse := {}


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
	_shaped_from = faces.size()
	for index in shaped_indices:
		faces.append(shaped_points[index])
	_shaped_to = faces.size()
	for index in shot_indices:
		faces.append(shot_points[index])
	_shots_to = faces.size()
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
	_add_bars()
	_add_windows()
	_index_surfaces()


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


func _index_surfaces() -> void:
	if colour_names.is_empty():
		return
	for i in range(0, boxes.size(), STRIDE):
		var colour := int(boxes[i + 8])
		if colour >= colour_names.size() or colour_names[colour] in SURFACE_SKIP:
			continue
		var xf := Transform3D(
			Basis(Vector3.UP, deg_to_rad(boxes[i + 6])) * Basis(Vector3.RIGHT, deg_to_rad(boxes[i + 7]))
				* Basis.from_scale(Vector3(boxes[i + 3], boxes[i + 4], boxes[i + 5])),
			Vector3(boxes[i], boxes[i + 1], boxes[i + 2]))
		_surface_inverse[i] = xf.affine_inverse()
		var reach := Vector2(boxes[i + 3], boxes[i + 5]).length() / 2.0 + 0.3
		var c0 := Vector2i(floori((boxes[i] - reach) / SURFACE_CELL), floori((boxes[i + 2] - reach) / SURFACE_CELL))
		var c1 := Vector2i(floori((boxes[i] + reach) / SURFACE_CELL), floori((boxes[i + 2] + reach) / SURFACE_CELL))
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var key := Vector2i(cx, cz)
				var list: PackedInt32Array = _surface_cells.get(key, PackedInt32Array())
				list.append(i)
				_surface_cells[key] = list   # (packed arrays are copied: put it back)


## What world point `feet` stands on (0.20.0): the top of a box at most a step below or above it (the highest), by
## its colour (SURFACE_BY_COLOUR); plain floors and the ground inside a building by the building (`floor_rects`);
## anything else the ground.
func surface_at(feet: Vector3) -> int:
	var local := to_local(feet)
	var best := -INF
	var surface := -1
	for i in _surface_cells.get(Vector2i(floori(local.x / SURFACE_CELL), floori(local.z / SURFACE_CELL)), PackedInt32Array()):
		var p: Vector3 = (_surface_inverse[i] as Transform3D) * local
		if absf(p.x) > 0.5 + 0.15 / boxes[i + 3] or absf(p.z) > 0.5 + 0.15 / boxes[i + 5]:
			continue
		var height := p.y * boxes[i + 4] - boxes[i + 4] / 2.0   # (feet above the box's top, along the box's up)
		if height < -0.3 or height > 0.35 or boxes[i + 1] + boxes[i + 4] / 2.0 <= best:
			continue
		best = boxes[i + 1] + boxes[i + 4] / 2.0
		surface = SURFACE_BY_COLOUR.get(colour_names[int(boxes[i + 8])], -1)
	if surface >= 0:
		return surface
	for r in range(0, floor_rects.size(), 5):
		if local.x >= floor_rects[r] and local.x <= floor_rects[r + 2] and local.z >= floor_rects[r + 1] and local.z <= floor_rects[r + 3]:
			return int(floor_rects[r + 4])
	return SURFACE_GROUND


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


## Inside something solid (0.19.4, owner: a friend vaulted into a dirt bank and was stuck in it). Map collision is
## a shell of triangles, solid from both sides, so a body that ends up inside it can't get out. Inside = the first
## map surface straight above `point` faces up (it's seen from behind). Needs the project's Jolt ray face index.
static func inside_solid(body: CollisionObject3D, point: Vector3) -> bool:
	var hit := body.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(point, point + Vector3.UP * 30.0, 1, [body.get_rid()]))
	return not hit.is_empty() and hit_from_behind(hit, Vector3.UP)


## A body standing at `feet` is stuck inside the map's collision (0.19.4): inside something (inside_solid) and either
## caught in its skin or walled in by it all round. (Just inside_solid isn't enough: crouched under an overhang that's
## open to one side, the overhang is seen from behind too, but you can walk out.)
static func stuck_inside(body: CollisionObject3D, feet: Vector3, radius: float, height: float) -> bool:
	var chest := feet + Vector3.UP * 0.3
	if not inside_solid(body, chest):
		return false
	var space := body.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(radius - 0.08, 0.1)
	capsule.height = maxf(height - 0.2, capsule.radius * 2.0)
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = capsule
	overlap.collision_mask = 1
	overlap.exclude = [body.get_rid()]
	overlap.transform = Transform3D(Basis(), feet + Vector3.UP * (height * 0.5 + 0.05))
	if not space.intersect_shape(overlap, 1).is_empty():
		return true
	for k in 4:
		var way := Vector3(cos(TAU * k / 4.0), 0.0, sin(TAU * k / 4.0))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + way * 8.0, 1, [body.get_rid()]))
		if hit.is_empty() or not hit_from_behind(hit, way):
			return false
	return true


## True if a ray going `direction` that made `hit` struck a map surface from behind: it started inside something.
static func hit_from_behind(hit: Dictionary, direction: Vector3) -> bool:
	var map := hit.get("collider") as BoxMap
	var face: int = hit.get("face_index", -1)
	if map == null or face < 0 or face * 3 + 2 >= map.collision_faces.size():
		return false
	var a := map.collision_faces[face * 3]
	var outside := (map.collision_faces[face * 3 + 2] - a).cross(map.collision_faces[face * 3 + 1] - a)
	if face * 3 >= map._shaped_from and face * 3 < map._shots_to:
		outside = -outside
	return (map.global_basis * outside).dot(direction) > 0.0


## The nearest place to stand near `feet` (on a walkable top, with room for a body `radius` wide and `height` tall,
## and not inside anything), for getting a stuck body out; `feet` itself if there's none within 5 m.
static func free_spot(body: CollisionObject3D, feet: Vector3, radius: float, height: float) -> Vector3:
	var space := body.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	var fit := PhysicsShapeQueryParameters3D.new()
	fit.shape = capsule
	fit.collision_mask = 1 | 2 | 4 | BARS_LAYER
	fit.exclude = [body.get_rid()]
	for ring: float in [0.0, 0.6, 1.2, 2.0, 3.0, 4.0, 5.0]:
		var sides := 1 if ring == 0.0 else 16
		for k in sides:
			var at := feet + Vector3(cos(TAU * k / sides), 0.0, sin(TAU * k / sides)) * ring
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 6.0, at + Vector3.DOWN * 3.0, 1,
				[body.get_rid()]))
			if hit.is_empty() or (hit.normal as Vector3).y < 0.7 or hit_from_behind(hit, Vector3.DOWN):
				continue
			var spot: Vector3 = hit.position + Vector3.UP * 0.05
			fit.transform = Transform3D(Basis(), spot + Vector3.UP * (height * 0.5 + 0.05))
			if space.intersect_shape(fit, 1).is_empty() and not inside_solid(body, spot + Vector3.UP * 0.3):
				return spot
	return feet


## `collision_faces` without the shot triangles (they're inside `people_faces`), for the navigation bake.
func nav_faces() -> PackedVector3Array:
	if _shots_to == _shaped_to:
		return collision_faces
	return collision_faces.slice(0, _shaped_to) + collision_faces.slice(_shots_to)


## True while `body` stands in water.
static func is_wading(body: Node) -> bool:
	return int(body.get_meta(WADE_META, 0)) > 0


func _add_bars() -> void:
	if bar_boxes.is_empty():
		return
	var cube := BoxMesh.new().get_faces()
	var body := StaticBody3D.new()
	body.name = "Bars"
	body.collision_layer = BARS_LAYER
	body.collision_mask = 0
	for i in range(0, bar_boxes.size(), 7):
		var shape := BoxShape3D.new()
		shape.size = Vector3(bar_boxes[i + 3], bar_boxes[i + 4], bar_boxes[i + 5])
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(bar_boxes[i + 6])),
			Vector3(bar_boxes[i], bar_boxes[i + 1], bar_boxes[i + 2]))
		body.add_child(collider)
		for v in cube:
			people_faces.append(collider.transform * (v * shape.size))
	add_child(body)


## Glazed windows (0.18.8): one body with a thin box per pane, and one mesh with all the panes still whole.
const WINDOW_T := 0.04
const WINDOW_MATERIAL := "res://assets/materials/glass.tres"
const GLASS_SOUND := "res://audio/glass.wav"
## A pane broke (its number in `window_panes`): the raid sends it to the other players.
signal window_broken(pane: int)

var _windows: StaticBody3D
var _window_mesh: MeshInstance3D
var _whole: Array[bool] = []


func _add_windows() -> void:
	if window_panes.is_empty():
		return
	_windows = StaticBody3D.new()
	_windows.name = "Windows"
	_windows.collision_layer = WINDOW_LAYER
	_windows.collision_mask = 0
	for i in panes():
		_whole.append(true)
		var shape := BoxShape3D.new()
		shape.size = Vector3(_pane_size(i).x, _pane_size(i).y, WINDOW_T)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.transform = _pane_transform(i)
		_windows.add_child(collider)
	add_child(_windows)
	if DisplayServer.get_name() == "headless":
		return
	_window_mesh = MeshInstance3D.new()
	_window_mesh.name = "Panes"
	add_child(_window_mesh)
	_redraw_windows()


func panes() -> int:
	return window_panes.size() / 6


func _pane_size(i: int) -> Vector2:
	return Vector2(window_panes[i * 6 + 3], window_panes[i * 6 + 4])


func _pane_transform(i: int) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(window_panes[i * 6 + 5])),
		Vector3(window_panes[i * 6], window_panes[i * 6 + 1], window_panes[i * 6 + 2]))


## Is pane `i` still whole?
func pane_whole(i: int) -> bool:
	return i >= 0 and i < _whole.size() and _whole[i]


## Breaks pane `i` (a shot through it, or someone pushing into it). True if it was whole.
func break_pane(i: int, quiet := false) -> bool:
	if not pane_whole(i):
		return false
	_whole[i] = false
	(_windows.get_child(i) as CollisionShape3D).disabled = true   # (one shape per child, in order)
	_redraw_windows()
	if not quiet and DisplayServer.get_name() != "headless":
		Effects.sound_at(get_tree().current_scene, load(GLASS_SOUND), _pane_transform(i).origin, -4.0)
	window_broken.emit(i)
	return true


## The panes still whole, as one mesh (rebuilt when one breaks: it happens a handful of times a raid).
func _redraw_windows() -> void:
	if _window_mesh == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for i in panes():
		if not _whole[i]:
			continue
		any = true
		var xf := _pane_transform(i)
		var size := _pane_size(i)
		var corners := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
		st.set_normal(xf.basis.z)
		for k in [0, 1, 2, 0, 2, 3]:
			var c: Vector2 = corners[k]
			st.set_uv(Vector2((c.x + 0.5) * size.x, (0.5 - c.y) * size.y))
			st.add_vertex(xf * Vector3(c.x * size.x, c.y * size.y, 0.0))
	st.set_material(load(WINDOW_MATERIAL))
	_window_mesh.mesh = st.commit() if any else null


## Breaks any pane on the way from `from` to `to` (a shot, or a vault): shots pass through, leaving it broken.
## Returns the pane's number, or -1. `report`: tell the raid, so the other players' games break it too.
static func break_window_along(node: Node3D, from: Vector3, to: Vector3, report := true) -> int:
	var query := PhysicsRayQueryParameters3D.create(from, to, WINDOW_LAYER)
	var hit := node.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1
	return break_window_at(hit["collider"], hit["shape"], report)


## Breaks the pane shape `shape_index` of a "Windows" body (from a ray or a slide collision).
static func break_window_at(body: Object, shape_index: int, report := true) -> int:
	var map := (body as Node).get_parent() as BoxMap if body is StaticBody3D else null
	if map == null or shape_index < 0 or shape_index >= map.panes():
		return -1
	if not map.break_pane(shape_index):
		return -1
	if report:
		Network.main.break_window(shape_index)
	return shape_index


## In a bush (0.18.3): moves slower.
static func in_bush(body: Node) -> bool:
	return int(body.get_meta(BUSH_META, 0)) > 0


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
		if not Engine.is_editor_hint() and water_material is ShaderMaterial:   # (not in the editor: it would save them)
			var rocks: Array[Vector4] = []
			for r in water_rocks.slice(0, 16):
				rocks.append(r)
			water_material.set_shader_parameter("rocks", rocks)
			water_material.set_shader_parameter("rock_count", rocks.size())
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


## The tree tops' own body on LEAVES_LAYER only (nothing collides with it; only the AI's rays look for it), and the
## bushes' on BUSH_LAYER, plus the area that slows down whoever walks into a bush.
func _add_leaves() -> void:
	var leaf_faces := PackedVector3Array()
	var bush_faces := PackedVector3Array()
	var bush_area := Area3D.new()
	bush_area.name = "BushArea"
	bush_area.collision_layer = 0
	bush_area.collision_mask = 2 | 4   # players, enemies
	bush_area.monitorable = false
	var box_faces := BoxMesh.new().get_faces()
	for i in range(0, boxes.size(), STRIDE):
		var index := int(boxes[i + 8])
		# (non-solid leaves: drawn here, or hidden under a model (3), like the walk-through bushes of World art 0.17)
		if int(boxes[i + 9]) not in [0, 3] or index >= colors.size():
			continue
		var bush := colors[index].is_equal_approx(BUSH_COLOUR)
		if not bush and not colors[index].is_equal_approx(LEAVES_COLOUR):
			continue
		var turn := Basis(Vector3.UP, deg_to_rad(boxes[i + 6])) * Basis(Vector3.RIGHT, deg_to_rad(boxes[i + 7]))
		var size := Vector3(boxes[i + 3], boxes[i + 4], boxes[i + 5])
		var at := Vector3(boxes[i], boxes[i + 1], boxes[i + 2])
		var xf := Transform3D(turn * Basis.from_scale(size), at)
		for v in box_faces:
			(bush_faces if bush else leaf_faces).append(xf * v)
		if bush:   # (a little inside its edges: you slow down once you're in the leaves)
			var shape := BoxShape3D.new()
			shape.size = Vector3(maxf(size.x - 0.3, 0.2), size.y, maxf(size.z - 0.3, 0.2))
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.transform = Transform3D(turn, at)
			bush_area.add_child(collider)
	for part in [[leaf_faces, "Leaves", LEAVES_LAYER], [bush_faces, "BushLeaves", BUSH_LAYER]]:
		if (part[0] as PackedVector3Array).is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = part[1]
		body.collision_layer = part[2]
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(part[0])
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		add_child(body)
	if bush_area.get_child_count() == 0:
		bush_area.free()
		return
	bush_area.body_entered.connect(func(body: Node) -> void: body.set_meta(BUSH_META, int(body.get_meta(BUSH_META, 0)) + 1))
	bush_area.body_exited.connect(func(body: Node) -> void: body.set_meta(BUSH_META, maxi(int(body.get_meta(BUSH_META, 0)) - 1, 0)))
	add_child(bush_area)
