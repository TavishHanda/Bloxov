class_name HideoutTouch
extends Control
## Touch controls for walking round the hideout (0.29.10): the raid's stick (left thumb) and look drag (right side),
## with JUMP and CROUCH (hold = prone). USE and MENU are the hideout's own big buttons. Same rules as the raid's
## (TouchInput): on phones always, on computers after the first touch, mouse and keyboard unchanged.
## The shooting range uses the raid's TouchControls with the range's shooter.

const BUTTONS := {
	"jump": {"label": "JUMP", "x": 0.79, "y": 0.73, "r": 42.0},
	"crouch": {"label": "CROUCH", "x": 0.69, "y": 0.83, "r": 38.0},
	"throw": {"label": "THROW", "x": 0.86, "y": 0.6, "r": 56.0},
}

var walker: HideoutWalker
## Darts, while a game is on: THROW (hold to wind up, let go to throw) instead of JUMP and CROUCH.
var toys: HideoutToys
## Walking round (no menu, not sitting, not at the range): set by the hideout every frame.
var walking := false
## The hideout's own buttons (USE, MENU): touches on them are theirs, not the stick's or the look's.
var blockers: Array[Control] = []
var _fingers := {}
## finger index -> where it was last (the look finger: see TouchControls._last_at).
var _last_at := {}
var _stick_origin := Vector2.ZERO
var _stick := Vector2.ZERO
var _sprinting := false
var _crouch_held := -1.0
var _taps := {}
var _emulating := true
var _boost := 1.0


func _init(owner_walker: HideoutWalker) -> void:
	walker = owner_walker
	name = "HideoutTouch"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if GameSettings.is_phone():
		TouchInput.active = true
	TouchInput.paused = false   # (a raid left from its pause menu leaves it set)


func _exit_tree() -> void:
	_release_all()
	Input.emulate_mouse_from_touch = true


func button_center(id: String) -> Vector2:
	return Vector2(size.x * float(BUTTONS[id]["x"]), size.y * float(BUTTONS[id]["y"]))


func button_radius(id: String) -> float:
	return float(BUTTONS[id]["r"]) * _boost


func button_shown(id: String) -> bool:
	return (id == "throw") == playing_darts()


func playing_darts() -> bool:
	return toys != null and toys.darts and toys.darts_game != null and toys.darts_game.mode != ""


func button_at(pos: Vector2) -> String:
	for id: String in BUTTONS:
		if button_shown(id) and pos.distance_to(button_center(id)) <= button_radius(id) * 1.2:
			return id
	return ""


