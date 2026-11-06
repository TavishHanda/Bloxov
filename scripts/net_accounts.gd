class_name NetAccounts
extends RefCounted
## The server's side of PvP accounts and the online stash (Stash update, 0.31; docs/STASH_UPDATE_PLAN.md §5, §7).
## Net (net.gd) owns the RPCs and passes them here. A signed-in player's online profile lives in memory on the
## server (the source of truth while they're connected) and is written through to the Stash API after every change,
## one write at a time per account. The connection is the session: one per account (owner), TAKE OVER HERE moves it.
##
## Raids (plan §7.3-7.4): as a raid starts the server issues the kit from the saved loadout (the client's own kit
## list is ignored) and saves the profile as in the raid with the kit at risk; dying, leaving or dropping out keeps
## only the secure pocket; extracting (checked by the server) keeps what they came out with, which may not hold more
## than the server counted them carrying. A raid from before a server restart is put back as it was ("crash").
##
## The hideout (plan Phase 3, 0.31.3): the game still runs it and sends the whole profile after each change, and the
## server only takes a profile the last one could have become there (OnlineProfile.audit: nothing bought without
## paying a trader's price, no money from nowhere, no free repairs, marks or stash rows). One it can't is refused and
## the game gets the server's copy back. Ming's boxes are rolled here.

const IN_RAID := "in_raid"
const IDLE := "idle"

var net: Node
var api: StashClient
## This server run's id: raid ids are "<boot>-<n>", so a raid from an earlier run is known to be gone.
var boot := ""
## peer -> record: {account_id, username, profile, revision, raid: {state, id, snapshot}, results: [], busy, dirty,
## kit, final, extracted, display_name}
var by_peer := {}
## account id -> peer.
var by_account := {}


func _init(owner: Node, stash_api: StashClient) -> void:
	net = owner
	api = stash_api
	boot = "%x" % (int(Time.get_unix_time_from_system()) % 0xFFFFFF)


func signed_in(peer: int) -> bool:
	return by_peer.has(peer)


## A sign-in screen action from `peer`. Answers with Net._account_result.
func handle(peer: int, action: String, fields: Dictionary) -> void:
	var text := func(key: String, longest: int) -> String:
		var value: Variant = fields.get(key, "")
		return (value as String).left(longest) if value is String else ""
	var take_over: bool = fields.get("take_over") == true
	var reply: Dictionary
	match action:
		"sign_up":
			var username: String = text.call("username", 20)
			if NameFilter.is_blocked(username):
				_answer(peer, action, {"error": "bad_username"})
				return
			reply = await api.request("signup", {"username": username, "password": text.call("password", 128),
				"display_name": _name(peer), "profile": OnlineProfile.fresh()})
		"sign_in":
			reply = await api.request("login", {"username": text.call("username", 20), "password": text.call("password", 128),
				"cancel_delete": fields.get("cancel_delete") == true})
		"resume":
			reply = await api.request("resume", {"token": text.call("token", 100)})
		"recover":
			reply = await api.request("recover", {"username": text.call("username", 20),
				"recovery_code": text.call("code", 20), "new_password": text.call("password", 128)})
		"sign_out", "delete":
			var record: Dictionary = by_peer.get(peer, {})
			if record.is_empty():
				return
			if record["raid"]["state"] == IN_RAID:
				_answer(peer, action, {"error": "in_raid"})
				return
			sign_out(peer)
			reply = await api.request("logout" if action == "sign_out" else "delete", {"account_id": record["account_id"]})
			_answer(peer, action, reply if reply.has("error") else {"done": true, "delete_on": reply.get("delete_on", "")})
			return
		_:
			return
	if not net.matchmaker.players.has(peer):
		return   # (gone while the API answered)
	if reply.has("error"):
		_answer(peer, action, reply)
		return
	var other: int = by_account.get(reply["account_id"], 0)
	if other != 0 and other != peer:
		if not take_over:
			_answer(peer, action, {"error": "in_use"})
			return
		net._log("%s took over their account from peer %d" % [reply["username"], other])
		sign_out(other)
		if net._peer_open(other):
			net._account_result.rpc_id(other, "signed_out", false, {"error": "taken_over"})
	if by_peer.has(peer):
		sign_out(peer)
	_bind(peer, reply)
	var record: Dictionary = by_peer[peer]
	var out := {"username": reply["username"], "token": reply["token"], "profile": record["profile"]}
	if reply.has("recovery_code"):
		out["recovery_code"] = reply["recovery_code"]
	_answer(peer, action, out)


