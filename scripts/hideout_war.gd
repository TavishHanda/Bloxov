class_name HideoutWar
extends Node3D
## The war upstairs (lively hideout, owner 2026-11-09: "holy yes"): every few minutes a shell lands somewhere above
## the bunker. Grit trickles off the roof around you, the hanging lamps sway, the lights dip and flicker and the view
## gives a small jolt. Looks only: nothing collides, nothing is sent online, and a headless run (the server, the
## tests) does none of it unless `force_reacts` is set.

const FIRST_AFTER := Vector2(45.0, 90.0)    # seconds after walking in before the first one
const BETWEEN := Vector2(120.0, 240.0)      # seconds between them after that (owner wanted them rare-ish, 0.30.2)
const DUST_FALLS := 4                       # trickles of grit around you per shell
const DUST_REACH := 7.0                     # how far from you (across) they come down
const FLICKER_TIME := 0.9
const SHAKE_TIME := 0.7
const SHELL := preload("res://audio/world/shell_far.wav")
const GRIT := preload("res://audio/world/grit.wav")
const SHELL_DB := -9.0
const ROOF := preload("res://assets/hideout/roof.res")
const SHAKE := 0.012                        # metres the view jolts at most

var walker: Node3D
var toys: HideoutToys
var lamps: Node3D
var left := 0.0                             # seconds to the next shell
var falls: Array[CPUParticles3D] = []       # the grit trickles now falling (for the tests)
var shells := 0                             # how many have landed (for the tests)
var _dice := RandomNumberGenerator.new()
var _flicker := 0.0
var _shake := 0.0
var _camera: Camera3D
var roof: Image = ROOF


func setup(level: Node3D, who: Node3D, hideout_toys: HideoutToys) -> void:
	walker = who
	toys = hideout_toys
	lamps = level.get_node_or_null("Swings") as Node3D
	_camera = who.get(&"camera") as Camera3D if who != null else null


func _ready() -> void:
	_dice.randomize()
	left = _dice.randf_range(FIRST_AFTER.x, FIRST_AFTER.y)
	set_process(Reacts.wanted(self))


func _process(delta: float) -> void:
	left -= delta
	if left <= 0.0:
		left = _dice.randf_range(BETWEEN.x, BETWEEN.y)
		shell()
	_update_flicker(delta)
	_update_shake(delta)


## A shell landing up top, now.
func shell() -> void:
	shells += 1
	_flicker = FLICKER_TIME
	_shake = SHAKE_TIME
	var at := walker.global_position if walker != null else global_position
	var from := Vector3(_dice.randf_range(-1.0, 1.0), 0.0, _dice.randf_range(-1.0, 1.0)).normalized()
	if lamps != null and lamps.has_method(&"knock"):
		for i: int in lamps.get(&"tilt").size():
			lamps.knock(i, from * _dice.randf_range(0.5, 1.1))
	for k in DUST_FALLS:
		var spot := at + Vector3(_dice.randf_range(-DUST_REACH, DUST_REACH), 0.0, _dice.randf_range(-DUST_REACH, DUST_REACH))
		if k == 0:   # (one you'll see: a few metres in front of you)
			var ahead: Vector3 = walker.call(&"facing") if walker != null and walker.has_method(&"facing") else Vector3.FORWARD
			ahead.y = 0.0
			spot = at + ahead.normalized() * _dice.randf_range(2.5, 4.0) + Vector3(_dice.randf_range(-1.0, 1.0), 0.0, 0.0)
		var top := _roof_above(spot)
		if top != Vector3.INF:
			_grit(top)
			if k == 0:   # (you hear the one by you come down)
				WorldSounds.at_soft(self, GRIT, top, -12.0, 9.0, _dice.randf_range(0.9, 1.1))
	if is_inside_tree():
		var boom := AudioStreamPlayer.new()   # (overhead, everywhere in the bunker: through the rock, not from a spot)
		boom.stream = SHELL
		boom.volume_db = SHELL_DB + _dice.randf_range(-3.0, 1.0)
		boom.pitch_scale = _dice.randf_range(0.85, 1.1)
		boom.bus = Hearing.world_bus()
		add_child(boom)
		boom.finished.connect(boom.queue_free)
		boom.play()


