class_name MapSelect
extends Control
## The war table's map (0.33.9, owner: "a huge map where they can select the map"): a full-screen chart of the
## Bloxov border region with a marker for each raid map (RaidMap.MAPS). Tap a marker to pick it; the hideout's
## START RAID button then says which map you're on. Solo it sets the map straight away; online the party's leader
## picks (Hideout.pick_map sends it to the server) and everyone else sees the leader's choice.

signal picked(index: int)
signal closed

## What the chart says about each map (the same order as RaidMap.MAPS): where its marker sits on the chart (0..1),
## its tag line and its facts.
const INFO := [
	{"at": Vector2(0.34, 0.56), "tag": "The border town and the hills round it.",
		"facts": ["10 MINUTE RAIDS", "UP TO 6 PLAYERS", "BOSS: BON"]},
	{"at": Vector2(0.71, 0.33), "tag": "The Landing, the drillship Leviathan, and Site Zero under the sea.",
		"facts": ["15 MINUTE RAIDS", "UP TO 6 PLAYERS", "BOSS: ZERO", "THE HARDEST RAID"]},
]
const SEA := Color("1b2b36")
const LAND := Color("3a3d33")
const GRID := Color(1, 1, 1, 0.05)

## The map picked now, and whether it can be changed here (false: a party member, or in the queue).
var selected := 0
var can_pick := true
var locked_note := ""

var _markers: Array[Button] = []
var _title: Label
var _note: Label
var _facts: Label
var _back: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title = Label.new()
	_title.text = "WAR TABLE: CHOOSE YOUR RAID"
	HudStyle.style_label(_title, 34, HudStyle.BRASS_HI)
	_title.position = Vector2(40, 24)
	add_child(_title)
	_note = Label.new()
	HudStyle.style_label(_note, 20, HudStyle.INK_DIM)
	_note.position = Vector2(40, 68)
	add_child(_note)
	_facts = Label.new()
	HudStyle.style_label(_facts, 22, HudStyle.INK)
	add_child(_facts)
	for i in RaidMap.MAPS.size():
		var marker := Button.new()
		marker.name = "Map%d" % i
		marker.text = String(RaidMap.MAPS[i][0])
		marker.focus_mode = Control.FOCUS_NONE
		marker.custom_minimum_size = Vector2(240, 64)
		marker.pressed.connect(_pick.bind(i))
		add_child(marker)
		_markers.append(marker)
	var back := Button.new()
	back.name = "Back"
	back.text = "BACK TO THE TABLE"
	back.focus_mode = Control.FOCUS_NONE
	LootUI.style_button(back, 24, HudStyle.HAZARD)
	back.pressed.connect(close)
	back.custom_minimum_size = Vector2(260, 56)
	add_child(back)
	_back = back
	resized.connect(refresh)
	refresh()


func open(index: int, pickable: bool, note := "") -> void:
	selected = clampi(index, 0, RaidMap.MAPS.size() - 1)
	can_pick = pickable
	locked_note = note
	visible = true
	move_to_front()
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _pick(index: int) -> void:
	if not can_pick or index == selected:
		return
	selected = index
	UISounds.play(self, UISounds.CLICK, -10.0)
	picked.emit(index)
	refresh()


## Lays the markers out on the chart and shows the picked map's facts.
func refresh() -> void:
	if _markers.is_empty():
		return
	for i in _markers.size():
		var marker := _markers[i]
		var on := i == selected
		LootUI.style_button(marker, 28, HudStyle.HAZARD if on else HudStyle.FACE)
		marker.disabled = not can_pick and not on
		marker.position = (size * (INFO[i]["at"] as Vector2) - marker.custom_minimum_size * Vector2(0.5, 1.6)).round()
	var info: Dictionary = INFO[selected]
	_note.text = locked_note if not can_pick else "Tap a place on the map. START RAID takes you there."
	_facts.text = "%s\n%s\n\n%s" % [RaidMap.MAPS[selected][0], info["tag"], "\n".join(info["facts"])]
	_facts.position = Vector2(40, size.y - 230)
	_back.position = size - Vector2(300, 84)
	queue_redraw()


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, SEA)
	# the land: the west of the chart, with a ragged coast, and an island off it
	var coast := PackedVector2Array([Vector2(0, 0)])
	for p in [Vector2(0.52, 0.0), Vector2(0.57, 0.12), Vector2(0.53, 0.24), Vector2(0.6, 0.36), Vector2(0.56, 0.5),
			Vector2(0.62, 0.62), Vector2(0.55, 0.78), Vector2(0.6, 0.9), Vector2(0.54, 1.0), Vector2(0.0, 1.0)]:
		coast.append(size * p)
	draw_colored_polygon(coast, LAND)
	draw_polyline(coast, HudStyle.TAPE, 2.0)
	var step := maxf(size.y / 12.0, 24.0)
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID, 1.0)
		x += step
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID, 1.0)
		y += step
	# each map's place: a ring, filled for the one picked, and a line up to its name
	for i in INFO.size():
		var at := size * (INFO[i]["at"] as Vector2)
		var on := i == selected
		var colour := HudStyle.HAZARD if on else HudStyle.TAPE
		draw_arc(at, 18.0 if on else 12.0, 0.0, TAU, 32, colour, 3.0)
		if on:
			draw_circle(at, 8.0, colour)
			draw_arc(at, 30.0, 0.0, TAU, 40, Color(colour, 0.4), 2.0)
		draw_line(at + Vector2(0, -20), at + Vector2(0, -38), colour, 2.0)
	draw_rect(full.grow(-8.0), HudStyle.BRASS_DK, false, 2.0)
