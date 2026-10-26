class_name WardrobeScreen
extends Control
## The wardrobe (0.21.6, owner: "wardrobe should be like character select"; picked operators AND customizing): pick an
## operator on the left, see them in the middle (drag to turn them, 0.22.5), change any part on the right. What you pick is worn at once and
## saved (Profile.look); online, the others in your raid see it. Looks only.

const CHARACTER_MODEL := preload("res://assets/models/characters/pmc.glb")
const PIXEL_MODEL_SCRIPT := preload("res://scripts/pixel_model.gd")
const SIDE_WIDTH := 300.0
const DRAG_TURN := 0.01   # radians per pixel dragged (0.22.5: the character stays still until you drag; was a constant spin)

## Called with the new look whenever it changes (the hideout saves it and tells the inventory and the server).
var on_change: Callable
var look := {}
var model: PixelModel
var _operator_buttons := {}
var _name: Label
var _hint: Label
var _rows := {}


func _init() -> void:
	name = "WardrobeScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_top = 56
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(0.1, 0.11, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom", "top"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	margin.add_child(columns)

	var left := _panel(columns, SIDE_WIDTH)
	left.add_child(_heading("OPERATORS"))
	for entry: Dictionary in Operators.LIST:
		var button := Button.new()
		button.name = String(entry["id"])
		button.text = String(entry["name"]).to_upper()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 52)
		LootUI.style_button(button, 30)
		button.pressed.connect(func() -> void: wear(entry["look"]))
		left.add_child(button)
		_operator_buttons[entry["id"]] = button
	var stash := Button.new()
	stash.name = "StashButton"
	stash.text = "STASH & GEAR"
	stash.focus_mode = Control.FOCUS_NONE
	stash.custom_minimum_size = Vector2(0, 44)
	stash.size_flags_vertical = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	LootUI.style_button(stash, 20)
	stash.pressed.connect(func() -> void: visible = false)
	left.add_child(stash)

	# The middle: you, turning slowly, on a lit stand.
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 4)
	columns.add_child(middle)
	_name = Label.new()
	HudStyle.style_label(_name, 50)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_name)
	middle.add_child(_build_preview())
	_hint = Label.new()
	_hint.text = "Drag the character to turn them. Looks only: nothing here changes how you play. Others see your character online."
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.modulate = Color(1, 1, 1, 0.55)
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	middle.add_child(_hint)

	var right := _panel(columns, SIDE_WIDTH)
	right.add_child(_heading("CUSTOMIZE"))
	for slot: String in Operators.SLOTS:
		var row := HBoxContainer.new()
		row.name = slot
		row.add_theme_constant_override("separation", 6)
		right.add_child(row)
		var title := Label.new()
		title.text = Operators.SLOT_NAMES[slot]
		title.custom_minimum_size.x = 92
		HudStyle.style_label(title, 20, HudStyle.BRASS)
		row.add_child(title)
		var back := _arrow("<", slot, -1)
		row.add_child(back)
		var option := Label.new()
		HudStyle.style_label(option, 20)
		option.add_theme_font_override("font", HudStyle.spaced_font(20))
		option.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(option)
		row.add_child(_arrow(">", slot, 1))
		_rows[slot] = option


func _panel(parent: Control, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	LootUI.skin_panel(panel)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	return box


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	HudStyle.style_label(label, 30)
	return label


func _arrow(text: String, slot: String, step: int) -> Button:
	var button := Button.new()
	button.name = "Next" if step > 0 else "Back"
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(44, 36)
	LootUI.style_button(button, 20)
	button.pressed.connect(func() -> void: cycle(slot, step))
	return button


func _build_preview() -> SubViewportContainer:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_DRAG
	holder.gui_input.connect(_preview_input)
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	holder.add_child(view)
	var character := CHARACTER_MODEL.instantiate()
	character.set_script(PIXEL_MODEL_SCRIPT)
	model = character as PixelModel
	model.name = "Character"
	model.randomize_outfit = false
	model.rotation.y = PI + 0.4
	view.add_child(model)
	var stand := MeshInstance3D.new()                              # a steel plate to stand on
	var plate := CylinderMesh.new()
	plate.top_radius = 0.7
	plate.bottom_radius = 0.75
	plate.height = 0.08
	plate.radial_segments = 12
	var steel := StandardMaterial3D.new()
	steel.albedo_color = HudStyle.FACE_HI
	plate.material = steel
	stand.mesh = plate
	stand.position.y = -0.04
	view.add_child(stand)
	var camera := Camera3D.new()
	camera.fov = 30.0
	var eye := Vector3(0, 1.2, 5.2)
	camera.transform = Transform3D(Basis.looking_at(Vector3(0, 0.95, 0) - eye), eye)
	view.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.6, 0.6, 0)
	view.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	view.add_child(environment)
	return holder


## Click (or touch) and drag on the character to turn them. Touches arrive as mouse events too (emulated), so
## this works on phones.
func _preview_input(event: InputEvent) -> void:
	if model != null and event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		model.rotation.y += (event as InputEventMouseMotion).relative.x * DRAG_TURN


## Shows the wardrobe with `current` (your look now).
func open(current: Dictionary) -> void:
	look = Operators.clean(current)
	visible = true
	_show()


## Puts on a whole look (an operator).
func wear(new_look: Dictionary) -> void:
	look = Operators.clean(new_look)
	_show()
	if on_change.is_valid():
		on_change.call(look)


## The next (step 1) or previous (-1) option for one part.
func cycle(slot: String, step: int) -> void:
	var options: Array = Operators.SLOTS[slot]
	var changed := look.duplicate()
	changed[slot] = options[posmod(options.find(look[slot]) + step, options.size())]
	wear(changed)


func _show() -> void:
	model.pick_outfit(look)
	var id := Operators.matching(look)
	for operator: String in _operator_buttons:
		_operator_buttons[operator].button_pressed = operator == id
	_name.text = String(Operators.by_id(id)["name"]).to_upper() if id != "" else "YOUR OWN"
	for slot: String in _rows:
		(_rows[slot] as Label).text = String(look[slot]).replace("_", " ").capitalize()
