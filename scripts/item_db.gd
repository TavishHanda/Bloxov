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
##       "weapon" (Primary/Secondary slot), "armor" (Armor slot), "backpack" (Backpack slot; "grid" = its inventory size)
## w/h: size in grid cells (before rotation). stack: how many fit in one cell stack. value: price of ONE.
const ITEMS := {
	"rifle_ammo": {"name": "Rifle Rounds", "short": "5.45", "kind": "ammo", "rarity": "common", "w": 1, "h": 1, "stack": 120, "value": 3},
	"pistol_ammo": {"name": "Pistol Rounds", "short": "9mm", "kind": "ammo", "rarity": "common", "w": 1, "h": 1, "stack": 50, "value": 2},
	"ak": {"name": "AK Rifle", "short": "AK", "kind": "weapon", "slot": "primary", "rarity": "uncommon", "w": 4, "h": 2, "stack": 1, "value": 2500,
		"model": "rifle", "ammo": "rifle_ammo", "auto": true, "damage": 28, "head": 2.0, "rpm": 600, "mag": 30, "reload": 1.6,
		"spread": 0.15, "hip_spread": 0.68, "move_spread": 0.75, "ads_time": 0.28, "ads_fov": 55.0,
		"bloom": 0.12, "max_bloom": 1.2, "recoil": 1.2, "recoil_yaw": 0.45, "noise": 25.0},
	"pistol": {"name": "Pistol", "kind": "weapon", "slot": "secondary", "rarity": "common", "w": 2, "h": 1, "stack": 1, "value": 600,
		"model": "pistol", "ammo": "pistol_ammo", "auto": false, "damage": 17, "head": 2.5, "rpm": 360, "mag": 12, "reload": 1.2,
		"spread": 0.3, "hip_spread": 0.5, "move_spread": 0.5, "ads_time": 0.16, "ads_fov": 66.0,
		"bloom": 0.3, "max_bloom": 1.5, "recoil": 1.2, "recoil_yaw": 0.3, "noise": 18.0},
	"armor_light": {"name": "Light Armor", "short": "Lt Armor", "kind": "armor", "rarity": "uncommon", "w": 3, "h": 3, "stack": 1, "value": 1500, "reduction": 0.2},
	"armor_heavy": {"name": "Heavy Armor", "short": "Hv Armor", "kind": "armor", "rarity": "rare", "w": 3, "h": 3, "stack": 1, "value": 4000, "reduction": 0.4},
	"backpack_small": {"name": "Small Backpack", "short": "Sm Pack", "kind": "backpack", "rarity": "common", "w": 3, "h": 3, "stack": 1, "value": 400, "grid": [4, 3]},
	"backpack_medium": {"name": "Medium Backpack", "short": "Md Pack", "kind": "backpack", "rarity": "uncommon", "w": 3, "h": 3, "stack": 1, "value": 900, "grid": [5, 4]},
	"backpack_large": {"name": "Large Backpack", "short": "Lg Pack", "kind": "backpack", "rarity": "rare", "w": 4, "h": 4, "stack": 1, "value": 2000, "grid": [6, 5]},
	"bandage": {"name": "Bandage", "kind": "heal", "rarity": "common", "w": 1, "h": 1, "stack": 5, "value": 100, "heal": 25, "use_time": 2.0},
	"medkit": {"name": "Medkit", "kind": "heal", "rarity": "uncommon", "w": 2, "h": 2, "stack": 1, "value": 400, "heal": 70, "use_time": 4.0},
	"beans": {"name": "Canned Beans", "short": "Beans", "kind": "valuable", "rarity": "common", "w": 1, "h": 1, "stack": 1, "value": 150},
	"duct_tape": {"name": "Duct Tape", "short": "Tape", "kind": "valuable", "rarity": "common", "w": 1, "h": 1, "stack": 1, "value": 300},
	"scrap": {"name": "Scrap Metal", "short": "Scrap", "kind": "valuable", "rarity": "common", "w": 2, "h": 1, "stack": 1, "value": 250},
	"phone": {"name": "Old Phone", "short": "Phone", "kind": "valuable", "rarity": "uncommon", "w": 1, "h": 1, "stack": 1, "value": 800},
	"battery": {"name": "Car Battery", "kind": "valuable", "rarity": "uncommon", "w": 2, "h": 2, "stack": 1, "value": 1200},
	"gold_watch": {"name": "Gold Watch", "short": "Watch", "kind": "valuable", "rarity": "rare", "w": 1, "h": 1, "stack": 1, "value": 2500},
	"laptop": {"name": "Laptop", "kind": "valuable", "rarity": "rare", "w": 2, "h": 1, "stack": 1, "value": 4000},
	"mil_chip": {"name": "Military Chip", "short": "Chip", "kind": "valuable", "rarity": "epic", "w": 1, "h": 1, "stack": 1, "value": 7500},
	"vase": {"name": "Antique Vase", "kind": "valuable", "rarity": "epic", "w": 2, "h": 2, "stack": 1, "value": 9000},
	"crystal": {"name": "Rare Crystal", "short": "Crystal", "kind": "valuable", "rarity": "legendary", "w": 1, "h": 1, "stack": 1, "value": 18000},
	"golden_toilet": {"name": "Golden Toilet", "kind": "valuable", "rarity": "legendary", "w": 2, "h": 3, "stack": 1, "value": 50000},
}

## Weights. A key is either an item id or a rarity (= a random valuable of that rarity).
const LOOT_TABLES := {
	"crate": {"pistol_ammo": 8, "backpack_small": 2, "rifle_ammo": 30, "bandage": 18, "medkit": 4, "common": 30, "uncommon": 12, "rare": 3},
	"locker": {"pistol": 5, "armor_light": 4, "backpack_small": 3, "backpack_medium": 2, "pistol_ammo": 6, "rifle_ammo": 15, "bandage": 10, "medkit": 12, "common": 18, "uncommon": 25, "rare": 15, "epic": 4},
	"safe": {"armor_heavy": 6, "backpack_large": 4, "uncommon": 15, "rare": 40, "epic": 30, "legendary": 15},
	"scav": {"pistol": 4, "pistol_ammo": 10, "rifle_ammo": 40, "bandage": 20, "medkit": 6, "common": 20, "uncommon": 10, "rare": 4},
	"raider": {"pistol": 5, "armor_light": 5, "backpack_medium": 3, "pistol_ammo": 6, "rifle_ammo": 30, "bandage": 12, "medkit": 12, "common": 12, "uncommon": 20, "rare": 10, "epic": 2},
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


static func roll(table: String) -> String:
	var weights: Dictionary = LOOT_TABLES[table]
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
