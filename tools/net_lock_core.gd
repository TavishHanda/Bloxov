extends RefCounted
## The online contract's fingerprint (0.35.2), shared by tests/smoke_test.gd (section "netlock") and tools/net_lock.gd.
## It covers every @rpc line with its func signature, and the shared rule files with comments and blank lines removed.
## tests/ and tools/ are left out of the exports, so nothing in the game loads this. Rule: docs/context/ONLINE.md.

const LOCK_PATH := "res://tests/net_lock.txt"

## Files whose contents both sides must agree on (items, prices, stock, recipes, quests, accounts, anti-cheat, matchmaking).
const RULE_FILES: Array[String] = [
	"scripts/item_db.gd", "scripts/online_profile.gd", "scripts/net_guard.gd", "scripts/net_accounts.gd",
	"scripts/matchmaker.gd", "scripts/traders.gd", "scripts/quests.gd", "scripts/crafting.gd", "scripts/health.gd",
]


## [[entry name, hash], ...]: "rpc" first, then each rule file.
static func fingerprint() -> Array:
	var out: Array = []
	var rpcs := PackedStringArray()
	var names := PackedStringArray()
	var dir := DirAccess.open("res://scripts")
	for f in dir.get_files():
		if f.ends_with(".gd"):
			names.append(f)
	names.sort()
	for f in names:
		var lines := FileAccess.get_file_as_string("res://scripts/" + f).split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("@rpc"):
				# (the func line is the next one; a blank or comment line between them is skipped)
				var j := i + 1
				while j < lines.size() and (lines[j].strip_edges() == "" or lines[j].strip_edges().begins_with("#")):
					j += 1
				rpcs.append("%s: %s | %s" % [f, line, lines[j].strip_edges() if j < lines.size() else ""])
	out.append(["rpc", "\n".join(rpcs).sha256_text().substr(0, 12)])
	for path in RULE_FILES:
		var kept := PackedStringArray()
		for raw in FileAccess.get_file_as_string("res://" + path).split("\n"):
			var t := raw.strip_edges()
			if t != "" and not t.begins_with("#"):
				kept.append(raw.rstrip(" \t\r"))
		out.append([path, "\n".join(kept).sha256_text().substr(0, 12)])
	return out


static func project_net_version() -> int:
	return int(ProjectSettings.get_setting("application/config/net_version", 0))


## The text of the lock file for the current code.
static func lock_text() -> String:
	var lines := PackedStringArray([str(project_net_version())])
	for e in fingerprint():
		lines.append("%s %s" % [e[0], e[1]])
	return "\n".join(lines) + "\n"


## What changed against the lock file: [] when it matches, else plain sentences.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(LOCK_PATH):
		out.append("tests/net_lock.txt is missing")
		return out
	var lines := FileAccess.get_file_as_string(LOCK_PATH).strip_edges().split("\n")
	var recorded := {}
	for i in range(1, lines.size()):
		var parts := lines[i].split(" ")
		if parts.size() == 2:
			recorded[parts[0]] = parts[1]
	if int(lines[0]) != project_net_version():
		out.append("config/net_version is %d but the lock was recorded at %d" % [project_net_version(), int(lines[0])])
	for e in fingerprint():
		if not recorded.has(e[0]):
			out.append("%s is new in the lock" % e[0])
		elif recorded[e[0]] != e[1]:
			out.append("%s changed" % ("the @rpc list" if e[0] == "rpc" else e[0]))
		recorded.erase(e[0])
	for k in recorded:
		out.append("%s is no longer covered" % k)
	return out
