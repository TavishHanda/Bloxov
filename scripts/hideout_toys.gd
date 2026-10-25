class_name HideoutToys
extends Node3D
## Things to do in the mess and the bunks (0.21.7, owner asked for all four; "fun to just roam around... in call with
## your friend late at night"): a radio you can switch on, the couch and the mess benches to sit on, darts, and a
## light switch for the bunks. Just for fun: nothing here is saved or changes how you play.
## The level (art_source/scripts/make_hideout.py) places them: Level/Seats, Level/Dartboard, Level/Quarters and the
## radio, darts and lights stations.

const RADIO_SONG := preload("res://audio/world/radio.wav")
const RADIO_KNOB := preload("res://audio/world/radio_on.wav")
const DART_HIT := preload("res://audio/world/dart.wav")
const SWITCH_CLACK := preload("res://audio/world/switch.wav")
## The board's numbers, clockwise from the top.
const DART_NUMBERS := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
const DARTS_PER_ROUND := 3
## How far a dart lands from where you aim (m, the spread of a normal distribution).
const DART_SPREAD := 0.028
const DART_FLIGHT := 0.18      # seconds from your hand to the board
const DARTS_FOV := 45.0      # zoomed in a little at the line, so the board's easier to see
const SEAT_REACH := 1.5
const SEATED_EYE := 0.72       # how far above the seat your eyes are, sitting
const LIGHTS_ON_ENERGY := 0.9  # (the hideout's ambient light, HideoutWorld._ready)
const LIGHTS_OFF_ENERGY := 0.12
const LIGHTS_FADE := 2.5       # how quickly the bunks go dark (per second)

## Left on (or off) until the game closes, like a real radio.
static var radio_on := false
static var lights_on := true
static var best_round := 0

var walker: HideoutWalker
var environment: Environment
## The seat you're on (its Marker3D) or null; where you stood before sitting down.
var seat: Node3D
var _stood_at := Vector3.ZERO
## Playing darts (standing at the line), this round's darts (each [score, label]) and the darts in the board.
var darts := false
var round_darts: Array = []
var _thrown: Array[Node3D] = []
var _dice := RandomNumberGenerator.new()
var _board: Node3D
var _rings := PackedFloat32Array()
var _radio: AudioStreamPlayer3D
var _area := Rect2()
var _dark := 0.0
var _glows: MultiMeshInstance3D
var _tv_light: OmniLight3D
var _bunk_light: OmniLight3D
var _hud: CanvasLayer
var _darts_label: Label


func setup(level: Node3D, who: HideoutWalker, env: Environment) -> void:
	walker = who
	environment = env
	_board = level.get_node_or_null("Dartboard") as Node3D
	if _board != null:
		_rings = _board.get_meta("rings")
		_paint_numbers()
	var quarters := level.get_node_or_null("Quarters") as Node3D
	if quarters != null:
		_area = quarters.get_meta("area")
		_build_radio(quarters.get_meta("radio"))
		_build_dark(quarters)
	_hud = CanvasLayer.new()
	_hud.layer = 3
	_hud.visible = false
	add_child(_hud)
	_darts_label = Label.new()
	_darts_label.name = "Darts"
	_darts_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_darts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_darts_label.position = Vector2(-300, 14)
	_darts_label.size = Vector2(600, 120)
	HudStyle.style_label(_darts_label, 22)
	_hud.add_child(_darts_label)


## Sitting or playing darts: the hideout's own prompts and USE wait until you get up.
func busy() -> bool:
	return seat != null or darts


## What the world does with a station's use: true if it's one of these.
func use(id: String) -> bool:
	match id:
		"radio":
			switch_radio(not radio_on)
		"lights":
			switch_lights(not lights_on)
		"darts":
			start_darts()
		_:
			return false
	return true


