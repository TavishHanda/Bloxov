extends Node3D
## The walkable hideout (0.21.0): where the game starts and where you come back to after a raid. A cave the PMCs
## dug tunnels off (art_source/scripts/make_hideout.py builds it): walk up to a trader's counter, the stash, the
## wardrobe or the war table and press E (or tap USE) to open the hideout menu there. Tab or the MENU button opens
## the menu (today's hideout screen: stash, loadout, traders, START RAID, online party) from anywhere.
## Phones open straight on the menu until the touch controls (moving with a stick) exist.

const LEVEL := preload("res://scenes/hideout/hideout_level.tscn")
const MENU := preload("res://scenes/hideout.tscn")
## What each station is called on the USE prompt (traders take their names from Traders.LIST).
const STATION_NAMES := {"stash": "Stash", "wardrobe": "Wardrobe", "workbench": "Workbench", "war_table": "War table",
	"quests": "Quests", "stats": "Stats", "range": "Shooting range"}
## Stations with nothing of their own yet: what the menu says when you use them.
const STATION_NOTES := {"wardrobe": "Characters come with the character update. For now: your loadout is on the left.",
	"workbench": "Crafting comes in a later update.",
	"war_table": "Pick your loadout, then START RAID (or go online and queue with your party).",
	"quests": "Quests are under each trader: pick a trader on the right.",
	"range": "The shooting range opens in the next update."}

var walker: HideoutWalker
## Today's hideout screen, kept the whole time (hidden while you walk round).
var menu: Control
var _menu_layer: CanvasLayer
var _hud: CanvasLayer
var _prompt: Label
var _use_button: Button
var _menu_button: Button
var _crosshair: Control
var _click_hint: Label
## The station in reach (its Marker3D) or null.
var station: Node3D


func _ready() -> void:
	get_tree().paused = false
	var level: Node3D = LEVEL.instantiate()
	level.name = "Level"
	add_child(level)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.86, 0.68)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	walker = HideoutWalker.new()
	walker.name = "Walker"
	add_child(walker)
	walker.global_position = (level.get_node("Spawn") as Node3D).global_position + Vector3.UP * 0.05
	_build_hud()
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 5
	add_child(_menu_layer)
	menu = MENU.instantiate()
	_menu_layer.add_child(menu)
	var back := Button.new()
	back.name = "BackToHideout"
	back.text = "BACK TO HIDEOUT  (Tab)"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(260, 52)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.position = Vector2(12, -64)
	back.grow_vertical = Control.GROW_DIRECTION_BEGIN
	LootUI.style_button(back)
	back.pressed.connect(close_menu)
	_menu_layer.add_child(back)
	back.visible = not GameSettings.is_phone()
	# Online (back from a raid with your party) or on a phone: start on the menu.
	if Network.main.is_client() or GameSettings.is_phone():
		open_menu()
	else:
		close_menu()


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 2
	add_child(_hud)
	_crosshair = ColorRect.new()
	(_crosshair as ColorRect).color = Color(1, 1, 1, 0.7)
	_crosshair.size = Vector2(4, 4)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.position = Vector2(-2, -2)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_crosshair)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(-300, -150)
	_prompt.size = Vector2(600, 40)
	HudStyle.style_label(_prompt, 24)
	_hud.add_child(_prompt)
	_click_hint = Label.new()
	_click_hint.text = "Click to look around"
	_click_hint.set_anchors_preset(Control.PRESET_CENTER)
	_click_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_click_hint.position = Vector2(-200, 30)
	_click_hint.size = Vector2(400, 30)
	HudStyle.style_label(_click_hint, 20)
	_hud.add_child(_click_hint)
	# Big buttons for touch screens (and the mouse): MENU always, USE when something is in reach.
	_menu_button = Button.new()
	_menu_button.name = "MenuButton"
	_menu_button.text = "MENU  (Tab)"
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.custom_minimum_size = Vector2(170, 56)
	_menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu_button.position = Vector2(-182, 12)
	LootUI.style_button(_menu_button)
	_menu_button.pressed.connect(open_menu)
	_hud.add_child(_menu_button)
	_use_button = Button.new()
	_use_button.name = "UseButton"
	_use_button.text = "USE  (E)"
	_use_button.focus_mode = Control.FOCUS_NONE
	_use_button.custom_minimum_size = Vector2(170, 72)
	_use_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_use_button.position = Vector2(-194, -96)
	LootUI.style_button(_use_button)
	_use_button.pressed.connect(use_station)
	_hud.add_child(_use_button)


func _process(_delta: float) -> void:
	# Another tab already plays: the menu shows the notice (TabLock) over everything.
	if TabLock.state() != "owner" and not menu_open():
		open_menu()
	station = _station_in_reach() if not menu_open() else null
	_use_button.visible = station != null
	_prompt.visible = station != null
	if station != null:
		_prompt.text = "E   " + station_name(station.name)
	_click_hint.visible = not menu_open() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not GameSettings.is_phone()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if menu_open():
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not menu_open():
		open_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and station != null:
		use_station()
		get_viewport().set_input_as_handled()


func menu_open() -> bool:
	return _menu_layer.visible


## Opens the hideout menu, on `at`'s tab if it's a trader.
func open_menu(at := "") -> void:
	_menu_layer.visible = true
	menu.visible = true
	_hud.visible = false
	walker.locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Traders.LIST.has(at):
		menu.open_trader(at)
	if STATION_NOTES.has(at):
		menu.show_message(STATION_NOTES[at])


## Back to walking round.
func close_menu() -> void:
	if GameSettings.is_phone() or TabLock.state() != "owner":
		return
	_menu_layer.visible = false
	_hud.visible = true
	walker.locked = false
	menu.save_now()


func use_station() -> void:
	if station != null:
		open_menu(station.name)


func station_name(id: String) -> String:
	if Traders.LIST.has(id):
		return String(Traders.LIST[id]["name"])
	return String(STATION_NAMES.get(id, id.capitalize()))


## The nearest station you're within reach of and roughly facing.
func _station_in_reach() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var at := walker.global_position
	for node: Node in $Level/Stations.get_children():
		var marker := node as Node3D
		var to := marker.global_position - at
		to.y = 0.0
		var d := to.length()
		if d > float(marker.get_meta("reach", 2.5)) or d >= best_d:
			continue
		if d > 0.8 and walker.facing().dot(to / d) < 0.2:
			continue
		best = marker
		best_d = d
	return best
