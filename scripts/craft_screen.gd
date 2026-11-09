class_name CraftScreen
extends Control
## The workbench (0.32.0, owner): crafting from what's in your stash. Instant (owner: no timers), with a selector to
## make one or more at once. Left: the bench's level and its next upgrade. Right: every recipe as a row with what it
## needs (have / need, red when short), - / + / MAX, and CRAFT. Big buttons for touch; phones reach it from the menu's
## CRAFT tab, computers by walking to the workbench. Crafting goes through the hideout menu (`hideout`).

const SIDE_WIDTH := 300.0
const ROW_HEIGHT := 84.0

var hideout: Node
## recipe id -> how many the selector is set to.
var times := {}
var _level: Label
var _pips: HBoxContainer
var _next: VBoxContainer
var _upgrade: Button
var _rows: VBoxContainer
## recipe id -> {"count": Label, "parts": HFlowContainer, "craft": Button, "minus", "plus", "max"}
var _row_parts := {}


func _init(menu: Node) -> void:
	hideout = menu
	name = "CraftScreen"
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
	columns.add_child(_build_bench())
	columns.add_child(_build_recipes())


func _panel(width: float) -> Array:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	if width <= 0.0:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	LootUI.skin_panel(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	return [panel, box]


func _small(text := "", color := Color(1, 1, 1, 0.65)) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, width: float, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, 48)
	LootUI.style_button(button, 20)
	button.pressed.connect(on_press)
	return button


func _build_bench() -> Control:
	var parts := _panel(SIDE_WIDTH)
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "WORKBENCH"
	HudStyle.style_label(title, 40)
	box.add_child(title)
	box.add_child(_small("Turn what you bring home into gear. Parts come from your stash (not the free kit). Crafted things aren't found in raid, so they can't be handed in for jobs."))
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 4)
	box.add_child(_pips)
	_level = Label.new()
	HudStyle.style_label(_level, 20, HudStyle.BRASS)
	box.add_child(_level)
	_next = VBoxContainer.new()
	_next.add_theme_constant_override("separation", 2)
	box.add_child(_next)
	_upgrade = _button("UPGRADE", 0, func() -> void:
		hideout.upgrade_bench()
		refresh())
	_upgrade.name = "UpgradeButton"
	box.add_child(_upgrade)
	return parts[0]


func _build_recipes() -> Control:
	var parts := _panel(0)
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "RECIPES"
	HudStyle.style_label(title, 20, HudStyle.BRASS)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 8
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	for recipe: String in Crafting.RECIPES:
		times[recipe] = 1
		_rows.add_child(_build_row(recipe))
	return parts[0]


