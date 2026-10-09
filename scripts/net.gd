class_name Network
extends Node
## Multiplayer connection (autoload "Net"; other scripts use it as `Network.main`, which also works in the
## headless test, where autoload names aren't known when scripts compile). Offline by default: solo raids never touch the network.
##
## Browsers can't host, so online raids run on a dedicated server: this same project started with
##   godot --headless -- --server [--port=9080]
## (or the PORT environment variable, which hosting services set). Players join from the hideout with the
## server's address and a room code. One raid (room) per server process for now: the first player to join
## picks the code, the room resets when everyone has left.
##
## 0.7.0 (multiplayer step 1): the server checks version, room code and player count, owns the raid clock and
## which extracts are open, and relays every player's position to the others. Everything else (AI, loot, hits)
## still runs on each player's own machine until the later steps.

signal joined
signal join_failed(reason: String)
## The connection to the server dropped mid-raid (the server stopped, or the internet went away).
signal connection_lost

enum Mode { OFFLINE, SERVER, CLIENT }

const DEFAULT_PORT := 9080
## The hosted server (Fly.io, deployed by CI: see fly.toml). A local test server is ws://localhost:9080.
const DEFAULT_ADDRESS := "wss://bloxov-server.fly.dev"
## Owner: duos, up to 6 players per raid.
const MAX_PLAYERS := 6
const RAID_TIME := 600.0
## Position updates per second, both ways.
const SEND_RATE := 20.0

var mode := Mode.OFFLINE
var room_code := ""
## Shared by everyone in the room so they all get the same open extracts.
var raid_seed := 0
## Seconds left on the raid clock when we joined (the client counts down from there).
var raid_time_left := RAID_TIME
## Client: the other players' latest [position, yaw], by peer id (not including us).
var states := {}

## The game's own connection (the "Net" autoload). The test makes extra Network nodes; those aren't this.
static var main: Network

# Server only.
var _welcomed := {}
var _raid_started_msec := 0
var _send_left := 0.0


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
		# The server has no screen and no hideout: drop the main scene and just run the room.
		get_tree().unload_current_scene.call_deferred()
		if start_server(port) != OK:
			get_tree().quit(1)


func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_client() -> bool:
	return mode == Mode.CLIENT


func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "?"))


## Players in the raid, us included (1 offline).
func player_count() -> int:
	return _welcomed.size() if mode == Mode.SERVER else states.size() + 1


# --- Server --------------------------------------------------------------------------

func start_server(port: int) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		_log("could not listen on port %d (error %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_left)
	mode = Mode.SERVER
	_reset_room()
	_log("v%s listening on port %d" % [version(), port])
	return OK


func _reset_room() -> void:
	room_code = ""
	_welcomed.clear()
	raid_seed = randi()


func _server_time_left() -> float:
	return RAID_TIME - (Time.get_ticks_msec() - _raid_started_msec) / 1000.0


@rpc("any_peer", "call_remote", "reliable")
func _hello(client_version: String, code: String) -> void:
	if mode != Mode.SERVER:
		return
	var peer := multiplayer.get_remote_sender_id()
	code = code.strip_edges().to_upper()
	var reason := join_problem(client_version, code)
	if reason != "":
		_log("peer %d turned away: %s" % [peer, reason])
		_rejected.rpc_id(peer, reason)
		return
	if room_code == "":
		room_code = code
		_raid_started_msec = Time.get_ticks_msec()
		_log("room %s opened" % code)
	_welcomed[peer] = [Vector3.ZERO, 0.0]
	_log("peer %d joined room %s (%d players)" % [peer, room_code, _welcomed.size()])
	_welcome.rpc_id(peer, room_code, raid_seed, _server_time_left())


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _state(pos: Vector3, yaw: float) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if mode == Mode.SERVER and _welcomed.has(peer):
		_welcomed[peer] = [pos, yaw]


func _on_peer_left(peer: int) -> void:
	if not _welcomed.erase(peer):
		return
	_log("peer %d left (%d players)" % [peer, _welcomed.size()])
	if _welcomed.is_empty():
		_log("room %s closed" % room_code)
		_reset_room()


func _process(delta: float) -> void:
	if mode != Mode.SERVER or _welcomed.is_empty():
		return
	_send_left -= delta
	if _send_left > 0.0:
		return
	_send_left = 1.0 / SEND_RATE
	for peer in _welcomed:
		_states.rpc_id(peer, _welcomed)


## Why a player can't join right now ("" = they can).
func join_problem(client_version: String, code: String) -> String:
	if client_version != version():
		return "The server is on v%s and you have v%s. Reload the page to update." % [version(), client_version]
	if code == "":
		return "Enter a room code."
	if _welcomed.size() >= MAX_PLAYERS:
		return "The raid is full (%d players)." % MAX_PLAYERS
	if room_code != "" and code != room_code:
		return "This server is running another room. Check the code."
	if room_code != "" and _server_time_left() < 30.0:
		return "This raid is about to end. Try again in a minute."
	return ""


# --- Client --------------------------------------------------------------------------

## Connects to a server and asks to join the room. Emits `joined` or `join_failed`.
func join(address: String, code: String) -> void:
	leave()
	address = address.strip_edges()
	if not address.contains("://"):
		# Secure by default (the web page is https, so browsers refuse plain ws:// to other machines).
		var local := address.begins_with("localhost") or address.begins_with("127.") or address.begins_with("192.168.")
		address = ("ws://" if local else "wss://") + address
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(address)
	if err != OK:
		join_failed.emit("Couldn't connect to %s." % address)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected.bind(code), CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	multiplayer.server_disconnected.connect(_on_server_disconnected, CONNECT_ONE_SHOT)


## Back to offline (after a raid, or to cancel joining).
func leave() -> void:
	if mode == Mode.SERVER:
		return
	for sig: Signal in [multiplayer.connected_to_server, multiplayer.connection_failed, multiplayer.server_disconnected]:
		for c in sig.get_connections():
			if c.callable.get_object() == self:
				sig.disconnect(c.callable)
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if mode == Mode.CLIENT:
		mode = Mode.OFFLINE
	states.clear()


## Sends our position to the server (the raid calls this SEND_RATE times a second).
func send_state(pos: Vector3, yaw: float) -> void:
	if mode == Mode.CLIENT:
		_state.rpc_id(1, pos, yaw)


func _on_connected(code: String) -> void:
	_hello.rpc_id(1, version(), code)


func _on_connection_failed() -> void:
	leave.call_deferred()
	join_failed.emit("Couldn't reach the server.")


func _on_server_disconnected() -> void:
	var was_in_raid := mode == Mode.CLIENT
	# Not while the network is being polled (that's where this signal comes from).
	leave.call_deferred()
	if was_in_raid:
		connection_lost.emit()
	else:
		join_failed.emit("The server closed the connection.")


@rpc("authority", "call_remote", "reliable")
func _welcome(code: String, seed_value: int, time_left: float) -> void:
	mode = Mode.CLIENT
	room_code = code
	raid_seed = seed_value
	raid_time_left = time_left
	states.clear()
	joined.emit()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	leave.call_deferred()
	join_failed.emit(reason)


@rpc("authority", "call_remote", "unreliable_ordered")
func _states(all: Dictionary) -> void:
	if mode != Mode.CLIENT:
		return
	var me := multiplayer.get_unique_id()
	states = all.duplicate()
	states.erase(me)


func _log(text: String) -> void:
	print("[server] ", text)
