class_name Characters
extends RefCounted
## The playable characters (0.37.0, owner 2026-11-20; the design: project file characters/roster-proposal-2026-11-20.html).
## Six REVENANT contractors, each with two upsides, two downsides and a passive with three ranks. A trait grows with the
## character's level: a quarter of its full size at level 1, full at level 20 (upsides AND downsides, owner's pick).
## Upgrade points (2 at level 10, 3 at level 20, 2 per expedition escape up to 10) are the player's choice: +2% on an
## upside (5 points at most each), a quarter off a downside (2 at most each, never removed), or a passive rank (2 points
## per rank). An expedition resets the level (the points stay; level points only come the first time).
## Health and damage are the same for everyone. Characters are earned (in-game money and a trader level), never sold
## for real money (docs/STORE_RULES.md).
## Pure data and rules: the server uses it too (OnlineProfile, NetAccounts), so like net.gd it must never lean on
## player, gun or hideout scripts. The state is a Dictionary (Profile.characters / an online profile's "characters").

const MAX_LEVEL := 20
## A trait at level 1 is this share of its full size; it grows evenly to 1.0 at MAX_LEVEL.
const START_SHARE := 0.25
## Points for reaching a level, the first time only.
const LEVEL_POINTS := {10: 2, 20: 3}
const EXPEDITION_POINTS := 2
const MAX_EXPEDITION_POINTS := 10
const UPSIDE_STEP := 0.02
const UPSIDE_MAX := 5
const DOWNSIDE_STEP := 0.25
const DOWNSIDE_MAX := 2
const PASSIVE_RANK_COST := 2
## Moving your points around (all of them back) costs this much.
const RESET_COST := 25000
## Raid XP (numbers are a start, owner tunes): an extract, a raid you didn't get out of, and each kill you got out with.
const XP_EXTRACT := 100
const XP_LOST := 30
const XP_KILL := {"scav": 10, "raider": 25, "pmc": 50, "boss": 100}
## Bounty (SABLE's passive): money per kill by kind at rank 1; ranks 2 and 3 pay BOUNTY_RANKS times that. Paid on extract.
const BOUNTY := {"scav": 1000, "raider": 2500, "pmc": 5000, "boss": 10000}
const BOUNTY_RANKS: Array[float] = [1.0, 1.5, 2.0]
## What a kill's target (the AI's scene name, or "player") counts as. AI PMCs and players are both "pmc" (owner:
## an AI PMC is a PMC, there to fill the lobby).
const KIND_OF := {"scav": "scav", "sniper": "scav", "deckhand": "scav", "raider": "raider", "trooper": "raider",
	"guard_riptide": "raider", "boss_ace": "raider", "boss_orbit": "raider", "boss": "boss", "boss_raijin": "boss",
	"player": "pmc", "pmc_ai": "pmc"}

