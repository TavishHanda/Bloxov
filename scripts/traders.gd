class_name Traders
extends RefCounted
## The hideout's traders (0.16.0, Economy update, owner): one per kind of goods, each with levels that unlock
## better stock. A trader levels up from the money you've spent with them (Profile.trader_spent), so progress is
## access to gear, not power. Each trader buys back its own kinds of items; valuables go to the valuables trader.
## Names are placeholders until the owner picks them.

const BUY_MARKUP := 1.2
## What a trader pays for gear (guns, meds, supplies); valuables sell for full value.
const GEAR_SELL_RATE := 0.6

## id -> name, its tab label and blurb in the hideout, the kinds it buys, sell rate, and its levels. Each level: money spent to reach it, and the stock it
## adds ([item id, amount per purchase]). Level 1 is open from the start.
const LIST := {
	"guns": {"name": "Gunsmith", "tab": "GUNS", "about": "Guns, ammo, attachments, grenades.", "kinds": ["weapon", "attachment", "ammo", "throwable"], "rate": GEAR_SELL_RATE,
		"levels": [
			{"spent": 0, "stock": [["pistol", 1], ["smg", 1], ["shotgun", 1], ["pistol_ammo", 50], ["smg_ammo", 60],
				["shells", 12], ["red_dot", 1], ["choke", 1]]},
			{"spent": 15000, "stock": [["ak", 1], ["rifle_ammo", 60], ["foregrip", 1], ["ext_mag", 1], ["grenade", 1]]},
			{"spent": 40000, "stock": [["sniper", 1], ["sniper_ammo", 10], ["scope_4x", 1], ["scope_8x", 1], ["suppressor", 1]]},
		]},
	"meds": {"name": "Medic", "tab": "MEDS", "about": "Bandages and medkits.", "kinds": ["heal"], "rate": GEAR_SELL_RATE,
		"levels": [
			{"spent": 0, "stock": [["bandage", 1]]},
			{"spent": 3000, "stock": [["medkit", 1]]},
		]},
	"supplies": {"name": "Supplier", "tab": "GEAR", "about": "Armor, helmets, backpacks, drinks, stash space.", "kinds": ["armor", "helmet", "backpack", "drink"], "rate": GEAR_SELL_RATE,
		"levels": [
			{"spent": 0, "stock": [["backpack_small", 1], ["energy_drink", 1]]},
			{"spent": 5000, "stock": [["backpack_medium", 1], ["armor_light", 1], ["helmet_basic", 1]]},
		]},
	"valuables": {"name": "Fence", "tab": "LOOT", "about": "Buys valuables and keys at full value. Sells nothing.", "kinds": ["valuable", "key"], "rate": 1.0, "levels": [{"spent": 0, "stock": []}]},
}


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
static func level(trader: String, spent: int) -> int:
	var levels: Array = LIST[trader]["levels"]
	var reached := 1
	for i in levels.size():
		if spent >= int(levels[i]["spent"]):
			reached = i + 1
	return reached


static func max_level(trader: String) -> int:
	return LIST[trader]["levels"].size()


## Money still to spend for the next level, or 0 at the top.
static func next_level_cost(trader: String, spent: int) -> int:
	var lv := level(trader, spent)
	if lv >= max_level(trader):
		return 0
	return int(LIST[trader]["levels"][lv]["spent"]) - spent


## [[item id, amount, level needed], ...]: everything this trader ever sells, in level order.
static func stock(trader: String) -> Array:
	var out := []
	var levels: Array = LIST[trader]["levels"]
	for i in levels.size():
		for entry: Array in levels[i]["stock"]:
			out.append([entry[0], entry[1], i + 1])
	return out
