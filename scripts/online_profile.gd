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
	"free_kit_raid", "quests_done", "quest_progress", "rewards_taken", "trader_levels", "presets"]
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


# --- The hideout check (Stash update Phase 3, 0.31.3) ----------------------------------
## The PvP hideout runs in the player's game (buying, selling, moving, repairs, quests, the free kit) and sends the
## whole profile after each change. The server only takes a new profile that the old one could have become in the
## hideout: no item appears unless it was bought from a trader at a level they have (or is the free kit), no money
## appears unless something was sold or a quest paid it, nothing gets a found-in-raid or free mark it didn't have,
## nothing is repaired for free, and the stash only grows when paid for. Prices are the traders' own; the check
## rounds in the player's favour by a dollar or two, never more. Ming's boxes are rolled by the server (open_box).

## The free kit (hideout.take_free_kit): a Stinger with a full magazine, 30 rounds, a bandage, a small backpack.
const FREE_KIT := {"pistol": 1, "backpack_small": 1, "pistol_ammo": 42, "bandage": 1}


## Every stack in a profile (stash and loadout), as saved.
static func entries(profile: Dictionary) -> Array:
	var out: Array = []
	var stash = profile.get("stash", [])
	if stash is Array:
		out.append_array(stash)
	var loadout = profile.get("loadout", {})
	if loadout is Dictionary:
		var equipment = loadout.get("equipment", {})
		if equipment is Dictionary:
			out.append_array(equipment.values())
		for grid in ["pockets", "backpack", "secure"]:
			if loadout.get(grid) is Array:
				out.append_array(loadout[grid])
	return out.filter(func(e: Variant) -> bool: return e is Dictionary and ItemDB.ITEMS.has(str(e.get("id", ""))))


## A PvP raid ended with an extract: the kills the server counted ([[target, weapon, tags], ...]), the places searched
## (`marks`), the extract (`at`, its node name) and the loot brought out move the open quests, and a finished one pays
## its reward (the server's Quests.raid_ended).
static func raid_quests(profile: Dictionary, kills: Array, loot_value: int, marks: Array = [], at := "") -> void:
	if not profile.get("quest_progress") is Dictionary:
		profile["quest_progress"] = {}
	if not profile.get("quests_done") is Array:
		profile["quests_done"] = []
	var levels: Dictionary = profile.get("trader_levels", {}) if profile.get("trader_levels") is Dictionary else {}
	var progress: Dictionary = profile["quest_progress"]
	var done: Array = profile["quests_done"]
	var open: Array[String] = []
	for id: String in Quests.LIST:
		var trader := str(Quests.LIST[id]["trader"])
		if Quests.is_open(id, clampi(int(levels.get(trader, 1)), 1, Traders.max_level(trader)), done):
			open.append(id)
	for id in open:
		var quest: Dictionary = Quests.LIST[id]
		var gained := Quests.gain(quest, kills, marks, loot_value, at)
		if gained <= 0:
			continue
		var count := int(quest["count"])
		var now := mini(int(progress.get(id, 0)) + gained, count)
		progress[id] = now
		if now >= count:
			done.append(id)
			profile["money"] = int(profile.get("money", 0)) + int(quest["reward"])


## A PvP raid ended without an extract: the open streak quests start again.
static func raid_lost(profile: Dictionary) -> void:
	var progress: Variant = profile.get("quest_progress")
	var done: Variant = profile.get("quests_done")
	if not progress is Dictionary:
		return
	for id: String in Quests.LIST:
		if Quests.LIST[id]["kind"] == "streak" and not (done is Array and done.has(id)):
			progress.erase(id)


## The reward items of quests newly marked taken (`old` -> `new`): id -> how many. Null when a mark is made up
## (a quest not done, or a mark taken back).
static func reward_items(old: Dictionary, new: Dictionary) -> Variant:
	var before: Array = old.get("rewards_taken", []) if old.get("rewards_taken") is Array else []
	var after: Array = new.get("rewards_taken", []) if new.get("rewards_taken") is Array else []
	var done: Array = new.get("quests_done", []) if new.get("quests_done") is Array else []
	var out := {}
	for id: Variant in before:
		if not after.has(id):
			return null
	for id: Variant in after:
		if before.has(id):
			continue
		if not Quests.LIST.has(id) or not done.has(id) or after.count(id) > 1:
			return null
		for entry: Array in Quests.LIST[id].get("items", []):
			out[entry[0]] = int(out.get(entry[0], 0)) + int(entry[1])
	return out


