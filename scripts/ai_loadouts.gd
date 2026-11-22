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

## What an AI PMC wears and carries (0.36.4, piece 5 of the AI PMC plan: "light armor most of the time, sometimes none
## or heavy, sometimes a helmet, a small backpack"). The plan gave no odds, so these are PROPOSED numbers for the
## owner to approve before bots are switched on (tunable here, piece 7). Weights: item id ("" = none) -> weight.
## (0.36.7, owner approved: "make heavy stuff rarer for now": light 65, none 30, heavy 5, was 60/25/15.)
const PMC_ARMOR := {"armor_light": 65, "": 30, "armor_heavy": 5}
## Share of AI PMCs in a helmet, and which one. Decided from the bot's id (`pmc_helmet`), because the helmet has to
## match the hat on its outfit and every screen only knows the id.
const PMC_HELMET_CHANCE := 0.3
## (0.36.7, owner approved: the Combat Helmet is 1 in 10 of helmets, was 1 in 5.)
const PMC_HELMETS := {"helmet_basic": 90, "helmet_good": 10}
## Backpack it carries (it ends up on its body): item id ("" = none) -> weight.
## (0.36.7, owner approved: none 55, small 40, medium 5, was 55/35/10.)
const PMC_BACKPACK := {"": 55, "backpack_small": 40, "backpack_medium": 5}
## A bandage stack it carries, the share of AI PMCs with a medkit too, and its ammo: the carried gun's rounds, rolled
## like any body's (ItemDB.roll_count).
const PMC_MEDKIT_CHANCE := 0.15

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


## The helmet an AI PMC with this id wears ("" = none). Only the id decides, so the server and every screen agree
## (the outfit's hat is picked to match, Scav.pick_look).
static func pmc_helmet(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if rng.randf() >= PMC_HELMET_CHANCE:
		return ""
	return roll_weighted(PMC_HELMETS, rng)


## An AI PMC's own kit for `ai` (a Scav), set before it puts its gear on: armor, helmet (from `seed_value`) and
## backpack. The gun comes from the "pmc" table through `loadout`.
static func roll_pmc_kit(ai: Object, seed_value: int) -> void:
	ai.set("armor", roll_weighted(PMC_ARMOR))
	ai.set("helmet", pmc_helmet(seed_value))
	ai.set("pack", roll_weighted(PMC_BACKPACK))


## What its body holds on top of the rolled loot (`kit`): its backpack, the rounds for its gun and some meds.
static func pmc_extras(gun: String, pack: String) -> Array:
	var extras: Array = []
	if pack != "":
		extras.append(ItemStack.new(pack))
	var ammo: String = ItemDB.ITEMS.get(gun, {}).get("ammo", "")
	if ammo != "":
		extras.append([ammo, ItemDB.roll_count(ammo)])
	extras.append(["bandage", ItemDB.roll_count("bandage")])
	if randf() < PMC_MEDKIT_CHANCE:
		extras.append(["medkit", 1])
	return extras
