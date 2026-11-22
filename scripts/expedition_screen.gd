class_name ExpeditionScreen
extends Control
## The truck (0.38.0, Expeditions; owner 2026-11-20): build the amphibious armoured truck's five parts from your
## stash and money, then pay the safe haven and leave. Left: the truck, the haven's price, what leaving resets and
## what stays, and LEAVE ON EXPEDITION (type LEAVE to confirm: it wipes this stash). Right: the parts as rows with
## what each needs (have / need, red when short) and BUILD. Opened from the workbench's THE TRUCK button (phones: the
## CRAFT tab, then THE TRUCK); everything goes through the hideout menu (`hideout`).

const SIDE_WIDTH := 330.0
const ROW_HEIGHT := 92.0

var hideout: Node
var _status: Label
var _pips: HBoxContainer
var _haven: Label
var _leave: Button
var _confirm_box: VBoxContainer
var _confirm_edit: LineEdit
var _go: Button
## part id -> {"needs": HFlowContainer, "build": Button, "row": PanelContainer, "money": Label}
var _rows := {}


func _init(menu: Node) -> void:
	hideout = menu
	name = "ExpeditionScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_top = 56
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(0.09, 0.1, 0.11)
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
	columns.add_child(_build_side())
	columns.add_child(_build_parts())


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


func _build_side() -> Control:
	var parts := _panel(SIDE_WIDTH)
	var box: VBoxContainer = parts[1]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	var title := Label.new()
	title.text = "THE TRUCK"
	HudStyle.style_label(title, 40)
	inner.add_child(title)
	inner.add_child(_small("An amphibious armoured truck: your way out of the war. Build its five parts from what you bring home, pay the safe haven's entry, and leave. Everything here is earned money and loot."))
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 4)
	inner.add_child(_pips)
	_status = Label.new()
	HudStyle.style_label(_status, 20, HudStyle.BRASS)
	inner.add_child(_status)
	_haven = _small()
	inner.add_child(_haven)
	inner.add_child(_small("Leaving starts this stash over: stash, materials locker, money, loadouts, traders, jobs and the workbench, and the character who goes is back to level 1. You keep your settings, looks, hideout, record, unlocked characters and upgrade points, and the character who goes earns %d more points of its own (up to %d from expeditions)." % [Expedition.POINTS, Characters.MAX_EXPEDITION_POINTS], Color(1, 1, 1, 0.8)))
	_leave = _button("LEAVE ON EXPEDITION", 0, _ask_leave)
	_leave.name = "LeaveButton"
	inner.add_child(_leave)
	_confirm_box = VBoxContainer.new()
	_confirm_box.add_theme_constant_override("separation", 6)
	_confirm_box.visible = false
	inner.add_child(_confirm_box)
	_confirm_box.add_child(_small("This can't be undone. Type LEAVE to go.", HudStyle.BLOOD))
	_confirm_edit = LineEdit.new()
	_confirm_edit.placeholder_text = "LEAVE"
	_confirm_edit.max_length = 5
	_confirm_edit.custom_minimum_size = Vector2(0, 44)
	_confirm_box.add_child(_confirm_edit)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	_confirm_box.add_child(line)
	var back := _button("BACK", 0, func() -> void: _confirm_box.visible = false)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(back)
	_go = _button("GO", 0, func() -> void:
		if _confirm_edit.text.strip_edges().to_upper() == "LEAVE":
			hideout.leave_expedition())
	_go.name = "GoButton"
	_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_go.disabled = true
	line.add_child(_go)
	_confirm_edit.text_changed.connect(func(text: String) -> void: _go.disabled = text.strip_edges().to_upper() != "LEAVE")
	return parts[0]


func _build_parts() -> Control:
	var parts := _panel(0)
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "PARTS"
	HudStyle.style_label(title, 20, HudStyle.BRASS)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 8
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for part: String in Expedition.PARTS:
		rows.add_child(_build_row(part))
	return parts[0]