## Keys while sitting or playing: the use key, jump or Esc gets you up; a click throws a dart. True if used.
func handle_input(event: InputEvent) -> bool:
	if not busy():
		return false
	if event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("ui_cancel"):
		stand_up()
		return true
	if darts and event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or GameSettings.is_phone()):
		throw_dart()
		return true
	return false


func _process(delta: float) -> void:
	if busy() and Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.5:
		stand_up()   # (walking off)
	_update_dark(delta)


# --- Sitting ---------------------------------------------------------------------------------

## The seat you're next to and looking roughly at, or null.
func seat_in_reach() -> Node3D:
	var level := get_parent().get_node_or_null("Level")
	if level == null or not level.has_node("Seats") or busy():
		return null
	var best: Node3D = null
	var best_d := SEAT_REACH
	for node: Node in level.get_node("Seats").get_children():
		var marker := node as Node3D
		var to := marker.global_position - walker.global_position
		to.y = 0.0
		var d := to.length()
		if d < best_d and (d < 0.5 or walker.facing().dot(to / d) > 0.3):
			best = marker
			best_d = d
	return best


func sit(on: Node3D) -> void:
	stand_up()
	seat = on
	_stood_at = walker.global_position
	_pin(true)
	walker.global_position = on.global_position + Vector3.DOWN * (HideoutWalker.EYE_HEIGHT - SEATED_EYE)
	walker.rotation.y = on.global_rotation.y
	walker.look(0.0, 0.0)


## Back on your feet (from a seat or the darts line).
func stand_up() -> void:
	if seat != null:
		walker.global_position = _stood_at
		seat = null
	if darts:
		darts = false
		_hud.visible = false
		walker.camera.fov = HideoutWalker.FOV
	_pin(false)


## Holds you still (looking round is still fine), without bumping into the seat you're on.
func _pin(on: bool) -> void:
	walker.pinned = on
	walker.velocity = Vector3.ZERO
	(walker.get_node("CollisionShape3D") as CollisionShape3D).disabled = on and seat != null


# --- Darts -----------------------------------------------------------------------------------

## To the line, facing the board.
func start_darts() -> void:
	if _board == null:
		return
	stand_up()
	var spot := get_parent().get_node("Level/Stations/darts") as Node3D
	walker.global_position = Vector3(spot.global_position.x, walker.global_position.y, spot.global_position.z)
	var to := _board.global_position - walker.global_position
	walker.rotation.y = atan2(-to.x, -to.z)
	darts = true
	walker.camera.fov = DARTS_FOV
	_pin(true)
	_hud.visible = true
	if round_darts.size() >= DARTS_PER_ROUND:
		_new_round()
	_show_darts()


## Throws where you're looking (a little off, like a real throw); a fourth click pulls the darts out for a new round.
func throw_dart() -> void:
	if round_darts.size() >= DARTS_PER_ROUND:
		_new_round()
		_show_darts()
		return
	var camera := walker.camera
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var normal := _board.global_basis.z
	var into := dir.dot(-normal)
	var hit: Vector3
	var landed := false
	if into > 0.05:
		hit = from + dir * ((_board.global_position - from).dot(normal) / dir.dot(normal))
		hit += _board.global_basis.x * _dice.randfn(0.0, DART_SPREAD) + _board.global_basis.y * _dice.randfn(0.0, DART_SPREAD)
		landed = hit.distance_to(_board.global_position) < 1.2
	if not landed:   # (nowhere near: it drops under the board)
		hit = _board.global_position + normal * 0.25 + Vector3.DOWN * (_board.global_position.y - 0.02)
	var local := _board.to_local(hit)
	var result := score_at(Vector2(local.x, local.y), _rings) if landed else [0, "MISS"]
	round_darts.append(result)
	_fly_dart(from + dir * 0.3, hit, landed)
	if round_darts.size() == DARTS_PER_ROUND:
		best_round = maxi(best_round, round_total())
	_show_darts()


