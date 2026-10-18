@tool
extends Node3D
## Grass tufts and wildflowers near the camera (World art 0.17, outdoor step 2; plan in
## /mnt/project-files/notes/outdoor-plan.md). Looks only: no collision, at most `height` tall (well under a prone
## player), gone by `fade_end`. Built lazily in square chunks round the camera, a few a frame, and dropped again far off.
## Where they grow comes from the generator (tools/gen_old_bloxov.py): the ground's splat map (no tufts on paths,
## mud, gravel or heavy scorch) and grass_mask.png (none under buildings, pavement and other flat pieces).
## Lives under the map's BoxMap (its parent) and asks it for the ground height. Skipped headless. In the editor
## (owner 2026-10-18: couldn't see them in the scene) they grow round the editor's camera; nothing is saved.

const CHUNK := 12.0
const SHADER := preload("res://assets/shaders/grass_tufts.gdshader")

@export var sprites: Texture2D
@export var splat: Texture2D
@export var mask: Texture2D
@export var map_origin := Vector2(-175.0, -175.0)
@export var map_size := 350.0
@export var per_square_metre := 1.3
@export var flower_chance := 0.12
@export var height := 0.28
@export var fade_end := 36.0

var _map: BoxMap
var _splat: Image
var _mask: Image
var _mesh: ArrayMesh
var _chunks := {}            # Vector2i -> MultiMeshInstance3D (null when the chunk has no tufts)


func _ready() -> void:
	_map = get_parent() as BoxMap
	if DisplayServer.get_name() == "headless" or _map == null or sprites == null:
		set_process(false)
		return
	_splat = splat.get_image() if splat else null
	_mask = mask.get_image() if mask else null
	for image in [_splat, _mask]:
		if image and image.is_compressed():
			image.decompress()
	_mesh = _tuft_mesh()


func _process(_delta: float) -> void:
	var camera := _camera()
	if camera == null:
		return
	var at := camera.global_position
	var reach := fade_end + CHUNK
	var centre := Vector2i(floori(at.x / CHUNK), floori(at.z / CHUNK))
	var r := ceili(reach / CHUNK)
	var built := 0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var key := centre + Vector2i(dx, dz)
			if _chunks.has(key) or built >= 2:
				continue
			if Vector2((key.x + 0.5) * CHUNK - at.x, (key.y + 0.5) * CHUNK - at.z).length() > reach:
				continue
			_chunks[key] = _build(key)
			built += 1
	for key: Vector2i in _chunks.keys():
		if Vector2((key.x + 0.5) * CHUNK - at.x, (key.y + 0.5) * CHUNK - at.z).length() > reach + CHUNK * 2.0:
			if _chunks[key]:
				(_chunks[key] as Node).queue_free()
			_chunks.erase(key)


func _camera() -> Camera3D:
	if Engine.is_editor_hint():   # (the editor's 3D view; looked up by name so exported games don't need the class)
		var editor := Engine.get_singleton(&"EditorInterface")
		return editor.get_editor_viewport_3d(0).get_camera_3d() if editor else null
	return get_viewport().get_camera_3d()


## Two crossed quads, `height` tall, bottom on the ground; UV y 0 at the top (the shader sways those corners).
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := height * 0.9
	for angle in [0.4, 0.4 + PI * 0.5]:
		var side := Vector3(cos(angle), 0.0, sin(angle)) * w
		var corners := [-side, side, side + Vector3.UP * height, -side + Vector3.UP * height]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[k])
			st.add_vertex(corners[k])
	var mesh := st.commit()
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"sprites", sprites)
	material.set_shader_parameter(&"fade_end", fade_end)
	material.set_shader_parameter(&"fade_start", fade_end - 10.0)
	mesh.surface_set_material(0, material)
	return mesh


func _sample(image: Image, x: float, z: float) -> Color:
	if image == null:
		return Color(0, 0, 0, 0)
	var u := clampi(int((x - map_origin.x) / map_size * image.get_width()), 0, image.get_width() - 1)
	var v := clampi(int((z - map_origin.y) / map_size * image.get_height()), 0, image.get_height() - 1)
	return image.get_pixel(u, v)


func _grows(x: float, z: float) -> bool:
	if _mask and _sample(_mask, x, z).r < 0.5:
		return false
	var s := _sample(_splat, x, z)
	return s.r < 0.4 and s.g < 0.4 and s.a < 0.4 and s.b < 0.6


func _build(key: Vector2i) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var xforms: Array[Transform3D] = []
	var flowers: Array[float] = []
	var count := int(CHUNK * CHUNK * per_square_metre)
	for n in count:
		var x := (key.x + rng.randf()) * CHUNK
		var z := (key.y + rng.randf()) * CHUNK
		var world := Vector3(x, 0.0, z)
		if not _grows(x, z):
			rng.randf()
			continue
		var h := _map.ground_height(world)
		if is_nan(h):
			continue
		var size := rng.randf_range(0.7, 1.15)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * rng.randf_range(0.8, 1.1), size))
		xforms.append(Transform3D(basis, Vector3(x, h - 0.02, z)))
		flowers.append(1.0 if rng.randf() < flower_chance else 0.0)
	if xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, Color(flowers[i], 0, 0, 0))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.top_level = true
	add_child(node)
	return node
