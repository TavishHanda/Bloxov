class_name TitleScreen
extends Node3D
## The main screen (0.21.13, owner: "a main screen when you open the game... play/options/privacy... then when you
## press PLAY you go to the hideout"): the game's name over a slow look round the hideout, and PLAY, OPTIONS,
## PRIVACY, CREDITS (QUIT on a computer build). Room is left under PLAY for signing in later (guest, email, Steam).
## The hideout loads in the background while you're here, so PLAY is quick.

const LEVEL := preload("res://scenes/hideout/hideout_level.tscn")
const HIDEOUT := "res://scenes/hideout_world.tscn"
## The slow camera: round the war table at this radius and height, looking at the middle of the hall.
const ORBIT_CENTER := Vector3(0, 1.4, -1.5)
const ORBIT_RADIUS := 8.5
const ORBIT_HEIGHT := 3.2
const ORBIT_SPEED := 0.035   # radians a second

## What the privacy page says (docs/STORE_RULES.md: the stores want it reachable in the game). Keep it true: update it
## whenever what the game collects changes.
const PRIVACY := """WHAT BLOXOV KEEPS ABOUT YOU

On this device: your progress (stash, loadout, traders, record, character) and your settings. They never leave the
device unless you play online.

Online play: the server is sent the name you type and your connection's IP address, which it needs to put you in a
raid. Other players in your raid see your name and character. Nothing is kept after the raid, apart from the
server's short log.

No accounts, no ads, no analytics, no tracking, and nothing is sold or shared. The server is hosted by Heroku.

To delete everything: clear this site's data in your browser (or uninstall the game)."""

const CREDITS := """BLOXOV: NO MAN'S LAND

A game by Tavish

Made with the Godot Engine (godotengine.org), MIT licence:
Copyright (c) 2014-present Godot Engine contributors; (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Fonts (SIL Open Font Licence 1.1):
Jersey, by the Soft Type Project Authors (Bloxov Jersey is a modified version)
Silkscreen, by the Silkscreen Project Authors
Pixelify Sans, by the Pixelify Sans Project Authors"""

var camera: Camera3D
var _angle := 0.6
var _ui: CanvasLayer
var _main_box: VBoxContainer
var _page: PanelContainer
var _page_title: Label
var _page_body: VBoxContainer
var _play_button: Button


func _ready() -> void:
	get_tree().paused = false
	GameSettings.load_settings()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var level: Node3D = LEVEL.instantiate()
	level.name = "Level"
	add_child(level)
	var env := Environment.new()   # (the hideout's own light, HideoutWorld._ready)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.86, 0.68)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	camera = Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	camera.current = true
	_move_camera()
	_build_ui()
	ResourceLoader.load_threaded_request(HIDEOUT)


func _process(delta: float) -> void:
	_angle += ORBIT_SPEED * delta
	_move_camera()


func _move_camera() -> void:
	var at := ORBIT_CENTER + Vector3(sin(_angle) * ORBIT_RADIUS, ORBIT_HEIGHT - ORBIT_CENTER.y, cos(_angle) * ORBIT_RADIUS)
	camera.look_at_from_position(at, ORBIT_CENTER)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _page.visible:
		_show_page("")
		get_viewport().set_input_as_handled()


## Into the hideout.
func play() -> void:
	_play_button.disabled = true
	_play_button.text = "LOADING..."
	var scene := ResourceLoader.load_threaded_get(HIDEOUT) as PackedScene
	get_tree().change_scene_to_packed(scene if scene != null else load(HIDEOUT) as PackedScene)


