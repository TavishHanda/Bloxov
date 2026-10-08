class_name NavBaker
extends NavigationRegion3D
## Builds the raid's navigation mesh (where enemies can walk) when the raid starts, from everything solid
## in the "nav_source" group (the level's CSG boxes and the loot containers' box colliders). Baked at runtime
## so editing the map by hand never needs a manual re-bake. Enemies walk straight at their goal until it's ready.
## The geometry is built from the boxes' sizes (not read back from the GPU), which keeps it cheap on the web.

signal baked

const SOURCE_GROUP := &"nav_source"

var is_baked := false


func _ready() -> void:
	var mesh := NavigationMesh.new()
	# Sizes are multiples of the cell size so nothing gets rounded. Paths keep 0.75 m from walls: the scav's
	# 0.8 x 0.6 m body reaches 0.5 m from its center when it turns, and would snag on corners at 0.5.
	# They can step up small ledges but not onto crates.
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = 0.75
	mesh.agent_height = 1.75
	mesh.agent_max_climb = 0.25
	mesh.agent_max_slope = 40.0
	navigation_mesh = mesh
	# CSG shapes finish building a frame after entering the tree, so bake after that.
	_bake.call_deferred()


func _bake() -> void:
	await get_tree().physics_frame
	var source := NavigationMeshSourceGeometryData3D.new()
	for node in get_tree().get_nodes_in_group(SOURCE_GROUP):
		_add_geometry(node, source)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
	# Hand the freshly baked polygons to the navigation server (the map picks them up on its next sync).
	NavigationServer3D.region_set_navigation_mesh(get_rid(), navigation_mesh)
	is_baked = true
	baked.emit()


## Adds solid boxes under `node`: CSG boxes with collision, and box colliders on the world layer.
func _add_geometry(node: Node, source: NavigationMeshSourceGeometryData3D) -> void:
	if node is CSGBox3D and (node as CSGBox3D).use_collision:
		var box := BoxMesh.new()
		box.size = (node as CSGBox3D).size
		source.add_faces(box.get_faces(), (node as Node3D).global_transform)
	elif node is CollisionShape3D and (node as CollisionShape3D).shape is BoxShape3D:
		var body := node.get_parent() as CollisionObject3D
		if body != null and body.collision_layer & 1:
			var box := BoxMesh.new()
			box.size = ((node as CollisionShape3D).shape as BoxShape3D).size
			source.add_faces(box.get_faces(), (node as Node3D).global_transform)
	for child in node.get_children():
		_add_geometry(child, source)
