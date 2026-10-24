class_name Profile
extends RefCounted
## The persistent player profile: money, stash, the loadout you take into raids, and stats.
## Saved as JSON in user://profile.json (browser storage on web). On web it's also copied to localStorage, see
## save_profile.
## Static so both the hideout and the raid scene see the same data.

const PATH := "user://profile.json"
const VERSION := 1
## A new stash's size (0.16.0, Economy update: it was 8 x 30; older saves keep the size they had).
const STASH_SIZE := Vector2i(8, 20)
## Stash upgrades (0.16.0, owner: a real stash size, bigger ones bought with money): rows at each level, and what
## each upgrade costs. Level 1 is the new stash.
const STASH_ROWS: Array[int] = [20, 30, 40, 50]
const STASH_UPGRADE_COST: Array[int] = [0, 50000, 120000, 250000]
## Only a brand new profile gets it: a save always keeps its own money.
## (0.16.1: x5 with the price pass; was $3,000. 0.17.5, owner: $50,000, was $15,000.)
const START_MONEY := 50000
const DEFAULT_STATS := {"raids": 0, "extracts": 0, "deaths": 0, "earned": 0}
## Where an unreadable save is copied before the profile is reset, so it isn't silently lost.
const BAD_PATH := "user://profile.bad.json"
## The localStorage key of the web copy of the save.
const WEB_KEY := "bloxov_profile"

static var money := START_MONEY
static var stash: GridInventory = GridInventory.new("Stash", STASH_SIZE.x, STASH_SIZE.y)
## Serialized Inventory (see capture_inventory). Empty = use the starting kit.
static var loadout: Dictionary = {}
static var stats: Dictionary = DEFAULT_STATS.duplicate()
## Money spent with each trader (Traders.LIST id -> dollars); it sets their level.
static var trader_spent: Dictionary = {}
## The raid count (stats "raids") when you last took the free kit; one free kit per raid (0.16.4, owner: taking it
## and selling it over and over was infinite money). -1 = never taken.
static var free_kit_raid := -1
## Trader quests (0.16.13, see Quests): finished quest ids, and progress (quest id -> count) on the rest.
static var quests_done: Array[String] = []
static var quest_progress: Dictionary = {}
## Each trader's level (Traders.LIST id -> level; missing = 1). It goes up when you press LEVEL UP at the trader once
## the level's quests are done and its money spent (0.17.1, owner: a level-up button).
static var trader_levels: Dictionary = {}
static var _loaded := false


## Every field is type-checked and falls back to its default, so a malformed save can't throw halfway
## and leave a half-loaded profile.
static func load_profile() -> void:
	if _loaded:
		return
	_loaded = true
	TabLock.start()
	var text := newer_save(_read_file(), _web_read())
	if text == "":
		reset()
		return
	var data = JSON.parse_string(text)
	if not data is Dictionary or not _is_number(data.get("version")) or int(data["version"]) != VERSION:
		_backup_bad_save(text)
		reset()
		return
	money = int(data["money"]) if _is_number(data.get("money")) else START_MONEY
	var size = data.get("stash_size")
	if size is Array and size.size() == 2 and _is_number(size[0]) and _is_number(size[1]):
		stash = GridInventory.new("Stash", int(size[0]), int(size[1]))
	else:
		stash = GridInventory.new("Stash", STASH_SIZE.x, STASH_SIZE.y)
	_read_grid(_array(data.get("stash")), stash)
	var saved_loadout = data.get("loadout")
	loadout = saved_loadout if saved_loadout is Dictionary else starting_loadout()
	stats = DEFAULT_STATS.duplicate()
	var saved_stats = data.get("stats")
	if saved_stats is Dictionary:
		for key in stats:
			if _is_number(saved_stats.get(key)):
				stats[key] = int(saved_stats[key])
	free_kit_raid = int(data["free_kit_raid"]) if _is_number(data.get("free_kit_raid")) else -1
	trader_spent = {}
	var saved_spent = data.get("trader_spent")
	if saved_spent is Dictionary:
		for key in saved_spent:
			if key is String and _is_number(saved_spent[key]):
				trader_spent[key] = int(saved_spent[key])
	quests_done = []
	for id in _array(data.get("quests_done")):
		if id is String and Quests.LIST.has(id) and not quests_done.has(id):
			quests_done.append(id)
	quest_progress = {}
	var saved_progress = data.get("quest_progress")
	if saved_progress is Dictionary:
		for key in saved_progress:
			if key is String and Quests.LIST.has(key) and _is_number(saved_progress[key]):
				quest_progress[key] = clampi(int(saved_progress[key]), 0, int(Quests.LIST[key]["count"]))
	trader_levels = {}
	var saved_levels = data.get("trader_levels")
	for trader: String in Traders.LIST:
		if saved_levels is Dictionary:
			if _is_number(saved_levels.get(trader)):
				trader_levels[trader] = clampi(int(saved_levels[trader]), 1, trader_level_reached(trader))
		else:
			# A save from before the button: keep the levels it had reached.
			trader_levels[trader] = trader_level_reached(trader)


