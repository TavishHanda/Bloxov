class_name Hearing
extends RefCounted
## Hearing where things are (Sound update 0.20.1, the PvP part): far-off shots get a rolling boom on top, sounds
## behind a wall come through muffled (`Effects.sound_at`), there's a light echo while you're indoors, and bullets
## that pass close snap past your head. Today's sounds play as before; these only add to them.
##
## Sound 2.0 (0.30.1): `block_of` says WHAT is in the way (a wall, a floor, a shut door, a whole pane, or an opening
## sound comes round), and whether the shooter is behind your ear, so `GunSounds.shot_for` can pick a baked variant.
## Gunshots are not muffled again at runtime: the muffle lives in the WAVs so desktop and web hear the same thing.

const DISTANT_SHOT := preload("res://audio/distant_shot.wav")
const SNAPS: Array[AudioStream] = [preload("res://audio/snap1.wav"), preload("res://audio/snap2.wav")]
## Beyond this a shot also rolls in as a far boom (full from DISTANT_FULL m).
const DISTANT_FROM := 45.0
const DISTANT_FULL := 90.0
## A shot passing this close to your head snaps past (not from someone right next to you: you hear their gun).
const SNAP_RADIUS := 3.0
const SNAP_MIN_RANGE := 10.0
const SNAP_DB := -13.0
## The snap plays this far from your head toward the shooter.
const SNAP_SIDE := 2.0
## A shot that came at you: this share of the loudness it lost to distance comes back, at most AT_YOU_MAX_DB.
const AT_YOU_GIVE_BACK := 0.5
const AT_YOU_MAX_DB := 10.0
## Behind a wall: cut off the highs above this (Hz) and a little quieter. Footsteps and impacts still use this at
## runtime; gunshots use their baked variant instead (0.30.1).
const MUFFLED_CUTOFF := 900.0
const MUFFLED_DB := -5.0
## 0.30.1: gunshots are muffled by their variant file, not by `Effects.sound_at` (the web build skips bus effects, so
## desktop and web must match). Flip this to true to hear the old runtime filter on top for an A/B.
const RUNTIME_MUFFLE := false
## What sound has to get through (0.30.1). World (1), doors (Door.LAYER = 16) and whole window panes
## (BoxMap.WINDOW_LAYER = 256): a shut door and a whole pane used to be acoustically invisible.
const BLOCK_MASK := 1 | 16 | 256
const DOOR_LAYER := 16
const WINDOW_LAYER := 256
## What is between your ear and a sound (0.30.1). OPENING: the direct line is blocked but a ray in the fan is clear,
## so the sound comes round a doorway or a broken window instead of through the wall.
enum Block { NONE, OPENING, WALL, FLOOR, DOOR, GLASS }
## The fan around the direct ray: +/-10 degrees sideways, +/-8 up/down. Any clear ray means an opening.
const FAN_SIDE := PI / 18.0
const FAN_UP := PI * 4.0 / 90.0
## The bus every game sound goes through, with the indoor echo on it (off outdoors).
const WORLD_BUS := &"World"
const INDOOR_CHECK := 0.3
## Indoors = a roof within this many meters above your head.
const ROOF_REACH := 12.0
## A fight ducks the ambience (0.30.3): a shot you can hear within FIGHT_RANGE m keeps it down for FIGHT_TIME s.
## Someone else's footsteps within STEP_RANGE m add a shorter dip on top.
const FIGHT_RANGE := 50.0
const FIGHT_TIME := 4.0
const STEP_RANGE := 8.0
const STEP_TIME := 0.4

static var _indoor_check_left := 0.0
static var indoors := false
static var fight_left := 0.0
static var step_left := 0.0


## The game's sound bus: World -> Master, with a small-room echo that's on only indoors. The buses are set up in
## `default_bus_layout.tres`, loaded when the game starts (0.20.8): adding buses while the game runs silences every
## sound on the web (Godot 4.5's web audio drops Master when a bus is added at the end).
static func world_bus() -> StringName:
	return bus(WORLD_BUS)


## Sound bus `name` (World, Voices, Ambience or UI, from default_bus_layout.tres); Master if it's missing.
static func bus(name: StringName) -> StringName:
	return name if AudioServer.get_bus_index(name) != -1 else &"Master"


## Where you hear from: the camera in use (null = nobody's listening, e.g. the game server).
static func listener(node: Node) -> Camera3D:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_viewport().get_camera_3d()


## Called every frame by the player: turns the indoor echo on under a roof, off outside.
static func listen(node: Node3D, delta: float) -> void:
	tick(delta)
	_indoor_check_left -= delta
	if _indoor_check_left > 0.0:
		return
	_indoor_check_left = INDOOR_CHECK
	var camera := listener(node)
	if camera == null:
		return
	var from := camera.global_position
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * ROOF_REACH, 1))
	set_indoors(not hit.is_empty())


static func set_indoors(inside: bool) -> void:
	indoors = inside
	var index := AudioServer.get_bus_index(WORLD_BUS)
	if index != -1 and AudioServer.get_bus_effect_count(index) > 0:
		AudioServer.set_bus_effect_enabled(index, 0, inside)


## A shot at `pos` you can hear (0.30.3): the ambience ducks for FIGHT_TIME s. No listener (the game server): nothing.
static func heard_shot(world: Node, pos: Vector3) -> void:
	var camera := listener(world)
	if camera != null and camera.global_position.distance_to(pos) <= FIGHT_RANGE:
		fight_left = FIGHT_TIME


