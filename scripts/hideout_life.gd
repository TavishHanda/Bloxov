extends Node3D
## A little life in the hideout (0.28.5, owner: "we need to give it more texture and life in the hideout too"): steam
## off the stove's pot and its fire flickering through the vents, dust drifting in the light over the war table, the
## TV's picture changing (it showed one blue glow). Where they go comes from art_source/scripts/make_hideout.py (this node's metadata). Looks
## only: nothing collides, nothing is sent online, and a headless run (the server, the tests) draws none of it.

const GLOW := preload("res://assets/shaders/hideout_glow.gdshader")
const TV := preload("res://assets/shaders/tv_picture.gdshader")
# Lively hideout (owner 2026-11-09, "rare and tied to things"): each sound plays only near the thing making it.
const DRIPS: Array[AudioStream] = [preload("res://audio/world/drip1.wav"), preload("res://audio/world/drip2.wav")]
const PIPE_KNOCK := preload("res://audio/world/pipe_knock.wav")
const GENERATOR := preload("res://audio/world/generator.wav")
const SWITCH := preload("res://audio/world/switch.wav")
const DRIP_EVERY := Vector2(2.5, 6.0)      # seconds between drops off the tap
const KNOCK_EVERY := Vector2(45.0, 110.0)  # seconds between the water pipe's knocks
const NEAR_DRIP := 7.0                     # metres you hear a drop from
const NEAR_PIPE := 14.0
const NEAR_GENERATOR := 12.0
const RAT := preload("res://audio/world/rat.wav")
const RAT_EVERY := Vector2(50.0, 140.0)    # seconds between the rat's runs
const RAT_SPEED := 1.6                     # m/s
const NEAR_RAT := 8.0

var steam: CPUParticles3D
var dust: CPUParticles3D
var glows: Array[MeshInstance3D] = []
var pictures: Array[MeshInstance3D] = []   # the TV's and the projector screen's
var drop: MeshInstance3D                   # the drop falling off the tap
var stream: MeshInstance3D                 # the washroom tap's water, while it runs (0.34.12)
var splash: CPUParticles3D                 # ... and where it lands
var tap_on := false
var _tap_at := Vector3.INF                 # the spout, and the water it falls into
var _tap_to := Vector3.INF
var _tap_left := 0.0                       # seconds until the tap turns itself off
var _splash_left := 0.0
var fan: Node3D                            # the generator's fan, turning
var exhaust: CPUParticles3D
var engine: AudioStreamPlayer3D
var _drip_at := Vector3.INF
var _pipe_at := Vector3.INF
var _drip_left := 0.0
var _knock_left := 0.0
var _drop_fall := -1.0                     # how far the drop has fallen (m), -1 while none is falling
var _generator_at := Vector3.INF
var _dice := RandomNumberGenerator.new()
var rat: Node3D                            # the rat (hidden between runs)
var _rat_path := PackedVector3Array()      # where it runs between
var _rat_left := 0.0
var _rat_run := -1.0                       # how far along its run (0-1), -1 while it's hiding
var _rat_back := false                     # this run goes the other way
var _rat_pause := 0.0


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
		_picture(get_meta(&"tv"), Vector2(0.54, 0.4), Vector3.RIGHT)
	if has_meta(&"screen"):   # (0.28.9, owner: the fun room's projector screen "the same as the tv")
		_picture(get_meta(&"screen"), Vector2(4.3, 2.25), get_meta(&"screen_dir", Vector3.BACK))
	if has_meta(&"dust"):
		dust = _dust(get_meta(&"dust"))
	if has_meta(&"drip"):
		_drip_at = get_meta(&"drip")
		drop = _drop(_drip_at)
	if has_meta(&"sink") and has_meta(&"sink_to"):
		_tap_at = get_meta(&"sink")
		_tap_to = get_meta(&"sink_to")
		_build_sink()
	if has_meta(&"pipes"):
		_pipe_at = get_meta(&"pipes")
	if has_meta(&"generator"):
		_generator(get_meta(&"generator"))
	if has_meta(&"rat") and has_meta(&"rat_to"):
		_rat_path = PackedVector3Array([get_meta(&"rat"), get_meta(&"rat_to")])
		rat = _rat()
	_dice.randomize()
	_rat_left = _dice.randf_range(RAT_EVERY.x * 0.3, RAT_EVERY.y * 0.5)
	_drip_left = _dice.randf_range(DRIP_EVERY.x, DRIP_EVERY.y)
	_knock_left = _dice.randf_range(KNOCK_EVERY.x, KNOCK_EVERY.y)
	set_process(_drip_at != Vector3.INF or _pipe_at != Vector3.INF or fan != null or rat != null
		or _tap_at != Vector3.INF)
	if not glows.is_empty():
		Reacts.warm_up(self, glows[0].mesh, glows[0].material_override)


