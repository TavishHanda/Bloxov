extends SceneTree
## Far versions of the building models (World art 0.17, outdoor step 10: far view and speed pass).
## Looks at each model from all round (32 directions x 8 heights, plus straight down) and keeps only the triangles
## that can be seen from outside, through its windows and doors included: rooms you can't see into, floor undersides,
## the vault and so on are dropped. Writes assets/models/far/<model>.res; scripts/far_view.gd shows it instead of the
## full model once you're FarView.FROM metres away. Re-run after rebuilding a building model:
##     xvfb-run -a godot --rendering-driver opengl3 -s tools/far_bake.gd [-- school motel ...]
## Only the opaque atlas/ground surfaces are trimmed; glass, decals and the rest are kept whole (they're small).

const MODELS := "res://assets/models/buildings/"
const OUT := "res://assets/models/far/"
const SIZE := 1536
const HEIGHTS := [-6.0, 0.0, 8.0, 18.0, 30.0, 45.0, 65.0]
const TURNS := 32

const ID_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
varying flat float id;
void vertex() {
	id = UV.x;
}
void fragment() {
	// (UV.x holds the triangle's number: 6 bits a channel at odd levels in the top half, which reads back exactly; the
	// dark end doesn't)
	float n = id + 0.5;
	vec3 bits = vec3(floor(n / 4096.0), mod(floor(n / 64.0), 64.0), mod(floor(n), 64.0));
	ALBEDO = (128.0 + bits * 2.0 + 1.0) / 255.0;
}
"""

var _viewport: SubViewport
var _camera: Camera3D


func _initialize() -> void:
	var names := []
	for a in OS.get_cmdline_user_args():
		names.append(a)
	if names.is_empty():
		for f in DirAccess.get_files_at(MODELS):
			if f.ends_with(".glb"):
				names.append(f.get_basename())
	DirAccess.make_dir_recursive_absolute(OUT)
	RenderingServer.set_default_clear_color(Color.BLACK)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	root.add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	var total := [0, 0]
	for n: String in names:
		var r := await _bake(n)
		total[0] += r[0]
		total[1] += r[1]
	print("FAR BAKE total: %d -> %d triangles" % total)
	quit()


func _bake(model: String) -> Array:
	var scene: Node = (load(MODELS + model + ".glb") as PackedScene).instantiate()
	var source: MeshInstance3D = scene if scene is MeshInstance3D else scene.find_children("*", "MeshInstance3D")[0]
	var mesh: Mesh = source.mesh
	# 1. One mesh with every trimmable triangle in its own colour (1 up; 0 is the empty background).
	var corners := PackedVector3Array()
	var numbers := PackedVector2Array()
	var tris := []   # [surface, first index] by triangle number - 1
	for s in mesh.get_surface_count():
		if not _trimmable(mesh.surface_get_material(s)):
			continue
		var arrays := mesh.surface_get_arrays(s)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, index.size(), 3):
			tris.append([s, t])
			var id := tris.size()
			for k in 3:
				corners.append(points[index[t + k]])
				numbers.append(Vector2(id, 0.0))
	var id_arrays := []
	id_arrays.resize(Mesh.ARRAY_MAX)
	id_arrays[Mesh.ARRAY_VERTEX] = corners
	id_arrays[Mesh.ARRAY_TEX_UV] = numbers
	var id_mesh := ArrayMesh.new()
	id_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, id_arrays, [], {}, 0)
	var ids := MeshInstance3D.new()
	ids.mesh = id_mesh
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = ID_SHADER
	ids.material_override = material
	_viewport.add_child(ids)
	# 2. Look at it from all round and note every triangle that shows.
	var box := ids.mesh.get_aabb()
	var centre := box.get_center()
	var radius := box.size.length() * 0.5
	_camera.size = radius * 2.0
	_camera.near = 0.05
	_camera.far = radius * 6.0
	var seen := {}
	var views := []
	for h: float in HEIGHTS:
		for k in TURNS:
			views.append(Vector2(deg_to_rad(360.0 * k / TURNS + (7.0 if int(h) % 2 else 0.0)), deg_to_rad(h)))
	views.append(Vector2(0.0, deg_to_rad(89.0)))
	for v: Vector2 in views:
		var dir := Vector3(cos(v.y) * sin(v.x), sin(v.y), cos(v.y) * cos(v.x))
		_camera.look_at_from_position(centre + dir * radius * 3.0, centre, Vector3.UP if absf(v.y) < 1.5 else Vector3.FORWARD)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := _viewport.get_texture().get_image()
		var data := image.get_data()
		var stride := 4 if image.get_format() == Image.FORMAT_RGBA8 else 3
		var last := -1
		for p in range(0, data.size(), stride):
			var r := data[p]
			var g := data[p + 1]
			var b := data[p + 2]
			if r < 128 or g < 128 or b < 128:
				continue   # (the background, or a corner between triangles)
			var id := (((r - 128) >> 1) << 12) | (((g - 128) >> 1) << 6) | ((b - 128) >> 1)
			if id != last:
				seen[id] = true
				last = id
	_viewport.remove_child(ids)
	ids.free()
	# 3. The far mesh: seen triangles of the trimmed surfaces, everything else whole.
	var keep := {}   # surface -> first indices of its seen triangles
	for id: int in seen:
		if id < 1 or id > tris.size():
			continue
		var t: Array = tris[id - 1]
		(keep.get_or_add(t[0], []) as Array).append(t[1])
	var far := ArrayMesh.new()
	var before := 0
	var after := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		before += index.size() / 3
		if _trimmable(mesh.surface_get_material(s)):
			var firsts := PackedInt32Array(keep.get(s, []))
			firsts.sort()
			arrays = _subset(arrays, firsts)
			if arrays.is_empty():
				continue
		after += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		far.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		far.surface_set_material(far.get_surface_count() - 1, mesh.surface_get_material(s))
	ResourceSaver.save(far, OUT + model + ".res", ResourceSaver.FLAG_COMPRESS)
	print("FAR BAKE %s: %d -> %d triangles (%d%%)" % [model, before, after, 100 * after / maxi(before, 1)])
	scene.free()
	return [before, after]


func _trimmable(material: Material) -> bool:
	# The opaque shader surfaces (the kit atlas, the ground); glass, decals and cut-outs are kept whole.
	return material is ShaderMaterial


func _subset(arrays: Array, firsts: PackedInt32Array) -> Array:
	# The arrays with only the triangles starting at `firsts`, and only the corners they use.
	if firsts.is_empty():
		return []
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var remap := {}
	var order := PackedInt32Array()
	var new_index := PackedInt32Array()
	for t in firsts:
		for k in 3:
			var i := index[t + k]
			if not remap.has(i):
				remap[i] = order.size()
				order.append(i)
			new_index.append(remap[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in Mesh.ARRAY_MAX:
		var src = arrays[a]
		if src == null or a == Mesh.ARRAY_INDEX:
			continue
		var per := 1
		if a == Mesh.ARRAY_TANGENT:
			per = 4
		var dst = src.duplicate()
		dst.resize(order.size() * per)
		for j in order.size():
			for c in per:
				dst[j * per + c] = src[order[j] * per + c]
		out[a] = dst
	out[Mesh.ARRAY_INDEX] = new_index
	return out