func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION) \
			or (event is InputEventKey and event.pressed and not event.echo):
		if TouchInput.active and not GameSettings.is_phone():
			_release_all()
			TouchInput.set_active(false)
			TouchInput.paused = false
		return
	var touched: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.device == InputEvent.DEVICE_ID_EMULATION)
	if touched and not TouchInput.active:
		TouchInput.set_active(true)
		TouchInput.paused = false
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not TouchInput.active or not walking:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_finger_down(touch.index, touch.position)
		else:
			_finger_up(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _fingers.has(drag.index):
			return
		if _fingers[drag.index] == "stick":
			var raw := (drag.position - _stick_origin) / (TouchControls.STICK_RADIUS * _boost)
			_sprinting = raw.length() > TouchControls.SPRINT_PAST and raw.y < -0.5 * raw.length()
			_stick = raw.limit_length(1.0)
		elif _fingers[drag.index] == "look":
			var moved := drag.position - (_last_at.get(drag.index, drag.position) as Vector2)
			_last_at[drag.index] = drag.position
			if moved.length() >= size.y * TouchControls.LOOK_JUMP:
				return
			var turn := moved * 720.0 / maxf(size.y, 1.0) * Player.TOUCH_LOOK * GameSettings.sensitivity
			walker.look(turn.x, turn.y)


func _finger_down(index: int, pos: Vector2) -> void:
	for blocker in blockers:
		if blocker.is_visible_in_tree() and blocker.get_global_rect().has_point(pos):
			return
	var id := button_at(pos)
	if id != "":
		_fingers[index] = id
		get_viewport().set_input_as_handled()
		if id == "jump":
			_tap("jump")
		elif id == "throw":
			_darts_click(true)
		else:
			_crouch_held = 0.0
		return
	if pos.x < size.x * TouchControls.STICK_SIDE and pos.y > size.y * 0.18 and not _fingers.values().has("stick"):
		_fingers[index] = "stick"
		_stick_origin = pos
	elif not _fingers.values().has("look"):
		_fingers[index] = "look"
		_last_at[index] = pos


func _finger_up(index: int) -> void:
	if not _fingers.has(index):
		return
	var id: String = _fingers[index]
	_fingers.erase(index)
	_last_at.erase(index)
	if id == "stick":
		_stick = Vector2.ZERO
		_sprinting = false
	elif id == "crouch" and _crouch_held >= 0.0:
		_crouch_held = -1.0
		_tap("crouch")
	elif id == "throw":
		_darts_click(false)


## THROW down / up: darts takes it as the click it's made for.
func _darts_click(pressed: bool) -> void:
	if not playing_darts():
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	toys.darts_game.handle_input(click)


func _process(delta: float) -> void:
	_boost = TouchControls.size_boost()
	var on := TouchInput.active and walking
	visible = on
	if on == _emulating:
		_emulating = not on
		if on:
			_release_mouse()
		Input.emulate_mouse_from_touch = not on
	if not on:
		if not _fingers.is_empty() or _stick != Vector2.ZERO:
			_release_all()
		return
	for action: String in _taps.keys():
		_taps[action] -= delta
		if _taps[action] <= 0.0:
			_taps.erase(action)
			_send(action, false)
	_press("move_left", maxf(-_stick.x, 0.0))
	_press("move_right", maxf(_stick.x, 0.0))
	_press("move_forward", maxf(-_stick.y, 0.0))
	_press("move_back", maxf(_stick.y, 0.0))
	_press("sprint", 1.0 if _sprinting else 0.0)
	if _crouch_held >= 0.0:
		_crouch_held += delta
		if _crouch_held > TouchControls.PRONE_HOLD:
			_crouch_held = -1.0
			_tap("prone")
	queue_redraw()


func _send(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


func _tap(action: String) -> void:
	if _taps.has(action):
		return
	_send(action, true)
	_taps[action] = TouchControls.TAP_TIME


func _press(action: String, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


func _release_all() -> void:
	_fingers.clear()
	_last_at.clear()
	for action: String in _taps:
		_send(action, false)
	_taps.clear()
	_stick = Vector2.ZERO
	_sprinting = false
	_crouch_held = -1.0
	for action in ["move_left", "move_right", "move_forward", "move_back", "sprint"]:
		_press(action, 0.0)


## (see TouchControls._release_mouse: the tap that closed the menu went down as a click)
func _release_mouse() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.device = InputEvent.DEVICE_ID_EMULATION
	Input.parse_input_event(up)


func _draw() -> void:
	var holding := _fingers.values().has("stick")
	var reach := TouchControls.STICK_RADIUS * _boost
	var base := _stick_origin if holding else Vector2(size.x * 0.14, size.y * 0.7)
	draw_arc(base, reach, 0.0, TAU, 40, Color(HudStyle.INK, 0.35 if holding else 0.15), 3.0)
	draw_circle(base + _stick * reach if holding else base, 30.0 * _boost, Color(HudStyle.INK, 0.45 if holding else 0.18))
	for id: String in BUTTONS:
		if not button_shown(id):
			continue
		var center := button_center(id)
		var radius := button_radius(id)
		var held := _fingers.values().has(id) or (id == "crouch" and (walker.is_crouching or walker.is_prone))
		draw_circle(center, radius, Color(HudStyle.FACE, 0.6 if held else 0.38))
		draw_arc(center, radius, 0.0, TAU, 48, HudStyle.HAZARD if held else Color(HudStyle.OUTLINE, 0.7), 3.0 if held else 2.0)
		var label: String = "PRONE" if id == "crouch" and walker.is_prone else BUTTONS[id]["label"]
		HudStyle.draw_text(self, label, Vector2(center.x - radius, HudStyle.centered_baseline(center.y, 20)), 20, HudStyle.INK, radius * 2.0, 1)
