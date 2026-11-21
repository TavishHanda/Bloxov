class_name MaterialLocker
extends RefCounted
## The materials locker (0.38.7, owner 2026-11-21: "a place to store all your craftable items like the nuts and bolts
## so it's not cluttering your main inventory ... really expensive"): bought once at the workbench for PRICE, it holds
## up to MAX_EACH of every crafting material as a plain count (no grid). The workbench and the truck take parts from
## it as well as the stash. Found-in-raid marks are kept, so jobs still work once you take them back out. Free-kit
## stacks never go in. The server checks it too (OnlineProfile.audit), so like OnlineProfile this only leans on item
## data (ItemDB, GridInventory, ItemStack), never on hideout or player scripts.

const PRICE := 150000
const MAX_EACH := 50
## What it takes (order = the locker screen's rows): everything a recipe, the bench or the truck uses that isn't gear.
const ITEMS: Array[String] = ["bolts", "wires", "scrap", "duct_tape", "gunpowder", "med_supplies", "battery", "fuel_can"]

var owned := false
## id -> [plain, found]: how many of each, without and with the found-in-raid mark.
var items := {}


func count(id: String) -> int:
	if not items.has(id):
		return 0
	return int(items[id][0]) + int(items[id][1])


func room(id: String) -> int:
	return maxi(MAX_EACH - count(id), 0) if owned and ITEMS.has(id) else 0


func total() -> int:
	var n := 0
	for id: String in items:
		n += count(id)
	return n


func copy() -> MaterialLocker:
	var out := MaterialLocker.new()
	out.owned = owned
	for id: String in items:
		out.items[id] = [int(items[id][0]), int(items[id][1])]
	return out


## Moves the stash's materials in (only `id`, or every kind when it's ""), up to the room left. Free-kit stacks stay.
## Returns how many went in.
func store(stash: GridInventory, id := "") -> int:
	var moved := 0
	for stack: ItemStack in stash.stacks.duplicate():
		if stack.free or not ITEMS.has(stack.id) or (id != "" and stack.id != id):
			continue
		var n := mini(stack.count, room(stack.id))
		if n <= 0:
			continue
		if not items.has(stack.id):
			items[stack.id] = [0, 0]
		items[stack.id][1 if stack.found else 0] += n
		stack.count -= n
		moved += n
		if stack.count <= 0:
			stash.stacks.erase(stack)
	if moved > 0:
		stash.changed.emit()
	return moved


## Moves up to `n` of `id` back to the stash (found-in-raid ones first, for jobs). Returns how many fit.
func take(stash: GridInventory, id: String, n: int) -> int:
	var moved := 0
	for slot in [1, 0]:
		var want := mini(n - moved, int(items.get(id, [0, 0])[slot]))
		if want <= 0:
			continue
		var left := stash.add(id, want, ItemStack.FOUND if slot == 1 else 0)
		items[id][slot] -= want - left
		moved += want - left
		if left > 0:
			break
	_tidy(id)
	return moved


## Uses up to `n` of `id` with (found) or without the found mark, for a craft. Returns how many it had.
func use(id: String, n: int, found: bool) -> int:
	if not items.has(id) or n <= 0:
		return 0
	var slot := 1 if found else 0
	var used := mini(n, int(items[id][slot]))
	items[id][slot] -= used
	_tidy(id)
	return used


func _tidy(id: String) -> void:
	if items.has(id) and count(id) <= 0:
		items.erase(id)


## The saved shape: {"owned": true, "items": [{"id", "count"(, "found": true)}]}, one entry per id and mark.
func to_data() -> Dictionary:
	var list := []
	for id: String in ITEMS:
		if not items.has(id):
			continue
		if int(items[id][0]) > 0:
			list.append({"id": id, "count": int(items[id][0])})
		if int(items[id][1]) > 0:
			list.append({"id": id, "count": int(items[id][1]), "found": true})
	return {"owned": owned, "items": list}


static func from_data(data: Variant) -> MaterialLocker:
	var out := MaterialLocker.new()
	var given := clean(data)
	out.owned = given["owned"]
	for entry: Dictionary in given["items"]:
		var id := str(entry["id"])
		if not out.items.has(id):
			out.items[id] = [0, 0]
		out.items[id][1 if entry.get("found") == true else 0] += int(entry["count"])
	return out


## A saved locker with only real materials, at most MAX_EACH of each, and nothing in it unless it was bought.
static func clean(data: Variant) -> Dictionary:
	var out := {"owned": false, "items": []}
	if not data is Dictionary or data.get("owned") != true:
		return out
	out["owned"] = true
	var held := {}
	var list = data.get("items")
	if not list is Array:
		return out
	for entry: Variant in list:
		if not entry is Dictionary or not ITEMS.has(str(entry.get("id", ""))):
			continue
		var id := str(entry["id"])
		var n = entry.get("count")
		if not (n is int or n is float):
			continue
		var fits := mini(int(n), MAX_EACH - int(held.get(id, 0)))
		if fits < 1:
			continue
		held[id] = int(held.get(id, 0)) + fits
		var item := {"id": id, "count": fits}
		if entry.get("found") == true:
			item["found"] = true
		out["items"].append(item)
	return out


## The locker's entries in a profile, in the stack shape (OnlineProfile.entries counts them with the stash).
static func entries_of(profile: Dictionary) -> Array:
	return clean(profile.get("locker"))["items"]


## What changed between two profiles: {"error", "money"} (bought = PRICE; it never goes away outside an expedition).
static func changes(old: Dictionary, new: Dictionary) -> Dictionary:
	var before: bool = clean(old.get("locker"))["owned"]
	var after: bool = clean(new.get("locker"))["owned"]
	if before and not after:
		return {"error": "locker gone", "money": 0}
	return {"error": "", "money": PRICE if after and not before else 0}
