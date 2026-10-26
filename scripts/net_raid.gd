class_name NetRaid
extends Node
## The online side of a raid, on a player's machine (does nothing offline). Sends our state to the server,
## shows the other players (RemotePlayer bodies) and a small "online" line on screen.
## Scavs and Raiders run on the server (RaidWorld); here they're puppets that show what the server's do.

const REMOTE_SCENE := preload("res://scenes/remote_player.tscn")
## Puppet copies of the server's scavs and Raiders (by kind: 0 scav, 1 Raider).
const ENEMY_SCENES := [preload("res://scenes/scav.tscn"), preload("res://scenes/raider.tscn"), preload("res://scenes/sniper.tscn"), preload("res://scenes/boss.tscn")]

@export var player: Player
@export var enemy_spawner: Node

## Peer id -> RemotePlayer.
var remotes := {}
## Server enemy id -> puppet Scav.
var enemy_puppets := {}
var _last_enemies_msec := -1
## Shared loot: the container we asked to open, the one we have open (and its grids, kept in case the bag is
## freed when emptied), and whether its contents changed since we last told the server.
var _asked: LootContainer = null
var _open: LootContainer = null
var _open_id := ""
var _open_grids: Array[GridInventory] = []
var _dirty := false
var _message_left := 0.0
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
	Network.main.damage_shown.connect(func(amount: int, headshot: bool, pos: Vector3) -> void:
		if GameSettings.damage_numbers:
			Effects.damage_number(get_tree().current_scene, pos, amount, headshot))
	Network.main.bashed.connect(func(amount: int, from: Vector3, shove: float, block: float) -> void:
		if not player.controls_locked():
			player.take_bash(amount, from, shove, block))
	Network.main.enemy_event.connect(on_enemy_event)
	Network.main.container_opened.connect(on_container_opened)
	Network.main.container_busy.connect(func(_id: String) -> void: _show_message("Someone else is looting that."))
	Network.main.bag_spawned.connect(on_bag_spawned)
	Network.main.bag_removed.connect(on_bag_removed)
	Network.main.door_opened.connect(on_door_opened)
	Network.main.window_broken.connect(on_window_broken)
	Network.main.door_state.connect(on_door_state)
	Network.main.lid_moved.connect(on_lid_moved)
	Network.main.player_fired.connect(on_player_fired)
	Network.main.grenade_seen.connect(func(from: Vector3, vel: Vector3) -> void:
		Grenade.spawn(get_parent(), from, vel, false))
	player.health.died.connect(_drop_body)
	Network.main.revive_changed.connect(player.set_being_revived)
	Network.main.revived.connect(player.revive)
	# Containers' contents come from the server when opened (the rolls made on this machine don't count).
	for box in RaidScope.nodes(self, &"loot_containers"):
		(box as LootContainer).grid.clear()
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
	_update_open_container()
	_message_left -= delta
	if _message_left > 0.0:
		pass
	elif _lost:
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
			# Their character, as they picked it in the wardrobe (0.21.6).
			var pixel := remote.model as PixelModel
			if pixel != null:
				pixel.pick_outfit(Operators.from_text(String(Network.main.looks.get(peer, ""))))
			remotes[peer] = remote
		remote.push_state(states[peer])


## Someone in the raid unlocked a key door: it's open here too.
func on_door_opened(id: String) -> void:
	var door := get_parent().get_node_or_null("KeyDoors/" + id) as KeyDoor
	if door != null:
		door.open()


## Someone in the raid broke a window pane (0.18.8): it's broken here too.
func on_window_broken(pane: int) -> void:
	var blocks := get_parent().get_node_or_null("Level/Blocks") as BoxMap
	if blocks != null:
		blocks.break_pane(pane)


## A door in the raid swung open or shut (someone else, the AI, or the server agreeing with us).
func on_door_state(id: String, state: int) -> void:
	var door := get_parent().get_node_or_null("Doors/" + id) as Door
	if door != null:
		door.set_state(state)


## Someone opened or shut a dropped backpack: its lid moves here too (ours already moved when we opened it).
func on_lid_moved(id: String, open: bool) -> void:
	var box := find_container(id)
	if box != null:
		box.set_open(open)


# --- Shared loot ---------------------------------------------------------------------

## Asks the server to open a container (it's shared: only one player at a time has it open).
func request_open(box: LootContainer) -> void:
	_asked = box
	Network.main.open_container(String(box.name))


## A container by its id (its node name: "Crate3" under Loot, or a bag's "Bag12").
func find_container(id: String) -> LootContainer:
	var node := get_parent().get_node_or_null("Loot/" + id)
	if node == null:
		node = get_parent().get_node_or_null(id)
	return node as LootContainer


func on_container_opened(id: String, data: Array) -> void:
	var box := find_container(id)
	if box == null:
		Network.main.close_container()
		return
	for grid in _open_grids:
		if grid.changed.is_connected(_mark_dirty):
			grid.changed.disconnect(_mark_dirty)
	box.load_net_data(data)
	_open = box
	_open_id = id
	_open_grids = box.all_grids()
	_dirty = false
	for grid in _open_grids:
		grid.changed.connect(_mark_dirty)
	var hud := get_parent().get_node_or_null("HUD")
	if hud != null and _asked == box:
		hud.loot_ui.open_for(box)
	_asked = null


func _mark_dirty() -> void:
	_dirty = true


