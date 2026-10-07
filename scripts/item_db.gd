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

## kind: "valuable" (worth money), "heal" (press H or Use), "ammo" (goes straight into your gun, takes no space)
const ITEMS := {
	"ammo": {"name": "Ammo Box", "kind": "ammo", "rarity": "common", "slots": 0, "value": 0, "amount": 60},
	"bandage": {"name": "Bandage", "kind": "heal", "rarity": "common", "slots": 1, "value": 100, "heal": 25, "use_time": 2.0},
	"medkit": {"name": "Medkit", "kind": "heal", "rarity": "uncommon", "slots": 2, "value": 400, "heal": 70, "use_time": 4.0},
	"beans": {"name": "Canned Beans", "kind": "valuable", "rarity": "common", "slots": 1, "value": 150},
	"duct_tape": {"name": "Duct Tape", "kind": "valuable", "rarity": "common", "slots": 1, "value": 300},
	"scrap": {"name": "Scrap Metal", "kind": "valuable", "rarity": "common", "slots": 2, "value": 250},
	"phone": {"name": "Old Phone", "kind": "valuable", "rarity": "uncommon", "slots": 1, "value": 800},
	"battery": {"name": "Car Battery", "kind": "valuable", "rarity": "uncommon", "slots": 2, "value": 1200},
	"gold_watch": {"name": "Gold Watch", "kind": "valuable", "rarity": "rare", "slots": 1, "value": 2500},
	"laptop": {"name": "Laptop", "kind": "valuable", "rarity": "rare", "slots": 2, "value": 4000},
	"mil_chip": {"name": "Military Chip", "kind": "valuable", "rarity": "epic", "slots": 1, "value": 7500},
	"vase": {"name": "Antique Vase", "kind": "valuable", "rarity": "epic", "slots": 3, "value": 9000},
	"crystal": {"name": "Rare Crystal", "kind": "valuable", "rarity": "legendary", "slots": 1, "value": 18000},
	"golden_toilet": {"name": "Golden Toilet", "kind": "valuable", "rarity": "legendary", "slots": 4, "value": 50000},
}

## Weights. A key is either an item id or a rarity (= a random valuable of that rarity).
const LOOT_TABLES := {
	"crate": {"ammo": 30, "bandage": 18, "medkit": 4, "common": 30, "uncommon": 12, "rare": 3},
	"locker": {"ammo": 15, "bandage": 10, "medkit": 12, "common": 18, "uncommon": 25, "rare": 15, "epic": 4},
	"safe": {"uncommon": 15, "rare": 40, "epic": 30, "legendary": 15},
	"scav": {"ammo": 40, "bandage": 20, "medkit": 6, "common": 20, "uncommon": 10, "rare": 4},
}


static func item(id: String) -> Dictionary:
	return ITEMS[id]


static func display_name(id: String) -> String:
	return ITEMS[id]["name"]


static func slots(id: String) -> int:
	return ITEMS[id]["slots"]


static func value(id: String) -> int:
	return ITEMS[id]["value"]


static func kind(id: String) -> String:
	return ITEMS[id]["kind"]


static func color(id: String) -> Color:
	return RARITY_COLORS[ITEMS[id]["rarity"]]


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
