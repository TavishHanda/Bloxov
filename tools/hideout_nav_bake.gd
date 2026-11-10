extends SceneTree
## Bakes where the hideout's crew can walk (lively hideout, 0.34.1) from the hideout level's colliders, to
## assets/hideout/nav.res (HideoutCrew walks them round with it). Re-run after make_hideout.py changes the cave:
##   godot --headless -s tools/hideout_nav_bake.gd
const OUT := "res://assets/hideout/nav.res"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node3D = (load("res://scenes/hideout/hideout_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await physics_frame
	await physics_frame
	var blocks := level.get_node("Blocks") as BoxMap
	var faces: PackedVector3Array = blocks.collision_faces
	for body in level.find_children("*", "StaticBody3D", true, false):   # (props too: they block walking)
		if body == blocks:
			continue
		for shape_owner in (body as StaticBody3D).get_shape_owners():
			for k in (body as StaticBody3D).shape_owner_get_shape_count(shape_owner):
				var shape := (body as StaticBody3D).shape_owner_get_shape(shape_owner, k)
				if shape is ConcavePolygonShape3D:
					var xf := (body as StaticBody3D).global_transform * (body as StaticBody3D).shape_owner_get_transform(shape_owner)
					for p in (shape as ConcavePolygonShape3D).get_faces():
						faces.append(xf * p)
	var source := NavigationMeshSourceGeometryData3D.new()
	source.add_faces(faces, Transform3D.IDENTITY)
	var mesh := NavigationMesh.new()
	mesh.cell_size = 0.15
	mesh.cell_height = 0.1
	mesh.agent_radius = 0.45
	mesh.agent_height = 1.8
	mesh.agent_max_climb = 0.3
	mesh.agent_max_slope = 46.0
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	print("hideout nav: %d polygons from %d faces" % [mesh.get_polygon_count(), faces.size() / 3])
	ResourceSaver.save(mesh, OUT)
	quit()
