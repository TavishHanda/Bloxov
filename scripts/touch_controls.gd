class_name TouchControls
extends Control
## On-screen controls for touch screens (0.29.9, the owner's mobile plan: every feature kept, buttons merged).
## Off on computers until the screen is touched (TouchInput); desktop controls never change.
##
## Left side: a stick that appears where your thumb lands (push it to the edge going forward to sprint).
## Right side: drag anywhere to look (FIRE looks too while held). About six fight buttons:
##   FIRE (hold; also aims down sights while held, a setting), AIM (tap on / off; CANCEL while a heal can be
##   stopped), RELOAD, JUMP (vaults and climbs where it can, lets go of ladders), CROUCH (tap; hold = prone),
##   ITEM (opens a quick wheel: meds, drinks, grenades, the knife).
## Only when they apply: USE (hold: search, open, unlock, revive) and LEAN left / right (next to cover, or always /
##   never: a setting). The hotbar slots take taps too (guns, meds, quick item, knife: HotbarHUD).
## Top edge: pause, BAG (inventory) and MAP (the full map, which shows the extracts).
## Every button can be moved, resized and hidden (pause menu: TOUCH LAYOUT), saved with the settings.
##
## Buttons send the same input actions the keys do (InputEventAction), so the game can't tell them apart.
## While playing, the browser's "touch = mouse click" copy is off (it would also press whatever is on the left
## mouse button); it comes back for menus and the inventory, which work by tapping and dragging.

## id -> label, default centre (fractions of the screen), radius (px at scale 1), group:
## "fight" (always there), "context" (only when it applies), "top" (small square icons along the top edge).
const BUTTONS := {
	"fire": {"label": "FIRE", "x": 0.895, "y": 0.6, "r": 60.0, "group": "fight"},
	"aim": {"label": "AIM", "x": 0.775, "y": 0.47, "r": 40.0, "group": "fight"},
	"reload": {"label": "RELOAD", "x": 0.955, "y": 0.38, "r": 34.0, "group": "fight"},
	"jump": {"label": "JUMP", "x": 0.79, "y": 0.73, "r": 42.0, "group": "fight"},
	"crouch": {"label": "CROUCH", "x": 0.69, "y": 0.83, "r": 38.0, "group": "fight"},
	"item": {"label": "ITEM", "x": 0.685, "y": 0.64, "r": 34.0, "group": "fight"},
	"use": {"label": "USE", "x": 0.63, "y": 0.47, "r": 40.0, "group": "context"},
	"lean_left": {"label": "LEAN", "x": 0.745, "y": 0.3, "r": 30.0, "group": "context"},
	"lean_right": {"label": "LEAN", "x": 0.835, "y": 0.3, "r": 30.0, "group": "context"},
	"pause": {"label": "", "x": 0.965, "y": 0.1, "r": 24.0, "group": "top"},
	"bag": {"label": "BAG", "x": 0.91, "y": 0.1, "r": 24.0, "group": "top"},
	"map": {"label": "MAP", "x": 0.855, "y": 0.1, "r": 24.0, "group": "top"},
}
## Held buttons: id -> the input action they hold down.
const HOLD_ACTIONS := {"fire": "shoot", "use": "interact", "jump": "jump", "reload": "reload"}
## The stick: how far the thumb moves for full speed (px), and past how much of that it sprints (going forward).
const STICK_RADIUS := 70.0
const SPRINT_PAST := 1.3
## The stick and look halves: thumbs landing left of this (fraction of the width) move, right of it look.
const STICK_SIDE := 0.42
## Holding CROUCH this long goes prone instead (seconds).
const PRONE_HOLD := 0.4
## How close cover has to be for the lean buttons to show (m).
const COVER_REACH := 1.4
const WHEEL_RADIUS := 150.0
const WHEEL_BUTTON := 44.0
## Taps sent as actions are let go of this long after (s), so a physics frame always sees them pressed.
const TAP_TIME := 0.08

var player: Player
## The raid HUD (null at the hideout's shooting range: no hotbar, BAG or MAP there).
var hud: Node
## Called by the pause button instead of pausing, if set (the range: back to its gun picker).
var on_pause := Callable()
## Laying out the buttons (from the pause menu): drag to move, the bar at the top resizes / hides.
var editing := false
var _edit_selected := ""
var _edit_finger := -1
var _edit_grab := Vector2.ZERO
var _edit_bar: HBoxContainer
var _hide_button: Button