func _answer(peer: int, action: String, data: Dictionary) -> void:
	if net._peer_open(peer):
		net._account_result.rpc_id(peer, action, not data.has("error"), data)


func _name(peer: int) -> String:
	return str(net.matchmaker.players[peer]["name"]) if net.matchmaker.players.has(peer) else ""


func _bind(peer: int, reply: Dictionary) -> void:
	var profile := OnlineProfile.clean(reply.get("profile"))
	if profile.is_empty():
		profile = OnlineProfile.fresh()
	var raid: Dictionary = reply.get("raid", {}) if reply.get("raid") is Dictionary else {}
	var record := {"account_id": reply["account_id"], "username": reply["username"], "profile": profile,
		"revision": int(reply.get("revision", 1)), "raid": {"state": IDLE, "id": null, "snapshot": null},
		"results": [], "busy": false, "dirty": false, "kit": {}, "final": null, "extracted": false,
		"display_name": _name(peer), "after_raid": false}
	by_peer[peer] = record
	by_account[record["account_id"]] = peer
	net._log("%s signed in (peer %d)" % [record["username"], peer])
	if raid.get("state") == IN_RAID:
		# A raid the server never finished: from an earlier run (a restart or crash: the gear comes back, owner
		# 2026-11-04), or from this run (they dropped out before it was saved: lost, as when leaving).
		var raid_id := str(raid.get("id", ""))
		var snapshot: Variant = raid.get("snapshot")
		var crashed := not raid_id.begins_with(boot + "-")
		if crashed and snapshot is Dictionary and OnlineProfile.loadout_ok(snapshot):
			profile["loadout"] = snapshot
		record["raid"] = {"state": IN_RAID, "id": raid_id, "snapshot": snapshot}
		_finish(record, "crash" if crashed else "left", 0)
		net._log("%s: raid %s put right as %s" % [record["username"], raid_id, "crash" if crashed else "left"])
	elif record["display_name"] != str(reply.get("display_name", "")):
		_persist(record)   # (the name they play under: what others see, never the username)


## Signed out, taken over, or gone: a raid they're in counts as left (gear lost).
func sign_out(peer: int) -> void:
	var record: Dictionary = by_peer.get(peer, {})
	if record.is_empty():
		return
	if record["raid"]["state"] == IN_RAID:
		raid_over(peer, "left")
	by_peer.erase(peer)
	if by_account.get(record["account_id"]) == peer:
		by_account.erase(record["account_id"])


## The hideout's whole PvP profile from the client (until the server runs the hideout, plan Phase 3). Not during a
## raid. The server keeps its own stats.
func save(peer: int, data: Variant) -> bool:
	var record: Dictionary = by_peer.get(peer, {})
	if record.is_empty() or record["raid"]["state"] == IN_RAID or int(net.matchmaker.players[peer]["raid"]) != 0:
		return true
	var clean := OnlineProfile.clean(data)
	if clean.is_empty():
		return false
	clean["stats"] = record["profile"]["stats"]
	var why := OnlineProfile.audit(record["profile"], clean, record["after_raid"])
	if why != "":
		# Refused: their game shows the server's copy again. Not a strike (a lag-crossed save can land here too).
		net._log("%s: hideout change refused (%s)" % [record["username"], why])
		if net._peer_open(peer):
			net._profile_sync.rpc_id(peer, record["profile"])
			net._notice.rpc_id(peer, "The server didn't accept that change, so your PvP stash is back as it was.")
		return true
	record["after_raid"] = false
	record["profile"] = clean
	_persist(record)
	return true


## One of Ming's boxes, rolled here (PvP): their game is told what came out and gets the stash with it in.
func open_box(peer: int, box: String) -> void:
	var record: Dictionary = by_peer.get(peer, {})
	if record.is_empty() or record["raid"]["state"] == IN_RAID:
		return
	var id := OnlineProfile.open_box(record["profile"], box)
	if id != "":
		_persist(record)
	if net._peer_open(peer):
		net._box_result.rpc_id(peer, box, id)
		net._profile_sync.rpc_id(peer, record["profile"])


