class_name ItemDB
extends RefCounted
## Every item in the game, plus the loot tables containers roll from.
## To add an item, add an entry to ITEMS. Valuables are picked up by loot tables automatically by rarity.

const RARITY_COLORS := {
	"common": Color(0.82, 0.82, 0.82),
	"uncommon": Color(0.4, 0.9, 0.4),
	"rare": Color(0.4, 0.65, 1.0),
	"epic": Color(0.8, 0.45, 1.0),
	"legendary": Color(1.0, 0.72, 0.15),
}

## kind: "valuable" (worth money), "heal" (press H or Use), "ammo" (loaded into guns when you reload),
##       "weapon" (Primary/Secondary slot), "armor" (Armor slot), "backpack" (Backpack slot; "grid" = its inventory size),
##       "key" (opens the key door named by "door"; carry it anywhere on you)
## w/h: size in grid cells (before rotation). stack: how many fit in one cell stack. value: price of ONE (new).
## desc: the line the inventory shows about it.
## durability (0.14.0): armor points (hits wear it down, worn armor protects less) or a key's uses. Each item keeps
## its own (ItemStack.durability); worn items are worth less (ItemStack.value).
const ITEMS := {
	"rifle_ammo": {"name": "Rifle Rounds", "desc": "Rifle rounds for the AK. Loaded when you reload.", "short": "5.45", "kind": "ammo", "rarity": "common", "w": 1, "h": 1, "stack": 120, "value": 3},
	"pistol_ammo": {"name": "Pistol Rounds", "desc": "Pistol rounds. Loaded when you reload.", "short": "9mm", "kind": "ammo", "rarity": "common", "w": 1, "h": 1, "stack": 50, "value": 2},
	"ak": {"name": "AK Rifle", "desc": "Old army rifle, full auto. Hits hard, kicks harder.", "short": "AK", "kind": "weapon", "slot": "primary", "rarity": "uncommon", "w": 4, "h": 2, "stack": 1, "value": 2500,
		"model": "rifle", "ammo": "rifle_ammo", "auto": true, "damage": 28, "head": 2.0, "rpm": 600, "mag": 30, "reload": 1.6,
		"spread": 0.15, "hip_spread": 0.68, "move_spread": 0.75, "ads_time": 0.28, "ads_fov": 55.0,
		"bloom": 0.12, "max_bloom": 1.2, "recoil": 1.2, "recoil_yaw": 0.45, "noise": 35.0},
	"pistol": {"name": "Pistol", "desc": "Small sidearm. Quick to aim, one shot per click.", "kind": "weapon", "slot": "secondary", "rarity": "common", "w": 2, "h": 1, "stack": 1, "value": 600,
		"model": "pistol", "ammo": "pistol_ammo", "auto": false, "damage": 17, "head": 2.5, "rpm": 360, "mag": 12, "reload": 1.2,
		"spread": 0.3, "hip_spread": 0.5, "move_spread": 0.5, "ads_time": 0.16, "ads_fov": 66.0,
		"bloom": 0.3, "max_bloom": 1.5, "recoil": 1.2, "recoil_yaw": 0.3, "noise": 25.0},
	"armor_light": {"name": "Light Armor", "desc": "Soft vest. Wears down as it takes hits, and protects less as it does.", "short": "Lt Armor", "kind": "armor", "rarity": "uncommon", "w": 3, "h": 3, "stack": 1, "value": 1500, "reduction": 0.2, "durability": 60},
	"armor_heavy": {"name": "Heavy Armor", "desc": "Plated vest. Stops a lot, wears down as it takes hits.", "short": "Hv Armor", "kind": "armor", "rarity": "rare", "w": 3, "h": 3, "stack": 1, "value": 4000, "reduction": 0.4, "durability": 120},
	"backpack_small": {"name": "Small Backpack", "desc": "A school bag. Better than pockets.", "short": "Sm Pack", "kind": "backpack", "rarity": "common", "w": 3, "h": 3, "stack": 1, "value": 400, "grid": [4, 3]},
	"backpack_medium": {"name": "Medium Backpack", "desc": "Hiking pack with room for a good haul.", "short": "Md Pack", "kind": "backpack", "rarity": "uncommon", "w": 3, "h": 3, "stack": 1, "value": 900, "grid": [5, 4]},
	"backpack_large": {"name": "Large Backpack", "desc": "Big army rucksack. Carry everything home.", "short": "Lg Pack", "kind": "backpack", "rarity": "rare", "w": 4, "h": 4, "stack": 1, "value": 2000, "grid": [6, 5]},
	"bandage": {"name": "Bandage", "desc": "Stops the bleeding. Quick to use.", "kind": "heal", "rarity": "common", "w": 1, "h": 1, "stack": 5, "value": 100, "heal": 25, "use_time": 2.0},
	"medkit": {"name": "Medkit", "desc": "Field kit. Heals a lot, takes a while.", "kind": "heal", "rarity": "uncommon", "w": 2, "h": 2, "stack": 1, "value": 400, "heal": 70, "use_time": 4.0},
	"bunker_key": {"name": "Bunker Key", "short": "Bunker", "desc": "Opens the bunker under the town hall. Bon keeps one on him. 3 uses.",
		"kind": "key", "door": "BunkerDoor", "rarity": "epic", "w": 1, "h": 1, "stack": 1, "value": 6000, "durability": 3},
	"bank_vault_key": {"name": "Bank Vault Key", "short": "Vault", "desc": "Opens the vault in the bank. 5 uses.",
		"kind": "key", "door": "BankVaultDoor", "rarity": "rare", "w": 1, "h": 1, "stack": 1, "value": 3500, "durability": 5},
	"beans": {"name": "Canned Beans", "desc": "Somebody's lunch. Traders pay for food out here.", "short": "Beans", "kind": "valuable", "rarity": "common", "w": 1, "h": 1, "stack": 1, "value": 150},
	"water": {"name": "Water Bottle", "short": "Water", "desc": "Clean water is rare out here. Traders pay for it.", "kind": "valuable", "rarity": "common", "w": 1, "h": 1, "stack": 1, "value": 200},
	"ration": {"name": "Ration Pack", "short": "Ration", "desc": "Novarran army meal. Tastes like cardboard, sells like gold.", "kind": "valuable", "rarity": "uncommon", "w": 1, "h": 1, "stack": 1, "value": 700},
	"duct_tape": {"name": "Duct Tape", "desc": "Fixes everything. Sells well.", "short": "Tape", "kind": "valuable", "rarity": "common", "w": 1, "h": 1, "stack": 1, "value": 300},
	"scrap": {"name": "Scrap Metal", "desc": "Bent metal. Worth a little to the right buyer.", "short": "Scrap", "kind": "valuable", "rarity": "common", "w": 2, "h": 1, "stack": 1, "value": 250},
	"phone": {"name": "Old Phone", "desc": "Cracked screen, still works. Someone wants the parts.", "short": "Phone", "kind": "valuable", "rarity": "uncommon", "w": 1, "h": 1, "stack": 1, "value": 800},
	"battery": {"name": "Car Battery", "desc": "Heavy and worth it.", "kind": "valuable", "rarity": "uncommon", "w": 2, "h": 2, "stack": 1, "value": 1200},
	"gold_watch": {"name": "Gold Watch", "desc": "Somebody's pride. Now yours.", "short": "Watch", "kind": "valuable", "rarity": "rare", "w": 1, "h": 1, "stack": 1, "value": 2500},
	"laptop": {"name": "Laptop", "desc": "Novarran office laptop. The data is worth more than the machine.", "kind": "valuable", "rarity": "rare", "w": 2, "h": 1, "stack": 1, "value": 4000},
	"cash": {"name": "Cash Bundle", "short": "Cash", "desc": "Old Novarran notes. Still good with the traders.", "kind": "valuable", "rarity": "rare", "w": 1, "h": 1, "stack": 1, "value": 3000},
	"gold_bar": {"name": "Gold Bar", "short": "Gold", "desc": "Straight from the vault.", "kind": "valuable", "rarity": "epic", "w": 1, "h": 1, "stack": 1, "value": 8000},
	"mil_chip": {"name": "Military Chip", "desc": "Exion military hardware. Very wanted.", "short": "Chip", "kind": "valuable", "rarity": "epic", "w": 1, "h": 1, "stack": 1, "value": 7500},
	"vase": {"name": "Antique Vase", "desc": "Old and fragile. Don't drop it.", "kind": "valuable", "rarity": "epic", "w": 2, "h": 2, "stack": 1, "value": 9000},
	"crystal": {"name": "Rare Crystal", "desc": "Nobody knows where these come from. Everyone wants one.", "short": "Crystal", "kind": "valuable", "rarity": "legendary", "w": 1, "h": 1, "stack": 1, "value": 18000},
	"golden_toilet": {"name": "Golden Toilet", "desc": "Yes, really.", "kind": "valuable", "rarity": "legendary", "w": 2, "h": 3, "stack": 1, "value": 50000},
}