## The order they're listed in. The first two are free.
const ORDER: Array[String] = ["vega", "voss", "sable", "patch", "nine", "korr"]
## Each trait: [stat, value at level 20, upside?]. Stats are multipliers (1 + value): see mult().
##   move: walk, crouch and sprint speed · sprint: sprint speed · sprint_stamina: stamina used sprinting · stamina_max ·
##   stamina_regen · reload: reload time · recoil · ads: time to aim · aim_spread: spread when aimed · hip_spread ·
##   auto_rate: fire rate of full-auto guns · aim_move: move speed while aiming · heal_time: time to use meds ·
##   swap: time to swap guns · search: time to search containers · steps: how far your footsteps carry ·
##   hearing: how far you hear others' footsteps · jump: jump height
const LIST := {
	"vega": {"name": "VEGA", "role": "Nova pathfinder", "side": "nova", "price": 0,
		"bio": "A Nova scout who ran messages across the border during the strike and never stopped running.",
		"traits": [["move", 0.08, true], ["reload", -0.10, true], ["sprint_stamina", 0.25, false], ["recoil", 0.10, false]],
		"passive": "light_feet"},
	"voss": {"name": "VOSS", "role": "Exion officer cadet", "side": "exion", "price": 0,
		"bio": "A Brotherhood cadet groomed for command, until he read what the program did to its own people.",
		"traits": [["stamina_max", 0.25, true], ["recoil", -0.15, true], ["sprint", -0.06, false], ["ads", 0.10, false]],
		"passive": "hold_steady"},
	"sable": {"name": "SABLE", "role": "Haven-born hunter", "side": "", "price": 400000, "trader": "guns", "trader_level": 3,
		"bio": "Grew up in a safe haven shooting game for the kitchens. REVENANT pays better for other targets.",
		"traits": [["ads", -0.20, true], ["hearing", 0.25, true], ["auto_rate", -0.10, false], ["aim_move", -0.15, false]],
		"passive": "bounty"},
	"patch": {"name": "PATCH", "role": "Bloxov medic", "side": "", "price": 250000, "trader": "meds", "trader_level": 2,
		"bio": "Born in Bloxov, patched up both armies' wounded for whoever paid in food.",
		"traits": [["heal_time", -0.15, true], ["swap", -0.25, true], ["stamina_max", -0.15, false], ["reload", 0.10, false]],
		"passive": "steady_hands"},
	"nine": {"name": "NINE", "role": "Escaped subject 09", "side": "", "price": 0, "files": true,
		"bio": "Subject 09 of the Brotherhood's super-soldier program, loose since the strike. Remembers nothing before the lab.",
		"traits": [["stamina_regen", 0.30, true], ["jump", 0.15, true], ["steps", 0.30, false], ["heal_time", 0.20, false]],
		"passive": "overdrive"},
	"korr": {"name": "KORR", "role": "Exion quartermaster", "side": "exion", "price": 500000, "trader": "supplies", "trader_level": 2,
		"bio": "Ran an Exion supply depot until the strike, then kept supplying himself from every ruin in Bloxov.",
		"traits": [["search", -0.30, true], ["hip_spread", -0.20, true], ["aim_spread", 0.15, false], ["stamina_max", -0.10, false]],
		"passive": "pack_rat"},
}
const STAT_NAMES := {"move": "Walk, crouch and sprint speed", "sprint": "Sprint speed", "sprint_stamina": "Stamina used sprinting",
	"stamina_max": "Max stamina", "stamina_regen": "Stamina comes back", "reload": "Reload time", "recoil": "Recoil",
	"ads": "Time to aim", "aim_spread": "Spread when aiming", "hip_spread": "Hip-fire spread",
	"auto_rate": "Full-auto fire rate", "aim_move": "Move speed while aiming", "heal_time": "Time to use meds",
	"swap": "Time to swap guns", "search": "Time to search containers", "steps": "How far your steps carry",
	"hearing": "How far you hear footsteps", "jump": "Jump height"}
## Passives: name, what it does, and its three ranks.
const PASSIVES := {
	"light_feet": {"name": "Light Feet", "about": "Your footsteps carry less far.", "ranks": [0.25, 0.35, 0.45],
		"rank_text": ["25% less far", "35% less far", "45% less far"]},
	"hold_steady": {"name": "Hold Steady", "about": "Holding still and aiming: less recoil and less spread.",
		"ranks": [0.06, 0.08, 0.10], "rank_text": ["standing still, -6%", "+ lying down, -8%", "+ crouched, -10%"]},
	"bounty": {"name": "Bounty", "about": "Every kill pays extra money when you extract.", "ranks": BOUNTY_RANKS,
		"rank_text": ["Scav $1k, Raider $2.5k, PMC $5k, Boss $10k", "x1.5", "x2"]},
	"steady_hands": {"name": "Steady Hands", "about": "Move freely while using meds.", "ranks": [0.0, 0.0, 0.10],
		"rank_text": ["walk at full speed", "sprint too", "meds 10% faster on top"]},
	"overdrive": {"name": "Overdrive", "about": "Once per raid, dropping below 30% health gives a sprint that uses no stamina.",
		"ranks": [5.0, 7.0, 9.0], "rank_text": ["5 s", "7 s", "9 s"]},
	"pack_rat": {"name": "Pack Rat", "about": "Extra pocket slots.", "ranks": [1, 2, 3], "rank_text": ["+1 slot", "+2 slots", "+3 slots"]},
}
const OVERDRIVE_BELOW := 0.3
const POCKETS_WIDTH := 4
## Spent-point keys: u0/u1 = the two upsides, d0/d1 = the two downsides, p = passive ranks above 1.
const SPEND_KEYS: Array[String] = ["u0", "u1", "d0", "d1", "p"]

