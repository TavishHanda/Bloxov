class_name Decor
## Your corner of the hideout (lively hideout, owner 2026-11-09: "customizable hideout, stuff that shows personality";
## he picked "your corner, unlocked decor"): your bunk in the quarters has spots (a poster, a flag, a rug, a lamp, a
## plant, your blanket), each with a few things to pick from. The first of each is yours from the start; the rest
## unlock with milestones the profile already keeps (no prices, nothing to buy). What you picked is saved with the
## profile like your look (account-wide: the same corner in PvE and PvP); something not unlocked in the stash you're
## on shows the spot's first option instead. Data only (no scenes, no game scripts): Profile loads and cleans it.
## The pieces themselves are drawn by HideoutDecor.

## Spot -> its options, in order: [id, name, unlock] where unlock is [kind, amount] (see unlocked()).
## kinds: "free", "raids", "extracts", "earned" (dollars), "jobs" (jobs done), "trader:<id>" (that trader's level),
## "quest:<id>" (that job done).
const SPOTS := {
	"poster": [
		["bloxov", "Bloxov", ["free", 0]],
		["nova", "NOVA recruits", ["raids", 5]],
		["exion", "Exion X1", ["extracts", 10]],
		["cat", "Hang in there", ["jobs", 3]],
		["map", "Map of Bloxov", ["extracts", 25]],
		["wanted", "Wanted: Bon", ["quest:big_game", 0]],
	],
	"flag": [
		["none", "Nothing", ["free", 0]],
		["bloxov", "Bloxov", ["free", 0]],
		["nova", "NOVA", ["extracts", 3]],
		["exion", "Exion", ["raids", 20]],
		["skull", "Skull", ["quest:big_game", 0]],
		["checker", "Checkered", ["extracts", 50]],
	],
	"rug": [
		["none", "Nothing", ["free", 0]],
		["olive", "Army blanket", ["free", 0]],
		["red", "Red rug", ["raids", 10]],
		["persian", "Fancy rug", ["trader:valuables", 2]],
		["bear", "Bear skin", ["earned", 100000]],
	],
	"lamp": [
		["none", "Nothing", ["free", 0]],
		["desk", "Desk lamp", ["free", 0]],
		["lantern", "Lantern", ["raids", 10]],
		["lava", "Lava lamp", ["trader:ming", 2]],
		["neon", "Neon X1", ["extracts", 40]],
	],
	"plant": [
		["none", "Nothing", ["free", 0]],
		["cactus", "Cactus", ["free", 0]],
		["fern", "Fern", ["extracts", 5]],
		["sunflower", "Sunflower", ["jobs", 9]],
		["bonsai", "Bonsai", ["trader:valuables", 3]],
	],
	"blanket": [
		["olive", "Olive", ["free", 0]],
		["red", "Red", ["raids", 5]],
		["blue", "Blue", ["extracts", 5]],
		["camo", "Camo", ["trader:guns", 2]],
		["leopard", "Leopard", ["trader:ming", 3]],
		["gold", "Gold", ["earned", 1000000]],
	],
}
## What each spot is called in the picker.
const SPOT_NAMES := {"poster": "POSTER", "flag": "FLAG", "rug": "RUG", "lamp": "LAMP", "plant": "PLANT",
	"blanket": "BLANKET"}


## A saved corner, made safe: only known spots and options (anything else is dropped).
static func clean(data: Variant) -> Dictionary:
	var out := {}
	if not data is Dictionary:
		return out
	for spot: String in SPOTS:
		var picked = (data as Dictionary).get(spot)
		if picked is String and option(spot, picked).size() > 0:
			out[spot] = picked
	return out


## The option [id, name, unlock] of `spot` called `id`, or [] if there's none.
static func option(spot: String, id: String) -> Array:
	for entry: Array in SPOTS.get(spot, []):
		if entry[0] == id:
			return entry
	return []


## What `spot` shows now: what you picked, if it's unlocked in this stash, else the spot's first option.
static func showing(spot: String) -> String:
	var picked := String(Profile.decor.get(spot, ""))
	var entry := option(spot, picked)
	if entry.is_empty() or not unlocked(entry[2]):
		return String(SPOTS[spot][0][0])
	return picked


## True if an unlock ([kind, amount]) is met by the profile showing now.
static func unlocked(unlock: Array) -> bool:
	var kind := String(unlock[0])
	var amount := int(unlock[1])
	match kind:
		"free":
			return true
		"raids", "extracts", "earned":
			return int(Profile.stats.get(kind, 0)) >= amount
		"jobs":
			return Profile.quests_done.size() >= amount
	if kind.begins_with("trader:"):
		return int(Profile.trader_levels.get(kind.substr(7), 1)) >= amount
	if kind.begins_with("quest:"):
		return Profile.quests_done.has(kind.substr(6))
	return false


## How to unlock it, for the picker ("10 raids", "Ming level 2", ...).
static func how_to_unlock(unlock: Array) -> String:
	var kind := String(unlock[0])
	var amount := int(unlock[1])
	match kind:
		"raids":
			return "%d raids" % amount
		"extracts":
			return "%d extracts" % amount
		"earned":
			return "$%s made" % _money(amount)
		"jobs":
			return "%d jobs done" % amount
	if kind.begins_with("trader:"):
		return "%s level %d" % [Traders.LIST[kind.substr(7)]["name"], amount]
	if kind.begins_with("quest:"):
		return "kill Bon (%s)" % String(Quests.LIST[kind.substr(6)]["name"]) if kind == "quest:big_game" \
			else "the job %s" % String(Quests.LIST[kind.substr(6)]["name"])
	return ""


## Picks `id` for `spot` (if it's unlocked) and saves.
static func pick(spot: String, id: String) -> bool:
	var entry := option(spot, id)
	if entry.is_empty() or not unlocked(entry[2]):
		return false
	Profile.decor[spot] = id
	Profile.save_profile()
	return true


static func _money(amount: int) -> String:
	var s := str(amount)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