## A raid is starting with `peer` in it: issue their kit (the loadout saved on the server) and put it at risk.
## Returns the kit, or {} when they aren't signed in (then their game's own kit list counts, as before accounts).
func raid_starting(peer: int, raid: int) -> Dictionary:
	var record: Dictionary = by_peer.get(peer, {})
	if record.is_empty():
		return {}
	if record["raid"]["state"] == IN_RAID:
		raid_over(peer, "left")
	var kit: Dictionary = record["profile"].get("loadout", {})
	record["kit"] = kit
	record["final"] = null
	record["extracted"] = false
	record["raid"] = {"state": IN_RAID, "id": "%s-%d" % [boot, raid], "snapshot": kit}
	record["profile"]["loadout"] = OnlineProfile.death_loadout(kit)
	record["profile"]["free_kit_raid"] = -1
	_persist(record)
	return kit


## The server accepted their extract. Saved once their game has sent what they came out with.
func extracted(peer: int) -> void:
	var record: Dictionary = by_peer.get(peer, {})
	if record.is_empty() or record["raid"]["state"] != IN_RAID:
		return
	record["extracted"] = true
	if record["final"] != null:
		raid_over(peer, "extracted")


## What their game says they came out with. More of anything than the server counted them carrying is a strike.
func final_kit(peer: int, loadout: Variant, carried: Dictionary) -> bool:
	var record: Dictionary = by_peer.get(peer, {})
	if record.is_empty() or record["raid"]["state"] != IN_RAID:
		return true
	if not OnlineProfile.loadout_ok(loadout):
		return false
	var extra := OnlineProfile.more_than(loadout, carried)
	if not extra.is_empty():
		net._caught(peer, "item", "came out with more than they carry: %s" % extra)
	record["final"] = loadout
	if record["extracted"]:
		raid_over(peer, "extracted")
	return true


## Their raid is over: "extracted", "killed" or "left". Saved, and their game gets the profile as the server has it.
func raid_over(peer: int, result: String) -> void:
	var record: Dictionary = by_peer.get(peer, {})
	if record.is_empty() or record["raid"]["state"] != IN_RAID:
		return
	var value := 0
	if result == "extracted" and record["final"] is Dictionary:
		record["profile"]["loadout"] = record["final"]
		value = maxi(OnlineProfile.worth(record["final"]) - OnlineProfile.worth(record["kit"]), 0)
	else:
		result = "killed" if result == "killed" else "left"
	_finish(record, result, value)
	if net._peer_open(peer):
		net._profile_sync.rpc_id(peer, record["profile"])


func _finish(record: Dictionary, result: String, value: int) -> void:
	var stats: Dictionary = record["profile"]["stats"]
	stats["raids"] = int(stats.get("raids", 0)) + 1
	if result == "extracted":
		stats["extracts"] = int(stats.get("extracts", 0)) + 1
		stats["earned"] = int(stats.get("earned", 0)) + value
	elif result != "crash":
		stats["deaths"] = int(stats.get("deaths", 0)) + 1
	record["results"].append({"raid_id": record["raid"]["id"], "result": result, "loot_value": value})
	record["raid"] = {"state": IDLE, "id": null, "snapshot": null}
	record["kit"] = {}
	record["final"] = null
	record["after_raid"] = true   # (the next hideout save may carry the raid's quest progress)
	_persist(record)


## Writes the record to the API, one write at a time; changes made meanwhile go in the next one. The server's copy
## wins a revision clash (it is the only writer for a signed-in account). A failing API is retried a few times.
func _persist(record: Dictionary) -> void:
	if record["busy"]:
		record["dirty"] = true
		return
	record["busy"] = true
	var tries := 0
	while true:
		record["dirty"] = false
		var body := {"account_id": record["account_id"], "revision": record["revision"], "profile": record["profile"],
			"raid": record["raid"], "display_name": record["display_name"]}
		var sent_result := false
		if not record["results"].is_empty():
			body["result"] = record["results"][0]
			sent_result = true
		var reply: Dictionary = await api.request("save", body)
		if reply.has("revision") and not reply.has("error"):
			record["revision"] = int(reply["revision"])
			if sent_result:
				record["results"].pop_front()
			tries = 0
		elif reply.get("error") == "conflict":
			record["revision"] = int(reply.get("revision", record["revision"]))
			record["dirty"] = true
		else:
			tries += 1
			net._log("saving %s's stash failed (%s), try %d" % [record["username"], reply.get("error", "?"), tries])
			if tries >= 5:
				break
			await net.get_tree().create_timer(2.0 * tries).timeout
			record["dirty"] = true
		if not record["dirty"] and record["results"].is_empty():
			break
	record["busy"] = false