## This device's player in a raid (set by the player as it spawns): stat -> multiplier, and the passive and its rank.
## Empty on the server and for everyone else, so nothing changes there.
static var active := {}
static var active_passive := ""
static var active_rank := 0
## How far this device's player hears others' footsteps (Surfaces.step).
static var hearing := 1.0
## The last raid's result for the end screen: {"xp", "bounty", "level", "levels_gained"}.
static var last_raid := {}


## A new state: the two starters unlocked, VEGA picked.
static func fresh() -> Dictionary:
	return {"selected": "vega", "unlocked": ["vega", "voss"], "exp_points": 0, "chars": {}}


static func _num(value: Variant) -> bool:
	return value is int or value is float


## A state from anything (a save, the network): every field type-checked, starters always unlocked.
static func clean(data: Variant) -> Dictionary:
	var out := fresh()
	if not data is Dictionary:
		return out
	var unlocked: Array = out["unlocked"]
	if data.get("unlocked") is Array:
		for id: Variant in data["unlocked"]:
			if id is String and LIST.has(id) and not unlocked.has(id):
				unlocked.append(id)
	var chars: Dictionary = out["chars"]
	if data.get("chars") is Dictionary:
		for id: Variant in data["chars"]:
			if id is String and LIST.has(id) and data["chars"][id] is Dictionary:
				chars[id] = _clean_char(data["chars"][id])
	out["exp_points"] = clampi(int(data["exp_points"]), 0, MAX_EXPEDITION_POINTS) if _num(data.get("exp_points")) else 0
	var pick: Variant = data.get("selected")
	out["selected"] = pick if pick is String and unlocked.has(pick) else "vega"
	return out


static func _clean_char(c: Dictionary) -> Dictionary:
	var out := {"xp": maxi(int(c["xp"]), 0) if _num(c.get("xp")) else 0,
		"lvl_points": clampi(int(c["lvl_points"]), 0, 5) if _num(c.get("lvl_points")) else 0,
		"spent": {}}
	var spent: Dictionary = c.get("spent", {}) if c.get("spent") is Dictionary else {}
	for key in SPEND_KEYS:
		var cap := UPSIDE_MAX if key.begins_with("u") else (DOWNSIDE_MAX if key.begins_with("d") else 2)
		out["spent"][key] = clampi(int(spent[key]), 0, cap) if _num(spent.get(key)) else 0
	return out


## One character's progress (a fresh one if it has none yet; not stored until it changes).
static func char_of(state: Dictionary, id: String) -> Dictionary:
	var chars: Dictionary = state.get_or_add("chars", {})
	if not chars.has(id):
		chars[id] = _clean_char({})
	return chars[id]


## XP needed to go from `level` to the next.
static func xp_to_next(level: int) -> int:
	return 100 + 15 * level


static func level_of_xp(xp: int) -> int:
	var level := 1
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
	return level


## [xp into this level, xp the level needs] (both 0 at the top level).
static func level_progress(xp: int) -> Array:
	var level := 1
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
	return [0, 0] if level >= MAX_LEVEL else [xp, xp_to_next(level)]


