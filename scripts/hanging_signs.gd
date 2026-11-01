extends Node3D
## The hideout's hanging bay signs (0.28.8, owner: "these signs arent even attached properly", "they should like move
## if u run into them too like sway abit"): each hangs on two cables from the roof and swings about the line between
## them. Always a little drift; jump into one and it swings, walk under it and it nods, shots and blasts knock it.
## make_hideout.py takes each sign out of the model round its pivot (assets/models/movers/hideout_<k>.glb). Looks only:
## nothing collides, nothing is sent online, and a headless run never draws them.

const STRIDE := 8          # pivot x, y, z, axis x, z (along the sign), length (pivot down to the sign's middle), half w, h
const DAMPING := 0.5       # per second
const MAX_SWING := 0.22    # radians
const GRAVITY := 9.8
const NUDGE := 0.25        # m/s: walking under one
const DRIFT := 0.012       # radians: the air moving it, always

@export var data := PackedFloat32Array()
@export var models := PackedStringArray()

var parts: Array[Node3D] = []
var swing := PackedFloat32Array()     # per sign: radians about its axis
var spin := PackedFloat32Array()      # per sign: how fast that changes
var _pivot := PackedVector3Array()
var _axis := PackedVector3Array()
var _length := PackedFloat32Array()
var _half := PackedVector2Array()
var _nudged := {}


func _ready() -> void:
	if not Reacts.wanted(self):
		set_physics_process(false)
		return
	add_to_group(Reacts.GROUP)
	for i in data.size() / STRIDE:
		var d := data.slice(i * STRIDE, i * STRIDE + STRIDE)
		var pivot := Node3D.new()
		pivot.name = "Sign%d" % i
		pivot.position = Vector3(d[0], d[1], d[2])
		var scene := load(models[i]) as PackedScene if i < models.size() else null
		if scene:
			pivot.add_child(scene.instantiate())
		add_child(pivot)
		parts.append(pivot)
		_pivot.append(pivot.position)
		_axis.append(Vector3(d[3], 0.0, d[4]).normalized())
		_length.append(maxf(d[5], 0.3))
		_half.append(Vector2(d[6], d[7]))
		swing.append(0.0)
		spin.append(0.0)


## The way the sign's bottom moves for a positive swing (flat, out of its face).
func _swing_way(i: int) -> Vector3:
	return _axis[i].cross(Vector3.DOWN).normalized()


## Where sign `i`'s middle is now.
func middle(i: int) -> Vector3:
	return _pivot[i] + Basis(_axis[i], swing[i]) * Vector3(0.0, -_length[i], 0.0)


func knock(i: int, velocity: Vector3) -> void:
	spin[i] += velocity.dot(_swing_way(i)) / _length[i]


func on_shot(from: Vector3, to: Vector3) -> void:
	var dir := (to - from).normalized()
	for i in parts.size():
		var p := middle(i)
		var near := Geometry3D.get_closest_point_to_segment(p, from, to)
		var off := near - p
		if absf(off.y) < _half[i].y and absf(off.dot(_axis[i])) < _half[i].x and absf(off.dot(_swing_way(i))) < 0.2:
			knock(i, dir * 1.2)


func on_blast(at: Vector3, radius: float) -> void:
	var reach := radius * 2.5
	for i in parts.size():
		var d := middle(i) - at
		var dist := d.length()
		if dist < reach:
			knock(i, d.normalized() * 2.0 * (1.0 - dist / reach))


func _physics_process(delta: float) -> void:
	for m: Dictionary in Reacts.movers(self):
		var pos := m.pos as Vector3
		var head := pos.y + float(m.height)
		var v := m.vel as Vector3
		var flat := Vector3(v.x, 0.0, v.z)
		for i in parts.size():
			var off := pos - middle(i)
			var along := absf(off.dot(_axis[i]))
			var across := absf(off.dot(_swing_way(i)))
			if along > _half[i].x + 0.3 or across > 0.7:
				continue
			var bottom := middle(i).y - _half[i].y
			if head > bottom - 0.05 and across < 0.4:
				# A head into it (jumping, mostly): it swings off the way you were going (or up and away).
				if absf(spin[i]) < 0.3:
					var push := flat if flat.length() > 0.5 else _swing_way(i) * signf(-off.dot(_swing_way(i)) + 0.001) * 0.8
					knock(i, push.limit_length(3.0) * 0.35)
			elif head > bottom - 1.2 and flat.length() > 1.0:
				var now := Time.get_ticks_msec()   # walking under it: a little nod, once a pass
				if now - int(_nudged.get(i, -10000)) > 1500:
					_nudged[i] = now
					knock(i, flat.normalized() * NUDGE)
	var t := Time.get_ticks_msec() / 1000.0
	for i in parts.size():
		var w2 := GRAVITY / _length[i]
		spin[i] += (-swing[i] * w2 - spin[i] * DAMPING * 2.0) * delta
		swing[i] = clampf(swing[i] + spin[i] * delta, -MAX_SWING, MAX_SWING)
		var drift := DRIFT * sin(t * 0.8 + float(i) * 1.9) * (0.6 + 0.4 * sin(t * 0.21 + float(i)))
		parts[i].basis = Basis(_axis[i], swing[i] + drift)
