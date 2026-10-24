class_name SlotGridView
extends GridView
## A body's gear slot (Primary / Secondary / Armor / Backpack) in the loot screen: a one-item GridInventory
## shown at a fixed size, like your own EquipSlotView. Drag in, drag out, Shift+click and right-click work like
## any grid.

var _cells: Vector2i
var _label: Label


func _init(target: GridInventory, owner_ui: LootUI, cells: Vector2i) -> void:
	super(target, owner_ui)
	_cells = cells
	custom_minimum_size = Vector2(cells) * CELL
	size = custom_minimum_size
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var shown: ItemStack = null
	for stack in grid.stacks:
		if stack != ui.drag_stack:
			shown = stack
	if shown != null:
		var tile := ItemTile.new(shown, grid, ui)
		tile.set_tile_size(_cells)
		add_child(tile)
	else:
		_label = Label.new()
		_label.text = grid.slot.to_upper()
		InvLook.style_slot_label(_label)
		_label.modulate = Color(1, 1, 1, 0.35)
		_label.position = Vector2(6, 4)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, custom_minimum_size)
	InvLook.draw_slot(self, rect)
	if ui.drag_stack != null and ui.hover_view == self:
		draw_rect(rect, DROP_OK if ui.can_drop_at(self, Vector2i.ZERO) else DROP_BAD)