func _process(delta: float) -> void:
	if fan != null:
		fan.rotate_object_local(Vector3.RIGHT, delta * 14.0)
	if drop != null:
		_drip(delta)
	if _tap_at != Vector3.INF:
		_run_tap(delta)
	if rat != null:
		_run_rat(delta)
	if _pipe_at != Vector3.INF:
		_knock_left -= delta
		if _knock_left <= 0.0:
			_knock_left = _dice.randf_range(KNOCK_EVERY.x, KNOCK_EVERY.y)
			knock_pipe()


## The rat comes out, runs along the wall (stopping to sniff now and then) and is gone again.
func _run_rat(delta: float) -> void:
	if _rat_run < 0.0:
		_rat_left -= delta
		if _rat_left <= 0.0:
			start_rat()
		return
	if _rat_pause > 0.0:
		_rat_pause -= delta
		rat.position.y = _rat_path[0].y + 0.004 * sin(Time.get_ticks_msec() * 0.05)   # (sniffing)
		return
	var length := _rat_path[0].distance_to(_rat_path[1])
	_rat_run += delta * RAT_SPEED / maxf(length, 0.1)
	if _rat_run >= 1.0:
		_rat_run = -1.0
		rat.visible = false
		_rat_left = _dice.randf_range(RAT_EVERY.x, RAT_EVERY.y)
		return
	if _dice.randf() < delta * 0.35 and _rat_run > 0.15 and _rat_run < 0.85:
		_rat_pause = _dice.randf_range(0.4, 1.2)
	var a := _rat_path[1] if _rat_back else _rat_path[0]
	var b := _rat_path[0] if _rat_back else _rat_path[1]
	rat.position = a.lerp(b, _rat_run) + Vector3.UP * absf(sin(_rat_run * length * 18.0)) * 0.012
	rat.look_at(to_global(b), Vector3.UP)


func start_rat() -> void:
	_rat_run = 0.0
	_rat_back = _dice.randf() < 0.5
	rat.visible = true
	rat.position = _rat_path[1] if _rat_back else _rat_path[0]
	WorldSounds.at_soft(self, RAT, to_global(rat.position), -16.0, NEAR_RAT, _dice.randf_range(0.9, 1.15))


## A little grey-brown rat of boxes, nose to -z (look_at points it where it runs).
func _rat() -> Node3D:
	var body := Node3D.new()
	body.name = "Rat"
	body.visible = false
	add_child(body)
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color(0.29, 0.25, 0.22)
	fur.roughness = 1.0
	var pink := StandardMaterial3D.new()
	pink.albedo_color = Color(0.62, 0.45, 0.43)
	pink.roughness = 1.0
	for part: Array in [[Vector3(0.07, 0.06, 0.15), Vector3(0, 0.04, 0.0), fur],       # body
			[Vector3(0.05, 0.045, 0.06), Vector3(0, 0.045, -0.095), fur],               # head
			[Vector3(0.018, 0.016, 0.02), Vector3(0, 0.035, -0.13), pink],               # nose
			[Vector3(0.02, 0.025, 0.006), Vector3(-0.02, 0.075, -0.085), pink],          # ears
			[Vector3(0.02, 0.025, 0.006), Vector3(0.02, 0.075, -0.085), pink],
			[Vector3(0.008, 0.008, 0.16), Vector3(0, 0.02, 0.15), pink]]:                # tail
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		mesh.material = part[2]
		box.mesh = mesh
		box.position = part[1]
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(box)
	return body


