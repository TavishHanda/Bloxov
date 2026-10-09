class_name NetRaid
extends Node
## The online side of a raid, on a player's machine (does nothing offline). Sends our state to the server,
## shows the other players (RemotePlayer bodies) and a small "online" line on screen.
## 0.7.0: no AI in online raids yet; scavs and Raiders move to the server in 0.7.3.

const REMOTE_SCENE := preload("res://scenes/remote_player.tscn")

@export var player: Player
@export var enemy_spawner: Node

## Peer id -> RemotePlayer.
var remotes := {}
var _send_left := 0.0
var _last_states_msec := -1
var _label: Label
var _lost := false


func _ready() -> void:
	if not Network.main.in_online_raid():
		return
	if enemy_spawner != null:
		enemy_spawner.queue_free()
	Network.main.connection_lost.connect(_on_connection_lost)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12, 40)
	_label.modulate = Color(1, 1, 1, 0.6)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_label)


func _process(delta: float) -> void:
	if _label == null:
		return
	if Network.main.in_online_raid():
		_send_left -= delta
		if _send_left <= 0.0:
			_send_left = 1.0 / Network.SEND_RATE
			Network.main.send_state(RemotePlayer.capture(player))
	if Network.main.states_msec != _last_states_msec:
		_last_states_msec = Network.main.states_msec
		sync_remotes(Network.main.states)
	if _lost:
		_label.text = "Disconnected from the server: you're on your own now."
	else:
		_label.text = "Online · %d players in this raid" % Network.main.player_count()


## Adds and removes RemotePlayer bodies to match `states` (peer id -> RemotePlayer state) and hands each its
## new state (call once per update from the server).
func sync_remotes(states: Dictionary) -> void:
	for peer in remotes.keys():
		if not states.has(peer):
			remotes[peer].queue_free()
			remotes.erase(peer)
	for peer in states:
		var remote: RemotePlayer = remotes.get(peer)
		if remote == null:
			remote = REMOTE_SCENE.instantiate()
			remote.peer_id = peer
			remote.name = "Remote%d" % peer
			remote.player_name = Network.main.names.get(peer, "")
			remote.teammate = Network.main.teammates.has(peer)
			get_parent().add_child(remote)
			remotes[peer] = remote
		remote.push_state(states[peer])


func _on_connection_lost() -> void:
	_lost = true
