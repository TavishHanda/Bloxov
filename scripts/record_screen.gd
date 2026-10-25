class_name RecordScreen
extends Control
## Your record and your open jobs on one screen (0.21.10, owner: everything the 3D hideout has must work on phones,
## which open on the menu). The same text as the 3D hideout's stats and quests boards; each trader with jobs open has a
## button to their screen (where HAND IN is).

var hideout: Node
var _stats: Label
var _jobs: VBoxContainer


func _init(menu: Node) -> void:
	hideout = menu
	name = "RecordScreen"
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
	var left := _panel(columns)
	left.add_child(_heading("YOUR RECORD"))
	_stats = Label.new()
	HudStyle.style_label(_stats, 30)
	_stats.add_theme_font_override("font", HudStyle.spaced_font(30))
	_stats.add_theme_constant_override("line_spacing", 8)
	left.add_child(_stats)
	var right := _panel(columns)
	right.add_child(_heading("JOBS"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	_jobs = VBoxContainer.new()
	_jobs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jobs.add_theme_constant_override("separation", 6)
	scroll.add_child(_jobs)


func _panel(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	LootUI.skin_panel(panel)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	return box


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	HudStyle.style_label(label, 30)
	return label


func open() -> void:
	visible = true
	refresh()


func refresh() -> void:
	_stats.text = stats_text()
	for child in _jobs.get_children():
		child.queue_free()
	var any := false
	for trader: String in Traders.LIST:
		var open_jobs := open_quests(trader)
		if open_jobs.is_empty():
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_jobs.add_child(row)
		var title := Label.new()
		title.text = "%s  (for level %d)" % [String(Traders.LIST[trader]["name"]).to_upper(), Profile.trader_level(trader) + 1]
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudStyle.style_label(title, 20, HudStyle.BRASS)
		row.add_child(title)
		var go := Button.new()
		go.name = "Go_" + trader
		go.text = "GO TO TRADER"
		go.focus_mode = Control.FOCUS_NONE
		go.custom_minimum_size = Vector2(0, 44)   # (big enough to tap)
		LootUI.style_button(go, 20)
		go.pressed.connect(func() -> void:
			visible = false
			hideout.open_trader_screen(trader))
		row.add_child(go)
		for id: String in open_jobs:
			var job := Label.new()
			job.text = "   %s   %d/%d\n   %s" % [Quests.LIST[id]["name"], Quests.progress(id), int(Quests.LIST[id]["count"]),
				Quests.LIST[id].get("text", "")]
			job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			HudStyle.style_label(job, 20)
			job.add_theme_font_override("font", HudStyle.spaced_font(20))
			_jobs.add_child(job)
	if not any:
		var none := Label.new()
		none.text = "No jobs right now. Every trader is at their top level, or ready to level up."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HudStyle.style_label(none, 20)
		_jobs.add_child(none)


## A trader's quests for their next level that you haven't done.
static func open_quests(trader: String) -> Array:
	var lv := Profile.trader_level(trader)
	return Quests.for_level(trader, lv + 1).filter(func(id: String) -> bool: return not Profile.quests_done.has(id))


## Your record (the stats board in the 3D hideout shows the same).
static func stats_text() -> String:
	var raids := int(Profile.stats["raids"])
	var extracts := int(Profile.stats["extracts"])
	var levels: Array[String] = []
	for trader: String in Traders.LIST:
		if Traders.max_level(trader) > 1:
			levels.append("%s %d/%d" % [Traders.LIST[trader]["tab"], Profile.trader_level(trader), Traders.max_level(trader)])
	return "\n".join([
		"RAIDS  %d" % raids,
		"EXTRACTED  %d   (%d%%)" % [extracts, roundi(100.0 * extracts / raids) if raids > 0 else 0],
		"DIED  %d" % int(Profile.stats["deaths"]),
		"EARNED  %s" % ItemDB.money(int(Profile.stats["earned"])),
		"STASH WORTH  %s" % ItemDB.money(Profile.stash.total_value()),
		"TRADERS  " + "   ".join(levels.slice(0, 2)),
		"   ".join(levels.slice(2))])
