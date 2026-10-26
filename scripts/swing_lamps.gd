extends Node3D
## Hanging lamps that swing (0.22.0, World reacts): a bulb (or a bulb under a tin shade) on a cable, knocked into a
## swing by a head bumping it, a shot going past or a blast, then slowing back to still. Looks only: the light they
## give is baked into the model and stays put, nothing collides with them, and nothing is sent online. Drawn as three
## MultiMeshes (cables, bulbs, shades): three draw calls however many lamps. The generator (make_hideout.py) leaves
## these lamps out of the model and lists them here.

const STRIDE := 5          # top x, y, z (where the cable hangs from), cable length, look (0 bare bulb, 1 shaded)
const BULB := Vector3(0.08, 0.1, 0.08)
const SHADE := Vector3(0.3, 0.07, 0.3)
const DAMPING := 0.55      # per second
const MAX_TILT := 0.7      # radians
const BUMP_REACH := 0.3    # how close (across) a head or a shot has to come to the bulb
const GRAVITY := 9.8
const NUDGE := 0.45        # m/s: walking under one

@export var data := PackedFloat32Array()

var tilt := PackedVector2Array()    # per lamp: lean about x, lean about z (radians)
var spin := PackedVector2Array()    # per lamp: how fast that changes
var _top := PackedVector3Array()
var _length := PackedFloat32Array()
var _shaded := PackedInt32Array()     # per lamp: its shade's number, or -1
var _shade_count := 0
var _awake := {}                    # lamps swinging now
var _nudged := {}                   # lamp -> when someone last walked under it (msec)
var _cables: MultiMesh
var _bulbs: MultiMesh
var _shades: MultiMesh


func _ready() -> void:
	var n := data.size() / STRIDE
	for i in n:
		_top.append(Vector3(data[i * STRIDE], data[i * STRIDE + 1], data[i * STRIDE + 2]))
		_length.append(data[i * STRIDE + 3])
		_shaded.append(_shade_count if data[i * STRIDE + 4] > 0.5 else -1)
		_shade_count += 1 if data[i * STRIDE + 4] > 0.5 else 0
	tilt.resize(n)
	spin.resize(n)
	if not Reacts.wanted(self):
		set_physics_process(false)
		return
	add_to_group(Reacts.GROUP)
	_cables = _multi(Vector3(0.015, 1.0, 0.015), Color(0.13, 0.13, 0.13), n)
	_bulbs = _multi(BULB, Color(0.886, 0.863, 0.796), n)
	_shades = _multi(SHADE, Color(0.2, 0.22, 0.16), _shade_count)
	for i in n:
		_place(i)


func _multi(size: Vector3, colour: Color, count: int) -> MultiMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()   # (lit like the model's lamps: they dim with the light switch)
	material.albedo_color = colour
	material.roughness = 1.0
	mesh.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mm


## Where lamp `i`'s bulb is now.
func bulb_at(i: int) -> Vector3:
	return _top[i] + _turn(i) * Vector3(0.0, -_length[i] - 0.06, 0.0)


func _turn(i: int) -> Basis:
	return Basis.from_euler(Vector3(tilt[i].x, 0.0, tilt[i].y))


## Knocks lamp `i` with a push of `velocity` (m/s, sideways) at the bulb.
func knock(i: int, velocity: Vector3) -> void:
	# (leaning about +x swings the bulb towards -z; about +z, towards +x)
	spin[i] += Vector2(-velocity.z, velocity.x) / maxf(_length[i], 0.2)
	_awake[i] = true


func on_shot(from: Vector3, to: Vector3) -> void:
	var dir := (to - from).normalized()
	for i in _top.size():
		var p := bulb_at(i)
		var near := Geometry3D.get_closest_point_to_segment(p, from, to)
		if near.distance_to(p) < BUMP_REACH:
			knock(i, Vector3(dir.x, 0.0, dir.z).normalized() * 1.6)


func on_blast(at: Vector3, radius: float) -> void:
	var reach := radius * 2.5
	for i in _top.size():
		var d := bulb_at(i) - at
		d.y = 0.0
		var dist := d.length()
		if dist < reach:
			knock(i, d.normalized() * 2.2 * (1.0 - dist / reach))


func _physics_process(delta: float) -> void:
	# Heads bumping bulbs: anyone whose head comes up to a bulb (jumping, mostly) knocks it the way they're going.
	for m: Dictionary in Reacts.movers(self):
		var pos := m.pos as Vector3
		var head := pos.y + float(m.height)
		for i in _top.size():
			var p := bulb_at(i)
			if head > p.y - 0.12 and pos.y < p.y and Vector2(p.x - pos.x, p.z - pos.z).length() < BUMP_REACH + 0.2:
				var v := m.vel as Vector3
				var push := Vector3(v.x, 0.0, v.z)
				if push.length() < 0.5:   # (straight up into it: off whichever way)
					var a := randf() * TAU
					push = Vector3(cos(a), 0.0, sin(a)) * 0.8
				if spin[i].length() < 0.4:   # (once per bump, not every frame the head is there)
					knock(i, push.limit_length(3.0) * 0.6)
			elif head > p.y - 1.0 and Vector2(p.x - pos.x, p.z - pos.z).length() < 0.55:
				# Walking right under one (owner: "when u walk through nothing happens"): a little nudge, as if you'd
				# brushed it, once a pass.
				var flat := Vector3((m.vel as Vector3).x, 0.0, (m.vel as Vector3).z)
				var now := Time.get_ticks_msec()
				if flat.length() > 1.0 and now - int(_nudged.get(i, -10000)) > 1500:
					_nudged[i] = now
					knock(i, flat.normalized() * NUDGE)
	for i: int in _awake.keys():
		var w2 := GRAVITY / maxf(_length[i], 0.2)
		spin[i] += (-tilt[i] * w2 - spin[i] * DAMPING * 2.0) * delta
		tilt[i] = (tilt[i] + spin[i] * delta).limit_length(MAX_TILT)
		if tilt[i].length() < 0.003 and spin[i].length() < 0.01:
			tilt[i] = Vector2.ZERO
			spin[i] = Vector2.ZERO
			_awake.erase(i)
		_place(i)


func _place(i: int) -> void:
	if _cables == null:
		return
	var turn := _turn(i)
	var length := _length[i]
	_cables.set_instance_transform(i, Transform3D(turn * Basis.from_scale(Vector3(1.0, length, 1.0)),
			_top[i] + turn * Vector3(0.0, -length / 2.0, 0.0)))
	_bulbs.set_instance_transform(i, Transform3D(turn, _top[i] + turn * Vector3(0.0, -length - 0.06, 0.0)))
	if _shaded[i] >= 0:
		_shades.set_instance_transform(_shaded[i], Transform3D(turn, _top[i] + turn * Vector3(0.0, -length + 0.06, 0.0)))
