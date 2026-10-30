class_name Network
extends Node
## Multiplayer connection (autoload "Net"; other scripts use it as `Network.main`, which also works in the
## headless test, where autoload names aren't known when scripts compile). Offline by default: solo raids never
## touch the network.
##
## Browsers can't host, so online raids run on a dedicated server: this same project started with
##   godot --headless -- --server [--port=9080]
## (or the PORT environment variable, which hosting services set).
##
## Going online (hideout): connect, and the server checks the game version. Then parties, the queue and
## "start now" (Matchmaker, on the server) decide who plays together; when a raid starts, every player in it
## loads the raid scene. One server runs several raids at once, each with its own copy of the map (RaidWorld).
## In a raid the server relays every player's state to the others in that raid, owns the raid clock and which
## extracts are open, and decides what every shot hit (walls block, lag compensated, damage from the weapon).
## Each player still applies hits to their own health (through their armor), and AI and loot still run on each
## player's own machine until the next steps (docs/MULTIPLAYER_PLAN.md).

## Connected and let in (the hideout shows the party/queue screen).
signal connected
## Couldn't connect, or the server turned us away (the reason says why).
signal connect_failed(reason: String)
## The connection dropped (the server stopped, or the internet went away).
signal connection_lost
## Party, queue, or a message from the server changed (the hideout redraws).
signal party_changed
signal queue_changed
signal notice(text: String)
## The server put us in a raid: load it.
signal raid_started
## In a raid: another player's shot hit us (damage before our armor); our shot hit someone; we killed someone.
## (`burst`: -1 for anything but an AI's shot, else its opening-burst number or 0; see Player.take_ai_hit.)
signal got_hit(amount: int, from: Vector3, headshot: bool, burst: int)
signal shot_confirmed(headshot: bool, amount: int, pos: Vector3)
## The damage your hit on another player really did, after their armor (0.17.1): for the damage number.
signal damage_shown(amount: int, headshot: bool, pos: Vector3)
signal kill_confirmed(target: String)
## The kill feed (0.18.9): a player in our raid died. `killer` is "" when nobody gets the credit (the AI, a fall);
## `mine` = we killed them, `ours` = we were the one who died.
signal kill_feed(killer: String, victim: String, mine: bool, ours: bool)
## A scav rifle-butted us; something a scav did that we should see/hear (RaidWorld.enemy_event kinds).
signal bashed(amount: int, from: Vector3, shove: float, aim_block: float)
signal enemy_event(id: int, kind: String, pos: Vector3)
## Loot: the server let us open a container (its contents), someone else has it open, a bag appeared or went.
signal container_opened(id: String, data: Array)
signal container_busy(id: String)
signal bag_spawned(id: String, pos: Vector3, yaw: float, title: String, search: float)
signal bag_removed(id: String)
## Key doors (0.14.0): someone in the raid unlocked one (its node name).
signal door_opened(id: String)
## Someone in our raid broke a window pane (0.18.8): its number in the map's BoxMap `window_panes`.
signal window_broken(pane: int)
## Doors (0.17): one in the raid swung open (1, -1) or shut (0): its node name under Doors.
signal door_state(id: String, state: int)
## A dropped backpack's lid opened or shut (0.17.10).
signal lid_moved(id: String, open: bool)
## Someone else in the raid threw a grenade (0.14.5): show it (the server's copy does the damage).
signal grenade_seen(from: Vector3, vel: Vector3)
## Someone else in the raid fired (0.15.28): play their shot and show the tracer (`end`: where it stopped).
signal player_fired(peer: int, from: Vector3, end: Vector3, weapon: String, suppressed: bool)
## Downed (0.9.2): a teammate started or stopped holding F on us; they finished (we're back up).
signal revive_changed(on: bool)
signal revived
## The server didn't take our last moves (0.25.0): we go back to `pos`, where it has us.
signal put_back(pos: Vector3)
## The server says we're dead (0.25.2: its count of our health hit 0 and we stayed up).
signal forced_dead

enum Mode { OFFLINE, SERVER, CLIENT }

const DEFAULT_PORT := 9080
## The hosted server (see fly.toml / heroku.yml). A local test server is ws://localhost:9080.
const DEFAULT_ADDRESS := "wss://bloxov-server-0f9c9a343ceb.herokuapp.com"
const RAID_TIME := 600.0
## Player state updates per second, both ways.
const SEND_RATE := 20.0
## Queue status updates per second (to players in the hideout).
const QUEUE_RATE := 2.0
## Seconds a teammate holds F to revive a downed player (owner, 0.9.2).
const REVIVE_TIME := 5.0
## Players online at once (in the hideout or raids). Keeps a flood of fake players from swamping the server.
const MAX_ONLINE := 40
## A player's health (Health.max_health) and what a revive stands them up with (PlayerBase.revive_health); kept here
## because this autoload can't load the player scripts (the smoke test checks they match).
const MAX_HEALTH := 100
const REVIVE_HEALTH := 30
## How long a player may stay up on the server's count of 0 health before it calls them dead (their game's
## "I'm down" takes a moment to arrive; a heal they finished may still be on its way).
const GOD_GRACE := 1.5

var mode := Mode.OFFLINE

# Client: what the server last told us.
var party_code := ""
## Names of the people in our party, leader first.
var party_names: PackedStringArray = []
var is_leader := true
var queued := false
## Players waiting in the queue, and seconds until their raid starts (-1 = waiting for more players).
var queue_waiting := 0
var queue_countdown := -1.0
var in_raid := false
## Shared by everyone in the raid so they all get the same open extracts.
var raid_seed := 0
## Seconds left on the raid clock when it started for us (the raid counts down from there).
var raid_time_left := RAID_TIME
## Where we start: [slot, place] (Matchmaker.spawn_slots; squads spawn together). Empty = anywhere.
var raid_spawn: Array = []
## Peer id -> name, for everyone in our raid; and which of them are in our party.
var names := {}
## Their looks in our raid (Operators.to_text) by peer id (0.21.6), and ours as we send it.
var looks := {}
var my_look := ""
var teammates: Array[int] = []
## The other players in our raid: their latest state (RemotePlayer.capture) by peer id, and when it arrived.
var states := {}
var states_msec := 0
## Server clock (seconds) of the last states update, and our clock when it arrived: lets shots say what moment
## of the raid we were looking at when we fired (the server checks hits against that moment).
var _server_time := 0.0
var _server_time_at := 0.0
## In a raid: every living scav/Raider as the server last sent them (RaidWorld.enemy_states), and when.
var enemies: Array = []
var enemies_msec := 0

## The game's own connection (the "Net" autoload). The test makes extra Network nodes; those aren't this.
static var main: Network

