class_name GunPartsBar
extends Control
## A gun's attachment slots along the bottom of a body's gun slot in the loot screen (0.38.13, owner: "when you are
## looting a body with a gun you should be able to see the attachments on the gun ... so u can take them off the gun
## easily without having to take the whole gun"). Looks like your own gun's (EquipSlotView): click or tap a fitted
## attachment to take it off into your inventory. Dropping an attachment on the slot still fits it (LootUI.attach_target).

var gun: ItemStack
var grid: GridInventory
var ui: LootUI
## The attachment slot under the mouse ("" = none).
var _hover := ""


func _init(target_gun: ItemStack, gun_grid: GridInventory, owner_ui: LootUI) -> void:
	gun = target_gun
	grid = gun_grid
	ui = owner_ui
	mouse_filter = Control.MOUSE_FILTER_STOP
	var count := ItemDB.attachment_slots(gun.id).size()
	custom_minimum_size = Vector2(count * EquipSlotView.PART_SIZE + maxi(count - 1, 0) * EquipSlotView.PART_GAP, EquipSlotView.PART_SIZE)
	size = custom_minimum_size
	mouse_exited.connect(func() -> void:
		_hover = ""
		queue_redraw())


## [[attachment slot, Rect2], ...] left to right.
func part_rects() -> Array:
	var rects := []
	var x := 0.0
	for part_slot: String in ItemDB.attachment_slots(gun.id):
		rects.append([part_slot, Rect2(x, 0, EquipSlotView.PART_SIZE, EquipSlotView.PART_SIZE)])
		x += EquipSlotView.PART_SIZE + EquipSlotView.PART_GAP
	return rects


func _part_at(point: Vector2) -> String:
	for entry: Array in part_rects():
		if (entry[1] as Rect2).has_point(point):
			return entry[0]
	return ""


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for entry: Array in part_rects():
		var part_slot: String = entry[0]
		var rect: Rect2 = entry[1]
		var part: String = gun.attachments.get(part_slot, "")
		draw_rect(rect.grow(1), HudStyle.OUTLINE)
		draw_rect(rect, HudStyle.DEEP)
		if part != "":
			var color := ItemDB.color(part)
			draw_rect(rect.grow(-1), color.darkened(0.7))
			EquipSlotView.draw_part_picture(self, part, rect)
			draw_rect(rect.grow(-1), color, false, 1.0)
		else:
			draw_string(font, Vector2(rect.position.x, rect.get_center().y + 3), EquipSlotView.SLOT_NAMES.get(part_slot, ""),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 8, Color(1, 1, 1, 0.35))
		if part_slot == _hover and part != "":
			draw_rect(rect, Color(1, 1, 1, 0.12))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var over := _part_at((event as InputEventMouseMotion).position)
		if over != _hover:
			_hover = over
			var part: String = gun.attachments.get(over, "")
			if ui.drag_stack == null:
				ui.show_info(ItemStack.new(part) if part != "" else gun)
			queue_redraw()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var button := event as InputEventMouseButton
	var part_slot := _part_at(button.position)
	if button.button_index == MOUSE_BUTTON_LEFT and part_slot != "" and gun.attachments.has(part_slot) and grid.stacks.has(gun):
		# Take it off: it goes into your inventory (or anywhere there's room), the gun stays on the body.
		ui.detach(gun, part_slot, grid)
		_hover = ""
		queue_redraw()
		accept_event()
