class_name Matchmaker
extends RefCounted
## The server's bookkeeping for parties, the queue and running raids (no networking here: Network calls it and
## sends the results, and the smoke test drives it directly).
##
## Owner rules (0.7.3): parties are duos at most and join each other with a party code. Solos and duos queue into
## the same raids. Once MIN_PLAYERS are waiting, a countdown (queue_countdown, 30 s) gives others time to join;
## then everyone waiting goes into one raid (up to MAX_PLAYERS, parties never split; it starts at once when full).
## No joining a raid that's running. "Start now" puts a party in a raid of its own (testing, playing alone).
## Every player is always in a party: alone, their party is just them (with its own code to share).

const MAX_PARTY := 2
const MIN_PLAYERS := 2
const MAX_PLAYERS := 6
## Raids at once on one server (each will get its own world on the server once hits move there).
const MAX_RAIDS := 4
## A raid is closed this long after its clock runs out, even if a player never said they left.
const RAID_GRACE := 120.0
const CODE_LETTERS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

var queue_countdown := 30.0
var raid_time := 600.0

## peer -> {name, party (code), raid (id, 0 = in the hideout)}
var players := {}
## code -> {members: Array[int] (first = leader), queued: bool, queued_at: float}
var parties := {}
## id -> {players: Array[int], started: float (seconds), seed: int, teams: {peer: party code},
##        spawns: {peer: [slot, place]}} (squads spawn together, 0.9.5: see spawn_slots)
var raids := {}
## Seconds until the queue's raid starts (-1 = no countdown running).
var countdown_left := -1.0
## Parties whose members need a fresh party update (Network sends them, then clears this).
var changed_parties := {}

var _clock := 0.0
var _next_raid_id := 1


func add_player(peer: int, player_name: String) -> void:
	player_name = player_name.strip_edges().left(16)
	if player_name == "":
		player_name = "Player %d" % (peer % 1000)
	players[peer] = {"name": player_name, "party": "", "raid": 0}
	_new_party(peer)


func remove_player(peer: int) -> void:
	if not players.has(peer):
		return
	leave_raid(peer)
	_leave_party_of(peer)
	players.erase(peer)


func party_of(peer: int) -> Dictionary:
	return parties.get(players[peer]["party"], {}) if players.has(peer) else {}


func is_leader(peer: int) -> bool:
	var party := party_of(peer)
	return not party.is_empty() and party["members"][0] == peer


## Joins a friend's party by its code. Returns "" or why not.
func join_party(peer: int, code: String) -> String:
	code = code.strip_edges().to_upper()
	if not players.has(peer):
		return "Not connected."
	if players[peer]["raid"] != 0:
		return "You're in a raid."
	if code == players[peer]["party"]:
		return "That's your own party code."
	if not parties.has(code):
		return "No party with code %s." % code
	var party: Dictionary = parties[code]
	if party["members"].size() >= MAX_PARTY:
		return "That party is full (duos max)."
	_leave_party_of(peer)
	party["members"].append(peer)
	players[peer]["party"] = code
	# The party changed, so it leaves the queue; the leader queues again when ready.
	party["queued"] = false
	changed_parties[code] = true
	return ""


## Leaves your party for a party of your own.
func leave_party(peer: int) -> void:
	if players.has(peer) and players[peer]["raid"] == 0 and party_of(peer)["members"].size() > 1:
		_leave_party_of(peer)
		_new_party(peer)


## Puts your party in (or takes it out of) the queue. Only the leader can. Returns "" or why not.
func set_queued(peer: int, on: bool) -> String:
	var problem := _leader_problem(peer)
	if problem != "":
		return problem
	var party := party_of(peer)
	party["queued"] = on
	party["queued_at"] = _clock
	changed_parties[players[peer]["party"]] = true
	return ""


## Starts a raid right away with just your party (no queue). Returns the raid id, or 0 with `why` filled in.
func start_now(peer: int, why: Array = []) -> int:
	var problem := _leader_problem(peer)
	if problem == "" and raids.size() >= MAX_RAIDS:
		problem = "The server is full right now. Try again in a minute."
	if problem != "":
		why.append(problem)
		return 0
	return _start_raid([players[peer]["party"]])


