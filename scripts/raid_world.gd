class_name RaidWorld
extends SubViewport
## One online raid's copy of the map on the server, in its own physics world (so several raids never touch),
## plus a short history of where every player in it was. The server checks shots here: walls block bullets,
## and a shot is tested against where the targets were on the shooter's screen when they fired (lag
## compensation), so what looked like a hit counts.
## It also runs the raid's AI (0.7.8): the scav spawner and navigation, with a proxy body for every player (the
## player scene in proxy mode) so scavs can see, hear, shoot and bash them. What scavs do to a proxy is passed on to
## that player's game; what scavs look like and do is sent to everyone in the raid (Network).
## Loaded at runtime by path, and no Player/Scav types here: the server autoload mustn't depend on scripts that
## preload sounds (a fresh project import would fail).

const RAID_SCENE := "res://scenes/main.tscn"
## The map pieces the server needs (solid things). Everything else in the raid scene is for players' screens.
const KEEP := ["Level", "Loot", "Navigation", "EnemySpawner", "KeyDoors", "Doors"]
const PLAYER_SCENE := "res://scenes/player.tscn"
## Seconds of position history kept per player, and the furthest back a shot is checked.
const HISTORY := 1.0
const MAX_REWIND := 0.5

## peer -> Array of [server seconds, state], oldest first.
var history := {}
## Scav/Raider instance id -> Array of [server seconds, position, yaw], oldest first (0.15.28): where each AI was
## when the server sent it to the players, so shots at AI are checked where the shooter saw them (like players).
var enemy_history := {}
## peer -> that player's proxy body (player.tscn in proxy mode).
var proxies := {}
## The raid scene's root inside this world (scavs and loot bags are added under it).
var raid: Node

## A scav hurt or bashed a player: Network passes it on to their game.
signal player_hit(peer: int, amount: int, from: Vector3, head: bool)
signal player_bashed(peer: int, amount: int, from: Vector3, shove: float, aim_block: float)
## Something a scav did that everyone in the raid should see/hear: kind is "fired" (pos = where the shot ended),
## "alerted", "bash" or "died" (pos = where).
signal enemy_event(id: int, kind: String, pos: Vector3)
## Loot (0.7.9): a bag appeared (a body, dropped items) or went (emptied). Network tells everyone in the raid.
signal bag_spawned(id: String, pos: Vector3, yaw: float, title: String, search: float)
signal bag_removed(id: String)
## A key door was unlocked (0.14.0): Network tells everyone in the raid.
signal door_opened(id: String)
## A player broke a window pane (0.18.8): its number in the map's BoxMap `window_panes`.
signal window_broken(pane: int)
## A door swung open (1, -1) or shut (0) (0.17): a player asked, or the AI walked up to it. Network tells the raid.
signal door_changed(id: String, state: int)
## A container with a lid (a dropped backpack, 0.17.10) was opened or shut: everyone sees the lid move.
signal lid_moved(id: String, open: bool)

## Loot containers are shared: their contents live here, and one player at a time has one open
## (container id -> peer). Ids are the container's node name: "Crate3" under Loot, or "Bag12" for bags.
var locks := {}
var _next_bag := 1


func _init() -> void:
	own_world_3d = true
	# Nothing is drawn: it only exists for its physics.
	disable_3d = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	size = Vector2i(2, 2)


func _ready() -> void:
	raid = (load(RAID_SCENE) as PackedScene).instantiate()
	for child in raid.get_children():
		if not KEEP.has(String(child.name)):
			raid.remove_child(child)
			child.free()
	raid.child_entered_tree.connect(_on_raid_child)
	add_child(raid)
	var doors := raid.get_node_or_null("Doors")
	if doors != null:
		for door in doors.get_children():
			if door.has_signal("changed"):
				var id := String(door.name)
				door.changed.connect(func(state: int) -> void: door_changed.emit(id, state))


