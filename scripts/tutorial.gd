class_name Tutorial
extends CanvasLayer
## The new-player tutorial (0.24.0, owner: "hideout, then first-raid hints"). A first walk round the hideout, one
## step at a time on a card at the top of the screen: walk, shoot at the range, open your gear, visit a trader, then
## the war table and START RAID. A marker over the next place shows where to go. SKIP TUTORIAL ends it any time;
## OPTIONS on the main screen has REPLAY TUTORIAL and the raid tips switch.
## In the first raids, short one-time tips (RaidTips) come up the first time each thing happens.
## Someone who has already played (a raid, money, stash, quests: Profile.has_played) never gets it (owner).
## Phones open on the hideout menu (no walking yet), so they get the raid tips only.
## Nothing here is sent anywhere: it's saved with the profile on your own device.

const DONE := Profile.TUTORIAL_DONE
## The walk round. "at": the station the marker points to; the text is filled in with the keys (keys()).
const STEPS: Array[Dictionary] = [
	{"id": "walk", "text": "Welcome to your hideout. Walk with {move}, look round with the mouse, hold {sprint} to sprint."},
	{"id": "range", "at": "range", "text": "Head to the shooting range and press {use} at the bench."},
	{"id": "shoot", "text": "Pick a gun and hit the targets. Hold {aim} to aim down the sights, {reload} reloads."},
	{"id": "leave_range", "text": "Nice shooting. Press {tab} to leave the range."},
	{"id": "gear", "at": "stash", "text": "Open your gear: press {tab} anywhere, or {use} at the stash."},
	{"id": "gear_info", "text": "Your loadout is what you take into a raid. Die there and you lose it (all but the secure pocket). Your stash stays safe at home. Drag items between them. {tab} to close."},
	{"id": "trader", "at": "guns", "text": "Traders sell guns, armor and meds, and buy your loot. Walk up to a counter and press {use}."},
	{"id": "trader_info", "text": "Buy and sell here. Spending money and doing a trader's jobs levels them up for better stock. {tab} to close."},
	{"id": "raid", "at": "war_table", "text": "You're ready. Press {use} at the war table, then START RAID. Grab loot and get out at an extract before time runs out."},
]
## Hits on the range's targets that finish the shooting step.
const HITS := 3

var world: HideoutWorld
var _card: PanelContainer
var _count: Label
var _text: Label
var _skip: Button
var _marker: Control
var _at := 0
var _start := Vector3.ZERO
var _hits := 0


## Should the hideout walk run (not finished, and you can walk: not on a phone, not online)?
static func wants_hideout() -> bool:
	return int(Profile.tutorial["step"]) < DONE and not GameSettings.is_phone() and not Network.main.is_client()


## REPLAY TUTORIAL: the walk and the raid tips again from the start.
static func replay() -> void:
	Profile.tutorial = Profile.fresh_tutorial()
	Profile.save_profile()


static func set_tips(on: bool) -> void:
	Profile.tutorial["tips"] = on
	Profile.save_profile()


