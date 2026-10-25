class_name TraderScreen
extends Control
## A trader's own screen (0.21.4, owner: "if you click on a trader in the hideout it gives a separate traders screen").
## Walking up to a trader in the 3D hideout opens it; the trader column beside the stash stays as it was.
## Left: who they are, their level and quests. Middle: their stock as big cards (hover one for its details).
## Right: what you have that they buy, with a SELL button each. Buying, selling and quests go through the hideout menu
## (`hideout`), the same as the trader column.

const CARD_SIZE := Vector2(150, 150)
const SIDE_WIDTH := 300.0

var hideout: Node
var trader := "guns"
var _tabs := {}
var _name: Label
var _about: Label
var _level: Label
var _pips: HBoxContainer
var _quests: VBoxContainer
var _cards: GridContainer
var _sell_rows: VBoxContainer
var _sell_title: Label
var _detail_name: Label
var _detail_line: Label
var _detail_desc: Label
var _bars: GunStatBars
var _card_width := CARD_SIZE.x


func _init(menu: Node) -> void:
	hideout = menu
	name = "TraderScreen"
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
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# Trader tabs, and the way to your stash.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)
	for id: String in Traders.LIST:
		var tab := Button.new()
		tab.text = String(Traders.LIST[id]["name"]).to_upper()
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(120, 40)
		LootUI.style_button(tab, 20)
		tab.pressed.connect(func() -> void:
			hideout.open_trader(id)
			open(id))
		top.add_child(tab)
		_tabs[id] = tab
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var stash := Button.new()
	stash.name = "StashButton"
	stash.text = "STASH & GEAR"
	stash.tooltip_text = "Your stash and what you carry (the trader stays in the column on the right)"
	stash.focus_mode = Control.FOCUS_NONE
	stash.custom_minimum_size = Vector2(0, 40)
	LootUI.style_button(stash, 20)
	stash.pressed.connect(func() -> void: visible = false)
	top.add_child(stash)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	columns.add_child(_build_trader_card())
	columns.add_child(_build_stock())
	columns.add_child(_build_sell())
	_build_details(root)


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
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	return [panel, box]


func _scroll(into: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 8
	into.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return rows


func _small(text := "") -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.65)
	label.add_theme_font_size_override("font_size", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _build_trader_card() -> Control:
	var parts := _panel(SIDE_WIDTH)
	var box: VBoxContainer = parts[1]
	_name = Label.new()
	HudStyle.style_label(_name, 40)
	box.add_child(_name)
	_about = _small()
	box.add_child(_about)
	# Level: a row of pips (filled up to your level), and what the next one takes.
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 4)
	box.add_child(_pips)
	_level = _small()
	box.add_child(_level)
	_quests = _scroll(box)
	return parts[0]


func _build_stock() -> Control:
	var parts := _panel(0)
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "FOR SALE"
	HudStyle.style_label(title, 20, HudStyle.BRASS)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 8
	box.add_child(scroll)
	_cards = GridContainer.new()
	_cards.columns = 3
	_cards.add_theme_constant_override("h_separation", 8)
	_cards.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_cards)
	# As many cards across as fit between the side columns (from the screen's width: the grid's own width would
	# only ever grow).
	resized.connect(func() -> void:
		var room := size.x - 20.0 - 2.0 * (SIDE_WIDTH + 10.0) - 28.0 - 14.0
		_cards.columns = maxi(1, int((room + 8.0) / (CARD_SIZE.x + 8.0)))
		_card_width = maxf(CARD_SIZE.x, (room - 8.0 * (_cards.columns - 1)) / _cards.columns)
		for card: Control in _cards.get_children():
			card.custom_minimum_size.x = _card_width)
	return parts[0]


