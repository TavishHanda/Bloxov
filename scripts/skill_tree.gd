class_name SkillTree
extends Control
## The upgrade points as a skill tree in its own menu (owner 2026-11-20: "the traits screen to kinda be like a skill
## tree in its own menu"), opened from the CHARACTERS screen (CharacterScreen.open_tree). Three branches grow up from
## the character: its two upsides (5 steps of +2% each) and its passive (rank 1 free, ranks 2 and 3 for 2 points each).
## Its downsides only grow with level (0.39.12, owner 2026-11-22), shown in red beside the character. A branch is bought from the bottom up (Characters.spend,
## through CharacterScreen.spend so the pockets and the save follow). Bought nodes are lit, the next one you can buy
## has a bright edge, the rest are dim. Same rules as before: only the look of the screen is new.

const NODE := 58.0
const BRANCHES: Array[String] = ["u0", "p", "u1"]
const COLUMNS := [0.2, 0.5, 0.8]
const LINE_ON := Color("e2a83e")
const LINE_OFF := Color("545b63")

var screen: Node
var _title: Label
var _points: Label
var _info: Label
var _reset: Button
var _area: Control
var _root: Button
var _downsides: Label
## branch key -> Array[Button], bottom first ("p" starts with rank 1, which every character has).
var _nodes := {}
var _heads := {}


func _init(owner_screen: Node) -> void:
	screen = owner_screen
	name = "SkillTree"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(0.07, 0.08, 0.08)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom", "top"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	rows.add_child(bar)
	_title = _label(32, HudStyle.INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title)
	_points = _label(20, HudStyle.BRASS)
	bar.add_child(_points)
	var back := Button.new()
	back.name = "Back"
	back.text = "BACK"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(120, 44)
	LootUI.style_button(back, 20)
	back.pressed.connect(close)
	bar.add_child(back)
	_area = Control.new()
	_area.name = "Tree"
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.clip_contents = true
	_area.draw.connect(_draw_lines)
	_area.resized.connect(_layout)
	rows.add_child(_area)
	for key: String in BRANCHES:
		var head := _label(15, HudStyle.INK)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.custom_minimum_size = Vector2(170, 0)
		_area.add_child(head)
		_heads[key] = head
		var list: Array[Button] = []
		for i in _count(key):
			var node := Button.new()
			node.name = "%s_%d" % [key, i]
			node.focus_mode = Control.FOCUS_NONE
			node.custom_minimum_size = Vector2(NODE, NODE)
			node.size = Vector2(NODE, NODE)
			node.add_theme_font_size_override("font_size", 16)
			node.pressed.connect(func() -> void: buy(key, i))
			node.mouse_entered.connect(func() -> void: _describe(key, i))
			_area.add_child(node)
			list.append(node)
		_nodes[key] = list
	_root = Button.new()
	_root.name = "Root"
	_root.focus_mode = Control.FOCUS_NONE
	_root.size = Vector2(200, 64)
	_root.add_theme_font_size_override("font_size", 18)
	_root.mouse_entered.connect(func() -> void: _info.text = _level_text())
	_area.add_child(_root)
	_downsides = _label(15, HudStyle.BLOOD)
	_downsides.name = "Downsides"
	_downsides.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_area.add_child(_downsides)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	rows.add_child(foot)
	_info = _label(17, HudStyle.INK_DIM)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(0, 48)
	foot.add_child(_info)
	_reset = Button.new()
	_reset.name = "Reset"
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.custom_minimum_size = Vector2(0, 44)
	LootUI.style_button(_reset, 17)
	_reset.pressed.connect(func() -> void:
		screen.reset_points()
		refresh())
	foot.add_child(_reset)


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## How many nodes a branch has (the passive's first is rank 1, always owned).
static func _count(key: String) -> int:
	if key == "p":
		return 3
	return Characters.UPSIDE_MAX


