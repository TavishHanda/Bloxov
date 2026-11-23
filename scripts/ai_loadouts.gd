class_name AILoadouts
extends RefCounted
## Which gun each kind of AI carries (0.15.5, owner's Guns plan) and how that gun changes the way it shoots.
## Only numbers change, no new behavior (the AI's fighting is locked in, 0.12.38): a shotgun AI hits hard but only
## up close, an SMG AI fires longer bursts that hurt less, a pistol AI shoots slower. An AK keeps the AI as it was,
## so overall danger stays about where it was before the new guns.

## AI loadout tables (ScavBase.loadout names one of these, or a gun id for a fixed gun): gun id -> weight.
const TABLES := {
	# (0.36.42, owner OK'd: the AI sometimes carries the new Hornet, Brawler and Viper.) 0.38.1 (owner approved,
	# 2026-11-20: the new guns are better variants, extremely rare on Frontlines, rarer-than-common on Riptide):
	# Frontlines scavs and Raiders never carry them, AI PMCs about 1 in 35; Riptide's Deckhands about 1 in 17, Troopers 1 in 9.
	"scav": {"ak": 40, "smg": 25, "shotgun": 20, "pistol": 15},
	"raider": {"ak": 50, "smg": 30, "shotgun": 20},
	# AI PMCs (0.36.4): any of the AI guns, the scav table's odds (plus a rare new gun, they count as players).
	"pmc": {"ak": 40, "smg": 25, "shotgun": 20, "pistol": 15, "hornet": 1, "brawler": 1, "viper": 1},
	# Riptide's scavs and Raiders (deckhand.tscn, trooper.tscn).
	"deckhand": {"ak": 40, "smg": 25, "shotgun": 20, "pistol": 15, "hornet": 2, "brawler": 2, "viper": 2},
	"trooper": {"ak": 50, "smg": 30, "shotgun": 20, "hornet": 6, "brawler": 6},
}

## What an AI PMC wears and carries. 0.36.4 / 0.36.7 gave every bot one kit (light armor mostly, sometimes a helmet,
## a small backpack). 0.39.29 (owner approved, 2026-11-23: bots were "too homeless", better loot overall and well-geared
## bots a bit more common, "you should be rewarded from killing a PMC (sometimes)"): each bot rolls one of three kit
## levels from its id. Light is about today's kit (about $15k on the body), Kitted about $30k, Geared about $60k.
## Weights: item id ("" = none) -> weight.
const PMC_TIERS := {"light": 50, "kitted": 35, "geared": 15}
const PMC_KITS := {
	"light": {"armor": {"armor_light": 70, "": 30}, "helmet_chance": 0.3, "helmets": {"helmet_basic": 1},
		"pack": {"": 50, "backpack_small": 50}, "parts": [0, 1], "drops": [2, 3], "medkits": 0, "medkit_chance": 0.15,
		"grenades": 0, "valuable": {}, "new_gun_chance": 0.0, "best_part_chance": 0.0},
	"kitted": {"armor": {"armor_light": 85, "armor_heavy": 15}, "helmet_chance": 0.7,
		"helmets": {"helmet_basic": 75, "helmet_good": 25}, "pack": {"backpack_small": 50, "backpack_medium": 50},
		"parts": [1, 2], "drops": [3, 5], "medkits": 1, "medkit_chance": 0.0, "grenades": 0,
		"valuable": {"uncommon": 60, "rare": 30, "epic": 10}, "new_gun_chance": 0.0, "best_part_chance": 0.0},
	"geared": {"armor": {"armor_heavy": 1}, "helmet_chance": 1.0, "helmets": {"helmet_good": 1},
		"pack": {"backpack_medium": 2, "backpack_large": 1}, "parts": [2, 3], "drops": [4, 6], "medkits": 2,
		"medkit_chance": 0.0, "grenades": 1, "valuable": {"rare": 60, "epic": 30, "legendary": 10},
		"new_gun_chance": 1.0 / 3.0, "best_part_chance": 0.25},
}
## The new guns a Geared bot may carry (they fight exactly like their base gun, STYLE_OF).
const PMC_NEW_GUNS := ["hornet", "brawler", "viper"]
## The purple "Best" attachments (loot-only, 0.39.28): a Geared bot's gun has one of these 1 time in 4.
const BEST_PARTS := ["tactical_grip", "heavy_suppressor", "drum_mag", "full_choke"]

