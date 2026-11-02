extends SceneTree
## Bakes the real map's enemy navigation ahead of time (0.29.3): saves it to assets/nav/<fingerprint>.res, which
## NavBaker loads instead of baking at raid start (~1.3 s a raid, more on the web and the server). Old bakes in the
## folder are removed. Re-run after changing the map (the generator) or NavBaker's settings; until then raids bake
## at the start as before (slower, never wrong).
##   godot --headless -s tools/nav_bake.gd
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RaidMap.scene_path = "res://scenes/maps/old_bloxov.tscn"
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var baker: NavBaker = null
	for n in main.find_children("*", "NavigationRegion3D", true, false):
		if n is NavBaker:
			baker = n
	if baker == null:
		push_error("nav_bake: no NavBaker in the raid")
		quit(1)
		return
	if not baker.is_baked:
		await baker.baked
	var dir := NavBaker.PREBAKED_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".res") and f != baker.source_key + ".res":
			DirAccess.remove_absolute(dir + f)
			print("nav_bake: removed old ", f)
	var path := dir + baker.source_key + ".res"
	var mesh := baker.navigation_mesh.duplicate() as NavigationMesh
	var err := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
	print("nav_bake: saved %s (%d polygons), error %d" % [path, mesh.get_polygon_count(), err])
	quit(0 if err == OK else 1)