func open() -> void:
	visible = true
	_info.text = "Points are shared by all your characters. Buy a branch from the bottom up."
	refresh()
	_layout.call_deferred()


func close() -> void:
	visible = false
	screen.refresh()


func _id() -> String:
	return str(screen.showing)


func _unlocked() -> bool:
	return screen._unlocked(_id())


## How many nodes of `key` are bought (the passive's rank 1 counts).
func _owned(c: Dictionary, key: String) -> int:
	return Characters.passive_rank(c) if key == "p" else int(c["spent"].get(key, 0))


func refresh() -> void:
	var state := Profile.characters
	var id := _id()
	var info: Dictionary = Characters.LIST[id]
	var c := Characters.char_of(state, id)
	_title.text = "%s  SKILL TREE" % info["name"]
	_points.text = "%d POINTS LEFT" % Characters.points_left(state)
	_root.text = "%s\nLEVEL %d" % [info["name"], Characters.level(state, id)]
	_style(_root, HudStyle.FACE_HI, HudStyle.BRASS)
	var downs: Array[String] = []
	for index in [2, 3]:
		var value := Characters.trait_value(id, c, index)
		downs.append("%s %s%.1f%%" % [Characters.STAT_NAMES[str(info["traits"][index][0])], "+" if value >= 0.0 else "", value * 100.0])
	_downsides.text = "DOWNSIDES (grow with level)\n" + "\n".join(downs)
	for key: String in BRANCHES:
		var owned := _owned(c, key)
		(_heads[key] as Label).text = _head_text(id, c, key)
		var color: Color = HudStyle.LIFE if key.begins_with("u") else HudStyle.BRASS
		var list: Array = _nodes[key]
		for i in list.size():
			var node: Button = list[i]
			node.text = _node_text(key, i)
			var next := i == owned and _unlocked() and Characters.can_spend(state, c, key)
			if i < owned:
				_style(node, color.darkened(0.35), color)
			elif next:
				_style(node, HudStyle.FACE, HudStyle.HAZARD)
			else:
				_style(node, HudStyle.FACE_DK, HudStyle.FACE_HI)
			node.set_meta("state", "owned" if i < owned else ("next" if next else "locked"))
	_reset.text = "RESET POINTS  %s" % ItemDB.money(Characters.RESET_COST)
	_reset.disabled = not _unlocked() or Characters.char_spent(c) == 0 or Profile.money < Characters.RESET_COST
	_layout.call_deferred()


func _node_text(key: String, i: int) -> String:
	if key == "p":
		return "R%d" % (i + 1)
	return "+2%"


func _stat(id: String, key: String) -> String:
	var index := {"u0": 0, "u1": 1}[key] as int
	return str(Characters.STAT_NAMES[str(Characters.LIST[id]["traits"][index][0])])


func _head_text(id: String, c: Dictionary, key: String) -> String:
	if key == "p":
		var passive: Dictionary = Characters.PASSIVES[Characters.LIST[id]["passive"]]
		return "%s\n%s" % [str(passive["name"]).to_upper(), passive["rank_text"][Characters.passive_rank(c) - 1]]
	var index := {"u0": 0, "u1": 1}[key] as int
	var value := Characters.trait_value(id, c, index)
	return "%s\n%s%.1f%%" % [_stat(id, key), "+" if value >= 0.0 else "", value * 100.0]


## The bottom text for a node: what it does, what it costs.
func _describe(key: String, i: int) -> void:
	var id := _id()
	var c := Characters.char_of(Profile.characters, id)
	var owned := _owned(c, key)
	if key == "p":
		var passive: Dictionary = Characters.PASSIVES[Characters.LIST[id]["passive"]]
		_info.text = "%s rank %d: %s %s%s" % [passive["name"], i + 1, passive["about"], passive["rank_text"][i],
			"" if i == 0 else ("  (owned)" if i < owned else "  Costs %d points." % Characters.PASSIVE_RANK_COST)]
		return
	var index := {"u0": 0, "u1": 1}[key] as int
	var trial := c.duplicate(true)
	trial["spent"][key] = i + 1
	var after := Characters.trait_value(id, trial, index)
	var what := "2% more"
	_info.text = "%s: %s, %s%.1f%% at this step.%s" % [_stat(id, key), what, "+" if after >= 0.0 else "", after * 100.0,
		"  (owned)" if i < owned else "  Costs 1 point."]


