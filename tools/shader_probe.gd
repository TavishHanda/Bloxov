extends SceneTree
## (0.29.3) Not part of the smoke test.
## Lists the distinct shaders a scene draws with (each one is compiled the first time it's seen: on the web that's
## a stall every time, there's no shader cache there).
func _initialize() -> void:
	_run.call_deferred()
var shaders := {}
func _mat(m: Material, where: String) -> void:
	if m == null: return
	var key := _key(m)
	if not shaders.has(key):
		var desc := m.get_class()
		if m is ShaderMaterial and (m as ShaderMaterial).shader: desc += " " + (m as ShaderMaterial).shader.resource_path
		shaders[key] = [0, desc, where, m]
	shaders[key][0] += 1
	if m.next_pass: _mat(m.next_pass, where + "(next)")
func _key(m: Material) -> String:
	if m is ShaderMaterial: return "SM " + str((m as ShaderMaterial).shader.get_instance_id() if (m as ShaderMaterial).shader else 0) + " " + ((m as ShaderMaterial).shader.resource_path if (m as ShaderMaterial).shader else "")
	var out := m.get_class()
	for p in m.get_property_list():
		var t: int = p.type
		var n: String = p.name
		if n == "next_pass" or n == "resource_name" or n == "resource_path" or n == "render_priority": continue
		if t == TYPE_BOOL or (t == TYPE_INT and p.hint == PROPERTY_HINT_ENUM):
			out += " %s=%s" % [n, str(m.get(n))]
		elif t == TYPE_OBJECT and p.hint == PROPERTY_HINT_RESOURCE_TYPE and str(p.hint_string).contains("Texture"):
			out += " %s=%s" % [n, str(m.get(n) != null)]
	return out
func _walk(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		_mat(g.material_override, str(n.get_path()))
		_mat(g.material_overlay, str(n.get_path()))
		var mesh: Mesh = null
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
			for i in (n as MeshInstance3D).get_surface_override_material_count():
				_mat((n as MeshInstance3D).get_surface_override_material(i), str(n.get_path()))
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh: mesh = (n as MultiMeshInstance3D).multimesh.mesh
		elif n is GPUParticles3D: mesh = (n as GPUParticles3D).draw_pass_1; _mat((n as GPUParticles3D).process_material, str(n.get_path()) + "(process)")
		elif n is CPUParticles3D: mesh = (n as CPUParticles3D).mesh
		elif n is SpriteBase3D or n is Label3D: _mat(null, "")
		if mesh: for i in mesh.get_surface_count(): _mat(mesh.surface_get_material(i), str(n.get_path()))
	for c in n.get_children(): _walk(c)
func _run() -> void:
	var path := "res://scenes/main.tscn"
	for a in OS.get_cmdline_user_args(): if a.begins_with("scene="): path = a.substr(6)
	RaidMap.scene_path = "res://scenes/maps/old_bloxov.tscn"
	var n := (load(path) as PackedScene).instantiate()
	root.add_child(n)
	for i in 10: await process_frame
	_walk(root)
	var rows := shaders.values()
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("DISTINCT SHADERS: ", rows.size())
	for r in rows:
		var m: Material = r[3]
		var extra := ""
		var b := m as BaseMaterial3D
		if b: extra = "transp=%d shading=%d tex=%s vcol=%s cull=%d emis=%s normal=%s" % [b.transparency, b.shading_mode, str(b.albedo_texture != null), str(b.vertex_color_use_as_albedo), b.cull_mode, str(b.emission_enabled), str(b.normal_enabled)]
		print("%5d  %s  %s  %s" % [r[0], r[1], extra, r[2]])
	quit()