## Sends our changes to the open container, and lets it go once the screen closes (or we walk off, or it's gone).
func _update_open_container() -> void:
	if _open_grids.is_empty():
		return
	var hud := get_parent().get_node_or_null("HUD")
	var still_open: bool = hud != null and is_instance_valid(_open) and hud.loot_ui.visible and hud.loot_ui.container == _open
	if _dirty:
		_dirty = false
		Network.main.update_container(_open_id, LootContainer.grids_data(_open_grids))
	if not still_open:
		for grid in _open_grids:
			grid.changed.disconnect(_mark_dirty)
		_open_grids = []
		_open = null
		Network.main.close_container()


func on_bag_spawned(id: String, pos: Vector3, yaw: float, title: String, search: float) -> void:
	if find_container(id) != null:
		return
	var bag := LootContainer.spawn_bag(get_parent(), pos, title, [], search)
	bag.name = id
	bag.rotation.y = yaw


func on_bag_removed(id: String) -> void:
	var bag := find_container(id)
	if bag != null:
		bag.queue_free()


## We died: everything we carried (except the secure pocket) becomes a body others can loot.
func _drop_body() -> void:
	# (our dog tag: the server adds it if another player killed us, 0.15.28)
	var data := []
	for slot in Inventory.SLOTS:
		var stack := player.inventory.equipped(slot)
		if stack != null:
			data.append(GridInventory.stack_data(stack))
	for grid in [player.inventory.pockets, player.inventory.backpack]:
		if grid != null:
			for stack in grid.stacks:
				data.append(GridInventory.stack_data(stack))
	Network.main.drop_items(data, true)


func _show_message(text: String) -> void:
	if _label != null:
		_label.text = text
		_message_left = 2.0


## Adds, moves and removes the scav/Raider puppets to match the server's list ([id, kind, net_capture(), gun]).
func sync_enemies(list: Array) -> void:
	var seen := {}
	for entry in list:
		var id: int = entry[0]
		seen[id] = true
		var puppet: Scav = enemy_puppets.get(id)
		if puppet == null:
			puppet = ENEMY_SCENES[clampi(entry[1], 0, ENEMY_SCENES.size() - 1)].instantiate()
			puppet.puppet = true
			# The gun the server's AI carries (0.15.12): the puppet holds, sounds and shoots like it.
			var gun: int = entry[3] if entry.size() > 3 else -1
			puppet.loadout = AILoadouts.NET_GUNS[gun] if gun >= 0 and gun < AILoadouts.NET_GUNS.size() else ""
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
	if kind.begins_with("bark:"):
		puppet.play_bark(kind.substr(5))
		return
	match kind:
		"fired":
			puppet.net_fired(pos)
		"bash":
			puppet.net_bash_started()
		"died":
			enemy_puppets.erase(id)
			puppet.global_position = pos
			puppet.net_died()


## A hit the server sent (another player's shot, or online an AI's): our armor, or on the head our helmet, applies
## as for any other hit.
## What it did goes back to the server for the shooter's damage number (0.17.1).
## An AI's shot (`burst` >= 0) that left the server just as you got behind something solid here misses (0.21.18,
## playtesters: shot through walls): the server sees you a moment late, so without this you'd be hit round a corner.
func apply_hit(amount: int, from: Vector3, headshot: bool, burst := -1) -> void:
	var dealt := 0
	if burst >= 0 and player.hidden_from(from):
		pass
	elif not player.controls_locked() and not player.spares_hit(amount, headshot, burst):
		dealt = player.health.take_damage(amount, from, false, headshot)
	Network.main.report_damage(dealt)


func _on_shot_confirmed(headshot: bool, amount: int, pos: Vector3) -> void:
	var world := get_tree().current_scene
	if GameSettings.damage_numbers and amount > 0:
		Effects.damage_number(world, pos, amount, headshot)
	Effects.sound(world, Gun.HEADSHOT_SOUND if headshot else Gun.HIT_SOUND, -3.0, 0.03)
	player.gun.hit_confirmed.emit(false, headshot)


func _on_kill_confirmed(target: String) -> void:
	player.kills += 1
	if target != "player":   # (a player kill is in the feed already: the server tells the whole raid)
		player.killed.emit(target)
	Quests.record_kill(target, player.gun.weapon.id if player.gun.weapon != null else "")
	Effects.sound(get_tree().current_scene, Gun.KILL_SOUND, -2.0, 0.0)
	player.gun.hit_confirmed.emit(true, false)


func _on_connection_lost() -> void:
	_lost = true


## Another player fired (0.15.28): their gun's sound where they stand (a suppressor: quieter, carries less far)
## and the tracer.
func on_player_fired(_peer: int, from: Vector3, end: Vector3, weapon: String, suppressed: bool) -> void:
	if not ItemDB.ITEMS.has(weapon) or ItemDB.kind(weapon) != "weapon":
		return
	var stats := ItemDB.item(weapon)
	var world := get_tree().current_scene
	Effects.tracer(world, from, end)
	var unit_size := 3.0 if suppressed else 6.0
	Effects.sound_at(world, GunSounds.shot(weapon), from, float(stats.get("shot_db", -4.0)) - (6.0 if suppressed else 0.0)
		+ Hearing.at_you_db(world, from, end, unit_size), 0.06, float(stats.get("shot_pitch", 1.0)), unit_size)
	Hearing.gunshot(world, from, end, float(stats.get("shot_db", -4.0)) - (12.0 if suppressed else 0.0))
