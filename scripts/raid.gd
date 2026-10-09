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
		var spawn := spawn_points.get_children().pick_random() as Node3D
		player.teleport_to(spawn.global_position)
		player.face_towards(Vector3.ZERO)

	var extracts := get_extracts()
	if Network.main.in_online_raid():
		# Everyone in an online raid gets the same open extracts (the server hands out the seed).
		shuffle_seeded(extracts, Network.main.raid_seed)
	else:
		extracts.shuffle()
	for i in extracts.size():
		extracts[i].set_open(i < open_extract_count)
		extracts[i].extracted.connect(_on_extracted)


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
	for node in get_tree().get_nodes_in_group("extracts"):
		list.append(node as ExtractZone)
	return list


func _process(delta: float) -> void:
	if result != "":
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		result = "mia"
		player.health.take_damage(999999)
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
