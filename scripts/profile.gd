class_name Profile
extends RefCounted
## The persistent player profile: money, stash, the loadout you take into raids, and stats.
## Saved as JSON in user://profile.json (browser storage on web).
## Static so both the hideout and the raid scene see the same data.

const PATH := "user://profile.json"
const VERSION := 1
const STASH_SIZE := Vector2i(8, 30)
const START_MONEY := 3000

static var money := START_MONEY
static var stash: GridInventory = GridInventory.new("Stash", STASH_SIZE.x, STASH_SIZE.y)
## Serialized Inventory (see capture_inventory). Empty = use the starting kit.
static var loadout: Dictionary = {}
static var stats := {"raids": 0, "extracts": 0, "deaths": 0, "earned": 0}
static var _loaded := false


static func load_profile() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		reset()
		return
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		reset()
		return
	money = int(data.get("money", START_MONEY))
	var size: Array = data.get("stash_size", [STASH_SIZE.x, STASH_SIZE.y])
	stash = GridInventory.new("Stash", int(size[0]), int(size[1]))
	_read_grid(data.get("stash", []), stash)
	loadout = data.get("loadout", {})
	var saved_stats: Dictionary = data.get("stats", {})
	for key in stats:
		stats[key] = int(saved_stats.get(key, 0))


## A brand new profile: starting money, empty stash, starting kit loadout.
static func reset() -> void:
	_loaded = true
	money = START_MONEY
	stash = GridInventory.new("Stash", STASH_SIZE.x, STASH_SIZE.y)
	loadout = starting_loadout()
	stats = {"raids": 0, "extracts": 0, "deaths": 0, "earned": 0}


static func save_profile() -> void:
	var data := {
		"version": VERSION,
		"money": money,
		"stash_size": [stash.width, stash.height],
		"stash": _write_grid(stash),
		"loadout": loadout,
		"stats": stats,
	}
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))


## The starter kit: AK (loaded), medium backpack, 60 rifle rounds, a bandage on hotbar key 3.
static func starting_loadout() -> Dictionary:
	return {
		"equipment": {
			"primary": {"id": "ak", "count": 1, "loaded": 30},
			"backpack": {"id": "backpack_medium", "count": 1},
		},
		"pockets": [{"id": "rifle_ammo", "count": 60, "x": 0, "y": 0}, {"id": "bandage", "count": 1, "x": 1, "y": 0}],
		"backpack": [],
		"secure": [],
		"hotbar": ["bandage", "", "", ""],
	}


## What's left of a loadout after dying: only the secure pocket (and hotbar bindings).
static func death_loadout(data: Dictionary) -> Dictionary:
	return {"equipment": {}, "pockets": [], "backpack": [], "secure": data.get("secure", []), "hotbar": data.get("hotbar", ["", "", "", ""])}


# --- Inventory <-> data ------------------------------------------------------------

static func capture_inventory(inventory: Inventory) -> Dictionary:
	var equipment := {}
	for slot in Inventory.SLOTS:
		var stack := inventory.equipped(slot)
		if stack != null:
			equipment[slot] = _write_stack(stack)
	return {
		"equipment": equipment,
		"pockets": _write_grid(inventory.pockets),
		"backpack": _write_grid(inventory.backpack) if inventory.backpack != null else [],
		"secure": _write_grid(inventory.secure),
		"hotbar": inventory.hotbar.duplicate(),
	}


## Replaces everything in `inventory` with the saved loadout.
static func apply_inventory(inventory: Inventory, data: Dictionary) -> void:
	for slot in Inventory.SLOTS:
		if inventory.equipped(slot) != null:
			if slot == "backpack" and inventory.backpack != null:
				inventory.backpack.clear()
			inventory.unequip(slot)
	inventory.clear()
	var equipment: Dictionary = data.get("equipment", {})
	# Backpack first, so its grid exists before its contents are read.
	for slot in ["backpack", "primary", "secondary", "armor"]:
		if equipment.has(slot):
			inventory.equip(slot, _read_stack(equipment[slot]))
	_read_grid(data.get("pockets", []), inventory.pockets)
	if inventory.backpack != null:
		_read_grid(data.get("backpack", []), inventory.backpack)
	_read_grid(data.get("secure", []), inventory.secure)
	var hotbar: Array = data.get("hotbar", [])
	for i in mini(hotbar.size(), Inventory.HOTBAR_SIZE):
		inventory.hotbar[i] = str(hotbar[i])
	inventory.changed.emit()


static func _write_stack(stack: ItemStack) -> Dictionary:
	var entry := {"id": stack.id, "count": stack.count, "x": stack.x, "y": stack.y}
	if stack.rotated:
		entry["r"] = true
	if stack.loaded > 0:
		entry["loaded"] = stack.loaded
	return entry


static func _read_stack(entry: Dictionary) -> ItemStack:
	var stack := ItemStack.new(str(entry["id"]), int(entry.get("count", 1)), int(entry.get("x", 0)), int(entry.get("y", 0)), bool(entry.get("r", false)))
	stack.loaded = int(entry.get("loaded", 0))
	return stack


static func _write_grid(grid: GridInventory) -> Array:
	var list := []
	for stack in grid.stacks:
		list.append(_write_stack(stack))
	return list


## Puts saved stacks back at their saved spots. Anything that no longer fits (or no longer exists) is skipped
## or added wherever there's room, so a changed item size can't corrupt a save.
static func _read_grid(entries: Array, grid: GridInventory) -> void:
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY or not ItemDB.ITEMS.has(str(entry.get("id", ""))):
			continue
		var stack := _read_stack(entry)
		if grid.fits(stack.id, stack.x, stack.y, stack.rotated):
			grid.place(stack)
		else:
			grid.add(stack.id, stack.count)
