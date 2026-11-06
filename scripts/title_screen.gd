class_name TitleScreen
extends Node3D
## The main screen (0.21.13, owner: "a main screen when you open the game... play/options/privacy... then when you
## press PLAY you go to the hideout"): the game's name over a slow look round the hideout, and PLAY, OPTIONS,
## PRIVACY, CREDITS (QUIT on a computer build). 0.21.15 (owner picked look A, "Front line"): the town at dusk behind it,
## drifting slowly side to side (a still picture, tools/render_title_bg.gd, so phones don't draw a 3D scene here), with a
## military red PLAY. Red is for this screen only: in the game yellow stays the "active" colour and red means danger. Room is left under PLAY for signing in later (guest, email, Steam).
## The hideout loads in the background while you're here, so PLAY is quick.
## 0.30.8 (owner: "people keep lagging when entering the game, in the hideout, and in raid... I want a way more clean
## experience loading on to the site, getting in to the hideout without any lag"): the screen opens with a loading bar
## where the buttons go, picking up from the web page's bar. Behind it the game builds the raid's and the hideout's
## shaders (ShaderWarm, quick once a browser has built them before) and loads the hideout; the picture holds still.
## Then the buttons fade in and the picture starts drifting, with nothing left to build while you click round.

const HIDEOUT := "res://scenes/hideout_world.tscn"
const BACKGROUND := preload("res://assets/textures/title_dusk.jpg")
## Seconds for the picture to drift from one side to the other (and as long back).
const DRIFT_SECONDS := 25.0   # (0.21.21, owner: a bit faster; was 40)
const ACCENT := Color("b03b2e")   # (PLAY)
const NAME_BLOCK := preload("res://assets/textures/title_text.png")
const BUTTON_FACE := Color(0.13, 0.14, 0.15, 0.92)

## What the privacy page says (docs/STORE_RULES.md: the stores want it reachable in the game). Keep it true: update it
## whenever what the game collects changes.
const PRIVACY := """WHAT BLOXOV KEEPS ABOUT YOU

PvE (solo): your progress (stash, loadout, traders, record, character) and your settings stay on this device. No
account. OPTIONS > SAVE TO FILE gives you a copy of them as a file to keep; it goes only to you.

Online play: the server is sent the name you type and your connection's IP address, which it needs to put you in a
raid. Other players in your raid see that name and your character. The server's log keeps names, IP addresses and
anti-cheat catches for a short time, to keep play fair.

PvP account (only if you make one): your username, your password scrambled so it can't be read back, your PvP stash,
money, loadout, stats, traders and quests, your raid results, and when you last played. No email and no real name.
It's kept in a database hosted by Heroku until you delete it; accounts not used for 12 months are deleted. A ban for
cheating is kept with the account. ONLINE > PvP ACCOUNT > DOWNLOAD MY PvP DATA gives you all of it as a file.

On bloxov.com only: Cloudflare Web Analytics counts visits to the page (which page, browser, country, how fast it
loaded). It uses no cookies and keeps nothing that identifies you. The phone and computer versions don't have it.

No ads, no tracking across other sites or apps, and nothing is sold. The server is hosted by Heroku.

To delete your PvP account: ONLINE > PvP ACCOUNT > DELETE PvP ACCOUNT. It's gone after 30 days (signing in before
then cancels it), and the host's backups may keep a copy a few days more. You can also email contact@bloxov.com, or
see bloxov.com/privacy. To delete your PvE progress: clear this site's data in your browser (or uninstall the game)."""

const CREDITS := """BLOXOV: NO MAN'S LAND

A game by Tavish

Made with the Godot Engine (godotengine.org), MIT licence:
Copyright (c) 2014-present Godot Engine contributors; (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Fonts (SIL Open Font Licence 1.1):
Jersey, by the Soft Type Project Authors (Bloxov Jersey is a modified version)
Silkscreen, by the Silkscreen Project Authors
Pixelify Sans, by the Pixelify Sans Project Authors"""