# --- The screen -------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var shade := ColorRect.new()   # (darker on the left, under the buttons)
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 460
	shade.color = Color(0, 0, 0, 0.45)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	margin.offset_right = 520
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_top", 168)
	margin.add_theme_constant_override("margin_bottom", 40)
	_ui.add_child(margin)
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 12)
	margin.add_child(_main_box)
	# The name, the pixel font drawn three times over (its pixels stay square), outside the list so it can be big.
	var logo := Label.new()
	logo.name = "Logo"
	logo.text = "BLOXOV"
	HudStyle.style_label(logo, 50)
	logo.position = Vector2(54, 40)
	logo.scale = Vector2(3, 3)
	_ui.add_child(logo)
	var subtitle := Label.new()
	subtitle.text = "NO MAN'S LAND"
	HudStyle.style_label(subtitle, 30, HudStyle.BRASS)
	subtitle.add_theme_font_override("font", HudStyle.spaced_font(30))
	_main_box.add_child(subtitle)
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 24
	_main_box.add_child(gap2)
	_play_button = _button("PLAY", play, 50, HudStyle.HAZARD)
	_play_button.custom_minimum_size = Vector2(340, 84)
	# (Signing in, later: guest / email / Steam buttons go here, under PLAY.)
	_button("OPTIONS", func() -> void: _show_page("options"))
	_button("PRIVACY", func() -> void: _show_page("privacy"))
	_button("CREDITS", func() -> void: _show_page("credits"))
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		_button("QUIT", func() -> void: get_tree().quit())
	var version := Label.new()
	version.name = "Version"
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	HudStyle.style_label(version, 20, Color(HudStyle.INK, 0.45))
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -12
	version.offset_bottom = -8
	_ui.add_child(version)
	# A page for options, privacy and credits, on the right.
	_page = PanelContainer.new()
	_page.name = "Page"
	LootUI.skin_panel(_page)
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page.offset_left = 560
	_page.offset_top = 60
	_page.offset_right = -40
	_page.offset_bottom = -50
	_page.visible = false
	_ui.add_child(_page)
	var page_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		page_margin.add_theme_constant_override("margin_" + side, 20)
	_page.add_child(page_margin)
	var page_box := VBoxContainer.new()
	page_box.add_theme_constant_override("separation", 14)
	page_margin.add_child(page_box)
	var head := HBoxContainer.new()
	page_box.add_child(head)
	_page_title = Label.new()
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudStyle.style_label(_page_title, 40)
	head.add_child(_page_title)
	var close := Button.new()
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(120, 44)
	LootUI.style_button(close, 20)
	close.pressed.connect(func() -> void: _show_page(""))
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_box.add_child(scroll)
	_page_body = VBoxContainer.new()
	_page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_body.add_theme_constant_override("separation", 14)
	scroll.add_child(_page_body)


func _button(text: String, on_press: Callable, size := 30, color := Color(0, 0, 0, 0)) -> Button:
	var button := Button.new()
	button.name = text.capitalize().replace(" ", "")
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(340, 60)   # (big enough to tap)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if color.a > 0.0:
		LootUI.style_button(button, size, color)
	else:
		LootUI.style_button(button, size)
	button.pressed.connect(on_press)
	_main_box.add_child(button)
	return button


## Shows page `id` ("options", "privacy", "credits"), or closes it ("").
func _show_page(id: String) -> void:
	_page.visible = id != ""
	for child in _page_body.get_children():
		child.queue_free()
	match id:
		"options":
			_page_title.text = "OPTIONS"
			_build_options()
		"privacy":
			_page_title.text = "PRIVACY"
			_text(PRIVACY)
		"credits":
			_page_title.text = "CREDITS"
			_text(CREDITS)


func page_open() -> String:
	return _page_title.text.to_lower() if _page.visible else ""


func _text(text: String) -> void:
	var label := Label.new()
	label.text = text.replace("\n\n", " ").replace("\n", " ").replace(" ", "\n\n")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudStyle.style_label(label, 20)
	label.add_theme_font_override("font", HudStyle.spaced_font(20))
	_page_body.add_child(label)


# --- Options (the same settings as the raid's menu, saved the same way) -----------------------

func _build_options() -> void:
	_slider("Volume", GameSettings.volume, 0.0, 1.0, func(v: float) -> void: GameSettings.set_volume(v), "%d%%", 100.0)
	for key: String in GameSettings.MIX_NAMES:
		_slider(GameSettings.MIX_NAMES[key], float(GameSettings.mix[key]), 0.0, 1.0,
			func(v: float) -> void: GameSettings.set_mix(key, v), "%d%%", 100.0)
	_slider("Mouse sensitivity", GameSettings.sensitivity, 0.1, 3.0, func(v: float) -> void: GameSettings.set_sensitivity(v), "%.2fx", 1.0)
	var row := _row("Graphics")
	for quality in GameSettings.GRAPHICS_NAMES.size():
		var button := Button.new()
		button.text = String(GameSettings.GRAPHICS_NAMES[quality]).to_upper()
		button.toggle_mode = true
		button.button_pressed = GameSettings.graphics == quality
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(110, 44)
		LootUI.style_button(button, 20)
		button.pressed.connect(func() -> void:
			GameSettings.set_graphics(quality)
			for other: Node in row.get_children():
				if other is Button:
					(other as Button).button_pressed = other == button)
		row.add_child(button)
	_toggle("Damage numbers", GameSettings.damage_numbers, func(on: bool) -> void: GameSettings.set_damage_numbers(on))
	_toggle("Lean: tap to toggle (off: hold)", GameSettings.lean_toggle, func(on: bool) -> void: GameSettings.set_lean_toggle(on))


func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 260
	HudStyle.style_label(label, 20)
	row.add_child(label)
	_page_body.add_child(row)
	return row


func _slider(title: String, value: float, low: float, high: float, on_change: Callable, shown: String, show_scale: float) -> void:
	var row := _row(title)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(260, 44)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var readout := Label.new()
	HudStyle.style_label(readout, 20)
	readout.text = shown % (value * show_scale)
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		readout.text = shown % (v * show_scale))


func _toggle(title: String, on: bool, on_change: Callable) -> void:
	var row := _row(title)
	var box := CheckButton.new()
	box.button_pressed = on
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(on_change)
	row.add_child(box)
