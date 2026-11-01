extends Node3D
## The hangout's sliding doors (0.25.34, owner: "add doors? custom nice doors they can open... make sure textures
## don't glitch"): a pair of painted steel leaves on a track over each doorway, hung a few centimetres in front of the
## wall (never in its face, so nothing flickers). They slide apart on their own when you walk up and close behind you.
## They stop you only while they're shut. Hideout only: nothing is sent online. make_hideout.py places them (data).

const STRIDE := 7            # doorway middle x, floor y, z, width, height, yaw (degrees: local x along the wall), side
const THICK := 0.04
const AHEAD := 0.1           # how far in front of the wall's middle the leaves hang (the wall is 0.12 thick)
const OPEN_NEAR := 2.3       # metres from the doorway: open
const SLIDE_TIME := 0.45
const TEXTURE := preload("res://assets/textures/hangout_door.png")
const OPEN_SOUND := preload("res://audio/world/door_open.wav")
const SHUT_SOUND := preload("res://audio/world/door_close.wav")

@export var data := PackedFloat32Array()

## Per doorway: how open (0 shut .. 1 open), whether it's opening, its leaves (bodies) and where they sit shut.
var amount := PackedFloat32Array()
var _want := PackedByteArray()
var _leaves: Array[Array] = []
var _middles := PackedVector3Array()
var _widths := PackedFloat32Array()
var _sounds: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	var n := data.size() / STRIDE
	amount.resize(n)
	_want.resize(n)
	var material := StandardMaterial3D.new()
	material.albedo_texture = TEXTURE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.8
	for i in n:
		var d := data.slice(i * STRIDE, i * STRIDE + STRIDE)
		var middle := Vector3(d[0], d[1], d[2])
		var width := d[3]
		var height := d[4]
		var basis := Basis(Vector3.UP, deg_to_rad(d[5]))
		var ahead := basis.z * AHEAD * d[6]
		_middles.append(middle)
		_widths.append(width)
		var pair: Array = []
		for k in 2:
			var side := -1.0 if k == 0 else 1.0
			var body := AnimatableBody3D.new()
			body.sync_to_physics = false
			body.collision_layer = 1
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(width * 0.5, height, THICK + 0.04)
			shape.shape = box
			shape.position.y = height * 0.5
			body.add_child(shape)
			var mesh := MeshInstance3D.new()
			mesh.mesh = _leaf_mesh(width * 0.5, height, side > 0.0)
			mesh.material_override = material
			body.add_child(mesh)
			body.transform = Transform3D(basis, middle + ahead + basis.x * side * width * 0.25)
			add_child(body)
			pair.append(body)
		_leaves.append(pair)
		var sound := AudioStreamPlayer3D.new()
		sound.position = middle + Vector3.UP * 1.2
		sound.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		sound.volume_db = -8.0
		add_child(sound)
		_sounds.append(sound)


## A leaf: a thin box, its two faces the whole picture (the handle side mirrored), the edges in the frame's colour.
func _leaf_mesh(w: float, h: float, mirror: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var t := THICK * 0.5
	var edge_uv := Vector2(0.02, 0.5)
	for face in 2:
		var z := t if face == 0 else -t
		var n := Vector3(0, 0, 1 if face == 0 else -1)
		var corners := [Vector3(x0, 0, z), Vector3(x1, 0, z), Vector3(x1, h, z), Vector3(x0, h, z)]
		# (The picture's pull is by its right edge: keep it at the meeting edge, from both sides.)
		var uvs := [Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]
		if not mirror:
			uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var order := [0, 1, 2, 0, 2, 3] if face == 0 else [0, 2, 1, 0, 3, 2]
		for k: int in order:
			st.set_normal(n)
			st.set_uv(uvs[k])
			st.add_vertex(corners[k])
	# The four edges.
	var sides := [[Vector3(x0, 0, -t), Vector3(x0, 0, t), Vector3(x0, h, t), Vector3(x0, h, -t), Vector3.LEFT],
		[Vector3(x1, 0, t), Vector3(x1, 0, -t), Vector3(x1, h, -t), Vector3(x1, h, t), Vector3.RIGHT],
		[Vector3(x0, h, t), Vector3(x1, h, t), Vector3(x1, h, -t), Vector3(x0, h, -t), Vector3.UP],
		[Vector3(x0, 0, -t), Vector3(x1, 0, -t), Vector3(x1, 0, t), Vector3(x0, 0, t), Vector3.DOWN]]
	for q: Array in sides:
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(q[4])
			st.set_uv(edge_uv)
			st.add_vertex(q[k])
	return st.commit()


func _physics_process(delta: float) -> void:
	var movers := get_tree().get_nodes_in_group(Reacts.MOVER)
	for i in amount.size():
		var near := false
		for m: Node in movers:
			var p := (m as Node3D).global_position
			if absf(p.y - (global_position.y + _middles[i].y)) < 2.0 \
					and Vector2(p.x, p.z).distance_to(Vector2(to_global(_middles[i]).x, to_global(_middles[i]).z)) < OPEN_NEAR:
				near = true
		if near != bool(_want[i]):
			_want[i] = 1 if near else 0
			_sounds[i].stream = OPEN_SOUND if near else SHUT_SOUND
			_sounds[i].play()
		var goal := 1.0 if near else 0.0
		if amount[i] == goal:
			continue
		amount[i] = move_toward(amount[i], goal, delta / SLIDE_TIME)
		var e := amount[i] * amount[i] * (3.0 - 2.0 * amount[i])     # (eased)
		for k in 2:
			var body: AnimatableBody3D = _leaves[i][k]
			var side := -1.0 if k == 0 else 1.0
			var shut := _middles[i] + body.transform.basis.z * AHEAD * data[i * STRIDE + 6] \
				+ body.transform.basis.x * side * _widths[i] * 0.25
			body.position = shut + body.transform.basis.x * side * e * (_widths[i] * 0.5 + 0.05)


## Is doorway i open enough to walk through? (The smoke test.)
func is_open(i: int) -> bool:
	return amount[i] > 0.95
