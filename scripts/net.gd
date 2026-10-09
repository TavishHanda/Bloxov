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
signal got_hit(amount: int, from: Vector3, headshot: bool)
signal shot_confirmed(headshot: bool)
signal kill_confirmed

enum Mode { OFFLINE, SERVER, CLIENT }

const DEFAULT_PORT := 9080
## The hosted server (see fly.toml / heroku.yml). A local test server is ws://localhost:9080.
const DEFAULT_ADDRESS := "wss://bloxov-server-0f9c9a343ceb.herokuapp.com"
const RAID_TIME := 600.0
## Player state updates per second, both ways.
const SEND_RATE := 20.0
## Queue status updates per second (to players in the hideout).
const QUEUE_RATE := 2.0
## Players online at once (in the hideout or raids). Keeps a flood of fake players from swamping the server.
const MAX_ONLINE := 40

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
## Peer id -> name, for everyone in our raid; and which of them are in our party.
var names := {}
var teammates: Array[int] = []
## The other players in our raid: their latest state (RemotePlayer.capture) by peer id, and when it arrived.
var states := {}
var states_msec := 0
## Server clock (seconds) of the last states update, and our clock when it arrived: lets shots say what moment
## of the raid we were looking at when we fired (the server checks hits against that moment).
var _server_time := 0.0
var _server_time_at := 0.0

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
## peer -> server time of their last shot (to ignore impossible fire rates).
var _last_shot := {}
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
func _hello(client_version: String, player_name: String) -> void:
	if mode != Mode.SERVER:
		return
	var peer := multiplayer.get_remote_sender_id()
	var reason := join_problem(client_version)
	if reason != "":
		_log("peer %d turned away: %s" % [peer, reason])
		_rejected.rpc_id(peer, reason)
		return
	matchmaker.add_player(peer, player_name)
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
		matchmaker.leave_raid(peer)
		return "")


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _state(state: Array) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not (mode == Mode.SERVER and matchmaker.players.has(peer) and matchmaker.players[peer]["raid"] != 0
			and is_valid_state(state)):
		return
	var was_dead: bool = _player_states.has(peer) and _player_states[peer][4] & Hitbox.FLAG_DEAD
	_player_states[peer] = state
	var world: RaidWorld = _worlds.get(matchmaker.players[peer]["raid"])
	if world != null:
		world.record(peer, state, _now())
	# Just died: credit whoever hit them last (within 10 s).
	if state[4] & Hitbox.FLAG_DEAD and not was_dead and _last_attacker.has(peer):
		var attacker: Array = _last_attacker[peer]
		if _now() - attacker[1] < 10.0 and _peer_open(attacker[0]):
			_kill_confirmed.rpc_id(attacker[0])
		_last_attacker.erase(peer)


## A player fired: the server decides what it hit (the map blocks shots; players are checked where they were on
## the shooter's screen at `view_time`). Damage comes from the weapon's stats, never from the shooter.
@rpc("any_peer", "call_remote", "reliable")
func _shot(from: Vector3, dir: Vector3, weapon: String, view_time: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if mode != Mode.SERVER or not matchmaker.players.has(peer) or not _player_states.has(peer):
		return
	var world: RaidWorld = _worlds.get(matchmaker.players[peer]["raid"])
	var me: Array = _player_states[peer]
	var stats := ItemDB.item(weapon)
	if (world == null or me[4] & (Hitbox.FLAG_DEAD | Hitbox.FLAG_EXTRACTED) or stats.get("kind") != "weapon"
			or from.distance_to(me[0] + Vector3(0, 1.4, 0)) > 2.5 or dir.length_squared() < 0.5
			or _now() - _last_shot.get(peer, -1.0) < 0.05):
		return
	_last_shot[peer] = _now()
	var hit := world.trace_shot(peer, from, dir, 150.0, view_time, _now())
	if hit.is_empty():
		return
	var victim: int = hit["peer"]
	var amount := roundi(float(stats["damage"]) * (float(stats.get("head", 2.0)) if hit["headshot"] else 1.0))
	_last_attacker[victim] = [peer, _now()]
	if _peer_open(victim):
		_hit.rpc_id(victim, amount, me[0], hit["headshot"])
	if _peer_open(peer):
		_hit_confirmed.rpc_id(peer, hit["headshot"])


## Runs a request from a player who is online; a non-empty result is sent back to them as a message.
func _server_call(action: Callable) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if mode != Mode.SERVER or not matchmaker.players.has(peer):
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
	var raid_names := {}
	for peer in raid["players"]:
		raid_names[peer] = matchmaker.players[peer]["name"]
	_log("raid %d started: %s" % [id, ", ".join(raid_names.values())])
	for peer in raid["players"]:
		var team: Array[int] = []
		for other in raid["players"]:
			if other != peer and raid["teams"][other] == raid["teams"][peer]:
				team.append(other)
		_raid_start.rpc_id(peer, raid["seed"], matchmaker.raid_time_left(id), raid_names, team)


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
		for peer in matchmaker.raids[id]["players"]:
			if _peer_open(peer):
				_states.rpc_id(peer, shown, _now())


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
func send_shot(from: Vector3, dir: Vector3, weapon: String) -> void:
	if in_online_raid():
		_shot.rpc_id(1, from, dir, weapon, client_view_time())


## The moment of the raid (server clock) we're seeing right now: other players are drawn RemotePlayer's
## INTERP_DELAY behind the latest update.
func client_view_time() -> float:
	return _server_time + (Time.get_ticks_msec() / 1000.0 - _server_time_at) - 0.1


func _on_connected(player_name: String) -> void:
	_hello.rpc_id(1, version(), player_name)


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
	go_offline.call_deferred()
	connect_failed.emit(reason)


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
func _raid_start(seed_value: int, time_left: float, raid_names: Dictionary, team: Array[int]) -> void:
	in_raid = true
	queued = false
	raid_seed = seed_value
	raid_time_left = time_left
	names = raid_names
	teammates = team
	states.clear()
	raid_started.emit()


@rpc("authority", "call_remote", "reliable")
func _hit(amount: int, from: Vector3, headshot: bool) -> void:
	if in_online_raid():
		got_hit.emit(amount, from, headshot)


@rpc("authority", "call_remote", "reliable")
func _hit_confirmed(headshot: bool) -> void:
	if in_online_raid():
		shot_confirmed.emit(headshot)


@rpc("authority", "call_remote", "reliable")
func _kill_confirmed() -> void:
	if in_online_raid():
		kill_confirmed.emit()


@rpc("authority", "call_remote", "unreliable_ordered")
func _states(all: Dictionary, server_time: float) -> void:
	if not in_online_raid():
		return
	_server_time = server_time
	_server_time_at = Time.get_ticks_msec() / 1000.0
	states = all.duplicate()
	states.erase(multiplayer.get_unique_id())
	states_msec = Time.get_ticks_msec()


func _log(text: String) -> void:
	print("[server] ", text)