## finger index -> what it's doing: "stick", "look" or a button id.
var _fingers := {}
## finger index -> where it was last (look fingers): the turn is worked out from these, not the event's own
## "relative", which a phone browser gets wrong with two fingers down (0.29.11, owner: walking and looking at once
## made the view jump about).
var _last_at := {}
## A look finger moving further than this (fraction of the screen height) in one event is a glitch, not a swipe.
const LOOK_JUMP := 0.25
var _stick_origin := Vector2.ZERO
var _stick_at := Vector2.ZERO
var _stick := Vector2.ZERO
var _sprinting := false
## AIM tapped on.
var _aim_on := false
## What we last told the game the aim button is (so it only hears changes).
var _aim_sent := false
## How long CROUCH has been held (s; -1 = not held, or it already went prone).
var _crouch_held := -1.0
## action -> seconds left before it's let go (taps).
var _taps := {}
var _wheel_open := false
var _wheel_items: Array = []
var _near_cover := false
var _cover_check_left := 0.0
var _emulating := true
## Bigger buttons on small phone screens (see size_boost).
var _boost := 1.0


func _init(owner_player: Player, owner_hud: Node) -> void:
	player = owner_player
	hud = owner_hud
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "TouchControls"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if GameSettings.is_phone():
		TouchInput.active = true
		TouchInput.paused = false
	_build_edit_bar()


func _exit_tree() -> void:
	_release_all()
	Input.emulate_mouse_from_touch = true


# --- Layout -------------------------------------------------------------------------------------------------------

## Where button `id` is now (centre, px) and how big (radius, px).
func button_center(id: String) -> Vector2:
	var spot: Dictionary = TouchInput.layout.get(id, BUTTONS[id])
	return Vector2(size.x * float(spot["x"]), size.y * float(spot["y"]))


func button_radius(id: String) -> float:
	var spot: Dictionary = TouchInput.layout.get(id, {})
	return float(BUTTONS[id]["r"]) * float(spot.get("scale", 1.0)) * _boost


## How much bigger the buttons are drawn on a phone: the HUD is laid out for a 720-high screen and a phone shrinks it
## (a 420 pt high phone draws it at 0.58x), so buttons grow back towards a comfortable thumb size (Apple asks for
## 44 pt taps). 1 on bigger screens and computers.
static func size_boost() -> float:
	if not GameSettings.is_phone():
		return 1.0
	var points_per_pixel := 1.0 / maxf(DisplayServer.screen_get_scale(), 1.0)
	if not OS.has_feature("web"):
		points_per_pixel = 160.0 / maxf(float(DisplayServer.screen_get_dpi()), 160.0)
	var height := float(DisplayServer.window_get_size().y) * points_per_pixel
	return clampf(550.0 / maxf(height, 1.0), 1.0, 1.6)


func is_hidden(id: String) -> bool:
	return bool((TouchInput.layout.get(id, {}) as Dictionary).get("hidden", false))


## Whether button `id` shows right now (hidden ones, and ones that don't apply, don't).
func button_shown(id: String) -> bool:
	if editing:
		return true
	if is_hidden(id) or not visible:
		return false
	var group: String = BUTTONS[id]["group"]
	if group == "top":
		return hud != null or id == "pause"
	if player.downed:
		return false   # (downed: you can only look round and crawl)
	match id:
		"use":
			var it := player.interactor
			return it.target != null or it.door != null or it.swing_door != null or it.revive_target != null
		"lean_left", "lean_right":
			return TouchInput.lean == TouchInput.Lean.ALWAYS or (TouchInput.lean == TouchInput.Lean.NEAR_COVER
				and (_near_cover or player.is_leaning()))
		"aim", "reload":
			return player.gun.weapon != null or (id == "aim" and player.can_cancel_heal())
	return true


func _set_spot(id: String, center: Vector2) -> void:
	var spot: Dictionary = (TouchInput.layout.get(id, {}) as Dictionary).duplicate()
	spot["x"] = clampf(center.x / maxf(size.x, 1.0), 0.02, 0.98)
	spot["y"] = clampf(center.y / maxf(size.y, 1.0), 0.04, 0.96)
	spot["scale"] = spot.get("scale", 1.0)
	spot["hidden"] = spot.get("hidden", false)
	TouchInput.layout[id] = spot