## The water pipe knocks (heard only near the washroom).
func knock_pipe() -> void:
	WorldSounds.at_soft(self, PIPE_KNOCK, to_global(_pipe_at), -10.0, NEAR_PIPE, _dice.randf_range(0.9, 1.1))


## A drop forms on the tap, falls into the trough and plinks (heard only close by).
func _drip(delta: float) -> void:
	if _drop_fall < 0.0:
		_drip_left -= delta
		drop.visible = _drip_left < 0.6   # (it swells on the tap for a moment first)
		drop.scale = Vector3.ONE * clampf(1.0 - _drip_left / 0.6, 0.3, 1.0)
		drop.position = _drip_at
		if _drip_left <= 0.0:
			_drop_fall = 0.0
		return
	_drop_fall += delta * 2.6
	drop.position = _drip_at + Vector3.DOWN * _drop_fall
	if _drop_fall >= 0.12:   # (into the trough's water)
		_drop_fall = -1.0
		drop.visible = false
		_drip_left = _dice.randf_range(DRIP_EVERY.x, DRIP_EVERY.y)
		WorldSounds.at_soft(self, DRIPS[_dice.randi() % DRIPS.size()], to_global(_drip_at), -14.0, NEAR_DRIP,
			_dice.randf_range(0.92, 1.08))


func _drop(at: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.014, 0.02, 0.014)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.82, 0.85, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.metallic_specular = 1.0
	material.roughness = 0.1
	mesh.material = material
	var d := MeshInstance3D.new()
	d.name = "Drop"
	d.mesh = mesh
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.visible = false
	add_child(d)
	d.position = at
	return d


## The washroom sink (0.34.12): USE at it runs the tap for a while, water falling from the gooseneck into the trough
## and splashing there, with the trickle heard close by. Looks only, like the rest of this node.
func set_tap(on: bool) -> void:
	tap_on = on
	if _tap_at == Vector3.INF:   # (headless: no models, no sounds)
		return
	if stream != null:
		stream.visible = on
	if splash != null:
		splash.emitting = on
	if on:
		_tap_left = 25.0
		if drop != null:
			drop.visible = false   # (the other tap's drip can wait)
	WorldSounds.at_soft(self, SWITCH, to_global(_tap_at), -9.0, NEAR_DRIP, _dice.randf_range(0.9, 1.05))


func _run_tap(delta: float) -> void:
	if not tap_on:
		return
	_tap_left -= delta
	if _tap_left <= 0.0:
		set_tap(false)
		return
	var wobble := 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.03)
	stream.scale.x = wobble
	stream.scale.z = wobble
	_splash_left -= delta
	if _splash_left <= 0.0:   # (a trickle: quick quiet drips at the water's surface)
		_splash_left = _dice.randf_range(0.09, 0.2)
		WorldSounds.at_soft(self, DRIPS[_dice.randi() % DRIPS.size()], to_global(_tap_to), -20.0, NEAR_DRIP,
			_dice.randf_range(1.15, 1.5))


