class_name RaidEndScreen
extends Control
## Shown when the raid ends: extracted, killed, or missing in action.
## Look (0.8.10, "Ammo Can"): a gunmetal plate with the result as a big ink stamp (green EXTRACTED, amber MISSING IN
## ACTION, red KILLED IN ACTION), how you got there, the loot, what it was worth on a brass tag ("KEPT", or "LOST" on
## a red one), your kills and profile stats as stenciled chips, and a gunmetal BACK TO HIDEOUT button.
## Dead online with a teammate still in the raid (0.9.5): a SPECTATE <NAME> button too (see Spectator).

## The player chose to watch a teammate (peer id).
signal spectate_pressed(peer: int)

const WIDTH := 600.0
const AMBER := Color("f0a03a")

var raid: Raid

var _panel: PanelContainer
var _stamp: Control
var _subtitle: Label
var _loot_title: Label
var _loot: Label
var _tag: Control
var _kept: Label
var _chips: HBoxContainer
var _spectate: Button
var _spectate_peer := 0

var _stamp_text := ""
var _stamp_color := HudStyle.EXTRACT
var _tag_text := ""
var _extracted := false


func _init(owner_raid: Raid) -> void:
	raid = owner_raid
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func show_result(kills: int) -> void:
	_extracted = raid.result == "extracted"
	match raid.result:
		"extracted":
			_stamp_text = "EXTRACTED"
			_stamp_color = HudStyle.EXTRACT
			_subtitle.text = "You made it out via %s." % raid.extract_used
		"mia":
			_stamp_text = "MISSING IN ACTION"
			_stamp_color = AMBER
			_subtitle.text = "The raid timer ran out. Everything you carried is gone."
		_:
			_stamp_text = "KILLED IN ACTION"
			_stamp_color = HudStyle.BLOOD
			_subtitle.text = "Everything you carried is gone."

	_loot.text = ", ".join(raid.loot_summary) if not raid.loot_summary.is_empty() else "nothing"
	_tag_text = ("KEPT  %s" if _extracted else "LOST  %s") % ItemDB.money(raid.loot_value)
	_kept.text = "Your gear is waiting in the hideout." if _extracted else "Only your secure pocket made it back."
	for chip in _chips.get_children():
		chip.queue_free()
	for entry in [["KILLS", str(kills)], ["MONEY", ItemDB.money(Profile.money)], ["RAIDS", str(int(Profile.stats["raids"]))],
			["EXTRACTS", str(int(Profile.stats["extracts"]))], ["DEATHS", str(int(Profile.stats["deaths"]))]]:
		_chips.add_child(_chip(entry[0], entry[1]))
	_spectate_peer = 0 if _extracted else Spectator.watchable_teammate()
	_spectate.visible = _spectate_peer != 0
	_spectate.text = "SPECTATE %s" % String(Network.main.names.get(_spectate_peer, "")).to_upper()
	_stamp.queue_redraw()
	_tag.queue_redraw()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## What the screen says, for the tests: {stamp, value, spectate (the button's text, "" when hidden)}.
func summary() -> Dictionary:
	return {"stamp": _stamp_text, "value": _tag_text, "spectate": _spectate.text if _spectate.visible else ""}


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_panel.draw.connect(func() -> void: HudStyle.draw_plate(_panel, Rect2(Vector2.ZERO, _panel.size), HudStyle.OUTLINE, HudStyle.FACE, 4.0))
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# The result, stamped.
	_stamp = Control.new()
	_stamp.custom_minimum_size = Vector2(0, 76)
	_stamp.draw.connect(_draw_stamp)
	vbox.add_child(_stamp)
	_subtitle = _text(vbox, 20, HudStyle.INK_DIM)

	vbox.add_child(_groove())
	_loot_title = _text(vbox, 20, HudStyle.INK_DIM)
	_loot_title.text = "LOOT"
	_loot = _text(vbox, 20, HudStyle.INK)

	# What it was worth, on a tag.
	_tag = Control.new()
	_tag.custom_minimum_size = Vector2(0, 54)
	_tag.draw.connect(_draw_tag)
	vbox.add_child(_tag)
	_kept = _text(vbox, 20, HudStyle.INK_DIM)

	vbox.add_child(_groove())
	_chips = HBoxContainer.new()
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.add_theme_constant_override("separation", 8)
	vbox.add_child(_chips)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)
	_spectate = Button.new()
	_spectate.custom_minimum_size = Vector2(0, 52)
	_spectate.focus_mode = Control.FOCUS_NONE
	_spectate.visible = false
	LootUI.style_button(_spectate, 30)
	_spectate.pressed.connect(func() -> void: spectate_pressed.emit(_spectate_peer))
	vbox.add_child(_spectate)
	var button := Button.new()
	button.text = "BACK TO HIDEOUT"
	button.custom_minimum_size = Vector2(0, 52)
	button.focus_mode = Control.FOCUS_NONE
	LootUI.style_button(button, 30)
	button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/hideout.tscn"))
	vbox.add_child(button)


