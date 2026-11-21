class_name HideoutVisits
extends Node
## Hideout visits, part 1 (0.39.0, owner 2026-11-21: "people can join each other's hideouts", PvP only): while you're
## in a PvP party, your party mates in the hideout walk round yours as their character in its skin, with their name
## over their head and their footsteps. Our own place goes to the server HIDEOUT_SEND_RATE times a second; the server
## passes it to our party mates in the hideout and nobody else (Network._hideout_state). Looks only: nothing here is
## saved or counts for anything, and the stations always open your own stash, traders and bench. No chat and no text
## players write (store rules): names come from the server, which filtered them when they came online.
## Part 2 (0.39.0): everyone sees the party LEADER's hideout: their corner's decor, trophy shelf and truck (HostView).
## The leader's game sends that look every LOOK_EVERY seconds; a banner says whose hideout it is.
## Part 3 (0.39.0): at the range a mate holds their gun and you hear and see their shots; their punches swing the bag.

const REMOTE_SCENE := preload("res://scenes/remote_player.tscn")
## A mate we've heard nothing from for this long has gone (into a raid, out of the party, offline).
const GONE_AFTER := 3.0
## How often the leader sends their hideout's look, and how long a visitor keeps showing it without a fresh one.
const LOOK_EVERY := 3.0
const LOOK_KEEP := 10.0

var walker: HideoutWalker
## The hideout world (its decor, trophies and garage show the leader's while visiting). Null in the test.
var world: Node
var banner: Label
## Peer id -> RemotePlayer.
var mates := {}
## Peer id -> when the state we last gave their body arrived (so each state is handed over once).
var _last_at := {}
var _send_left := 0.0
var _look_left := 0.0
## The host snapshot shown now (to rebuild only when it changes).
var _shown_host := {}


func setup(hideout_walker: HideoutWalker, hideout_world: Node = null, hud: CanvasLayer = null) -> void:
	walker = hideout_walker
	world = hideout_world
	if hud != null:
		banner = Label.new()
		banner.name = "VisitBanner"
		banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
		banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner.position = Vector2(-400, 48)
		banner.size = Vector2(800, 30)
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.visible = false
		HudStyle.style_label(banner, 20, HudStyle.BRASS)
		hud.add_child(banner)


## Whether we're somewhere a party mate could see us: online with the PvP stash, in a party of two or more.
func visiting() -> bool:
	var net := Network.main
	return net.is_client() and not net.in_raid and Profile.mode == Profile.ONLINE and net.party_names.size() > 1


## Our walker as a RemotePlayer state ([position, yaw, pitch, lean, flags]); at the range, the shooter holding the gun.
func capture() -> Array:
	var shooter: Player = world.get("shooter") if world != null else null
	if shooter != null and shooter.process_mode != Node.PROCESS_MODE_DISABLED:
		return RemotePlayer.capture(shooter)
	var flags := 0
	if walker.is_prone:
		flags |= Hitbox.FLAG_PRONE
	elif walker.is_crouching:
		flags |= Hitbox.FLAG_CROUCH
	if Vector2(walker.velocity.x, walker.velocity.z).length() > HideoutWalker.WALK_SPEED + 0.3:
		flags |= Hitbox.FLAG_SPRINT
	return [walker.global_position, walker.rotation.y, walker._pitch, 0.0, flags]


