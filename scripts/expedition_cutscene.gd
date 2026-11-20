class_name ExpeditionCutscene
extends Node3D
## Leaving on an expedition (0.38.0, owner 2026-11-20: "some cool animation/cutscene of u leaving", no escape raid):
## about 11 seconds. Dawn at the shore below the hideout: the amphibious armoured truck rolls down the ramp, into the
## water and floats off towards the haven, then the trip's line comes up. Any key or tap skips it (after a moment),
## and it ends back in the (new, wiped) hideout. Built in code like the item icons; never on the server, never synced.

const SCENE := "res://scenes/expedition_cutscene.tscn"
const HIDEOUT := "res://scenes/hideout_world.tscn"
const LENGTH := 11.0
## When the truck reaches the water (it slows and starts to float).
const SPLASH := 4.2
## The trip number the line shows (set by the hideout before changing scene).
static var trips := 1
## Upgrade points the trip added to the shared pool (0 once the pool is full), and who went (a name, or "").
static var points := Expedition.POINTS
static var who := ""

var _time := 0.0
var _truck: Node3D
var _camera: Camera3D
var _wake: MeshInstance3D
var _fade: ColorRect
var _title: Label
var _sub: Label
var _done := false


func _ready() -> void:
	_build_world()
	_truck = build_truck()
	add_child(_truck)
	_wake = MeshInstance3D.new()
	var foam := PlaneMesh.new()
	foam.size = Vector2(2.6, 8.0)
	_wake.mesh = foam
	_wake.material_override = _mat(Color(0.9, 0.95, 1.0, 0.0), true)
	add_child(_wake)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	_camera.make_current()
	_build_overlay()
	_place(0.0)


func _process(delta: float) -> void:
	_time += delta
	_place(_time)
	if _time >= LENGTH:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if _time > 1.0 and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch) and event.is_pressed():
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	get_tree().change_scene_to_file(HIDEOUT)


## Where everything is at time `t`.
func _place(t: float) -> void:
	# Down the ramp (z from -20 to 6, y from 3 to -0.4), then afloat out to sea (on to z 120, slower, bobbing).
	var z: float
	var y: float
	if t < SPLASH:
		var k := t / SPLASH
		z = lerpf(-20.0, 6.0, k * k * (3.0 - 2.0 * k))
		y = lerpf(3.0, -1.0, clampf((z + 2.0) / 8.0, 0.0, 1.0)) if z > -2.0 else 3.0
	else:
		var k := t - SPLASH
		z = 6.0 + k * 9.0 + k * k * 0.6
		y = -1.0 + sin(k * 2.2) * 0.08
	_truck.position = Vector3(0.0, y, z)
	var pitch := 0.32 if t < SPLASH and z > -2.0 else 0.0
	if t >= SPLASH:
		pitch = sin((t - SPLASH) * 1.7) * 0.03 + maxf(0.0, 0.15 - (t - SPLASH) * 0.12)
	_truck.rotation = Vector3(pitch, 0.0, sin(t * 1.3) * 0.015)
	# The wake behind it once it's in the water.
	var wake_on := clampf((t - SPLASH) * 1.5, 0.0, 1.0)
	_wake.position = Vector3(0.0, -0.45, z - 6.5)
	(_wake.material_override as StandardMaterial3D).albedo_color.a = 0.3 * wake_on
	# Camera: low by the ramp watching it go past, then up behind it as it heads out.
	var follow := clampf((t - 3.2) / 4.0, 0.0, 1.0)
	follow = follow * follow * (3.0 - 2.0 * follow)
	var start_pos := Vector3(11.0, 3.4, 11.0)
	var end_pos := Vector3(2.5, 6.0, z - 20.0)
	_camera.position = start_pos.lerp(end_pos, follow)
	_camera.look_at(_truck.position + Vector3(0.0, 1.2, 2.0 * follow))
	# Text and the fade.
	_title.modulate.a = clampf((t - 6.5) * 1.5, 0.0, 1.0)
	_sub.modulate.a = clampf((t - 7.3) * 1.5, 0.0, 1.0)
	_fade.color.a = clampf((t - (LENGTH - 1.0)), 0.0, 1.0) + clampf(1.0 - t * 1.5, 0.0, 1.0)


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.86, 0.62, 0.45)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.68, 0.66)
	environment.ambient_light_energy = 0.7
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.86, 0.66, 0.52)
	environment.fog_density = 0.006
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-14.0, 160.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	# The sea, the shore and the ramp down from the hideout's cave.
	_box(Vector3(400.0, 0.2, 400.0), Vector3(0.0, -0.6, 200.0), Color(0.13, 0.33, 0.43))
	_box(Vector3(60.0, 4.0, 40.0), Vector3(0.0, 0.9, -24.0), Color(0.36, 0.33, 0.28))
	var ramp := _box(Vector3(7.0, 0.4, 14.0), Vector3(0.0, 1.0, 0.5), Color(0.42, 0.4, 0.36))
	ramp.rotation.x = 0.32
	# Cliffs either side and the cave mouth behind.
	for side in [-1.0, 1.0]:
		_box(Vector3(14.0, 16.0, 30.0), Vector3(side * 13.0, 6.0, -22.0), Color(0.3, 0.28, 0.25))
		# Mooring posts along the ramp.
		for z in [-4.0, 1.0, 6.0]:
			_box(Vector3(0.3, 1.6, 0.3), Vector3(side * 4.2, 0.6 + maxf(0.0, -z) * 0.32, z), Color(0.35, 0.25, 0.16))
	_box(Vector3(12.0, 9.0, 1.0), Vector3(0.0, 7.0, -36.0), Color(0.08, 0.08, 0.08))
	# Far headlands on the way out.
	_box(Vector3(40.0, 6.0, 20.0), Vector3(-60.0, 1.5, 150.0), Color(0.5, 0.42, 0.4))
	_box(Vector3(30.0, 9.0, 18.0), Vector3(70.0, 3.0, 190.0), Color(0.52, 0.44, 0.42))


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -400.0
	box.offset_right = 400.0
	box.offset_top = -190.0
	box.offset_bottom = -80.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(box)
	_title = Label.new()
	_title.text = "OUT OF THE WAR"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.style_label(_title, 44)
	box.add_child(_title)
	_sub = Label.new()
	var line := "%s reached the haven" % who if who != "" else "You reached the haven"
	var earned := "+%d upgrade points to spend on any character." % points if points > 0 else "Your upgrade points are full."
	_sub.text = "Expedition %d: %s. %s" % [trips, line, earned]
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.style_label(_sub, 24, HudStyle.BRASS)
	box.add_child(_sub)