## A trader's level: what you've levelled them up to.
static func trader_level(trader: String) -> int:
	return clampi(int(trader_levels.get(trader, 1)), 1, Traders.max_level(trader))


## The highest level a trader's quests done and money spent allow (Traders.level).
static func trader_level_reached(trader: String) -> int:
	return Traders.level(trader, int(trader_spent.get(trader, 0)), quests_done)


## The next level's quests are done and its money spent: LEVEL UP can be pressed.
static func can_level_up(trader: String) -> bool:
	return trader_level_reached(trader) > trader_level(trader)


## Levels a trader up by one (LEVEL UP). False if they can't yet.
static func level_up(trader: String) -> bool:
	if not can_level_up(trader):
		return false
	trader_levels[trader] = trader_level(trader) + 1
	return true


## The stash's upgrade level (1-based): the biggest STASH_ROWS size it has reached.
static func stash_level() -> int:
	var reached := 1
	for i in STASH_ROWS.size():
		if stash.height >= STASH_ROWS[i]:
			reached = i + 1
	return reached


## What the next stash upgrade costs, or 0 when it's as big as it gets.
static func next_stash_cost() -> int:
	var lv := stash_level()
	return STASH_UPGRADE_COST[lv] if lv < STASH_ROWS.size() else 0


static func _read_file() -> String:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## Of two saves (JSON text, "" = none), the one written last (by its saved_at stamp; the file wins a tie and
## when neither has a stamp).
static func newer_save(file_text: String, web_text: String) -> String:
	if web_text == "":
		return file_text
	if file_text == "":
		return web_text
	var stamp := func(text: String) -> float:
		var data = JSON.parse_string(text)
		return float(data["saved_at"]) if data is Dictionary and _is_number(data.get("saved_at")) else -1.0
	return web_text if stamp.call(web_text) > stamp.call(file_text) else file_text


static func _backup_bad_save(text: String) -> void:
	var file := FileAccess.open(BAD_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)


## JSON numbers come back as floats; ints are accepted too for data built in code.
static func _is_number(value) -> bool:
	return value is float or value is int


static func _array(value) -> Array:
	return value if value is Array else []


## A brand new profile: starting money, empty stash, starting kit loadout.
static func reset() -> void:
	_loaded = true
	money = START_MONEY
	stash = GridInventory.new("Stash", STASH_SIZE.x, STASH_SIZE.y)
	loadout = starting_loadout()
	stats = DEFAULT_STATS.duplicate()
	trader_spent = {}
	free_kit_raid = -1
	quests_done = []
	quest_progress = {}
	trader_levels = {}


static func save_profile() -> void:
	# A second browser tab never saves (TabLock): its copy of the profile is out of date.
	if not TabLock.owns():
		return
	var data := {
		"version": VERSION,
		"money": money,
		"stash_size": [stash.width, stash.height],
		"stash": _write_grid(stash),
		"loadout": loadout,
		"stats": stats,
		"trader_spent": trader_spent,
		"free_kit_raid": free_kit_raid,
		"quests_done": quests_done,
		"quest_progress": quest_progress,
		"trader_levels": trader_levels,
		"saved_at": Time.get_unix_time_from_system(),
	}
	var text := JSON.stringify(data)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
	_web_write(text)


## On web, user:// only reaches the browser's storage when the engine copies it there a frame later, and if the
## browser drops that storage connection (seen after an update mid-raid: the extract save was lost on reload) every
## later copy fails quietly. localStorage is written right away, so the save keeps a second copy there.
static func _web_write(text: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.setItem('%s', %s) } catch (e) {}" % [WEB_KEY, JSON.stringify(text)], true)


static func _web_read() -> String:
	if not OS.has_feature("web"):
		return ""
	var text = JavaScriptBridge.eval("(function () { try { return localStorage.getItem('%s') || '' } catch (e) { return '' } })()" % WEB_KEY, true)
	return text if text is String else ""


## The starter kit: AK (loaded), medium backpack, 60 rifle rounds, a bandage (heals are on hotbar key 3).
static func starting_loadout() -> Dictionary:
	return {
		"equipment": {
			"primary": {"id": "ak", "count": 1, "loaded": 30},
			"backpack": {"id": "backpack_medium", "count": 1},
		},
		"pockets": [{"id": "rifle_ammo", "count": 60, "x": 0, "y": 0}, {"id": "bandage", "count": 1, "x": 1, "y": 0}],
		"backpack": [],
		"secure": [],
		"hotbar": ["", "", ""],
	}


