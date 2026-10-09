class_name NetRaid
extends Node
## The online side of a raid, on a player's machine (does nothing offline). Sends our state to the server,
## shows the other players (RemotePlayer bodies) and a small "online" line on screen.
## Scavs and Raiders run on the server (RaidWorld); here they're puppets that show what the server's do.

const REMOTE_SCENE := preload("res://scenes/remote_player.tscn")
## Puppet copies of the server's scavs and Raiders (by kind: 0 scav, 1 Raider).
const ENEMY_SCENES := [preload("res://scenes/scav.tscn"), preload("res://scenes/raider.tscn")]

@export var player: Player
@export var enemy_spawner: Node

## Peer id -> RemotePlayer.
var remotes := {}
## Server enemy id -> puppet Scav.
var enemy_puppets := {}
var _last_enemies_msec := -1
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
	Network.main.got_hit.connect(apply_hit)
	Network.main.shot_confirmed.connect(_on_shot_confirmed)
	Network.main.kill_confirmed.connect(_on_kill_confirmed)
	Network.main.bashed.connect(func(amount: int, from: Vector3, shove: float, block: float) -> void:
		if not player.controls_locked():
			player.take_bash(amount, from, shove, block))
	Network.main.enemy_event.connect(on_enemy_event)
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
	if Network.main.enemies_msec != _last_enemies_msec:
		_last_enemies_msec = Network.main.enemies_msec
		sync_enemies(Network.main.enemies)
	if _lost:
		_label.text = "Disconnected from the server: you're on your own now."
	else:
		var count := Network.main.player_count()
		_label.text = "Online · %d %s in this raid" % [count, "player" if count == 1 else "players"]


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


## Adds, moves and removes the scav/Raider puppets to match the server's list ([id, kind, net_capture()]).
func sync_enemies(list: Array) -> void:
	var seen := {}
	for entry in list:
		var id: int = entry[0]
		seen[id] = true
		var puppet: Scav = enemy_puppets.get(id)
		if puppet == null:
			puppet = ENEMY_SCENES[clampi(entry[1], 0, 1)].instantiate()
			puppet.puppet = true
			puppet.name = "Enemy%d" % id
			get_parent().add_child(puppet)
			# Same outfit on every player's screen.
			puppet.model.pick_outfit_seeded(id)
			enemy_puppets[id] = puppet
		puppet.net_push(entry[2])
	for id in enemy_puppets.keys():
		if not seen.has(id):
			if is_instance_valid(enemy_puppets[id]):
				enemy_puppets[id].queue_free()
			enemy_puppets.erase(id)


## Something a server scav did: show it on its puppet.
func on_enemy_event(id: int, kind: String, pos: Vector3) -> void:
	var puppet: Scav = enemy_puppets.get(id)
	if puppet == null or not is_instance_valid(puppet):
		return
	match kind:
		"fired":
			puppet.net_fired(pos)
		"alerted":
			puppet.net_alerted()
		"bash":
			puppet.net_bash_started()
		"died":
			enemy_puppets.erase(id)
			puppet.global_position = pos
			puppet.net_died()


## Another player's shot hit us (the server checked it): our armor applies as for any other hit.
func apply_hit(amount: int, from: Vector3, _headshot: bool) -> void:
	if not player.controls_locked():
		player.health.take_damage(amount, from)


func _on_shot_confirmed(headshot: bool) -> void:
	var world := get_tree().current_scene
	Effects.sound(world, Gun.HEADSHOT_SOUND if headshot else Gun.HIT_SOUND, -3.0, 0.03)
	player.gun.hit_confirmed.emit(false, headshot)


func _on_kill_confirmed() -> void:
	player.kills += 1
	Effects.sound(get_tree().current_scene, Gun.KILL_SOUND, -2.0, 0.0)
	player.gun.hit_confirmed.emit(true, false)


func _on_connection_lost() -> void:
	_lost = true
