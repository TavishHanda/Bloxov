class_name EquipSlotView
extends Control
## One equipment slot (Primary / Secondary / Armor / Backpack) in the inventory screen.
## Drag an item onto it to equip, drag it out to unequip, right-click for the menu.

var slot: String
var inventory: Inventory
var ui: LootUI

var _label: Label
var _detail: Label


func _init(slot_name: String, owner_inventory: Inventory, owner_ui: LootUI, cells: Vector2i) -> void:
	slot = slot_name
	inventory = owner_inventory
	ui = owner_ui
	custom_minimum_size = Vector2(cells) * GridView.CELL
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.position = Vector2(6, 4)
	_label.size = Vector2(size.x - 12, size.y - 24)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 11)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_detail.position = Vector2(4, size.y - 19)
	_detail.size = Vector2(size.x - 9, 16)
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail)
	mouse_entered.connect(_on_hover)


func _ready() -> void:
	inventory.equipment_changed.connect(rebuild)
	rebuild()


func _exit_tree() -> void:
	if inventory.equipment_changed.is_connected(rebuild):
		inventory.equipment_changed.disconnect(rebuild)


## What to show: nothing while it's being dragged out.
func shown_stack() -> ItemStack:
	var stack := inventory.equipped(slot)
	if stack == ui.drag_stack:
		return null
	return stack


func rebuild() -> void:
	var stack := shown_stack()
	if stack == null:
		_label.text = slot.to_upper()
		_label.modulate = Color(1, 1, 1, 0.35)
		_detail.text = ""
	else:
		_label.text = slot.to_upper() + "\n" + ItemDB.display_name(stack.id)
		_label.modulate = Color.WHITE
		match ItemDB.kind(stack.id):
			"weapon":
				_detail.text = "%d/%d" % [stack.loaded, int(ItemDB.item(stack.id)["mag"])]
			"armor":
				_detail.text = "-%d%%" % roundi(float(ItemDB.item(stack.id)["reduction"]) * 100.0)
			"backpack":
				var grid: Array = ItemDB.item(stack.id)["grid"]
				_detail.text = "%d×%d" % [grid[0], grid[1]]
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, GridView.BG_COLOR)
	var stack := shown_stack()
	if stack != null:
		var color := ItemDB.color(stack.id)
		draw_rect(rect.grow(-2), color.darkened(0.72))
		draw_rect(rect.grow(-2), color, false, 2.0)
	else:
		draw_rect(rect.grow(-1), Color(1, 1, 1, 0.12), false, 1.0)
	if ui.drag_stack != null and ui.hover_view == self:
		draw_rect(rect, GridView.DROP_OK if ui.can_drop_on_slot(slot) else GridView.DROP_BAD)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var stack := inventory.equipped(slot)
	if stack == null:
		return
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_LEFT:
		if button.shift_pressed:
			ui.unequip_to_inventory(slot)
		else:
			ui.start_drag_from_slot(slot)
		accept_event()
	elif button.button_index == MOUSE_BUTTON_RIGHT:
		ui.open_slot_menu(slot)
		accept_event()


func _on_hover() -> void:
	var stack := inventory.equipped(slot)
	if stack != null:
		ui.show_info(stack)