# Server only.
var matchmaker := Matchmaker.new()
## peer -> latest state, for players in a raid.
var _player_states := {}
## raid id -> RaidWorld (that raid's map on the server, for checking shots).
var _worlds := {}
## victim peer -> [attacker peer, server time]: who to credit when they die.
var _last_attacker := {}
## victim peer -> hits sent to them, oldest first: [attacker peer (0 = not a player), headshot, where] (0.17.1).
## Their game applies each through their armor and reports what it did, so the attacker's number shows that.
var _hits_out := {}
## Players killed by another player (0.15.28): their body gets their PMC dog tag.
var _player_kills := {}
## peer -> server time of their last shot (to ignore impossible fire rates).
var _last_shot := {}
## peer -> [shots they can still fire right now, server time it was worked out] (0.15.28): shots can arrive
## bunched up over the internet, so the fire-rate check allows a short burst instead of a fixed gap.
var _shot_budget := {}
## Reviver peer -> [downed peer, server time they started holding F].
var _reviving := {}
## A revive only counts after holding this long (a little under REVIVE_TIME for lag; the test shortens it).
var revive_min_hold := REVIVE_TIME - 0.5
## Anti-cheat (0.25.0): rate limits, movement checks, strikes (NetGuard). Players caught over and over are kicked.
var guard := NetGuard.new()
var kick_cheaters := true
## Peers being kicked (their requests are ignored until they're gone) -> true.
var _kicked := {}
## What each player in a raid carries (NetGuard.count_stacks: item id -> how many), from their kit as the raid
## starts plus what they took, minus what they put down, fired and threw (0.25.1).
var _carried := {}
## The server's own count of each player's health (0.25.2): [health, when it reached 0 or -1]. Only other players'
## hits count, through the best armor and helmet they carry, and every heal they finish adds; so it's never below
## their real health. Their game still runs their health; this only catches one that won't go down (god mode).
var _health := {}
## Which extract each player is standing in and since when (0.25.2): [zone name, server time].
var _in_extract := {}
## When each player was last told to go back to where the server has them (put-backs are sent at most ~3 a second).
var _fix_sent := {}
var _send_left := 0.0
var _queue_send_left := 0.0


func _enter_tree() -> void:
	if get_parent() == get_tree().root:
		main = self


func _ready() -> void:
	if main != self:
		return
	var args := OS.get_cmdline_user_args()
	if args.has("--server"):
		var port := DEFAULT_PORT
		if OS.get_environment("PORT").is_valid_int():
			port = OS.get_environment("PORT").to_int()
		for arg in args:
			if arg.begins_with("--port="):
				port = arg.trim_prefix("--port=").to_int()
			elif arg.begins_with("--countdown="):  # shorter queue countdown, for testing
				matchmaker.queue_countdown = arg.trim_prefix("--countdown=").to_float()
		# The server has no screen and no hideout: drop the main scene and just run the matchmaking and raids.
		get_tree().unload_current_scene.call_deferred()
		if start_server(port) != OK:
			get_tree().quit(1)


func is_online() -> bool:
	return mode != Mode.OFFLINE


## Connected to a server (in the hideout or a raid).
func is_client() -> bool:
	return mode == Mode.CLIENT


## In an online raid right now (the raid scene asks this).
func in_online_raid() -> bool:
	return mode == Mode.CLIENT and in_raid


func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "?"))


## Players in our raid, us included.
func player_count() -> int:
	return names.size() if in_raid else 1


# --- Server --------------------------------------------------------------------------

func start_server(port: int) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		_log("could not listen on port %d (error %d)" % [port, err])
		return err
	# Players only ever talk to the server (no relaying between them, no "player joined/left" broadcasts).
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_left)
	mode = Mode.SERVER
	matchmaker.raid_time = RAID_TIME
	guard.log_func = _log
	_log("v%s listening on port %d" % [version(), port])
	return OK


## The server only relays states shaped like RemotePlayer.capture()'s: [position, yaw, pitch, lean, flags]
## (a broken or tampered game can't crash the others). Kept here, not in RemotePlayer: this autoload must not
## depend on the player scripts, or a fresh project import fails (they preload sounds not imported yet).
static func is_valid_state(state: Array) -> bool:
	return (state.size() == 5 and state[0] is Vector3 and state[1] is float and state[2] is float
		and state[3] is float and state[4] is int)


## Why a player can't come online ("" = they can).
func join_problem(client_version: String) -> String:
	if client_version != version():
		return "The server is on v%s and you have v%s. Reload the page to update." % [version(), client_version]
	if matchmaker.players.size() >= MAX_ONLINE:
		return "The server is full right now (%d players). Try again in a few minutes." % MAX_ONLINE
	return ""


@rpc("any_peer", "call_remote", "reliable")
func _hello(client_version: String, player_name: String, look := "") -> void:
	var peer := multiplayer.get_remote_sender_id()
	if mode != Mode.SERVER or _kicked.has(peer) or matchmaker.players.has(peer) or not guard.allow(peer, "lobby", _now()):
		return
	var reason := join_problem(client_version)
	if reason != "":
		_log("peer %d turned away: %s" % [peer, reason])
		_rejected.rpc_id(peer, reason)
		return
	matchmaker.add_player(peer, player_name)
	matchmaker.players[peer]["look"] = Operators.to_text(Operators.from_text(look))   # (only real parts get through)
	_log("%s (peer %d) is online (%d players)" % [matchmaker.players[peer]["name"], peer, matchmaker.players.size()])
	_welcome.rpc_id(peer)
	_flush()


@rpc("any_peer", "call_remote", "reliable")
func _join_party(code: String) -> void:
	_server_call(func(peer: int) -> String: return matchmaker.join_party(peer, code))


@rpc("any_peer", "call_remote", "reliable")
func _leave_party() -> void:
	_server_call(func(peer: int) -> String:
		matchmaker.leave_party(peer)
		return "")


@rpc("any_peer", "call_remote", "reliable")
func _set_queued(on: bool) -> void:
	_server_call(func(peer: int) -> String: return matchmaker.set_queued(peer, on))


@rpc("any_peer", "call_remote", "reliable")
func _start_now() -> void:
	_server_call(func(peer: int) -> String:
		var why := []
		var id := matchmaker.start_now(peer, why)
		if id != 0:
			_send_raid_start(id)
		return "" if why.is_empty() else why[0])