## The button under `pos`, or "" (a little bigger than drawn: fingers are fat).
func button_at(pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id: String in BUTTONS:
		if not button_shown(id):
			continue
		var d := pos.distance_to(button_center(id))
		if d <= button_radius(id) * 1.2 and d < best_d:
			best = id
			best_d = d
	return best


# --- Input --------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# A real mouse click or a key: back to mouse and keyboard (not on phones). Touches turn the controls on.
	if (event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION) \
			or (event is InputEventKey and event.pressed and not event.echo):
		if TouchInput.active and not GameSettings.is_phone():
			_release_all()
			TouchInput.set_active(false)
			if not editing and TouchInput.screen_free:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # (if the browser says no, the pause menu shows)
			editing = false
		return
	# (a touch's copy as a mouse click comes first, before the touch itself: either one turns them on, so a tap on
	# PLAY already counts as touch)
	var touched: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.device == InputEvent.DEVICE_ID_EMULATION)
	if touched and not TouchInput.active:
		# Playing with the mouse: carry on with touch. In the pause menu: it stays up until PLAY is tapped.
		var was_playing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		TouchInput.set_active(true)
		TouchInput.paused = not was_playing
		if was_playing:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not TouchInput.active:
		return
	if editing:
		_edit_input(event)
		return
	if not TouchInput.playing():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_finger_down(touch.index, touch.position)
		else:
			_finger_up(touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_finger_moved(drag.index, drag.position)


func _finger_down(index: int, pos: Vector2) -> void:
	if hud != null and hud.hotbar.slot_at(pos) >= 0:
		return   # (the hotbar takes its own taps)
	if _wheel_open:
		var picked := _wheel_at(pos)
		if picked != "":
			_use_wheel(picked)
		_wheel_open = false
		get_viewport().set_input_as_handled()
		return
	var id := button_at(pos)
	if id == "":
		if pos.x < size.x * STICK_SIDE and pos.y > size.y * 0.18 and not _fingers.values().has("stick"):
			_fingers[index] = "stick"
			_stick_origin = pos
			_stick_at = pos
		elif not _fingers.values().has("look"):
			_fingers[index] = "look"
			_last_at[index] = pos
		return
	_fingers[index] = id
	_last_at[index] = pos
	get_viewport().set_input_as_handled()
	if HOLD_ACTIONS.has(id):
		_send(HOLD_ACTIONS[id], true)
	match id:
		"aim":
			if player.can_cancel_heal():
				_tap("aim")   # (cancels the heal, like right-click)
			else:
				_aim_on = not _aim_on
		"crouch":
			_crouch_held = 0.0
		"item":
			_open_wheel()
		"lean_left", "lean_right":
			_tap(id)
		"pause":
			if on_pause.is_valid():
				on_pause.call_deferred()
			else:
				TouchInput.paused = true
		"bag":
			_tap("inventory")
		"map":
			_tap("map")


func _finger_up(index: int, pos: Vector2) -> void:
	if not _fingers.has(index):
		return
	var id: String = _fingers[index]
	_fingers.erase(index)
	_last_at.erase(index)
	match id:
		"stick":
			_stick = Vector2.ZERO
			_sprinting = false
		"crouch":
			if _crouch_held >= 0.0:
				_tap("crouch")
			_crouch_held = -1.0
		"item":
			# Slid from ITEM onto a wheel item and let go there: use it.
			var picked := _wheel_at(pos)
			if picked != "":
				_use_wheel(picked)
				_wheel_open = false
	if HOLD_ACTIONS.has(id):
		_send(HOLD_ACTIONS[id], false)


func _finger_moved(index: int, pos: Vector2) -> void:
	if not _fingers.has(index):
		return
	var id: String = _fingers[index]
	if id == "stick":
		_stick_at = pos
		var raw := (pos - _stick_origin) / (STICK_RADIUS * _boost)
		_sprinting = raw.length() > SPRINT_PAST and raw.y < -0.5 * raw.length()
		_stick = raw.limit_length(1.0)
	elif id == "look" or id == "fire":
		# (in screen-height terms, so a phone and a tablet turn the same for the same swipe)
		var moved := pos - (_last_at.get(index, pos) as Vector2)
		_last_at[index] = pos
		if moved.length() < size.y * LOOK_JUMP:
			player.touch_look(moved * 720.0 / maxf(size.y, 1.0))


func _process(delta: float) -> void:
	_boost = size_boost()
	var active := TouchInput.active
	visible = active and (TouchInput.playing() or editing)
	var want_emulation := not active or editing or not TouchInput.playing()
	if want_emulation != _emulating:
		_emulating = want_emulation
		if not want_emulation:
			_release_mouse()
		Input.emulate_mouse_from_touch = want_emulation
	if not active or not TouchInput.playing():
		if not _fingers.is_empty() or _aim_sent or _aim_on:
			_release_all()
		if active:
			_edit_bar.visible = editing
		queue_redraw()
		return
	_edit_bar.visible = false
	for action: String in _taps.keys():
		_taps[action] -= delta
		if _taps[action] <= 0.0:
			_taps.erase(action)
			_send(action, false)
	# Movement: the stick's strength on the four move actions (like an analog stick).
	_press("move_left", maxf(-_stick.x, 0.0))
	_press("move_right", maxf(_stick.x, 0.0))
	_press("move_forward", maxf(-_stick.y, 0.0))
	_press("move_back", maxf(_stick.y, 0.0))
	_press("sprint", 1.0 if _sprinting and _fingers.values().has("stick") else 0.0)
	# Holding CROUCH: prone.
	if _crouch_held >= 0.0:
		_crouch_held += delta
		if _crouch_held > PRONE_HOLD:
			_crouch_held = -1.0
			_tap("prone")
	# Aim: tapped on, or FIRE held with auto-aim (not with a grenade out or a heal going: that would cancel it).
	if player.gun.weapon == null or player.out_of_fight():
		_aim_on = false
	var fire_held := _fingers.values().has("fire")
	var want_aim := (_aim_on or (fire_held and TouchInput.auto_ads)) and player.hands_free() and not player.is_throwing()
	if want_aim != _aim_sent:
		_aim_sent = want_aim
		_send("aim", want_aim)
	# A held button that stopped showing (USE with nothing left in reach) lets go.
	for index in _fingers.keys():
		var id: String = _fingers[index]
		if BUTTONS.has(id) and not button_shown(id):
			_fingers.erase(index)
			if HOLD_ACTIONS.has(id):
				_send(HOLD_ACTIONS[id], false)
	_cover_check_left -= delta
	if _cover_check_left <= 0.0:
		_cover_check_left = 0.2
		_near_cover = _cover_near()
	queue_redraw()


## Something solid close by, ahead or to the side (where leaning round it makes sense).
func _cover_near() -> bool:
	if not player.is_inside_tree():
		return false
	var space := player.get_world_3d().direct_space_state
	var from := player.head.global_position
	for angle_deg in [-90.0, -45.0, 0.0, 45.0, 90.0]:
		var dir := (-player.global_basis.z).rotated(Vector3.UP, deg_to_rad(angle_deg))
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * COVER_REACH, 1, [player.get_rid()])
		if not space.intersect_ray(query).is_empty():
			return true
	return false