## The result as an ink stamp: a double border and the words, in the result's color, a bit worn.
func _draw_stamp() -> void:
	if _stamp_text == "":
		return
	var size := 50
	var f := HudStyle.font(size)
	var text_w := HudStyle.text_width(_stamp_text, size, f) - 1.0
	var box := Rect2(Vector2(roundf((_stamp.size.x - text_w) * 0.5) - 22, 4), Vector2(text_w + 44, 68))
	var ink := Color(_stamp_color, 0.95)
	_stamp.draw_rect(box, Color(_stamp_color, 0.08))
	_stamp.draw_rect(box, ink, false, 4.0)
	_stamp.draw_rect(box.grow(-8), Color(ink, 0.75), false, 2.0)
	HudStyle.draw_centered(_stamp, _stamp_text, box, size, ink, f)
	# Worn ink: a few gaps punched in the border, the same every time.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_stamp_text)
	for i in 10:
		var on_top := i % 2 == 0
		var x := rng.randf_range(box.position.x + 10, box.end.x - 14)
		var y := box.position.y - 2 if on_top else box.end.y - 2
		_stamp.draw_rect(Rect2(Vector2(roundf(x), y), Vector2(rng.randi_range(3, 7), 4)), HudStyle.FACE)


## The loot's value on a tag: brass "KEPT" when you made it out, red "LOST" when you didn't.
func _draw_tag() -> void:
	if _tag_text == "":
		return
	var size := 40
	var text_w := HudStyle.text_width(_tag_text, size) - 1.0
	var rect := Rect2(Vector2(roundf((_tag.size.x - text_w) * 0.5) - 20, 2), Vector2(text_w + 40, 48))
	var face := HudStyle.BRASS if _extracted else HudStyle.BLOOD
	HudStyle.draw_block(_tag, rect, face, face.lightened(0.3), face.darkened(0.4), 3.0)
	HudStyle.draw_rivet(_tag, rect.position + Vector2(7, 7))
	HudStyle.draw_rivet(_tag, Vector2(rect.end.x - 10, rect.position.y + 7))
	HudStyle.draw_centered(_tag, _tag_text, rect, size, HudStyle.DEEP if _extracted else HudStyle.INK, null, not _extracted)


## A stat chip: a small sunk-in box with the name stenciled over the number.
func _chip(title: String, value: String) -> Control:
	var chip := Control.new()
	var width := maxf(HudStyle.text_width(value, 20), HudStyle.text_width(title, 8, HudStyle.label_font())) + 20.0
	chip.custom_minimum_size = Vector2(maxf(width, 70.0), 44)
	chip.draw.connect(func() -> void:
		var rect := Rect2(Vector2.ZERO, chip.size)
		HudStyle.draw_well(chip, rect)
		HudStyle.draw_centered(chip, title, Rect2(0, 4, chip.size.x, 12), 8, HudStyle.INK_DIM, HudStyle.label_font())
		HudStyle.draw_centered(chip, value, Rect2(0, 18, chip.size.x, 22), 20, HudStyle.INK))
	return chip


## A thin groove across the panel (dark line over a light one).
func _groove() -> Control:
	var groove := Control.new()
	groove.custom_minimum_size = Vector2(0, 2)
	groove.draw.connect(func() -> void:
		groove.draw_rect(Rect2(0, 0, groove.size.x, 1), HudStyle.FACE_DK)
		groove.draw_rect(Rect2(0, 1, groove.size.x, 1), HudStyle.FACE_HI))
	return groove


## A centered, wrapping line in the HUD's pixel font (letter-spaced, so mixed case reads cleanly).
func _text(parent: Control, size: int, color: Color) -> Label:
	var label := Label.new()
	HudStyle.style_label(label, size, color)
	label.add_theme_font_override("font", HudStyle.spaced_font(size))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