@rpc("any_peer", "call_remote", "reliable")
func _leave_raid() -> void:
	_server_call(func(peer: int) -> String:
		_player_states.erase(peer)
		_carried.erase(peer)
		_in_extract.erase(peer)
		_health.erase(peer)
		guard.reset_moves(peer)
		_reviving.erase(peer)
		matchmaker.leave_raid(peer)
		return "")


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _state(state: Array) -> void:
	var peer := _sender("state")
	if peer == 0 or matchmaker.players[peer]["raid"] == 0:
		return
	if not is_valid_state(state):
		_caught(peer, "bad_data", "state")
		return
	var old_flags: int = _player_states[peer][4] if _player_states.has(peer) else 0
	var was_dead := old_flags & Hitbox.FLAG_DEAD != 0
	var world: RaidWorld = _worlds.get(matchmaker.players[peer]["raid"])
	state = _checked_state(peer, state, old_flags, world)
	_player_states[peer] = state
	if not state[4] & Hitbox.FLAG_DEAD:
		_player_kills.erase(peer)
	if world != null:
		world.record(peer, state, _now())
		world.update_proxy(peer, state)
	# Just died: credit whoever hit them last (within 10 s, or 40 s if they bled out downed: down for up to 30 s).
	if state[4] & Hitbox.FLAG_DEAD and not was_dead and _last_attacker.has(peer):
		var attacker: Array = _last_attacker[peer]
		var window := 40.0 if old_flags & Hitbox.FLAG_DOWNED else 10.0
		var killer := 0
		if _now() - attacker[1] < window:
			_player_kills[peer] = true
			killer = attacker[0]
			if _peer_open(killer):
				_kill_confirmed.rpc_id(killer, "player")
		_last_attacker.erase(peer)
		_tell_kill_feed(matchmaker.players[peer]["raid"], killer, peer)


## Server: a state that passed the anti-cheat checks. Dead and extracted stay that way (until the next raid);
## a move the player couldn't have made isn't taken: they stay where the server has them and their game is told to
## put them back (NetGuard.check_move).
func _checked_state(peer: int, state: Array, old_flags: int, world: RaidWorld) -> Array:
	state = state.duplicate()
	if state[4] & Hitbox.FLAG_EXTRACTED and not old_flags & Hitbox.FLAG_EXTRACTED and not _extract_ok(peer, world):
		state[4] = int(state[4]) & ~Hitbox.FLAG_EXTRACTED
	state[4] = int(state[4]) | (old_flags & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED))
	if not state[4] & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED):
		_check_health(peer, state, old_flags)
	if state[4] & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED):
		var kept: Variant = guard.position_of(peer)
		if kept != null:
			state[0] = kept
		return state
	var problem := guard.check_move(peer, state[0], _now(), world.blocked if world != null else Callable())
	if problem == "":
		_track_extract(peer, state[0], world)
		return state
	var kept_pos: Vector3 = guard.position_of(peer)
	if problem != "fixing":
		_caught(peer, problem, "%.1f m" % kept_pos.distance_to(state[0]))
	state[0] = kept_pos
	if _now() - float(_fix_sent.get(peer, -1.0)) > 0.3 and _peer_open(peer):
		_fix_sent[peer] = _now()
		_put_back.rpc_id(peer, kept_pos)
	return state


## Server: notes which extract a player is standing in (and since when), from their checked position.
func _track_extract(peer: int, pos: Vector3, world: RaidWorld) -> void:
	var zone: Array = world.extract_at(pos) if world != null else []
	if zone.is_empty():
		_in_extract.erase(peer)
	elif not _in_extract.has(peer) or _in_extract[peer][0] != zone[0]:
		_in_extract[peer] = [zone[0], _now(), zone[1]]


## Server: a player says they extracted. True if the server had them standing in an extract for about its
## extract time (a second and a half of slack for lag); else the claim isn't taken (they're still in the raid,
## where the others can see and shoot them) and it's a strike.
func _extract_ok(peer: int, world: RaidWorld) -> bool:
	var kept: Variant = guard.position_of(peer)
	var zone: Array = _in_extract.get(peer, [])
	var ok: bool = (world != null and kept != null and not zone.is_empty() and not world.extract_at(kept).is_empty()
		and _now() - float(zone[1]) >= float(zone[2]) - 1.5)
	if not ok:
		_caught(peer, "extract", "not in an extract long enough")
	return ok


## Server: a player whose game stays up after the server's count of their health hit 0 (GOD_GRACE ago) is dead
## here (sets FLAG_DEAD in `state`: their shots and loot stop counting, everyone sees them dead) and is told so.
## Going down (downed) counts as down: their health is 0 from there until a revive.
func _check_health(peer: int, state: Array, old_flags: int) -> void:
	var hp: Array = _health.get_or_add(peer, [float(MAX_HEALTH), -1.0])
	if state[4] & Hitbox.FLAG_DOWNED:
		if not old_flags & Hitbox.FLAG_DOWNED:
			hp[0] = minf(hp[0], 0.0)
		hp[1] = -1.0
	elif hp[0] > 0.0:
		hp[1] = -1.0
	elif hp[1] < 0.0:
		hp[1] = _now()
	elif _now() - hp[1] > GOD_GRACE:
		_caught(peer, "god", "%.0f health" % hp[0])
		state[4] = int(state[4]) | Hitbox.FLAG_DEAD
		if _peer_open(peer):
			_forced_dead.rpc_id(peer)


## Server: another player's hit on `victim` (before armor) comes off the server's count of their health, through the
## best armor (or on the head, helmet) they carry at full strength.
func _hurt(victim: int, amount: int, head: bool) -> void:
	var best := 0.0
	for id: String in _carried.get(victim, {}):
		if int(_carried[victim][id]) > 0 and ItemDB.kind(id) == ("helmet" if head else "armor"):
			best = maxf(best, float(ItemDB.item(id).get("reduction", 0.0)))
	var hp: Array = _health.get_or_add(victim, [float(MAX_HEALTH), -1.0])
	hp[0] -= roundi(amount * (1.0 - best))


## Server: the player who sent the request being handled, if it's within its rate limit (NetGuard.RATES);
## 0 = drop it (offline, not a known player, being kicked, or over the limit).
func _sender(kind: String) -> int:
	var peer := multiplayer.get_remote_sender_id()
	if mode != Mode.SERVER or not matchmaker.players.has(peer) or _kicked.has(peer):
		return 0
	if not guard.allow(peer, kind, _now()):
		_caught(peer, "flood", kind)
		return 0
	return peer


## Server: `peer` was caught cheating (a NetGuard.STRIKES kind): logged, and kicked once it adds up.
func _caught(peer: int, kind: String, detail: String) -> void:
	if guard.strike(peer, kind, detail, _now()) and kick_cheaters:
		kick(peer, "You were removed from the server for cheating.")


## Server: tells a player why, then disconnects them (a moment later, so the message gets there first).
func kick(peer: int, reason: String) -> void:
	if _kicked.has(peer):
		return
	_kicked[peer] = true
	var who: String = matchmaker.players[peer]["name"] if matchmaker.players.has(peer) else "?"
	_log("KICKED %s (peer %d): %s" % [who, peer, reason])
	if _peer_open(peer):
		_rejected.rpc_id(peer, reason)
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		var ws := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
		if ws != null and matchmaker.players.has(peer):
			ws.disconnect_peer(peer))