## Details of the card under the mouse (or last tapped), across the bottom like the stash screen's.
func _build_details(root: VBoxContainer) -> void:
	var details := VBoxContainer.new()
	details.custom_minimum_size = Vector2(0, 80)
	details.add_theme_constant_override("separation", 0)
	root.add_child(details)
	_detail_name = Label.new()
	HudStyle.style_label(_detail_name, 30)
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(_detail_name)
	_detail_line = _small()
	_detail_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(_detail_line)
	_detail_desc = _small()
	_detail_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_desc.modulate.a = 0.5
	details.add_child(_detail_desc)
	_bars = GunStatBars.new()
	_bars.alignment = BoxContainer.ALIGNMENT_CENTER
	details.add_child(_bars)


func _build_sell() -> Control:
	var parts := _panel(SIDE_WIDTH)
	var box: VBoxContainer = parts[1]
	_sell_title = Label.new()
	HudStyle.style_label(_sell_title, 20, HudStyle.BRASS)
	box.add_child(_sell_title)
	box.add_child(_small("What you have that they buy, from your stash and what you carry (not what you wear)."))
	_sell_rows = _scroll(box)
	return parts[0]


## Shows `id`'s screen.
func open(id: String) -> void:
	trader = id
	visible = true
	_show_details(null)
	refresh()


func refresh() -> void:
	var info: Dictionary = Traders.LIST[trader]
	for id: String in _tabs:
		_tabs[id].button_pressed = id == trader
	var lv: int = Profile.trader_level(trader)
	var top_level := Traders.max_level(trader)
	_name.text = String(info["name"]).to_upper()
	_about.text = info["about"]
	for pip in _pips.get_children():
		pip.queue_free()
	for i in top_level:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(36, 10)
		pip.color = HudStyle.BRASS if i < lv else Color(1, 1, 1, 0.15)
		_pips.add_child(pip)
	var line := "LEVEL %d of %d" % [lv, top_level]
	if lv < top_level:
		var next := Traders.next_level_cost(trader, lv, int(Profile.trader_spent.get(trader, 0)))
		line += ". Level %d: the quests below" % (lv + 1) + (" and spend %s more here" % ItemDB.money(next) if next > 0 else "")
	_level.text = line
	for child in _quests.get_children():
		_quests.remove_child(child)
		child.queue_free()
	hideout._fill_quests(trader, lv, _quests)
	_pips.visible = top_level > 1
	_level.visible = top_level > 1
	if lv >= top_level and top_level > 1:
		_quests.add_child(_small("Top level: everything they sell is open to you."))
	_fill_cards(lv)
	_fill_sell()


func _fill_cards(lv: int) -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	for entry: Array in Traders.stock(trader):
		var id: String = entry[0]
		var amount: int = entry[1]
		var open: bool = entry[2] <= lv
		var price := ItemDB.money(Traders.buy_price(id, amount)) if open else "LEVEL %d" % entry[2]
		var card := _card(ItemIcons.get_icon(id), ItemDB.label(id, amount), ItemDB.color(id), price, open)
		var stack := ItemStack.new(id, mini(amount, ItemDB.max_stack(id)))
		if ItemDB.kind(id) == "weapon":
			stack.loaded = int(ItemDB.weapon_stats(stack)["mag"])
		card[0].mouse_entered.connect(_show_details.bind(stack))
		card[0].gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
				_show_details(stack))
		(card[1] as Button).pressed.connect(func() -> void: hideout.buy(id, amount))
	# Ming's boxes, odds on the card (shown before you buy: STORE_RULES.md section 5).
	if trader == "ming":
		for box: String in Traders.BOXES:
			var card := _card(null, Traders.BOXES[box]["name"], HudStyle.BRASS, ItemDB.money(int(Traders.BOXES[box]["price"])), true)
			var parts: Array[String] = []
			for odds: Array in Traders.box_odds(box):
				parts.append("%s %s%%" % [odds[0], str(snappedf(odds[1], 0.1)).trim_suffix(".0")])
			# (on the card itself, not only on hover: phones have no hover, and the odds must show before you pay)
			var odds := _small("Odds: " + ", ".join(parts))
			odds.add_theme_font_size_override("font_size", 11)
			odds.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var card_box := (card[0] as Control).get_child(0)
			card_box.add_child(odds)
			card_box.move_child(odds, 2)
			card[0].custom_minimum_size.y = 230
			card[0].mouse_entered.connect(func() -> void:
				_show_details(null)
				_detail_name.text = Traders.BOXES[box]["name"]
				_detail_line.text = "Odds: " + ", ".join(parts))
			(card[1] as Button).pressed.connect(func() -> void:
				hideout.open_box(box)
				refresh())
	if trader == "supplies":
		var cost := Profile.next_stash_cost()
		var card := _card(null, "Stash upgrade (+10 rows)" if cost > 0 else "Stash: max size", Color.WHITE,
			ItemDB.money(cost) if cost > 0 else "MAX", cost > 0)
		(card[1] as Button).name = "StashUpgradeButton"
		(card[1] as Button).pressed.connect(func() -> void:
			hideout.upgrade_stash()
			refresh())


