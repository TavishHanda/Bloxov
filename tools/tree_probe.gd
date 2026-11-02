extends SceneTree
## (0.29.3) Not part of the smoke test.
## Times the trees' build and prints a fingerprint of the meshes (to check a faster build makes the same trees).
func _initialize() -> void:
	_run.call_deferred()
func _find(n: Node, file: String) -> Node:
	if n.get_script() and n.get_script().resource_path.ends_with(file): return n
	for c in n.get_children():
		var f := _find(c, file)
		if f: return f
	return null
func _print(node: Node, label: String, t: int) -> void:
	var ms := (Time.get_ticks_usec() - t) / 1000
	var verts := 0
	var ctx := HashingContext.new(); ctx.start(HashingContext.HASH_MD5)
	for c in node.get_children():
		if not c is MeshInstance3D: continue
		var mi := c as MeshInstance3D
		var a := mi.mesh.surface_get_arrays(0)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var count := idx.size() if not idx.is_empty() else v.size()
		var ev := PackedVector3Array(); var en := PackedVector3Array(); var eu := PackedVector2Array(); var ec := PackedColorArray()
		for k in count:
			var j := idx[k] if not idx.is_empty() else k
			ev.append(v[j]); en.append(n[j]); eu.append(uv[j]); ec.append(col[j])
		verts += count
		ctx.update(var_to_bytes([mi.position, mi.visibility_range_begin, mi.visibility_range_end, ev, en, eu, ec]))
	print("commit ", Engine.get_meta("commit", 0) / 1000)
	print("%s: %d ms, %d meshes, %d vertices drawn, fingerprint %s" % [label, ms, node.get_child_count(), verts, ctx.finish().hex_encode()])
func _run() -> void:
	var map := (load("res://scenes/maps/old_bloxov.tscn") as PackedScene).instantiate()
	var holder := Node3D.new(); root.add_child(holder)
	for file in ["trees.gd", "bushes.gd"]:
		var node := _find(map, file)
		node.get_parent().remove_child(node)
		var t := Time.get_ticks_usec()
		holder.add_child(node)
		_print(node, file, t)
	quit()