## How a gun changes the AI's shooting: "mult" multiplies its stats, "set" replaces them.
## Rough damage per second up close against the AK (scav): SMG about the same, shotgun a little less but in big
## hits (you go down in 4 instead of 7), pistol about half.
## How it fights with the gun (0.15.11, owner asked): the same fight brain, only its distance settings change.
## Mauler rushes (chases from as far as it can hit, faster, hardly stops for cover), Wasp is aggressive (chases
## from farther, pins you down more), Stinger is careful (chases only up close, takes cover more). Hound and
## Lancer fight as before.
const STYLES := {
	"smg": {"mult": {"shot_damage": 0.75, "burst_size": 1.6, "burst_interval": 0.65, "shoot_range": 0.65, "accuracy_long": 0.7,
			"push_speed": 1.12, "suppress_chance": 1.4},
		"set": {"chase_range": 40.0, "shot_pitch": 0.95}},
	"shotgun": {"mult": {"shot_damage": 2.2, "accuracy_far": 0.6, "accuracy_long": 0.3, "push_speed": 1.25},
		"set": {"burst_size": 1, "burst_cooldown_min": 0.9, "burst_cooldown_max": 1.2, "shoot_range": 22.0,
			"chase_range": 22.0, "chase_cover_chance": 0.03, "shot_pitch": 0.95}},
	"pistol": {"mult": {"shot_damage": 0.8, "burst_size": 0.5, "burst_cooldown_min": 1.25, "burst_cooldown_max": 1.25, "shoot_range": 0.7, "shot_pitch": 1.1},
		"set": {"chase_range": 15.0, "chase_cover_chance": 0.3}},
	# (The Wasp, Mauler and Lancer have their own shot sounds, GunSounds, played near their real pitch.)
	"sniper": {"set": {"shot_pitch": 0.95}},
}

## Guns as numbers for the network (0.15.12): the server sends each AI's gun to the puppets, so online they hold,
## sound and shoot like the gun they really carry.
const NET_GUNS := ["", "ak", "smg", "shotgun", "pistol", "sniper", "reaper", "viper", "hornet", "brawler", "talon"]
## A gun that fights like another (0.36.42): the second gun of a type uses its type's style (the AI's fighting is locked,
## so only the numbers it already had), and its own shot pitch on top (ItemDB "shot_pitch").
const STYLE_OF := {"viper": "pistol", "hornet": "smg", "brawler": "shotgun", "talon": "sniper"}

## Attachments a dropped gun may come with (ScavBase.drop_part_chance: Raiders, sometimes).
const DROP_PARTS := ["red_dot", "foregrip", "ext_mag", "suppressor", "scope_4x", "taped_grip", "muzzle_brake", "fast_mag", "holo_sight"]


## The gun for loadout `name` (a table rolls one; a gun id is that gun).
static func pick(name: String) -> String:
	if not TABLES.has(name):
		return name
	var weights: Dictionary = TABLES[name]
	var total := 0
	for weight: int in weights.values():
		total += weight
	var roll := randi() % total
	for gun: String in weights:
		roll -= weights[gun]
		if roll < 0:
			return gun
	return weights.keys()[0]


## Changes `ai`'s shooting stats for carrying `gun`.
static func apply_style(ai: Object, gun: String) -> void:
	var style: Dictionary = STYLES.get(STYLE_OF.get(gun, gun), {})
	for stat: String in style.get("mult", {}):
		var value: float = float(ai.get(stat)) * float(style["mult"][stat])
		ai.set(stat, maxi(roundi(value), 1) if typeof(ai.get(stat)) == TYPE_INT else value)
	for stat: String in style.get("set", {}):
		ai.set(stat, style["set"][stat])
	if STYLE_OF.has(gun):
		ai.set("shot_pitch", float(ai.get("shot_pitch")) * float(ItemDB.item(gun).get("shot_pitch", 1.0)))


## The gun as it ends up on the body (empty, like before): with attachments `parts`, plus a random one
## `part_chance` of the time.
static func dropped_gun(gun: String, parts: Array, part_chance: float) -> ItemStack:
	var stack := ItemStack.new(gun)
	for part: String in parts:
		stack.attachments[ItemDB.attachment_slot_for(gun, part)] = part
	if randf() < part_chance:
		var options := DROP_PARTS.filter(func(part: String) -> bool:
			var slot := ItemDB.attachment_slot_for(gun, part)
			return slot != "" and not stack.attachments.has(slot))
		if not options.is_empty():
			var part: String = options.pick_random()
			stack.attachments[ItemDB.attachment_slot_for(gun, part)] = part
	return stack