## A player fired: the server decides what it hit (the map blocks shots; players are checked where they were on
## the shooter's screen at `view_time`). Damage comes from the weapon's stats, never from the shooter.
## `suppressed`: a suppressor on the gun, so AI hear it half as far (0.15.1). `dirs`: one per bullet, or one per
## pellet for a shotgun (0.15.4; at most its "pellets"); pellets that hit the same target add up into one hit.
@rpc("any_peer", "call_remote", "reliable")
func _shot(from: Vector3, dirs: PackedVector3Array, weapon: String, view_time: float, suppressed: bool) -> void:
	var peer := _sender("shot")
	if peer == 0 or not _player_states.has(peer):
		return
	var world: RaidWorld = _worlds.get(matchmaker.players[peer]["raid"])
	var me: Array = _player_states[peer]
	var stats := ItemDB.item(weapon)
	if (world == null or me[4] & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED) or stats.get("kind") != "weapon"
			or from.distance_to(me[0] + Vector3(0, 1.4, 0)) > 2.5 or dirs.is_empty() or dirs.size() > int(stats.get("pellets", 1))
			or not _spend_shot(peer, float(stats.get("rpm", 600)))):
		return
	# Only a gun they carry, and only with rounds they have (0.25.1).
	var carried: Dictionary = _carried.get(peer, {})
	if int(carried.get(weapon, 0)) < 1:
		_caught(peer, "item", "fired a %s they don't carry" % weapon)
		return
	if not NetGuard.use_item(carried, String(stats.get("ammo", ""))):
		_caught(peer, "item", "fired a %s with no rounds" % weapon)
		return
	_last_shot[peer] = _now()
	var targets := {}   # target key -> [hit, damage, headshot]
	var noise_end := from
	for dir in dirs:
		if dir.length_squared() < 0.5:
			continue
		var hit := world.trace_shot(peer, from, dir, 150.0, view_time, _now())
		noise_end = hit["end"]
		if not (hit.has("peer") or hit.has("enemy")):
			continue
		var key: Variant = hit["peer"] if hit.has("peer") else hit["enemy"].get_instance_id()
		var amount := float(stats["damage"]) * ItemDB.falloff_mult(stats.get("falloff", []), from.distance_to(hit["end"]))
		amount *= float(stats.get("head", 2.0)) if hit["headshot"] else 1.0
		if not targets.has(key):
			targets[key] = [hit, 0.0]
		targets[key][1] += amount
		targets[key][0]["headshot"] = targets[key][0]["headshot"] or hit["headshot"]
	var noise := float(stats.get("noise", 25.0)) * (float(ItemDB.item("suppressor")["mult"]["noise"]) if suppressed else 1.0)
	world.shot_noise(from, noise_end, noise, me[0])
	# Everyone else in the raid hears it (0.15.28, owner: other players' shots were silent).
	for other in _raid_peers(matchmaker.players[peer]["raid"]):
		if other != peer and _peer_open(other):
			_player_fired.rpc_id(other, peer, from, noise_end, weapon, suppressed)
	for key: Variant in targets:
		_damage(peer, targets[key][0], roundi(targets[key][1]), me[0])


## Tells everyone in raid `raid_id` that `victim` died, and who killed them (0 = nobody got the credit).
func _tell_kill_feed(raid_id: int, killer: int, victim: int) -> void:
	var killer_name: String = matchmaker.players[killer]["name"] if matchmaker.players.has(killer) else ""
	var victim_name: String = matchmaker.players[victim]["name"] if matchmaker.players.has(victim) else "PMC"
	for peer in _raid_peers(raid_id):
		_kill_feed_line.rpc_id(peer, killer_name, victim_name, peer == killer, peer == victim)


## True if another player killed `peer` (the body can be sent before or after the state that says they died).
func _killed_by_player(peer: int) -> bool:
	if _player_kills.has(peer):
		_player_kills.erase(peer)
		return true
	if _last_attacker.has(peer):
		var attacker: Array = _last_attacker[peer]
		return _now() - attacker[1] < 40.0
	return false


## Fire-rate check: a gun's rate (a bit over, for timing) refills up to a few shots of slack, one used per shot.
func _spend_shot(peer: int, rpm: float) -> bool:
	var budget: Array = _shot_budget.get(peer, [4.0, _now()])
	var left: float = minf(budget[0] + (_now() - budget[1]) * rpm / 60.0 * 1.25, 4.0)
	if left < 1.0:
		_shot_budget[peer] = [left, _now()]
		return false
	_shot_budget[peer] = [left - 1.0, _now()]
	return true


## Melee: the server checks what the knife reached (the same small fan of rays as on the player's screen).
## 45 damage; from behind it always kills (armor or not).
@rpc("any_peer", "call_remote", "reliable")
func _knife(from: Vector3, dir: Vector3) -> void:
	var peer := _sender("knife")
	if peer == 0 or not _player_states.has(peer):
		return
	var world: RaidWorld = _worlds.get(matchmaker.players[peer]["raid"])
	var me: Array = _player_states[peer]
	if (world == null or me[4] & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED)
			or from.distance_to(me[0] + Vector3(0, 1.4, 0)) > 2.5 or _now() - _last_shot.get(peer, -1.0) < 0.3):
		return
	_last_shot[peer] = _now()
	world.shot_noise(from, from, 4.0, me[0], false)
	for angle in [0.0, 0.25, -0.25]:
		var hit := world.trace_shot(peer, from, dir.normalized().rotated(Vector3.UP, angle), 2.2, client_view_time_of(peer), _now())
		if not (hit.has("peer") or hit.has("enemy")):
			continue
		var facing := Vector3.ZERO
		var victim_pos := Vector3.ZERO
		if hit.has("peer"):
			var state: Array = _player_states.get(hit["peer"], [])
			if not state.is_empty():
				facing = Vector3(-sin(state[1]), 0, -cos(state[1]))
				victim_pos = state[0]
		else:
			facing = -(hit["enemy"] as Node3D).global_basis.z
			victim_pos = (hit["enemy"] as Node3D).global_position
		var to_attacker: Vector3 = me[0] - victim_pos
		to_attacker.y = 0.0
		facing.y = 0.0
		var backstab := facing.normalized().dot(to_attacker.normalized()) < -0.3
		var amount := 45
		if backstab:
			# Enough to get through any armor (the victim's game applies theirs; a scav's is its damage multiplier).
			amount = 1000 if hit.has("peer") else ceili(hit["enemy"].health.current / maxf(minf(hit["enemy"].health.damage_multiplier, hit["enemy"].health.head_multiplier), 0.01))
		hit["headshot"] = backstab
		_damage(peer, hit, amount, me[0])
		return


@rpc("any_peer", "call_remote", "reliable")
func _open_container(id: String) -> void:
	var peer := _sender("loot")
	var world := _world_of(peer)
	if world == null or not _up(peer):
		return
	var data: Variant = world.open_container(peer, id)
	if data == null:
		_container_busy.rpc_id(peer, id)
	else:
		_container_contents.rpc_id(peer, id, data)