func _build_row(recipe: String) -> Control:
	var info: Dictionary = Crafting.RECIPES[recipe]
	var id: String = info["makes"]
	var row := PanelContainer.new()
	row.name = recipe
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0, 0, 0, 0.35)
	plate.border_color = Color(ItemDB.color(id), 0.6)
	plate.set_border_width_all(2)
	plate.border_width_left = 4
	plate.set_content_margin_all(8)
	row.add_theme_stylebox_override("panel", plate)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	row.add_child(line)
	var picture := TextureRect.new()
	picture.texture = ItemIcons.get_icon(id)
	picture.custom_minimum_size = Vector2(72, 64)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(picture)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(text)
	var label := Label.new()
	label.text = ItemDB.label(id, int(info["amount"]))
	HudStyle.style_label(label, 20, ItemDB.color(id))
	label.add_theme_font_override("font", HudStyle.spaced_font(20))
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(label)
	var needs := HFlowContainer.new()
	needs.add_theme_constant_override("h_separation", 12)
	text.add_child(needs)
	# The selector: - count + MAX, then CRAFT.
	var minus := _button("-", 48, func() -> void: _set_times(recipe, int(times[recipe]) - 1))
	line.add_child(minus)
	var count := Label.new()
	count.custom_minimum_size = Vector2(44, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.style_label(count, 30)
	line.add_child(count)
	var plus := _button("+", 48, func() -> void: _set_times(recipe, int(times[recipe]) + 1))
	line.add_child(plus)
	var most := _button("MAX", 70, func() -> void: _set_times(recipe, maxi(Crafting.times_possible(Profile.stash, recipe), 1)))
	line.add_child(most)
	var craft := _button("CRAFT", 130, func() -> void:
		if hideout.craft(recipe, int(times[recipe])):
			times[recipe] = 1
		refresh())
	craft.name = "CraftButton"
	line.add_child(craft)
	_row_parts[recipe] = {"count": count, "parts": needs, "craft": craft, "minus": minus, "plus": plus, "max": most, "row": row}
	return row


func _set_times(recipe: String, value: int) -> void:
	times[recipe] = clampi(value, 1, Crafting.MAX_TIMES)
	_fill_row(recipe)


func open() -> void:
	visible = true
	refresh()


func refresh() -> void:
	var lv := Profile.bench_level
	for pip in _pips.get_children():
		pip.queue_free()
	for i in Crafting.max_level():
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(36, 10)
		pip.color = HudStyle.BRASS if i < lv else Color(1, 1, 1, 0.15)
		_pips.add_child(pip)
	_level.text = "LEVEL %d OF %d" % [lv, Crafting.max_level()]
	for child in _next.get_children():
		_next.remove_child(child)
		child.queue_free()
	var cost := Crafting.bench_cost(lv + 1)
	_upgrade.visible = not cost.is_empty()
	if cost.is_empty():
		_next.add_child(_small("Top level: every recipe is open."))
	else:
		_next.add_child(_small("Level %d opens %s. It takes:" % [lv + 1, _opens(lv + 1)]))
		var money_ok := Profile.money >= int(cost["money"])
		_next.add_child(_small(ItemDB.money(int(cost["money"])), Color.WHITE if money_ok else HudStyle.BLOOD))
		var ready := money_ok
		for part: Array in Crafting.parts_text(Profile.stash, cost["needs"]):
			var ok: bool = part[1] >= part[2]
			ready = ready and ok
			_next.add_child(_small("%s  %d/%d" % [part[0], mini(part[1], part[2]), part[2]], Color.WHITE if ok else HudStyle.BLOOD))
		_upgrade.text = "UPGRADE TO LEVEL %d" % (lv + 1)
		_upgrade.modulate.a = 1.0 if ready else 0.6
	for recipe: String in Crafting.RECIPES:
		_fill_row(recipe)


## What a level opens, by name ("Frag Grenade, Foregrip...").
func _opens(level: int) -> String:
	var names: Array[String] = []
	for recipe: String in Crafting.RECIPES:
		if int(Crafting.RECIPES[recipe]["level"]) == level:
			names.append(ItemDB.display_name(Crafting.RECIPES[recipe]["makes"]))
	return ", ".join(names)


func _fill_row(recipe: String) -> void:
	var info: Dictionary = Crafting.RECIPES[recipe]
	var parts: Dictionary = _row_parts[recipe]
	var n := int(times[recipe])
	var locked := int(info["level"]) > Profile.bench_level
	(parts["count"] as Label).text = str(n)
	var flow: HFlowContainer = parts["parts"]
	for child in flow.get_children():
		flow.remove_child(child)
		child.queue_free()
	var ready := not locked
	for part: Array in Crafting.parts_text(Profile.stash, info["needs"], n):
		var ok: bool = part[1] >= part[2]
		ready = ready and ok
		var label := _small("%s %d/%d" % [part[0], mini(part[1], part[2]), part[2]], Color(1, 1, 1, 0.8) if ok else HudStyle.BLOOD)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		flow.add_child(label)
	var craft: Button = parts["craft"]
	craft.disabled = locked
	craft.text = "LEVEL %d" % int(info["level"]) if locked else "CRAFT"
	craft.modulate.a = 1.0 if ready else 0.6
	for key in ["minus", "plus", "max"]:
		(parts[key] as Button).disabled = locked
	(parts["minus"] as Button).disabled = locked or n <= 1
	(parts["row"] as Control).modulate.a = 0.55 if locked else 1.0
