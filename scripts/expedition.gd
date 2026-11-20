class_name Expedition
extends RefCounted
## Expeditions (0.38.0, owner 2026-11-20; plan: project file expeditions/build-plan.md): the way out of the war.
## You build an amphibious armoured truck from five parts at the hideout (loot from your stash plus money), pay the
## safe haven's entry price, and leave. Leaving wipes that stash (money, gear, traders, quests, workbench, character
## level) and the character earns upgrade points; settings, looks, hideout decor and the stats record stay.
## Solo and PvP are separate: each side builds its own truck and wipes only itself (owner 2026-11-08).
## Repeatable, solo only, earned money only: gems never buy a part, the entry or a skip (STORE_RULES.md section 5).
## Parts are not items: they live on the truck (profile key "truck"), so they can't be sold, dropped or lost.
## The server runs this too (OnlineProfile checks PvP part builds and does the PvP wipe), so like Crafting it only
## leans on item data, never on hideout or player scripts.

## part id -> its name, what it uses (item id -> how many) and its money. Order = the screen's order.
## Numbers: owner 2026-11-20 ("medium": ~35-40 raids, ~$890k with the haven), from the material sim.
const PARTS := {
	"frame": {"name": "Frame", "about": "The armoured body and the wheels. Big Don found the chassis.",
		"needs": {"scrap": 20, "bolts": 25, "duct_tape": 15}, "money": 60000},
	"engine": {"name": "Engine", "about": "Runs on land and pushes it through water. Ponta knows a mechanic.",
		"needs": {"battery": 4, "wires": 20, "bolts": 10, "cpu": 2}, "money": 90000},
	"armor": {"name": "Armor plates", "about": "Bolted on all round so the border guns can't stop you.",
		"needs": {"armor_heavy": 1, "scrap": 10, "duct_tape": 5}, "money": 60000},
	"radio": {"name": "Radio and route", "about": "The way through the lines and the haven's call sign. Supreme's contacts.",
		"needs": {"phone": 4, "laptop": 2, "hard_drive": 3, "intel_novarra": 3, "intel_exion": 1}, "money": 40000},
	"supplies": {"name": "Fuel and supplies", "about": "Enough to reach the haven without stopping.",
		"needs": {"fuel_can": 10, "ration": 8, "water": 12, "medkit": 4}, "money": 30000},
}
## The safe haven's entry price, paid as you leave.
const HAVEN_PRICE := 500000
## Upgrade points a character earns per trip (owner 2026-11-20; Characters caps the total).
const POINTS := 2


## The parts a profile's truck has, in PARTS order (only real ones, each once).
static func truck_of(profile: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var given = profile.get("truck")
	if given is Array:
		for id: String in PARTS:
			if given.has(id):
				out.append(id)
	return out


## How many trips a profile has made.
static func trips_of(profile: Dictionary) -> int:
	var given = profile.get("expeditions")
	return maxi(int(given), 0) if given is int or given is float else 0


## Why `part` can't be built now ("" = it can).
static func cant_build(stash: GridInventory, money: int, truck: Array, part: String) -> String:
	if not PARTS.has(part):
		return "No such part."
	if truck.has(part):
		return "Already built."
	if not Crafting.has_parts(stash, PARTS[part]["needs"]):
		return "Not enough parts in the stash."
	if money < int(PARTS[part]["money"]):
		return "Not enough money."
	return ""


## Builds `part`: takes its loot from the stash and adds it to `truck`. Returns the error ("" = done). The caller
## takes the money (Profile, or the server's copy).
static func build(stash: GridInventory, money: int, truck: Array, part: String) -> String:
	var why := cant_build(stash, money, truck, part)
	if why != "":
		return why
	Crafting._use(stash, PARTS[part]["needs"], 1)
	truck.append(part)
	return ""


## Whether the truck is finished and the entry can be paid.
static func can_leave(truck: Array, money: int) -> bool:
	return truck.size() == PARTS.size() and money >= HAVEN_PRICE


## What the truck parts built between two profiles used: {"error", "used": {id: n}, "money"} (OnlineProfile.audit).
## Parts only ever go on; trips only change through leave (on the server for PvP).
static func changes(old: Dictionary, new: Dictionary) -> Dictionary:
	var out := {"error": "", "used": {}, "money": 0}
	var before := truck_of(old)
	var after := truck_of(new)
	var given = new.get("truck", [])
	if not given is Array or given.size() != after.size():
		out["error"] = "truck parts"
		return out
	for id: String in before:
		if not after.has(id):
			out["error"] = "truck part removed"
			return out
	if trips_of(new) != trips_of(old):
		out["error"] = "expedition count"
		return out
	for id: String in after:
		if before.has(id):
			continue
		out["money"] += int(PARTS[id]["money"])
		for item: String in PARTS[id]["needs"]:
			out["used"][item] = int(out["used"].get(item, 0)) + int(PARTS[id]["needs"][item])
	return out


## The profile after leaving: `fresh` (a new profile in the saved shape: the starting money and kit) with the stats
## record kept and one more trip. "" error when `profile` can't leave yet. Look, decor, tutorial and settings aren't
## in a saved stash, so the caller keeps them.
static func wiped(profile: Dictionary, fresh: Dictionary) -> Dictionary:
	if not can_leave(truck_of(profile), int(profile.get("money", 0))):
		return {}
	var out := fresh.duplicate(true)
	if profile.get("stats") is Dictionary:
		out["stats"] = (profile["stats"] as Dictionary).duplicate()
	out["expeditions"] = trips_of(profile) + 1
	out["truck"] = []
	return out
