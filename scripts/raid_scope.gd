class_name RaidScope
extends RefCounted
## The game server runs several raids at once, each in its own SubViewport (RaidWorld), but node groups are shared
## by the whole game. These helpers only return group members in the same raid as `node` (same viewport). On a
## player's machine there's only one raid, so they return the whole group.


static func nodes(node: Node, group: StringName) -> Array[Node]:
	var viewport := node.get_viewport()
	var list: Array[Node] = []
	for other in node.get_tree().get_nodes_in_group(group):
		if other.get_viewport() == viewport:
			list.append(other)
	return list


## Calls `method` on the group members in `node`'s raid (like SceneTree.call_group, but for one raid).
static func call_all(node: Node, group: StringName, method: StringName, args: Array = []) -> void:
	for other in nodes(node, group):
		other.callv(method, args)