func _process(delta: float) -> void:
	if walker == null:
		return
	if visiting():
		_send_left -= delta
		if _send_left <= 0.0:
			_send_left = 1.0 / Network.HIDEOUT_SEND_RATE
			Network.main.send_hideout_state(capture())
	var now := Time.get_ticks_msec() / 1000.0
	sync(Network.main.hideout_mates if visiting() else {}, now)
	for act: Array in Network.main.hideout_acts:
		if visiting() and mates.has(act[0]):
			show_act(String(act[1]), act[2], act[3], String(act[4]))
	Network.main.hideout_acts.clear()
	if visiting() and Network.main.is_leader:
		_look_left -= delta
		if _look_left <= 0.0:
			_look_left = LOOK_EVERY
			Network.main.send_hideout_look(HostView.of_profile())
	else:
		_look_left = 0.0
	var host: Array = Network.main.hideout_host
	if visiting() and not Network.main.is_leader and host.size() == 3 and now - float(host[2]) <= LOOK_KEEP:
		show_host(String(host[0]), HostView.clean(host[1]))
	else:
		show_host("", {})
	if banner != null:
		banner.visible = visiting()
		if HostView.active():
			banner.text = "VISITING %s'S HIDEOUT" % HostView.host_name.to_upper()
		elif not mates.is_empty():
			banner.text = "YOUR HIDEOUT  ·  %s HERE" % ", ".join(mates.values().map(func(r: RemotePlayer) -> String: return r.player_name.to_upper()))
		else:
			banner.text = "YOUR HIDEOUT  ·  YOUR PARTY CAN WALK ROUND IT WITH YOU"


## A party mate's shot at the range (their gun's sound where they stand, and the tracer) or punch on the bag.
func show_act(kind: String, from: Vector3, to: Vector3, weapon: String) -> void:
	var scene := get_parent()
	if kind == "punch":
		var toys: HideoutToys = world.get("toys") if world != null else null
		if toys != null and toys.bag != null:
			toys.bag.punch(from)
		return
	if kind != "shot" or not ItemDB.ITEMS.has(weapon) or ItemDB.kind(weapon) != "weapon":
		return
	var stats := ItemDB.item(weapon)
	Effects.tracer(scene, from, to)
	var camera := get_viewport().get_camera_3d()
	var heard := camera.global_position.distance_to(from) if camera != null else 0.0
	Effects.shot_at(scene, GunSounds.shot_for(weapon, heard, GunSounds.Place.ROOM, Hearing.Block.NONE, false), from,
		float(stats.get("shot_db", -4.0)), float(stats.get("shot_pitch", 1.0)), 6.0, 0.0)


## Shows `who`'s hideout look (`data`, cleaned), or ours ({}), rebuilding the decor, trophies and truck if it changed.
func show_host(who: String, data: Dictionary) -> void:
	if data == _shown_host and who == HostView.host_name:
		return
	_shown_host = data
	HostView.host = data
	HostView.host_name = who if not data.is_empty() else ""
	if world == null:
		return
	for part in ["decor", "trophies", "garage"]:
		var node: Node = world.get(part)
		if node != null:
			node.call("refresh")


func _exit_tree() -> void:
	HostView.host = {}   # (static: nothing of a visit is left over for the next hideout)
	HostView.host_name = ""


## Adds and removes mates' bodies to match `heard` (Network.hideout_mates) at time `now`, and moves them.
func sync(heard: Dictionary, now: float) -> void:
	for peer: int in mates.keys():
		if not heard.has(peer) or now - float(heard[peer][3]) > GONE_AFTER:
			(mates[peer] as Node).queue_free()
			mates.erase(peer)
			_last_at.erase(peer)
	for peer: int in heard:
		var info: Array = heard[peer]
		if now - float(info[3]) > GONE_AFTER:
			continue
		var remote: RemotePlayer = mates.get(peer)
		if remote == null:
			remote = _add(peer, String(info[0]), String(info[1]))
		if _last_at.get(peer, -1.0) != float(info[3]):
			_last_at[peer] = float(info[3])
			remote.push_state(info[2])


func _add(peer: int, who: String, look: String) -> RemotePlayer:
	var remote: RemotePlayer = REMOTE_SCENE.instantiate()
	remote.peer_id = peer
	remote.name = "Mate%d" % peer
	remote.player_name = who
	remote.teammate = true   # (the small green name tag over their head)
	var character := Characters.character_of_look(look, Operators.SLOTS.size())
	PlayableModels.replace(remote, character[0], character[1])
	get_parent().add_child(remote)
	remote.step_mult = Characters.steps_of_look(look, Operators.SLOTS.size())
	mates[peer] = remote
	return remote
