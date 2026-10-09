class_name RaidWorld
extends SubViewport
## One online raid's copy of the map on the server, in its own physics world (so several raids never touch),
## plus a short history of where every player in it was. The server checks shots here: walls block bullets,
## and a shot is tested against where the targets were on the shooter's screen when they fired (lag
## compensation), so what looked like a hit counts.
## Loaded at runtime by path (not preloaded): the server autoload mustn't depend on the player scripts.

const RAID_SCENE := "res://scenes/main.tscn"
## The map pieces the server needs (solid things). Everything else in the raid scene is for players' screens.
const KEEP := ["Level", "Loot"]
## Seconds of position history kept per player, and the furthest back a shot is checked.
const HISTORY := 1.0
const MAX_REWIND := 0.5

## peer -> Array of [server seconds, state], oldest first.
var history := {}


func _init() -> void:
	own_world_3d = true
	# Nothing is drawn: it only exists for its physics.
	disable_3d = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	size = Vector2i(2, 2)


func _ready() -> void:
	var raid := (load(RAID_SCENE) as PackedScene).instantiate()
	for child in raid.get_children():
		if not KEEP.has(String(child.name)):
			raid.remove_child(child)
			child.free()
	add_child(raid)


## Remembers a player's state at server time `now`.
func record(peer: int, state: Array, now: float) -> void:
	if not history.has(peer):
		history[peer] = []
	var list: Array = history[peer]
	list.append([now, state])
	while list.size() > 2 and list[0][0] < now - HISTORY:
		list.pop_front()


func forget(peer: int) -> void:
	history.erase(peer)


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


## Checks a shot fired by `shooter` from `from` along `dir` (up to `max_range`), against the map and every other
## player as they were at server time `view_time`. Returns {} for a miss, else {peer, headshot}.
func trace_shot(shooter: int, from: Vector3, dir: Vector3, max_range: float, view_time: float, now: float) -> Dictionary:
	var to := from + dir.normalized() * max_range
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var wall := find_world_3d().direct_space_state.intersect_ray(query)
	var limit := from.distance_to(wall.position) if not wall.is_empty() else max_range
	var time := clampf(view_time, now - MAX_REWIND, now)
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
	return best
