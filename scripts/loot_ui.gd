class_name LootUI
extends Control
## Backpack screen (Tab), and the side-by-side container + backpack screen when you open loot (E).
## The game keeps running while this is open, so loot fast.

const PICKUP_SOUND := preload("res://audio/mag_in.wav")

var player: Player
var container: LootContainer = null

var _container_panel: Control
var _container_title: Label
var _container_list: VBoxContainer
var _bag_title: Label
var _bag_info: Label
var _bag_list: VBoxContainer


func _init(owner_player: Player) -> void:
	player = owner_player
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _ready() -> void:
	player.inventory.changed.connect(_refresh)


func open_for(target: LootContainer) -> void:
	container = target
	visible = true
	player.interactor.blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	container = null
	player.interactor.blocked = false
	if not player.controls_locked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not visible:
		return
	if player.controls_locked():
		close()
		return
	# Walked away (or the bag got emptied by someone else): keep the backpack open, drop the container.
	if container != null and (not is_instance_valid(container) or container.global_position.distance_to(player.global_position) > 3.5):
		container = null
		_refresh()


func _refresh() -> void:
	if not visible:
		return
	var has_container := container != null and is_instance_valid(container)
	_container_panel.visible = has_container
	_clear(_container_list)
	if has_container:
		_container_title.text = container.display_name.to_upper()
		if container.items.is_empty():
			_container_list.add_child(_dim_label("Empty"))
		for i in container.items.size():
			var id := container.items[i]
			var fits := ItemDB.kind(id) == "ammo" or player.inventory.can_fit(id)
			_container_list.add_child(_item_row(id, [["Take" if fits else "No space", _take.bind(i), not fits]]))

	var inv := player.inventory
	_bag_title.text = "BACKPACK"
	_bag_info.text = "%d / %d slots   ·   %s" % [inv.used_slots(), inv.capacity, ItemDB.money(inv.total_value())]
	_clear(_bag_list)
	if inv.items.is_empty():
		_bag_list.add_child(_dim_label("Nothing yet. Go find something."))
	for i in inv.items.size():
		var id := inv.items[i]
		var buttons := []
		if ItemDB.kind(id) == "heal":
			buttons.append(["Use", _use.bind(i), player.is_healing()])
		buttons.append(["Put in" if has_container else "Drop", _put.bind(i), false])
		_bag_list.add_child(_item_row(id, buttons))


func _take(index: int) -> void:
	if container == null or index >= container.items.size():
		return
	var id := container.items[index]
	if ItemDB.kind(id) == "ammo":
		player.gun.reserve += int(ItemDB.item(id)["amount"])
	elif not player.inventory.add(id):
		return
	container.items.remove_at(index)
	Effects.sound(player.get_tree().current_scene, PICKUP_SOUND, -8.0)
	if container.remove_when_empty and container.items.is_empty():
		container.queue_free()
		container = null
	_refresh()


func _put(index: int) -> void:
	var id := player.inventory.remove_at(index)
	if container != null and is_instance_valid(container):
		container.items.append(id)
	else:
		var drop_pos := player.global_position - player.global_basis.z * 0.8
		var contents: Array[String] = [id]
		LootContainer.spawn_bag(player.get_tree().current_scene, drop_pos, "Dropped Items", contents)
	_refresh()


func _use(index: int) -> void:
	player.use_item(index)
	_refresh()


# --- UI building -------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	center.add_child(root)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	root.add_child(columns)

	var container_parts := _column(columns)
	_container_panel = container_parts[0]
	_container_title = container_parts[1]
	(container_parts[2] as Label).text = "Click Take to grab it"
	_container_list = container_parts[3]

	var bag_parts := _column(columns)
	_bag_title = bag_parts[1]
	_bag_info = bag_parts[2]
	_bag_list = bag_parts[3]

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)
	var hint := _dim_label("Tab / E to close  ·  H to heal  ·  the raid doesn't pause!")
	footer.add_child(hint)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	footer.add_child(close_button)


## Returns [panel, title, subtitle, list].
func _column(parent: Control) -> Array:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 440)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	var subtitle := _dim_label("")
	vbox.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return [panel, title, subtitle, list]


## buttons: Array of [text, Callable, disabled]
func _item_row(id: String, buttons: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)

	var item_name := Label.new()
	item_name.text = ItemDB.display_name(id)
	item_name.add_theme_color_override("font_color", ItemDB.color(id))
	item_name.add_theme_font_size_override("font_size", 18)
	info.add_child(item_name)

	var details := _dim_label(_details(id))
	info.add_child(details)

	for spec in buttons:
		var button := Button.new()
		button.text = spec[0]
		button.disabled = spec[2]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(76, 0)
		button.pressed.connect(spec[1])
		row.add_child(button)
	return row


func _details(id: String) -> String:
	var data := ItemDB.item(id)
	var rarity: String = data["rarity"]
	match ItemDB.kind(id):
		"ammo":
			return "%s · +%d rounds · no space" % [rarity.capitalize(), int(data["amount"])]
		"heal":
			return "%s · heals %d · %d slot%s" % [rarity.capitalize(), int(data["heal"]), ItemDB.slots(id), "" if ItemDB.slots(id) == 1 else "s"]
	return "%s · %s · %d slot%s" % [rarity.capitalize(), ItemDB.money(ItemDB.value(id)), ItemDB.slots(id), "" if ItemDB.slots(id) == 1 else "s"]


func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.65)
	label.add_theme_font_size_override("font_size", 14)
	return label


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
