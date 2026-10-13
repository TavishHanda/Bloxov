class_name Interactor
extends Node
## Finds the loot container the player is looking at and handles hold-F-to-search, and hold-F-to-unlock on a key
## door (0.14.0) when its key is on you.
## Online (0.9.2) it also handles hold-F-to-revive: a downed teammate close by (reviving comes before looting).

signal opened(container: LootContainer)
## We held F long enough on a downed teammate (the server stands them back up).
signal revive_finished(peer: int)

@export var reach := 2.6
## How close (meters, to the middle of their body) you have to be to revive a downed teammate.
@export var revive_reach := 2.2

@onready var player: Player = owner

var target: LootContainer = null
## A shut key door we're looking at (instead of a container).
var door: KeyDoor = null
## An ordinary door we're looking at (0.17): F opens or shuts it.
var swing_door: Door = null
## The container or door `progress` belongs to (looking at another one starts over).
var _progress_target: Node = null
## 0..1 while holding F on an unsearched container.
var progress := 0.0
## Set by the HUD while a loot/inventory screen is open.
var blocked := false
## A downed teammate close enough to revive (null if none), and 0..1 while holding F on them.
var revive_target: RemotePlayer = null
var revive_progress := 0.0
## Who we told the server we're reviving (0 = nobody).
var _reviving_peer := 0
## After a revive, F has to be let go before the next one starts.
var _needs_release := false
## After a loot screen closes, F has to be let go before it can open one again
## (the F press that closed it would otherwise reopen it in the same frame).
var _open_needs_release := false


func is_reviving() -> bool:
	return _reviving_peer != 0


func _physics_process(delta: float) -> void:
	target = null
	door = null
	swing_door = null
	if blocked or not Input.is_action_pressed("interact"):
		_open_needs_release = blocked
	var able := not blocked and not player.out_of_fight() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	revive_target = find_revive_target() if able and not player.is_healing() else null
	update_revive(delta, able and Input.is_action_pressed("interact"))
	if not able or revive_target != null:
		progress = 0.0
		return
	var looked_at := _find_target()
	target = looked_at as LootContainer
	door = looked_at as KeyDoor
	if door != null and door.is_open:
		door = null
	if door != null:
		_update_door(delta)
		return
	swing_door = looked_at as Door
	if swing_door != null:
		progress = 0.0
		if Input.is_action_just_pressed("interact") and not _open_needs_release:
			swing_door.use(player.global_position)
		return
	if target == null or not Input.is_action_pressed("interact") or _open_needs_release:
		progress = 0.0
		return

	if target != _progress_target:
		_progress_target = target
		progress = 0.0
	var hold_time := target.interact_time()
	if hold_time <= 0.0:
		if Input.is_action_just_pressed("interact"):
			opened.emit(target)
		return
	progress += delta / hold_time
	if progress >= 1.0:
		progress = 0.0
		target.mark_searched()
		opened.emit(target)


## The closest downed teammate within revive reach, or null.
func find_revive_target() -> RemotePlayer:
	var best: RemotePlayer = null
	var best_dist := revive_reach
	for node in RaidScope.nodes(player, RemotePlayer.GROUP):
		var other := node as RemotePlayer
		if other == null or not other.can_be_revived():
			continue
		var middle := other.global_transform * Hitbox.DOWNED_BODY_CENTER
		var d := Vector2(middle.x - player.global_position.x, middle.z - player.global_position.z).length()
		if d <= best_dist:
			best = other
			best_dist = d
	return best


## Holding F on `revive_target` fills the revive bar (Network.REVIVE_TIME); letting go or moving off starts over.
## The server is told when we start and stop (their screen shows it) and when we finish.
func update_revive(delta: float, holding: bool) -> void:
	if not holding:
		_needs_release = false
	if revive_target == null or not holding or _needs_release:
		_stop_revive()
		return
	if revive_target.peer_id != _reviving_peer:
		_stop_revive()
		_reviving_peer = revive_target.peer_id
		Network.main.send_reviving(_reviving_peer, true)
	revive_progress += delta / Network.REVIVE_TIME
	if revive_progress >= 1.0:
		var peer := _reviving_peer
		_reviving_peer = 0
		revive_progress = 0.0
		_needs_release = true
		Network.main.send_revive(peer)
		revive_finished.emit(peer)


func _stop_revive() -> void:
	if _reviving_peer != 0:
		Network.main.send_reviving(_reviving_peer, false)
	_reviving_peer = 0
	revive_progress = 0.0


## Holding F on a shut key door with its key on you fills the bar, then unlocks it.
func _update_door(delta: float) -> void:
	if not Input.is_action_pressed("interact") or _open_needs_release or player.inventory.key_for(String(door.name)) == null:
		progress = 0.0
		return
	if door != _progress_target:
		_progress_target = door
		progress = 0.0
	progress += delta / door.unlock_time
	if progress >= 1.0:
		progress = 0.0
		door.unlock(player.inventory)


## The container, key door or door in reach under the crosshair, or null.
func _find_target() -> Node:
	var camera := player.camera
	var from := camera.global_position
	var to := from - camera.global_basis.z * reach
	# Mask: world (1) so walls block it + interactables (8; doors are on it too).
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 8, [player.get_rid()])
	var result := player.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	var hit: Object = result.collider
	return hit if hit is LootContainer or hit is KeyDoor or hit is Door else null
