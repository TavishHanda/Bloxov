extends SceneTree
## Bakes the real maps' enemy navigation ahead of time (0.29.3): saves it to assets/nav/<fingerprint>.res, which
## NavBaker loads instead of baking at raid start (~1.3 s a raid, more on the web and the server). Old bakes in the
## folder are removed. Re-run after changing the map (the generator) or NavBaker's settings; until then raids bake
## at the start as before (slower, never wrong).
##   godot --headless -s tools/nav_bake.gd
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Every map in RaidMap.MAPS (Riptide, map 2, 2026-11-09), so cleaning up old bakes never deletes another map's.
	var keep := {}
	for entry: Array in RaidMap.MAPS:
		var key := await _bake(entry[1])
		if key == "":
			quit(1)
			return
		keep[key + ".res"] = true
	var dir := NavBaker.PREBAKED_DIR
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".res") and not keep.has(f):
			DirAccess.remove_absolute(dir + f)
			print("nav_bake: removed old ", f)
	quit(0)


## Bakes one map and saves it; returns its fingerprint ("" if it failed).
func _bake(map_path: String) -> String:
	RaidMap.scene_path = map_path
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var baker: NavBaker = null
	for n in main.find_children("*", "NavigationRegion3D", true, false):
		if n is NavBaker:
			baker = n
	if baker == null:
		push_error("nav_bake: no NavBaker in the raid")
		return ""
	if not baker.is_baked:
		await baker.baked
	var dir := NavBaker.PREBAKED_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + baker.source_key + ".res"
	var mesh := baker.navigation_mesh.duplicate() as NavigationMesh
	var err := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
	print("nav_bake: %s -> saved %s (%d polygons), error %d" % [map_path, path, mesh.get_polygon_count(), err])
	var key := baker.source_key
	main.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	return key if err == OK else ""