var _time := 0.0
var _background: TextureRect
## Where the picture's window is now (UV, for the test).
var drift_offset := Vector2.ZERO
var _ui: CanvasLayer
var _main_box: VBoxContainer
## The OPTIONS / PRIVACY / CREDITS (/ QUIT) row under PLAY.
var _row: HBoxContainer
var _poster: CenterContainer
var _page: PanelContainer
var _page_title: Label
var _page_body: VBoxContainer
var _play_button: Button
## The loading bar and its words (until everything's ready), and the hideout once it's loaded.
var _loading_box: VBoxContainer
var _loading_bar: ProgressBar
var _loading_label: Label
var _hideout: PackedScene
## Set once the shaders are built and the hideout is loaded: the buttons are up.
var ready_to_play := false
var _hideout_requested := false


func _ready() -> void:
	get_tree().paused = false
	GameSettings.load_settings()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_drift()
	ShaderWarm.start(get_tree())   # builds the raid's and hideout's shaders behind the loading bar (0.29.5, 0.30.8)
	if DisplayServer.get_name() == "headless":
		ResourceLoader.load_threaded_request(HIDEOUT)
		_hideout_requested = true
		_show_ready(false)
	else:
		_show_loading()


func _process(delta: float) -> void:
	if not ready_to_play:
		_load_step()
		return   # (the picture holds still while loading: frames are uneven then)
	_time += delta
	_drift()


## Shows the loading bar in place of the buttons.
func _show_loading() -> void:
	_play_button.visible = false
	_row.visible = false
	_loading_box.visible = true
	if LoadingScreen.first_setup():
		_loading_label.text = "FIRST-TIME SETUP: GETTING THE GRAPHICS READY"


## One frame of loading: the shaders first (most of the bar), then the hideout.
func _load_step() -> void:
	if not ShaderWarm.is_done():
		_loading_bar.value = ShaderWarm.progress() * 90.0
		return
	LoadingScreen.setup_done()
	if not _hideout_requested:
		_hideout_requested = true
		_loading_bar.value = 90.0
		_loading_label.text = "LOADING THE HIDEOUT"
		if not OS.has_feature("threads"):
			# (the web build has no threads: a background load would run here anyway, so load it in one go, a frame
			# after the words above are on screen)
			_load_hideout_now.call_deferred()
			return
		ResourceLoader.load_threaded_request(HIDEOUT)
		return
	if _hideout != null:
		_show_ready(true)
		return
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(HIDEOUT, progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_loading_bar.value = 90.0 + 10.0 * float(progress[0] if not progress.is_empty() else 0.0)
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		_hideout = ResourceLoader.load_threaded_get(HIDEOUT) as PackedScene
	else:
		_hideout = load(HIDEOUT) as PackedScene


func _load_hideout_now() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_hideout = load(HIDEOUT) as PackedScene


## The buttons come up (fading in after a load).
func _show_ready(fade: bool) -> void:
	ready_to_play = true
	_loading_box.visible = false
	_play_button.visible = true
	_row.visible = true
	if fade:
		for node: CanvasItem in [_play_button, _row]:
			node.modulate.a = 0.0
			create_tween().tween_property(node, "modulate:a", 1.0, 0.4)


## The picture fills the screen's height and slides across what's wider than the screen, easing at each end. It slides
## in a shader (0.21.20, owner: the drift was choppy): a Control moved by itself snaps to whole pixels, so at a few
## pixels a second it stepped.
func _drift() -> void:
	var screen := get_viewport().get_visible_rect().size
	var picture := Vector2(BACKGROUND.get_size())
	var fit := maxf(screen.y / picture.y, screen.x / picture.x)
	var window := screen / (picture * fit)   # (the part of the picture on screen, 0-1)
	var along := 0.5 - 0.5 * cos(_time * PI / DRIFT_SECONDS)
	drift_offset = Vector2((1.0 - window.x) * along, (1.0 - window.y) * 0.5)
	var material := _background.material as ShaderMaterial
	material.set_shader_parameter("window", window)
	material.set_shader_parameter("offset", drift_offset)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _page.visible:
		_show_page("")
		get_viewport().set_input_as_handled()


## Into the hideout.
func play() -> void:
	_play_button.disabled = true
	_play_button.text = "LOADING..."
	var scene := _hideout
	if scene == null and _hideout_requested and OS.has_feature("threads"):
		scene = ResourceLoader.load_threaded_get(HIDEOUT) as PackedScene
	get_tree().change_scene_to_packed(scene if scene != null else load(HIDEOUT) as PackedScene)


# --- The screen -------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	_background = TextureRect.new()
	_background.name = "Background"
	_background.texture = BACKGROUND
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform vec2 window = vec2(1.0);\nuniform vec2 offset = vec2(0.0);\n" \
		+ "void fragment() { COLOR = texture(TEXTURE, offset + UV * window); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	_background.material = material
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_background)
	# 0.27.2 (owner: "use the brag.jpg for like our main screens... i like that picture a lot"): laid out like that poster,
	# the picture darkened warm, the name big in the middle, the red bar, NO MAN'S LAND and the gold line under it, and the
	# buttons below. Drawn live (not the poster itself) so it fits any screen shape.
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.07, 0.03, 0.02, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	_poster = CenterContainer.new()
	_poster.name = "Poster"
	_poster.set_anchors_preset(Control.PRESET_FULL_RECT)
	_poster.offset_bottom = -20
	_ui.add_child(_poster)
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 12)
	_main_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_poster.add_child(_main_box)
	# The name block (0.28.2, owner: the live lettering "looks off"): one picture lettered like the poster by
	# tools/make_web_branding.py at 1080p size, shown at the screen's scale, so its pixels stay even on every screen.
	var name_block := TextureRect.new()
	name_block.name = "Logo"
	name_block.texture = NAME_BLOCK
	name_block.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	name_block.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	name_block.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	name_block.custom_minimum_size = Vector2(NAME_BLOCK.get_size()) * (720.0 / 1080.0)
	name_block.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_box.add_child(name_block)
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 26
	_main_box.add_child(gap2)
	_play_button = _button("PLAY", play, 46, ACCENT)
	_play_button.custom_minimum_size = Vector2(340, 76)
	_play_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# (Signing in, later: guest / email / Steam buttons go here, under PLAY.)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_box.add_child(_row)
	_build_loading_bar()
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
	_page.offset_left = 80
	_page.offset_top = 50
	_page.offset_right = -80
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