## Clicking a node buys it when it is the next one in its branch.
func buy(key: String, i: int) -> void:
	var c := Characters.char_of(Profile.characters, _id())
	if not _unlocked():
		_info.text = "Unlock %s first." % Characters.LIST[_id()]["name"]
		return
	if i < _owned(c, key):
		return
	if i > _owned(c, key):
		_info.text = "Buy the ones below it first."
		return
	if not Characters.can_spend(Profile.characters, c, key):
		_info.text = "Not enough points. Earn them at levels 10 and 20 and on expedition escapes."
		return
	screen.spend(key)
	refresh()
	_describe(key, i)


func _style(button: Button, fill: Color, edge: Color) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = fill.lightened(0.12) if state == "hover" else fill
		box.border_color = edge
		box.set_border_width_all(3)
		box.set_corner_radius_all(4)
		button.add_theme_stylebox_override(state, box)
	button.add_theme_color_override("font_color", HudStyle.INK)
	button.add_theme_color_override("font_hover_color", HudStyle.INK)


## Places the nodes: the character at the bottom, each branch a column going up.
func _layout() -> void:
	var w := _area.size.x
	var h := _area.size.y
	if w <= 0.0 or h <= 0.0:
		return
	_root.position = Vector2(w * 0.5 - _root.size.x / 2.0, h - _root.size.y - 6.0)
	_downsides.size = Vector2(minf(w * 0.5 - _root.size.x / 2.0 - 24.0, 300.0), 0)
	_downsides.position = Vector2(w * 0.5 + _root.size.x / 2.0 + 16.0, h - 80.0)
	var bottom := _root.position.y - 40.0
	var step := clampf((bottom - 60.0) / float(Characters.UPSIDE_MAX), 50.0, 90.0)
	for k in BRANCHES.size():
		var key: String = BRANCHES[k]
		var x: float = w * COLUMNS[k]
		var list: Array = _nodes[key]
		for i in list.size():
			(list[i] as Button).position = Vector2(x - NODE / 2.0, bottom - NODE - i * step)
		var head: Label = _heads[key]
		head.size = Vector2(170, 0)
		var top := (list[list.size() - 1] as Button).position.y
		head.position = Vector2(x - 85.0, maxf(top - head.get_combined_minimum_size().y - 6.0, 0.0))
	_area.queue_redraw()


func _draw_lines() -> void:
	var c := Characters.char_of(Profile.characters, _id())
	var from := _root.position + Vector2(_root.size.x / 2.0, 0.0)
	for key: String in BRANCHES:
		var list: Array = _nodes[key]
		var owned := _owned(c, key)
		var first: Button = list[0]
		var start := first.position + Vector2(NODE / 2.0, NODE)
		var bend := Vector2(start.x, from.y - 18.0)
		var color := LINE_ON if owned > 0 else LINE_OFF
		_area.draw_polyline(PackedVector2Array([from, Vector2(from.x, bend.y), bend, start]), color, 4.0)
		for i in range(1, list.size()):
			var below: Button = list[i - 1]
			var above: Button = list[i]
			_area.draw_line(below.position + Vector2(NODE / 2.0, 0.0), above.position + Vector2(NODE / 2.0, NODE),
				LINE_ON if i < owned else LINE_OFF, 4.0)


func _level_text() -> String:
	var id := _id()
	return "%s, level %d. Traits grow with the level; the points you spend add on top." % [Characters.LIST[id]["name"], Characters.level(Profile.characters, id)]