@rpc("any_peer", "call_remote", "reliable")
func _container_update(id: String, data: Array) -> void:
	var peer := _sender("loot")
	var world := _world_of(peer)
	var box := world.container(id) if world != null and _up(peer) else null
	if box == null or world.locks.get(id) != peer:
		return
	# What they took is theirs now; what they put in has to be something they carry (0.25.1).
	var old_data := box.net_data()
	var before := NetGuard.count_container(old_data)
	world.update_container(peer, id, data)
	var after := NetGuard.count_container(box.net_data()) if is_instance_valid(box) and not box.is_queued_for_deletion() else {}
	var made_up := NetGuard.move_items(_carried.get_or_add(peer, {}), before, after)
	if made_up != "":
		box.load_net_data(old_data)
		_container_contents.rpc_id(peer, id, old_data)
		_caught(peer, "item", "put %s they don't carry in %s" % [made_up, id])


@rpc("any_peer", "call_remote", "reliable")
func _close_container() -> void:
	var peer := _sender("loot")
	var world := _world_of(peer)
	if world != null:
		world.close_containers(peer)


## A player unlocked a key door (their game checked and used up the key): open it here and for everyone else.
@rpc("any_peer", "call_remote", "reliable")
func _open_door(id: String) -> void:
	var peer := _sender("world")
	var world := _world_of(peer)
	if world == null:
		return
	var key := world.door_key(id)
	if key != "" and int(_carried.get(peer, {}).get(key, 0)) < 1:
		_caught(peer, "item", "opened %s without its key" % id)
		return
	world.open_door(id)


## A player broke a window pane (0.18.8): break it here, and for everyone else in the raid.
@rpc("any_peer", "call_remote", "reliable")
func _break_window(pane: int) -> void:
	var world := _world_of(_sender("world"))
	if world != null:
		world.break_window(pane)


## A player opened or shut a door (0.17): swing it here, and for everyone else in the raid.
@rpc("any_peer", "call_remote", "reliable")
func _use_door(id: String, state: int) -> void:
	var world := _world_of(_sender("world"))
	if world != null:
		world.set_door(id, state)


## A player threw a grenade: the server's copy flies and does the damage; everyone else in the raid sees it.
@rpc("any_peer", "call_remote", "reliable")
func _grenade(from: Vector3, vel: Vector3) -> void:
	var peer := _sender("grenade")
	var world := _world_of(peer)
	if world == null or not _player_states.has(peer) or vel.length() > 30.0:
		return
	var me: Array = _player_states[peer]
	if (me[0] as Vector3).distance_to(from) > 4.0:
		return   # (not from where they are)
	if not NetGuard.use_item(_carried.get(peer, {}), "grenade"):
		_caught(peer, "item", "threw a grenade they don't have")
		return
	world.throw_grenade(from, vel)
	for other in _raid_peers(matchmaker.players[peer]["raid"]):
		if other != peer:
			_grenade_seen.rpc_id(other, from, vel)


## A player dropped items, or died (their body holds what they carried): a bag where they are.
@rpc("any_peer", "call_remote", "reliable")
func _drop_items(data: Array, is_body: bool) -> void:
	var peer := _sender("drop")
	var world := _world_of(peer)
	if world == null or not _player_states.has(peer) or data.size() > 200:
		return
	var me: Array = _player_states[peer]
	# Only what they carry (0.25.1): anything else is left out.
	var taken := NetGuard.take_entries(_carried.get_or_add(peer, {}), data)
	data = taken[0]
	if taken[1] > 0:
		_caught(peer, "item", "dropped %d things they don't carry" % taken[1])
	var title: String = ("%s's Body" % matchmaker.players[peer]["name"]) if is_body else "Dropped Items"
	if is_body and _killed_by_player(peer):
		# Killed by another player (0.15.28, owner): "Name's Dog Tag" on the body, in its own slot.
		var tag := ItemStack.new("player_tag")
		tag.label = String(matchmaker.players[peer]["name"]).left(ItemStack.LABEL_MAX)
		tag.found = true
		data.append(GridInventory.stack_data(tag))
	var forward := Vector3(-sin(me[1]), 0, -cos(me[1]))
	world.drop_bag(me[0] + (Vector3.ZERO if is_body else forward * 0.8), title, data, is_body)


## A player's kit as their raid starts (every stack they carry, GridInventory.stack_data): what the server counts as
## theirs (0.25.1). Once per raid. Still taken on trust: the stash lives in their browser until the Stash update.
@rpc("any_peer", "call_remote", "reliable")
func _kit(data: Array) -> void:
	var peer := _sender("kit")
	if peer == 0 or matchmaker.players[peer]["raid"] == 0:
		return
	if _carried.has(peer) or data.size() > 300:
		_caught(peer, "bad_data", "kit")
		return
	_carried[peer] = NetGuard.count_stacks(data, {})


## A player finished using a heal item (0.25.2): it comes off what they carry and its health goes on the server's
## count (a heal they don't carry is refused).
@rpc("any_peer", "call_remote", "reliable")
func _healed(item: String) -> void:
	var peer := _sender("use")
	if peer == 0 or not _player_states.has(peer):
		return
	if not ItemDB.ITEMS.has(item) or ItemDB.kind(item) != "heal" or not NetGuard.use_item(_carried.get(peer, {}), item):
		_caught(peer, "item", "healed with %s they don't carry" % item)
		return
	var hp: Array = _health.get_or_add(peer, [float(MAX_HEALTH), -1.0])
	hp[0] = minf(hp[0] + float(ItemDB.item(item)["heal"]), float(MAX_HEALTH))


## A player started (on) or stopped holding F on a downed teammate: tell the downed one (their screen shows it).
@rpc("any_peer", "call_remote", "reliable")
func _set_reviving(target: int, on: bool) -> void:
	var peer := _sender("revive")
	if peer == 0:
		return
	var started := on and can_revive(peer, target)
	if started:
		_reviving[peer] = [target, _now()]
	elif _reviving.has(peer) and _reviving[peer][0] == target:
		_reviving.erase(peer)
	else:
		return
	if _peer_open(target):
		_revive_state.rpc_id(target, started)


## A player held F long enough on a downed teammate: stand them back up (if it all checks out).
@rpc("any_peer", "call_remote", "reliable")
func _revive(target: int) -> void:
	var peer := _sender("revive")
	if peer == 0 or not _reviving.has(peer):
		return
	var started: Array = _reviving[peer]
	_reviving.erase(peer)
	if started[0] != target or _now() - started[1] < revive_min_hold or not can_revive(peer, target):
		if _peer_open(target):
			_revive_state.rpc_id(target, false)
		return
	_log("%s revived %s" % [matchmaker.players[peer]["name"], matchmaker.players[target]["name"]])
	_health[target] = [float(REVIVE_HEALTH), -1.0]
	if _peer_open(target):
		_revived.rpc_id(target)