## Weights. A key is either an item id or a rarity (= a random valuable of that rarity).
const LOOT_TABLES := {
	"crate": {"pistol_ammo": 8, "backpack_small": 2, "rifle_ammo": 30, "bandage": 18, "medkit": 4, "common": 30, "uncommon": 12, "rare": 3},
	"locker": {"pistol": 5, "armor_light": 4, "backpack_small": 3, "backpack_medium": 2, "pistol_ammo": 6, "rifle_ammo": 15, "bandage": 10, "medkit": 12, "common": 18, "uncommon": 25, "rare": 15, "epic": 4},
	"safe": {"armor_heavy": 6, "backpack_large": 4, "uncommon": 15, "rare": 40, "epic": 30, "legendary": 15},
	"scav": {"pistol": 4, "pistol_ammo": 10, "rifle_ammo": 40, "bandage": 20, "medkit": 6, "common": 20, "uncommon": 10, "rare": 4},
	"raider": {"bank_vault_key": 1, "pistol": 5, "armor_light": 5, "backpack_medium": 3, "pistol_ammo": 6, "rifle_ammo": 30, "bandage": 12, "medkit": 12, "common": 12, "uncommon": 20, "rare": 10, "epic": 2},
}

## Loot by place (0.14.0, MAP_PLAN.md "Loot by place"): a container tagged with one of these places (its
## `place` metadata) rolls from its own table plus these weights, so a gun store's lockers are mostly guns.
## Places not listed (shops, offices, houses, the station...) roll the plain tables: mid loot.
const PLACE_LOOT := {
	"Bunker": {"legendary": 25, "epic": 35, "mil_chip": 10, "armor_heavy": 10, "ak": 8, "rifle_ammo": 15},
	"TownHall": {"bunker_key": 3, "uncommon": 10},
	"Bank": {"cash": 30, "gold_bar": 12, "gold_watch": 15, "rare": 10},
	"Offices": {"bank_vault_key": 4},
	"BigHouse1": {"gold_watch": 20, "cash": 15, "crystal": 3},        # jewellery
	"BigHouse2": {"laptop": 15, "phone": 25, "battery": 10},          # electronics
	"BigHouse3": {"vase": 15, "golden_toilet": 2, "epic": 8},        # antiques
	"Police": {"armor_light": 15, "armor_heavy": 4, "pistol": 15, "pistol_ammo": 20, "bunker_key": 2, "bank_vault_key": 3},
	"GunStore": {"ak": 12, "pistol": 15, "rifle_ammo": 30, "pistol_ammo": 25},
	"Pharmacy": {"bandage": 45, "medkit": 25},
	"Grocery": {"beans": 30, "water": 30, "ration": 10},
	"Diner": {"beans": 30, "water": 30, "ration": 10},
	"School": {"backpack_small": 15, "backpack_medium": 10, "backpack_large": 3, "armor_light": 5},
}


