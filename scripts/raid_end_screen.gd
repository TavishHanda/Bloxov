class_name RaidEndScreen
extends Control
## Shown when the raid ends: extracted, killed, or missing in action.

var raid: Raid

var _title: Label
var _subtitle: Label
var _loot: Label
var _value: Label
var _session: Label


func _init(owner_raid: Raid) -> void:
	raid = owner_raid
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func show_result(kills: int) -> void:
	var extracted := raid.result == "extracted"
	match raid.result:
		"extracted":
			_title.text = "EXTRACTED"
			_title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.5))
			_subtitle.text = "You made it out via %s." % raid.extract_used
		"mia":
			_title.text = "MISSING IN ACTION"
			_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
			_subtitle.text = "The raid timer ran out. Everything you carried is gone."
		_:
			_title.text = "KILLED IN ACTION"
			_title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
			_subtitle.text = "Everything you carried is gone."

	var names: PackedStringArray = []
	for id in raid.loot_items:
		names.append(ItemDB.display_name(id))
	_loot.text = "Loot: " + (", ".join(names) if not names.is_empty() else "nothing")
	_value.text = ("Kept: %s" if extracted else "Lost: %s") % ItemDB.money(raid.loot_value)
	_value.add_theme_color_override("font_color", Color(0.45, 1.0, 0.5) if extracted else Color(1.0, 0.4, 0.35))
	_session.text = "Kills: %d\n\nThis session: %d raids · %d extracts · %s extracted\n(Stash coming in Phase 3)" % [
		kills, Raid.session_raids, Raid.session_extracts, ItemDB.money(Raid.session_value)]
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	_title = _label(44, vbox)
	_subtitle = _label(16, vbox)
	_loot = _label(16, vbox)
	_value = _label(30, vbox)
	_session = _label(14, vbox)
	_session.modulate = Color(1, 1, 1, 0.7)

	var button := Button.new()
	button.text = "NEXT RAID"
	button.custom_minimum_size = Vector2(0, 50)
	button.add_theme_font_size_override("font_size", 22)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	vbox.add_child(button)


func _label(font_size: int, parent: Control) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
