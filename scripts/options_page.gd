class_name OptionsPage
extends RefCounted
## The game's settings as a list of rows (0.24.1): the main screen's OPTIONS page and the hideout menu's OPTIONS
## window both fill theirs from here. Saved the same way as the raid's pause menu (GameSettings).

## Fills `body` with the settings. `on_replay`: what REPLAY TUTORIAL does after resetting it (none: it starts on the
## next PLAY).
static func build(body: VBoxContainer, on_replay := Callable()) -> void:
	_slider(body, "Volume", GameSettings.volume, 0.0, 1.0, func(v: float) -> void: GameSettings.set_volume(v), "%d%%", 100.0)
	for key: String in GameSettings.MIX_NAMES:
		_slider(body, GameSettings.MIX_NAMES[key], float(GameSettings.mix[key]), 0.0, 1.0,
			func(v: float) -> void: GameSettings.set_mix(key, v), "%d%%", 100.0)
	_slider(body, "Mouse sensitivity", GameSettings.sensitivity, 0.1, 3.0, func(v: float) -> void: GameSettings.set_sensitivity(v), "%.2fx", 1.0)
	var row := _row(body, "Graphics")
	for quality in GameSettings.GRAPHICS_NAMES.size():
		var button := Button.new()
		button.text = String(GameSettings.GRAPHICS_NAMES[quality]).to_upper()
		button.toggle_mode = true
		button.button_pressed = GameSettings.graphics == quality
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(110, 44)
		LootUI.style_button(button, 20)
		button.pressed.connect(func() -> void:
			GameSettings.set_graphics(quality)
			for other: Node in row.get_children():
				if other is Button:
					(other as Button).button_pressed = other == button)
		row.add_child(button)
	_toggle(body, "Damage numbers", GameSettings.damage_numbers, func(on: bool) -> void: GameSettings.set_damage_numbers(on))
	_toggle(body, "Lean: tap to toggle (off: hold)", GameSettings.lean_toggle, func(on: bool) -> void: GameSettings.set_lean_toggle(on))
	# The new-player tutorial (0.24.0): its raid tips, and the whole thing again from the start.
	Profile.load_profile()
	_toggle(body, "Raid tips", RaidTips.on(), func(on: bool) -> void: Tutorial.set_tips(on))
	var tutorial_row := _row(body, "Tutorial")
	var replay := Button.new()
	replay.name = "ReplayTutorial"
	replay.text = "REPLAY TUTORIAL"
	replay.focus_mode = Control.FOCUS_NONE
	replay.custom_minimum_size = Vector2(260, 44)
	LootUI.style_button(replay, 20)
	replay.pressed.connect(func() -> void:
		Tutorial.replay()
		replay.text = "ON NEXT PLAY"
		replay.disabled = true
		if on_replay.is_valid():
			on_replay.call())
	tutorial_row.add_child(replay)


static func _row(body: VBoxContainer, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 260
	HudStyle.style_label(label, 20)
	row.add_child(label)
	body.add_child(row)
	return row


static func _slider(body: VBoxContainer, title: String, value: float, low: float, high: float, on_change: Callable, shown: String, show_scale: float) -> void:
	var row := _row(body, title)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(260, 44)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var readout := Label.new()
	HudStyle.style_label(readout, 20)
	readout.text = shown % (value * show_scale)
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		readout.text = shown % (v * show_scale))


static func _toggle(body: VBoxContainer, title: String, on: bool, on_change: Callable) -> void:
	var row := _row(body, title)
	var box := CheckButton.new()
	box.button_pressed = on
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(on_change)
	row.add_child(box)
