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
##       "throwable" (a grenade: bound to key 4 when picked up, thrown with it), "drink" (Use: an energy drink's
##       stamina boost for "boost_time" seconds), "helmet" (Helmet slot; "reduction" applies to hits on the head), "key" (opens the key door named by "door"; carry it anywhere on you)
## w/h: size in grid cells (before rotation). stack: how many fit in one cell stack. value: price of ONE (new).
## desc: the line the inventory shows about it.
## durability: armor points (hits wear it down, worn armor protects less) or a key's uses. Each item keeps its own
## (ItemStack.durability); worn items are worth less (ItemStack.value). No item has one for now (owner, 0.14.3:
## durability is its own update later); the code is ready for when it comes.
const ITEMS := {
	"rifle_ammo": {"name": "Rifle Rounds", "desc": "Rifle rounds for the Hound. Loaded when you reload.", "short": "5.45", "kind": "ammo", "rarity": "common", "w": 1, "h": 1, "stack": 120, "value": 3},
	"pistol_ammo": {"name": "Pistol Rounds", "desc": "Pistol rounds for the Stinger. Loaded when you reload.", "short": "9mm", "kind": "ammo", "rarity": "common", "w": 1, "h": 1, "stack": 50, "value": 2},
	# One ammo per gun type (owner, 0.15.4: the SMG gets its own).
	"smg_ammo": {"name": "SMG Rounds", "desc": "Small rounds for the Wasp. Loaded when you reload.", "short": "SMG", "kind": "ammo", "rarity": "common", "w": 1, "h": 1, "stack": 90, "value": 2},
	"shells": {"name": "Shotgun Shells", "desc": "Buckshot for the Mauler. Loaded one at a time.", "short": "Shells", "kind": "ammo", "rarity": "common", "w": 1, "h": 1, "stack": 30, "value": 6},
	"sniper_ammo": {"name": "Sniper Rounds", "desc": "Long rounds for the Lancer. Loaded when you reload.", "short": "Sniper", "kind": "ammo", "rarity": "uncommon", "w": 1, "h": 1, "stack": 30, "value": 15},
	"ak": {"name": "Hound", "desc": "Old army rifle, full auto. Hits hard, kicks harder.", "short": "Hound", "kind": "weapon", "slot": "primary", "rarity": "uncommon", "w": 4, "h": 2, "stack": 1, "value": 2500,
		"model": "rifle", "ammo": "rifle_ammo", "auto": true, "damage": 28, "head": 2.0, "rpm": 600, "mag": 30, "reload": 1.6,
		"spread": 0.15, "hip_spread": 0.68, "move_spread": 0.75, "ads_time": 0.28, "ads_fov": 55.0,
		"bloom": 0.12, "max_bloom": 1.2, "recoil": 1.2, "recoil_yaw": 0.45, "noise": 35.0,
		"slots": ["scope", "barrel", "grip", "mag"]},
	"pistol": {"name": "Stinger", "desc": "Small sidearm. Quick to aim, one shot per click.", "kind": "weapon", "slot": "secondary", "rarity": "common", "w": 2, "h": 1, "stack": 1, "value": 600,
		"model": "pistol", "ammo": "pistol_ammo", "auto": false, "damage": 17, "head": 2.5, "rpm": 360, "mag": 12, "reload": 1.2,
		"spread": 0.3, "hip_spread": 0.5, "move_spread": 0.5, "ads_time": 0.16, "ads_fov": 66.0,
		"bloom": 0.3, "max_bloom": 1.5, "recoil": 1.2, "recoil_yaw": 0.3, "noise": 25.0,
		"slots": ["barrel", "sight"]},
	# The Guns update's new guns (0.15.4, owner OK'd names and numbers; tune after playing). Made-up names, no real
	# brands (STORE_RULES.md). Optional stats: "pellets" + "pellet_spread" (degrees: a shotgun fires that many at
	# once, each doing "damage"), "falloff" [from m, to m, damage multiplier at the far end and beyond],
	# "load_one" (reload is per round: "reload" seconds each, and firing stops it), "flash" (muzzle flash size),
	# "shot_pitch"/"shot_db" (its shot sound), "cycle" ("pump"/"bolt": worked between shots, 0.15.6).
	"smg": {"name": "Wasp", "desc": "Small and fast. Sprays at close range, weak far away.", "short": "Wasp", "kind": "weapon", "slot": "primary", "rarity": "uncommon", "w": 3, "h": 2, "stack": 1, "value": 2000,
		"model": "smg", "ammo": "smg_ammo", "auto": true, "damage": 20, "head": 2.0, "rpm": 900, "mag": 30, "reload": 1.4,
		"spread": 0.25, "hip_spread": 0.45, "move_spread": 0.45, "ads_time": 0.2, "ads_fov": 62.0,
		"bloom": 0.1, "max_bloom": 1.3, "recoil": 0.7, "recoil_yaw": 0.4, "noise": 28.0, "falloff": [25.0, 50.0, 0.7], "flash": 0.8, "shot_db": -6.0,
		"slots": ["scope", "barrel", "grip", "mag"]},
	"shotgun": {"name": "Mauler", "desc": "Pump shotgun. Deadly up close, useless far away. Loads one shell at a time.", "short": "Mauler", "kind": "weapon", "slot": "primary", "rarity": "uncommon", "w": 4, "h": 1, "stack": 1, "value": 2200,
		"model": "shotgun", "ammo": "shells", "auto": false, "damage": 14, "head": 1.5, "rpm": 70, "mag": 6, "reload": 0.45, "load_one": true, "cycle": "pump",
		"pellets": 8, "pellet_spread": 3.0, "spread": 0.3, "hip_spread": 0.6, "move_spread": 0.6, "ads_time": 0.3, "ads_fov": 62.0,
		"bloom": 0.0, "max_bloom": 0.0, "recoil": 4.0, "recoil_yaw": 0.6, "noise": 40.0, "falloff": [12.0, 30.0, 0.4], "flash": 1.6, "shot_db": -1.0,
		"slots": ["barrel", "grip", "sight"]},
	"sniper": {"name": "Lancer", "desc": "Bolt-action sniper rifle. Two body shots or one to the head. Terrible from the hip.", "short": "Lancer", "kind": "weapon", "slot": "primary", "rarity": "rare", "w": 5, "h": 1, "stack": 1, "value": 4500,
		"model": "sniper", "ammo": "sniper_ammo", "auto": false, "cycle": "bolt", "damage": 90, "head": 2.0, "rpm": 40, "mag": 5, "reload": 2.4,
		"spread": 0.03, "hip_spread": 3.0, "move_spread": 1.5, "ads_time": 0.4, "ads_fov": 45.0,
		"bloom": 0.0, "max_bloom": 0.0, "recoil": 5.0, "recoil_yaw": 0.5, "noise": 60.0, "flash": 1.4, "shot_db": -1.0,
		"slots": ["scope", "barrel", "grip", "mag"]},
	# Attachments (0.15.1, owner's plan): each goes in one slot type of a gun ("slots" on the gun) and its "mult"
	# stats multiply the gun's (ItemDB.weapon_stats). "fits" (optional) limits it to those guns. "reticle": what you
	# see through it when aimed ("dot": a red dot; "scope": the view through a scope, the gun out of sight).
	"red_dot": {"name": "Red Dot", "desc": "Small sight with a red dot. Quicker to aim, a little more zoom.", "kind": "attachment", "rarity": "uncommon",
		"w": 1, "h": 1, "stack": 1, "value": 500, "slots": ["sight", "scope"], "mult": {"ads_time": 0.85, "ads_fov": 0.92}, "reticle": "dot"},
	"scope_4x": {"name": "4x Scope", "short": "4x", "desc": "Brings far targets close. Slower to aim.", "kind": "attachment", "rarity": "rare",
		"w": 2, "h": 1, "stack": 1, "value": 1500, "slots": ["scope"], "mult": {"ads_time": 1.2}, "set": {"ads_fov": 30.0}, "reticle": "scope"},
	"scope_8x": {"name": "8x Scope", "short": "8x", "desc": "A sniper's scope. Huge zoom, slow to aim.", "kind": "attachment", "rarity": "epic",
		"w": 2, "h": 1, "stack": 1, "value": 3000, "slots": ["scope"], "fits": ["sniper"], "mult": {"ads_time": 1.3}, "set": {"ads_fov": 14.0}, "reticle": "scope"},
	"suppressor": {"name": "Suppressor", "short": "Supp", "desc": "Your shots are heard half as far. A little less kick.", "kind": "attachment", "rarity": "rare",
		"w": 2, "h": 1, "stack": 1, "value": 1800, "slots": ["barrel"], "fits": ["pistol", "ak", "smg", "sniper"], "mult": {"noise": 0.5, "recoil": 0.9, "recoil_yaw": 0.9}},
	"choke": {"name": "Choke", "desc": "Shotgun muzzle. Keeps the pellets tighter.", "kind": "attachment", "rarity": "uncommon",
		"w": 1, "h": 1, "stack": 1, "value": 700, "slots": ["barrel"], "fits": ["shotgun"], "mult": {"pellet_spread": 0.85}},
	"foregrip": {"name": "Foregrip", "short": "Grip", "desc": "Something to hold on to. Less kick.", "kind": "attachment", "rarity": "uncommon",
		"w": 1, "h": 1, "stack": 1, "value": 800, "slots": ["grip"], "mult": {"recoil": 0.8, "recoil_yaw": 0.8}},
	"ext_mag": {"name": "Extended Mag", "short": "Ext Mag", "desc": "Holds half as many rounds again. Slower to reload.", "kind": "attachment", "rarity": "rare",
		"w": 1, "h": 1, "stack": 1, "value": 1200, "slots": ["mag"], "mult": {"mag": 1.5, "reload": 1.1}},
	"armor_light": {"name": "Light Armor", "desc": "Soft vest. Takes the edge off a hit.", "short": "Lt Armor", "kind": "armor", "rarity": "uncommon", "w": 3, "h": 3, "stack": 1, "value": 1500, "reduction": 0.2},
	"armor_heavy": {"name": "Heavy Armor", "desc": "Plated vest. Stops a lot.", "short": "Hv Armor", "kind": "armor", "rarity": "rare", "w": 3, "h": 3, "stack": 1, "value": 4000, "reduction": 0.4},
	"helmet_basic": {"name": "Old Helmet", "short": "Old Helm", "desc": "Dented steel pot. Better than nothing on your head.",
		"kind": "helmet", "rarity": "uncommon", "w": 2, "h": 2, "stack": 1, "value": 1000, "reduction": 0.25},
	"helmet_good": {"name": "Combat Helmet", "short": "Combat", "desc": "Army helmet. Takes a hit to the head well.",
		"kind": "helmet", "rarity": "rare", "w": 2, "h": 2, "stack": 1, "value": 3000, "reduction": 0.45},
	"backpack_small": {"name": "Small Backpack", "desc": "A school bag. Better than pockets.", "short": "Sm Pack", "kind": "backpack", "rarity": "common", "w": 3, "h": 3, "stack": 1, "value": 400, "grid": [4, 3]},
	"backpack_medium": {"name": "Medium Backpack", "desc": "Hiking pack with room for a good haul.", "short": "Md Pack", "kind": "backpack", "rarity": "uncommon", "w": 3, "h": 3, "stack": 1, "value": 900, "grid": [5, 4]},
	"backpack_large": {"name": "Large Backpack", "desc": "Big army rucksack. Carry everything home.", "short": "Lg Pack", "kind": "backpack", "rarity": "rare", "w": 4, "h": 4, "stack": 1, "value": 2000, "grid": [6, 5]},
	"grenade": {"name": "Frag Grenade", "short": "Frag", "desc": "Pull, throw, take cover. Goes off 3 seconds after it leaves your hand.",
		"kind": "throwable", "rarity": "uncommon", "w": 1, "h": 1, "stack": 3, "value": 600},
	"energy_drink": {"name": "Energy Drink", "short": "Energy", "desc": "Fills your stamina, then sprinting costs none for 10 s.",
		"kind": "drink", "rarity": "common", "w": 1, "h": 1, "stack": 1, "value": 250, "use_time": 1.5, "boost_time": 10.0},
	"bandage": {"name": "Bandage", "desc": "Stops the bleeding. Quick to use.", "kind": "heal", "rarity": "common", "w": 1, "h": 1, "stack": 5, "value": 100, "heal": 25, "use_time": 2.0},
	"medkit": {"name": "Medkit", "desc": "Field kit. Heals a lot, takes a while.", "kind": "heal", "rarity": "uncommon", "w": 2, "h": 1, "stack": 3, "value": 400, "heal": 70, "use_time": 4.0},
	"bunker_key": {"name": "Bunker Key", "short": "Bunker", "desc": "Opens the bunker under the town hall. Bon keeps one on him.",
		"kind": "key", "door": "BunkerDoor", "rarity": "epic", "w": 1, "h": 1, "stack": 1, "value": 6000},
	"bank_vault_key": {"name": "Bank Vault Key", "short": "Vault", "desc": "Opens the vault in the bank.",
		"kind": "key", "door": "BankVaultDoor", "rarity": "rare", "w": 1, "h": 1, "stack": 1, "value": 3500},
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
	"dog_tag": {"name": "Raider Dog Tag", "short": "Tag", "desc": "Taken off a Raider. Proof of a kill, and traders pay for it.", "kind": "valuable", "rarity": "uncommon", "w": 1, "h": 1, "stack": 1, "value": 900, "special": true},
	"player_tag": {"name": "PMC Dog Tag", "short": "PMC Tag", "desc": "Taken off another player. Traders pay well for these.", "kind": "valuable", "rarity": "rare", "w": 1, "h": 1, "stack": 1, "value": 2500, "special": true},
	"bon_tag": {"name": "Bon's Dog Tag", "short": "Bon Tag", "desc": "Bon's own tag. Everyone in Bloxov will want to see this.", "kind": "valuable", "rarity": "epic", "w": 1, "h": 1, "stack": 1, "value": 9000, "special": true},
	"intel_novarra": {"name": "Novarra Field Report", "short": "Report", "desc": "Novarran army papers: patrols, supply runs, names. Someone will pay to read them.", "kind": "valuable", "rarity": "rare", "w": 1, "h": 1, "stack": 1, "value": 3000},
	"intel_exion": {"name": "Exion Orders", "short": "Orders", "desc": "Sealed orders with the Brotherhood's X1 mark. Dangerous to carry, worth a fortune.", "kind": "valuable", "rarity": "epic", "w": 1, "h": 1, "stack": 1, "value": 8500},
	"mil_chip": {"name": "Military Chip", "desc": "Exion military hardware. Very wanted.", "short": "Chip", "kind": "valuable", "rarity": "epic", "w": 1, "h": 1, "stack": 1, "value": 7500},
	"bolts": {"name": "Bolts", "desc": "A handful of nuts and bolts. Small, but always needed.", "kind": "valuable", "rarity": "common", "w": 1, "h": 1, "stack": 1, "value": 120},
	"wires": {"name": "Wires", "desc": "Copper wire stripped from a wall. Useful for fixing things.", "kind": "valuable", "rarity": "common", "w": 1, "h": 1, "stack": 1, "value": 180},
	"gunpowder": {"name": "Powder Tin", "short": "Powder", "desc": "A tin of gunpowder. Keep it away from fire.", "kind": "valuable", "rarity": "uncommon", "w": 1, "h": 1, "stack": 1, "value": 1000},
	"cpu": {"name": "Processor", "short": "CPU", "desc": "A computer processor. Small, light and worth a lot.", "kind": "valuable", "rarity": "rare", "w": 1, "h": 1, "stack": 1, "value": 5000},
	"fuel_can": {"name": "Fuel Can", "short": "Fuel", "desc": "Half full. Every generator in Bloxov wants it.", "kind": "valuable", "rarity": "uncommon", "w": 2, "h": 2, "stack": 1, "value": 900},
	"med_supplies": {"name": "Medical Supplies", "short": "Meds", "desc": "Gauze, syringes, pills. Clinics pay well for them.", "kind": "valuable", "rarity": "uncommon", "w": 1, "h": 1, "stack": 1, "value": 800},
	"novarra_badge": {"name": "Novarra Badge", "short": "Badge", "desc": "A Novarran soldier's unit badge. Collectors and traders want them.", "kind": "valuable", "rarity": "rare", "w": 1, "h": 1, "stack": 1, "value": 2000},
	"hard_drive": {"name": "Hard Drive", "short": "HDD", "desc": "Pulled from an office computer. Nobody wiped it.", "kind": "valuable", "rarity": "rare", "w": 1, "h": 1, "stack": 1, "value": 3500},
	"exion_medal": {"name": "Exion Medal", "short": "Medal", "desc": "Brotherhood medal with the X1 mark. Only their best get one.", "kind": "valuable", "rarity": "epic", "w": 1, "h": 1, "stack": 1, "value": 7000},
	"gpu": {"name": "Graphics Card", "short": "GPU", "desc": "A high-end graphics card. Worth more than most guns.", "kind": "valuable", "rarity": "epic", "w": 2, "h": 1, "stack": 1, "value": 10000},
	"diamond_ring": {"name": "Diamond Ring", "short": "Ring", "desc": "A real diamond. Someone kept it in the vault for a reason.", "kind": "valuable", "rarity": "legendary", "w": 1, "h": 1, "stack": 1, "value": 15000},
	"vase": {"name": "Antique Vase", "desc": "Old and fragile. Don't drop it.", "kind": "valuable", "rarity": "epic", "w": 2, "h": 2, "stack": 1, "value": 9000},
	"crystal": {"name": "Rare Crystal", "desc": "Nobody knows where these come from. Everyone wants one.", "short": "Crystal", "kind": "valuable", "rarity": "legendary", "w": 1, "h": 1, "stack": 1, "value": 18000},
	"golden_toilet": {"name": "Golden Toilet", "desc": "Yes, really.", "kind": "valuable", "rarity": "legendary", "w": 2, "h": 3, "stack": 1, "value": 50000},
	"holy_grail": {"name": "Holy Grail", "short": "Grail", "desc": "The most valuable thing in Bloxov. Only ever seen in the town hall and the bank vault.", "kind": "valuable", "rarity": "legendary", "w": 2, "h": 2, "stack": 1, "value": 75000, "special": true},
}