## `peer` may revive `target`: same raid and squad, `peer` up and in the raid, `target` downed, and close.
func can_revive(peer: int, target: int) -> bool:
	if peer == target or not matchmaker.players.has(peer) or not matchmaker.players.has(target):
		return false
	var raid_id: int = matchmaker.players[peer]["raid"]
	if raid_id == 0 or matchmaker.players[target]["raid"] != raid_id or not matchmaker.raids.has(raid_id):
		return false
	var teams: Dictionary = matchmaker.raids[raid_id]["teams"]
	if teams.get(peer) != teams.get(target) or not _player_states.has(peer) or not _player_states.has(target):
		return false
	var me: Array = _player_states[peer]
	var them: Array = _player_states[target]
	return (me[4] & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED | Hitbox.FLAG_DOWNED) == 0
		and them[4] & Hitbox.FLAG_DOWNED != 0 and them[4] & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED) == 0
		and (me[0] as Vector3).distance_to(them[0]) < 3.5)


## True if the server has `peer` in the raid and neither dead nor extracted.
func _up(peer: int) -> bool:
	return _player_states.has(peer) and not _player_states[peer][4] & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED)


## The raid world a player is in (null if they aren't in a raid).
func _world_of(peer: int) -> RaidWorld:
	if mode != Mode.SERVER or not matchmaker.players.has(peer):
		return null
	return _worlds.get(matchmaker.players[peer]["raid"])


## For knife hits: the knife is right in front, so players are checked where they are now.
func client_view_time_of(_peer: int) -> float:
	return _now()


## Applies a hit the server decided on: to a player (their game applies it, through their armor) or a scav.
func _damage(attacker: int, hit: Dictionary, amount: int, attacker_pos: Vector3) -> void:
	var killed := false
	# What the attacker's damage number shows: a scav's real damage taken. A player's game applies the hit through
	# their armor and reports what it did (0.17.1, owner: numbers after armor), so for them the number comes later.
	var shown := 0
	if hit.has("peer"):
		var victim: int = hit["peer"]
		_last_attacker[victim] = [attacker, _now()]
		_hurt(victim, amount, hit["headshot"])
		if _peer_open(victim):
			_send_hit(victim, amount, attacker_pos, hit["headshot"], attacker, hit.get("end", attacker_pos))
	else:
		var health: Node = hit["enemy"].health
		shown = health.take_damage(amount, attacker_pos, false, hit["headshot"])
		killed = health.is_dead
	if _peer_open(attacker):
		_hit_confirmed.rpc_id(attacker, hit["headshot"], shown, hit.get("end", attacker_pos))
		if killed:
			# (what it was, by its scene's name: scav, sniper, raider, boss; for quests, 0.16.13)
			_kill_confirmed.rpc_id(attacker, String(hit["enemy"].scene_file_path).get_file().get_basename())


## Runs a request from a player who is online; a non-empty result is sent back to them as a message.
func _server_call(action: Callable) -> void:
	var peer := _sender("lobby")
	if peer == 0:
		return
	var problem: String = action.call(peer)
	if problem != "":
		_notice.rpc_id(peer, problem)
	_flush()


func _on_peer_left(peer: int) -> void:
	if not matchmaker.players.has(peer):
		return
	_log("%s (peer %d) went offline" % [matchmaker.players[peer]["name"], peer])
	_player_states.erase(peer)
	_hits_out.erase(peer)
	_reviving.erase(peer)
	_kicked.erase(peer)
	_fix_sent.erase(peer)
	_carried.erase(peer)
	_in_extract.erase(peer)
	_health.erase(peer)
	guard.forget(peer)
	matchmaker.remove_player(peer)
	_flush()


## Sends a fresh party update to everyone whose party changed.
func _flush() -> void:
	for code in matchmaker.changed_parties:
		if not matchmaker.parties.has(code):
			continue
		var party: Dictionary = matchmaker.parties[code]
		var member_names := PackedStringArray()
		for member in party["members"]:
			member_names.append(matchmaker.players[member]["name"])
		for member in party["members"]:
			if _peer_open(member):
				_party.rpc_id(member, code, member_names, member == party["members"][0], party["queued"])
	matchmaker.changed_parties.clear()


## Players in a raid who can be sent to right now.
func _raid_peers(id: int) -> Array:
	if not matchmaker.raids.has(id):
		return []
	return matchmaker.raids[id]["players"].filter(_peer_open)


## False for a player who is disconnecting (sending to them would only log errors until they're gone).
func _peer_open(peer: int) -> bool:
	var ws := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if ws == null:
		return true
	var socket := ws.get_peer(peer)
	return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _send_raid_start(id: int) -> void:
	var raid: Dictionary = matchmaker.raids[id]
	var world := RaidWorld.new()
	world.name = "Raid%d" % id
	add_child(world)
	_worlds[id] = world
	world.player_hit.connect(func(peer: int, amount: int, from: Vector3, head: bool, burst: int) -> void:
		if _peer_open(peer):
			_send_hit(peer, amount, from, head, 0, Vector3.ZERO, burst))
	world.player_bashed.connect(func(peer: int, amount: int, from: Vector3, shove: float, block: float) -> void:
		if _peer_open(peer):
			_bashed.rpc_id(peer, amount, from, shove, block))
	world.enemy_event.connect(func(enemy: int, kind: String, pos: Vector3) -> void:
		for peer in _raid_peers(id):
			_enemy_event.rpc_id(peer, enemy, kind, pos))
	world.bag_spawned.connect(func(bag: String, pos: Vector3, yaw: float, title: String, search: float) -> void:
		for peer in _raid_peers(id):
			_bag.rpc_id(peer, bag, pos, yaw, title, search))
	world.bag_removed.connect(func(bag: String) -> void:
		for peer in _raid_peers(id):
			_bag_gone.rpc_id(peer, bag))
	world.door_opened.connect(func(door: String) -> void:
		for peer in _raid_peers(id):
			_door_open.rpc_id(peer, door))
	world.window_broken.connect(func(pane: int) -> void:
		for peer in _raid_peers(id):
			_window_broke.rpc_id(peer, pane))
	world.door_changed.connect(func(door: String, state: int) -> void:
		for peer in _raid_peers(id):
			_door_state.rpc_id(peer, door, state))
	world.lid_moved.connect(func(box: String, open: bool) -> void:
		for peer in _raid_peers(id):
			_lid_moved.rpc_id(peer, box, open))
	var raid_names := {}
	var raid_looks := {}
	for peer in raid["players"]:
		raid_names[peer] = matchmaker.players[peer]["name"]
		raid_looks[peer] = matchmaker.players[peer].get("look", "")
		_hits_out.erase(peer)
		_carried.erase(peer)
		_in_extract.erase(peer)
		_health.erase(peer)
		guard.reset_moves(peer)
	_log("raid %d started: %s" % [id, ", ".join(raid_names.values())])
	for peer in raid["players"]:
		var team: Array[int] = []
		for other in raid["players"]:
			if other != peer and raid["teams"][other] == raid["teams"][peer]:
				team.append(other)
		_raid_start.rpc_id(peer, raid["seed"], matchmaker.raid_time_left(id), raid_names, team, raid["spawns"].get(peer, []), raid_looks)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	if mode != Mode.SERVER:
		return
	for id in matchmaker.tick(delta):
		_send_raid_start(id)
	_flush()
	# Raids that ended: drop their worlds; players who left a raid: drop their history.
	for id in _worlds.keys():
		if not matchmaker.raids.has(id):
			_worlds[id].queue_free()
			_worlds.erase(id)
		else:
			for peer in _worlds[id].history.keys():
				if not matchmaker.raids[id]["players"].has(peer):
					_worlds[id].forget(peer)
	_queue_send_left -= delta
	if _queue_send_left <= 0.0:
		_queue_send_left = 1.0 / QUEUE_RATE
		var waiting := matchmaker.queued_count()
		for peer in matchmaker.players:
			if matchmaker.players[peer]["raid"] == 0 and _peer_open(peer):
				_queue_status.rpc_id(peer, waiting, matchmaker.countdown_left)
	_send_left -= delta
	if _send_left > 0.0:
		return
	_send_left = 1.0 / SEND_RATE
	for id in matchmaker.raids:
		# Players who haven't sent a state yet (still loading the raid) aren't shown.
		var shown := {}
		for peer in matchmaker.raids[id]["players"]:
			if _player_states.has(peer):
				shown[peer] = _player_states[peer]
		var enemy_list: Array = _worlds[id].enemy_states() if _worlds.has(id) else []
		if _worlds.has(id):
			_worlds[id].record_enemies(_now())
		for peer in matchmaker.raids[id]["players"]:
			if _peer_open(peer):
				_states.rpc_id(peer, shown, _now(), enemy_list)