func _build_sink() -> void:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.62, 0.76, 0.8, 0.55)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.metallic_specular = 1.0
	water.roughness = 0.05
	var length := _tap_at.distance_to(_tap_to)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, maxf(length, 0.05), 0.02)
	mesh.material = water
	stream = MeshInstance3D.new()
	stream.name = "Tap"
	stream.mesh = mesh
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stream)
	stream.position = (_tap_at + _tap_to) * 0.5
	stream.visible = false
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(0.72, 0.86, 0.9, 0.7), Color(0.75, 0.88, 0.92, 0.5),
		Color(0.75, 0.88, 0.92, 0.0)])
	splash = _puffs(12, 0.5, 0.012, ramp)
	splash.name = "Splash"
	splash.position = _tap_to + Vector3.UP * 0.012
	splash.preprocess = 0.0
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	splash.emission_sphere_radius = 0.025
	splash.direction = Vector3.UP
	splash.spread = 35.0
	splash.initial_velocity_min = 0.15
	splash.initial_velocity_max = 0.4
	splash.gravity = Vector3(0.0, -2.4, 0.0)
	splash.emitting = false


## The generator (its body is in the model): a fan turning behind a guard on its west end, puffs off the exhaust
## pipe and its chug, heard only near it.
func _generator(at: Vector3) -> void:
	_generator_at = at
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.13, 0.135, 0.14)
	iron.roughness = 0.9
	var hub := Node3D.new()
	hub.name = "Fan"
	add_child(hub)
	hub.position = at + Vector3(-0.93, 0.02, 0.0)
	for k in 4:
		var blade := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.02, 0.3, 0.08)
		mesh.material = iron
		blade.mesh = mesh
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var turn := Basis(Vector3.RIGHT, k * PI / 2.0)
		blade.transform = Transform3D(turn * Basis(Vector3.UP, 0.35), turn * Vector3(0.0, 0.15, 0.0))
		hub.add_child(blade)
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.05, 0.07, 0.07)
	cap_mesh.material = iron
	cap.mesh = cap_mesh
	hub.add_child(cap)
	fan = hub
	for k in 4:   # (a square steel frame round it)
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.04, 0.04, 0.74) if k < 2 else Vector3(0.04, 0.74, 0.04)
		bar_mesh.material = iron
		bar.mesh = bar_mesh
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var side := 1.0 if k % 2 == 0 else -1.0
		add_child(bar)
		bar.position = at + Vector3(-0.92, 0.02, 0.0) + (Vector3(0, 0.35 * side, 0) if k < 2 else Vector3(0, 0, 0.35 * side))
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	ramp.colors = PackedColorArray([Color(0.3, 0.3, 0.3, 0.0), Color(0.32, 0.32, 0.32, 0.35), Color(0.4, 0.4, 0.4, 0.0)])
	exhaust = _puffs(14, 2.2, 0.08, ramp)
	exhaust.name = "Exhaust"
	exhaust.position = at + Vector3(0.8, 2.15, 0.0)   # (the top of its exhaust pipe)
	exhaust.direction = Vector3.UP
	exhaust.spread = 15.0
	exhaust.initial_velocity_min = 0.3
	exhaust.initial_velocity_max = 0.5
	exhaust.gravity = Vector3(0.02, 0.06, 0.0)
	exhaust.scale_amount_min = 0.8
	exhaust.scale_amount_max = 1.5
	engine = AudioStreamPlayer3D.new()
	engine.name = "Engine"
	engine.stream = Ambience.looped(GENERATOR)
	engine.volume_db = -16.0
	engine.unit_size = 2.0
	engine.max_distance = NEAR_GENERATOR
	engine.bus = Hearing.world_bus()
	engine.autoplay = true
	add_child(engine)
	engine.position = at


## A changing picture (assets/shaders/tv_picture.gdshader) on a quad over a glowing screen, facing `out`.
func _picture(at: Vector3, size: Vector2, out: Vector3) -> MeshInstance3D:
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	screen.mesh = quad
	var picture := ShaderMaterial.new()
	picture.shader = TV
	screen.material_override = picture
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.rotation.y = atan2(out.x, out.z)
	add_child(screen)
	screen.position = at
	pictures.append(screen)
	Reacts.warm_up(self, quad, picture)
	return screen


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