func _build_row(part: String) -> Control:
	var info: Dictionary = Expedition.PARTS[part]
	var row := PanelContainer.new()
	row.name = part
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0, 0, 0, 0.35)
	plate.border_color = Color(HudStyle.BRASS, 0.6)
	plate.set_border_width_all(2)
	plate.border_width_left = 4
	plate.set_content_margin_all(8)
	row.add_theme_stylebox_override("panel", plate)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	row.add_child(line)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(text)
	var label := Label.new()
	label.text = str(info["name"]).to_upper()
	HudStyle.style_label(label, 20)
	label.add_theme_font_override("font", HudStyle.spaced_font(20))
	text.add_child(label)
	text.add_child(_small(info["about"]))
	var needs := HFlowContainer.new()
	needs.add_theme_constant_override("h_separation", 12)
	text.add_child(needs)
	var build := _button("BUILD", 130, func() -> void:
		hideout.build_truck_part(part)
		refresh())
	build.name = "BuildButton"
	line.add_child(build)
	_rows[part] = {"needs": needs, "build": build, "row": row}
	return row


func open() -> void:
	visible = true
	_confirm_box.visible = false
	_confirm_edit.text = ""
	_go.disabled = true
	refresh()


func refresh() -> void:
	var truck := Profile.truck
	for pip in _pips.get_children():
		pip.queue_free()
	for part: String in Expedition.PARTS:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(48, 10)
		pip.color = HudStyle.BRASS if truck.has(part) else Color(1, 1, 1, 0.15)
		_pips.add_child(pip)
	_status.text = "%d OF %d PARTS BUILT" % [truck.size(), Expedition.PARTS.size()]
	var money_ok := Profile.money >= Expedition.HAVEN_PRICE
	_haven.text = "The safe haven's entry: %s%s" % [ItemDB.money(Expedition.HAVEN_PRICE),
		"" if money_ok else "  (you have %s)" % ItemDB.money(Profile.money)]
	_haven.modulate = Color.WHITE if money_ok else HudStyle.BLOOD
	if Profile.expeditions > 0:
		_status.text += "   ·   TRIPS %d" % Profile.expeditions
	var ready := Expedition.can_leave(truck, Profile.money)
	_leave.disabled = not ready
	_leave.modulate.a = 1.0 if ready else 0.6
	if not ready:
		_confirm_box.visible = false
	for part: String in Expedition.PARTS:
		_fill_row(part)


func _fill_row(part: String) -> void:
	var info: Dictionary = Expedition.PARTS[part]
	var row: Dictionary = _rows[part]
	var flow: HFlowContainer = row["needs"]
	for child in flow.get_children():
		flow.remove_child(child)
		child.queue_free()
	var built := Profile.truck.has(part)
	var build: Button = row["build"]
	build.disabled = built
	build.text = "BUILT" if built else "BUILD"
	(row["row"] as Control).modulate.a = 0.6 if built else 1.0
	if built:
		flow.add_child(_small("On the truck.", HudStyle.BRASS))
		return
	var money_ok := Profile.money >= int(info["money"])
	var ready := money_ok
	var cost := _small(ItemDB.money(int(info["money"])), Color.WHITE if money_ok else HudStyle.BLOOD)
	cost.autowrap_mode = TextServer.AUTOWRAP_OFF
	flow.add_child(cost)
	for need: Array in Crafting.parts_text(Profile.stash, info["needs"], 1, Profile.locker):
		var ok: bool = need[1] >= need[2]
		ready = ready and ok
		var label := _small("%s %d/%d" % [need[0], mini(need[1], need[2]), need[2]], Color(1, 1, 1, 0.8) if ok else HudStyle.BLOOD)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		flow.add_child(label)
	build.modulate.a = 1.0 if ready else 0.6


func _ask_leave() -> void:
	if Expedition.can_leave(Profile.truck, Profile.money):
		_confirm_box.visible = true
		_confirm_edit.text = ""
		_go.disabled = true