# --- Client --------------------------------------------------------------------------

## Connects to a server. Emits `connected` or `connect_failed`.
func go_online(address: String, player_name: String) -> void:
	go_offline()
	address = address.strip_edges()
	if not address.contains("://"):
		# Secure by default (the web page is https, so browsers refuse plain ws:// to other machines).
		var local := address.begins_with("localhost") or address.begins_with("127.") or address.begins_with("192.168.")
		address = ("ws://" if local else "wss://") + address
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(address)
	if err != OK:
		connect_failed.emit("Couldn't connect to %s." % address)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected.bind(player_name), CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	multiplayer.server_disconnected.connect(_on_server_disconnected, CONNECT_ONE_SHOT)


## Disconnects (going back to solo play, or cancelling a connection attempt).
func go_offline() -> void:
	if mode == Mode.SERVER:
		return
	for sig: Signal in [multiplayer.connected_to_server, multiplayer.connection_failed, multiplayer.server_disconnected]:
		for c in sig.get_connections():
			if c.callable.get_object() == self:
				sig.disconnect(c.callable)
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	in_raid = false
	queued = false
	party_code = ""
	party_names = []
	states.clear()


func join_party(code: String) -> void:
	if is_client():
		_join_party.rpc_id(1, code)


func leave_party() -> void:
	if is_client():
		_leave_party.rpc_id(1)


func set_queued(on: bool) -> void:
	if is_client():
		_set_queued.rpc_id(1, on)


## Starts a raid with just our party, no queue (testing, or playing online alone).
func start_now() -> void:
	if is_client():
		_start_now.rpc_id(1)


## Back in the hideout after a raid: tell the server (we stay online, in the same party).
func leave_raid() -> void:
	if in_online_raid():
		_leave_raid.rpc_id(1)
	in_raid = false
	states.clear()


## Sends our state (RemotePlayer.capture) to the server (the raid calls this SEND_RATE times a second).
func send_state(state: Array) -> void:
	if in_online_raid():
		_state.rpc_id(1, state)


## Tells the server we fired (it decides what the shot hit).
func send_shot(from: Vector3, dirs: PackedVector3Array, weapon: String, suppressed := false) -> void:
	if in_online_raid():
		_shot.rpc_id(1, from, dirs, weapon, client_view_time(), suppressed)


func open_container(id: String) -> void:
	if in_online_raid():
		_open_container.rpc_id(1, id)


func update_container(id: String, data: Array) -> void:
	if in_online_raid():
		_container_update.rpc_id(1, id, data)


func close_container() -> void:
	if in_online_raid():
		_close_container.rpc_id(1)


## We threw a grenade.
func send_grenade(from: Vector3, vel: Vector3) -> void:
	if in_online_raid():
		_grenade.rpc_id(1, from, vel)


## We unlocked a key door.
func open_door(id: String) -> void:
	if in_online_raid():
		_open_door.rpc_id(1, id)


## We broke a window pane (0.18.8).
func break_window(pane: int) -> void:
	if in_online_raid():
		_break_window.rpc_id(1, pane)


## We opened or shut a door (0.17).
func use_door(id: String, state: int) -> void:
	if in_online_raid():
		_use_door.rpc_id(1, id, state)


## We finished using a heal item (0.25.2).
func report_heal(item: String) -> void:
	if in_online_raid():
		_healed.rpc_id(1, item)


## Everything we carry as the raid starts (0.25.1): the server counts it as ours.
func send_kit(data: Array) -> void:
	if in_online_raid():
		_kit.rpc_id(1, data)


## Items we dropped (`body` = we died: everything we carried).
func drop_items(data: Array, body := false) -> void:
	if in_online_raid():
		_drop_items.rpc_id(1, data, body)


## We started/stopped holding F on a downed teammate (peer id).
func send_reviving(target: int, on: bool) -> void:
	if in_online_raid():
		_set_reviving.rpc_id(1, target, on)


## We held F long enough: the server checks it and stands them back up.
func send_revive(target: int) -> void:
	if in_online_raid():
		_revive.rpc_id(1, target)


## Tells the server we swung the knife (it decides what it hit).
func send_knife(from: Vector3, dir: Vector3) -> void:
	if in_online_raid():
		_knife.rpc_id(1, from, dir)


## The moment of the raid (server clock) we're seeing right now: other players are drawn RemotePlayer's
## INTERP_DELAY behind the latest update.
func client_view_time() -> float:
	return _server_time + (Time.get_ticks_msec() / 1000.0 - _server_time_at) - 0.1


func _on_connected(player_name: String) -> void:
	_hello.rpc_id(1, version(), player_name, my_look)


## Our look changed in the wardrobe (Operators.to_text): the server passes it on at the next raid.
func set_look(text: String) -> void:
	my_look = text
	if is_client():
		_look.rpc_id(1, text)


@rpc("any_peer", "call_remote", "reliable")
func _look(text: String) -> void:
	var peer := _sender("lobby")
	if peer != 0 and text.length() <= 16:
		matchmaker.players[peer]["look"] = Operators.to_text(Operators.from_text(text))


func _on_connection_failed() -> void:
	# Not while the network is being polled (that's where this signal comes from).
	go_offline.call_deferred()
	connect_failed.emit("Couldn't reach the server.")


func _on_server_disconnected() -> void:
	var was_online := mode == Mode.CLIENT
	go_offline.call_deferred()
	if was_online:
		connection_lost.emit()
	else:
		connect_failed.emit("The server closed the connection.")


