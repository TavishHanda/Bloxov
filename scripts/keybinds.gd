class_name Keybinds
extends RefCounted
## Rebindable controls (0.26.0, the Keybinds update): one key or mouse button per action, changed in OPTIONS and saved
## with the settings (GameSettings, section "keys"; a save backup carries them too). The defaults are the ones in
## project.godot's input map. Touch controls don't use these.
##
## Never allowed: Escape (pause / back), the Windows / Cmd key, the mouse wheel (it can't be held), F3 and F4 (debug
## line, web raw mouse). In the browser also Ctrl (owner, 0.26.0: holding Ctrl while walking on W is Ctrl+W, which
## closes the tab, and no page can stop that), F11 (full screen) and F12 (developer tools). Other browser keys (F5,
## Ctrl+R, Tab) are fine: the web build swallows every key press while the game has focus (checked in a web export).

## The actions in OPTIONS, in order: [action, label]. A row with no action is a heading.
const ACTIONS: Array = [
	["", "Moving"],
	["move_forward", "Forward"], ["move_back", "Back"], ["move_left", "Left"], ["move_right", "Right"],
	["sprint", "Sprint"], ["jump", "Jump / vault"], ["crouch", "Crouch"], ["prone", "Prone"],
	["lean_left", "Lean left"], ["lean_right", "Lean right"],
	["", "Fighting"],
	["shoot", "Shoot"], ["aim", "Aim"], ["reload", "Reload"], ["melee", "Knife"],
	["weapon_1", "Primary gun"], ["weapon_2", "Sidearm"], ["hotbar_3", "Meds slot"], ["hotbar_4", "Quick slot"],
	["heal", "Heal"],
	["", "Other"],
	["interact", "Use / search"], ["inventory", "Inventory"], ["map", "Map"], ["extracts", "Extracts"],
	["", "Recording"],
	["hide_hud", "Hide HUD"], ["free_cam", "Free camera (solo)"], ["cam_time", "Slow-mo / freeze (free camera)"],
]

## Saved code per action: "key:<physical keycode>" or "mouse:<button index>".
static var _defaults := {}


## The rebindable action names.
static func actions() -> Array[String]:
	var list: Array[String] = []
	for row: Array in ACTIONS:
		if row[0] != "":
			list.append(row[0])
	return list


## The default code of every action (from project.godot, read before anything is changed).
static func defaults() -> Dictionary:
	if _defaults.is_empty():
		for action in actions():
			_defaults[action] = code(action)
	return _defaults


## The code an action is on now.
static func code(action: String) -> String:
	for event in InputMap.action_get_events(action):
		var text := event_code(event)
		if text != "":
			return text
	return ""


## An input event as a code ("" for anything that can't be bound).
static func event_code(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var physical := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:%d" % physical if physical != KEY_NONE else ""
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	return ""


## A code back into an event (null if it isn't one). Keys are physical (the same place on any keyboard layout) and
## carry no modifiers, so Shift held for sprinting doesn't stop F from working.
static func code_event(text: String) -> InputEvent:
	var parts := text.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var value := int(parts[1])
	if parts[0] == "key" and value > 0:
		var key := InputEventKey.new()
		key.physical_keycode = value as Key
		return key
	if parts[0] == "mouse" and value > 0:
		var button := InputEventMouseButton.new()
		button.button_index = value as MouseButton
		return button
	return null


## Why `event` can't be bound ("" = it can). `web`: the browser rules (default: are we in one).
static func refusal(event: InputEvent, web := OS.has_feature("web")) -> String:
	if event is InputEventMouseButton:
		var index := (event as InputEventMouseButton).button_index
		if index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return "The mouse wheel can't be held down: pick a key or button."
		return ""
	if not event is InputEventKey:
		return "Pick a key or mouse button."
	var key := event as InputEventKey
	var physical := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	match physical:
		KEY_ESCAPE:
			return "Escape is kept for the pause menu."
		KEY_META:
			return "The Windows / Cmd key can't be used."
		KEY_F3, KEY_F4:
			return "F3 and F4 are already used by the game."
		KEY_CTRL:
			if web:
				return "Ctrl can't be used in the browser: Ctrl + W closes the tab. It works in the Steam version."
		KEY_F11, KEY_F12:
			if web:
				return "%s is the browser's key: pick another." % key_name("key:%d" % physical)
	return ""


## Puts `event` on `action`. If another action had it, that one gets `action`'s old key (a swap), so nothing is ever
## left with no key. Returns what happened, for the note under the list ("" when nothing else moved), or the reason
## it was refused (`ok` false).
static func bind(action: String, event: InputEvent) -> Dictionary:
	var why := refusal(event)
	if why != "":
		return {"ok": false, "note": why}
	var new_code := event_code(event)
	var old_code := code(action)
	var note := ""
	if new_code == old_code:
		return {"ok": true, "note": ""}
	defaults()
	for other in actions():
		if other != action and code(other) == new_code:
			_put(other, old_code)
			note = "%s moved to %s." % [label(other), key_name(old_code)]
	_put(action, new_code)
	GameSettings.save()
	return {"ok": true, "note": note}


## Every action back on its default.
static func reset_all() -> void:
	var start := defaults()
	for action in actions():
		_put(action, start[action])
	GameSettings.save()


## The codes to save (every action).
static func saved() -> Dictionary:
	defaults()
	var out := {}
	for action in actions():
		out[action] = code(action)
	return out


## Puts saved codes on the input map. Bad, refused or doubled-up ones are skipped (that action keeps its default).
static func load_saved(codes: Dictionary) -> void:
	var start := defaults()
	var taken := {}
	for action in actions():
		var want: String = codes.get(action, start[action]) if codes.get(action) is String else start[action]
		var event := code_event(want)
		if event == null or refusal(event) != "" or taken.has(want):
			want = start[action]
		taken[want] = true
		_put(action, want)


static func _put(action: String, text: String) -> void:
	var event := code_event(text)
	if event == null or not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)


