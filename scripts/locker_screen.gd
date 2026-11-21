class_name LockerScreen
extends Control
## The materials locker (0.38.7, owner 2026-11-21; see MaterialLocker): bought once for $150,000, it keeps up to 50 of
## each crafting material out of the stash. Left: what it is, BUY (until bought), STORE ALL and BACK TO THE WORKBENCH.
## Right: one row per material with how many are in the locker and the stash, STORE, TAKE 1 and TAKE ALL. Opened from
## the workbench's MATERIALS LOCKER button (phones: the CRAFT tab, then MATERIALS LOCKER); everything goes through the
## hideout menu (`hideout`).

const SIDE_WIDTH := 300.0
const ROW_HEIGHT := 76.0

var hideout: Node
var _status: Label
var _buy: Button
var _store_all: Button
## item id -> {"count": Label, "stash": Label, "store": Button, "one": Button, "all": Button, "row": PanelContainer}
var _rows := {}


func _init(menu: Node) -> void:
	hideout = menu
	name = "LockerScreen"
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
	columns.add_child(_build_side())
	columns.add_child(_build_items())


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
	var title := Label.new()
	title.text = "MATERIALS LOCKER"
	HudStyle.style_label(title, 30)
	box.add_child(title)
	box.add_child(_small("Keeps your crafting materials out of the stash: up to %d of each, no fitting things together. The workbench and the truck take parts straight from it. Found-in-raid marks stay, so take things out to hand them in for jobs or sell them." % MaterialLocker.MAX_EACH))
	_status = Label.new()
	HudStyle.style_label(_status, 20, HudStyle.BRASS)
	box.add_child(_status)
	_buy = _button("BUY  %s" % ItemDB.money(MaterialLocker.PRICE), 0, func() -> void:
		hideout.buy_locker()
		refresh())
	_buy.name = "BuyButton"
	box.add_child(_buy)
	_store_all = _button("STORE ALL", 0, func() -> void:
		hideout.store_materials()
		refresh())
	_store_all.name = "StoreAllButton"
	box.add_child(_store_all)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var back := _button("WORKBENCH", 0, func() -> void: hideout.open_craft())
	back.name = "BackButton"
	box.add_child(back)
	return parts[0]


func _build_items() -> Control:
	var parts := _panel(0)
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "MATERIALS"
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
	for id: String in MaterialLocker.ITEMS:
		rows.add_child(_build_row(id))
	return parts[0]


func _build_row(id: String) -> Control:
	var row := PanelContainer.new()
	row.name = id
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
	picture.custom_minimum_size = Vector2(64, 56)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(picture)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(text)
	var label := Label.new()
	label.text = ItemDB.display_name(id)
	HudStyle.style_label(label, 20, ItemDB.color(id))
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(label)
	var stash := _small()
	text.add_child(stash)
	var count := Label.new()
	count.custom_minimum_size = Vector2(80, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.style_label(count, 24)
	line.add_child(count)
	var store := _button("STORE", 100, func() -> void:
		hideout.store_materials(id)
		refresh())
	store.name = "StoreButton"
	line.add_child(store)
	var one := _button("TAKE 1", 100, func() -> void:
		hideout.take_material(id, 1)
		refresh())
	one.name = "TakeOneButton"
	line.add_child(one)
	var all := _button("TAKE ALL", 120, func() -> void:
		hideout.take_material(id, MaterialLocker.MAX_EACH)
		refresh())
	all.name = "TakeAllButton"
	line.add_child(all)
	_rows[id] = {"count": count, "stash": stash, "store": store, "one": one, "all": all, "row": row}
	return row


func open() -> void:
	visible = true
	refresh()


func refresh() -> void:
	var locker := Profile.locker
	_buy.visible = not locker.owned
	var money_ok := Profile.money >= MaterialLocker.PRICE
	_buy.modulate.a = 1.0 if money_ok else 0.6
	_store_all.visible = locker.owned
	_status.text = "%d STORED" % locker.total() if locker.owned else "NOT BOUGHT YET"
	for id: String in MaterialLocker.ITEMS:
		var row: Dictionary = _rows[id]
		var held := locker.count(id)
		var in_stash := Crafting.have(Profile.stash, id)
		(row["count"] as Label).text = "%d/%d" % [held, MaterialLocker.MAX_EACH]
		(row["stash"] as Label).text = "In your stash: %d" % in_stash
		(row["store"] as Button).disabled = not locker.owned or in_stash == 0 or held >= MaterialLocker.MAX_EACH
		(row["one"] as Button).disabled = held == 0
		(row["all"] as Button).disabled = held == 0
		(row["row"] as Control).modulate.a = 1.0 if locker.owned else 0.55
