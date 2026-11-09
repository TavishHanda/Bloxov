class_name DecorPicker
extends Control
## Decorating your corner (lively hideout): a panel at the side of the screen, the corner still in view behind it.
## A row of spots (POSTER, FLAG, RUG, ...) and that spot's options; locked ones say how to unlock them. Picking one
## puts it in your corner straight away (HideoutDecor.refresh) and saves. Big buttons for phones; Esc, Tab or USE
## (or DONE) closes it.

signal closed

var decor: HideoutDecor
var spot := "poster"
var _spot_row: HBoxContainer
var _options: VBoxContainer
var _title: Label


func _init(corner: HideoutDecor) -> void:
	decor = corner
	name = "DecorPicker"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -470
	panel.offset_right = -16
	panel.offset_top = 90
	panel.offset_bottom = -110
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.08, 0.86)
	style.border_color = Color(0.85, 0.7, 0.25, 0.9)
	style.set_border_width_all(2)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_title = Label.new()
	_title.text = "YOUR CORNER"
	HudStyle.style_label(_title, 30)
	box.add_child(_title)
	var grid := GridContainer.new()   # (the spots: 3 a row so they fit a phone)
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for id: String in Decor.SPOTS:
		var b := _button(Decor.SPOT_NAMES[id], 52)
		b.name = "Spot_" + id
		b.toggle_mode = true
		b.pressed.connect(show_spot.bind(id))
		grid.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_options = VBoxContainer.new()
	_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options.add_theme_constant_override("separation", 6)
	scroll.add_child(_options)
	var done := _button("DONE", 60)
	done.name = "Done"
	done.pressed.connect(close)
	box.add_child(done)
	_spot_row = null
	show_spot(spot)


func _button(text: String, height: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(130, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	LootUI.style_button(b)
	return b


## Shows `id`'s options.
func show_spot(id: String) -> void:
	spot = id
	for b in find_children("Spot_*", "Button", true, false):
		(b as Button).set_pressed_no_signal(b.name == "Spot_" + id)
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	var current := Decor.showing(id)
	for entry: Array in Decor.SPOTS[id]:
		var open := Decor.unlocked(entry[2])
		var text := String(entry[1])
		if entry[0] == current:
			text = "> " + text + " <"
		elif not open:
			text += "   (locked: %s)" % Decor.how_to_unlock(entry[2])
		var b := _button(text, 56)
		b.name = "Option_" + String(entry[0])
		b.disabled = not open
		b.pressed.connect(pick.bind(String(entry[0])))
		_options.add_child(b)


## Puts `id` in the spot showing now.
func pick(id: String) -> void:
	if Decor.pick(spot, id):
		decor.refresh()
		show_spot(spot)


func close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()
