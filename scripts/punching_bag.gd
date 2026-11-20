class_name PunchingBag
extends Node3D
## The gym's punching bag (0.36.39, owner picked the gym): a red leather bag on a chain from the beam that swings when
## it's hit, by you (USE while looking at it), by the crew's boxer, a shot or a blast, then settles. Looks only: its
## light is the room's, nothing is saved or sent online, and a headless run (the server, the tests) doesn't draw it.
## Where it hangs comes from the hideout level's Life node ("bag": the chain's top, "bag_bottom": the bag's bottom).

const HIT := preload("res://audio/world/bag_hit.wav")
const DAMPING := 1.2         # per second
const MAX_TILT := 0.6        # radians
const GRAVITY := 9.8
const SIZE := Vector3(0.46, 1.15, 0.46)
const HIT_DB := -6.0
const HIT_RANGE := 16.0

var top := Vector3.ZERO       # where the chain hangs from
var length := 1.0             # top to the bag's middle
var tilt := Vector2.ZERO      # lean about x, lean about z (radians)
var spin := Vector2.ZERO
var hits := 0                 # (counted: the tests check a punch lands)
var _bag: Node3D
var _chain: MeshInstance3D
var _chain_len := 0.0


func setup(life: Node3D) -> void:
	top = life.get_meta(&"bag")
	var bottom: Vector3 = life.get_meta(&"bag_bottom")
	length = top.y - (bottom.y + SIZE.y / 2.0)
	_chain_len = length - SIZE.y / 2.0
	add_to_group(&"punching_bag")
	if not Reacts.wanted(self):
		set_physics_process(false)
		return
	add_to_group(Reacts.GROUP)
	_bag = Node3D.new()
	add_child(_bag)
	var leather := _material(Color(0.48, 0.17, 0.13))
	var band := _material(Color(0.12, 0.12, 0.13))
	_box(_bag, SIZE, Vector3.ZERO, leather)
	_box(_bag, Vector3(0.4, 1.17, 0.4), Vector3.ZERO, leather).rotation.y = PI / 4.0   # (rounder: two boxes)
	for y: float in [-SIZE.y / 2.0 + 0.06, SIZE.y / 2.0 - 0.06]:   # dark bands at the ends, a ring on top
		_box(_bag, Vector3(SIZE.x + 0.02, 0.1, SIZE.z + 0.02), Vector3(0, y, 0), band)
	_box(_bag, Vector3(0.08, 0.1, 0.02), Vector3(0, SIZE.y / 2.0 + 0.06, 0), band)
	_chain = _box(self, Vector3(0.03, 1.0, 0.03), Vector3.ZERO, band)
	_place()


func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 1.0
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.material_override = material
	box.position = at
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(box)
	return box


## The bag's middle where it hangs now.
func middle() -> Vector3:
	return top + _turn() * Vector3(0.0, -length, 0.0)


## A punch from `from` (a fist, a shoulder): pushes the bag away from it, a thud. `power` 1 is a solid hit.
func punch(from: Vector3, power := 1.0) -> void:
	var away := middle() - from
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	_push(away.normalized() * 1.3 * power)
	hits += 1
	if _bag != null:
		WorldSounds.at_soft(self, HIT, middle(), HIT_DB + 4.0 * (power - 1.0), HIT_RANGE, randf_range(0.9, 1.1))


func _push(velocity: Vector3) -> void:
	# (leaning about +x swings the bag towards -z; about +z, towards +x: as scripts/swing_lamps.gd)
	spin += Vector2(-velocity.z, velocity.x) / maxf(length, 0.2)
	set_physics_process(_bag != null)


func on_shot(from: Vector3, to: Vector3) -> void:
	var p := middle()
	var near := Geometry3D.get_closest_point_to_segment(p, from, to)
	if near.distance_to(p) < SIZE.x * 0.7:
		var dir := (to - from).normalized()
		_push(Vector3(dir.x, 0.0, dir.z).normalized() * 0.9)


func on_blast(at: Vector3, radius: float) -> void:
	var d := middle() - at
	d.y = 0.0
	var reach := radius * 2.5
	if d.length() < reach:
		_push(d.normalized() * 1.5 * (1.0 - d.length() / reach))


func _physics_process(delta: float) -> void:
	var w2 := GRAVITY / maxf(length, 0.2)
	spin += (-tilt * w2 - spin * DAMPING * 2.0) * delta
	tilt = (tilt + spin * delta).limit_length(MAX_TILT)
	if tilt.length() < 0.002 and spin.length() < 0.01:
		tilt = Vector2.ZERO
		spin = Vector2.ZERO
		set_physics_process(false)
	_place()


func _turn() -> Basis:
	return Basis.from_euler(Vector3(tilt.x, 0.0, tilt.y))


func _place() -> void:
	if _bag == null:
		return
	var turn := _turn()
	_bag.transform = Transform3D(turn, top + turn * Vector3(0.0, -length, 0.0))
	_chain.transform = Transform3D(turn * Basis.from_scale(Vector3(1.0, _chain_len, 1.0)),
			top + turn * Vector3(0.0, -_chain_len / 2.0, 0.0))