static func level(state: Dictionary, id: String) -> int:
	return level_of_xp(int(char_of(state, id)["xp"]))


## Upgrade points are one pool for the whole account (owner, 2026-11-20): earned by any character (its levels 10 and
## 20, the first time) and by expedition escapes, spent on any unlocked character.
static func points_earned(state: Dictionary) -> int:
	var total := int(state.get("exp_points", 0))
	for id: String in state.get("chars", {}):
		total += int(state["chars"][id]["lvl_points"])
	return total


## Points on one character.
static func char_spent(c: Dictionary) -> int:
	var spent: Dictionary = c["spent"]
	var total := 0
	for key in SPEND_KEYS:
		total += int(spent.get(key, 0)) * (PASSIVE_RANK_COST if key == "p" else 1)
	return total


static func points_spent(state: Dictionary) -> int:
	var total := 0
	for id: String in state.get("chars", {}):
		total += char_spent(state["chars"][id])
	return total


static func points_left(state: Dictionary) -> int:
	return points_earned(state) - points_spent(state)


## The passive's rank (1-3).
static func passive_rank(c: Dictionary) -> int:
	return 1 + int(c["spent"].get("p", 0))


## A trait's value now: [stat, value]. `index` 0-3 (0, 1 upsides; 2, 3 downsides).
static func trait_value(id: String, c: Dictionary, index: int) -> float:
	var entry: Array = LIST[id]["traits"][index]
	var full := float(entry[1])
	var lv := level_of_xp(int(c["xp"]))
	var value := full * (START_SHARE + (1.0 - START_SHARE) * float(lv - 1) / float(MAX_LEVEL - 1))
	if index < 2:
		value += signf(full) * UPSIDE_STEP * int(c["spent"].get("u%d" % index, 0))
	else:
		value *= 1.0 - DOWNSIDE_STEP * int(c["spent"].get("d%d" % (index - 2), 0))
	return value


## Whether one more point can go on `key` ("u0".."d1", "p").
static func can_spend(state: Dictionary, c: Dictionary, key: String) -> bool:
	var cost := PASSIVE_RANK_COST if key == "p" else 1
	var cap := UPSIDE_MAX if key.begins_with("u") else (DOWNSIDE_MAX if key.begins_with("d") else 2)
	return SPEND_KEYS.has(key) and points_left(state) >= cost and int(c["spent"].get(key, 0)) < cap


static func spend(state: Dictionary, id: String, key: String) -> bool:
	var c := char_of(state, id)
	if not can_spend(state, c, key):
		return false
	c["spent"][key] = int(c["spent"].get(key, 0)) + 1
	return true


## Every point on `id` back to the pool (costs RESET_COST, taken by the caller).
static func reset_points(state: Dictionary, id: String) -> void:
	var c := char_of(state, id)
	for key in SPEND_KEYS:
		c["spent"][key] = 0


## Why `id` can't be unlocked now ("" = it can): money on hand and each trader's level.
static func unlock_problem(state: Dictionary, id: String, money: int, trader_levels: Dictionary) -> String:
	var info: Dictionary = LIST[id]
	if (state.get("unlocked", []) as Array).has(id):
		return "Unlocked"
	if info.get("files", false):
		return "Find the 3 Subject 09 files in Site Zero (coming in the next update)"
	var trader := str(info.get("trader", ""))
	if trader != "" and int(trader_levels.get(trader, 1)) < int(info["trader_level"]):
		return "Needs %s level %d" % [Traders.title(trader), int(info["trader_level"])]
	if money < int(info["price"]):
		return "Needs %s" % ItemDB.money(int(info["price"]))
	return ""


## The expedition (0.38, its own thread): `id` escaped. Points go to the shared pool (up to the cap for the account);
## the expedition also calls `reset_level` for the character that went.
static func add_expedition_points(state: Dictionary, _id: String, amount := EXPEDITION_POINTS) -> void:
	state["exp_points"] = mini(int(state.get("exp_points", 0)) + amount, MAX_EXPEDITION_POINTS)


