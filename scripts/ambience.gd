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
## The hideout's own (0.25.38, owner: too loud and the loop could be heard): three quiet beds of different lengths,
## each drifting up and down at random, and little one-off sounds now and then (drips, pipe ticks, a creak...).
const BUNKER_BEDS: Array[AudioStream] = [preload("res://audio/ambience/bunker_air.wav"),
	preload("res://audio/ambience/bunker_vent.wav"), preload("res://audio/ambience/bunker_hum.wav")]
const BUNKER_BED_DB: Array[float] = [-31.0, -35.0, -34.0]
const BUNKER_BITS: Array[AudioStream] = [preload("res://audio/ambience/bunker_drip1.wav"),
	preload("res://audio/ambience/bunker_drip2.wav"), preload("res://audio/ambience/bunker_drip3.wav"),
	preload("res://audio/ambience/bunker_tick1.wav"), preload("res://audio/ambience/bunker_tick2.wav"),
	preload("res://audio/ambience/bunker_creak.wav"), preload("res://audio/ambience/bunker_clank.wav"),
	preload("res://audio/ambience/bunker_breath.wav")]
const BUNKER_BIT_DB: Array[float] = [-31.0, -31.0, -31.0, -27.0, -27.0, -33.0, -29.0, -33.0]
const BUNKER_DUST := preload("res://audio/ambience/bunker_dust.wav")
const BUNKER_DUST_DB := -30.0
const BUS := &"Ambience"
## Loudness (dB) of each at full: quiet, under the game.
const WIND_DB := -22.0
const WOODS_DB := -20.0
const ROOM_DB := -30.0
const CREEK_DB := -26.0   # (0.20.10, owner: water "way too loud")
const WATERFALL_DB := -20.0
const RUMBLE_DB := -16.0
## Trees within WOODS_RADIUS m for the birds at full.
const WOODS_RADIUS := 25.0
const WOODS_FULL := 12
const CHECK_EVERY := 0.25
const FADE := 1.5   # (dB-ish per second of linear fade, see _fade)
## Underground in the hideout (0.25.22, owner: "really quiet"): the room tone a little louder than a raid's indoors,
## and the war overhead dulled by the earth.
## (0.25.38: the room tone there is now BUNKER_BEDS, and the war a little quieter.)
const BUNKER_RUMBLE_DB := -26.0

var listener: Node3D
## True in the hideout: only the room tone and the far-off war (no wind, birds or water down there).
var bunker := false
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
## The hideout's beds, the loudness (linear) and pitch each is drifting toward, and when each picks a new one.
var _beds: Array[AudioStreamPlayer] = []
var _bed_target: Array[float] = []
var _bed_pitch: Array[float] = []
var _bed_left: Array[float] = []
var _bit_left := 0.0
var _last_bit := -1
var _dust_left := -1.0


## Starts the ambience for `who` (the local player) in their raid.
static func start(who: Node3D) -> Ambience:
	var ambience := Ambience.new()
	ambience.name = "Ambience"
	ambience.listener = who
	who.add_child(ambience)
	return ambience


## The hideout's background sound (0.25.22): the bunker's room tone and the war rumbling far overhead now and then.
static func start_bunker(parent: Node) -> Ambience:
	var ambience := Ambience.new()
	ambience.name = "Ambience"
	ambience.bunker = true
	parent.add_child(ambience)
	return ambience


func _ready() -> void:
	Hearing.bus(BUS)
	_rumble_left = _dice.randf_range(15.0, 40.0)
	_wind = _loop(WIND)
	_woods = _loop(WOODS)
	_room = _loop(ROOM)
	_creek = _loop_at(CREEK, 3.0, 22.0)
	_waterfall = _loop_at(WATERFALL, 5.0, 45.0)
	_waterfall.stop()   # (until the map says where it is)
	if bunker:
		_creek.stop()
		_room.stop()
		_bit_left = _dice.randf_range(3.0, 8.0)
		for i in BUNKER_BEDS.size():
			var bed := _loop(BUNKER_BEDS[i])
			bed.pitch_scale = _dice.randf_range(0.95, 1.05)
			_beds.append(bed)
			_bed_target.append(0.0)
			_bed_pitch.append(bed.pitch_scale)
			_bed_left.append(0.0)


## A copy of `stream` that repeats end to start (the files are made to loop without a seam; .import files aren't
## kept in git, so it's set here). Loops always start at the beginning (0.22.8): on the web Godot repeats a loop from
## where it was started, so one started near its end (they used to start at a random point) repeated a few
## milliseconds over and over as a loud buzz.
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
	player.play()
	return player


