class_name OnlineProfile
extends RefCounted
## The PvP stash's profile (Stash update, 0.31; docs/STASH_UPDATE_PLAN.md): a Dictionary in the solo save's shape
## (Profile.save_text), minus look and tutorial, which are account-wide. The game server keeps one per signed-in
## player and the Stash API stores it. Kept apart from Profile so the server can use it: like net.gd, this must only
## lean on item data (ItemDB, GridInventory, ItemStack), never on player, gun or hideout scripts.

const VERSION := 1
## The PvP starter money (plan §4.6, owner 2026-11-04).
const START_MONEY := 50000
const STASH_WIDTH := 8
const STASH_ROWS: Array[int] = [20, 30, 40, 50]
## What a client may send at most (a 8 x 50 stash is 400 cells; bigger is made up).
const MAX_STACKS := 500
const MAX_MONEY := 1_000_000_000
const KEYS: Array[String] = ["version", "money", "stash_size", "stash", "loadout", "stats", "trader_spent",
	"free_kit_raid", "quests_done", "quest_progress", "trader_levels", "presets"]
const STATS: Array[String] = ["raids", "extracts", "deaths", "earned"]


## A new PvP stash (plan §4.6, owner 2026-11-04; 3 Stingers, not 5: owner 2026-11-06): $50k, three Hounds, three
## Stingers, a red dot, foregrip and extended mag per Hound, a suppressor, ammo, meds, and one ready kit (light armor,
## old helmet, medium backpack) worn with a Hound and a Stinger. Ordinary stacks, so it can be sold (the repeatable
## free kit stays unsellable).
static func fresh() -> Dictionary:
	var grid := GridInventory.new("Stash", STASH_WIDTH, STASH_ROWS[0])
	for id in ["ak", "ak", "pistol", "pistol"]:
		var spot := grid.find_spot(id)
		var gun := ItemStack.new(id, 1, spot[0], spot[1], spot[2])
		gun.loaded = int(ItemDB.ITEMS[id]["mag"])
		grid.place(gun)
	for entry in [["red_dot", 3], ["foregrip", 3], ["ext_mag", 3], ["suppressor", 1], ["rifle_ammo", 270],
			["pistol_ammo", 250], ["bandage", 4], ["medkit", 2], ["energy_drink", 3], ["backpack_small", 1]]:
		grid.add(entry[0], entry[1])
	var stash := []
	for stack: ItemStack in grid.stacks:
		var item := {"id": stack.id, "count": stack.count, "x": stack.x, "y": stack.y}
		if stack.rotated:
			item["r"] = true
		if stack.loaded > 0:
			item["loaded"] = stack.loaded
		stash.append(item)
	return {
		"version": VERSION,
		"money": START_MONEY,
		"stash_size": [grid.width, grid.height],
		"stash": stash,
		"loadout": {
			"equipment": {
				"primary": {"id": "ak", "count": 1, "loaded": int(ItemDB.ITEMS["ak"]["mag"])},
				"secondary": {"id": "pistol", "count": 1, "loaded": int(ItemDB.ITEMS["pistol"]["mag"])},
				"armor": {"id": "armor_light", "count": 1},
				"helmet": {"id": "helmet_basic", "count": 1},
				"backpack": {"id": "backpack_medium", "count": 1},
			},
			"pockets": [{"id": "rifle_ammo", "count": 90, "x": 0, "y": 0}, {"id": "bandage", "count": 1, "x": 1, "y": 0}],
			"backpack": [],
			"secure": [],
			"hotbar": ["", "", ""],
		},
		"stats": {"raids": 0, "extracts": 0, "deaths": 0, "earned": 0},
		"free_kit_raid": -1,
	}