static func reset_level(state: Dictionary, id: String) -> void:
	char_of(state, id)["xp"] = 0


## Adds raid XP to the picked character; level points for levels reached the first time. Returns levels gained.
static func add_xp(state: Dictionary, id: String, xp: int) -> int:
	var c := char_of(state, id)
	var before := level_of_xp(int(c["xp"]))
	c["xp"] = int(c["xp"]) + maxi(xp, 0)
	var after := level_of_xp(int(c["xp"]))
	var owed := 0
	for lv: int in LEVEL_POINTS:
		if after >= lv:
			owed += int(LEVEL_POINTS[lv])
	c["lvl_points"] = maxi(int(c["lvl_points"]), owed)
	return after - before


## What a kill counts as ("scav", "raider", "pmc", "boss"; "" = nothing).
static func kind_of(target: String) -> String:
	return str(KIND_OF.get(target, ""))


## A raid ended for `state`'s picked character: XP (extract or not, kills only if out) and the Bounty money (out only).
## `kills` as the quests count them ([[target, weapon, tags], ...]). Returns {"xp", "bounty", "levels_gained", "level"}.
static func raid_ended(state: Dictionary, extracted: bool, kills: Array) -> Dictionary:
	var id := str(state.get("selected", "vega"))
	if not LIST.has(id):
		id = "vega"
	var xp := XP_EXTRACT if extracted else XP_LOST
	var bounty := 0
	var c := char_of(state, id)
	var rank := passive_rank(c)
	if extracted:
		for kill: Variant in kills:
			if not (kill is Array and kill.size() >= 1):
				continue
			var kind := kind_of(str(kill[0]))
			xp += int(XP_KILL.get(kind, 0))
			if LIST[id]["passive"] == "bounty" and BOUNTY.has(kind):
				bounty += roundi(int(BOUNTY[kind]) * BOUNTY_RANKS[rank - 1])
	var gained := add_xp(state, id, xp)
	return {"xp": xp, "bounty": bounty, "levels_gained": gained, "level": level(state, id), "id": id}


## stat -> multiplier for a character's traits now.
static func multipliers(state: Dictionary, id: String) -> Dictionary:
	var out := {}
	var c := char_of(state, id)
	for i in 4:
		var stat := str(LIST[id]["traits"][i][0])
		out[stat] = float(out.get(stat, 1.0)) * (1.0 + trait_value(id, c, i))
	var passive := str(LIST[id]["passive"])
	var rank := passive_rank(c)
	if passive == "light_feet":
		out["steps"] = float(out.get("steps", 1.0)) * (1.0 - float(PASSIVES[passive]["ranks"][rank - 1]))
	elif passive == "steady_hands" and rank >= 3:
		out["heal_time"] = float(out.get("heal_time", 1.0)) * (1.0 - float(PASSIVES[passive]["ranks"][2]))
	return out


## This device's player is spawning as the picked character (from Profile's state).
static func begin(state: Dictionary) -> void:
	var id := str(state.get("selected", "vega"))
	if not LIST.has(id):
		id = "vega"
	active = multipliers(state, id)
	active_passive = str(LIST[id]["passive"])
	active_rank = passive_rank(char_of(state, id))
	hearing = float(active.get("hearing", 1.0))


## Back to a plain soldier (leaving the raid, the server).
static func end() -> void:
	active = {}
	active_passive = ""
	active_rank = 0
	hearing = 1.0


static func mult(stat: String) -> float:
	return float(active.get(stat, 1.0))


## The picked character's pocket width (Pack Rat adds slots).
static func pocket_width(state: Dictionary) -> int:
	var id := str(state.get("selected", "vega"))
	if not LIST.has(id) or LIST[id]["passive"] != "pack_rat":
		return POCKETS_WIDTH
	return POCKETS_WIDTH + int(PASSIVES["pack_rat"]["ranks"][passive_rank(char_of(state, id)) - 1])