@rpc("authority", "call_remote", "reliable")
func _welcome() -> void:
	mode = Mode.CLIENT
	in_raid = false
	connected.emit()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	var was_in_raid := in_online_raid()
	go_offline.call_deferred()
	connect_failed.emit(reason)
	if was_in_raid:
		connection_lost.emit()


## The server counted our health at 0 and we didn't go down (0.25.2): we're dead.
@rpc("authority", "call_remote", "reliable")
func _forced_dead() -> void:
	if in_online_raid():
		forced_dead.emit()


## The server didn't take a move of ours (anti-cheat, 0.25.0; a bad lag spike can do it too): back to where it has us.
@rpc("authority", "call_remote", "reliable")
func _put_back(pos: Vector3) -> void:
	if in_online_raid():
		put_back.emit(pos)


@rpc("authority", "call_remote", "reliable")
func _notice(text: String) -> void:
	notice.emit(text)


@rpc("authority", "call_remote", "reliable")
func _party(code: String, member_names: PackedStringArray, leader: bool, is_queued: bool) -> void:
	party_code = code
	party_names = member_names
	is_leader = leader
	queued = is_queued
	party_changed.emit()


@rpc("authority", "call_remote", "unreliable_ordered")
func _queue_status(waiting: int, countdown: float) -> void:
	queue_waiting = waiting
	queue_countdown = countdown
	queue_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _raid_start(seed_value: int, time_left: float, raid_names: Dictionary, team: Array[int], spawn: Array,
		raid_looks := {}) -> void:
	in_raid = true
	looks = raid_looks
	raid_spawn = spawn
	queued = false
	raid_seed = seed_value
	raid_time_left = time_left
	names = raid_names
	teammates = team
	states.clear()
	raid_started.emit()


## Server: sends a hit to a player and remembers who it was from, for their report of what it did.
func _send_hit(victim: int, amount: int, from: Vector3, headshot: bool, attacker: int, pos: Vector3, burst := -1) -> void:
	var queue: Array = _hits_out.get(victim, [])
	queue.append([attacker, headshot, pos])
	if queue.size() > 32:
		queue.pop_front()
	_hits_out[victim] = queue
	_hit.rpc_id(victim, amount, from, headshot, burst)


@rpc("authority", "call_remote", "reliable")
func _hit(amount: int, from: Vector3, headshot: bool, burst: int) -> void:
	if in_online_raid():
		got_hit.emit(amount, from, headshot, burst)


## Client: what the last hit the server sent really did here (after armor; 0 if none). Every hit gets a report,
## in order, so the server can match them up.
func report_damage(dealt: int) -> void:
	if in_online_raid():
		_damage_taken.rpc_id(1, dealt)


## Server: a player says what a hit did to them; the player who shot gets it for their damage number.
@rpc("any_peer", "call_remote", "reliable")
func _damage_taken(dealt: int) -> void:
	var victim := _sender("report")
	var queue: Array = _hits_out.get(victim, [])
	if victim == 0 or queue.is_empty():
		return
	var sent: Array = queue.pop_front()
	var attacker: int = sent[0]
	if attacker != 0 and dealt > 0 and _peer_open(attacker):
		_damage_shown.rpc_id(attacker, clampi(dealt, 0, 999), sent[1], sent[2])


@rpc("authority", "call_remote", "reliable")
func _damage_shown(amount: int, headshot: bool, pos: Vector3) -> void:
	if in_online_raid():
		damage_shown.emit(amount, headshot, pos)


@rpc("authority", "call_remote", "reliable")
func _hit_confirmed(headshot: bool, amount: int, pos: Vector3) -> void:
	if in_online_raid():
		shot_confirmed.emit(headshot, amount, pos)


@rpc("authority", "call_remote", "reliable")
func _kill_confirmed(target: String) -> void:
	if in_online_raid():
		kill_confirmed.emit(target)


@rpc("authority", "call_remote", "reliable")
func _bashed(amount: int, from: Vector3, shove: float, aim_block: float) -> void:
	if in_online_raid():
		bashed.emit(amount, from, shove, aim_block)


@rpc("authority", "call_remote", "reliable")
func _container_contents(id: String, data: Array) -> void:
	if in_online_raid():
		container_opened.emit(id, data)


@rpc("authority", "call_remote", "reliable")
func _container_busy(id: String) -> void:
	if in_online_raid():
		container_busy.emit(id)


@rpc("authority", "call_remote", "reliable")
func _bag(id: String, pos: Vector3, yaw: float, title: String, search: float) -> void:
	if in_online_raid():
		bag_spawned.emit(id, pos, yaw, title, search)


@rpc("authority", "call_remote", "reliable")
func _bag_gone(id: String) -> void:
	if in_online_raid():
		bag_removed.emit(id)


@rpc("authority", "call_remote", "unreliable")
func _player_fired(peer: int, from: Vector3, end: Vector3, weapon: String, suppressed: bool) -> void:
	if in_online_raid():
		player_fired.emit(peer, from, end, weapon, suppressed)


@rpc("authority", "call_remote", "reliable")
func _grenade_seen(from: Vector3, vel: Vector3) -> void:
	if in_online_raid():
		grenade_seen.emit(from, vel)


@rpc("authority", "call_remote", "reliable")
func _door_open(id: String) -> void:
	if in_online_raid():
		door_opened.emit(id)


@rpc("authority", "call_remote", "reliable")
func _kill_feed_line(killer: String, victim: String, mine: bool, ours: bool) -> void:
	if in_online_raid():
		kill_feed.emit(killer, victim, mine, ours)


@rpc("authority", "call_remote", "reliable")
func _window_broke(pane: int) -> void:
	if in_online_raid():
		window_broken.emit(pane)


@rpc("authority", "call_remote", "reliable")
func _door_state(id: String, state: int) -> void:
	if in_online_raid():
		door_state.emit(id, state)


@rpc("authority", "call_remote", "reliable")
func _lid_moved(id: String, open: bool) -> void:
	if in_online_raid():
		lid_moved.emit(id, open)


@rpc("authority", "call_remote", "reliable")
func _revive_state(on: bool) -> void:
	if in_online_raid():
		revive_changed.emit(on)


@rpc("authority", "call_remote", "reliable")
func _revived() -> void:
	if in_online_raid():
		revived.emit()


@rpc("authority", "call_remote", "reliable")
func _enemy_event(id: int, kind: String, pos: Vector3) -> void:
	if in_online_raid():
		enemy_event.emit(id, kind, pos)


@rpc("authority", "call_remote", "unreliable_ordered")
func _states(all: Dictionary, server_time: float, enemy_list: Array) -> void:
	if not in_online_raid():
		return
	enemies = enemy_list
	enemies_msec = Time.get_ticks_msec()
	_server_time = server_time
	_server_time_at = Time.get_ticks_msec() / 1000.0
	states = all.duplicate()
	states.erase(multiplayer.get_unique_id())
	states_msec = Time.get_ticks_msec()


func _log(text: String) -> void:
	print("[server] ", text)