## Score and label (e.g. [60, "T20"]) for a dart at `at` (m on the board's face from its middle, y up).
static func score_at(at: Vector2, rings: PackedFloat32Array) -> Array:
	var r := at.length()
	if r <= rings[0]:
		return [50, "BULL"]
	if r <= rings[1]:
		return [25, "25"]
	if r > rings[5]:
		return [0, "MISS"]
	var wedge := int(fposmod(rad_to_deg(atan2(at.x, at.y)) + 9.0, 360.0) / 18.0) % 20
	var number: int = DART_NUMBERS[wedge]
	if r > rings[2] and r <= rings[3]:
		return [number * 3, "T%d" % number]
	if r > rings[4]:
		return [number * 2, "D%d" % number]
	return [number, str(number)]


func round_total() -> int:
	var total := 0
	for result: Array in round_darts:
		total += int(result[0])
	return total


func _new_round() -> void:
	round_darts.clear()
	for dart in _thrown:
		dart.queue_free()
	_thrown.clear()


func _show_darts() -> void:
	var line := ""
	for k in DARTS_PER_ROUND:
		line += ("   " if k > 0 else "") + (String(round_darts[k][1]) if k < round_darts.size() else "-")
	var next := "Click: pull the darts out" if round_darts.size() >= DARTS_PER_ROUND else "Click: throw"
	_darts_label.text = "DARTS    %s    %s: stop\n%s    =  %d\nBEST ROUND  %d" % [next, HideoutWorld.use_key(), line,
		round_total(), best_round]


func _fly_dart(from: Vector3, to: Vector3, landed: bool) -> void:
	var dart := _dart_mesh()
	add_child(dart)
	_thrown.append(dart)
	var point := (_board.global_basis.z * -1.0).rotated(Vector3.UP, _dice.randf_range(-0.12, 0.12))
	dart.global_position = from
	dart.look_at(from + point, Vector3.UP)
	var tween := create_tween()
	tween.tween_property(dart, "global_position", to + point * 0.02, DART_FLIGHT)
	if landed:
		tween.tween_callback(func() -> void: Effects.sound_at(self, DART_HIT, to, -4.0, 0.1, 1.0, 3.0, 25.0))
	else:
		tween.tween_callback(func() -> void: dart.rotation.x = -PI / 2.2)


