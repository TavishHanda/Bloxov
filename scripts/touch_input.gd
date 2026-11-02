class_name TouchInput
extends RefCounted
## Touch controls' shared state (0.29.9): whether the on-screen controls are in use, and their saved settings.
## Plain statics with no game-script references, so the gun, the player, Keybinds and GameSettings can all ask it.
## The controls themselves are scripts/touch_controls.gd (raid only).
##
## On a phone the touch controls are always on. On a computer they turn on with the first touch of the screen and
## off again with a real mouse click or a key, so a touch-screen laptop works either way and desktop play never
## changes.

## Lean buttons: never, only next to cover (the default, owner's plan: fewer buttons), or always.
enum Lean { OFF, NEAR_COVER, ALWAYS }

## The touch controls are in use (instead of mouse and keyboard).
static var active := false
## The pause button was pressed (touch has no captured mouse to say "playing").
static var paused := false
## Set by the HUD every frame: no pause menu, inventory or end screen is up.
static var screen_free := false

## Holding FIRE also aims down sights (owner's plan, a setting).
static var auto_ads := true
static var lean := Lean.NEAR_COVER
## Moved / resized / hidden buttons: {button id: {"x": 0..1, "y": 0..1, "scale": float, "hidden": bool}}.
## Missing ids use the default layout (TouchControls.BUTTONS).
static var layout := {}


## Playing right now (what "the mouse is captured" means with a mouse): the gun fires, F opens things, etc.
static func playing() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (active and not paused and screen_free)


## Turns the touch controls on or off (on a phone they stay on).
static func set_active(on: bool) -> void:
	if not on and GameSettings.is_phone():
		return
	if active == on:
		return
	active = on
	# Back on mouse and keyboard: show the pause menu (click PLAY to take the mouse), like after Escape.
	paused = not on


static func layout_text() -> String:
	return JSON.stringify(layout)


## Reads a saved layout (JSON). Anything that isn't a sensible entry is dropped.
static func load_layout(text: String) -> void:
	layout = {}
	var json := JSON.new()
	if text == "" or json.parse(text) != OK or not json.data is Dictionary:
		return
	for id in json.data:
		var entry = json.data[id]
		if not (id is String and entry is Dictionary):
			continue
		layout[id] = {
			"x": clampf(float(entry.get("x", 0.5)), 0.0, 1.0),
			"y": clampf(float(entry.get("y", 0.5)), 0.0, 1.0),
			"scale": clampf(float(entry.get("scale", 1.0)), 0.6, 1.8),
			"hidden": entry.get("hidden", false) == true,
		}
