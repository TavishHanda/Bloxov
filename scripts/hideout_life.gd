extends Node3D
## A little life in the hideout (0.28.5, owner: "we need to give it more texture and life in the hideout too"): steam
## off the stove's pot and its fire flickering through the vents, dust drifting in the light over the war table, the
## TV's picture changing (it showed one blue glow). Where they go comes from art_source/scripts/make_hideout.py (this node's metadata). Looks
## only: nothing collides, nothing is sent online, and a headless run (the server, the tests) draws none of it.

const GLOW := preload("res://assets/shaders/hideout_glow.gdshader")
const TV := preload("res://assets/shaders/tv_picture.gdshader")

var steam: CPUParticles3D
var dust: CPUParticles3D
var glows: Array[MeshInstance3D] = []


func _ready() -> void:
	if not Reacts.wanted(self):
		return
	if has_meta(&"steam"):
		steam = _steam(get_meta(&"steam"))
	if has_meta(&"fire"):   # (0.28.8: the stove's door, its fire showing between the grate's bars, and the ash door's crack)
		var dir: Vector3 = get_meta(&"fire_dir", Vector3.LEFT)
		var turn := atan2(dir.z, -dir.x) if absf(dir.x) > 0.001 or absf(dir.z) > 0.001 else 0.0
		var fire := _glow(Vector3(0.006, 0.16, 0.17), Color(1.0, 0.42, 0.1), 1.3)
		fire.position = get_meta(&"fire")
		fire.rotation.y = turn
		if has_meta(&"ash"):
			var ash := _glow(Vector3(0.006, 0.012, 0.15), Color(1.0, 0.3, 0.06), 0.8)
			ash.position = (get_meta(&"ash") as Vector3) + Vector3.UP * 0.036
			ash.rotation.y = turn
	if has_meta(&"tv"):
		var screen := MeshInstance3D.new()   # (a quad over the model's glowing screen, facing out into the room)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.54, 0.4)
		screen.mesh = quad
		var picture := ShaderMaterial.new()
		picture.shader = TV
		screen.material_override = picture
		screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		screen.rotation.y = PI * 0.5
		add_child(screen)
		screen.position = get_meta(&"tv")
		Reacts.warm_up(self, quad, picture)
	if has_meta(&"dust"):
		dust = _dust(get_meta(&"dust"))
	if not glows.is_empty():
		Reacts.warm_up(self, glows[0].mesh, glows[0].material_override)


func _glow(size: Vector3, colour: Color, strength: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := ShaderMaterial.new()
	material.shader = GLOW
	material.set_shader_parameter(&"colour", Vector3(colour.r, colour.g, colour.b))
	material.set_shader_parameter(&"strength", strength)
	var glow := MeshInstance3D.new()
	glow.mesh = mesh
	glow.material_override = material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	glows.append(glow)
	return glow


func _puffs(amount: int, lifetime: float, size: float, ramp: Gradient) -> CPUParticles3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.color_ramp = ramp
	add_child(p)
	return p


func _steam(at: Vector3) -> CPUParticles3D:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(0.9, 0.9, 0.88, 0.0), Color(0.92, 0.92, 0.9, 0.5), Color(0.8, 0.8, 0.78, 0.0)])
	var p := _puffs(18, 2.6, 0.09, ramp)
	p.name = "Steam"
	p.position = at
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.1, 0.01, 0.1)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.4
	p.gravity = Vector3(0.03, 0.05, 0.0)
	p.angle_min = 0.0
	p.angle_max = 90.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.3
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 2.5))
	p.scale_amount_curve = grow
	return p


func _dust(at: Vector3) -> CPUParticles3D:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.92, 0.75, 0.0), Color(1.0, 0.92, 0.75, 0.55),
		Color(1.0, 0.92, 0.75, 0.55), Color(1.0, 0.92, 0.75, 0.0)])
	var p := _puffs(70, 14.0, 0.014, ramp)
	p.name = "Dust"
	p.position = at
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(3.0, 1.6, 2.4)
	p.direction = Vector3(1.0, 0.0, 0.3)
	p.spread = 180.0
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.08
	p.gravity = Vector3(0.0, -0.006, 0.0)
	return p