## Weights. A key is either an item id or a rarity (= a random valuable of that rarity).
const LOOT_TABLES := {
	"crate": {"smg_ammo": 3, "shells": 3, "sniper_ammo": 1, "energy_drink": 5, "pistol_ammo": 8, "backpack_small": 2, "rifle_ammo": 30, "bandage": 18, "medkit": 4, "common": 30, "uncommon": 12, "rare": 3},
	"locker": {"smg": 2, "shotgun": 2, "smg_ammo": 5, "shells": 5, "sniper_ammo": 2, "gunpowder": 2, "grenade": 3, "energy_drink": 4, "intel_novarra": 1, "pistol": 5, "armor_light": 4, "helmet_basic": 4, "backpack_small": 3, "backpack_medium": 2, "pistol_ammo": 6, "rifle_ammo": 15, "bandage": 10, "medkit": 12, "common": 18, "uncommon": 25, "rare": 15, "epic": 4},
	"safe": {"armor_heavy": 6, "helmet_good": 5, "backpack_large": 4, "uncommon": 15, "rare": 40, "epic": 30, "legendary": 15},
	"scav": {"smg_ammo": 10, "shells": 8, "energy_drink": 4, "pistol": 4, "pistol_ammo": 10, "rifle_ammo": 40, "bandage": 20, "medkit": 6, "common": 20, "uncommon": 10, "rare": 4},
	"raider": {"smg_ammo": 10, "shells": 8, "sniper_ammo": 3, "red_dot": 3, "foregrip": 3, "scope_4x": 1, "suppressor": 1, "ext_mag": 1, "grenade": 6, "energy_drink": 4, "pistol": 5, "backpack_medium": 3, "pistol_ammo": 6, "rifle_ammo": 30, "bandage": 12, "medkit": 12, "common": 12, "uncommon": 20, "rare": 10, "epic": 2},
}

