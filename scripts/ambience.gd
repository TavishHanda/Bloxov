class_name Ambience
extends Node
## The raid's background sound (Sound update 0.20.5), for the local player only: wind outdoors, birds and insects in
## the woods, the creek and the waterfall where they are, the war rumbling far off now and then, and a quiet room
## tone indoors. Everything fades smoothly as you move; it all goes through the Ambience bus.

const WIND := preload("res://audio/ambience/wind.wav")
const WOODS := preload("res://audio/ambience/woods.wav")
const CREEK := preload("res://audio/ambience/creek.wav")
const WATERFALL := preload("res://audio/ambience/waterfall.wav")
const ROOM := preload("res://audio/ambience/room.wav")
const RUMBLES: Array[AudioStream] = [preload("res://audio/ambience/rumble1.wav"), preload("res://audio/ambience/rumble2.wav"),
	preload("res://audio/ambience/rumble3.wav")]
const BUS := &"Ambience"
## Loudness (dB) of each at full: quiet, under the game.
const WIND_DB := -22.0
const WOODS_DB := -20.0
const ROOM_DB := -30.0
const CREEK_DB := -12.0
const WATERFALL_DB := -6.0
const RUMBLE_DB := -16.0
## Trees within WOODS_RADIUS m for the birds at full.
const WOODS_RADIUS := 25.0
const WOODS_FULL := 12
const CHECK_EVERY := 0.25
const FADE := 1.5   # (dB-ish per second of linear fade, see _fade)

var listener: Node3D
var _wind: AudioStreamPlayer
var _woods: AudioStreamPlayer
var _room: AudioStreamPlayer
var _creek: AudioStreamPlayer3D
var _waterfall: AudioStreamPlayer3D
var _check_left := 0.0
var _waterfall_placed := false
var _woods_level := 0.0
var _rumble_left := 0.0
var _dice := RandomNumberGenerator.new()


## Starts the ambience for `who` (the local player) in their raid.
static func start(who: Node3D) -> Ambience:
	var ambience := Ambience.new()
	ambience.name = "Ambience"
	ambience.listener = who
	who.add_child(ambience)
	return ambience


func _ready() -> void:
	Hearing.bus(BUS)
	_rumble_left = _dice.randf_range(15.0, 40.0)
	_wind = _loop(WIND)
	_woods = _loop(WOODS)
	_room = _loop(ROOM)
	_creek = _loop_at(CREEK, 8.0, 40.0)
	_waterfall = _loop_at(WATERFALL, 10.0, 70.0)
	_waterfall.stop()   # (until the map says where it is)


## A copy of `stream` that repeats end to start (the files are made to loop without a seam; .import files aren't
## kept in git, so it's set here).
static func looped(stream: AudioStream) -> AudioStream:
	var wav := stream as AudioStreamWAV
	if wav == null or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return stream
	wav = wav.duplicate() as AudioStreamWAV
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(wav.get_length() * wav.mix_rate)
	return wav


func _loop(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = looped(stream)
	player.bus = BUS
	player.volume_linear = 0.0
	add_child(player)
	player.play(_dice.randf() * stream.get_length())
	return player


func _loop_at(stream: AudioStream, unit_size: float, reach: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = looped(stream)
	player.bus = BUS
	player.unit_size = unit_size
	player.max_distance = reach
	player.top_level = true
	add_child(player)
	player.play(_dice.randf() * stream.get_length())
	return player


func _map() -> BoxMap:
	for node in RaidScope.nodes(listener, &"box_maps"):
		return node as BoxMap
	return null


func _process(delta: float) -> void:
	if listener == null or not listener.is_inside_tree():
		return
	var indoors := Hearing.indoors
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_EVERY
		var map := _map()
		if map and not _waterfall_placed:
			_waterfall_placed = true
			var fall := map.get_parent().get_node_or_null("WaterfallSheet") as Node3D
			if fall:
				_waterfall.global_position = fall.global_position
				_waterfall.play(_dice.randf() * WATERFALL.get_length())
		var water := map.nearest_water(listener.global_position) if map else Vector3.INF
		if water != Vector3.INF:
			_creek.global_position = water
		_woods_level = clampf(float(map.trees_near(listener.global_position, WOODS_RADIUS)) / WOODS_FULL, 0.0, 1.0) if map else 0.0
	_fade(_wind, db_to_linear(WIND_DB) * (0.25 if indoors else 1.0), delta)
	_fade(_woods, db_to_linear(WOODS_DB) * _woods_level * (0.3 if indoors else 1.0), delta)
	_fade(_room, db_to_linear(ROOM_DB) if indoors else 0.0, delta)
	_creek.volume_db = CREEK_DB - (8.0 if indoors else 0.0)
	_waterfall.volume_db = WATERFALL_DB - (8.0 if indoors else 0.0)
	_rumble_left -= delta
	if _rumble_left <= 0.0:
		_rumble_left = _dice.randf_range(25.0, 70.0)
		var rumble := AudioStreamPlayer.new()
		rumble.stream = RUMBLES[_dice.randi() % RUMBLES.size()]
		rumble.bus = BUS
		rumble.volume_db = RUMBLE_DB + _dice.randf_range(-4.0, 2.0)
		rumble.pitch_scale = _dice.randf_range(0.8, 1.1)
		add_child(rumble)
		rumble.finished.connect(rumble.queue_free)
		rumble.play()


## Moves `player`'s loudness toward `target` (linear), smoothly.
func _fade(player: AudioStreamPlayer, target: float, delta: float) -> void:
	player.volume_linear = move_toward(player.volume_linear, target, delta * FADE * maxf(target, 0.05))
