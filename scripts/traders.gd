class_name Traders
extends RefCounted
## The hideout's traders (0.16.0, Economy update, owner): one per kind of goods, each with levels that unlock
## better stock. A trader levels up by finishing their quests for that level (0.16.13, owner: quests, see Quests) and,
## for some levels, spending some money with them (Profile.trader_spent), so progress is access to gear, not power. Each trader buys back its own kinds of items; valuables go to the valuables trader.
## Names (owner): Ponta (guns, 0.25.4), Big Don (supplies, 0.25.4), Supreme (valuables), Ming (boxes); the Medic's is still a placeholder.

## 0.25.6 (owner): 1.56, was 1.2 (30% dearer, so a good kit takes 2-3 raids; tools/economy_sim.gd).
const BUY_MARKUP := 1.56
## What a trader pays for gear (guns, meds, supplies); valuables sell for full value.
const GEAR_SELL_RATE := 0.6

## id -> name, its tab label and blurb in the hideout, the kinds it buys, sell rate, and its levels. Each level: money spent to reach it, and the stock it
## adds ([item id, amount per purchase]). Level 1 is open from the start.
const LIST := {
	"guns": {"name": "Ponta", "tab": "GUNS", "about": "Guns, ammo, attachments, grenades.", "kinds": ["weapon", "attachment", "ammo", "throwable"], "rate": GEAR_SELL_RATE,
		"levels": [
			{"spent": 0, "stock": [["pistol", 1], ["smg", 1], ["shotgun", 1], ["pistol_ammo", 50], ["smg_ammo", 60],
				["shells", 12], ["red_dot", 1], ["choke", 1]]},
			{"spent": 15000, "stock": [["ak", 1], ["rifle_ammo", 60], ["foregrip", 1], ["ext_mag", 1], ["grenade", 1]]},
			{"spent": 40000, "stock": [["sniper", 1], ["sniper_ammo", 10], ["scope_4x", 1], ["scope_8x", 1], ["suppressor", 1]]},
		]},
	"meds": {"name": "Medic", "tab": "MEDS", "about": "Bandages and medkits.", "kinds": ["heal"], "rate": GEAR_SELL_RATE,
		"levels": [
			{"spent": 0, "stock": [["bandage", 1]]},
			{"spent": 0, "stock": [["medkit", 1]]},
		]},
	"supplies": {"name": "Big Don", "tab": "GEAR", "about": "Armor, helmets, backpacks, drinks, stash space.", "kinds": ["armor", "helmet", "backpack", "drink"], "rate": GEAR_SELL_RATE,
		"levels": [
			{"spent": 0, "stock": [["backpack_small", 1], ["energy_drink", 1]]},
			{"spent": 5000, "stock": [["backpack_medium", 1], ["armor_light", 1], ["helmet_basic", 1]]},
		]},
	"valuables": {"name": "Supreme", "tab": "LOOT", "about": "Buys valuables and keys at full value. Sells nothing.", "kinds": ["valuable", "key"], "rate": 1.0, "levels": [{"spent": 0, "stock": []}]},
	"ming": {"name": "Ming", "tab": "MING", "about": "Uncle Ming keeps the outpost entertained. Pick a box, pay, see what's inside. The odds are on every box.", "kinds": [], "rate": 1.0, "levels": [{"spent": 0, "stock": []}]},
}


## Ming's mystery boxes (0.16.2, owner): pay earned money, get one random item from the box, with every chance
## shown before you buy (STORE_RULES.md section 5; never the premium currency). A rarity key ("rare") means a random
## valuable of that rarity. Each box pays back about 80% of its price on average, so it's a money sink
## (tools/economy_sim.gd prints the numbers).
const BOXES := {
	"gun_box": {"name": "Gun Box", "price": 12000,
		"odds": {"pistol": 30, "smg": 25, "shotgun": 20, "ak": 15, "sniper": 10}},
	"gear_box": {"name": "Gear Box", "price": 10000,
		"odds": {"armor_light": 30, "helmet_basic": 25, "backpack_medium": 20, "backpack_large": 9, "armor_heavy": 8, "helmet_good": 8}},
	"loot_box": {"name": "Loot Box", "price": 3500,
		"odds": {"common": 30, "uncommon": 30, "rare": 25, "epic": 12, "legendary": 3}},
}


## Rolls one of Ming's boxes: an item id.
static func open_box(box: String) -> String:
	var odds: Dictionary = BOXES[box]["odds"]
	var total := 0
	for weight: int in odds.values():
		total += weight
	var pick := randi() % total
	for key: String in odds:
		pick -= odds[key]
		if pick < 0:
			return key if ItemDB.ITEMS.has(key) else ItemDB._random_valuable(key)
	return odds.keys()[0]


## [[label, percent], ...] for showing a box's odds.
static func box_odds(box: String) -> Array:
	var odds: Dictionary = BOXES[box]["odds"]
	var total := 0
	for weight: int in odds.values():
		total += weight
	var out := []
	for key: String in odds:
		var label := ItemDB.display_name(key) if ItemDB.ITEMS.has(key) else "%s valuable" % key.capitalize()
		out.append([label, 100.0 * odds[key] / total])
	return out


static func buy_price(id: String, amount: int) -> int:
	return ceili(ItemDB.value(id) * amount * BUY_MARKUP)


## What the trader that buys this kind of item pays for it.
static func sell_price(stack: ItemStack) -> int:
	return roundi(stack.value() * float(LIST[buyer_for(stack.id)]["rate"]))


## The trader that buys this item back.
static func buyer_for(id: String) -> String:
	var kind := ItemDB.kind(id)
	for trader: String in LIST:
		if kind in LIST[trader]["kinds"]:
			return trader
	return "valuables"


## The trader that sells this item at some level, or "" if it's loot-only.
static func trader_for(id: String) -> String:
	for trader: String in LIST:
		for level: Dictionary in LIST[trader]["levels"]:
			for entry: Array in level["stock"]:
				if entry[0] == id:
					return trader
	return ""


## The trader's level (1-based) after spending `spent` with them.
## `done`: finished quest ids. Each level needs the one before it, its quests done and its money spent.
static func level(trader: String, spent: int, done: Array = []) -> int:
	var levels: Array = LIST[trader]["levels"]
	var reached := 1
	for i in range(1, levels.size()):
		if spent < int(levels[i]["spent"]) or not Quests.for_level(trader, i + 1).all(func(id: String) -> bool: return done.has(id)):
			break
		reached = i + 1
	return reached


static func max_level(trader: String) -> int:
	return LIST[trader]["levels"].size()


## Money still to spend for the level after `lv` (on top of its quests), or 0 at the top or when it's already spent.
static func next_level_cost(trader: String, lv: int, spent: int) -> int:
	if lv >= max_level(trader):
		return 0
	return maxi(int(LIST[trader]["levels"][lv]["spent"]) - spent, 0)


## [[item id, amount, level needed], ...]: everything this trader ever sells, in level order.
static func stock(trader: String) -> Array:
	var out := []
	var levels: Array = LIST[trader]["levels"]
	for i in levels.size():
		for entry: Array in levels[i]["stock"]:
			out.append([entry[0], entry[1], i + 1])
	return out