func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = _mat(color)
	add_child(mesh)
	return mesh


static func _mat(color: Color, see_through := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if see_through:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## The amphibious armoured truck, blocky like the rest of the game (front = +z). `parts` = which parts are on it
## (all by default): the frame is always there; the others add their pieces. The hideout's garage can reuse this.
static func build_truck(parts: Array = ["frame", "engine", "armor", "radio", "supplies"]) -> Node3D:
	var truck := Node3D.new()
	truck.name = "Truck"
	var olive := Color(0.33, 0.36, 0.24)
	var dark := Color(0.16, 0.17, 0.15)
	var steel := Color(0.42, 0.43, 0.42)
	var add := func(size: Vector3, at: Vector3, color: Color, rot := Vector3.ZERO) -> void:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.position = at
		mesh.rotation = rot
		mesh.material_override = _mat(color)
		truck.add_child(mesh)
	# Frame: the boat-shaped hull (a raised bow) and six wheels.
	add.call(Vector3(2.6, 1.0, 6.4), Vector3(0.0, 0.9, 0.0), olive)
	add.call(Vector3(2.4, 0.7, 1.2), Vector3(0.0, 1.05, 3.5), olive, Vector3(-0.5, 0.0, 0.0))
	add.call(Vector3(2.7, 0.15, 6.6), Vector3(0.0, 1.45, 0.0), dark)
	for x in [-1.35, 1.35]:
		for z in [-2.1, 0.0, 2.1]:
			var wheel := MeshInstance3D.new()
			var tyre := CylinderMesh.new()
			tyre.top_radius = 0.55
			tyre.bottom_radius = 0.55
			tyre.height = 0.45
			tyre.radial_segments = 10
			wheel.mesh = tyre
			wheel.position = Vector3(x, 0.55, z)
			wheel.rotation = Vector3(0.0, 0.0, PI / 2.0)
			wheel.material_override = _mat(Color(0.08, 0.08, 0.08))
			truck.add_child(wheel)
	if parts.has("engine"):
		# The cab and the engine hump, the propeller housing at the back.
		add.call(Vector3(2.3, 1.2, 2.0), Vector3(0.0, 2.1, 1.4), olive)
		add.call(Vector3(2.0, 0.25, 0.25), Vector3(0.0, 2.35, 2.42), dark)   # the window slit
		add.call(Vector3(0.9, 0.5, 0.4), Vector3(0.0, 0.7, -3.35), steel)
	if parts.has("armor"):
		# Plates bolted along the sides and over the bow.
		for x in [-1.38, 1.38]:
			add.call(Vector3(0.12, 0.8, 5.6), Vector3(x, 1.35, -0.2), steel)
		add.call(Vector3(2.5, 0.12, 1.1), Vector3(0.0, 1.5, 3.4), steel, Vector3(-0.5, 0.0, 0.0))
		add.call(Vector3(2.4, 0.12, 2.1), Vector3(0.0, 2.75, 1.4), steel)
	if parts.has("radio"):
		add.call(Vector3(0.08, 2.4, 0.08), Vector3(0.9, 3.9, 0.7), dark)
		add.call(Vector3(0.5, 0.35, 0.4), Vector3(0.9, 2.95, 0.7), dark)
	if parts.has("supplies"):
		# Fuel cans and crates strapped on the back deck.
		for x in [-0.8, -0.25, 0.3]:
			add.call(Vector3(0.45, 0.6, 0.3), Vector3(x, 1.85, -2.7), Color(0.55, 0.12, 0.1))
		add.call(Vector3(1.2, 0.6, 1.0), Vector3(0.3, 1.85, -1.5), Color(0.45, 0.36, 0.22))
		add.call(Vector3(0.8, 0.5, 0.8), Vector3(-0.6, 1.8, -1.4), Color(0.4, 0.42, 0.3))
	return truck