## Every scav the spawner adds: pass its events on. Every bag (scav bodies): name it and announce it.
func _on_raid_child(node: Node) -> void:
	if node is LootContainer:
		_announce_bag.call_deferred(node)
		return
	if not node.has_signal("fired"):
		return
	var id := node.get_instance_id()
	node.fired.connect(func(end: Vector3) -> void: enemy_event.emit(id, "fired", end))
	node.alerted.connect(func() -> void: enemy_event.emit(id, "alerted", Vector3.ZERO))
	node.barked.connect(func(kind: String) -> void: enemy_event.emit(id, "bark:" + kind, Vector3.ZERO))
	node.bash_started.connect(func() -> void: enemy_event.emit(id, "bash", Vector3.ZERO))
	node.tree_exiting.connect(func() -> void: enemy_event.emit(id, "died", node.global_position))


func _announce_bag(bag: LootContainer) -> void:
	if not is_instance_valid(bag):
		return
	bag.name = "Bag%d" % _next_bag
	_next_bag += 1
	bag_spawned.emit(String(bag.name), bag.global_position, bag.rotation.y, bag.display_name, bag.search_time)


## A shared container by id, or null.
func container(id: String) -> LootContainer:
	if id.is_empty() or id.contains("/") or id.contains(".."):
		return null
	var node := raid.get_node_or_null("Loot/" + id)
	if node == null:
		node = raid.get_node_or_null(id)
	return node as LootContainer


## A player opens a container: its contents if they get it, or null if someone else has it open.
func open_container(peer: int, id: String) -> Variant:
	var box := container(id)
	if box == null or (locks.has(id) and locks[id] != peer):
		return null
	close_containers(peer)
	locks[id] = peer
	if box.find_child("Lid", true, false) != null:
		lid_moved.emit(id, true)
	return box.net_data()


## The player who has it open moved things around: store the new contents (an emptied bag goes away).
func update_container(peer: int, id: String, data: Array) -> void:
	var box := container(id)
	if box == null or locks.get(id) != peer:
		return
	box.load_net_data(data)
	if box.remove_when_empty and box.is_empty():
		locks.erase(id)
		box.queue_free()
		bag_removed.emit(id)


## Lets go of whatever this player has open (closed it, walked off, died, left).
func close_containers(peer: int) -> void:
	for id in locks.keys():
		if locks[id] == peer:
			locks.erase(id)
			var box := container(id)
			if box != null and box.find_child("Lid", true, false) != null:
				lid_moved.emit(id, false)


## A player unlocked key door `id` (a node under KeyDoors): open it here (shots and the AI's bodies pass) and
## tell the raid. Untyped: no KeyDoor type here (see the top).
func open_door(id: String) -> void:
	if id.is_empty() or id.contains("/") or id.contains(".."):
		return
	var door := raid.get_node_or_null("KeyDoors/" + id)
	if door == null or not door.has_method("open") or door.get("is_open"):
		return
	door.call("open")
	door_opened.emit(id)


## A player broke window pane `pane` (0.18.8): break it in this raid's map too, and tell the raid.
func break_window(pane: int) -> void:
	var blocks := raid.get_node_or_null("Level/Blocks")   # untyped: no BoxMap type here (see the top)
	if blocks == null or not blocks.has_method("break_pane") or not blocks.call("break_pane", pane, true):
		return
	window_broken.emit(pane)


## A player opened or shut door `id` (a node under Doors). Untyped: no Door type here (see the top).
func set_door(id: String, state: int) -> void:
	if id.is_empty() or id.contains("/") or id.contains(".."):
		return
	var door := raid.get_node_or_null("Doors/" + id)
	if door != null and door.has_method("set_state"):
		door.call("set_state", clampi(state, -1, 1))


## A player threw a grenade: this raid's copy flies and does the damage (to the AI, and to players through their
## proxies). Loaded by path: no Grenade type here (see the top).
func throw_grenade(from: Vector3, vel: Vector3) -> void:
	(load("res://scripts/grenade.gd") as GDScript).call("spawn", raid, from, vel, true)


## A bag of items (a dead player's body, things a player dropped) at `pos`. A body gets gear slots.
func drop_bag(pos: Vector3, title: String, data: Array, body := false) -> void:
	var contents := []
	for entry in data:
		var stack := GridInventory.data_stack(entry)
		if stack != null:
			contents.append(stack)
	if contents.is_empty():
		return
	# (onto the pile already there, unless someone has it open: 0.15.16)
	var pile := LootContainer.pile_near(raid, pos) if not body else null
	if pile != null and not locks.has(String(pile.name)):
		pile.add_to_pile(contents)
	else:
		LootContainer.spawn_bag(raid, pos, title, contents, 0.0, body)


