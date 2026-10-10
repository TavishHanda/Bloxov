class_name AINav
extends RefCounted
## Navigation queries for the AI, safe before the map is ready. `node` is any node in the raid: each raid
## (a SubViewport on the server) has its own navigation map.
## A raid world made on the server mid-game has no synced navigation map for its first frames; asking it then only
## logs errors. Until it's ready these act like "no map" (callers then walk straight).


static func ready(node: Node3D) -> bool:
	return NavigationServer3D.map_get_iteration_id(node.get_world_3d().navigation_map) > 0


## The closest walkable point to `point`; Vector3.ZERO without a map.
static func closest(node: Node3D, point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(node.get_world_3d().navigation_map, point) if ready(node) else Vector3.ZERO


## No limit on how much of the map a path search may look at: the default (4096 pieces) is less than a real map
## has (Old Bloxov, 0.10.0), so a path across it would stop short and lead somewhere odd. Empty without a map.
static func path(node: Node3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	if not ready(node):
		return PackedVector3Array()
	var query := NavigationPathQueryParameters3D.new()
	query.map = node.get_world_3d().navigation_map
	query.start_position = from
	query.target_position = to
	query.path_search_max_polygons = 0
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	return result.path


## A random walkable point anywhere on the map; Vector3.ZERO without a map.
static func random_point(node: Node3D) -> Vector3:
	return NavigationServer3D.map_get_random_point(node.get_world_3d().navigation_map, 1, false) if ready(node) else Vector3.ZERO


## Walking length of a path; INF for an empty or one-point path.
static func path_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total if points.size() > 1 else INF
