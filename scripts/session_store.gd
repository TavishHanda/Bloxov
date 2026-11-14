class_name SessionStore
extends RefCounted
## The PvP sign-in's remember-me session (Stash update plan §5.3, 0.31): the server's session token and the username
## it belongs to, kept so the next launch doesn't ask for the password. It is a session the server can revoke, never
## the account itself: clearing it only means typing the password again. Saved to user://session.json and, on the web,
## to localStorage as well (the same two copies the profile keeps). The password is never stored.
## Phase 1 (0.31.0): stored and read only; nothing sends it yet (the accounts step sends it once, in the hello).

const PATH := "user://session.json"
const WEB_KEY := "bloxov_session"
## The REMEMBER ME tick on the sign-in page (0.35.4): on by default; off means no token is kept on this device.
const PREF_PATH := "user://remember_me.txt"


## Keeps a session: `token` from the server, `username` to show on the sign-in panel.
static func save(token: String, username: String) -> void:
	var text := JSON.stringify({"token": token, "username": username})
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.setItem('%s', %s) } catch (e) {}" % [WEB_KEY, JSON.stringify(text)], true)


## The kept session: {"token", "username"}, or {} when there is none (or it's unreadable).
static func read() -> Dictionary:
	var text := ""
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file != null:
		text = file.get_as_text()
		file.close()
	if text == "" and OS.has_feature("web"):
		var web = JavaScriptBridge.eval("(function () { try { return localStorage.getItem('%s') || '' } catch (e) { return '' } })()" % WEB_KEY, true)
		text = web if web is String else ""
	var data = JSON.parse_string(text) if text != "" else null
	if not data is Dictionary or not data.get("token") is String or not data.get("username") is String \
			or data["token"] == "":
		return {}
	return {"token": data["token"], "username": data["username"]}


## Signing out (or a revoked session): both copies gone.
static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.removeItem('%s') } catch (e) {}" % WEB_KEY, true)


## Whether sign-ins are kept (the REMEMBER ME tick). On unless the player turned it off.
static func wants_remember() -> bool:
	if not FileAccess.file_exists(PREF_PATH):
		return true
	return FileAccess.get_file_as_string(PREF_PATH).strip_edges() != "off"


## Sets the tick. Turning it off also forgets any session kept so far.
static func set_remember(on: bool) -> void:
	var file := FileAccess.open(PREF_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("on" if on else "off")
		file.close()
	if not on:
		clear()
