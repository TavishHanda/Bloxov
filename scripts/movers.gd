extends Node3D
## Parts of buildings that move (0.28.0, owner: "anything that should have some sort of animation/life we need to give
## it"): the farmhouse's weathervane turns in the wind, clock pendulums swing (and tick when you're close), a porch
## swing sways on its chains, crane hooks and what hangs off them sway a little. make_building.py takes each part out
## of its building's model into its own little model round its pivot ("movers" in <name>_solids.json); the generator
## places them here. Looks only: nothing they draw collides (the building keeps its boxes), nothing is sent online and
## the game server never draws them.

const STRIDE := 8          # pivot x, y, z, yaw (degrees: the building's turn), axis x, y, z (the building's space), kind
const VANE := 0
const PENDULUM := 1
const SWING := 2
const HOOK := 3
const KINDS := {"vane": VANE, "pendulum": PENDULUM, "swing": SWING, "hook": HOOK}
const WIND_YAW := 0.7      # radians: where the vanes point, give or take (the wind's way)
const NEAR := 90.0         # parts farther than this from the camera stop moving (you can't see them move)
const TICK_RANGE := 14.0
const TICKS := [preload("res://audio/world/clock_tick1.wav"), preload("res://audio/world/clock_tick2.wav")]

@export var data := PackedFloat32Array()
@export var models := PackedStringArray()   # per part: its model (res:// path)

var parts: Array[Node3D] = []
var _base: Array[Basis] = []
var _axis: Array[Vector3] = []
var _kind := PackedInt32Array()
var _phase := PackedFloat32Array()
var _tick: Array[AudioStreamPlayer3D] = []
var _beat := PackedInt32Array()
## The movers' own clock (0.29.14). It used to be the wall clock (Time.get_ticks_msec), so opening the menu in a raid
## stopped the drawing but not the time: everything jumped to a new phase when you came back. The smoke test also
## sampled it over a fixed number of frames, which are not real time, so the pendulum check failed at random.
var _t := 0.0


func _ready() -> void:
	if not Reacts.wanted(self):
		set_process(false)
		return
	var n := data.size() / STRIDE
	for i in n:
		var d := data.slice(i * STRIDE, i * STRIDE + STRIDE)
		var pivot := Node3D.new()
		pivot.name = "Mover%d" % i
		var base := Basis(Vector3.UP, deg_to_rad(d[3]))
		pivot.transform = Transform3D(base, Vector3(d[0], d[1], d[2]))
		var scene := load(models[i]) as PackedScene if i < models.size() else null
		if scene:
			pivot.add_child(scene.instantiate())
		add_child(pivot)
		parts.append(pivot)
		_base.append(base)
		_axis.append(Vector3(d[4], d[5], d[6]).normalized())
		_kind.append(int(d[7]))
		_phase.append(fposmod(d[0] * 0.37 + d[2] * 0.61, TAU))
		_beat.append(0)
		var tick: AudioStreamPlayer3D = null
		if int(d[7]) == PENDULUM:
			tick = AudioStreamPlayer3D.new()
			tick.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
			tick.volume_db = -16.0
			tick.unit_size = 2.0
			tick.max_distance = TICK_RANGE
			pivot.add_child(tick)
		_tick.append(tick)


func _process(delta: float) -> void:
	_t += delta
	var t := _t
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else Vector3.ZERO
	for i in parts.size():
		var part := parts[i]
		var far := eye.distance_to(part.global_position)
		if camera and far > NEAR:
			continue
		var ph := _phase[i]
		match _kind[i]:
			VANE:      # mostly into the wind, wandering slowly, twitching when a gust comes
				var gust := maxf(0.0, sin(t * 0.4 + ph)) ** 2
				var a := WIND_YAW + 0.45 * sin(t * 0.11 + ph) + 0.25 * sin(t * 0.37 + ph * 2.0) \
					+ 0.18 * gust * sin(t * 6.3 + ph)
				part.basis = _base[i] * Basis(_axis[i], a)
			PENDULUM:  # a seconds pendulum: one beat a second, a tick at each end of its swing
				part.basis = _base[i] * Basis(_axis[i], 0.12 * sin(PI * (t + ph)))
				var beat := int(floor(t + ph - 0.5))
				if beat != _beat[i]:
					_beat[i] = beat
					if _tick[i] and far < TICK_RANGE:
						_tick[i].stream = TICKS[beat & 1]
						_tick[i].pitch_scale = 1.0 + 0.03 * sin(float(beat) * 1.7)
						_tick[i].play()
			SWING:     # a slow sway, bigger and smaller as the breeze comes and goes
				var a := (0.04 + 0.025 * sin(t * 0.23 + ph)) * sin(TAU * t / 3.4 + ph)
				part.basis = _base[i] * Basis(_axis[i], a)
			HOOK:      # heavy and high up: a slow small circle
				part.basis = _base[i] * Basis(Vector3.RIGHT, 0.012 * sin(t * 0.55 + ph)) \
					* Basis(Vector3.BACK, 0.016 * sin(t * 0.43 + ph * 1.3))