## Back to the hideout (raid over, or quit). The raid closes once everyone has left.
func leave_raid(peer: int) -> void:
	if not players.has(peer) or players[peer]["raid"] == 0:
		return
	var id: int = players[peer]["raid"]
	players[peer]["raid"] = 0
	changed_parties[players[peer]["party"]] = true
	if raids.has(id):
		raids[id]["players"].erase(peer)
		if raids[id]["players"].is_empty():
			raids.erase(id)


func raid_time_left(id: int) -> float:
	return raid_time - (_clock - raids[id]["started"]) if raids.has(id) else 0.0


## Players waiting in the queue right now.
func queued_count() -> int:
	var count := 0
	for code in _queued_parties():
		count += parties[code]["members"].size()
	return count


## Advances the clock; starts the queue's raid when it's due. Returns the ids of raids that started.
func tick(delta: float) -> Array[int]:
	_clock += delta
	var started: Array[int] = []
	for id in raids.keys():
		if raid_time_left(id) < -RAID_GRACE:
			for peer in raids[id]["players"].duplicate():
				leave_raid(peer)
			raids.erase(id)
	var waiting := queued_count()
	if waiting < MIN_PLAYERS:
		countdown_left = -1.0
		return started
	if countdown_left < 0.0:
		countdown_left = queue_countdown
	countdown_left -= delta
	if (countdown_left <= 0.0 or waiting >= MAX_PLAYERS) and raids.size() < MAX_RAIDS:
		# Everyone who fits, first come first served, without splitting a party.
		var picked: Array = []
		var count := 0
		for code in _queued_parties():
			var size: int = parties[code]["members"].size()
			if count + size <= MAX_PLAYERS:
				picked.append(code)
				count += size
		started.append(_start_raid(picked))
		countdown_left = -1.0
	return started


func _start_raid(codes: Array) -> int:
	var id := _next_raid_id
	_next_raid_id += 1
	var raid := {"players": [], "started": _clock, "seed": randi(), "teams": {}}
	var teams := []
	for code in codes:
		parties[code]["queued"] = false
		changed_parties[code] = true
		teams.append(parties[code]["members"].duplicate())
		for peer in parties[code]["members"]:
			raid["players"].append(peer)
			raid["teams"][peer] = code
			players[peer]["raid"] = id
	raid["spawns"] = spawn_slots(teams, raid["seed"])
	raids[id] = raid
	return id


## Where everyone starts (owner, 0.9.5: squads spawn together): each squad gets its own spawn slot (shuffled by the
## raid's seed), and its members a place next to each other there. peer -> [slot, place]. The raid turns a slot into
## a spawn point (Raid.spawn_position).
static func spawn_slots(teams: Array, seed_value: int) -> Dictionary:
	var order := range(teams.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	var result := {}
	for t in teams.size():
		var members: Array = teams[t]
		for place in members.size():
			result[members[place]] = [order[t], place]
	return result


func _leader_problem(peer: int) -> String:
	if not players.has(peer):
		return "Not connected."
	if not is_leader(peer):
		return "Only the party leader can do that."
	for member in party_of(peer)["members"]:
		if players[member]["raid"] != 0:
			return "Wait until everyone in your party is back from their raid."
	return ""


## Queued parties whose members are all in the hideout, oldest first.
func _queued_parties() -> Array:
	var list := []
	for code in parties:
		var party: Dictionary = parties[code]
		if party["queued"] and party["members"].all(func(p: int) -> bool: return players[p]["raid"] == 0):
			list.append(code)
	list.sort_custom(func(a: String, b: String) -> bool: return parties[a]["queued_at"] < parties[b]["queued_at"])
	return list


func _new_party(peer: int) -> void:
	var code := ""
	while code == "" or parties.has(code):
		code = ""
		for i in 4:
			code += CODE_LETTERS[randi() % CODE_LETTERS.length()]
	parties[code] = {"members": [peer], "queued": false, "queued_at": 0.0}
	players[peer]["party"] = code
	changed_parties[code] = true


func _leave_party_of(peer: int) -> void:
	var code: String = players[peer]["party"]
	if not parties.has(code):
		return
	var party: Dictionary = parties[code]
	party["members"].erase(peer)
	party["queued"] = false
	if party["members"].is_empty():
		parties.erase(code)
		changed_parties.erase(code)
	else:
		changed_parties[code] = true