## Every living scav/Raider/sniper: [id, kind (0 scav, 1 Raider, 2 sniper, 3 boss), net_capture(), gun (AILoadouts.NET_GUNS)].
func enemy_states() -> Array:
	var list := []
	for enemy in RaidScope.nodes(raid, &"enemies"):
		if enemy.has_method("net_capture"):
			list.append([enemy.get_instance_id(), enemy.net_kind, enemy.net_capture(), AILoadouts.NET_GUNS.find(enemy.carried_gun)])
	return list


## Remembers a player's state at server time `now`.
func record(peer: int, state: Array, now: float) -> void:
	if not history.has(peer):
		history[peer] = []
	var list: Array = history[peer]
	list.append([now, state])
	while list.size() > 2 and list[0][0] < now - HISTORY:
		list.pop_front()


## Remembers where every AI is at server time `now` (called when the states go out to the players).
func record_enemies(now: float) -> void:
	var seen := {}
	for enemy in RaidScope.nodes(raid, &"enemies"):
		if not enemy.has_method("net_capture"):
			continue
		var id := enemy.get_instance_id()
		seen[id] = true
		if not enemy_history.has(id):
			enemy_history[id] = []
		var list: Array = enemy_history[id]
		list.append([now, (enemy as Node3D).global_position, (enemy as Node3D).rotation.y])
		while list.size() > 2 and list[0][0] < now - HISTORY:
			list.pop_front()
	for id in enemy_history.keys():
		if not seen.has(id):
			enemy_history.erase(id)


## Where an AI was at server time `time`: [position, yaw], or [] if unknown.
func enemy_at(id: int, time: float) -> Array:
	var list: Array = enemy_history.get(id, [])
	if list.is_empty():
		return []
	if time <= list[0][0]:
		return [list[0][1], list[0][2]]
	for i in range(list.size() - 1, -1, -1):
		if list[i][0] <= time:
			if i == list.size() - 1:
				return [list[i][1], list[i][2]]
			var a: Array = list[i]
			var b: Array = list[i + 1]
			var t: float = (time - a[0]) / maxf(b[0] - a[0], 0.0001)
			return [(a[1] as Vector3).lerp(b[1], t), lerp_angle(a[2], b[2], t)]
	return [list[-1][1], list[-1][2]]


func forget(peer: int) -> void:
	history.erase(peer)
	close_containers(peer)
	if proxies.has(peer):
		proxies[peer].queue_free()
		proxies.erase(peer)


## Moves a player's proxy (makes one the first time).
func update_proxy(peer: int, state: Array) -> void:
	var body: Node = proxies.get(peer)
	if body == null:
		body = (load(PLAYER_SCENE) as PackedScene).instantiate()
		body.proxy = true
		body.name = "Proxy%d" % peer
		raid.add_child(body)
		body.global_position = state[0]
		body.health.damaged.connect(func(amount: int, from: Vector3) -> void:
			# The player's own game owns their health (and armor): pass the hit on, keep the proxy alive.
			body.health.current = body.health.max_health
			player_hit.emit(peer, amount, from, body.health.last_hit_head))
		body.bashed.connect(func(amount: int, from: Vector3, shove: float, block: float) -> void:
			player_bashed.emit(peer, amount, from, shove, block))
		proxies[peer] = body
	body.apply_net_state(state)


## A player fired from `from` (noise radius `noise`): scavs in this raid hear it, notice the threat, and the ones the
## shot passed close to turn toward it.
func shot_noise(from: Vector3, end: Vector3, noise: float, shooter_pos: Vector3, gunshot := true) -> void:
	for enemy in RaidScope.nodes(raid, &"enemies"):
		enemy.hear_noise(shooter_pos, noise, gunshot)
		enemy.notice_threat()
		var chest: Vector3 = enemy.global_position + Vector3(0, 1.2, 0)
		if Geometry3D.get_closest_point_to_segment(chest, from, end).distance_to(chest) <= enemy.near_miss_radius:
			enemy.notice_near_miss(shooter_pos)