func _loop_at(stream: AudioStream, unit_size: float, reach: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = looped(stream)
	player.bus = BUS
	player.unit_size = unit_size
	player.max_distance = reach
	player.top_level = true
	add_child(player)
	player.play()
	return player


func _map() -> BoxMap:
	for node in RaidScope.nodes(listener, &"box_maps"):
		return node as BoxMap
	return null


func _process(delta: float) -> void:
	if bunker:
		_bunker(delta)
		if _rumbles(delta, BUNKER_RUMBLE_DB, 0.7):
			_dust_left = _dice.randf_range(0.6, 1.5) if _dice.randf() < 0.6 else -1.0
		return
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
				_waterfall.play()
		var water := map.nearest_water(listener.global_position) if map else Vector3.INF
		if water != Vector3.INF:
			_creek.global_position = water
		_woods_level = clampf(float(map.trees_near(listener.global_position, WOODS_RADIUS)) / WOODS_FULL, 0.0, 1.0) if map else 0.0
	_fade(_wind, db_to_linear(WIND_DB) * (0.25 if indoors else 1.0), delta)
	_fade(_woods, db_to_linear(WOODS_DB) * _woods_level * (0.3 if indoors else 1.0), delta)
	_fade(_room, db_to_linear(ROOM_DB) if indoors else 0.0, delta)
	_creek.volume_db = CREEK_DB - (8.0 if indoors else 0.0)
	_waterfall.volume_db = WATERFALL_DB - (8.0 if indoors else 0.0)
	_rumbles(delta, RUMBLE_DB, 0.8)


## The hideout's sound (0.25.38): each bed drifts slowly toward its own random loudness and pitch, picked anew every
## 6-16 s, so the three never sound the same twice; and every 4-14 s one of the little sounds (never the same one
## twice running), at a random pitch and loudness. Some rumbles shake a little dust down after them.
func _bunker(delta: float) -> void:
	for i in _beds.size():
		_bed_left[i] -= delta
		if _bed_left[i] <= 0.0:
			_bed_left[i] = _dice.randf_range(6.0, 16.0)
			_bed_target[i] = db_to_linear(BUNKER_BED_DB[i] + _dice.randf_range(-5.0, 1.5))
			_bed_pitch[i] = _dice.randf_range(0.94, 1.06)
		_fade(_beds[i], _bed_target[i], delta * 0.15)
		_beds[i].pitch_scale = move_toward(_beds[i].pitch_scale, _bed_pitch[i], delta * 0.006)
	_bit_left -= delta
	if _bit_left <= 0.0:
		_bit_left = _dice.randf_range(4.0, 14.0)
		var pick := _dice.randi() % BUNKER_BITS.size()
		if pick == _last_bit:
			pick = (pick + 1 + _dice.randi() % (BUNKER_BITS.size() - 1)) % BUNKER_BITS.size()
		_last_bit = pick
		_one_shot(BUNKER_BITS[pick], BUNKER_BIT_DB[pick] + _dice.randf_range(-5.0, 1.0), _dice.randf_range(0.85, 1.15))
	if _dust_left > 0.0:
		_dust_left -= delta
		if _dust_left <= 0.0:
			_one_shot(BUNKER_DUST, BUNKER_DUST_DB + _dice.randf_range(-4.0, 1.0), _dice.randf_range(0.9, 1.1))


func _one_shot(stream: AudioStream, db: float, pitch: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS
	player.volume_db = db
	player.pitch_scale = pitch
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Now and then, the war rumbling far off (`db` loud, pitched from `low_pitch` to 1.1: lower sounds farther/deeper).
## True when one started this frame.
func _rumbles(delta: float, db: float, low_pitch: float) -> bool:
	_rumble_left -= delta
	if _rumble_left <= 0.0:
		_rumble_left = _dice.randf_range(25.0, 70.0)
		var rumble := AudioStreamPlayer.new()
		rumble.stream = RUMBLES[_dice.randi() % RUMBLES.size()]
		rumble.bus = BUS
		rumble.volume_db = db + _dice.randf_range(-4.0, 2.0)
		rumble.pitch_scale = _dice.randf_range(low_pitch, 1.1)
		add_child(rumble)
		rumble.finished.connect(rumble.queue_free)
		rumble.play()
		return true
	return false


## Moves `player`'s loudness toward `target` (linear), smoothly.
func _fade(player: AudioStreamPlayer, target: float, delta: float) -> void:
	player.volume_linear = move_toward(player.volume_linear, target, delta * FADE * maxf(target, 0.05))