static func item(id: String) -> Dictionary:
	return ITEMS[id]


static func display_name(id: String) -> String:
	return ITEMS[id]["name"]


## Display name with a count suffix when there's more than one: "Bandage x3".
static func label(id: String, count: int) -> String:
	return display_name(id) + (" x%d" % count if count > 1 else "")


## Short label for small inventory tiles.
static func short_name(id: String) -> String:
	return ITEMS[id].get("short", ITEMS[id]["name"])


## Size in grid cells, unrotated.
static func size(id: String) -> Vector2i:
	return Vector2i(ITEMS[id]["w"], ITEMS[id]["h"])


## Size in grid cells, with width and height swapped if rotated.
static func rotated_size(id: String, rotated: bool) -> Vector2i:
	var base := size(id)
	return Vector2i(base.y, base.x) if rotated else base


static func max_stack(id: String) -> int:
	return ITEMS[id]["stack"]


## How many of an item a container/body rolls when it rolls that item.
static func roll_count(id: String) -> int:
	match id:
		"rifle_ammo":
			return randi_range(20, 60)
		"pistol_ammo":
			return randi_range(15, 40)
		"bandage":
			return randi_range(1, 2)
	return 1


static func value(id: String) -> int:
	return ITEMS[id]["value"]


static func kind(id: String) -> String:
	return ITEMS[id]["kind"]


static func color(id: String) -> Color:
	return RARITY_COLORS[ITEMS[id]["rarity"]]


## Which equipment slot an item goes in ("primary", "secondary", "armor", "backpack"), or "" if none.
static func equip_slot(id: String) -> String:
	match kind(id):
		"weapon":
			return ITEMS[id]["slot"]
		"armor":
			return "armor"
		"backpack":
			return "backpack"
	return ""


## The line the inventory shows about it.
static func description(id: String) -> String:
	return ITEMS[id].get("desc", "")


## Armor points or key uses when new (0 = it doesn't wear).
static func max_durability(id: String) -> int:
	return int(ITEMS[id].get("durability", 0))


## Durability of one found in a raid: armor turns up worn (40-100%), keys with all their uses.
static func found_durability(id: String) -> int:
	var most := max_durability(id)
	if kind(id) == "armor":
		return randi_range(ceili(most * 0.4), most)
	return most


## Rolls one item from `table`, with the place's weights on top (PLACE_LOOT) when `place` has any.
static func roll(table: String, place := "") -> String:
	var weights: Dictionary = LOOT_TABLES[table]
	if PLACE_LOOT.has(place):
		weights = weights.merged(PLACE_LOOT[place], false)
		for key in PLACE_LOOT[place]:
			if LOOT_TABLES[table].has(key):
				weights[key] = LOOT_TABLES[table][key] + PLACE_LOOT[place][key]
	var total := 0
	for weight in weights.values():
		total += weight
	var pick := randi() % total
	for key in weights:
		pick -= weights[key]
		if pick < 0:
			return key if ITEMS.has(key) else _random_valuable(key)
	return "beans"


static func _random_valuable(rarity: String) -> String:
	var options: Array[String] = []
	for id in ITEMS:
		if ITEMS[id]["kind"] == "valuable" and ITEMS[id]["rarity"] == rarity:
			options.append(id)
	return options.pick_random()


## 12345 -> "$12,345"
static func money(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if amount < 0 else "") + "$" + digits + grouped
