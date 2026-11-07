extends Node3D
## Crows (0.28.0, owner: give the world some life): a few small flocks circling high over the fields and the
## churchyard, flapping and gliding, now and then drifting wider. One MultiMesh for every bird (one draw call), the
## flapping in a shader (assets/shaders/crow.gdshader). Looks only: nothing hits them, nothing is sent online and the
## game server never draws them.

const STRIDE := 4          # flock: middle x, ground y, z, birds
const SHADER := preload("res://assets/shaders/crow.gdshader")
const HEIGHT := 24.0       # how high over the ground, about
const SIZE := 2.0

@export var data := PackedFloat32Array()

var flocks: Array[Dictionary] = []
var positions := PackedVector3Array()   # where each crow is now (the MultiMesh can't be read back on every renderer)
var _multi: MultiMesh
var _count := 0
## Now and then a crow in the flock nearest you caws (0.31.14, owner). Its own dice: looks and sounds only.
const CAW_EVERY := Vector2(7.0, 18.0)   # seconds between caws, from-to
var _caw_rng := RandomNumberGenerator.new()
var _caw_wait := 4.0


func _ready() -> void:
	if not Reacts.wanted(self):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 2800
	for i in data.size() / STRIDE:
		var birds: Array[Dictionary] = []
		for k in int(data[i * STRIDE + 3]):
			birds.append({"angle": rng.randf() * TAU, "radius": rng.randf_range(10.0, 22.0),
				"height": rng.randf_range(-4.0, 5.0), "speed": rng.randf_range(0.16, 0.24) * (1 if rng.randf() < 0.85 else -1),
				"phase": rng.randf()})
			_count += 1
		flocks.append({"middle": Vector3(data[i * STRIDE], data[i * STRIDE + 1] + HEIGHT, data[i * STRIDE + 2]),
			"birds": birds, "drift": rng.randf() * TAU})
	if _count == 0:
		return
	var material := ShaderMaterial.new()
	material.shader = SHADER
	_multi = MultiMesh.new()
	_multi.transform_format = MultiMesh.TRANSFORM_3D
	_multi.use_custom_data = true
	_multi.mesh = crow_mesh()
	_multi.instance_count = _count
	positions.resize(_count)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Crows"
	mmi.multimesh = _multi
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_process(0.0)
	Reacts.warm_up(self, _multi.mesh, material)


func _process(delta: float) -> void:
	if _multi == null:
		return
	_caw(delta)
	var t := Time.get_ticks_msec() / 1000.0
	var n := 0
	for flock: Dictionary in flocks:
		# (the flock's middle wanders a little round its spot)
		var wander := Vector3(sin(t * 0.03 + flock.drift), 0.0, cos(t * 0.025 + flock.drift)) * 12.0
		for bird: Dictionary in flock.birds:
			bird.angle += bird.speed * delta
			var r: float = bird.radius * (1.0 + 0.25 * sin(t * 0.07 + bird.phase * 9.0))
			var at: Vector3 = flock.middle + wander + Vector3(cos(bird.angle) * r,
				bird.height + 1.5 * sin(t * 0.3 + bird.phase * 7.0), sin(bird.angle) * r)
			var ahead := Vector3(-sin(bird.angle), 0.0, cos(bird.angle)) * signf(bird.speed)
			var bank := -0.35 * signf(bird.speed)
			var basis := (Basis.looking_at(ahead, Vector3.UP) * Basis(Vector3.BACK, bank)).scaled(Vector3.ONE * SIZE)
			_multi.set_instance_transform(n, Transform3D(basis, at))
			positions[n] = at
			var flap := 1.0 if fmod(t * 0.2 + bird.phase * 5.0, 3.0) < 1.6 else 0.0   # (flap a while, glide a while)
			_multi.set_instance_custom_data(n, Color(bird.phase, flap, 0.0, 0.0))
			n += 1


func _caw(delta: float) -> void:
	_caw_wait -= delta
	if _caw_wait > 0.0 or positions.is_empty():
		return
	_caw_wait = _caw_rng.randf_range(CAW_EVERY.x, CAW_EVERY.y)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var best := -1
	var best_d := WorldSounds.CROW_RANGE
	for i in positions.size():
		var d := positions[i].distance_to(camera.global_position)
		if d < best_d:
			best = i
			best_d = d
	if best >= 0:
		WorldSounds.at_soft(self, WorldSounds.CROWS[_caw_rng.randi() % WorldSounds.CROWS.size()], positions[best],
			WorldSounds.CROW_DB, WorldSounds.CROW_RANGE, 1.0, 0.08)


## A crow (drawn twice this size: about 90 cm across the wings), looking down -z: a body, a tail and two wings (flat, both sides drawn).
static func crow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		st.set_normal(Vector3.UP)
		for p: Vector3 in [a, b, c, a, c, d]:
			st.add_vertex(p)
	quad.call(Vector3(-0.05, 0, -0.16), Vector3(0.05, 0, -0.16), Vector3(0.05, 0, 0.1), Vector3(-0.05, 0, 0.1))   # body
	quad.call(Vector3(-0.03, 0.03, -0.16), Vector3(0.03, 0.03, -0.16), Vector3(0.03, 0.03, 0.06), Vector3(-0.03, 0.03, 0.06))
	quad.call(Vector3(-0.06, 0, 0.1), Vector3(0.06, 0, 0.1), Vector3(0.08, 0, 0.22), Vector3(-0.08, 0, 0.22))     # tail
	for s in [-1.0, 1.0]:                                                                                          # wings
		quad.call(Vector3(s * 0.05, 0, -0.08), Vector3(s * 0.23, 0, -0.03), Vector3(s * 0.24, 0, 0.04), Vector3(s * 0.05, 0, 0.05))
	return st.commit()