## One key of `weights` (item id -> weight), or "" for none.
static func roll_weighted(weights: Dictionary, rng: RandomNumberGenerator = null) -> String:
	var total := 0
	for weight: int in weights.values():
		total += weight
	var roll := (rng.randi() if rng != null else randi()) % total
	for key: String in weights:
		roll -= weights[key]
		if roll < 0:
			return key
	return weights.keys()[0]


## An AI PMC's kit level ("light", "kitted", "geared") from its id. Only the id decides, so the server and every
## screen agree (its helmet, and so its outfit's hat, depends on it).
static func pmc_tier(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return roll_weighted(PMC_TIERS, rng)


## The helmet an AI PMC with this id wears ("" = none). Only the id decides, so the server and every screen agree
## (the outfit's hat is picked to match, Scav.pick_look).
static func pmc_helmet(seed_value: int) -> String:
	var kit: Dictionary = PMC_KITS[pmc_tier(seed_value)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7919
	if rng.randf() >= float(kit["helmet_chance"]):
		return ""
	return roll_weighted(kit["helmets"], rng)


## An AI PMC's own kit for `ai` (a Scav), set before it puts its gear on: armor, helmet (from `seed_value`), backpack
## and how many items its body rolls. The gun comes from the "pmc" table through `loadout` (or a new gun, Geared).
static func roll_pmc_kit(ai: Object, seed_value: int) -> void:
	var tier := pmc_tier(seed_value)
	var kit: Dictionary = PMC_KITS[tier]
	ai.set("pmc_tier", tier)
	ai.set("armor", roll_weighted(kit["armor"]))
	ai.set("helmet", pmc_helmet(seed_value))
	ai.set("pack", roll_weighted(kit["pack"]))
	ai.set("min_drops", kit["drops"][0])
	ai.set("max_drops", kit["drops"][1])
	if String(ai.get("loadout")) != "" and randf() < float(kit["new_gun_chance"]):
		ai.set("loadout", PMC_NEW_GUNS.pick_random())


## An AI PMC's gun as it ends up on its body: its kit level's number of attachments (a Geared bot's sometimes a
## purple one).
static func pmc_gun(gun: String, tier: String) -> ItemStack:
	var kit: Dictionary = PMC_KITS.get(tier, PMC_KITS["light"])
	var stack := ItemStack.new(gun)
	var count := randi_range(kit["parts"][0], kit["parts"][1])
	if count > 0 and randf() < float(kit["best_part_chance"]):
		var best := BEST_PARTS.filter(func(part: String) -> bool: return ItemDB.attachment_slot_for(gun, part) != "")
		if not best.is_empty():
			var part: String = best.pick_random()
			stack.attachments[ItemDB.attachment_slot_for(gun, part)] = part
			count -= 1
	var options := DROP_PARTS.duplicate()
	options.shuffle()
	for part: String in options:
		if count <= 0:
			break
		var slot := ItemDB.attachment_slot_for(gun, part)
		if slot != "" and not stack.attachments.has(slot):
			stack.attachments[slot] = part
			count -= 1
	return stack


## A random valuable whose rarity is rolled from `rarities` (rarity -> weight), or "" for none.
static func bonus_valuable(rarities: Dictionary) -> String:
	if rarities.is_empty():
		return ""
	return ItemDB._random_valuable(roll_weighted(rarities))


## What its body holds on top of the rolled loot (`kit`): its backpack, the rounds for its gun, some meds, and its kit
## level's extras (a grenade, a valuable).
static func pmc_extras(gun: String, pack: String, tier: String = "light") -> Array:
	var kit: Dictionary = PMC_KITS.get(tier, PMC_KITS["light"])
	var extras: Array = []
	if pack != "":
		extras.append(ItemStack.new(pack))
	var ammo: String = ItemDB.ITEMS.get(gun, {}).get("ammo", "")
	if ammo != "":
		extras.append([ammo, ItemDB.roll_count(ammo)])
	extras.append(["bandage", ItemDB.roll_count("bandage")])
	var medkits: int = kit["medkits"]
	if medkits == 0 and randf() < float(kit["medkit_chance"]):
		medkits = 1
	for i in medkits:
		extras.append(["medkit", 1])
	for i in int(kit["grenades"]):
		extras.append(["grenade", 1])
	var valuable := bonus_valuable(kit["valuable"])
	if valuable != "":
		extras.append([valuable, 1])
	return extras
