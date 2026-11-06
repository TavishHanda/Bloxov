class_name LoadingScreen
extends Control
## The loading screen (Look update 0.19.3, owner picked look B "map vista"): a shot of the map with the late
## afternoon look, the map's name, a random tip and ENTERING THE RAID. The hideout puts it up when START RAID is
## pressed; the web build can't draw while the raid loads, so it's a still picture, not a moving bar. The raid then
## puts the same screen (same tip) over its first second, while it settles (shaders, the AI's map), and fades it out.
## The picture is `tools/render_views.gd`'s "town" view with the current look, saved as a .jpg.

const PICTURE := "res://assets/textures/loading_battlegrounds.jpg"
const MAP_NAME := "Bloxov Frontlines"
## How long the raid keeps it up at least (seconds, counted once the raid is drawing) and how long the fade takes.
const HOLD := 0.8
const FADE := 0.5
## (0.30.8) It then stays up until the game is drawing smoothly (SETTLE_FRAMES frames in a row, none a hitch), but
## never longer than SETTLE_MAX seconds. A hitch is a frame over SPIKE_MS and well over the usual frame.
const SETTLE_FRAMES := 12
const SETTLE_MAX := 8.0
const SPIKE_MS := 45.0
## The hideout's curtain (0.30.8): the title picture, darkened, over its first frames.
const CURTAIN_PICTURE := "res://assets/textures/title_dusk.jpg"
const CURTAIN_FADE := 0.35
## Gameplay tips (true for desktop and phones alike: no keys named).
const TIPS := [
	"Crouch-walking is quiet: scavs hear sprinting footsteps from much farther away.",
	"Crouching or standing still makes you harder for scavs to spot.",
	"An extract only works while it's open. Check the map for yours before the timer runs out.",
	"Searching containers takes time. Listen out while you loot.",
	"Items found in raid can be handed in for quests at the traders.",
	"Kills only count for quests if you make it out alive.",
	"Low walls, sandbags and crates can be vaulted. Jump at them.",
	"Lean round corners to shoot while showing less of yourself.",
	"Some doors need keys. The bunker and the bank vault hide the best loot.",
	"Bandages stop bleeding. Heal up in cover before you push.",
]

## The browser key remembering which Godot version this browser has built the raid's shaders for (0.29.5): until
## then the first raid takes long, so the loading screen says it's a one-time setup instead of looking stuck.
const SETUP_KEY := "bloxov_shaders_built"

## The tip picked for this load, so the raid shows the same one the hideout did.
static var tip := ""

## Set on the raid's copy: fade out (and free its layer) once the raid has settled.
var fades := false


## A new loading screen (picks a new tip).
static func make() -> LoadingScreen:
	tip = TIPS.pick_random()
	var screen := LoadingScreen.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	return screen


## Puts the loading screen over `raid` (a raid scene being made) and fades it once the raid has settled.
## Not on servers or headless runs.
static func cover(raid: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.name = "LoadingCover"
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS   # (the HUD pauses the raid until the mouse is captured)
	var screen := make() if tip == "" else _again()
	screen.fades = true
	layer.add_child(screen)
	raid.add_child(layer)


static func _again() -> LoadingScreen:
	var keep := tip
	var screen := make()
	tip = keep
	return screen


func _ready() -> void:
	var picture := TextureRect.new()
	picture.texture = load(PICTURE)
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(picture)
	# Dark from the middle down, so the words read on any picture.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([Color(0.04, 0.04, 0.05, 0.0), Color(0.04, 0.04, 0.05, 0.0), Color(0.04, 0.04, 0.05, 0.92)])
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = gradient
	shade_texture.fill_from = Vector2(0, 0)
	shade_texture.fill_to = Vector2(0, 1)
	shade.texture = shade_texture
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = MAP_NAME.to_upper()
	HudStyle.style_label(title, 50)
	column.add_child(title)
	var bar := ColorRect.new()
	bar.color = HudStyle.BRASS
	bar.custom_minimum_size = Vector2(380, 5)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(bar)
	var tip_label := Label.new()
	tip_label.text = "TIP: " + tip
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.style_label(tip_label, 22, HudStyle.INK, false)
	tip_label.add_theme_font_override("font", HudStyle.tape_font())
	column.add_child(tip_label)
	if first_setup():
		var setup := Label.new()
		setup.text = "FIRST-TIME SETUP: GETTING THE GRAPHICS READY. ONLY SLOW THE FIRST TIME."
		setup.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		setup.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HudStyle.style_label(setup, 18, HudStyle.INK, false)
		column.add_child(setup)
	var entering := Label.new()
	entering.text = "ENTERING THE RAID..."
	entering.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	HudStyle.style_label(entering, 30, HudStyle.BRASS)
	column.add_child(entering)
	if fades:
		_fade_out()


## Waits for the raid to settle (HOLD seconds of drawing), then fades out and frees its layer.
func _fade_out() -> void:
	var tree := get_tree()
	await settle(tree, HOLD)
	setup_done()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE)
	await tween.finished
	tip = ""
	get_parent().queue_free()


## Waits until the game is drawing smoothly (0.30.8, owner: people lagged just after getting in): at least `at_least`
## seconds of frames, then SETTLE_FRAMES frames in a row with no hitch (a shader being built, things being set up),
## at most SETTLE_MAX seconds. A slow machine's frames are all slow, so a hitch is measured against the usual frame.
static func settle(tree: SceneTree, at_least := 0.0) -> void:
	for i in 3:   # (the first frames after a load take long; start the clock once frames are coming)
		await tree.process_frame
	var start := Time.get_ticks_usec()
	var last := start
	var smooth := 0
	var recent: Array[float] = []
	while true:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		var usual := ms
		if not recent.is_empty():
			var sorted := recent.duplicate()
			sorted.sort()
			usual = sorted[sorted.size() / 2]
		recent.append(ms)
		if recent.size() > 20:
			recent.pop_front()
		smooth = smooth + 1 if ms < maxf(SPIKE_MS, usual * 1.6) else 0
		var waited := (now - start) / 1e6
		if (smooth >= SETTLE_FRAMES and waited >= at_least) or waited >= SETTLE_MAX:
			return


## Puts the title picture over `scene` (the hideout, as you walk in) until it draws smoothly, then fades it out.
## Not on servers or headless runs.
static func curtain(scene: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.name = "Curtain"
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var picture := TextureRect.new()
	picture.texture = load(CURTAIN_PICTURE)
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_STOP
	picture.modulate = Color(0.45, 0.4, 0.38)   # (as dark as the title screen's shade)
	layer.add_child(picture)
	scene.add_child(layer)
	_lift.call_deferred(layer, picture)


static func _lift(layer: CanvasLayer, picture: TextureRect) -> void:
	if not is_instance_valid(layer) or not layer.is_inside_tree():
		return
	await settle(layer.get_tree())
	if not is_instance_valid(layer):
		return
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := layer.create_tween()
	tween.tween_property(picture, "modulate:a", 0.0, CURTAIN_FADE)
	tween.tween_callback(layer.queue_free)


## True in a browser that hasn't loaded a raid on this Godot version yet (its shaders aren't built and kept yet).
static func first_setup() -> bool:
	if not OS.has_feature("web"):
		return false
	var seen = JavaScriptBridge.eval("(function () { try { return localStorage.getItem('%s') || '' } catch (e) { return '' } })()" % SETUP_KEY, true)
	return str(seen) != _engine_version()


static func setup_done() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.setItem('%s', '%s') } catch (e) {}" % [SETUP_KEY, _engine_version()], true)


static func _engine_version() -> String:
	return Engine.get_version_info().string
