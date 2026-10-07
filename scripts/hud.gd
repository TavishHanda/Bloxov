extends CanvasLayer
## Shows the "click to play" hint while the mouse is free, and the crosshair while playing.
## F3 toggles a debug overlay. F4 toggles raw mouse input (web only; press Esc and click to re-lock).

@export var player: Node

@onready var hint: Label = $Hint
@onready var crosshair: Label = $Crosshair
@onready var debug_label: Label = $Debug

var _max_delta_timer := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			debug_label.visible = not debug_label.visible
		elif event.physical_keycode == KEY_F4 and OS.has_feature("web"):
			JavaScriptBridge.eval("window.bloxovRaw && (window.bloxovRaw.want = !window.bloxovRaw.want)", true)


func _process(delta: float) -> void:
	var playing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	hint.visible = not playing
	crosshair.visible = playing

	if not debug_label.visible or player == null:
		return
	var raw := "n/a (not web)"
	if OS.has_feature("web"):
		var want = JavaScriptBridge.eval("window.bloxovRaw ? window.bloxovRaw.want : null", true)
		var active = JavaScriptBridge.eval("window.bloxovRaw ? window.bloxovRaw.active : null", true)
		raw = "wanted=%s active=%s (F4 toggles, then Esc + click)" % [want, active]
	debug_label.text = "FPS: %d\nRaw mouse: %s\nBiggest mouse move (last 1s): %d px\nSpikes dropped: %d\nRecent X moves: %s" % [
		Engine.get_frames_per_second(), raw, roundi(player.debug_max_delta),
		player.debug_spikes_dropped, str(player.debug_recent_dx)]
	_max_delta_timer += delta
	if _max_delta_timer >= 1.0:
		_max_delta_timer = 0.0
		player.debug_max_delta = 0.0
