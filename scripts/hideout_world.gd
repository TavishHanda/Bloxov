class_name HideoutWorld
extends Node3D
## The walkable hideout (0.21.0): where the game starts and where you come back to after a raid. A cave the PMCs
## dug tunnels off (art_source/scripts/make_hideout.py builds it): walk up to a trader's counter, the stash, the
## wardrobe or the war table and press the use key, F (or tap USE) to open the hideout menu there. Tab or the MENU button opens
## the menu (today's hideout screen: stash, loadout, traders, START RAID, online party) from anywhere.
## The shooting range (0.21.1): at its bench, pick your own loadout or borrow any gun the Gunsmith sells you, and
## shoot the targets at 10, 25, 50 and 100 m. Ammo is free; nothing you do there is saved.
## Phones open straight on the menu until the touch controls (moving with a stick) exist.

const LEVEL := preload("res://scenes/hideout/hideout_level.tscn")
const MENU := preload("res://scenes/hideout.tscn")
const PLAYER := preload("res://scenes/player.tscn")
const DUMMY := preload("res://scenes/target_dummy.tscn")
## What each station is called on the USE prompt (traders take their names from Traders.LIST).
const STATION_NAMES := {"stash": "Stash", "wardrobe": "Wardrobe", "workbench": "Workbench", "war_table": "War table",
	"quests": "Quests", "stats": "Stats", "range": "Shooting range", "darts": "Darts", "radio": "Radio",
	"lights": "Lights"}
## Stations with nothing of their own yet: what the menu says when you use them.
const STATION_NOTES := {"workbench": "Crafting comes in a later update.",
	"war_table": "Pick your loadout, then START RAID (or go online and queue with your party)."}

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
## The station in reach (its Marker3D) or null; with none, the seat in reach (or null).
var station: Node3D
var seat: Node3D
## The radio, the seats, darts and the bunks' lights (0.21.7).
var toys: HideoutToys
## At the range: you, with a gun (null while walking round), the gun picker, and the range's HUD.
var shooter: Player
var _picker: CanvasLayer
var _range_hud: CanvasLayer
var _ammo_hud: AmmoHUD
var _crosshair_hud: CrosshairHUD
var _last_hit: Label
var _hit_damage := 0
var _hit_distance := 0.0
var _hit_head := false


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
	walker.locked = true   # (until close_menu says you're walking)
	toys = HideoutToys.new()
	toys.name = "Toys"
	add_child(toys)
	toys.setup(level, walker, env)
	_build_hud()
	_build_range(level)
	_build_boards(level)
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 5
	add_child(_menu_layer)
	menu = MENU.instantiate()
	_menu_layer.add_child(menu)
	var back: Button = menu.add_back_button("< HIDEOUT  (Tab)", "Back to walking round the hideout", close_menu)
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
	HudStyle.style_label(_prompt, 30)
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
	_use_button.text = "USE  (%s)" % use_key()
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
		leave_range()
		open_menu()
	# The mouse is only grabbed while you walk round (or shoot at the range): never with the menu up (0.21.10, owner:
	# on a first load the menu could show before the tab check let it close, with you still free to walk, so a click
	# on the stash grabbed the mouse).
	if menu_open():
		walker.locked = true
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if in_range():
		_top_up_ammo()
		_hud.visible = false
		return
	var free := not menu_open() and not toys.busy()
	station = _station_in_reach() if free else null
	seat = toys.seat_in_reach() if free and station == null else null
	_use_button.visible = station != null or seat != null or toys.busy()
	_use_button.text = ("GET UP  (%s)" if toys.seat != null else "STOP  (%s)" if toys.darts else "USE  (%s)") % use_key()
	_prompt.visible = station != null or seat != null
	if station != null:
		_prompt.text = use_key() + "   " + station_label(station.name)
	elif seat != null:
		_prompt.text = use_key() + "   Sit down"
	_click_hint.visible = not menu_open() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not GameSettings.is_phone()