## Hold Steady: the cut to recoil and spread now (0 = none). `still` and aiming are the caller's checks.
static func hold_steady_cut(prone: bool, crouching: bool) -> float:
	if active_passive != "hold_steady" or active_rank < 1:
		return 0.0
	if prone and active_rank < 2:
		return 0.0
	if crouching and not prone and active_rank < 3:
		return 0.0
	return float(PASSIVES["hold_steady"]["ranks"][active_rank - 1])


## Online: what others need to know about our character, after the look's digits: its index and how far our steps
## carry (percent - 50, two digits). The server checks it (clean_tag) before passing it on.
static func net_tag(state: Dictionary) -> String:
	var id := str(state.get("selected", "vega"))
	if not LIST.has(id):
		id = "vega"
	var steps := float(multipliers(state, id).get("steps", 1.0))
	return "%d%02d" % [ORDER.find(id), clampi(roundi(steps * 100.0) - 50, 0, 99)]


## A tag from the network, kept only if it's possible: a real character and steps no quieter than the quietest
## anyone can be (a made-up tag can't make you silent).
static func clean_tag(tag: String) -> String:
	if tag.length() != 3 or not tag.is_valid_int():
		return ""
	var index := int(tag[0])
	var steps := clampi(int(tag.substr(1)), 0, 99)
	if index < 0 or index >= ORDER.size():
		return ""
	return "%d%02d" % [index, maxi(steps, 5)]   # (at least 0.55: VEGA's quietest)


## How far someone's steps carry, from their look text (1.0 when it has no tag).
static func steps_of_look(text: String, look_length: int) -> float:
	var tag := clean_tag(text.substr(look_length))
	return 1.0 if tag == "" else (float(int(tag.substr(1))) + 50.0) / 100.0


## The hideout's check of a profile change (OnlineProfile.audit): unlocks paid for and allowed, XP and earned points
## untouched (only raids and expeditions move them, on the server), spent points within what was earned, a reset paid.
## Returns {"error": "" or why, "money": what it cost}.
static func changes(old: Dictionary, new: Dictionary) -> Dictionary:
	var a := clean(old.get("characters"))
	var b := clean(new.get("characters"))
	var cost := 0
	var levels: Dictionary = new.get("trader_levels", {}) if new.get("trader_levels") is Dictionary else {}
	for id: String in a["unlocked"]:
		if not (b["unlocked"] as Array).has(id):
			return {"error": "character locked again", "money": 0}
	for id: String in b["unlocked"]:
		if (a["unlocked"] as Array).has(id):
			continue
		var info: Dictionary = LIST[id]
		if info.get("files", false):
			return {"error": "character %s without its files" % id, "money": 0}
		var trader := str(info.get("trader", ""))
		if trader != "" and int(levels.get(trader, 1)) < int(info["trader_level"]):
			return {"error": "character %s before its trader level" % id, "money": 0}
		cost += int(info["price"])
	if int(b["exp_points"]) != int(a["exp_points"]):
		return {"error": "expedition points changed", "money": 0}
	for id: String in LIST:
		var ca := char_of(a, id)
		var cb := char_of(b, id)
		for key in ["xp", "lvl_points"]:
			if int(cb[key]) != int(ca[key]):
				return {"error": "character %s %s changed" % [id, key], "money": 0}
		if char_spent(cb) > 0 and not (b["unlocked"] as Array).has(id):
			return {"error": "points on locked character %s" % id, "money": 0}
		var lowered := false
		for key in SPEND_KEYS:
			if int(cb["spent"][key]) < int(ca["spent"][key]):
				lowered = true
		if lowered:
			cost += RESET_COST
	if points_spent(b) > points_earned(b):
		return {"error": "upgrade points overspent", "money": 0}
	return {"error": "", "money": cost}
