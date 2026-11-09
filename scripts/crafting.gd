class_name Crafting
extends RefCounted
## Crafting at the hideout's workbench (0.32.0, owner 2026-11-09): turn loot you bring home into gear. Instant (owner:
## no timers), any number at once, from what's in your stash. Every recipe makes and uses items already in the game
## (owner: no new items without asking). The bench has levels that open more recipes, paid with money and parts.
## The server runs this too (OnlineProfile.audit checks PvP crafts), so like OnlineProfile it only leans on item
## data (ItemDB, GridInventory, ItemStack), never on hideout or player scripts.
## Crafted items are ordinary bought-like stacks: not free, not found in raid (no quest hand-ins).

## id -> what it makes (item id, how many per craft), what it uses (item id -> how many), and the bench level it needs.
## Order = the order on the crafting screen.
const RECIPES := {
	"bandage": {"makes": "bandage", "amount": 2, "needs": {"med_supplies": 1, "duct_tape": 1}, "level": 1},
	"medkit": {"makes": "medkit", "amount": 1, "needs": {"med_supplies": 2, "bandage": 1}, "level": 1},
	"energy_drink": {"makes": "energy_drink", "amount": 1, "needs": {"water": 2, "ration": 1}, "level": 1},
	"rifle_ammo": {"makes": "rifle_ammo", "amount": 90, "needs": {"gunpowder": 1, "scrap": 1}, "level": 1},
	"smg_ammo": {"makes": "smg_ammo", "amount": 90, "needs": {"gunpowder": 1, "bolts": 2}, "level": 1},
	"shells": {"makes": "shells", "amount": 30, "needs": {"gunpowder": 1, "scrap": 1}, "level": 1},
	"sniper_ammo": {"makes": "sniper_ammo", "amount": 20, "needs": {"gunpowder": 2, "bolts": 5}, "level": 1},
	"grenade": {"makes": "grenade", "amount": 1, "needs": {"gunpowder": 2, "scrap": 1, "duct_tape": 1}, "level": 2},
	"foregrip": {"makes": "foregrip", "amount": 1, "needs": {"scrap": 1, "bolts": 3, "duct_tape": 1}, "level": 2},
	"suppressor": {"makes": "suppressor", "amount": 1, "needs": {"scrap": 3, "bolts": 5, "duct_tape": 1}, "level": 2},
	"scope_4x": {"makes": "scope_4x", "amount": 1, "needs": {"phone": 1, "bolts": 3, "duct_tape": 1}, "level": 2},
}

## What each bench level costs to reach: BENCH[0] = level 2. Level 1 is free. (Owner, 2026-11-09: heavy armor, the
## combat helmet and the large backpack stay loot-only, so there's no level 3 for now.)
const BENCH := [
	{"money": 10000, "needs": {"bolts": 10, "wires": 3, "scrap": 3}},
]
## The most crafts at once (the selector's top end).
const MAX_TIMES := 99


static func max_level() -> int:
	return BENCH.size() + 1


## What reaching `level` costs ({} for level 1 or past the top).
static func bench_cost(level: int) -> Dictionary:
	if level < 2 or level > max_level():
		return {}
	return BENCH[level - 2]


## How many of `id` the stash has to craft with: free-kit stacks don't count (they can't be sold either).
static func have(stash: GridInventory, id: String) -> int:
	var total := 0
	for stack in stash.stacks:
		if stack.id == id and not stack.free:
			total += stack.count
	return total


## How many times `recipe` can be made from the stash (parts only; room is checked when crafting).
static func times_possible(stash: GridInventory, recipe: String) -> int:
	var most := MAX_TIMES
	for id: String in RECIPES[recipe]["needs"]:
		most = mini(most, have(stash, id) / int(RECIPES[recipe]["needs"][id]))
	return most


## Whether you have every part in `needs` (item id -> count) `times` over.
static func has_parts(stash: GridInventory, needs: Dictionary, times := 1) -> bool:
	for id: String in needs:
		if have(stash, id) < int(needs[id]) * times:
			return false
	return true


## Crafts `recipe` `times` over into `stash` at bench level `level`. Returns "" if it worked (the parts are gone and
## the items are in the stash), else why not (and nothing changed).
static func craft(stash: GridInventory, recipe: String, times: int, level: int) -> String:
	if not RECIPES.has(recipe):
		return "No such recipe"
	var info: Dictionary = RECIPES[recipe]
	if times < 1 or times > MAX_TIMES:
		return "Pick how many to make"
	if int(info["level"]) > level:
		return "Needs workbench level %d" % int(info["level"])
	if not has_parts(stash, info["needs"], times):
		return "Not enough parts"
	# Try it on a copy first, so a full stash changes nothing.
	var copy := _copy(stash)
	_use(copy, info["needs"], times)
	if not _make(copy, info["makes"], int(info["amount"]) * times):
		return "No room in your stash"
	_use(stash, info["needs"], times)
	_make(stash, info["makes"], int(info["amount"]) * times)
	return ""


