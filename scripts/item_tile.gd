class_name ItemTile
extends Control
## Placeholder icon for an item in a grid: a block the size of the item, rarity-colored border, short name, count.
## Left-drag to move, Shift+click to quick-move, right-click for the menu.

var stack: ItemStack
var grid: GridInventory
var ui: LootUI

var _name_label: Label
var _count_label: Label


func _init(target: ItemStack, owner_grid: GridInventory, owner_ui: LootUI, is_preview := false) -> void:
	stack = target
	grid = owner_grid
	ui = owner_ui
	mouse_filter = Control.MOUSE_FILTER_IGNORE if is_preview else Control.MOUSE_FILTER_STOP

	_name_label = Label.new()
	_name_label.text = ItemDB.display_name(stack.id)
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.clip_text = true
	_name_label.position = Vector2(5, 3)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)

	set_tile_size(stack.size())
	if not is_preview:
		mouse_entered.connect(func() -> void: ui.show_info(stack))


func set_tile_size(cells: Vector2i) -> void:
	size = Vector2(cells) * GridView.CELL
	_name_label.size = Vector2(size.x - 10, size.y - 18)
	_fit_name()
	_count_label.text = "x%d" % stack.count if stack.count > 1 else ""
	_count_label.position = Vector2(4, size.y - 19)
	_count_label.size = Vector2(size.x - 9, 16)
	queue_redraw()


## The full name, in the biggest font (12 down to 8) that fits the tile (owner: icons replace this with the art).
func _fit_name() -> void:
	var font := _name_label.get_theme_font("font")
	var room := _name_label.size
	for font_size in range(12, 7, -1):
		var needed := font.get_multiline_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, room.x, font_size)
		if needed.x <= room.x and needed.y <= room.y + 2:
			_name_label.add_theme_font_size_override("font_size", font_size)
			return
	_name_label.add_theme_font_size_override("font_size", 8)


func _draw() -> void:
	var color := ItemDB.color(stack.id)
	var rect := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	draw_rect(rect, color.darkened(0.72))
	draw_rect(rect, color, false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_LEFT:
		if button.shift_pressed:
			ui.quick_move(grid, stack)
		else:
			ui.start_drag(grid, stack, button.position)
		accept_event()
	elif button.button_index == MOUSE_BUTTON_RIGHT:
		ui.open_menu(grid, stack)
		accept_event()
