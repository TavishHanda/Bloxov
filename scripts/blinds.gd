extends Node3D
## Window blinds that swing aside (0.23.4, owner picked "climb through, blinds swing aside"): the motel's slatted
## blinds, which you can climb through. Someone pushing through one swings it up and away from them; it swings back
## and settles after. A shot through it or a blast nearby sets it swaying. Looks only: nothing collides with them,
## nothing is sent online and the game server never draws them. The model draws each head rail; the generator lists
## the rest from make_building.py's BLINDS.

const STRIDE := 7          # head rail's middle x, y, z, yaw (degrees: its +z into the room), width, drop, crooked lift
const PITCH := 0.06        # slat spacing
const SLAT := 0.025        # half a slat's depth
const REACH := 0.6         # a body this close (across, to its middle) pushes the blind
const MAX_SWING := 1.35    # radians
const STIFF := 150.0
const DAMP := 12.0
const COLOUR := Color(0.886, 0.863, 0.796)   # (the model's "bone")

@export var data := PackedFloat32Array()

var swing := PackedFloat32Array()   # per blind: radians about its head rail (+ swings the bottom outwards, -z)
var speed := PackedFloat32Array()
var _rail: Array[Transform3D] = []
var _width := PackedFloat32Array()
var _drop := PackedFloat32Array()
var _meshes: Array[MeshInstance3D] = []
var _awake := {}


func _ready() -> void:
	var n := data.size() / STRIDE
	swing.resize(n)
	speed.resize(n)
	for i in n:
		var d := data.slice(i * STRIDE, i * STRIDE + STRIDE)
		_rail.append(Transform3D(Basis(Vector3.UP, deg_to_rad(d[3])), Vector3(d[0], d[1], d[2])))
		_width.append(d[4])
		_drop.append(d[5])
	if not Reacts.wanted(self):
		set_physics_process(false)
		return
	add_to_group(Reacts.GROUP)
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOUR
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = _sheet(_width[i], _drop[i], data[i * STRIDE + 6])
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 80.0   # (the building's far mesh, from 70 m, has none)
		mi.transform = _rail[i]
		add_child(mi)
		_meshes.append(mi)


## One blind's slats, bottom rail and cord, hanging from its head rail (the origin) down -y, across x.
func _sheet(w: float, drop: float, lift: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		st.set_normal((b - a).cross(d - a).normalized())
		for p: Vector3 in [a, b, c, a, c, d]:
			st.add_vertex(p)
	var y := -PITCH / 2.0
	while y > -drop + 0.02:
		var raise := absf(lift) * (-y) / maxf(0.01, drop)   # (the broken cord's end rides up the further down)
		var ya := y + (raise if lift < 0.0 else 0.0)
		var yb := y + (raise if lift > 0.0 else 0.0)
		if ya > -0.01 or yb > -0.01:
			break
		quad.call(Vector3(-w / 2, ya - SLAT * 0.5, -SLAT), Vector3(w / 2, yb - SLAT * 0.5, -SLAT),
			Vector3(w / 2, yb + SLAT * 0.5, SLAT), Vector3(-w / 2, ya + SLAT * 0.5, SLAT))
		y -= PITCH
	var low := y + PITCH - 0.02
	var ra := low + (absf(lift) if lift < 0.0 else 0.0)
	var rb := low + (absf(lift) if lift > 0.0 else 0.0)
	for h in [-0.015, 0.015]:   # (the bottom rail: its top and bottom faces, and front and back)
		quad.call(Vector3(-w / 2, ra + h, -0.025), Vector3(w / 2, rb + h, -0.025), Vector3(w / 2, rb + h, 0.025),
			Vector3(-w / 2, ra + h, 0.025))
	for z in [-0.025, 0.025]:
		quad.call(Vector3(-w / 2, ra - 0.015, z), Vector3(w / 2, rb - 0.015, z), Vector3(w / 2, rb + 0.015, z),
			Vector3(-w / 2, ra + 0.015, z))
	var cx := w / 2 - 0.08
	quad.call(Vector3(cx - 0.004, 0.0, 0.03), Vector3(cx + 0.004, 0.0, 0.03), Vector3(cx + 0.004, rb, 0.03),
		Vector3(cx - 0.004, rb, 0.03))
	return st.commit()


## Where blind `i` would be pushed to by the bodies about it: how far it swings (signed), 0 with nobody in it.
func _push(i: int) -> float:
	var push := 0.0
	var inv := _rail[i].affine_inverse()
	var drop := _drop[i]
	for m: Dictionary in Reacts.movers(self):
		var at: Vector3 = inv * (m.pos as Vector3)
		if absf(at.z) > REACH or absf(at.x) > _width[i] / 2.0 + 0.35 or at.y > 0.0 or at.y + float(m.height) < -drop:
			continue
		var amount := sqrt(1.0 - absf(at.z) / REACH) * MAX_SWING * (1.0 if at.z >= 0.0 else -1.0)
		if absf(amount) > absf(push):
			push = amount
	return push


func on_shot(from: Vector3, to: Vector3) -> void:
	for i in _rail.size():
		var mid := _rail[i] * Vector3(0.0, -_drop[i] / 2.0, 0.0)
		if Geometry3D.get_closest_point_to_segment(mid, from, to).distance_to(mid) < _width[i] / 2.0:
			var across := (_rail[i].basis.inverse() * (to - from).normalized()).z
			speed[i] += -signf(across) * 2.5   # (a shot going into the room knocks the bottom inwards)
			_awake[i] = true


func on_blast(at: Vector3, radius: float) -> void:
	for i in _rail.size():
		var local := _rail[i].affine_inverse() * at
		var dist := local.length()
		if dist < radius * 2.5:
			speed[i] += signf(local.z) * 4.0 * (1.0 - dist / (radius * 2.5))
			_awake[i] = true


func _physics_process(delta: float) -> void:
	var eye := get_viewport().get_camera_3d()
	for i in _rail.size():
		if eye != null and eye.global_position.distance_squared_to(_rail[i].origin) > 6400.0 and not _awake.has(i):
			continue
		var target := _push(i)
		if target == 0.0 and not _awake.has(i):
			continue
		_awake[i] = true
		speed[i] += (STIFF * (target - swing[i]) - DAMP * speed[i]) * delta
		swing[i] = clampf(swing[i] + speed[i] * delta, -MAX_SWING, MAX_SWING)
		if target == 0.0 and absf(swing[i]) < 0.002 and absf(speed[i]) < 0.01:
			swing[i] = 0.0
			speed[i] = 0.0
			_awake.erase(i)
		_meshes[i].transform = _rail[i] * Transform3D(Basis(Vector3.RIGHT, swing[i]), Vector3.ZERO)