static func label(action: String) -> String:
	for row: Array in ACTIONS:
		if row[0] == action:
			return row[1]
	return action


## The key an action is on, as shown to the player ("F", "Shift", "Right mouse"). With the touch controls on
## (0.29.9), the on-screen button that does it instead ("USE", "BAG").
static func name_of(action: String) -> String:
	if TouchInput.active and TOUCH_NAMES.has(action):
		return TOUCH_NAMES[action]
	return key_of(action)


## The key an action is on, never a touch button (the rebinding list).
static func key_of(action: String) -> String:
	var text := code(action)
	return key_name(text) if text != "" else "?"


## What the touch controls call each action (prompts and tips name these instead of keys).
const TOUCH_NAMES := {
	"move_forward": "the stick", "move_back": "", "move_left": "", "move_right": "", "sprint": "the stick pushed to the edge",
	"jump": "JUMP", "crouch": "CROUCH", "prone": "holding CROUCH", "lean_left": "LEAN", "lean_right": "LEAN",
	"shoot": "FIRE", "aim": "AIM", "reload": "RELOAD", "melee": "KNIFE", "weapon_1": "1", "weapon_2": "2",
	"hotbar_3": "3", "hotbar_4": "4", "heal": "ITEM", "interact": "USE", "inventory": "BAG", "map": "MAP",
	"extracts": "MAP",
	"hide_hud": "HIDE HUD (pause menu)", "free_cam": "CAM", "cam_time": "SLOW",
}


## A code's name ("F", "Shift", "Mouse 4").
static func key_name(text: String) -> String:
	var event := code_event(text)
	if event is InputEventKey:
		return OS.get_keycode_string((event as InputEventKey).physical_keycode)
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "Left mouse"
			MOUSE_BUTTON_RIGHT:
				return "Right mouse"
			MOUSE_BUTTON_MIDDLE:
				return "Middle mouse"
			MOUSE_BUTTON_XBUTTON1:
				return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2:
				return "Mouse 5"
			var index:
				return "Mouse %d" % index
	return "?"


## A short upper-case name for key caps on the HUD ("F", "TAB", "SHIFT", "M4").
static func cap(action: String) -> String:
	if TouchInput.active and action in ["interact", "map", "extracts"]:
		return TOUCH_NAMES[action]
	var text := code(action)
	var event := code_event(text)
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			var index:
				return "M%d" % (index - 4 if index >= MOUSE_BUTTON_XBUTTON1 else index)
	var shown := key_name(text).to_upper()
	return SHORT.get(shown, shown)


## Shorter key cap names, and signs for the sign keys.
const SHORT := {"SPACE": "SPC", "ESCAPE": "ESC", "CAPSLOCK": "CAPS", "BACKSPACE": "BKSP", "ENTER": "ENT",
	"INSERT": "INS", "DELETE": "DEL", "PAGEUP": "PGUP", "PAGEDOWN": "PGDN", "HOME": "HOME", "END": "END",
	"MINUS": "-", "EQUAL": "=", "BRACKETLEFT": "[", "BRACKETRIGHT": "]", "BACKSLASH": "\\", "SEMICOLON": ";",
	"APOSTROPHE": "'", "COMMA": ",", "PERIOD": ".", "SLASH": "/", "QUOTELEFT": "`", "UP": "^", "DOWN": "DN",
	"LEFT": "<", "RIGHT": ">"}