func _input(event: InputEvent) -> void:
	# At the range the keys are the range's: E (or Esc) brings up the guns, Tab leaves. The player never sees them.
	if not in_range() or _picker.visible:
		return
	if event.is_action_pressed("inventory"):
		leave_range()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		_show_picker()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not GameSettings.is_phone():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if in_range():
		if _picker.visible and event.is_action_pressed("inventory"):
			leave_range()
			get_viewport().set_input_as_handled()
		return
	if not menu_open() and toys.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory"):
		if menu_open():
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not menu_open():
		open_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and (station != null or seat != null):
		use_station()
		get_viewport().set_input_as_handled()


func menu_open() -> bool:
	return _menu_layer.visible


## Opens the hideout menu, on `at`'s tab if it's a trader.
func open_menu(at := "") -> void:
	toys.stand_up()
	_menu_layer.visible = true
	menu.visible = true
	_hud.visible = false
	walker.locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Traders.LIST.has(at):
		menu.open_trader_screen(at)   # (walking up to a trader: their own screen, 0.21.4)
	else:
		menu.close_trader_screen()
	if at == "wardrobe":
		menu.open_wardrobe()          # (character select, 0.21.6)
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
	fill_boards()


func use_station() -> void:
	if toys.busy():
		toys.stand_up()
		return
	if station == null:
		if seat != null:
			toys.sit(seat)
		return
	if toys.use(station.name):
		return
	if station.name == "range":
		enter_range()
	elif station.name == "quests":
		open_menu(quest_trader())   # (the trader whose quests you're on: their screen has them, with HAND IN)
	else:
		open_menu(station.name)


## The prompt for a station: its name, or what using it does.
func station_label(id: String) -> String:
	match id:
		"radio":
			return "Turn the radio " + ("off" if HideoutToys.radio_on else "on")
		"lights":
			return "Lights " + ("off" if HideoutToys.lights_on else "on")
		"darts":
			return "Play darts"
	return station_name(id)


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


# --- The shooting range ------------------------------------------------------------------------

func in_range() -> bool:
	return _picker.visible or shooter != null