## Where the segment from..to first enters an AI's box shapes (its CollisionShape3D children) with its feet at
## `feet`: {} for a miss, else {distance, headshot (the HeadShape)}.
static func _box_trace(body: Node3D, feet: Transform3D, from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	for child in body.get_children():
		var shape := child as CollisionShape3D
		if shape == null or shape.disabled or not shape.shape is BoxShape3D:
			continue
		var xf := feet * shape.transform
		var inv := xf.affine_inverse()
		var size := (shape.shape as BoxShape3D).size
		var hit: Variant = AABB(-size * 0.5, size).intersects_segment(inv * from, inv * to)
		if hit != null:
			var distance := from.distance_to(xf * (hit as Vector3))
			if best.is_empty() or distance < best["distance"]:
				best = {"distance": distance, "headshot": shape.name == &"HeadShape"}
	return best


## A player's state at server time `time` (between the two recorded states around it), or [] if unknown.
func state_at(peer: int, time: float) -> Array:
	var list: Array = history.get(peer, [])
	if list.is_empty():
		return []
	if time <= list[0][0]:
		return list[0][1]
	for i in range(list.size() - 1, -1, -1):
		if list[i][0] <= time:
			if i == list.size() - 1:
				return list[i][1]
			var a: Array = list[i]
			var b: Array = list[i + 1]
			var t: float = (time - a[0]) / maxf(b[0] - a[0], 0.0001)
			var state: Array = b[1].duplicate()
			state[0] = (a[1][0] as Vector3).lerp(b[1][0], t)
			state[1] = lerp_angle(a[1][1], b[1][1], t)
			state[3] = lerpf(a[1][3], b[1][3], t)
			return state
	return list[-1][1]


## Checks a shot fired by `shooter` from `from` along `dir` (up to `max_range`), against the map, the scavs, and
## every other player as they were at server time `view_time`. Returns {end} (where the shot stopped) plus
## {peer, headshot} for a player hit or {enemy, headshot} for a scav hit.
func trace_shot(shooter: int, from: Vector3, dir: Vector3, max_range: float, view_time: float, now: float) -> Dictionary:
	var to := from + dir.normalized() * max_range
	var time := clampf(view_time, now - MAX_REWIND, now)
	# The map (layer 1); players and AI are checked below, where they were on the shooter's screen (0.15.28: AI
	# were checked where they are now, so shots at a moving AI missed online).
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var wall := find_world_3d().direct_space_state.intersect_ray(query)
	var limit := from.distance_to(wall.position) if not wall.is_empty() else max_range
	var best := {}
	for peer in history:
		if peer == shooter:
			continue
		var state := state_at(peer, time)
		if state.is_empty():
			continue
		var hit := Hitbox.trace(state, from, to)
		if not hit.is_empty() and hit["distance"] < limit and (best.is_empty() or hit["distance"] < best["distance"]):
			best = {"peer": peer, "headshot": hit["headshot"], "distance": hit["distance"]}
	for enemy in RaidScope.nodes(raid, &"enemies"):
		if not enemy.has_method("net_capture"):
			continue
		var body := enemy as Node3D
		var then := enemy_at(enemy.get_instance_id(), time)
		var at: Vector3 = then[0] if not then.is_empty() else body.global_position
		var chest := at + Vector3(0, 1.0, 0)
		if Geometry3D.get_closest_point_to_segment(chest, from, to).distance_to(chest) > 3.0:
			continue
		var feet := Transform3D(Basis(Vector3.UP, then[1] if not then.is_empty() else body.rotation.y)
			.scaled(body.global_basis.get_scale()), at)
		var hit := _box_trace(body, feet, from, to)
		if not hit.is_empty() and hit["distance"] < limit and (best.is_empty() or hit["distance"] < best["distance"]):
			best = {"enemy": enemy, "headshot": hit["headshot"], "distance": hit["distance"]}
	var end: Vector3 = from + dir.normalized() * (best["distance"] if best.has("distance") else limit)
	best["end"] = end
	return best
