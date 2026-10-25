class_name HideoutToys
extends Node3D
## Things to do in the mess and the bunks (0.21.7, owner asked for all four; "fun to just roam around... in call with
## your friend late at night"): a radio you can switch on, the couch and the mess benches to sit on, darts, and a
## light switch for the bunks. Just for fun: nothing here is saved or changes how you play.
## The level (art_source/scripts/make_hideout.py) places them: Level/Seats, Level/Dartboard, Level/Quarters and the
## radio, darts and lights stations.

const RADIO_SONG := preload("res://audio/world/radio.wav")
const RADIO_KNOB := preload("res://audio/world/radio_on.wav")
const SWITCH_CLACK := preload("res://audio/world/switch.wav")
## The level's materials with the bunks' lights switch in them (0.21.16).
const ATLAS_SHADER := preload("res://assets/shaders/hideout_atlas.gdshader")
const DECALS_SHADER := preload("res://assets/shaders/hideout_decals.gdshader")
const DARTS_FOV := 45.0      # zoomed in a little at the line, so the board's easier to see
const SEAT_REACH := 1.5
const SEATED_EYE := 0.72       # how far above the seat your eyes are, sitting
const LIGHTS_FADE := 2.5       # how quickly the bunks go dark (per second)

## Left on (or off) until the game closes, like a real radio.
static var radio_on := false
static var lights_on := true

var walker: HideoutWalker
var environment: Environment
## The seat you're on (its Marker3D) or null; where you stood before sitting down.
var seat: Node3D
var _stood_at := Vector3.ZERO
## Playing darts (standing at the line).
var darts := false
var darts_game: DartsGame
var _radio: AudioStreamPlayer3D
var _area := Rect2()
## 0 = the bunks' lights on, 1 = off (fades).
var _off := 0.0
## The level's materials that go dark in the bunks (hideout_dark.gdshaderinc).
var _level_materials: Array[ShaderMaterial] = []
var _glows: MultiMeshInstance3D
var _tv_light: OmniLight3D
var _bunk_light: OmniLight3D


func setup(level: Node3D, who: HideoutWalker, env: Environment) -> void:
	walker = who
	environment = env
	var board := level.get_node_or_null("Dartboard") as Node3D
	if board != null:
		darts_game = DartsGame.new()
		darts_game.name = "Darts"
		add_child(darts_game)
		darts_game.setup(board, who)
	var quarters := level.get_node_or_null("Quarters") as Node3D
	if quarters != null:
		_area = quarters.get_meta("area")
		_build_radio(quarters.get_meta("radio"))
		_build_dark(quarters)
		_darken_level(level)


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
	return darts and darts_game.handle_input(event)


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
		darts_game.end()
		walker.camera.fov = HideoutWalker.FOV
	_pin(false)


## Holds you still (looking round is still fine), without bumping into the seat you're on.
func _pin(on: bool) -> void:
	walker.pinned = on
	walker.velocity = Vector3.ZERO
	(walker.get_node("CollisionShape3D") as CollisionShape3D).disabled = on and seat != null


# --- Darts (scripts/darts_game.gd) -----------------------------------------------------------

## To the line, facing the board.
func start_darts() -> void:
	if darts_game == null:
		return
	stand_up()
	var spot := get_parent().get_node("Level/Stations/darts") as Node3D
	walker.global_position = Vector3(spot.global_position.x, walker.global_position.y, spot.global_position.z)
	var to := darts_game.board.global_position - walker.global_position
	walker.rotation.y = atan2(-to.x, -to.z)
	darts = true
	walker.camera.fov = DARTS_FOV
	_pin(true)
	darts_game.begin()


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

## With the lights off the bunks go dark (seen from anywhere, 0.21.16), but the fairy lights and the TV stay on.
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


## Gives the level's model materials that darken the bunks (the same look otherwise): the kit atlas and the decals.
func _darken_level(level: Node3D) -> void:
	for mesh: MeshInstance3D in level.find_children("*", "MeshInstance3D", true, false):
		for k in mesh.mesh.get_surface_count():
			var old := mesh.get_active_material(k)
			var material := ShaderMaterial.new()
			if old is ShaderMaterial and (old as ShaderMaterial).shader != null and (old as ShaderMaterial).shader.resource_path.ends_with("kit_atlas.gdshader"):
				material.shader = ATLAS_SHADER
				material.set_shader_parameter("atlas", (old as ShaderMaterial).get_shader_parameter("atlas"))
			elif old is StandardMaterial3D and (old as StandardMaterial3D).vertex_color_use_as_albedo \
					and (old as StandardMaterial3D).albedo_texture != null and (old as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				material.shader = DECALS_SHADER
				material.set_shader_parameter("decals", (old as StandardMaterial3D).albedo_texture)
			else:
				continue
			material.set_shader_parameter("area", Vector4(_area.position.x, _area.position.y, _area.end.x, _area.end.y))
			mesh.set_surface_override_material(k, material)
			_level_materials.append(material)


func switch_lights(on: bool) -> void:
	lights_on = on
	var switch := get_parent().get_node_or_null("Level/Stations/lights") as Node3D
	Effects.sound_at(self, SWITCH_CLACK, switch.global_position + Vector3.UP * 1.3 if switch else walker.global_position,
		-6.0, 0.05, 1.0, 3.0, 20.0)


## The bunks go dark in the level's own materials (0.21.16), so they look dark from wherever you are: before, the whole
## hideout's ambient light dimmed while you stood in the bunks, and walking out turned them back on.
func _update_dark(delta: float) -> void:
	_off = move_toward(_off, 0.0 if lights_on else 1.0, LIGHTS_FADE * delta)
	for material in _level_materials:
		material.set_shader_parameter("lights_off", _off)
	var on := _off > 0.01
	if _glows != null:
		_glows.visible = on
		_tv_light.visible = on
		_bunk_light.visible = on
		var flicker := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.011) * sin(Time.get_ticks_msec() * 0.0037)
		_tv_light.light_energy = _off * 0.9 * flicker
		_bunk_light.light_energy = _off * 0.6