## Where the roof is straight above `spot` (from tools/hideout_roof_bake.gd), or INF if there's none.
func _roof_above(spot: Vector3) -> Vector3:
	if roof == null:
		return Vector3.INF
	var local := spot - global_position   # (the hideout's own coordinates: the tests move it)
	var origin: Vector2 = roof.get_meta(&"origin")
	var cell: float = roof.get_meta(&"cell")
	var x := int(floorf((local.x - origin.x) / cell))
	var z := int(floorf((local.z - origin.y) / cell))
	if x < 0 or z < 0 or x >= roof.get_width() or z >= roof.get_height():
		return Vector3.INF
	var heights := roof.get_pixel(x, z)
	for k in 4:
		if heights[k] > local.y + 2.0 and heights[k] < 900.0:   # (the first ceiling over your head)
			return Vector3(spot.x, global_position.y + heights[k] - 0.05, spot.z)
	return Vector3.INF


## A short trickle of grit and a puff of dust off the roof at `at`.
func _grit(at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.045
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.1, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(0.62, 0.58, 0.5, 0.0), Color(0.62, 0.58, 0.5, 0.9),
		Color(0.55, 0.52, 0.46, 0.7), Color(0.55, 0.52, 0.46, 0.0)])
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = 70
	p.lifetime = 3.4
	p.one_shot = true
	p.explosiveness = 0.15
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.color_ramp = ramp
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.5, 0.02, 0.5)
	p.direction = Vector3.DOWN
	p.spread = 8.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0.0, -4.0, 0.0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.6
	add_child(p)
	p.global_position = at
	p.emitting = true
	falls.append(p)
	var haze := CPUParticles3D.new()   # (and a slow cloud of fine dust coming down after it)
	var haze_mesh := BoxMesh.new()
	haze_mesh.size = Vector3.ONE * 0.22
	haze_mesh.material = material
	haze.mesh = haze_mesh
	var haze_ramp := Gradient.new()
	haze_ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	haze_ramp.colors = PackedColorArray([Color(0.7, 0.66, 0.58, 0.0), Color(0.7, 0.66, 0.58, 0.22), Color(0.7, 0.66, 0.58, 0.0)])
	haze.color_ramp = haze_ramp
	haze.amount = 16
	haze.lifetime = 4.5
	haze.one_shot = true
	haze.explosiveness = 0.5
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	haze.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	haze.emission_box_extents = Vector3(0.6, 0.1, 0.6)
	haze.direction = Vector3.DOWN
	haze.spread = 40.0
	haze.initial_velocity_min = 0.2
	haze.initial_velocity_max = 0.6
	haze.gravity = Vector3(0.0, -1.2, 0.0)
	haze.scale_amount_min = 0.7
	haze.scale_amount_max = 2.0
	p.add_child(haze)
	haze.emitting = true
	p.finished.connect(func() -> void:
		falls.erase(p)
		p.queue_free())


## The lights dip and stutter for a moment after a hit (HideoutToys multiplies its ambient light by this).
func _update_flicker(delta: float) -> void:
	if toys == null:
		return
	if _flicker <= 0.0:
		toys.flicker = 1.0
		return
	_flicker = maxf(0.0, _flicker - delta)
	var t := 1.0 - _flicker / FLICKER_TIME          # 0 at the hit, 1 when it's over
	var stutter := 1.0 if _dice.randf() > 0.35 else 0.55
	toys.flicker = lerpf(0.45, 1.0, t * t) * (stutter if t < 0.7 else 1.0)


func _update_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake <= 0.0:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return
	_shake = maxf(0.0, _shake - delta)
	var size := SHAKE * _shake / SHAKE_TIME
	_camera.h_offset = _dice.randf_range(-size, size)
	_camera.v_offset = _dice.randf_range(-size, size)
