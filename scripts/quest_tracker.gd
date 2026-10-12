class_name QuestTracker
extends PanelContainer
## The quest tracker (0.17.1, owner: "add it to the pause menu, that way it's not a different button"): a plate next
## to the pause menu listing the quests you can work on now, with your progress and what this raid adds once you
## get out. Shown while the pause menu is.

const WIDTH := 300.0

var _list: VBoxContainer


func _init() -> void:
	name = "QuestTracker"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	LootUI.skin_panel(self)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	margin.add_child(_list)


var _menu: Control


## Fills the list; it sits just right of the pause menu `menu`, level with its top.
func refresh(menu: Control) -> void:
	_menu = menu
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_list.add_child(_label("QUESTS", 30, HudStyle.INK, true))
	var open := Quests.open_quests()
	for trader: String in Traders.LIST:
		if Profile.can_level_up(trader):
			_list.add_child(_label("%s can level up: press LEVEL UP at the trader." % Traders.LIST[trader]["name"], 15, HudStyle.EXTRACT))
	if open.is_empty():
		_list.add_child(_label("No open quests right now.", 15, HudStyle.INK_DIM))
	for id in open:
		var quest: Dictionary = Quests.LIST[id]
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 0)
		_list.add_child(entry)
		var row := HBoxContainer.new()
		entry.add_child(row)
		var title := _label(quest["name"].to_upper(), 20, HudStyle.BRASS, true)
		title.custom_minimum_size.x = 0
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.clip_text = true
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		row.add_child(_label("%d/%d" % [Quests.progress(id), int(quest["count"])], 20, HudStyle.INK, true))
		var count: Label = row.get_child(1)
		count.custom_minimum_size.x = 0
		count.autowrap_mode = TextServer.AUTOWRAP_OFF
		var about := "%s: %s" % [Traders.LIST[quest["trader"]]["name"], quest["text"]]
		var pending := Quests.this_raid(id)
		if pending > 0:
			about += " +%d when you extract." % pending
		elif quest["kind"] == "hand_in":
			about += " (At the trader.)"
		entry.add_child(_label(about, 14, HudStyle.INK_DIM))
	reset_size()
	_place()


func _process(_delta: float) -> void:
	if visible:
		_place()


func _place() -> void:
	if _menu != null and is_instance_valid(_menu):
		position = Vector2(_menu.position.x + _menu.size.x + 12.0, _menu.position.y)


func _label(text: String, size: int, color: Color, pixel := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 36.0
	HudStyle.style_label(label, size, color, pixel)
	return label
