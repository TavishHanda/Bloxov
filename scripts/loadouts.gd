class_name Loadouts
extends RefCounted
## Saved loadouts (0.21.2, owner): save what you're carrying as a named loadout, then EQUIP it later in one tap.
## Equipping puts what you carry into the stash, then builds the loadout from the stash first and buys only what's
## missing from the traders (at your trader levels, earned money only). With BUY NEW on, everything is bought new
## even if the stash has it (owner: "an option to buy it even if they own it").
## A saved loadout is a Profile.capture_inventory dictionary (items, spots, attachments, loaded rounds, hotbar),
## without wear or the free kit / found in raid marks: those belong to the items, not the plan.

const MAX := 8
const NAME_MAX := 20
## Entry keys a saved loadout keeps (see Profile._write_stack).
const KEEP_KEYS: Array[String] = ["id", "count", "x", "y", "r", "loaded", "att"]

## The BUY NEW option, kept while the game is open.
static var buy_new := false


## What `inventory` carries, as a loadout to save.
static func from_inventory(inventory: Inventory) -> Dictionary:
	var kit := Profile.capture_inventory(inventory)
	var equipment := {}
	for slot: String in kit["equipment"]:
		equipment[slot] = _plain(kit["equipment"][slot])
	kit["equipment"] = equipment
	for key in ["pockets", "backpack", "secure"]:
		kit[key] = (kit[key] as Array).map(func(entry: Dictionary) -> Dictionary: return _plain(entry))
	return kit


static func _plain(entry: Dictionary) -> Dictionary:
	var out := {}
	for key in KEEP_KEYS:
		if entry.has(key):
			out[key] = entry[key]
	return out


## A saved loadout read from a save file: a name and a kit, or {} if it's malformed. Item ids are checked when it's
## equipped (Profile.apply_inventory's rules: anything that no longer exists is skipped).
static func clean(data: Variant) -> Dictionary:
	if not data is Dictionary or not data.get("name") is String or not data.get("kit") is Dictionary:
		return {}
	var kit: Dictionary = data["kit"]
	var out := {"equipment": kit.get("equipment") if kit.get("equipment") is Dictionary else {}, "hotbar": kit.get("hotbar", ["", "", ""])}
	for key in ["pockets", "backpack", "secure"]:
		out[key] = (kit.get(key) as Array).filter(func(e: Variant) -> bool: return e is Dictionary) if kit.get(key) is Array else []
	return {"name": clean_name(data["name"]), "kit": out}


static func clean_name(text: String) -> String:
	var out := text.strip_edges().left(NAME_MAX)
	return out if out != "" else "Loadout"


## How many items a loadout holds (a gun's attachments count), for its summary line.
static func item_count(kit: Dictionary) -> int:
	var total := 0
	for entry: Dictionary in kit["equipment"].values():
		total += 1 + (entry.get("att", {}) as Dictionary).size()
	for key in ["pockets", "backpack", "secure"]:
		total += (kit[key] as Array).size()
	return total


