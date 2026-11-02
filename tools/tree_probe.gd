extends SceneTree
## (0.29.3, 0.29.8) Not part of the smoke test.
## Times the trees' build and prints a fingerprint of the meshes, built all at once and built a bit at a time the way
## the hideout does it (the two fingerprints must match: the same trees either way).
##   xvfb-run -a godot --rendering-driver opengl3 -s tools/tree_probe.gd
const TREES := preload("res://scripts/trees.gd")
const LIST := "res://scenes/maps/old_bloxov_trees.tres"

func _initialize() -> void:
	_run.call_deferred()

func _print(node: Node, label: String, ms: int) -> void:
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
	print("%s: %d ms, %d meshes, %d vertices drawn, fingerprint %s" % [label, ms, node.get_child_count(), verts, ctx.finish().hex_encode()])

func _trees() -> Node3D:
	var t: Node3D = TREES.new()
	t.sheet = load("res://assets/textures/trees/trees.png")
	t.look = load(LIST).get_meta(&"look")
	t.source = load(LIST)
	return t

func _run() -> void:
	var holder := Node3D.new(); root.add_child(holder)
	var t0 := Time.get_ticks_usec()
	var full := _trees()
	holder.add_child(full)
	_print(full, "built at once", (Time.get_ticks_usec() - t0) / 1000)
	TREES._built_sets.clear()
	var frames := 0
	var work := 0
	while true:
		var t := Time.get_ticks_usec()
		var done := TREES.prebuild(LIST, 3000)
		work += Time.get_ticks_usec() - t
		frames += 1
		if done: break
	t0 = Time.get_ticks_usec()
	var later := _trees()
	holder.add_child(later)
	print("prebuilt over %d frames (%d ms of work), then the raid's part took %d ms" % [frames, work / 1000, (Time.get_ticks_usec() - t0) / 1000])
	_print(later, "built a bit at a time", 0)
	quit()
