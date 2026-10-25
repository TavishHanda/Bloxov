extends Node3D
## The walkable hideout (0.21.0): where the game starts and where you come back to after a raid. A cave the PMCs
## dug tunnels off (art_source/scripts/make_hideout.py builds it): walk up to a trader's counter, the stash, the
## wardrobe or the war table and press E (or tap USE) to open the hideout menu there. Tab or the MENU button opens
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
	"quests": "Quests", "stats": "Stats", "range": "Shooting range"}
## Stations with nothing of their own yet: what the menu says when you use them.
const STATION_NOTES := {"wardrobe": "Characters come with the character update. For now: your loadout is on the left.",
	"workbench": "Crafting comes in a later update.",
	"war_table": "Pick your loadout, then START RAID (or go online and queue with your party).",
	"quests": "Quests are under each trader: pick a trader on the right."}

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
	_build_hud()
	_build_range(level)
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
		leave_range()
		open_menu()
	if in_range():
		_top_up_ammo()
		_hud.visible = false
		return
	station = _station_in_reach() if not menu_open() else null
	_use_button.visible = station != null
	_prompt.visible = station != null
	if station != null:
		_prompt.text = "E   " + station_name(station.name)
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
	if station == null:
		return
	if station.name == "range":
		enter_range()
	else:
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
	HudStyle.style_label(title, 28, HudStyle.BRASS)
	box.add_child(title)
	var about := Label.new()
	about.text = "Free ammo. Borrowed guns stay at the range; nothing here changes your stash.\nTargets at 10, 25, 50 and 100 m."
	HudStyle.style_label(about, 16)
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
	info.text = "SHOOTING RANGE    E: change gun    Tab: leave"
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
	for spec: Array in [["GUNS  (E)", Vector2(-194, 12), _show_picker], ["LEAVE  (Tab)", Vector2(-194, 80), leave_range]]:
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