## Counts by id: "all" (with attachments and loaded rounds, like count), "free" and "found" (stacks with that mark),
## and "wear": the durability on each id's not-free stacks added up.
static func tally(profile: Dictionary) -> Dictionary:
	var all := {}
	var free := {}
	var found := {}
	var wear := {}
	for entry: Dictionary in entries(profile):
		var id := str(entry["id"])
		var n := maxi(int(entry.get("count", 1)), 1)
		all[id] = int(all.get(id, 0)) + n
		if entry.get("free") == true:
			free[id] = int(free.get(id, 0)) + n
		elif ItemDB.max_durability(id) > 0:
			var d: Variant = entry.get("d")
			wear[id] = int(wear.get(id, 0)) + (int(d) if d is int or d is float else ItemDB.max_durability(id))
		if entry.get("found") == true:
			found[id] = int(found.get(id, 0)) + n
		var parts = entry.get("att", {})
		if parts is Dictionary:
			for part: Variant in parts.values():
				if ItemDB.ITEMS.has(str(part)):
					all[str(part)] = int(all.get(str(part), 0)) + 1
		var ammo := String(ItemDB.item(id).get("ammo", ""))
		if int(entry.get("loaded", 0)) > 0 and ammo != "":
			all[ammo] = int(all.get(ammo, 0)) + int(entry["loaded"])
	return {"all": all, "free": free, "found": found, "wear": wear}


## Checks a hideout change. `old` is the server's profile, `new` the cleaned one the game sent. Returns "" if it's
## fine (and fixes `new`'s trader money to what the server worked out), else why not. Kill and extract quests never
## move here: the server moves them itself when a raid ends (raid_quests).
static func audit(old: Dictionary, new: Dictionary) -> String:
	var a := tally(old)
	var b := tally(new)
	var raids := int(old.get("stats", {}).get("raids", 0))
	# The free kit: once per raid, only with nothing on you.
	var kit_taken := int(new.get("free_kit_raid", -1)) == raids and int(old.get("free_kit_raid", -1)) != raids
	if kit_taken and not _bare(old.get("loadout", {})):
		return "free kit while carrying gear"
	if int(new.get("free_kit_raid", -1)) != int(old.get("free_kit_raid", -1)) and not kit_taken:
		return "free kit raid changed"
	for id: String in b["free"]:
		if int(b["free"][id]) > int(a["free"].get(id, 0)) + (int(FREE_KIT.get(id, 0)) if kit_taken else 0):
			return "free mark on %s" % id
	for id: String in b["found"]:
		if int(b["found"][id]) > int(a["found"].get(id, 0)):
			return "found mark on %s" % id
	# Quests: each finished once; hand-ins use up found items; kill and extract quests only move on the server.
	var done_old: Array = old.get("quests_done", [])
	var done_new: Array = new.get("quests_done", [])
	var rewards := 0
	var handed := 0
	for id: Variant in done_old:
		if not done_new.has(id):
			return "quest undone"
	var progress_old: Dictionary = old.get("quest_progress", {}) if old.get("quest_progress") is Dictionary else {}
	var progress_new: Dictionary = new.get("quest_progress", {}) if new.get("quest_progress") is Dictionary else {}
	for id: String in Quests.LIST:
		var quest: Dictionary = Quests.LIST[id]
		var before := int(progress_old.get(id, 0))
		var after := int(progress_new.get(id, 0))
		if after < before or after > int(quest["count"]):
			return "quest progress %s" % id
		if after > before:
			if quest["kind"] == "hand_in":
				handed += after - before
			else:
				return "quest progress outside a raid %s" % id
		if done_new.has(id) and not done_old.has(id):
			if after < int(quest["count"]):
				return "quest done early %s" % id
			rewards += int(quest["reward"])
	for id: Variant in done_new:
		if not Quests.LIST.has(id):
			return "unknown quest"
	var found_used := 0
	for id: String in a["found"]:
		found_used += maxi(int(a["found"][id]) - int(b["found"].get(id, 0)), 0)
	if handed > found_used:
		return "hand-in without found items"
	var given: Variant = reward_items(old, new)
	if given == null:
		return "quest reward"
	# Trader levels: only up, and only as far as quests and money spent allow.
	var spent_old: Dictionary = old.get("trader_spent", {}) if old.get("trader_spent") is Dictionary else {}
	var levels_old: Dictionary = old.get("trader_levels", {}) if old.get("trader_levels") is Dictionary else {}
	var levels_new: Dictionary = new.get("trader_levels", {}) if new.get("trader_levels") is Dictionary else {}
	# Buying and selling: what each item cost or paid, at the trader's prices.
	var cost := 0
	var paid := 0
	var spent := spent_old.duplicate()
	var spent_new: Dictionary = new.get("trader_spent", {}) if new.get("trader_spent") is Dictionary else {}
	var bought := {}
	for id: String in _keys(a["all"], b["all"]):
		var free_gain := (int(FREE_KIT.get(id, 0)) if kit_taken else 0)
		# (free items count apart, except rounds: loading and unloading moves them between free and not)
		var change: int
		if ItemDB.kind(id) == "ammo":
			change = int(b["all"].get(id, 0)) - int(a["all"].get(id, 0)) - free_gain
		else:
			change = (int(b["all"].get(id, 0)) - int(b["free"].get(id, 0))) - (int(a["all"].get(id, 0)) - int(a["free"].get(id, 0)))
		if change > 0:   # (a quest's reward items come free)
			var reward := mini(int(given.get(id, 0)), change)
			given[id] = int(given.get(id, 0)) - reward
			change -= reward
		if change > 0:
			var trader := Traders.trader_for(id)
			if trader == "" or not _sells(trader, id, maxi(int(levels_new.get(trader, 1)), int(levels_old.get(trader, 1)))):
				return "%s isn't for sale" % id
			var price := ceili(ItemDB.value(id) * change * Traders.BUY_MARKUP)
			cost += price
			spent[trader] = int(spent.get(trader, 0)) + price
			bought[trader] = int(bought.get(trader, 0)) + change
		elif change < 0:
			paid += ceili(ItemDB.value(id) * -change * float(Traders.LIST[Traders.buyer_for(id)]["rate"]))
	# (the game adds each purchase's own rounded price: a dollar or so more per item than the total above)
	for trader: String in spent:
		var low := int(spent_old.get(trader, 0))
		spent[trader] = clampi(int(spent_new.get(trader, low)), low, int(spent[trader]) + int(bought.get(trader, 0)))
	for trader: String in Traders.LIST:
		var lv := int(levels_new.get(trader, 1))
		var lv_old := int(levels_old.get(trader, 1))
		if lv < lv_old or lv > Traders.level(trader, int(spent.get(trader, 0)), done_new):
			return "trader level %s" % trader
	# Repairs: wear that came back on items that were already there was paid for.
	for id: String in b["wear"]:
		var gained := int(b["all"].get(id, 0)) - int(b["free"].get(id, 0)) - (int(a["all"].get(id, 0)) - int(a["free"].get(id, 0)))
		var fixed := int(b["wear"][id]) - int(a["wear"].get(id, 0)) - maxi(gained, 0) * ItemDB.max_durability(id)
		if fixed > 0:
			cost += floori(ItemDB.value(id) * 0.7 * float(fixed) / ItemDB.max_durability(id) * Traders.REPAIR_RATE)
	# The stash: only bigger, paid for.
	var rows_old := int(old.get("stash_size", [STASH_WIDTH, STASH_ROWS[0]])[1])
	var rows_new := int(new.get("stash_size", [STASH_WIDTH, STASH_ROWS[0]])[1])
	if rows_new < rows_old:
		return "stash shrank"
	for i in STASH_ROWS.size():
		if STASH_ROWS[i] > rows_old and STASH_ROWS[i] <= rows_new:
			cost += Profile.STASH_UPGRADE_COST[i]
	# Money: no more than what was there, less what was bought, plus what was sold and quest rewards.
	var allowed := int(old.get("money", 0)) - cost + paid + rewards
	if int(new.get("money", 0)) > allowed + 2:
		return "money %d, at most %d" % [int(new.get("money", 0)), allowed]
	new["trader_spent"] = spent
	return ""


