class_name Quests
extends RefCounted
## Trader quests (0.16.13, owner: "quests instead of buying items to unlock items"). Each trader level past the first
## needs that level's quests done (and, for some, some money spent with the trader: Traders.LIST "spent"). Only the
## quests for a trader's next level are open. Kills and extracts only count once you get out alive (owner); hand-ins
## take items found in raid (ItemStack.found) from your stash and loadout. Every quest pays a small reward.
## No quests for killing other players (owner). Names and text are placeholders until the owner renames them.

## kind "kill": `target` is the AI's scene name (scav, sniper, raider, boss), optional `weapon` = the gun's item id.
## kind "hand_in": `item` is an item id, or "kind:a,b" for any item of those kinds.
## kind "extract": get out alive, optionally carrying at least `min_value` of loot.
const LIST := {
	"zeroing_in": {"trader": "guns", "level": 2, "name": "Zeroing In", "text": "Kill 5 scavs, then extract.",
		"kind": "kill", "target": "scav", "count": 5, "reward": 2000},
	"spare_parts": {"trader": "guns", "level": 2, "name": "Spare Parts", "text": "Hand in 2 attachments found in raid.",
		"kind": "hand_in", "item": "kind:attachment", "count": 2, "reward": 3000},
	"field_test": {"trader": "guns", "level": 2, "name": "Field Test", "text": "Kill 3 scavs with a Mauler, then extract.",
		"kind": "kill", "target": "scav", "weapon": "shotgun", "count": 3, "reward": 3000},
	"overwatch": {"trader": "guns", "level": 3, "name": "Overwatch", "text": "Kill 2 snipers, then extract.",
		"kind": "kill", "target": "sniper", "count": 2, "reward": 5000},
	"hard_targets": {"trader": "guns", "level": 3, "name": "Hard Targets", "text": "Kill 3 Raiders, then extract.",
		"kind": "kill", "target": "raider", "count": 3, "reward": 6000},
	"big_game": {"trader": "guns", "level": 3, "name": "Big Game", "text": "Kill Bon, then extract.",
		"kind": "kill", "target": "boss", "count": 1, "reward": 10000},
	"first_aid": {"trader": "meds", "level": 2, "name": "First Aid", "text": "Hand in 3 bandages found in raid.",
		"kind": "hand_in", "item": "bandage", "count": 3, "reward": 1500},
	"house_call": {"trader": "meds", "level": 2, "name": "House Call", "text": "Extract 3 times.",
		"kind": "extract", "count": 3, "reward": 2000},
	"packing_up": {"trader": "supplies", "level": 2, "name": "Packing Up", "text": "Extract with $10,000 of loot or more.",
		"kind": "extract", "min_value": 10000, "count": 1, "reward": 3000},
	"scrap_run": {"trader": "supplies", "level": 2, "name": "Scrap Run", "text": "Hand in 2 armor vests or helmets found in raid.",
		"kind": "hand_in", "item": "kind:armor,helmet", "count": 2, "reward": 2500},
}

## This raid's kills, [[target, weapon], ...]: they only count if you extract.
static var raid_kills: Array = []
## Quests finished by the last raid, for the hideout to announce.
static var just_finished: Array[String] = []


## Quest ids for a trader's level, in list order.
static func for_level(trader: String, level: int) -> Array[String]:
	var out: Array[String] = []
	for id: String in LIST:
		if LIST[id]["trader"] == trader and int(LIST[id]["level"]) == level:
			out.append(id)
	return out


## The quests you can work on now: those for each trader's next level.
static func open_quests() -> Array[String]:
	var out: Array[String] = []
	for trader: String in Traders.LIST:
		for id in for_level(trader, Profile.trader_level(trader) + 1):
			if not Profile.quests_done.has(id):
				out.append(id)
	return out


## An open hand-in quest takes this item, so whether it was found in raid matters (0.17.2, owner: otherwise the mark
## is ignored and it stacks with everything).
static func wants(item_id: String) -> bool:
	for id in open_quests():
		if LIST[id]["kind"] == "hand_in" and _matches(LIST[id]["item"], item_id):
			return true
	return false


