class_name HostView
## Hideout visits, part 2 (0.39.0): in a PvP party, everyone walks round the LEADER's hideout. What makes one
## hideout look different from another is small: the corner's decor, the trophy shelf (from the record), and the
## truck in the garage. The leader's game sends that as a little snapshot (of_profile) through the server to the
## party (Network.send_hideout_look); the others show it while they're visiting (`host`), and their own when they
## aren't. Looks only: data from the profile, no text anyone writes. HideoutDecor, HideoutTrophies and HideoutGarage
## read through here instead of Profile. Data only (no scenes, no game scripts).

const TRADERS := ["guns", "supplies", "valuables", "ming", "meds"]

## The leader's cleaned snapshot while we're visiting them, else {} (our own hideout).
static var host := {}
## The leader's name ("" when at home).
static var host_name := ""


static func active() -> bool:
	return not host.is_empty()


## This profile's hideout, as a snapshot for visitors.
static func of_profile() -> Dictionary:
	var decor := {}
	for spot: String in Decor.SPOTS:
		decor[spot] = Decor.showing(spot)
	var traders := {}
	for id: String in TRADERS:
		traders[id] = int(Profile.trader_levels.get(id, 1))
	return {
		"decor": decor,
		"raids": int(Profile.stats.get("raids", 0)),
		"extracts": int(Profile.stats.get("extracts", 0)),
		"earned": int(Profile.stats.get("earned", 0)),
		"jobs": Profile.quests_done.size(),
		"bon": Profile.quests_done.has("big_game") or int(Profile.quest_progress.get("big_game", 0)) >= 1,
		"traders": traders,
		"bench_top": Profile.bench_level >= Crafting.max_level(),
		"truck": Profile.truck.duplicate(),
	}


## A snapshot that came over the network, made safe: known decor and truck parts, sane numbers. {} if it isn't one.
static func clean(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var given: Dictionary = data
	var out := {"decor": Decor.clean(given.get("decor")), "traders": {}, "truck": []}
	for key in ["raids", "extracts", "earned", "jobs"]:
		var n = given.get(key)
		out[key] = clampi(int(n), 0, 1_000_000_000) if n is int or n is float else 0
	out["bon"] = given.get("bon") == true
	out["bench_top"] = given.get("bench_top") == true
	var traders = given.get("traders")
	for id: String in TRADERS:
		var lv = traders.get(id) if traders is Dictionary else null
		out["traders"][id] = clampi(int(lv), 1, 9) if lv is int or lv is float else 1
	var truck = given.get("truck")
	if truck is Array:
		for part: Variant in truck:
			if part is String and Expedition.PARTS.has(part) and not out["truck"].has(part):
				out["truck"].append(part)
	return out


# --- What the hideout shows: the leader's while visiting, else ours --------------------

static func decor_showing(spot: String) -> String:
	if active():
		var picked := String(host["decor"].get(spot, ""))
		return picked if Decor.option(spot, picked).size() > 0 else String(Decor.SPOTS[spot][0][0])
	return Decor.showing(spot)


static func stat(key: String) -> int:
	return int(host.get(key, 0)) if active() else int(Profile.stats.get(key, 0))


static func jobs_done() -> int:
	return int(host.get("jobs", 0)) if active() else Profile.quests_done.size()


static func killed_bon() -> bool:
	if active():
		return host.get("bon") == true
	return Profile.quests_done.has("big_game") or int(Profile.quest_progress.get("big_game", 0)) >= 1


static func trader_level(id: String) -> int:
	return int(host["traders"].get(id, 1)) if active() else int(Profile.trader_levels.get(id, 1))


static func bench_top() -> bool:
	return host.get("bench_top") == true if active() else Profile.bench_level >= Crafting.max_level()


static func truck() -> Array:
	return host.get("truck", []) if active() else Array(Profile.truck)
