class_name GridView
extends Control
## Draws one GridInventory as cells with ItemTiles on top, and the drop preview while dragging.

const CELL := 44

var grid: GridInventory
var ui: LootUI


func _init(target: GridInventory, owner_ui: LootUI) -> void:
	grid = target
	ui = owner_ui
	custom_minimum_size = Vector2(grid.width, grid.height) * CELL
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	grid.changed.connect(rebuild)
	rebuild()


func _exit_tree() -> void:
	if grid.changed.is_connected(rebuild):
		grid.changed.disconnect(rebuild)


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for stack in grid.stacks:
		if stack == ui.drag_stack:
			continue
		var tile := ItemTile.new(stack, grid, ui)
		tile.position = Vector2(stack.x, stack.y) * CELL
		add_child(tile)
	queue_redraw()


func cell_at_global(pos: Vector2) -> Vector2i:
	var local := pos - global_position
	return Vector2i(floori(local.x / CELL), floori(local.y / CELL))


func _draw() -> void:
	var area := Vector2(grid.width, grid.height) * CELL
	draw_rect(Rect2(Vector2.ZERO, area), Color(0.07, 0.08, 0.09, 0.92))
	var line := Color(1, 1, 1, 0.07)
	for x in grid.width + 1:
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, area.y), line)
	for y in grid.height + 1:
		draw_line(Vector2(0, y * CELL), Vector2(area.x, y * CELL), line)
	if ui.drag_stack != null and ui.hover_view == self:
		var cell := ui.drop_cell(self)
		var ok := ui.can_drop_at(self, cell)
		var color := Color(0.3, 1.0, 0.4, 0.28) if ok else Color(1.0, 0.3, 0.25, 0.28)
		draw_rect(Rect2(Vector2(cell) * CELL, Vector2(ui.drag_size()) * CELL), color)
