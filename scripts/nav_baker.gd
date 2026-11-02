class_name NavBaker
extends NavigationRegion3D
## Builds the raid's navigation mesh (where enemies can walk) when the raid starts, from everything solid
## in the "nav_source" group (the level's CSG boxes and the loot containers' box colliders). Baked at runtime
## so editing the map by hand never needs a manual re-bake. Enemies walk straight at their goal until it's ready.
## The geometry is built from the boxes' sizes (not read back from the GPU), which keeps it cheap on the web.

signal baked

const SOURCE_GROUP := &"nav_source"
## Baked ahead of time (0.29.3, faster loading: the real map's bake took ~1.3 s on every raid, longer on the web and on
## the server): `tools/nav_bake.gd` saves the bake as PREBAKED_DIR/<fingerprint>.res, the fingerprint being the
## source geometry's. A raid whose geometry matches loads that; anything else (the test map, a map changed since)
## bakes here as before, so a stale file only costs time, never a wrong mesh.
const PREBAKED_DIR := "res://assets/nav/"

var is_baked := false
var source_key := ""   # (this raid's geometry fingerprint: tools/nav_bake.gd saves the bake under it)


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
	for node in RaidScope.nodes(self, SOURCE_GROUP):
		_add_geometry(node, source)
	source_key = fingerprint(navigation_mesh, source)
	var prebaked := PREBAKED_DIR + source_key + ".res"
	if ResourceLoader.exists(prebaked):
		navigation_mesh = load(prebaked) as NavigationMesh
	else:
		NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
	# Hand the freshly baked polygons to the navigation server (the map picks them up on its next sync).
	NavigationServer3D.region_set_navigation_mesh(get_rid(), navigation_mesh)
	is_baked = true
	baked.emit()


## What a bake is made from: the settings and every face (so the same geometry always gives the same name).
static func fingerprint(mesh: NavigationMesh, source: NavigationMeshSourceGeometryData3D) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(var_to_bytes([mesh.cell_size, mesh.cell_height, mesh.agent_radius, mesh.agent_height,
		mesh.agent_max_climb, mesh.agent_max_slope]))
	if source.has_data():   # (hashing nothing is an error)
		ctx.update(source.get_vertices().to_byte_array())
		ctx.update(source.get_indices().to_byte_array())
	return ctx.finish().hex_encode()


## Adds solid boxes under `node`: CSG boxes with collision, box colliders on the world layer, and gray-box maps
## (BoxMap: all their solid boxes at once).
func _add_geometry(node: Node, source: NavigationMeshSourceGeometryData3D) -> void:
	if node is BoxMap:
		var map := node as BoxMap
		source.add_faces(map.nav_faces(), map.global_transform)
		if not map.people_faces.is_empty():   # (railings, fences: people-only boxes, 0.19.8)
			source.add_faces(map.people_faces, map.global_transform)
		return
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
