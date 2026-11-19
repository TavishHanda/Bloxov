class_name RaidPrep
extends RefCounted
## Gets the next raid ready ahead of time (0.36.35, owner: START RAID sat on a frozen picture for a few seconds on
## Frontlines). In a browser the game has one thread, so loading the raid stops it drawing. The big pieces (the map
## scene, the raid scene, and the map's collision shape, BoxMap.prebuild) are done in steps, a frame apart, so START
## RAID's loading screen counts up instead of sitting still; then making the raid itself is quick. When a raid ends,
## everything it loaded is kept for the next one on the same map (prepare_now), so later raids skip the loading.
## Held until the raid has started (RaidMap releases them). What the raid ends up with is the same either way.
## Players' games without threads (the web build); desktops warm the map on a thread instead (hideout `_warm_raid`).

const RAID_SCENE := "res://scenes/main.tscn"

## The map these are for ("" = nothing ready).
static var _path := ""
static var _map: PackedScene
static var _raid: PackedScene
static var _shapes := []
static var _shaped := false
## A prepare() is running.
static var _busy := false


## Tests turn it on where it would be off (headless, threads).
static var always := false


## Whether this game gets raids ready this way.
static func wanted() -> bool:
	return always or (not OS.has_feature("threads") and DisplayServer.get_name() != "headless")


## True when everything for the map at `path` is ready.
static func ready_for(path: String) -> bool:
	return path != "" and _path == path and _shaped


## Gets the map at `path` ready, a step per frame: `progress` gets 0..1 after each step. Returns at once if it's
## ready already. Anything ready for another map is let go first. Safe to call while another call is still going
## (START RAID during the hideout's own): it waits for that one, then carries on from there.
static func prepare(tree: SceneTree, path: String, progress := Callable()) -> void:
	while _busy:
		await tree.process_frame
	if path == "" or ready_for(path):
		return
	_busy = true
	if _path != path:
		release()
		_path = path
	if _map == null:
		_map = load(path) as PackedScene
		await _step(tree, progress, 0.4)
	if _raid == null:
		_raid = load(RAID_SCENE) as PackedScene
		await _step(tree, progress, 0.6)
	if not _shaped:
		_shapes = BoxMap.prebuild(_map) if _map != null else []
		_shaped = true
		await _step(tree, progress, 1.0)
	_busy = false


## The same, all at once (each step is quick when the raid that just ended still has it all loaded). Called as a
## raid ends (RaidMap), so the next raid on this map finds it ready instead of loading it all again.
static func prepare_now(path: String) -> void:
	if not wanted() or path == "" or _busy or ready_for(path):
		return
	release()
	_path = path
	_map = load(path) as PackedScene
	_raid = load(RAID_SCENE) as PackedScene
	_shapes = BoxMap.prebuild(_map) if _map != null else []
	_shaped = true


static func _step(tree: SceneTree, progress: Callable, done: float) -> void:
	if progress.is_valid():
		progress.call(done)
	await tree.process_frame


## The raid scene, loaded (it's cached when prepared).
static func raid_scene() -> PackedScene:
	return _raid if _raid != null else load(RAID_SCENE) as PackedScene


## Lets go of everything (the raid has what it needs by now).
static func release() -> void:
	_path = ""
	_map = null
	_raid = null
	BoxMap.let_go(_shapes)
	_shapes = []
	_shaped = false
