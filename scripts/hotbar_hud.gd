class_name HotbarHUD
extends HBoxContainer
## Bottom-center hotbar: 1 = primary, 2 = secondary (active one highlighted), 3-6 = bound items (heals etc).

const SLOT_SIZE := Vector2(92, 46)

var player: Player
var _panels: Array[PanelContainer] = []
var _keys: Array[Label] = []
var _names: Array[Label] = []
var _counts: Array[Label] = []
var _styles: Array[StyleBoxFlat] = []


func _init(owner_player: Player) -> void:
	player = owner_player
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_top = -12.0
	offset_bottom = -12.0
	for i in 2 + Inventory.HOTBAR_SIZE:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = SLOT_SIZE
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.45)
		style.set_border_width_all(2)
		style.border_color = Color(1, 1, 1, 0.15)
		style.set_content_margin_all(4)
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", -2)
		panel.add_child(box)
		var top := HBoxContainer.new()
		box.add_child(top)
		var key := _label(11, Color(1, 1, 1, 0.55))
		key.text = str(i + 1)
		top.add_child(key)
		var count := _label(11, Color(1, 1, 1, 0.8))
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		top.add_child(count)
		var item_name := _label(13, Color.WHITE)
		item_name.clip_text = true
		box.add_child(item_name)
		_panels.append(panel)
		_keys.append(key)
		_names.append(item_name)
		_counts.append(count)
		_styles.append(style)


func _process(_delta: float) -> void:
	var inventory := player.inventory
	var gun := player.gun
	for i in _panels.size():
		var text := ""
		var count := ""
		var color := Color(1, 1, 1, 0.15)
		if i < 2:
			var slot := "primary" if i == 0 else "secondary"
			var weapon := inventory.equipped(slot)
			if weapon != null:
				text = ItemDB.short_name(weapon.id)
				var ammo_id: String = ItemDB.item(weapon.id)["ammo"]
				count = "%d/%d" % [weapon.loaded, inventory.count_of(ammo_id)]
				color = ItemDB.color(weapon.id) if gun.weapon == weapon else Color(1, 1, 1, 0.3)
		else:
			var id := inventory.hotbar[i - 2]
			if id != "":
				text = ItemDB.short_name(id)
				var have := inventory.count_of(id)
				count = "x%d" % have
				color = ItemDB.color(id) if have > 0 else Color(1, 0.3, 0.25, 0.5)
		_names[i].text = text
		_counts[i].text = count
		_styles[i].border_color = color


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