## The key an action is on, as shown to the player ("F", "Shift", "Right mouse").
static func key(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var k := event as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
		if event is InputEventMouseButton:
			match (event as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					return "Left mouse"
				MOUSE_BUTTON_RIGHT:
					return "Right mouse"
	return "?"


## `text` with {move}, {use} and the like swapped for the keys they're on.
static func keys(text: String) -> String:
	return text.format({
		"move": key("move_forward") + key("move_left") + key("move_back") + key("move_right"),
		"sprint": key("sprint"), "use": key("interact"), "aim": key("aim"), "reload": key("reload"),
		"tab": key("inventory"), "heal": key("heal"), "map": key("map"), "extracts": key("extracts"),
		"jump": key("jump"), "crouch": key("crouch"), "prone": key("prone"), "shoot": key("shoot"),
	})


func _init(owner_world: HideoutWorld) -> void:
	world = owner_world
	layer = 6   # (over the hideout menu, so the steps that happen in it show)


func _ready() -> void:
	_at = clampi(int(Profile.tutorial["step"]), 0, STEPS.size() - 1)
	_start = world.walker.global_position
	world.target_hit.connect(func() -> void: _hits += 1)
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.custom_minimum_size = Vector2(640, 0)
	_card.position = Vector2(-320, 12)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(HudStyle.FACE, 0.94)
	style.border_color = HudStyle.BRASS
	style.set_border_width_all(3)
	style.set_content_margin_all(12)
	_card.add_theme_stylebox_override("panel", style)
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_count = Label.new()
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudStyle.style_label(_count, 20, HudStyle.BRASS)
	top.add_child(_count)
	_skip = Button.new()
	_skip.name = "Skip"
	_skip.text = "SKIP TUTORIAL"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.custom_minimum_size = Vector2(190, 44)
	LootUI.style_button(_skip, 20)
	_skip.pressed.connect(skip)
	top.add_child(_skip)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(616, 0)
	HudStyle.style_label(_text, 20)
	box.add_child(_text)
	_marker = Control.new()
	_marker.name = "Marker"
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	add_child(_marker)
	_marker.move_to_front()
	_show()


## The step on the card. Profile's step is DONE once the last card shows (it stays up for this visit).
func step_id() -> String:
	return String(STEPS[_at]["id"])


func skip() -> void:
	Profile.tutorial["step"] = DONE
	Profile.save_profile()
	queue_free()


func _process(_delta: float) -> void:
	if _at < STEPS.size() - 1 and _is_done(step_id()):
		_at += 1
		Profile.tutorial["step"] = _at if _at < STEPS.size() - 1 else DONE
		Profile.save_profile()
		_show()
	# At the range, under the range's own top line; over the menu, at the bottom (its top bar and headings stay clear).
	_card.position.y = 52.0 if world.in_range() else 12.0
	if world.menu_open():
		_card.position.y = _marker.size.y - _card.size.y - 40.0
	_marker.visible = not world.menu_open() and not world.in_range()
	_marker.queue_redraw()


func _is_done(id: String) -> bool:
	match id:
		"walk":
			var moved := world.walker.global_position - _start
			return Vector2(moved.x, moved.z).length() > 3.0
		"range":
			return world.in_range()
		"shoot":
			return _hits >= HITS or not world.in_range()
		"leave_range":
			return not world.in_range()
		"gear":
			return world.menu_open()
		"gear_info", "trader_info":
			return not world.menu_open()
		"trader":
			return world.menu_open() and world.menu.trader_screen.visible
	return false


func _show() -> void:
	_count.text = "TRAINING  %d / %d" % [_at + 1, STEPS.size()]
	_text.text = keys(String(STEPS[_at]["text"]))
	_skip.visible = _at < STEPS.size() - 1


## The station the marker points to (its Marker3D), or null.
func target() -> Node3D:
	var at := String(STEPS[_at].get("at", ""))
	return world.get_node_or_null("Level/Stations/" + at) as Node3D if at != "" else null


func _draw_marker() -> void:
	var spot := target()
	if spot == null:
		return
	var camera := world.walker.camera
	var point := spot.global_position + Vector3.UP * 2.2
	var distance := Vector2(point.x - camera.global_position.x, point.z - camera.global_position.z).length()
	if distance < 1.5 or not camera.current:   # (there already; and straight overhead can't be put on screen)
		return
	var screen := _marker.size
	var at := camera.unproject_position(point)
	if camera.is_position_behind(point):
		at = Vector2(screen.x - at.x, screen.y - 40.0)
	at = at.clamp(Vector2(40, 140), screen - Vector2(40, 60))
	var tri := PackedVector2Array([at + Vector2(-14, -10), at + Vector2(14, -10), at + Vector2(0, 10)])
	_marker.draw_colored_polygon(tri, HudStyle.OUTLINE)
	_marker.draw_colored_polygon(PackedVector2Array([tri[0] + Vector2(3, 2), tri[1] + Vector2(-3, 2), tri[2] + Vector2(0, -3)]), HudStyle.BRASS)
	var label := "%s  %d m" % [world.station_name(spot.name).to_upper(), roundi(distance)]
	var width := HudStyle.text_width(label, 20)
	HudStyle.draw_text(_marker, label, Vector2(at.x - width * 0.5, at.y - 18), 20, HudStyle.INK)
