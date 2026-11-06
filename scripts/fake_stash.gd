class_name FakeStash
extends StashClient
## The Stash API in memory, for the smoke test (plan §12.2): the same calls and answers as server/src/api.js, without
## Postgres. Passwords are kept as given (test data only); everything goes through JSON both ways, like the real one.
## `down` makes every call fail, as when the database is unreachable.

var down := false
var accounts := {}   # lower-case username -> {id, username, password, recovery, display_name, banned, deleted, fails}
var profiles := {}   # id -> {data, revision, raid}
var sessions := {}   # token -> id
var results: Array = []
var saves := 0
var _next := 0


func request(action: String, body: Dictionary) -> Dictionary:
	if down:
		return {"error": "unavailable"}
	body = JSON.parse_string(JSON.stringify(body))
	var reply: Dictionary = call("_" + action, body)
	return JSON.parse_string(JSON.stringify(reply))


func _signup(body: Dictionary) -> Dictionary:
	var username := str(body.get("username", ""))
	if not RegEx.create_from_string("^[A-Za-z0-9_.-]{3,20}$").search(username):
		return {"error": "bad_username"}
	if str(body.get("password", "")).length() < 10:
		return {"error": "weak_password"}
	if accounts.has(username.to_lower()):
		return {"error": "username_taken"}
	_next += 1
	var id := "acct-%d" % _next
	var code := "CODE-%04d-TEST" % _next
	accounts[username.to_lower()] = {"id": id, "username": username, "password": body["password"], "recovery": code,
		"display_name": str(body.get("display_name", "")), "banned": "", "deleted": false, "fails": 0}
	profiles[id] = {"data": body["profile"], "revision": 1, "raid": {"state": "idle", "id": null, "snapshot": null}}
	var out := _signed_in(accounts[username.to_lower()])
	out["recovery_code"] = code
	return out


func _signed_in(account: Dictionary) -> Dictionary:
	for token: String in sessions.keys():
		if sessions[token] == account["id"]:
			sessions.erase(token)
	_next += 1
	var token := "token-%d-xxxxxxxxxxxxxxxxxxxx" % _next
	sessions[token] = account["id"]
	var profile: Dictionary = profiles[account["id"]]
	return {"account_id": account["id"], "username": account["username"], "display_name": account["display_name"],
		"token": token, "profile": profile["data"], "revision": profile["revision"], "raid": profile["raid"]}


func _login(body: Dictionary) -> Dictionary:
	var account: Dictionary = accounts.get(str(body.get("username", "")).to_lower(), {})
	if account.is_empty() or account["password"] != body.get("password"):
		return {"error": "bad_login"}
	if account["deleted"]:
		if body.get("cancel_delete") != true:
			return {"error": "deleted", "delete_on": "2099-01-01T00:00:00Z"}
		account["deleted"] = false
	if account["banned"] != "":
		return {"error": "banned", "until": account["banned"], "reason": "test"}
	return _signed_in(account)


func _resume(body: Dictionary) -> Dictionary:
	var id: String = sessions.get(str(body.get("token", "")), "")
	for account: Dictionary in accounts.values():
		if account["id"] == id and not account["deleted"]:
			var token := str(body["token"])
			var out := _signed_in(account)
			sessions.erase(out["token"])
			sessions[token] = id
			out["token"] = token
			return out
	return {"error": "bad_session"}


func _logout(body: Dictionary) -> Dictionary:
	for token: String in sessions.keys():
		if sessions[token] == body.get("account_id"):
			sessions.erase(token)
	return {"ok": true}


func _recover(body: Dictionary) -> Dictionary:
	var account: Dictionary = accounts.get(str(body.get("username", "")).to_lower(), {})
	if account.is_empty() or account["recovery"] != str(body.get("recovery_code", "")).to_upper():
		return {"error": "bad_recovery"}
	account["password"] = body["new_password"]
	account["recovery"] = "CODE-NEW-%d" % _next
	var out := _signed_in(account)
	out["recovery_code"] = account["recovery"]
	return out


func _save(body: Dictionary) -> Dictionary:
	var profile: Dictionary = profiles.get(body.get("account_id"), {})
	if profile.is_empty():
		return {"error": "no_account"}
	if int(profile["revision"]) != int(body.get("revision", -1)):
		return {"error": "conflict", "revision": profile["revision"]}
	saves += 1
	profile["data"] = body["profile"]
	profile["revision"] = int(profile["revision"]) + 1
	if body.get("raid") is Dictionary:
		profile["raid"] = {"state": body["raid"].get("state", "idle"), "id": body["raid"].get("id"),
			"snapshot": body["raid"].get("snapshot")}
	if body.get("result") is Dictionary:
		results.append(body["result"])
	return {"revision": profile["revision"]}


func _delete(body: Dictionary) -> Dictionary:
	for account: Dictionary in accounts.values():
		if account["id"] == body.get("account_id"):
			account["deleted"] = true
	_logout(body)
	return {"delete_on": "2099-01-01T00:00:00Z"}


func _export(body: Dictionary) -> Dictionary:
	for account: Dictionary in accounts.values():
		if account["id"] == body.get("account_id"):
			return {"format": "bloxov-pvp-data", "account": {"username": account["username"]},
				"profile": {"data": profiles[account["id"]]["data"]}, "raid_results": results}
	return {"error": "no_account"}


func _ban(body: Dictionary) -> Dictionary:
	for account: Dictionary in accounts.values():
		if account["id"] == body.get("account_id"):
			account["banned"] = "2099-01-01T00:00:00Z"
	_logout(body)
	return {"until": "2099-01-01T00:00:00Z", "permanent": false}