## A raid starts with your loadout on you. Until you extract, the saved profile counts you as dead (so closing the
## tab mid-raid loses your gear). Going on the raid also frees up the next free kit (0.20.12: closing the tab mid-raid
## never reaches the raid count, so after taking the kit and losing it that way you were left with nothing and no kit).
static func raid_begun() -> void:
	loadout = death_loadout(loadout)
	free_kit_raid = -1
	save_profile()


## What's left of a loadout after dying: only the secure pocket (and hotbar bindings).
static func death_loadout(data: Dictionary) -> Dictionary:
	return {"equipment": {}, "pockets": [], "backpack": [], "secure": data.get("secure", []), "hotbar": data.get("hotbar", ["", "", ""])}


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
	var equipment = data.get("equipment")
	if not equipment is Dictionary:
		equipment = {}
	# Backpack first, so its grid exists before its contents are read. Items that no longer exist are dropped.
	for slot in ["backpack", "primary", "secondary", "armor", "helmet"]:
		var entry = equipment.get(slot)
		if entry is Dictionary and ItemDB.ITEMS.has(str(entry.get("id", ""))):
			inventory.equip(slot, _read_stack(entry))
	_read_grid(_array(data.get("pockets")), inventory.pockets)
	if inventory.backpack != null:
		_read_grid(_array(data.get("backpack")), inventory.backpack)
	_read_grid(_array(data.get("secure")), inventory.secure)
	var hotbar := _array(data.get("hotbar"))
	for i in mini(hotbar.size(), Inventory.HOTBAR_SIZE):
		var id := str(hotbar[i])
		# Only keys 4 and 5 hold bindings (older saves had heals on 3-6: those are on key 3 now).
		inventory.hotbar[i] = id if ItemDB.ITEMS.has(id) and Inventory.BINDABLE_KEYS.has(i) and ItemDB.kind(id) != "heal" else ""
	inventory.changed.emit()


static func _write_stack(stack: ItemStack) -> Dictionary:
	var entry := {"id": stack.id, "count": stack.count, "x": stack.x, "y": stack.y}
	if stack.rotated:
		entry["r"] = true
	if stack.loaded > 0:
		entry["loaded"] = stack.loaded
	if stack.durability < ItemDB.max_durability(stack.id):
		entry["d"] = stack.durability
	if not stack.attachments.is_empty():
		entry["att"] = stack.attachments.duplicate()
	if stack.label != "":
		entry["n"] = stack.label
	if stack.free:
		entry["free"] = true
	if stack.found:
		entry["found"] = true
	if not stack.found_parts.is_empty():
		entry["fatt"] = stack.found_parts.duplicate()
	return entry


static func _read_stack(entry: Dictionary) -> ItemStack:
	var stack := ItemStack.new(str(entry["id"]), int(entry.get("count", 1)), int(entry.get("x", 0)), int(entry.get("y", 0)), bool(entry.get("r", false)))
	stack.loaded = int(entry.get("loaded", 0))
	if _is_number(entry.get("d")):
		stack.durability = clampi(int(entry["d"]), 0, ItemDB.max_durability(stack.id))
	stack.clean_attachments(entry.get("att"))
	if entry.get("n") is String and stack.id == "player_tag":
		stack.label = (entry["n"] as String).left(ItemStack.LABEL_MAX)
	stack.free = entry.get("free") == true
	stack.found = entry.get("found") == true
	stack.clean_found_parts(entry.get("fatt"))
	return stack


static func _write_grid(grid: GridInventory) -> Array:
	var list := []
	for stack in grid.stacks:
		list.append(_write_stack(stack))
	return list


## Puts saved stacks back at their saved spots. Anything that no longer exists is skipped; anything that no
## longer fits its spot moves to the first free one (keeping its loaded rounds), so a changed item size can't
## corrupt a save.
static func _read_grid(entries: Array, grid: GridInventory) -> void:
	for entry in entries:
		if not entry is Dictionary or not ItemDB.ITEMS.has(str(entry.get("id", ""))):
			continue
		var stack := _read_stack(entry)
		if grid.fits(stack.id, stack.x, stack.y, stack.rotated):
			grid.place(stack)
			continue
		var spot := grid.find_spot(stack.id)
		if spot.is_empty():
			grid.add(stack.id, stack.count, stack.marks())
		else:
			stack.x = spot[0]
			stack.y = spot[1]
			stack.rotated = spot[2]
			grid.place(stack)