## A profile a client sent, checked for shape only (the hideout's buys and sells are still the client's until the
## server runs the hideout, plan Phase 3): known keys, sane numbers, real item ids, sizes in range. {} = refused.
static func clean(data: Variant) -> Dictionary:
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		return {}
	var money = data.get("money")
	var size = data.get("stash_size")
	if not (money is int or money is float) or money < 0 or money > MAX_MONEY:
		return {}
	if not (size is Array and size.size() == 2 and int(size[0]) == STASH_WIDTH and STASH_ROWS.has(int(size[1]))):
		return {}
	var stash = data.get("stash")
	var loadout = data.get("loadout")
	if not stash is Array or stash.size() > MAX_STACKS or not _entries_ok(stash) or not loadout_ok(loadout):
		return {}
	var out := {}
	for key in KEYS:
		if data.has(key):
			out[key] = data[key]
	out["version"] = VERSION
	out["money"] = int(money)
	out["stash_size"] = [STASH_WIDTH, int(size[1])]
	var stats := {}
	var given = data.get("stats")
	for key in STATS:
		stats[key] = maxi(int(given.get(key, 0)), 0) if given is Dictionary and (given.get(key) is int or given.get(key) is float) else 0
	out["stats"] = stats
	return out


## A loadout in Profile.capture_inventory's shape, with only real items in it.
static func loadout_ok(loadout: Variant) -> bool:
	if not loadout is Dictionary:
		return false
	var equipment = loadout.get("equipment", {})
	if not equipment is Dictionary or equipment.size() > 8 or not _entries_ok(equipment.values()):
		return false
	for grid in ["pockets", "backpack", "secure"]:
		var list = loadout.get(grid, [])
		if not list is Array or list.size() > 200 or not _entries_ok(list):
			return false
	return true


static func _entries_ok(entries: Array) -> bool:
	for entry: Variant in entries:
		if not entry is Dictionary or not ItemDB.ITEMS.has(str(entry.get("id", ""))):
			return false
		var count = entry.get("count", 1)
		if not (count is int or count is float) or count < 1 or count > ItemDB.max_stack(str(entry["id"])):
			return false
	return true


## Every item in a loadout, counted like NetGuard.count_stacks: id -> how many, with attachments and loaded rounds.
static func count(loadout: Dictionary) -> Dictionary:
	var counts := {}
	var entries: Array = []
	var equipment = loadout.get("equipment", {})
	if equipment is Dictionary:
		entries.append_array(equipment.values())
	for grid in ["pockets", "backpack", "secure"]:
		var list = loadout.get(grid, [])
		if list is Array:
			entries.append_array(list)
	for entry: Variant in entries:
		if not entry is Dictionary or not ItemDB.ITEMS.has(str(entry.get("id", ""))):
			continue
		var id := str(entry["id"])
		counts[id] = int(counts.get(id, 0)) + maxi(int(entry.get("count", 1)), 1)
		var parts = entry.get("att", {})
		if parts is Dictionary:
			for part: Variant in parts.values():
				if ItemDB.ITEMS.has(str(part)):
					counts[str(part)] = int(counts.get(str(part), 0)) + 1
		var ammo := String(ItemDB.item(id).get("ammo", ""))
		if int(entry.get("loaded", 0)) > 0 and ammo != "":
			counts[ammo] = int(counts.get(ammo, 0)) + int(entry["loaded"])
	return counts


## What a loadout is worth (ItemDB values).
static func worth(loadout: Dictionary) -> int:
	var total := 0
	var counts := count(loadout)
	for id: String in counts:
		total += ItemDB.value(id) * int(counts[id])
	return total


## The ids a loadout has more of than `carried` allows (the server's own count): {id: how many too many}.
static func more_than(loadout: Dictionary, carried: Dictionary) -> Dictionary:
	var extra := {}
	var counts := count(loadout)
	for id: String in counts:
		var over := int(counts[id]) - int(carried.get(id, 0))
		if over > 0:
			extra[id] = over
	return extra


## What's left of a loadout after dying: only the secure pocket (and hotbar bindings). Same as Profile.death_loadout.
static func death_loadout(loadout: Dictionary) -> Dictionary:
	return {"equipment": {}, "pockets": [], "backpack": [], "secure": loadout.get("secure", []),
		"hotbar": loadout.get("hotbar", ["", "", ""])}