## The loading bar (0.30.8), drawn like the web page's (tools/web_seo.py: red on near-black, black edge, grey line).
func _build_loading_bar() -> void:
	_loading_box = VBoxContainer.new()
	_loading_box.name = "Loading"
	_loading_box.visible = false
	_loading_box.add_theme_constant_override("separation", 12)
	_loading_box.custom_minimum_size = Vector2(480, 144)   # (as tall as PLAY and the row under it: nothing moves)
	_loading_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_loading_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_box.add_child(_loading_box)
	_loading_box.get_parent().move_child(_loading_box, _row.get_index())
	_loading_label = Label.new()
	_loading_label.text = "GETTING READY"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.style_label(_loading_label, 24, HudStyle.INK)
	_loading_box.add_child(_loading_label)
	_loading_bar = ProgressBar.new()
	_loading_bar.show_percentage = false
	_loading_bar.custom_minimum_size = Vector2(480, 14)
	_loading_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color("121417")
	back.border_color = Color.BLACK
	back.set_border_width_all(2)
	back.expand_margin_left = 2
	back.expand_margin_right = 2
	back.expand_margin_top = 2
	back.expand_margin_bottom = 2
	back.shadow_color = Color("353a40")
	back.shadow_size = 2
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("d33b2c")
	_loading_bar.add_theme_stylebox_override("background", back)
	_loading_bar.add_theme_stylebox_override("fill", fill)
	_loading_box.add_child(_loading_bar)


func _button(text: String, on_press: Callable, size := 26, color := BUTTON_FACE) -> Button:
	var button := Button.new()
	button.name = text.capitalize().replace(" ", "")
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(190, 56)   # (big enough to tap)
	LootUI.style_button(button, size, color)
	button.pressed.connect(on_press)
	(_main_box if _row == null else _row).add_child(button)
	return button


## Shows page `id` ("options", "privacy", "credits"), or closes it ("").
func _show_page(id: String) -> void:
	_page.visible = id != ""
	_poster.visible = id == ""   # (the page sits where the name and buttons were)
	for child in _page_body.get_children():
		child.queue_free()
	match id:
		"options":
			_page_title.text = "OPTIONS"
			OptionsPage.build(_page_body)
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
