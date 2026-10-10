class_name Raid
extends Node
## Runs one raid: places the player, opens a random set of extracts, counts down the timer,
## and decides how it ends: "extracted", "killed", or "mia" (out of time).

signal ended(result: String)

@export var player: Player
## Parent of Marker3D spawn points. The player starts at a random one.
@export var spawn_points: Node3D
@export var raid_time := 600.0
@export var open_extract_count := 2

## Meters between squadmates at the spawn.
const SQUAD_SPACING := 1.4
## Extracts closer than this to where you spawned are closed for you (owner, 0.10.3).
const CLOSED_NEAR_SPAWN := 120.0

var time_left: float
## "" while the raid is running.
var result := ""
var extract_used := ""
var loot_value := 0
## "Name xN" lines describing what the player had when the raid ended.
var loot_summary: PackedStringArray = []


func _ready() -> void:
	# Online, the server runs the clock (you may join a raid that's already going).
	time_left = Network.main.raid_time_left if Network.main.in_online_raid() else raid_time
	player.health.died.connect(_on_player_died)

	if spawn_points != null and spawn_points.get_child_count() > 0:
		var points := spawn_points.get_children()
		if Network.main.in_online_raid() and Network.main.raid_spawn.size() == 2:
			# Online the server picks: your squad together, other squads elsewhere (0.9.5).
			# (squadmates stand off to the side of the marker, where the hill can be higher: onto the ground)
			player.teleport_to(BoxMap.above_ground(player, spawn_position(points, Network.main.raid_spawn[0], Network.main.raid_spawn[1]), 0.0))
		else:
			player.teleport_to((points.pick_random() as Node3D).global_position)
		player.face_towards(Vector3.ZERO)

	var extracts := get_extracts()
	if Network.main.in_online_raid():
		# Same seed on every machine: your squad (same spawn) gets the same open extracts (the server hands it out).
		shuffle_seeded(extracts, Network.main.raid_seed)
	else:
		extracts.shuffle()
	var open := pick_open(extracts, player.global_position, open_extract_count)
	for zone in extracts:
		zone.set_open(open.has(zone))
		zone.extracted.connect(_on_extracted)


## The extracts open for someone who spawned at `spawn` (owner, 0.10.3): the first `count` of `shuffled` that
## aren't near the spawn. If too few are far enough (a small map), the farthest of the rest fill in.
static func pick_open(shuffled: Array[ExtractZone], spawn: Vector3, count: int) -> Array[ExtractZone]:
	var flat := func(zone: ExtractZone) -> float: return Vector2(zone.global_position.x - spawn.x, zone.global_position.z - spawn.z).length()
	var open: Array[ExtractZone] = []
	for zone in shuffled:
		if open.size() < count and flat.call(zone) >= CLOSED_NEAR_SPAWN:
			open.append(zone)
	if open.size() < count:
		var rest := shuffled.filter(func(zone: ExtractZone) -> bool: return not open.has(zone))
		rest.sort_custom(func(a: ExtractZone, b: ExtractZone) -> bool: return flat.call(a) > flat.call(b))
		for zone in rest.slice(0, count - open.size()):
			open.append(zone)
	return open


## Spawn point `slot` (Matchmaker.spawn_slots; the same on every machine: points sorted by name), and `place`
## steps to the side of it (squadmates stand next to each other). More squads than points share one, further apart.
static func spawn_position(points: Array, slot: int, place: int) -> Vector3:
	var sorted := points.duplicate()
	sorted.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	var point := sorted[slot % sorted.size()] as Node3D
	var step := place + (slot / sorted.size()) * 3
	# (toward the middle of the map, away from its edge walls)
	var side := -1.0 if point.global_position.x > 0.0 else 1.0
	return point.global_position + Vector3(SQUAD_SPACING * step * side, 0, 0)


## Shuffles the extracts the same way on every machine that uses the same seed.
static func shuffle_seeded(extracts: Array[ExtractZone], seed_value: int) -> void:
	extracts.sort_custom(func(a: ExtractZone, b: ExtractZone) -> bool: return a.name < b.name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(extracts.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := extracts[i]
		extracts[i] = extracts[j]
		extracts[j] = swap


func get_extracts() -> Array[ExtractZone]:
	var list: Array[ExtractZone] = []
	for node in RaidScope.nodes(self, &"extracts"):
		list.append(node as ExtractZone)
	return list


func _process(delta: float) -> void:
	# (the clock keeps running after you're out: a spectator still sees the raid's time)
	time_left = maxf(time_left - delta, 0.0)
	if result != "":
		return
	if time_left <= 0.0:
		time_left = 0.0
		result = "mia"
		player.health.kill()
		_finish()


func _on_player_died() -> void:
	if result == "":
		result = "killed"
		_finish()


func _on_extracted(zone: ExtractZone) -> void:
	if result != "":
		return
	result = "extracted"
	extract_used = zone.extract_name
	player.extract()
	_finish()


func _finish() -> void:
	loot_summary.clear()
	for stack in player.inventory.all_stacks():
		loot_summary.append(ItemDB.label(stack.id, stack.count))
	loot_value = player.inventory.total_value()
	_save_to_profile()
	ended.emit(result)


## Extracted: you keep everything you're carrying. Killed / MIA: only the secure pocket survives.
func _save_to_profile() -> void:
	var carried := Profile.capture_inventory(player.inventory)
	Profile.stats["raids"] += 1
	if result == "extracted":
		Profile.loadout = carried
		Profile.stats["extracts"] += 1
	else:
		Profile.loadout = Profile.death_loadout(carried)
		Profile.stats["deaths"] += 1
	Profile.save_profile()