## A chance (0.14.14, owner) that a container or body rolled from this loot table also holds this item, once.
## The bank vault key: 10% on Raiders, 2% in crates (for now: later it goes in chests by place).
const TABLE_CHANCES := {
	"raider": {"bank_vault_key": 0.10},
	"crate": {"bank_vault_key": 0.02},
}

## One-off finds (0.14.12, owner): a chance, each raid, that this item is in that container (by its map name).
## "special" items never come from random rolls: only from here, or off bodies (dog tags).
const SPECIAL_FINDS := {
	"TownHall_Locker1": {"holy_grail": 0.15},
	"Bank_Safe1": {"holy_grail": 0.05},   # the bank vault
}

## Loot by place (0.14.0, MAP_PLAN.md "Loot by place"): a container tagged with one of these places (its
## `place` metadata) rolls from its own table plus these weights, so a gun store's lockers are mostly guns.
## Places not listed (shops, offices, houses, the station...) roll the plain tables: mid loot.
const PLACE_LOOT := {
	"Bunker": {"sniper": 6, "sniper_ammo": 10, "scope_4x": 6, "scope_8x": 3, "suppressor": 5, "ext_mag": 5, "gunpowder": 8, "exion_medal": 6, "gpu": 3, "med_supplies": 6, "intel_exion": 12, "grenade": 8, "legendary": 25, "epic": 35, "mil_chip": 10, "armor_heavy": 10, "helmet_good": 8, "ak": 8, "rifle_ammo": 15},
	"TownHall": {"novarra_badge": 6, "hard_drive": 6, "intel_novarra": 8, "intel_exion": 2, "bunker_key": 3, "uncommon": 10},
	"Bank": {"diamond_ring": 5, "cash": 30, "gold_bar": 12, "gold_watch": 15, "rare": 10},
	"Offices": {"wires": 10, "cpu": 5, "hard_drive": 8, "gpu": 3, "intel_novarra": 5},
	"BigHouse1": {"diamond_ring": 3, "gold_watch": 20, "cash": 15, "crystal": 3},        # jewellery
	"BigHouse2": {"cpu": 8, "wires": 8, "gpu": 6, "hard_drive": 10, "laptop": 15, "phone": 25, "battery": 10},          # electronics
	"BigHouse3": {"vase": 15, "golden_toilet": 2, "epic": 8},        # antiques
	"Police": {"shotgun": 10, "shells": 15, "red_dot": 6, "foregrip": 5, "ext_mag": 3, "gunpowder": 4, "novarra_badge": 8, "grenade": 8, "intel_novarra": 4, "armor_light": 15, "armor_heavy": 4, "helmet_basic": 10, "helmet_good": 3, "pistol": 15, "pistol_ammo": 20, "bunker_key": 2},
	"GunStore": {"smg": 10, "shotgun": 10, "sniper": 4, "smg_ammo": 20, "shells": 20, "sniper_ammo": 10, "red_dot": 10, "scope_4x": 6, "scope_8x": 2, "suppressor": 5, "choke": 6, "foregrip": 8, "ext_mag": 6, "gunpowder": 15, "ak": 12, "pistol": 15, "rifle_ammo": 30, "pistol_ammo": 25},
	"Pharmacy": {"med_supplies": 25, "bandage": 45, "medkit": 25},
	"Grocery": {"energy_drink": 15, "beans": 30, "water": 30, "ration": 10},
	"Diner": {"energy_drink": 15, "beans": 30, "water": 30, "ration": 10},
	"Checkpoint": {"novarra_badge": 8, "grenade": 10, "intel_novarra": 6, "intel_exion": 2},
	"GasStation": {"fuel_can": 25},
	"GasStationTown": {"fuel_can": 25},
	"Garage": {"bolts": 15, "wires": 8, "fuel_can": 20},
	"Depot": {"fuel_can": 10},
	"Barn": {"fuel_can": 8, "bolts": 10},
	"Shed": {"bolts": 15, "wires": 10},
	"Railyard": {"bolts": 15},
	"Junkyard": {"bolts": 20, "wires": 15, "fuel_can": 6},
	"School": {"med_supplies": 5, "backpack_small": 15, "backpack_medium": 10, "backpack_large": 3, "armor_light": 5, "helmet_basic": 5},
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
		"pistol_ammo", "smg_ammo":
			return randi_range(15, 40)
		"shells":
			return randi_range(5, 12)
		"sniper_ammo":
			return randi_range(3, 10)
		"bandage":
			return randi_range(1, 2)
	return 1


static func value(id: String) -> int:
	return ITEMS[id]["value"]


static func kind(id: String) -> String:
	return ITEMS[id]["kind"]


static func color(id: String) -> Color:
	return RARITY_COLORS[ITEMS[id]["rarity"]]


## Damage multiplier at `distance` for a gun's "falloff" [from m, to m, multiplier at the far end] (1 = none).
static func falloff_mult(falloff: Array, distance: float) -> float:
	if falloff.size() != 3:
		return 1.0
	return lerpf(1.0, float(falloff[2]), clampf(inverse_lerp(float(falloff[0]), float(falloff[1]), distance), 0.0, 1.0))


## A weapon's stats with its attachments' on top (0.15.1): "mult" stats multiply, "set" stats replace
## (a scope's zoom). The mag size rounds to whole rounds.
static func weapon_stats(stack: ItemStack) -> Dictionary:
	var stats: Dictionary = ITEMS[stack.id].duplicate()
	for slot: String in stack.attachments:
		var part: Dictionary = ITEMS[stack.attachments[slot]]
		for stat: String in part.get("mult", {}):
			if stats.has(stat):
				stats[stat] = float(stats[stat]) * float(part["mult"][stat])
		for stat: String in part.get("set", {}):
			stats[stat] = part["set"][stat]
	stats["mag"] = roundi(float(stats["mag"]))
	return stats


## Attachment slots on a weapon ("scope", "sight", "barrel", "grip", "mag"); none for anything else.
static func attachment_slots(id: String) -> Array:
	return ITEMS[id].get("slots", [])


## The slot of weapon `gun_id` attachment `part_id` goes in, or "" if it doesn't fit that gun.
static func attachment_slot_for(gun_id: String, part_id: String) -> String:
	var part: Dictionary = ITEMS[part_id]
	if part["kind"] != "attachment" or (part.has("fits") and not gun_id in part["fits"]):
		return ""
	for slot: String in attachment_slots(gun_id):
		if slot in part["slots"]:
			return slot
	return ""


## Which equipment slot an item goes in ("primary", "secondary", "armor", "backpack"), or "" if none.
static func equip_slot(id: String) -> String:
	match kind(id):
		"weapon":
			return ITEMS[id]["slot"]
		"armor":
			return "armor"
		"helmet":
			return "helmet"
		"backpack":
			return "backpack"
	return ""


## The line the inventory shows about it.
static func description(id: String) -> String:
	return ITEMS[id].get("desc", "")


## Armor points or key uses when new (0 = it doesn't wear).
static func max_durability(id: String) -> int:
	return int(ITEMS[id].get("durability", 0))


## How much of a hit an armor or helmet stack stops (0 to 1, 0 for none): its reduction times how much is left.
static func reduction(stack: ItemStack) -> float:
	if stack == null or not ITEMS[stack.id].has("reduction"):
		return 0.0
	return float(ITEMS[stack.id]["reduction"]) * stack.condition()


## A hit of `damage` (before armor) wore `stack` down: it loses the part it stops when new (at least 1 point).
static func wear(stack: ItemStack, damage: int) -> void:
	var lost := maxi(roundi(mini(damage, 100) * float(ITEMS[stack.id]["reduction"])), 1)
	stack.durability = maxi(stack.durability - lost, 0)


## Durability of one found in a raid: armor turns up worn (40-100%), keys with all their uses.
static func found_durability(id: String) -> int:
	var most := max_durability(id)
	if kind(id) in ["armor", "helmet"]:
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
		if ITEMS[id]["kind"] == "valuable" and ITEMS[id]["rarity"] == rarity and not ITEMS[id].get("special", false):
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
