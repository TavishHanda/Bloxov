class_name Hearing
extends RefCounted
## Hearing where things are (Sound update 0.20.1, the PvP part): far-off shots get a rolling boom on top, sounds
## behind a wall come through muffled (`Effects.sound_at`), there's a light echo while you're indoors, and bullets
## that pass close snap past your head. Today's sounds play as before; these only add to them.

const DISTANT_SHOT := preload("res://audio/distant_shot.wav")
const SNAPS: Array[AudioStream] = [preload("res://audio/snap1.wav"), preload("res://audio/snap2.wav")]
## Beyond this a shot also rolls in as a far boom (full from DISTANT_FULL m).
const DISTANT_FROM := 45.0
const DISTANT_FULL := 90.0
## A shot passing this close to your head snaps past (not from someone right next to you: you hear their gun).
const SNAP_RADIUS := 3.0
const SNAP_MIN_RANGE := 10.0
## Behind a wall: cut off the highs above this (Hz) and a little quieter.
const MUFFLED_CUTOFF := 900.0
const MUFFLED_DB := -5.0
## The bus every game sound goes through, with the indoor echo on it (off outdoors).
const WORLD_BUS := &"World"
const INDOOR_CHECK := 0.3
## Indoors = a roof within this many meters above your head.
const ROOF_REACH := 12.0

static var _indoor_check_left := 0.0
static var indoors := false


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


## True if a wall stands between the listener and `pos` (sounds from there come through muffled).
static func blocked(camera: Camera3D, pos: Vector3) -> bool:
	var from := camera.global_position
	var to := pos.move_toward(from, 0.6)   # (not the wall the sound's own maker leans on)
	if from.distance_squared_to(to) < 1.0:
		return false
	return not camera.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, 1)).is_empty()


## Someone else's gunshot at `from` heading to `end`: the far boom if it's far, the snap if it passes close.
static func gunshot(world: Node, from: Vector3, end: Vector3, volume_db: float) -> void:
	var camera := listener(world)
	if camera == null:
		return
	var ear := camera.global_position
	var far := ear.distance_to(from)
	if far > DISTANT_FROM:
		var fade := clampf((far - DISTANT_FROM) / (DISTANT_FULL - DISTANT_FROM), 0.0, 1.0)
		Effects.sound_at(world, DISTANT_SHOT, from, volume_db - 4.0 + linear_to_db(maxf(fade, 0.01)), 0.08, 1.0, 45.0)
	if far < SNAP_MIN_RANGE:
		return
	var closest := Geometry3D.get_closest_point_to_segment(ear, from, end)
	if closest.distance_to(ear) < SNAP_RADIUS and closest.distance_to(from) > SNAP_MIN_RANGE:
		Effects.sound_at(world, SNAPS.pick_random(), closest, -4.0, 0.1, 1.0, 4.0, 30.0)