## Someone else's footsteps at `pos` (0.30.3): a short dip when they are close, so they stand out over the ambience.
static func heard_step(world: Node, pos: Vector3) -> void:
	var camera := listener(world)
	if camera != null and camera.global_position.distance_to(pos) <= STEP_RANGE:
		step_left = STEP_TIME


## Runs the duck timers (real seconds, so the menu pauses them too).
static func tick(delta: float) -> void:
	fight_left = maxf(0.0, fight_left - delta)
	step_left = maxf(0.0, step_left - delta)


## Forgets any duck in progress (leaving a raid).
static func reset_duck() -> void:
	fight_left = 0.0
	step_left = 0.0


## What stands between the listener and `pos` (0.30.1): a wall, a floor/ceiling, a shut door, a whole pane, or an
## opening the sound comes round. The direct ray is one cast; the fan is four short ones, only when it is blocked.
static func block_of(camera: Camera3D, pos: Vector3) -> int:
	if camera == null:
		return Block.NONE
	var from := camera.global_position
	var to := pos.move_toward(from, 0.6)   # (not the wall the sound's own maker leans on)
	if from.distance_squared_to(to) < 1.0:
		return Block.NONE
	var space := camera.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, BLOCK_MASK))
	if hit.is_empty():
		return Block.NONE
	if _fan_is_clear(space, from, pos):
		return Block.OPENING
	var normal: Vector3 = hit["normal"]
	if absf(normal.y) >= 0.7:
		return Block.FLOOR
	var collider := hit["collider"] as CollisionObject3D
	if collider != null and (collider.collision_layer & DOOR_LAYER) != 0:
		return Block.DOOR
	if collider != null and (collider.collision_layer & WINDOW_LAYER) != 0:
		return Block.GLASS
	return Block.WALL


## Is one of the four rays around the direct line clear? (The direct line is blocked: a doorway or a broken window in
## the fan means the sound comes round it, not through the wall.)
static func _fan_is_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var aim := to - from
	var length := aim.length()
	if length < 0.01:
		return false
	var forward := aim / length
	# Right and up across the ray (a fallback when it is straight up or down, where UP gives no side).
	var up_hint := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := forward.cross(up_hint).normalized()
	var up := right.cross(forward).normalized()
	var rays: Array[Vector3] = [
		forward.rotated(up, FAN_SIDE), forward.rotated(up, -FAN_SIDE),
		forward.rotated(right, FAN_UP), forward.rotated(right, -FAN_UP)]
	for dir in rays:
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * length, BLOCK_MASK)).is_empty():
			return true
	return false


## True if a wall stands between the listener and `pos` (sounds from there come through muffled). An opening is not
## blocked: sound comes round it, so footsteps and impacts through a doorway are not muffled again.
static func blocked(camera: Camera3D, pos: Vector3) -> bool:
	var block := block_of(camera, pos)
	return block != Block.NONE and block != Block.OPENING


## True if `pos` is behind the listener's ear (0.30.1): a shot from behind is a little duller. Only used up close
## outdoors; indoors the room tail already says where it came from.
static func behind(camera: Camera3D, pos: Vector3) -> bool:
	if camera == null:
		return false
	var to := pos - camera.global_position
	if to.length_squared() < 0.01:
		return false
	return to.normalized().dot(-camera.global_transform.basis.z) < -0.25


## Someone else's gunshot at `from` heading to `end`: the far boom if it's far, the snap if it passes close.
static func gunshot(world: Node, from: Vector3, end: Vector3, volume_db: float) -> void:
	var camera := listener(world)
	if camera == null:
		return
	var ear := camera.global_position
	var far := ear.distance_to(from)
	if far > DISTANT_FROM:
		var fade := clampf((far - DISTANT_FROM) / (DISTANT_FULL - DISTANT_FROM), 0.0, 1.0)
		Effects.sound_at(world, DISTANT_SHOT, from, volume_db - 4.0 + linear_to_db(maxf(fade, 0.01)),
			0.08, 1.0, 45.0, 0.0, &"", RUNTIME_MUFFLE)
	if far < SNAP_MIN_RANGE:
		return
	var closest := Geometry3D.get_closest_point_to_segment(ear, from, end)
	if closest.distance_to(ear) < SNAP_RADIUS and closest.distance_to(from) > SNAP_MIN_RANGE:
		# On the shooter's side of your head, and softer (0.22.8): the snap used to come from beside you and drown
		# out where the shot came from.
		Effects.sound_at(world, SNAPS.pick_random(), ear + ear.direction_to(from) * SNAP_SIDE, SNAP_DB, 0.1, 1.0, 4.0, 30.0)


## Extra loudness (dB) for someone else's shot at `from` that came at you (passed within SNAP_RADIUS of your head
## or hit you, ending at `end`), 0.22.8, owner: "hear more where u got shot from and less where the shot lands".
## It gives back part of what the distance took off (a shot's sound is at full within `unit_size` m), so the gun
## that's shooting at you stands out over the bullets landing around you.
static func at_you_db(world: Node, from: Vector3, end: Vector3, unit_size: float) -> float:
	var camera := listener(world)
	if camera == null:
		return 0.0
	var ear := camera.global_position
	if Geometry3D.get_closest_point_to_segment(ear, from, end).distance_to(ear) >= SNAP_RADIUS:
		return 0.0
	return clampf(linear_to_db(ear.distance_to(from) / maxf(unit_size, 0.1)) * AT_YOU_GIVE_BACK, 0.0, AT_YOU_MAX_DB)

