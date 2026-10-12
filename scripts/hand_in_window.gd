class_name HandInWindow
extends Control
## The hand-in window for a trader quest (0.16.14, owner): your found-in-raid items that count for the quest on the
## left, the trader's box on the right. Tap an item to move one into the box (tap it in the box to take it back),
## then HAND IN gives the trader what's in the box. Part of a quest can be handed in now and the rest later.

signal handed_in(given: int)

const TILE := Vector2(96, 72)

var quest := ""
## Where the items come from (the stash, then what you carry).
var grids: Array = []
## ItemStack -> how many of it are in the box.
var offered := {}

var _title: Label
var _about: Label
var _yours: GridContainer
var _box: GridContainer
var _yours_empty: Label
var _hand_in: Button


func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.17, 0.18)
	style.border_color = HudStyle.BRASS
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_title = Label.new()
	HudStyle.style_label(_title, 30)
	box.add_child(_title)
	_about = Label.new()
	_about.modulate = Color(1, 1, 1, 0.7)
	_about.add_theme_font_size_override("font_size", 14)
	box.add_child(_about)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	box.add_child(columns)
	var left := _column(columns, "YOUR FOUND ITEMS")
	_yours = left[0]
	_yours_empty = Label.new()
	_yours_empty.text = "Nothing found in raid that counts."
	_yours_empty.modulate = Color(1, 1, 1, 0.5)
	_yours_empty.add_theme_font_size_override("font_size", 14)
	(left[1] as VBoxContainer).add_child(_yours_empty)
	_box = _column(columns, "TRADER'S BOX")[0]
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(140, 48)
	LootUI.style_button(cancel, 20)
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	_hand_in = Button.new()
	_hand_in.focus_mode = Control.FOCUS_NONE
	_hand_in.custom_minimum_size = Vector2(180, 48)
	LootUI.style_button(_hand_in, 20)
	_hand_in.pressed.connect(confirm)
	buttons.add_child(_hand_in)


## [the tile grid, the column box] under a heading, in a dark well.
func _column(parent: Control, heading: String) -> Array:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	var label := Label.new()
	label.text = heading
	HudStyle.style_label(label, 16, HudStyle.BRASS)
	column.add_child(label)
	var well := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.075, 0.08)
	style.set_content_margin_all(8)
	well.add_theme_stylebox_override("panel", style)
	well.custom_minimum_size = Vector2(TILE.x * 3 + 24, TILE.y * 2 + 24)
	column.add_child(well)
	var inner := VBoxContainer.new()
	well.add_child(inner)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	inner.add_child(grid)
	return [grid, inner]


func open(quest_id: String, from_grids: Array) -> void:
	quest = quest_id
	grids = from_grids
	offered = {}
	visible = true
	refresh()


func close() -> void:
	visible = false
	offered = {}


## Moves one of `stack` into the box (as long as the quest still needs more).
func offer(stack: ItemStack) -> void:
	if boxed() >= Quests.needed(quest) or int(offered.get(stack, 0)) >= stack.count:
		return
	offered[stack] = int(offered.get(stack, 0)) + 1
	refresh()


## Takes one of `stack` back out of the box.
func take_back(stack: ItemStack) -> void:
	if not offered.has(stack):
		return
	offered[stack] = int(offered[stack]) - 1
	if offered[stack] <= 0:
		offered.erase(stack)
	refresh()


## How many items are in the box.
func boxed() -> int:
	var total := 0
	for stack: ItemStack in offered:
		total += int(offered[stack])
	return total


## Hands in what's in the box.
func confirm() -> void:
	var picks := []
	for grid: GridInventory in grids:
		for stack: ItemStack in grid.stacks:
			if offered.has(stack):
				picks.append([grid, stack, offered[stack]])
	var given := Quests.hand_in_picked(quest, picks)
	close()
	handed_in.emit(given)


func refresh() -> void:
	var info: Dictionary = Quests.LIST[quest]
	_title.text = "%s: HAND IN" % String(info["name"]).to_upper()
	var need := Quests.needed(quest)
	_about.text = "%s  Handed in so far: %d/%d.\nTap an item to put it in the box (tap it again to take it back). You can hand in part now and the rest later." % [info["text"], Quests.progress(quest), int(info["count"])]
	for grid: GridContainer in [_yours, _box]:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	var any := false
	for stack in Quests.hand_in_stacks(quest, grids):
		var left := stack.count - int(offered.get(stack, 0))
		if left > 0:
			any = true
			_yours.add_child(_tile(stack, left, offer.bind(stack), boxed() < need))
		if offered.has(stack):
			_box.add_child(_tile(stack, offered[stack], take_back.bind(stack), true))
	_yours_empty.visible = not any
	var n := boxed()
	_hand_in.text = "HAND IN %d/%d" % [n, need]
	_hand_in.disabled = n == 0


func _tile(stack: ItemStack, count: int, action: Callable, enabled: bool) -> Button:
	var tile := Button.new()
	tile.text = ItemDB.display_name(stack.id) + ("\nx%d" % count if count > 1 else "")
	tile.custom_minimum_size = TILE
	tile.clip_text = true
	tile.focus_mode = Control.FOCUS_NONE
	tile.disabled = not enabled
	LootUI.style_button(tile, 14)
	tile.add_theme_color_override("font_color", ItemDB.color(stack.id))
	tile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tile.pressed.connect(action)
	return tile
