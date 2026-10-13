class_name TabLock
extends RefCounted
## One game per browser (0.17.5, owner: a friend ran two raids in two tabs). Every tab keeps its own copy of the
## profile in memory and saves the whole thing, so a second tab could take the same gear into another raid and keep
## it if the first one died, or hand a copy to itself online. Now only the first tab plays: it holds a Web Lock for as
## long as it's open; any other tab waits behind a notice, never saves, and reloads (reading the fresh save) once the
## first tab closes. Off the web (desktop, server, tests) there is nothing to share, so the game always plays.

const LOCK_NAME := "bloxov_game"
## How long a new tab waits for the lock before it shows the notice (a reloading tab's old page can hold it a moment).
const WAIT_MS := 1500


## Asks for the lock (once per page). Safe to call any number of times.
static func start() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("""(function () {
	if (window.bloxovTab) return;
	if (!navigator.locks) { window.bloxovTab = 'owner'; return; }
	window.bloxovTab = 'pending';
	setTimeout(function () { if (window.bloxovTab === 'pending') window.bloxovTab = 'blocked'; }, %d);
	navigator.locks.request('%s', function () {
		var was = window.bloxovTab;
		window.bloxovTab = 'owner';
		if (was === 'blocked') location.reload();
		return new Promise(function () {});
	});
})()""" % [WAIT_MS, LOCK_NAME], true)


## "owner" (this tab plays), "pending" (still asking) or "blocked" (the game is open in another tab).
static func state() -> String:
	if not OS.has_feature("web"):
		return "owner"
	var value = JavaScriptBridge.eval("window.bloxovTab || ''", true)
	return value if value is String and value != "" else "pending"


static func owns() -> bool:
	return state() == "owner"