func _send(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


## Press an action now and let go of it a moment later.
func _tap(action: String) -> void:
	if _taps.has(action):
		return
	_send(action, true)
	_taps[action] = TAP_TIME


## Holds a move action at `strength` (0 = let go). Only state, no event: movement is read each physics frame.
func _press(action: String, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


## Lets go of everything the touch controls are holding (menu opened, controls turned off, raid left).
func _release_all() -> void:
	for index in _fingers.keys():
		var id: String = _fingers[index]
		if HOLD_ACTIONS.has(id):
			_send(HOLD_ACTIONS[id], false)
	_fingers.clear()
	_last_at.clear()
	for action: String in _taps:
		_send(action, false)
	_taps.clear()
	_stick = Vector2.ZERO
	_sprinting = false
	for action in ["move_left", "move_right", "move_forward", "move_back", "sprint"]:
		_press(action, 0.0)
	_aim_on = false
	if _aim_sent:
		_aim_sent = false
		_send("aim", false)
	_crouch_held = -1.0
	_wheel_open = false


## The tap that started play (PLAY, closing the bag) went down as a mouse click: let go of it, or whatever is on
## the left mouse button (FIRE) would stay held with nothing to let go of it.
func _release_mouse() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.device = InputEvent.DEVICE_ID_EMULATION
	Input.parse_input_event(up)


# --- The item wheel ------------------------------------------------------------------------------------------------

## ITEM: a ring of what you can use from your bag right now (each kind of med, drink and grenade, and the knife).
func _open_wheel() -> void:
	if _wheel_open:
		_wheel_open = false
		return
	_wheel_items = wheel_items()
	_wheel_open = true


## [{id, label, count}] for the wheel. "knife" is the knife.
func wheel_items() -> Array:
	var items: Array = []
	var seen := {}
	for stack in player.inventory.all_stacks():
		if seen.has(stack.id) or not ItemDB.kind(stack.id) in ["heal", "drink", "throwable"]:
			continue
		seen[stack.id] = true
		items.append({"id": stack.id, "label": ItemDB.short_name(stack.id).to_upper(), "count": player.inventory.count_of(stack.id)})
	items.append({"id": "knife", "label": "KNIFE", "count": -1})
	return items


func wheel_center() -> Vector2:
	return size * 0.5


func wheel_spot(i: int) -> Vector2:
	var angle := -PI * 0.5 + TAU * float(i) / maxf(float(_wheel_items.size()), 1.0)
	return wheel_center() + Vector2(cos(angle), sin(angle)) * WHEEL_RADIUS * _boost


func _wheel_at(pos: Vector2) -> String:
	if not _wheel_open:
		return ""
	for i in _wheel_items.size():
		if pos.distance_to(wheel_spot(i)) <= WHEEL_BUTTON * _boost * 1.15:
			return _wheel_items[i]["id"]
	return ""


func _use_wheel(id: String) -> void:
	if id == "knife":
		_tap("melee")
		return
	var found := player.inventory.find(id)
	if not found.is_empty():
		player.use_item(found[0], found[1])


# --- Laying the buttons out ---------------------------------------------------------------------------------------

func start_edit() -> void:
	_release_all()
	editing = true
	_edit_selected = ""
	_update_edit_bar()


func stop_edit() -> void:
	editing = false
	_edit_finger = -1
	GameSettings.save()


func _edit_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _edit_finger == -1:
			if _edit_bar.get_global_rect().has_point(touch.position):
				return   # (the bar's own buttons)
			var id := button_at(touch.position)
			if id != "":
				_edit_selected = id
				_edit_finger = touch.index
				_edit_grab = button_center(id) - touch.position
				_update_edit_bar()
				get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _edit_finger:
			_edit_finger = -1
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _edit_finger:
		_set_spot(_edit_selected, (event as InputEventScreenDrag).position + _edit_grab)
		get_viewport().set_input_as_handled()


func _build_edit_bar() -> void:
	_edit_bar = HBoxContainer.new()
	_edit_bar.name = "EditBar"
	_edit_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_edit_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_edit_bar.position.y = 70
	_edit_bar.add_theme_constant_override("separation", 10)
	_edit_bar.visible = false
	add_child(_edit_bar)
	for entry: Array in [["SMALLER", _resize.bind(-0.15)], ["BIGGER", _resize.bind(0.15)], ["HIDE", _toggle_hidden],
			["RESET", _reset_layout], ["DONE", stop_edit]]:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		LootUI.style_button(button, 22, HudStyle.HAZARD if entry[0] == "DONE" else HudStyle.FACE)
		button.custom_minimum_size = Vector2(110, 56)
		button.pressed.connect(entry[1])
		_edit_bar.add_child(button)
		if entry[0] == "HIDE":
			_hide_button = button


func _update_edit_bar() -> void:
	for i in 3:
		(_edit_bar.get_child(i) as Button).disabled = _edit_selected == ""
	_hide_button.text = "SHOW" if _edit_selected != "" and is_hidden(_edit_selected) else "HIDE"


func _resize(step: float) -> void:
	if _edit_selected == "":
		return
	_set_spot(_edit_selected, button_center(_edit_selected))
	TouchInput.layout[_edit_selected]["scale"] = clampf(float(TouchInput.layout[_edit_selected]["scale"]) + step, 0.6, 1.8)


func _toggle_hidden() -> void:
	if _edit_selected == "":
		return
	_set_spot(_edit_selected, button_center(_edit_selected))
	TouchInput.layout[_edit_selected]["hidden"] = not is_hidden(_edit_selected)
	_update_edit_bar()


func _reset_layout() -> void:
	TouchInput.layout = {}
	_edit_selected = ""
	_update_edit_bar()


# --- Drawing -------------------------------------------------------------------------------------------------------

func _draw() -> void:
	if not visible:
		return
	if editing:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
		HudStyle.draw_text(self, "Drag a button to move it. Pick one, then make it bigger, smaller or hide it.",
			Vector2(0, 150), 18, HudStyle.INK, size.x, 1)
	# The stick: a faint ring where it rests, the real one under the thumb.
	if not editing:
		var holding := _fingers.values().has("stick")
		var base := _stick_origin if holding else Vector2(size.x * 0.14, size.y * 0.7)
		var reach := STICK_RADIUS * _boost
		draw_arc(base, reach, 0.0, TAU, 40, Color(HudStyle.INK, 0.35 if holding else 0.15), 3.0)
		var knob := base + _stick * reach if holding else base
		draw_circle(knob, 30.0 * _boost, Color(HudStyle.INK, 0.45 if holding else 0.18))
		if holding and _sprinting:
			draw_arc(base, reach * SPRINT_PAST, -PI * 0.75, -PI * 0.25, 20, Color(HudStyle.HAZARD, 0.8), 4.0)
	for id: String in BUTTONS:
		if not button_shown(id):
			continue
		_draw_button(id)
	if _wheel_open:
		_draw_wheel()


func _draw_button(id: String) -> void:
	var center := button_center(id)
	var radius := button_radius(id)
	var held := _fingers.values().has(id) or (id == "aim" and _aim_sent) or (id == "crouch" and player.is_crouching) \
		or (id == "lean_left" and player.lean_input() < 0) or (id == "lean_right" and player.lean_input() > 0)
	var alpha := 0.3 if editing and is_hidden(id) else 1.0
	var ring := HudStyle.HAZARD if held or (editing and id == _edit_selected) else Color(HudStyle.OUTLINE, 0.7)
	var label: String = BUTTONS[id]["label"]
	if id == "aim" and player.can_cancel_heal():
		label = "CANCEL"
	elif id == "crouch" and player.is_prone:
		label = "PRONE"
	if BUTTONS[id]["group"] == "top":
		var rect := Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		HudStyle.draw_plate(self, rect, ring, Color(HudStyle.FACE, 0.75 * alpha))
		if id == "pause":
			for x in [-6.0, 3.0]:
				draw_rect(Rect2(center + Vector2(x, -9), Vector2(5, 18)), Color(HudStyle.INK, alpha))
		else:
			HudStyle.draw_text(self, label, Vector2(rect.position.x, HudStyle.centered_baseline(center.y, 20)), 20, Color(HudStyle.INK, alpha), rect.size.x, 1)
		return
	draw_circle(center, radius, Color(HudStyle.FACE, (0.6 if held else 0.38) * alpha))
	draw_arc(center, radius, 0.0, TAU, 48, Color(ring, ring.a * alpha), 3.0 if held else 2.0)
	var text_size := 20 if radius >= 38.0 else 16
	if id == "lean_left" or id == "lean_right":
		var side := -1.0 if id == "lean_left" else 1.0
		var tip := center + Vector2(side * radius * 0.45, -radius * 0.25)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-side * 10, -8), tip + Vector2(-side * 10, 8)]), Color(HudStyle.INK, alpha))
		HudStyle.draw_text(self, label, Vector2(center.x - radius, center.y + radius * 0.5), 14, Color(HudStyle.INK, alpha), radius * 2.0, 1)
		return
	HudStyle.draw_text(self, label, Vector2(center.x - radius, HudStyle.centered_baseline(center.y, text_size)), text_size,
		Color(HudStyle.INK, alpha), radius * 2.0, 1)


func _draw_wheel() -> void:
	var center := wheel_center()
	var button := WHEEL_BUTTON * _boost
	draw_circle(center, WHEEL_RADIUS * _boost + button + 14.0, Color(0, 0, 0, 0.35))
	for i in _wheel_items.size():
		var entry: Dictionary = _wheel_items[i]
		var spot := wheel_spot(i)
		draw_circle(spot, button, Color(HudStyle.FACE, 0.85))
		draw_arc(spot, button, 0.0, TAU, 40, HudStyle.BRASS, 2.0)
		HudStyle.draw_text(self, entry["label"], Vector2(spot.x - button, spot.y + 2), 18, HudStyle.INK, button * 2.0, 1)
		if int(entry["count"]) >= 0:
			HudStyle.draw_text(self, "x%d" % int(entry["count"]), Vector2(spot.x - button, spot.y + 24), 16, HudStyle.INK_DIM, button * 2.0, 1)
	HudStyle.draw_text(self, "TAP TO USE", Vector2(center.x - 80, center.y + 6), 16, HudStyle.INK_DIM, 160, 1)