func _build_range(level: Node3D) -> void:
	for marker: Node in level.get_node("Range").get_children():
		if not String(marker.name).begins_with("Target"):
			continue
		var dummy: Node3D = DUMMY.instantiate()
		dummy.name = "Dummy" + String(marker.name).trim_prefix("Target")
		add_child(dummy)
		# (turned to face the bench, like the raid's test dummy)
		dummy.global_transform = Transform3D(Basis(Vector3.UP, PI), (marker as Node3D).global_position)
		dummy.get_node("Health").damaged.connect(_on_target_hit.bind(dummy))
	_picker = CanvasLayer.new()
	_picker.layer = 4
	_picker.visible = false
	add_child(_picker)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Guns"
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "SHOOTING RANGE"
	HudStyle.style_label(title, 30, HudStyle.BRASS)
	box.add_child(title)
	var about := Label.new()
	about.text = "Free ammo. Borrowed guns stay at the range; nothing here changes your stash.\nTargets at 10, 25, 50 and 100 m."
	HudStyle.style_label(about, 20)
	box.add_child(about)
	_range_button(box, "YOUR LOADOUT", "loadout", true)
	var lv := Profile.trader_level("guns")
	for entry: Array in Traders.stock("guns"):
		var id: String = entry[0]
		if ItemDB.kind(id) != "weapon":
			continue
		var open: bool = entry[2] <= lv
		_range_button(box, ItemDB.label(id, 1) if open else "%s  (Gunsmith level %d)" % [ItemDB.label(id, 1), entry[2]], id, open)
	var leave := _range_button(box, "LEAVE THE RANGE  (Tab)", "", true)
	leave.name = "LeaveRange"
	_range_hud = CanvasLayer.new()
	_range_hud.layer = 3
	_range_hud.visible = false
	add_child(_range_hud)
	var info := Label.new()
	info.text = "SHOOTING RANGE    %s: change gun    Tab: leave" % use_key()
	info.set_anchors_preset(Control.PRESET_CENTER_TOP)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.position = Vector2(-300, 14)
	info.size = Vector2(600, 30)
	HudStyle.style_label(info, 20)
	_range_hud.add_child(info)
	_last_hit = Label.new()
	_last_hit.name = "LastHit"
	_last_hit.set_anchors_preset(Control.PRESET_CENTER)
	_last_hit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_last_hit.position = Vector2(-250, 40)
	_last_hit.size = Vector2(500, 30)
	HudStyle.style_label(_last_hit, 20)
	_range_hud.add_child(_last_hit)
	# Big buttons for touch screens: change gun, leave.
	for spec: Array in [["GUNS  (%s)" % use_key(), Vector2(-194, 12), _show_picker], ["LEAVE  (Tab)", Vector2(-194, 80), leave_range]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(170, 56)
		button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		button.position = spec[1]
		LootUI.style_button(button)
		button.pressed.connect(spec[2])
		_range_hud.add_child(button)


func _range_button(box: Container, text: String, gun: String, open: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not open
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(420, 50)
	LootUI.style_button(button)
	if gun == "":
		button.pressed.connect(leave_range)
	else:
		button.name = gun
		button.pressed.connect(pick_gun.bind(gun))
	box.add_child(button)
	return button


## At the range's bench: pick a gun.
func enter_range() -> void:
	walker.locked = true
	_hud.visible = false
	_show_picker()


func _show_picker() -> void:
	_picker.visible = true
	_range_hud.visible = false
	if shooter != null:
		shooter.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Shoot with `gun` ("loadout": a copy of your own loadout, attachments and all). Ammo for it is topped up for free.
func pick_gun(gun: String) -> void:
	if shooter == null:
		var spot := get_node("Level/Range/Spot") as Node3D
		Player.practice = true
		shooter = PLAYER.instantiate()
		shooter.name = "RangeShooter"
		shooter.transform = global_transform.affine_inverse() * Transform3D(spot.global_basis, spot.global_position + Vector3.UP * 0.1)
		add_child(shooter)
		walker.visible = false
		walker.process_mode = Node.PROCESS_MODE_DISABLED
		(walker.get_node("CollisionShape3D") as CollisionShape3D).disabled = true
		_ammo_hud = AmmoHUD.new(shooter)
		_range_hud.add_child(_ammo_hud)
		_crosshair_hud = CrosshairHUD.new()
		_range_hud.add_child(_crosshair_hud)
		shooter.gun.hit_confirmed.connect(_on_hit_confirmed)
	shooter.process_mode = Node.PROCESS_MODE_INHERIT
	shooter.camera.current = true
	var inv := shooter.inventory
	if gun == "loadout":
		Profile.apply_inventory(inv, Profile.loadout)
	else:
		Profile.apply_inventory(inv, {})
		var stack := ItemStack.new(gun)
		stack.loaded = int(ItemDB.ITEMS[gun].get("mag", 0))
		inv.equip("secondary" if inv.slot_accepts("secondary", gun) and not inv.slot_accepts("primary", gun) else "primary", stack)
	_top_up_ammo()
	_picker.visible = false
	_range_hud.visible = true
	_last_hit.text = ""
	if not GameSettings.is_phone():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Back to walking round, from where the range's bench is.
func leave_range() -> void:
	if shooter != null:
		shooter.queue_free()
		shooter = null
		_ammo_hud.queue_free()
		_crosshair_hud.queue_free()
	_picker.visible = false
	_range_hud.visible = false
	walker.visible = true
	walker.process_mode = Node.PROCESS_MODE_INHERIT
	(walker.get_node("CollisionShape3D") as CollisionShape3D).disabled = false
	walker.camera.current = true
	walker.locked = menu_open()
	_hud.visible = not menu_open()


## Free ammo: at least four magazines' worth for each gun you hold.
func _top_up_ammo() -> void:
	if shooter == null:
		return
	var inv := shooter.inventory
	for slot: String in ["primary", "secondary"]:
		var held := inv.equipped(slot)
		if held == null or not ItemDB.ITEMS.has(held.id):
			continue
		var info: Dictionary = ItemDB.ITEMS[held.id]
		var ammo := String(info.get("ammo", ""))
		var want := int(info.get("mag_ext", info.get("mag", 10))) * 4
		var have := inv.count_of(ammo)
		if ammo != "" and have < want:
			inv.add(ammo, want - have)
	if _crosshair_hud != null:
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		_crosshair_hud.show_crosshair = captured and not shooter.gun.is_aiming()
		_crosshair_hud.reticle = shooter.gun.reticle() if captured else ""


func _on_target_hit(amount: int, _from: Vector3, dummy: Node3D) -> void:
	_hit_damage = amount
	_hit_distance = Vector2(dummy.global_position.x - shooter.global_position.x,
		dummy.global_position.z - shooter.global_position.z).length() if shooter != null else 0.0
	_hit_head = false
	_show_last_hit.call_deferred()


func _on_hit_confirmed(_killed: bool, headshot: bool) -> void:
	_crosshair_hud.flash_hit(headshot)
	_hit_head = headshot
	_show_last_hit.call_deferred()


func _show_last_hit() -> void:
	_last_hit.text = "%d damage%s at %d m" % [_hit_damage, " (HEAD)" if _hit_head else "", roundi(_hit_distance)]


## The key the use (interact) action is on, for the prompts: F today (E leans in a raid; 0.21.4, owner).
static func use_key() -> String:
	for event in InputMap.action_get_events("interact"):
		if event is InputEventKey:
			var key := event as InputEventKey
			return OS.get_keycode_string(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
	return "F"


# --- The quests and stats boards (0.21.4, owner: "give it more of its own space", "stats board more visible") ---
## Text painted on each board (Marker3Ds under Level/Boards, +z out of the board): your current quests, your record.
var boards := {}


func _build_boards(level: Node3D) -> void:
	var holder := level.get_node_or_null("Boards")
	if holder == null:
		return
	for marker: Node3D in holder.get_children():
		var size: Vector2 = marker.get_meta("size", Vector2(2.3, 1.6))
		var text := Label3D.new()
		text.name = "Text"
		text.font = HudStyle.font(30)
		text.font_size = 30
		text.pixel_size = 0.0065
		text.modulate = HudStyle.TAPE_INK
		text.outline_size = 0
		text.shaded = false
		text.double_sided = false
		text.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		text.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.width = size.x / text.pixel_size
		text.position = Vector3(-size.x / 2, size.y / 2, 0.025)   # (top left, just off the steel)
		marker.add_child(text)
		boards[String(marker.name)] = text
	fill_boards()


## Writes what's on the boards now (after a raid, a hand-in, a level up...).
func fill_boards() -> void:
	if boards.has("quests"):
		(boards["quests"] as Label3D).text = quest_board_text()
	if boards.has("stats"):
		(boards["stats"] as Label3D).text = stats_board_text()


## Each trader's quests for their next level, with your progress; at most 8 lines.
static func quest_board_text() -> String:
	var lines: Array[String] = []
	for trader: String in Traders.LIST:
		var lv := Profile.trader_level(trader)
		var open := Quests.for_level(trader, lv + 1).filter(func(id: String) -> bool: return not Profile.quests_done.has(id))
		if open.is_empty():
			continue
		lines.append("%s  (level %d)" % [String(Traders.LIST[trader]["name"]).to_upper(), lv + 1])
		for id: String in open:
			lines.append("   %s   %d/%d" % [Quests.LIST[id]["name"], Quests.progress(id), int(Quests.LIST[id]["count"])])
	if lines.is_empty():
		return "No jobs right now.\nEvery trader is at their top level, or ready to level up."
	if lines.size() > 8:
		lines.resize(7)
		if not lines[-1].begins_with(" "):   # (no trader name with none of their quests under it)
			lines.resize(6)
		lines.append("   ...more at the traders")
	return "\n".join(lines)


static func stats_board_text() -> String:
	return RecordScreen.stats_text()


## The trader whose quests you'd want to look at: the first one with jobs still open (the Gunsmith if none).
static func quest_trader() -> String:
	for trader: String in Traders.LIST:
		var lv := Profile.trader_level(trader)
		if Quests.for_level(trader, lv + 1).any(func(id: String) -> bool: return not Profile.quests_done.has(id)):
			return trader
	return "guns"
