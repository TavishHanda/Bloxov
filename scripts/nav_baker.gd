class_name NavBaker
extends NavigationRegion3D
## Builds the raid's navigation mesh (where enemies can walk) when the raid starts, from everything solid
## in the "nav_source" group (the level's CSG boxes and the loot containers' box colliders). Baked at runtime
## so editing the map by hand never needs a manual re-bake. Enemies walk straight at their goal until it's ready.
## The geometry is built from the boxes' sizes (not read back from the GPU), which keeps it cheap on the web.

signal baked

const SOURCE_GROUP := &"nav_source"
## AI vaulting (0.13.1): a link over low, thin cover every this many meters along it.
const VAULT_LINK_SPACING := 3.0
## Going over costs as much as walking this many extra meters, so a short way round still wins.
const VAULT_LINK_COST := 3.0

var is_baked := false
var _vault_links: Array[NavigationLink3D] = []


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
	for link in _vault_links:
		link.queue_free()
	_vault_links.clear()
	for node in RaidScope.nodes(self, SOURCE_GROUP):
		_add_geometry(node, source)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
	# Hand the freshly baked polygons to the navigation server (the map picks them up on its next sync).
	NavigationServer3D.region_set_navigation_mesh(get_rid(), navigation_mesh)
	is_baked = true
	baked.emit()


## Adds solid boxes under `node`: CSG boxes with collision, box colliders on the world layer, and gray-box maps
## (BoxMap: all their solid boxes at once).
func _add_geometry(node: Node, source: NavigationMeshSourceGeometryData3D) -> void:
	if node is BoxMap:
		var map := node as BoxMap
		source.add_faces(map.collision_faces, map.global_transform)
		for i in range(0, map.boxes.size(), BoxMap.STRIDE):
			var b := map.boxes
			if b[i + 9] > 0.5 and is_zero_approx(b[i + 7]):
				_add_vault_links(map.global_transform * Transform3D(Basis(Vector3.UP, deg_to_rad(b[i + 6])),
					Vector3(b[i], b[i + 1], b[i + 2])), Vector3(b[i + 3], b[i + 4], b[i + 5]))
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
			_add_vault_links((node as Node3D).global_transform, box.size)
	for child in node.get_children():
		_add_geometry(child, source)


## Low, thin cover (fences, sandbags, low walls): links across it, so the AI's paths can go over (AI vault when
## their path walks them into it; see Scav). Upright boxes only.
func _add_vault_links(xform: Transform3D, size: Vector3) -> void:
	if size.y < Vault.MIN_HEIGHT or size.y > Vault.VAULT_HEIGHT or not xform.basis.y.normalized().is_equal_approx(Vector3.UP):
		return
	var across := xform.basis.x.normalized()
	var along := xform.basis.z.normalized()
	var thickness := size.x
	var length := size.z
	if size.z < size.x:
		across = xform.basis.z.normalized()
		along = xform.basis.x.normalized()
		thickness = size.z
		length = size.x
	if thickness > Vault.MAX_THICKNESS or length < 0.8:
		return
	# Something solid just above the top: a gap in a wall. A window (a gap of 1 m or more, 0.13.11, owner: the AI
	# may climb through windows if it fits in) is linked like low cover; anything tighter isn't.
	var top := xform.origin + Vector3(0, size.y * 0.5 + 0.05, 0)
	var above := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(top, top + Vector3(0, 1.6, 0), 1))
	if not above.is_empty() and (above.position as Vector3).y - top.y < 1.0:
		return
	var is_window := not above.is_empty()
	var count := maxi(1, floori(length / VAULT_LINK_SPACING))
	var bottom := xform.origin - Vector3(0, size.y * 0.5, 0)
	var space := get_world_3d().direct_space_state
	for k in count:
		var at := bottom + along * ((k + 0.5) / count - 0.5) * length
		# A window: only if an AI fits where it lands on both sides (furniture or a crate right inside would
		# leave it pressing into the wall).
		if is_window and not (_room_at(at - across * (thickness * 0.5 + 0.55)) and _room_at(at + across * (thickness * 0.5 + 0.55))):
			continue
		# Only where both sides are open: a safe or bench against a wall would otherwise get a link through the
		# wall (0.14.0: the AI's paths went into the locked bank vault through its outside wall). The rays start
		# inside the box itself, which they don't count.
		var middle := at + Vector3.UP * (size.y * 0.5)
		var blocked := false
		for side in [-1.0, 1.0]:
			var end: Vector3 = middle + across * side * (thickness * 0.5 + 1.0)
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(middle, end, 1)).is_empty():
				blocked = true
		if blocked:
			continue
		var link := NavigationLink3D.new()
		link.bidirectional = true
		link.enter_cost = VAULT_LINK_COST
		add_child(link)
		link.global_position = at
		link.start_position = link.to_local(at - across * (thickness * 0.5 + 1.0))
		link.end_position = link.to_local(at + across * (thickness * 0.5 + 1.0))
		_vault_links.append(link)


## Room for an AI standing at `feet` (on the floor there).
func _room_at(feet: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(feet + Vector3(0, 0.5, 0), feet + Vector3(0, -1.0, 0), 1))
	if down.is_empty():
		return false
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.transform = Transform3D(Basis(), (down.position as Vector3) + Vector3(0, 1.1, 0))
	return space.intersect_shape(query, 1).is_empty()
