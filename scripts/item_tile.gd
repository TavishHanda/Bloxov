class_name ItemTile
extends Control
## An item in a grid: a dark block the size of the item glowing in its rarity color (InvLook), its picture
## (ItemIcons), short name and count. Items without a picture show their full name instead.
## Left-drag to move, Shift+click to quick-move, right-click for the menu.

var stack: ItemStack
var grid: GridInventory
var ui: LootUI

var _name_label: Label
var _count_label: Label
var _icon: Texture2D


func _init(target: ItemStack, owner_grid: GridInventory, owner_ui: LootUI, is_preview := false) -> void:
	stack = target
	grid = owner_grid
	ui = owner_ui
	mouse_filter = Control.MOUSE_FILTER_IGNORE if is_preview else Control.MOUSE_FILTER_STOP
	_icon = ItemIcons.get_icon(stack.id)

	_name_label = Label.new()
	_name_label.clip_text = true
	_name_label.position = Vector2(4, 3)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	_count_label = Label.new()
	HudStyle.style_label(_count_label, 20)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)

	set_tile_size(stack.size())
	if not is_preview:
		mouse_entered.connect(func() -> void: ui.show_info(stack))


func set_tile_size(cells: Vector2i) -> void:
	size = Vector2(cells) * GridView.CELL
	_count_label.text = "x%d" % stack.count if stack.count > 1 else ""
	_count_label.position = Vector2(4, size.y - 22)
	_count_label.size = Vector2(size.x - 9, 18)
	# (the name gets the whole tile unless there's a count at the bottom)
	_name_label.size = Vector2(size.x - 6, size.y - (20 if stack.count > 1 else 6))
	if _icon != null:
		_fit_short_name()
	else:
		_fit_name()
	queue_redraw()


## With a picture: the short name in one line.
func _fit_short_name() -> void:
	_small_name(ItemDB.short_name(stack.id))


## The full name, one word per line if it doesn't fit on one (owner, 0.14.10: "Raider / Dog / Tag", not a cut-off
## "Raider"). (Only items without a picture.)
func _fit_name() -> void:
	var name := stack.title()
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_small_name(name)


## The name small in the top-right corner, so it hardly covers the picture (0.19.10, owner picked "top-right, no
## strip"): the plain font at 10 px (down to 8 for long names), soft white with a 1 px shadow.
func _small_name(text: String) -> void:
	var f := ThemeDB.fallback_font
	var font_size := 10
	if _name_label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		while font_size > 8 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > _name_label.size.x:
			font_size -= 1
	_name_label.add_theme_font_override("font", f)
	_name_label.add_theme_font_size_override("font_size", font_size)
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name_label.position = Vector2(2, 2)
	_name_label.text = text


func _draw() -> void:
	var color := ItemDB.color(stack.id)
	var rect := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	InvLook.draw_tile(self, rect, color)
	if _icon != null:
		_draw_icon(rect.grow(-3))
	InvLook.draw_edge(self, rect, color)
	_draw_wear(rect.grow(-2))


## Wear (0.14.0): armor and keys show what's left as a bar along the bottom, green to red.
func _draw_wear(inner: Rect2) -> void:
	if ItemDB.max_durability(stack.id) > 0:
		var left := stack.condition()
		var bar := Rect2(Vector2(inner.position.x + 2, inner.end.y - 6), Vector2(inner.size.x - 4, 4))
		draw_rect(bar, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * left), bar.size.y)), Color(1.0, 0.3, 0.2).lerp(Color(0.45, 0.9, 0.35), left))


## The picture fills the tile; a rotated item's picture turns with it (a quarter turn clockwise).
func _draw_icon(room: Rect2) -> void:
	if not stack.rotated:
		draw_texture_rect(_icon, room, false)
		return
	draw_set_transform(Vector2(room.end.x, room.position.y), PI * 0.5)
	draw_texture_rect(_icon, Rect2(Vector2.ZERO, Vector2(room.size.y, room.size.x)), false)
	draw_set_transform(Vector2.ZERO)


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