## Builds `kit` on `inventory`. Everything carried goes into `stash` first; each item then comes from the stash
## (unless `buy_all`) or is bought, if `can_buy(id)` says the traders sell it at your level.
## Returns {"ok", "bought": {id: amount}, "taken": items from the stash, "missing": [ids], "error": ""}.
## It spends no money: the caller prices "bought" (and runs it on copies first to check, see hideout.gd equip_loadout).
## error "stash_full": something didn't fit anywhere. "missing": items you don't have that the traders don't sell you
## (loot-only, or above your trader level); they're left out and the rest is equipped.
static func equip(kit: Dictionary, stash: GridInventory, inventory: Inventory, buy_all: bool, can_buy: Callable) -> Dictionary:
	var result := {"ok": false, "bought": {}, "taken": 0, "missing": [], "error": ""}
	if not stow_all(stash, inventory):
		result["error"] = "stash_full"
		return result
	var source := {"stash": stash, "buy_all": buy_all, "can_buy": can_buy, "result": result}
	# Backpack first, so its grid exists before its contents.
	for slot in ["backpack", "primary", "secondary", "armor", "helmet"]:
		var entry = kit["equipment"].get(slot)
		if not entry is Dictionary or not ItemDB.ITEMS.has(str(entry.get("id", ""))) or ItemDB.equip_slot(entry["id"]) != slot:
			continue
		var gear := _gear(entry, source)
		if gear != null:
			inventory.equip(slot, gear)
	var grids := {"pockets": inventory.pockets, "backpack": inventory.backpack, "secure": inventory.secure}
	for key: String in grids:
		var grid: GridInventory = grids[key]
		if grid == null:
			continue
		for entry: Dictionary in kit[key]:
			var id := str(entry.get("id", ""))
			if not ItemDB.ITEMS.has(id):
				continue
			var pieces: Array[ItemStack] = []
			if ItemDB.max_stack(id) == 1:
				var gear := _gear(entry, source)
				if gear != null:
					pieces.append(gear)
			else:
				pieces = _units(id, maxi(int(entry.get("count", 1)), 1), source)
			for i in pieces.size():
				if not _put(pieces[i], grid, entry if i == 0 else {}, inventory, stash):
					result["error"] = "stash_full"
	var hotbar = kit.get("hotbar")
	if hotbar is Array:
		for i in mini(hotbar.size(), Inventory.HOTBAR_SIZE):
			var id := str(hotbar[i])
			if Inventory.BINDABLE_KEYS.has(i):
				inventory.hotbar[i] = id if ItemDB.ITEMS.has(id) and inventory.count_of(id) > 0 else ""
	inventory.changed.emit()
	result["ok"] = result["error"] == ""
	return result


## Moves everything you carry into the stash (guns keep their rounds and attachments). False if it didn't all fit
## (what fitted stays moved: the caller puts things back).
static func stow_all(stash: GridInventory, inventory: Inventory) -> bool:
	var ok := true
	for grid in inventory.grids():
		for stack in grid.stacks.duplicate():
			grid.remove(stack)
			ok = _to_stash(stack, stash) and ok
	for slot in ["primary", "secondary", "armor", "helmet", "backpack"]:
		var stack := inventory.unequip(slot)
		if stack != null:
			ok = _to_stash(stack, stash) and ok
	return ok


static func _to_stash(stack: ItemStack, stash: GridInventory) -> bool:
	if ItemDB.max_stack(stack.id) > 1:
		var left := stash.add(stack.id, stack.count, stack.marks())
		return left == 0
	var spot := stash.find_spot(stack.id)
	if spot.is_empty():
		return false
	stack.set_spot(Vector2i(spot[0], spot[1]), spot[2])
	stash.place(stack)
	return true


## One gun or piece of gear for `entry`: the stash's best match, or a new one bought. Guns get the saved attachments
## (parts it shouldn't have go to the stash, missing ones come from the stash or are bought) and their saved rounds.
static func _gear(entry: Dictionary, source: Dictionary) -> ItemStack:
	var id := str(entry["id"])
	var stash: GridInventory = source["stash"]
	var want := ItemStack.new(id)
	want.clean_attachments(entry.get("att"))
	var stack: ItemStack = null
	if not source["buy_all"]:
		stack = _best_match(stash, want)
	if stack != null:
		stash.remove(stack)
		source["result"]["taken"] += 1
	elif _buy(id, 1, source):
		stack = ItemStack.new(id)
	else:
		return null
	if ItemDB.kind(id) != "weapon":
		return stack
	var ammo := str(ItemDB.item(id).get("ammo", ""))
	# Start from an empty gun: its rounds and the parts the loadout doesn't want go back to the stash.
	if stack.loaded > 0 and ammo != "":
		if stash.add(ammo, stack.loaded) > 0:
			source["result"]["error"] = "stash_full"
		stack.loaded = 0
	for slot: String in stack.attachments.keys():
		if want.attachments.get(slot, "") != stack.attachments[slot]:
			if stash.add(stack.attachments[slot], 1, ItemStack.FOUND if stack.found_parts.has(slot) else 0) > 0:
				source["result"]["error"] = "stash_full"
			stack.attachments.erase(slot)
			stack.found_parts.erase(slot)
	for slot: String in want.attachments:
		if stack.attachments.has(slot):
			continue
		var parts := _units(want.attachments[slot], 1, source)
		if not parts.is_empty():
			stack.attachments[slot] = want.attachments[slot]
			if parts[0].found:
				stack.found_parts.append(slot)
	var rounds := mini(int(entry.get("loaded", 0)), int(ItemDB.weapon_stats(stack)["mag"]))
	if rounds > 0 and ammo != "":
		for piece in _units(ammo, rounds, source):
			stack.loaded += piece.count
	return stack


