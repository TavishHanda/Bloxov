extends Node3D
## Paper and leaves blowing about (0.28.0, owner: give the world some life): a few dead leaves tumbling along the wind
## round the camera wherever you are outside, and scraps of paper with them in town. They follow the camera (only
## what's near you is drawn) and stop while you're under a roof. Looks only: nothing hits them, nothing is sent online
## and the game server never draws them.

const WIND := Vector3(0.64, 0.0, 0.77)
const LEAF_COLOURS := [Color(0.42, 0.3, 0.14), Color(0.55, 0.38, 0.16), Color(0.33, 0.28, 0.12)]

@export var town := Rect2()   # in Godot x, z: where paper blows about too

var leaves: CPUParticles3D
var paper: CPUParticles3D
var _check := 0.0
var _ground := 0.0   # how far below the camera the ground is (looked up now and then)


func _ready() -> void:
	if not Reacts.wanted(self):
		return
	leaves = _blowing(30, Vector3(0.16, 0.01, 0.12), LEAF_COLOURS[0])
	leaves.name = "Leaves"
	paper = _blowing(8, Vector3(0.18, 0.005, 0.24), Color(0.82, 0.8, 0.72))
	paper.name = "Paper"
	paper.emitting = false


func _blowing(amount: int, size: Vector3, colour: Color) -> CPUParticles3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	mesh.material = material
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.randomness = 0.5
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14.0, 0.5, 14.0)
	p.direction = WIND + Vector3.UP * 0.2
	p.spread = 25.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0.0, -0.05, 0.0)
	p.damping_min = 0.1
	p.damping_max = 0.3
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.particle_flag_rotate_y = false
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	if colour == LEAF_COLOURS[0]:
		var ramp := Gradient.new()   # (browns: one colour per leaf)
		ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		ramp.colors = PackedColorArray(LEAF_COLOURS)
		p.color_initial_ramp = ramp
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
	add_child(p)
	return p


func _process(delta: float) -> void:
	if leaves == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	# (upwind of the camera, about knee height over the ground: they blow past you)
	var at := Vector3(eye.x, eye.y - _ground + 0.7, eye.z) - WIND * 5.0
	leaves.global_position = at
	paper.global_position = at
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	var space := get_world_3d().direct_space_state
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + Vector3.DOWN * 4.0, 1))
	_ground = eye.y - down.position.y if down else 1.6
	var outside := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + Vector3.UP * 25.0, 1)).is_empty()
	leaves.emitting = outside
	paper.emitting = outside and town.has_point(Vector2(eye.x, eye.z))

