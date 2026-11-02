extends SceneTree
## Lists every material the raid (Bloxov Frontlines, the AI, the player) and the walkable hideout draw with, and
## saves one stand-in per distinct shader to res://assets/warm/<name>_warm.tscn for ShaderWarm (0.29.5).
## Why: a browser builds a shader the first time something using it is drawn. With a cold browser cache (first visit,
## or every shader changed, as with the Godot 4.7 update) the first raid built ~220 shader programs while loading and
## took ~30 s; ShaderWarm draws these stand-ins on the title screen and in the hideout instead, a few each frame.
## Re-run after adding materials, shaders or new kinds of things to the raid or hideout (a stale list only means
## some shaders get built in the raid as before):
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/gen_shader_warm.gd

const OUT_DIR := "res://assets/warm/"
## Scenes that join a raid after it starts (AI, other players), dropped into it so their materials are listed too.
const RAID_EXTRAS := ["res://scenes/scav.tscn", "res://scenes/raider.tscn", "res://scenes/boss.tscn",
	"res://scenes/sniper.tscn", "res://scenes/remote_player.tscn", "res://scenes/loot_bag.tscn",
	"res://scenes/backpack_bag.tscn", "res://scenes/smoke_column.tscn"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 360)
	RaidMap.scene_path = "res://scenes/maps/old_bloxov.tscn"
	var raid: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(raid)
	current_scene = raid
	for path in RAID_EXTRAS:
		var extra: Node = (load(path) as PackedScene).instantiate()
		extra.process_mode = Node.PROCESS_MODE_DISABLED
		raid.add_child(extra)
	# Twice: just after it starts (the effects warm-ups, freed after half a second) and once it has settled.
	await process_frame
	await process_frame
	var found := _collect(raid)
	await _settle()
	found.merge(_collect(raid))
	_save("raid", found)
	raid.queue_free()
	await _settle()
	var hideout: Node = (load("res://scenes/hideout_world.tscn") as PackedScene).instantiate()
	root.add_child(hideout)
	current_scene = hideout
	await process_frame
	await process_frame
	var in_hideout := _collect(hideout)
	await _settle()
	in_hideout.merge(_collect(hideout))
	_save("hideout", in_hideout)
	quit()


func _settle() -> void:
	for i in 20:
		await process_frame


## Distinct (material, how it's drawn) pairs under `top`: key -> [material, instanced, colors, custom data].
func _collect(top: Node) -> Dictionary:
	var found := {}
	var stack: Array[Node] = [top]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children(true))
		if node is MeshInstance3D and node.mesh != null:
			for i in node.mesh.get_surface_count():
				_add(found, node.get_active_material(i), false, false, false)
			_add(found, node.material_overlay, false, false, false)
		elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
			var mm: MultiMesh = node.multimesh
			for i in mm.mesh.get_surface_count():
				_add(found, node.material_override if node.material_override else mm.mesh.surface_get_material(i),
					true, mm.use_colors, mm.use_custom_data)
		elif node is CPUParticles3D and node.mesh != null:
			for i in node.mesh.get_surface_count():
				_add(found, node.material_override if node.material_override else node.mesh.surface_get_material(i),
					true, true, true)
		elif node is CSGShape3D and node.is_root_shape():
			var meshes: Array = node.get_meshes()
			if meshes.size() > 1 and meshes[1] != null:
				for i in meshes[1].get_surface_count():
					_add(found, meshes[1].surface_get_material(i), false, false, false)
	return found


func _add(found: Dictionary, material: Material, instanced: bool, colors: bool, custom: bool) -> void:
	while material != null:
		var key := "%s|%s|%s|%s" % [_shader_key(material), instanced, colors, custom]
		if not found.has(key):
			found[key] = [material, instanced, colors, custom]
		material = material.next_pass


## What decides the shader a material compiles to: a ShaderMaterial's shader, or a built-in material's switches
## (its on/off and choice settings and which texture slots are filled; colours and amounts are only inputs).
static func _shader_key(material: Material) -> String:
	if material is ShaderMaterial:
		var shader: Shader = material.shader
		return "shader:" + (shader.resource_path if shader and shader.resource_path != "" else str(hash(shader.code if shader else "")))
	var parts := [material.get_class()]
	for prop in material.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_STORAGE) or prop.name == "next_pass" or prop.name == "render_priority":
			continue
		var value = material.get(prop.name)
		if value is bool or value is int:
			parts.append("%s=%s" % [prop.name, value])
		elif prop.type == TYPE_OBJECT and prop.hint == PROPERTY_HINT_RESOURCE_TYPE and prop.hint_string.contains("Texture"):
			parts.append("%s=%s" % [prop.name, value != null])
	return ",".join(parts)


## Saves a scene of stand-ins: one tiny triangle per entry with a copy of its material (textures left out, so loading
## the list doesn't load the game's pictures; a built-in material's empty slot gets a 1x1 white picture so it still
## compiles to the shader with that slot in use).
func _save(name: String, found: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = name.capitalize() + "Warm"
	var white := ImageTexture.create_from_image(Image.create_from_data(1, 1, false, Image.FORMAT_RGBA8, PackedByteArray([255, 255, 255, 255])))
	var mesh := _triangle()
	var n := 0
	var keys: Array = found.keys()
	keys.sort()
	for key in keys:
		var entry: Array = found[key]
		var material := _copy(entry[0], white)
		var node: GeometryInstance3D
		if entry[1]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = entry[2]
			mm.use_custom_data = entry[3]
			mm.mesh = mesh
			mm.instance_count = 1
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			node = mmi
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			node = mi
		node.material_override = material
		node.name = "W%03d" % n
		holder.add_child(node)
		node.owner = holder
		n += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene := PackedScene.new()
	scene.pack(holder)
	var path := OUT_DIR + name + "_warm.tscn"
	ResourceSaver.save(scene, path)
	print("gen_shader_warm: %s: %d stand-ins -> %s" % [name, n, path])
	holder.free()


static func _copy(material: Material, white: Texture2D) -> Material:
	if material is ShaderMaterial:
		var copy := ShaderMaterial.new()
		copy.shader = material.shader
		return copy
	var copy: Material = material.duplicate()
	copy.next_pass = null
	for prop in copy.get_property_list():
		if prop.type == TYPE_OBJECT and prop.hint == PROPERTY_HINT_RESOURCE_TYPE and prop.hint_string.contains("Texture") \
				and copy.get(prop.name) != null:
			copy.set(prop.name, white)
	return copy


static func _triangle() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(0, 1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0)])
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