static func _keys(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = a.keys()
	for key: Variant in b:
		if not out.has(key):
			out.append(key)
	return out


## Nothing on you but the secure pocket (when the free kit can be taken).
static func _bare(loadout: Variant) -> bool:
	if not loadout is Dictionary:
		return true
	var equipment = loadout.get("equipment", {})
	return (not equipment is Dictionary or equipment.is_empty()) and (loadout.get("pockets", []) as Array).is_empty() \
		and (loadout.get("backpack", []) as Array).is_empty()


## Whether `trader` at level `lv` has `id` for sale.
static func _sells(trader: String, id: String, lv: int) -> bool:
	for entry: Array in Traders.stock(trader):
		if entry[0] == id and int(entry[2]) <= lv:
			return true
	return false


## Ming's box rolled on the server (PvP): pays the price and puts the item in the stash. Returns the item id, or ""
## (not enough money, no room, not a box).
static func open_box(profile: Dictionary, box: String) -> String:
	if not Traders.BOXES.has(box):
		return ""
	var price := int(Traders.BOXES[box]["price"])
	if int(profile.get("money", 0)) < price:
		return ""
	var size: Array = profile.get("stash_size", [STASH_WIDTH, STASH_ROWS[0]])
	var grid := GridInventory.new("Stash", int(size[0]), int(size[1]))
	for entry: Variant in profile.get("stash", []):
		if not entry is Dictionary or not ItemDB.ITEMS.has(str(entry.get("id", ""))):
			continue
		var stack := ItemStack.new(str(entry["id"]), int(entry.get("count", 1)), int(entry.get("x", 0)), int(entry.get("y", 0)), entry.get("r") == true)
		grid.stacks.append(stack)   # (kept as they are; only the free spots matter)
	var id := Traders.open_box(box)
	var spot := grid.find_spot(id)
	if spot.is_empty():
		return ""
	var item := {"id": id, "count": 1, "x": spot[0], "y": spot[1]}
	if spot[2]:
		item["r"] = true
	(profile["stash"] as Array).append(item)
	profile["money"] = int(profile["money"]) - price
	return id
