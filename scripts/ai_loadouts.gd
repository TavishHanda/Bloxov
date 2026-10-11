class_name AILoadouts
extends RefCounted
## Which gun each kind of AI carries (0.15.5, owner's Guns plan) and how that gun changes the way it shoots.
## Only numbers change, no new behavior (the AI's fighting is locked in, 0.12.38): a shotgun AI hits hard but only
## up close, an SMG AI fires longer bursts that hurt less, a pistol AI shoots slower. An AK keeps the AI as it was,
## so overall danger stays about where it was before the new guns.

## AI loadout tables (ScavBase.loadout names one of these, or a gun id for a fixed gun): gun id -> weight.
const TABLES := {
	"scav": {"ak": 40, "smg": 25, "shotgun": 20, "pistol": 15},
	"raider": {"ak": 50, "smg": 30, "shotgun": 20},
}

## How a gun changes the AI's shooting: "mult" multiplies its stats, "set" replaces them.
## Rough damage per second up close against the AK (scav): SMG about the same, shotgun a little less but in big
## hits (you go down in 4 instead of 7), pistol about half.
## How it fights with the gun (0.15.11, owner asked): the same fight brain, only its distance settings change.
## Mauler rushes (chases from as far as it can hit, faster, hardly stops for cover), Wasp is aggressive (chases
## from farther, pins you down more), Stinger is careful (chases only up close, takes cover more). Hound and
## Lancer fight as before.
const STYLES := {
	"smg": {"mult": {"shot_damage": 0.75, "burst_size": 1.6, "burst_interval": 0.65, "shoot_range": 0.65, "accuracy_long": 0.7, "shot_pitch": 1.25,
			"push_speed": 1.12, "suppress_chance": 1.4},
		"set": {"chase_range": 40.0}},
	"shotgun": {"mult": {"shot_damage": 2.2, "accuracy_far": 0.6, "accuracy_long": 0.3, "shot_pitch": 0.75, "push_speed": 1.25},
		"set": {"burst_size": 1, "burst_cooldown_min": 0.9, "burst_cooldown_max": 1.2, "shoot_range": 22.0,
			"chase_range": 22.0, "chase_cover_chance": 0.03}},
	"pistol": {"mult": {"shot_damage": 0.8, "burst_size": 0.5, "burst_cooldown_min": 1.25, "burst_cooldown_max": 1.25, "shoot_range": 0.7, "shot_pitch": 1.1},
		"set": {"chase_range": 15.0, "chase_cover_chance": 0.3}},
}

## Attachments a dropped gun may come with (ScavBase.drop_part_chance: Raiders, sometimes).
const DROP_PARTS := ["red_dot", "foregrip", "ext_mag", "suppressor", "scope_4x"]


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
	var style: Dictionary = STYLES.get(gun, {})
	for stat: String in style.get("mult", {}):
		var value: float = float(ai.get(stat)) * float(style["mult"][stat])
		ai.set(stat, maxi(roundi(value), 1) if typeof(ai.get(stat)) == TYPE_INT else value)
	for stat: String in style.get("set", {}):
		ai.set(stat, style["set"][stat])


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
