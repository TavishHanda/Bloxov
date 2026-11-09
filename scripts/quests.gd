class_name Quests
extends RefCounted
## Trader quests (0.16.13, owner: "quests instead of buying items to unlock items"). Each trader level past the first
## needs that level's quests done (and, for some, some money spent with the trader: Traders.LIST "spent"). Only the
## quests for a trader's next level are open. Kills and extracts only count once you get out alive (owner); hand-ins
## take items found in raid (ItemStack.found) from your stash and loadout. Every quest pays a small reward.
## No quests for killing other players (owner). Names and text are placeholders until the owner renames them.

## kind "kill": `target` is the AI's scene name (scav, sniper, raider, boss; none = any), optional `weapon` = the gun's item id.
## kind "hand_in": `item` is an item id, or "kind:a,b" for any item of those kinds.
## kind "extract": get out alive, optionally carrying at least `min_value` of loot, or at the extract `at` (its node name).
## kind "visit": search a container in `place` (a container's place metadata; "BankVault" = a locked one in the bank).
## kind "streak": get out alive `count` raids in a row; dying or leaving starts it again.
## A kill quest's `tag` asks for a certain kind of kill: "quiet" (a suppressor on the gun), "far" (FAR_KILL m or more
## out) or "grenade".
##
## Jobs (0.31.15, owner OK'd the list): "level" 0. One-time side quests that pay money (and `items`: [[id, amount]])
## but unlock nothing. Each trader shows one job at a time, in list order, from the start. Their items wait at the
## trader until there's room in the stash (Profile.rewards_taken). Ming has no jobs (owner).
const LIST := {
	"zeroing_in": {"trader": "guns", "level": 2, "name": "Zeroing In", "text": "Kill 5 scavs, then extract.",
		"kind": "kill", "target": "scav", "count": 5, "reward": 2000},
	"spare_parts": {"trader": "guns", "level": 2, "name": "Spare Parts", "text": "Hand in 2 attachments found in raid.",
		"kind": "hand_in", "item": "kind:attachment", "count": 2, "reward": 3000},
	"field_test": {"trader": "guns", "level": 3, "name": "Field Test", "text": "Kill 3 scavs with a Mauler, then extract.",
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
	# --- Jobs (0.31.15) ---
	"quiet_work": {"trader": "guns", "level": 0, "name": "Quiet Work", "text": "Kill 5 scavs with a suppressor on your gun, then extract.",
		"kind": "kill", "target": "scav", "tag": "quiet", "count": 5, "reward": 6000},
	"long_shot": {"trader": "guns", "level": 0, "name": "Long Shot", "text": "Kill 3 enemies from 75 m or farther, then extract.",
		"kind": "kill", "tag": "far", "count": 3, "reward": 4000, "items": [["scope_4x", 1]]},
	"gun_show": {"trader": "guns", "level": 0, "name": "Gun Show", "text": "Hand in 3 guns found in raid.",
		"kind": "hand_in", "item": "kind:weapon", "count": 3, "reward": 8000, "items": [["suppressor", 1]]},
	"powder_keg": {"trader": "guns", "level": 0, "name": "Powder Keg", "text": "Hand in 3 Powder Tins found in raid.",
		"kind": "hand_in", "item": "gunpowder", "count": 3, "reward": 3000, "items": [["grenade", 2]]},
	"close_quarters": {"trader": "guns", "level": 0, "name": "Close Quarters", "text": "Kill 2 Raiders with a Mauler, then extract.",
		"kind": "kill", "target": "raider", "weapon": "shotgun", "count": 2, "reward": 7000},
	"restock": {"trader": "meds", "level": 0, "name": "Restock", "text": "Hand in 4 Medical Supplies found in raid.",
		"kind": "hand_in", "item": "med_supplies", "count": 4, "reward": 0, "items": [["medkit", 2]]},
	"pharmacy_run": {"trader": "meds", "level": 0, "name": "Pharmacy Run", "text": "Search something in the Pharmacy, then extract.",
		"kind": "visit", "place": "Pharmacy", "count": 1, "reward": 3000},
	"clean_record": {"trader": "meds", "level": 0, "name": "Clean Record", "text": "Extract 3 raids in a row without dying.",
		"kind": "streak", "count": 3, "reward": 5000, "items": [["medkit", 2]]},
	"fuel_run": {"trader": "supplies", "level": 0, "name": "Fuel Run", "text": "Hand in 3 Fuel Cans found in raid.",
		"kind": "hand_in", "item": "fuel_can", "count": 3, "reward": 4000},
	"scrap_collector": {"trader": "supplies", "level": 0, "name": "Scrap Collector", "text": "Hand in 6 Scrap Metal found in raid.",
		"kind": "hand_in", "item": "scrap", "count": 6, "reward": 2000, "items": [["energy_drink", 2]]},
	"battery_life": {"trader": "supplies", "level": 0, "name": "Battery Life", "text": "Hand in 2 Car Batteries found in raid.",
		"kind": "hand_in", "item": "battery", "count": 2, "reward": 4000},
	"heavy_lifting": {"trader": "supplies", "level": 0, "name": "Heavy Lifting", "text": "Extract with $25,000 of loot or more.",
		"kind": "extract", "min_value": 25000, "count": 1, "reward": 6000},
	"long_haul": {"trader": "supplies", "level": 0, "name": "Long Haul", "text": "Extract at the Highway 3 times.",
		"kind": "extract", "at": "Highway", "count": 3, "reward": 5000, "items": [["backpack_medium", 1]]},
	"pocket_change": {"trader": "valuables", "level": 0, "name": "Pocket Change", "text": "Hand in 3 Cash Bundles found in raid.",
		"kind": "hand_in", "item": "cash", "count": 3, "reward": 12000},
	"paper_trail": {"trader": "valuables", "level": 0, "name": "Paper Trail", "text": "Hand in 2 Novarra Field Reports found in raid.",
		"kind": "hand_in", "item": "intel_novarra", "count": 2, "reward": 9000},
	"trophy_shelf": {"trader": "valuables", "level": 0, "name": "Trophy Shelf", "text": "Hand in 3 Raider Dog Tags found in raid.",
		"kind": "hand_in", "item": "dog_tag", "count": 3, "reward": 5000},
	"bank_job": {"trader": "valuables", "level": 0, "name": "Bank Job", "text": "Search a safe in the bank vault, then extract.",
		"kind": "visit", "place": "BankVault", "count": 1, "reward": 8000},
	"brotherhood_secrets": {"trader": "valuables", "level": 0, "name": "Brotherhood Secrets", "text": "Hand in Exion Orders found in raid.",
		"kind": "hand_in", "item": "intel_exion", "count": 1, "reward": 14000},
	"below_the_town_hall": {"trader": "valuables", "level": 0, "name": "Below the Town Hall", "text": "Search something in the bunker, then extract.",
		"kind": "visit", "place": "Bunker", "count": 1, "reward": 10000},
}

## How far out a "far" kill is, in metres.
const FAR_KILL := 75.0

## This raid's kills, [[target, weapon, tags], ...]: they only count if you extract.
static var raid_kills: Array = []
## This raid's places ("place:Pharmacy") you searched something in: they count if you extract.
static var raid_marks: Array = []
## Quests finished by the last raid, for the hideout to announce.
static var just_finished: Array[String] = []


## Quest ids for a trader's level, in list order (level 0: the trader's jobs).
static func for_level(trader: String, level: int) -> Array[String]:
	var out: Array[String] = []
	for id: String in LIST:
		if LIST[id]["trader"] == trader and int(LIST[id]["level"]) == level:
			out.append(id)
	return out


static func is_job(id: String) -> bool:
	return int(LIST[id]["level"]) == 0


## A trader's job you can do now: the first one in the list not done yet ("" when they're all done).
static func current_job(trader: String, done: Array = Profile.quests_done) -> String:
	for id in for_level(trader, 0):
		if not done.has(id):
			return id
	return ""


## Whether a quest is open, for a trader at level `level` with `done` finished (also used on the server's profiles).
static func is_open(id: String, level: int, done: Array) -> bool:
	if done.has(id):
		return false
	if is_job(id):
		return current_job(LIST[id]["trader"], done) == id
	return int(LIST[id]["level"]) == level + 1


## A trader's open quests: those for their next level, then their current job.
static func open_for(trader: String) -> Array[String]:
	var out: Array[String] = []
	for id in for_level(trader, Profile.trader_level(trader) + 1):
		if not Profile.quests_done.has(id):
			out.append(id)
	var job := current_job(trader)
	if job != "":
		out.append(job)
	return out


## The quests you can work on now: each trader's for their next level, and their current job.
static func open_quests() -> Array[String]:
	var out: Array[String] = []
	for trader: String in Traders.LIST:
		out.append_array(open_for(trader))
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


## A new raid: forget the last one's kills and places.
static func raid_started() -> void:
	raid_kills = []
	raid_marks = []


## You killed an AI (`target` = its scene name) with `weapon` (item id, "" if unknown). `tags`: "quiet", "far",
## "grenade".
static func record_kill(target: String, weapon: String, tags: Array = []) -> void:
	raid_kills.append([target, weapon, tags])


## The tags for a kill: from `shooter` at `from` to the victim at `to`, `quiet` when a suppressor was on.
static func kill_tags(from: Vector3, to: Vector3, quiet: bool) -> Array:
	var tags := []
	if quiet:
		tags.append("quiet")
	if from.distance_to(to) >= FAR_KILL:
		tags.append("far")
	return tags


## What searching this container counts as: ["place:Pharmacy"], and "place:BankVault" for a locked one in the bank.
static func marks_of(box: Node) -> Array:
	var place := String(box.get_meta("place", "")) if box != null else ""
	if place == "":
		return []
	var out := ["place:" + place]
	if place == "Bank" and box.get_meta("locked", false):
		out.append("place:BankVault")
	return out


## You searched (or opened) a container this raid.
static func searched(box: Node) -> void:
	for mark: String in marks_of(box):
		if not raid_marks.has(mark):
			raid_marks.append(mark)


## Whether a kill [target, weapon, tags] counts for a kill quest.
static func kill_counts(quest: Dictionary, kill: Array) -> bool:
	var tags: Array = kill[2] if kill.size() > 2 and kill[2] is Array else []
	return (not quest.has("target") or kill[0] == quest["target"]) and (not quest.has("weapon") or kill[1] == quest["weapon"]) \
		and (not quest.has("tag") or tags.has(quest["tag"]))


## What an extract adds to a quest: `kills` and `marks` from the raid, `loot_value` brought out, at extract `at`.
static func gain(quest: Dictionary, kills: Array, marks: Array, loot_value: int, at: String) -> int:
	match quest["kind"]:
		"kill":
			return kills.filter(func(kill: Variant) -> bool: return kill is Array and kill.size() >= 2 and kill_counts(quest, kill)).size()
		"extract":
			return 1 if loot_value >= int(quest.get("min_value", 0)) and (not quest.has("at") or quest["at"] == at) else 0
		"visit":
			return 1 if marks.has("place:" + String(quest["place"])) else 0
		"streak":
			return 1
	return 0


## What this raid adds to a quest once you get out (for the quest tracker, 0.17.1): its kills and places that count,
## or 1 for an extract quest without a loot target or extract, or a streak.
static func this_raid(id: String) -> int:
	var quest: Dictionary = LIST[id]
	if quest["kind"] == "extract" and (quest.has("min_value") or quest.has("at")):
		return 0
	return gain(quest, raid_kills, raid_marks, 0, "")


## The raid is over. Extracted (at `at`, the extract's node name): its kills, places and the extract count toward
## open quests. Not: streaks start again.
static func raid_ended(extracted: bool, loot_value: int, at := "") -> void:
	just_finished = []
	if not extracted:
		for id in open_quests():
			if LIST[id]["kind"] == "streak":
				Profile.quest_progress.erase(id)
		raid_kills = []
		raid_marks = []
		return
	for id in open_quests():
		var gained := gain(LIST[id], raid_kills, raid_marks, loot_value, at)
		if gained > 0:
			_advance(id, gained)
	raid_kills = []
	raid_marks = []


## What a quest pays: "$6,000", "$4,000 + 4x Scope", "2 Medkits".
static func reward_text(id: String) -> String:
	var parts: Array[String] = []
	if int(LIST[id]["reward"]) > 0:
		parts.append(ItemDB.money(int(LIST[id]["reward"])))
	for entry: Array in LIST[id].get("items", []):
		parts.append(ItemDB.display_name(entry[0]) if int(entry[1]) == 1 else "%d x %s" % [int(entry[1]), ItemDB.display_name(entry[0])])
	return " + ".join(parts)


## Finished quests whose items haven't gone in the stash yet.
static func rewards_waiting() -> Array[String]:
	var out: Array[String] = []
	for id in Profile.quests_done:
		if LIST.has(id) and not LIST[id].get("items", []).is_empty() and not Profile.rewards_taken.has(id):
			out.append(id)
	return out


## Puts waiting reward items in `stash` (all of a quest's or none). Returns [quests given, quests still waiting].
static func give_rewards(stash: GridInventory) -> Array:
	var given: Array[String] = []
	var waiting: Array[String] = []
	for id in rewards_waiting():
		# (checked on a copy first, each item in a spot of its own, so a quest's items go in all together)
		var trial := GridInventory.new("Trial", stash.width, stash.height)
		trial.stacks = stash.stacks.duplicate()
		var fits := true
		for entry: Array in LIST[id]["items"]:
			for i in int(entry[1]):
				var spot := trial.find_spot(entry[0])
				if spot.is_empty():
					fits = false
					break
				trial.stacks.append(ItemStack.new(entry[0], 1, spot[0], spot[1], spot[2]))
		if not fits:
			waiting.append(id)
			continue
		for entry: Array in LIST[id]["items"]:
			stash.add(entry[0], int(entry[1]))
		Profile.rewards_taken.append(id)
		given.append(id)
	return [given, waiting]


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