static func progress(id: String) -> int:
	return int(Profile.quest_progress.get(id, 0))


## A new raid: forget the last one's kills.
static func raid_started() -> void:
	raid_kills = []


## You killed an AI (`target` = its scene name) with `weapon` (item id, "" if unknown).
static func record_kill(target: String, weapon: String) -> void:
	raid_kills.append([target, weapon])


## What this raid adds to a quest once you get out (for the quest tracker, 0.17.1): its kills that count, or 1 for
## an extract quest without a loot target.
static func this_raid(id: String) -> int:
	var quest: Dictionary = LIST[id]
	match quest["kind"]:
		"kill":
			return raid_kills.filter(func(kill: Array) -> bool:
				return kill[0] == quest["target"] and (not quest.has("weapon") or kill[1] == quest["weapon"])).size()
		"extract":
			return 1 if not quest.has("min_value") else 0
	return 0


## The raid is over. Extracted: its kills and the extract count toward open quests.
static func raid_ended(extracted: bool, loot_value: int) -> void:
	just_finished = []
	if not extracted:
		raid_kills = []
		return
	for id in open_quests():
		var quest: Dictionary = LIST[id]
		var gained := 0
		match quest["kind"]:
			"kill":
				gained = this_raid(id)
			"extract":
				if loot_value >= int(quest.get("min_value", 0)):
					gained = 1
		if gained > 0:
			_advance(id, gained)
	raid_kills = []


## Items that count for a hand-in quest: found in raid and matching, from these grids.
static func hand_in_stacks(id: String, grids: Array) -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	var item: String = LIST[id].get("item", "")
	for grid: GridInventory in grids:
		for stack in grid.stacks:
			if stack.found and _matches(item, stack.id):
				out.append(stack)
	return out


static func hand_in_count(id: String, grids: Array) -> int:
	var total := 0
	for stack in hand_in_stacks(id, grids):
		total += stack.count
	return total


## Hands in what's still needed (or what you have of it) from `grids`. Returns how many were handed in.
static func hand_in(id: String, grids: Array) -> int:
	var picks := []
	for grid: GridInventory in grids:
		for stack: ItemStack in hand_in_stacks(id, [grid]):
			picks.append([grid, stack, stack.count])
	return hand_in_picked(id, picks)


## What's still needed for a hand-in quest.
static func needed(id: String) -> int:
	return int(LIST[id]["count"]) - progress(id)


## Hands in the picked items ([[grid, stack, how many], ...]; 0.16.14, the hand-in window), up to what's still
## needed. Part of a quest can be handed in and the rest later. Returns how many were handed in.
static func hand_in_picked(id: String, picks: Array) -> int:
	if not open_quests().has(id) or LIST[id]["kind"] != "hand_in":
		return 0
	var need := needed(id)
	var given := 0
	for pick: Array in picks:
		var grid: GridInventory = pick[0]
		var stack: ItemStack = pick[1]
		if given >= need or not stack.found or not _matches(LIST[id]["item"], stack.id) or not grid.stacks.has(stack):
			continue
		var take := mini(mini(int(pick[2]), stack.count), need - given)
		if take <= 0:
			continue
		stack.count -= take
		given += take
		if stack.count <= 0:
			grid.remove(stack)
		else:
			grid.changed.emit()
	if given > 0:
		_advance(id, given)
	return given


static func _matches(item: String, id: String) -> bool:
	if item.begins_with("kind:"):
		return ItemDB.kind(id) in item.trim_prefix("kind:").split(",")
	return item == id


static func _advance(id: String, amount: int) -> void:
	var count := int(LIST[id]["count"])
	var now := mini(progress(id) + amount, count)
	Profile.quest_progress[id] = now
	if now >= count and not Profile.quests_done.has(id):
		Profile.quests_done.append(id)
		Profile.money += int(LIST[id]["reward"])
		just_finished.append(id)