## The stash's closest match for a gun or piece of gear: same attachments first, then the most matching parts, then
## the best condition. Free kit ones before bought ones, found in raid ones last (keep those for quests).
static func _best_match(stash: GridInventory, want: ItemStack) -> ItemStack:
	var best: ItemStack = null
	var best_score := -INF
	for stack in stash.stacks:
		if stack.id != want.id:
			continue
		var score := 0.0
		if stack.attachments == want.attachments:
			score += 1000.0
		for slot: String in want.attachments:
			if stack.attachments.get(slot, "") == want.attachments[slot]:
				score += 100.0
		score += stack.condition() * 10.0 + (1.0 if stack.free else 0.0) - (5.0 if stack.found else 0.0)
		if score > best_score:
			best_score = score
			best = stack
	return best


## `amount` of a stackable item (or one attachment): from the stash first (free kit stacks first, found in raid last,
## each piece keeping its marks), then bought. Returns the pieces, each no bigger than a full stack.
static func _units(id: String, amount: int, source: Dictionary) -> Array[ItemStack]:
	var pieces: Array[ItemStack] = []
	var left := amount
	var stash: GridInventory = source["stash"]
	if not source["buy_all"]:
		var mine := stash.stacks.filter(func(st: ItemStack) -> bool: return st.id == id)
		mine.sort_custom(func(a: ItemStack, b: ItemStack) -> bool: return _take_order(a) < _take_order(b))
		for stack: ItemStack in mine:
			if left <= 0:
				break
			var moved := mini(left, stack.count)
			stack.count -= moved
			if stack.count <= 0:
				stash.stacks.erase(stack)
			var piece := ItemStack.new(id, moved)
			piece.set_marks(stack.marks())
			pieces.append(piece)
			left -= moved
			source["result"]["taken"] += moved
		if left < amount:
			stash.changed.emit()
	if left > 0 and _buy(id, left, source):
		while left > 0:
			var size := mini(left, ItemDB.max_stack(id))
			pieces.append(ItemStack.new(id, size))
			left -= size
	return pieces


static func _take_order(stack: ItemStack) -> int:
	return 0 if stack.free else (2 if stack.found else 1)


## Notes `amount` of `id` as bought, if the traders sell it to you; otherwise it's missing.
static func _buy(id: String, amount: int, source: Dictionary) -> bool:
	var result: Dictionary = source["result"]
	if not (source["can_buy"] as Callable).call(id):
		if not (result["missing"] as Array).has(id):
			result["missing"].append(id)
		return false
	result["bought"][id] = int(result["bought"].get(id, 0)) + amount
	return true


## Puts a piece in `grid`: at the saved spot (`entry`) if it's free, else anywhere on you, else back in the stash.
## False only if it fit nowhere.
static func _put(piece: ItemStack, grid: GridInventory, entry: Dictionary, inventory: Inventory, stash: GridInventory) -> bool:
	if not entry.is_empty():
		var x := int(entry.get("x", 0))
		var y := int(entry.get("y", 0))
		var rotated := bool(entry.get("r", false))
		if grid.fits(piece.id, x, y, rotated):
			piece.set_spot(Vector2i(x, y), rotated)
			grid.place(piece)
			return true
	for target in [grid] + Array(inventory.grids()):
		if ItemDB.max_stack(piece.id) > 1:
			var left: int = target.add(piece.id, piece.count, piece.marks())
			piece.count = left
			if left == 0:
				return true
		else:
			var spot: Array = target.find_spot(piece.id)
			if not spot.is_empty():
				piece.set_spot(Vector2i(spot[0], spot[1]), spot[2])
				target.place(piece)
				return true
	return _to_stash(piece, stash)
