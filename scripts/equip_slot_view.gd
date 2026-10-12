class_name EquipSlotView
extends Control
## One equipment slot (Primary / Secondary / Armor / Backpack) in the inventory screen.
## Drag an item onto it to equip, drag it out to unequip, right-click for the menu.
## An equipped gun shows its attachment slots along the bottom (0.15.17, owner): a small picture of what's on it,
## drop an attachment on the gun to fit it, click (or tap) a filled slot to take that attachment off.

## Attachment slot boxes: size and gap (pixels).
const PART_SIZE := 26.0
const PART_GAP := 3.0
## What an empty attachment slot says.
const SLOT_NAMES := {"scope": "SCP", "sight": "SGT", "barrel": "BRL", "grip": "GRP", "mag": "MAG"}

var slot: String
var inventory: Inventory
var ui: LootUI

var _label: Label
var _detail: Label
## The attachment slot under the mouse ("" = none), for its info line.
var _hover_part := ""


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
	HudStyle.style_label(_detail, 20)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_detail.position = Vector2(4, size.y - 22)
	_detail.size = Vector2(size.x - 9, 18)
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(func() -> void:
		_hover_part = ""
		queue_redraw())


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
				_detail.text = "%d/%d" % [stack.loaded, int(ItemDB.weapon_stats(stack)["mag"])]
			"armor", "helmet":
				_detail.text = ("%d/%d" % [stack.durability, ItemDB.max_durability(stack.id)] if ItemDB.max_durability(stack.id) > 0
					else "-%d%%" % roundi(ItemDB.reduction(stack) * 100.0))
			"backpack":
				var grid: Array = ItemDB.item(stack.id)["grid"]
				_detail.text = "%d×%d" % [grid[0], grid[1]]
	# The ammo count sits above the attachment slots when there are some.
	var has_parts := not _part_rects().is_empty()
	_detail.position = Vector2(4, size.y - 22 - (PART_SIZE + 4.0 if has_parts else 0.0))
	queue_redraw()


## The equipped gun's attachment slots: [[slot name, Rect2], ...] along the bottom left (none for anything else).
func _part_rects() -> Array:
	var stack := shown_stack()
	var rects := []
	if stack == null or ItemDB.kind(stack.id) != "weapon":
		return rects
	var x := 4.0
	for part_slot: String in ItemDB.attachment_slots(stack.id):
		rects.append([part_slot, Rect2(x, size.y - PART_SIZE - 4.0, PART_SIZE, PART_SIZE)])
		x += PART_SIZE + PART_GAP
	return rects


func _part_at(point: Vector2) -> String:
	for entry: Array in _part_rects():
		if (entry[1] as Rect2).has_point(point):
			return entry[0]
	return ""


func _draw_parts() -> void:
	var stack := shown_stack()
	var dragged := ui.drag_stack
	var target := ""
	if dragged != null and ui.hover_view == self and stack != null and ui.drag_slot == "":
		target = ItemDB.attachment_slot_for(stack.id, dragged.id)
	var font := ThemeDB.fallback_font
	for entry: Array in _part_rects():
		var part_slot: String = entry[0]
		var rect: Rect2 = entry[1]
		var part: String = stack.attachments.get(part_slot, "")
		draw_rect(rect.grow(1), HudStyle.OUTLINE)
		draw_rect(rect, HudStyle.DEEP)
		if part != "":
			var color := ItemDB.color(part)
			draw_rect(rect.grow(-1), color.darkened(0.7))
			_draw_part_picture(part, rect)
			draw_rect(rect.grow(-1), color, false, 1.0)
		else:
			draw_string(font, Vector2(rect.position.x, rect.get_center().y + 3), SLOT_NAMES.get(part_slot, ""),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 8, Color(1, 1, 1, 0.35))
		if part_slot == target:
			draw_rect(rect, GridView.DROP_OK)
		if part_slot == _hover_part and part != "":
			draw_rect(rect, Color(1, 1, 1, 0.12))


## A little picture of attachment `part` in `rect` (placeholder blocks, like the gun's: GunViewModels.LOOKS).
func _draw_part_picture(part: String, rect: Rect2) -> void:
	var c := rect.get_center()
	var ink := HudStyle.INK
	match part:
		"red_dot":
			draw_rect(Rect2(c + Vector2(-6, -4), Vector2(12, 9)), ink)
			draw_rect(Rect2(c + Vector2(-2, -2), Vector2(4, 4)), HudStyle.BLOOD)
		"scope_4x", "scope_8x":
			var length := 16.0 if part == "scope_4x" else 20.0
			draw_rect(Rect2(c + Vector2(-length / 2, -3), Vector2(length, 6)), ink)
			draw_rect(Rect2(c + Vector2(-length / 2 - 1, -5), Vector2(4, 10)), ink)
			draw_rect(Rect2(c + Vector2(length / 2 - 3, -5), Vector2(4, 10)), ink)
			draw_string(ThemeDB.fallback_font, Vector2(rect.position.x, rect.end.y - 2), "4x" if part == "scope_4x" else "8x",
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 8, HudStyle.BRASS)
		"suppressor":
			draw_rect(Rect2(c + Vector2(-10, -3), Vector2(20, 6)), ink)
		"choke":
			draw_rect(Rect2(c + Vector2(-5, -5), Vector2(10, 10)), HudStyle.COPPER)
			draw_rect(Rect2(c + Vector2(-2, -2), Vector2(4, 4)), HudStyle.DEEP)
		"foregrip":
			draw_rect(Rect2(c + Vector2(-8, -7), Vector2(16, 3)), ink)
			draw_rect(Rect2(c + Vector2(-2, -4), Vector2(5, 11)), HudStyle.COPPER)
		"ext_mag":
			draw_rect(Rect2(c + Vector2(-3, -9), Vector2(7, 18)), ink)
		_:
			draw_rect(Rect2(c + Vector2(-5, -5), Vector2(10, 10)), ink)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect.grow(2), HudStyle.OUTLINE)
	draw_rect(rect, GridView.BG_COLOR)
	var stack := shown_stack()
	if stack != null:
		var color := ItemDB.color(stack.id)
		draw_rect(rect.grow(-2), color.darkened(0.72))
		draw_rect(rect.grow(-2), color, false, 2.0)
	else:
		# Empty: sunk in (shadow along the top and left).
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 2)), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(Vector2.ZERO, Vector2(2, size.y)), Color(0, 0, 0, 0.5))
	if ui.drag_stack != null and ui.hover_view == self and ui.attach_target(self) == null:
		draw_rect(rect, GridView.DROP_OK if ui.can_drop_on_slot(slot) else GridView.DROP_BAD)
	if stack != null:
		_draw_parts()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_parts((event as InputEventMouseMotion).position)
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var stack := inventory.equipped(slot)
	if stack == null:
		return
	var button := event as InputEventMouseButton
	var part_slot := _part_at(button.position)
	if button.button_index == MOUSE_BUTTON_LEFT and part_slot != "" and stack.attachments.has(part_slot):
		# Click or tap a fitted attachment: take it off (it goes into your inventory).
		ui.detach(stack, part_slot, null)
		_hover_part = ""
		accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
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


## Pointing at an attachment slot shows that attachment's info; back on the gun shows the gun's.
func _hover_parts(point: Vector2) -> void:
	var part_slot := _part_at(point)
	if part_slot == _hover_part:
		return
	_hover_part = part_slot
	var stack := inventory.equipped(slot)
	if stack != null and ui.drag_stack == null:
		var part: String = stack.attachments.get(part_slot, "")
		ui.show_info(ItemStack.new(part) if part != "" else stack)
	queue_redraw()