## Takes the parts for one bench level from the stash ("" if done; the caller takes the money).
static func use_bench_parts(stash: GridInventory, level: int) -> String:
	var cost := bench_cost(level)
	if cost.is_empty():
		return "The workbench is as good as it gets"
	if not has_parts(stash, cost["needs"]):
		return "Not enough parts"
	_use(stash, cost["needs"], 1)
	return ""


## What a recipe's parts line reads: "Medical Supplies 1/1 · Duct Tape 0/1", for `times` crafts.
static func parts_text(stash: GridInventory, needs: Dictionary, times := 1) -> Array:
	var parts := []
	for id: String in needs:
		var need := int(needs[id]) * maxi(times, 1)
		parts.append([ItemDB.display_name(id), have(stash, id), need])
	return parts


static func _copy(stash: GridInventory) -> GridInventory:
	var copy := GridInventory.new(stash.title, stash.width, stash.height)
	for stack in stash.stacks:
		copy.stacks.append(GridInventory.data_stack(GridInventory.stack_data(stack)))
	return copy


## Takes the parts: never free-kit stacks; plain ones before found-in-raid ones (so quest items go last), smallest first.
static func _use(stash: GridInventory, needs: Dictionary, times: int) -> void:
	for id: String in needs:
		var left := int(needs[id]) * times
		var matching: Array[ItemStack] = []
		for stack in stash.stacks:
			if stack.id == id and not stack.free:
				matching.append(stack)
		matching.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
			if a.found != b.found:
				return not a.found
			return a.count < b.count)
		for stack in matching:
			if left <= 0:
				break
			var moved := mini(left, stack.count)
			stack.count -= moved
			left -= moved
			if stack.count <= 0:
				stash.stacks.erase(stack)
	stash.changed.emit()


## Puts `count` of `id` in the stash. False if it didn't all fit.
static func _make(stash: GridInventory, id: String, count: int) -> bool:
	if ItemDB.max_stack(id) == 1:
		for i in count:
			var spot := stash.find_spot(id)
			if spot.is_empty():
				return false
			stash.place(ItemStack.new(id, 1, spot[0], spot[1], spot[2]))
		return true
	return stash.add(id, count) == 0


# --- PvP: what the server checks (OnlineProfile.audit) ---------------------------

## A profile's crafts so far: recipe id -> times (only ever goes up).
static func crafted_of(profile: Dictionary) -> Dictionary:
	var out := {}
	var given = profile.get("crafted")
	if given is Dictionary:
		for key: Variant in given:
			if key is String and RECIPES.has(key) and (given[key] is int or given[key] is float):
				out[key] = maxi(int(given[key]), 0)
	return out


static func bench_of(profile: Dictionary) -> int:
	var given = profile.get("bench_level")
	return clampi(int(given), 1, max_level()) if given is int or given is float else 1


## What changed between two profiles through crafting and bench upgrades: {"error", "made": {id: n}, "used": {id: n},
## "money": dollars spent}. The audit then treats what's left of the change as buying and selling.
static func changes(old: Dictionary, new: Dictionary) -> Dictionary:
	var out := {"error": "", "made": {}, "used": {}, "money": 0}
	var level_old := bench_of(old)
	var level_new := bench_of(new)
	var given = new.get("bench_level", 1)
	if not (given is int or given is float) or int(given) != level_new:
		out["error"] = "workbench level %s" % str(given)
		return out
	if level_new < level_old:
		out["error"] = "workbench level went down"
		return out
	for level in range(level_old + 1, level_new + 1):
		var cost := bench_cost(level)
		out["money"] += int(cost["money"])
		for id: String in cost["needs"]:
			out["used"][id] = int(out["used"].get(id, 0)) + int(cost["needs"][id])
	var before := crafted_of(old)
	var after := crafted_of(new)
	for recipe: String in after:
		var times := int(after[recipe]) - int(before.get(recipe, 0))
		if times < 0:
			out["error"] = "craft count went down"
			return out
		if times == 0:
			continue
		var info: Dictionary = RECIPES[recipe]
		if int(info["level"]) > level_new:
			out["error"] = "craft %s above the workbench's level" % recipe
			return out
		out["made"][info["makes"]] = int(out["made"].get(info["makes"], 0)) + int(info["amount"]) * times
		for id: String in info["needs"]:
			out["used"][id] = int(out["used"].get(id, 0)) + int(info["needs"][id]) * times
	for recipe: String in before:
		if not after.has(recipe):
			out["error"] = "craft count went down"
			return out
	return out