static func _dart_mesh() -> Node3D:
	var dart := Node3D.new()
	dart.name = "Dart"
	for part: Array in [[Vector3(0.008, 0.008, 0.11), Vector3(0, 0, 0.05), Color(0.2, 0.2, 0.22)],
			[Vector3(0.002, 0.03, 0.035), Vector3(0, 0, 0.11), Color(0.75, 0.15, 0.12)],
			[Vector3(0.03, 0.002, 0.035), Vector3(0, 0, 0.11), Color(0.75, 0.15, 0.12)]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mesh.mesh = box
		mesh.position = part[1]
		mesh.material_override = Effects.unshaded(part[2])
		dart.add_child(mesh)
	return dart


## The numbers round the board (white, like the wire ring on a real one).
func _paint_numbers() -> void:
	for k in DART_NUMBERS.size():
		var label := Label3D.new()
		label.text = str(DART_NUMBERS[k])
		label.font = HudStyle.font(24)
		label.font_size = 24
		label.pixel_size = 0.0018
		label.modulate = Color(0.95, 0.93, 0.85)
		label.shaded = false
		label.double_sided = false
		var angle := deg_to_rad(k * 18.0)
		var radius := (_rings[5] + _rings[6]) / 2.0
		label.position = Vector3(sin(angle) * radius, cos(angle) * radius, 0.004)
		_board.add_child(label)


# --- The radio -------------------------------------------------------------------------------

func _build_radio(at: Vector3) -> void:
	_radio = AudioStreamPlayer3D.new()
	_radio.name = "Radio"
	_radio.stream = Ambience.looped(RADIO_SONG)
	_radio.volume_db = -8.0
	_radio.unit_size = 2.5
	_radio.max_distance = 22.0
	_radio.bus = Hearing.world_bus()
	add_child(_radio)
	_radio.global_position = at
	if radio_on:
		_radio.play()


func switch_radio(on: bool) -> void:
	radio_on = on
	if _radio == null:
		return
	Effects.sound_at(self, RADIO_KNOB, _radio.global_position, -10.0, 0.05, 1.0, 3.0, 20.0)
	if on:
		_radio.play()
	else:
		_radio.stop()


func radio_playing() -> bool:
	return _radio != null and _radio.playing


# --- The bunks' lights -----------------------------------------------------------------------

## With the lights off the bunks go dark, but the fairy lights and the TV stay on.
func _build_dark(quarters: Node3D) -> void:
	var points: PackedVector3Array = quarters.get_meta("glows")
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	var bulb := BoxMesh.new()
	bulb.size = Vector3(0.08, 0.1, 0.08)
	multi.mesh = bulb
	multi.instance_count = points.size()
	for k in points.size():
		multi.set_instance_transform(k, Transform3D(Basis(), points[k] + Vector3.UP * 0.09))   # (the bulb, over its light)
	_glows = MultiMeshInstance3D.new()
	_glows.name = "FairyLights"
	_glows.multimesh = multi
	_glows.material_override = Effects.unshaded(Color(1.0, 0.86, 0.6))
	_glows.visible = false
	add_child(_glows)
	var tv: Vector3 = quarters.get_meta("tv")
	var screen := MeshInstance3D.new()
	screen.name = "TVScreen"
	var quad := BoxMesh.new()
	quad.size = Vector3(0.012, 0.42, 0.56)
	screen.mesh = quad
	screen.material_override = Effects.unshaded(Color(0.45, 0.6, 0.85))
	screen.position = tv
	_glows.add_child(screen)
	_tv_light = _omni(tv + Vector3(0.5, 0.0, 0.0), Color(0.5, 0.65, 1.0), 4.5)
	var middle := Vector3.ZERO
	for p in points:
		middle += p
	_bunk_light = _omni(middle / maxf(1.0, points.size()) + Vector3.DOWN * 0.4, Color(1.0, 0.8, 0.55), 7.0)


func _omni(at: Vector3, color: Color, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = reach
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	light.position = at
	return light


func switch_lights(on: bool) -> void:
	lights_on = on
	var switch := get_parent().get_node_or_null("Level/Stations/lights") as Node3D
	Effects.sound_at(self, SWITCH_CLACK, switch.global_position + Vector3.UP * 1.3 if switch else walker.global_position,
		-6.0, 0.05, 1.0, 3.0, 20.0)


## How dark it is where you are now (0 = lit, 1 = the bunks with the lights off): fades as you walk in and out.
func darkness_wanted() -> float:
	if lights_on or _area.size == Vector2.ZERO:
		return 0.0
	var at := Vector2(walker.global_position.x, walker.global_position.z)
	if at.x < _area.position.x - 0.5 or at.x > _area.end.x + 0.5:
		return 0.0
	return clampf((at.y - _area.position.y + 2.0) / 3.0, 0.0, 1.0)


func _update_dark(delta: float) -> void:
	if environment == null:
		return
	_dark = move_toward(_dark, darkness_wanted(), LIGHTS_FADE * delta)
	environment.ambient_light_energy = lerpf(LIGHTS_ON_ENERGY, LIGHTS_OFF_ENERGY, _dark)
	var on := _dark > 0.01
	if _glows != null:
		_glows.visible = on
		_tv_light.visible = on
		_bunk_light.visible = on
		var flicker := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.011) * sin(Time.get_ticks_msec() * 0.0037)
		_tv_light.light_energy = _dark * 0.9 * flicker
		_bunk_light.light_energy = _dark * 0.6