## One card: picture, name, and a price button. Returns [card, button].
func _card(icon: Texture2D, title: String, color: Color, price: String, open: bool) -> Array:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(_card_width, CARD_SIZE.y)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0, 0, 0, 0.35)
	plate.border_color = Color(color, 0.6 if open else 0.2)
	plate.set_border_width_all(2)
	plate.border_width_bottom = 4
	plate.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", plate)
	_cards.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var picture := TextureRect.new()
	picture.texture = icon
	picture.custom_minimum_size = Vector2(0, 64)
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(picture)
	var label := Label.new()
	label.text = title
	HudStyle.style_label(label, 20, color)
	label.add_theme_font_override("font", HudStyle.spaced_font(20))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	var button := Button.new()
	button.text = price
	button.disabled = not open
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 36)
	LootUI.style_button(button)
	box.add_child(button)
	card.modulate.a = 1.0 if open else 0.55
	return [card, button]


func _show_details(stack: ItemStack) -> void:
	if stack == null:
		_detail_name.text = ""
		_detail_line.text = ""
		_detail_desc.text = ""
		_bars.clear()
		return
	_detail_name.text = stack.title() + ("  x%d" % stack.count if stack.count > 1 else "")
	_detail_name.add_theme_color_override("font_color", ItemDB.color(stack.id))
	_detail_line.text = LootUI.details(stack)
	_detail_desc.text = ItemDB.description(stack.id)
	_bars.show_gun(stack)


## Everything you have that this trader buys: stash first, then pockets, backpack and secure pocket.
func sellable() -> Array:
	var found := []
	for grid: GridInventory in [Profile.stash] + hideout.inventory.grids():
		for stack: ItemStack in grid.stacks:
			if Traders.buyer_for(stack.id) == trader:
				found.append([grid, stack])
	return found


func _fill_sell() -> void:
	for child in _sell_rows.get_children():
		_sell_rows.remove_child(child)
		child.queue_free()
	var info: Dictionary = Traders.LIST[trader]
	_sell_title.text = "SELL TO %s" % String(info["name"]).to_upper()
	var items := sellable()
	if items.is_empty():
		_sell_rows.add_child(_small("Nothing they buy right now." if not (info["kinds"] as Array).is_empty()
			else "%s doesn't buy anything." % info["name"]))
		return
	for pair: Array in items:
		var grid: GridInventory = pair[0]
		var stack: ItemStack = pair[1]
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_entered.connect(_show_details.bind(stack))
		_sell_rows.add_child(row)
		var picture := TextureRect.new()
		picture.texture = ItemIcons.get_icon(stack.id)
		picture.custom_minimum_size = Vector2(48, 28)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(picture)
		var label := Label.new()
		label.text = stack.title() + (" x%d" % stack.count if stack.count > 1 else "")
		HudStyle.style_label(label, 20, ItemDB.color(stack.id))
		label.add_theme_font_override("font", HudStyle.spaced_font(20))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		var button := Button.new()
		button.text = ItemDB.money(Traders.sell_price(stack))
		button.tooltip_text = "Sell"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(84, 36)
		LootUI.style_button(button, 20, HudStyle.EXTRACT)
		button.pressed.connect(func() -> void:
			if grid.stacks.has(stack):
				hideout.sell(grid, stack)
			refresh())
		row.add_child(button)
