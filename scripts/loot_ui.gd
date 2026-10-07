class_name LootUI
extends Control
## Inventory screen (Tab), and the container + inventory screen when you open loot (E).
## Drag & drop items between grids, R rotates while dragging, Shift+click quick-moves,
## right-click for Use / Split / Drop. The raid keeps running while this is open, so loot fast.

const CELL := GridView.CELL
const PICKUP_SOUND := preload("res://audio/mag_in.wav")
enum MenuAction { USE, SPLIT, DROP }

var player: Player
var container: LootContainer = null

## The stack being dragged (stays in its grid until dropped), where it came from, and its rotation.
var drag_stack: ItemStack = null
var drag_from: GridInventory = null
var drag_rotated := false
## The GridView under the mouse while dragging.
var hover_view: GridView = null

var _grab_cell := Vector2i.ZERO
var _preview: ItemTile = null
var _views: Array[GridView] = []
var _menu: PopupMenu
var _menu_grid: GridInventory
var _menu_stack: ItemStack

var _container_panel: Control
var _container_box: VBoxContainer
var _player_box: VBoxContainer
var _value_label: Label
var _info_label: Label


func _init(owner_player: Player) -> void:
	player = owner_player
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _ready() -> void:
	player.inventory.changed.connect(_update_labels)


func open_for(target: LootContainer) -> void:
	container = target
	visible = true
	player.interactor.blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_layout()


func close() -> void:
	if not visible:
		return
	_cancel_drag()
	visible = false
	container = null
	_clear_views()
	player.interactor.blocked = false
	if not player.controls_locked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not visible:
		return
	if player.controls_locked():
		close()
		return
	# Walked away (or the bag was emptied): keep your inventory open, drop the container.
	if container != null and (not is_instance_valid(container) or container.global_position.distance_to(player.global_position) > 3.5):
		_cancel_drag()
		container = null
		_rebuild_layout()


# --- Moving items --------------------------------------------------------------

## Moves `stack` from `from` to `to` with its top-left at `cell`. If there's a matching stack with room at
## `merge_cell`, merges into it instead. Returns true if anything moved.
func move_stack(stack: ItemStack, from: GridInventory, to: GridInventory, cell: Vector2i, rotated: bool, merge_cell := Vector2i(-1, -1)) -> bool:
	var target: ItemStack = null
	if merge_cell.x >= 0:
		target = to.stack_at(merge_cell)
	if target != null and target != stack and target.id == stack.id and target.space_left() > 0:
		var moved := mini(stack.count, target.space_left())
		target.count += moved
		stack.count -= moved
		if stack.count <= 0:
			from.remove(stack)
		else:
			from.changed.emit()
		to.changed.emit()
		_after_move()
		return true
	if not to.fits(stack.id, cell.x, cell.y, rotated, stack if to == from else null):
		return false
	if to == from:
		stack.x = cell.x
		stack.y = cell.y
		stack.rotated = rotated
		from.changed.emit()
	else:
		from.remove(stack)
		stack.x = cell.x
		stack.y = cell.y
		stack.rotated = rotated
		to.place(stack)
	_after_move()
	return true


## Shift+click: send a stack straight to the other side (container <-> your inventory).
func quick_move(grid: GridInventory, stack: ItemStack) -> void:
	var destinations: Array[GridInventory] = []
	if container != null and grid == container.grid:
		destinations = player.inventory.grids()
	elif container != null:
		destinations = [container.grid]
	else:
		return
	var left := stack.count
	for destination in destinations:
		if left > 0:
			left = destination.add(stack.id, left)
	if left == stack.count:
		return
	if left <= 0:
		grid.remove(stack)
	else:
		stack.count = left
		grid.changed.emit()
	_after_move()


func _after_move() -> void:
	Effects.sound(player.get_tree().current_scene, PICKUP_SOUND, -10.0)
	if container != null and is_instance_valid(container) and container.remove_when_empty and container.grid.is_empty():
		container.queue_free()
		container = null
		_rebuild_layout.call_deferred()
	_update_labels()


# --- Dragging ------------------------------------------------------------------

func start_drag(grid: GridInventory, stack: ItemStack, grab_position: Vector2) -> void:
	_cancel_drag()
	drag_stack = stack
	drag_from = grid
	drag_rotated = stack.rotated
	_grab_cell = Vector2i(floori(grab_position.x / CELL), floori(grab_position.y / CELL))
	_preview = ItemTile.new(stack, grid, self, true)
	_preview.top_level = true
	_preview.modulate.a = 0.85
	add_child(_preview)
	_update_drag()
	_refresh_views()


func drag_size() -> Vector2i:
	var base := ItemDB.size(drag_stack.id)
	return Vector2i(base.y, base.x) if drag_rotated else base


## Top-left cell the dragged item would land on in `view`.
func drop_cell(view: GridView) -> Vector2i:
	return view.cell_at_global(get_global_mouse_position()) - _grab_cell


func can_drop_at(view: GridView, cell: Vector2i) -> bool:
	var target := view.grid.stack_at(cell + _grab_cell)
	if target != null and target != drag_stack and target.id == drag_stack.id and target.space_left() > 0:
		return true
	return view.grid.fits(drag_stack.id, cell.x, cell.y, drag_rotated, drag_stack if view.grid == drag_from else null)


func _input(event: InputEvent) -> void:
	if drag_stack == null:
		return
	if event is InputEventMouseMotion:
		_update_drag()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		drag_rotated = not drag_rotated
		_grab_cell = Vector2i(_grab_cell.y, _grab_cell.x)
		_update_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_finish_drag()
		get_viewport().set_input_as_handled()


func _update_drag() -> void:
	var mouse := get_global_mouse_position()
	_preview.set_tile_size(drag_size())
	_grab_cell = _grab_cell.clamp(Vector2i.ZERO, drag_size() - Vector2i.ONE)
	_preview.global_position = mouse - (Vector2(_grab_cell) + Vector2(0.5, 0.5)) * CELL
	hover_view = null
	for view in _views:
		if view.get_global_rect().has_point(mouse):
			hover_view = view
	for view in _views:
		view.queue_redraw()


func _finish_drag() -> void:
	var stack := drag_stack
	var from := drag_from
	var rotated := drag_rotated
	var view := hover_view
	var cell := drop_cell(view) if view != null else Vector2i.ZERO
	var merge_cell := cell + _grab_cell
	_cancel_drag()
	if view != null:
		move_stack(stack, from, view.grid, cell, rotated, merge_cell)
	_refresh_views()


func _cancel_drag() -> void:
	drag_stack = null
	drag_from = null
	hover_view = null
	if _preview != null:
		_preview.queue_free()
		_preview = null


# --- Right-click menu ----------------------------------------------------------

func open_menu(grid: GridInventory, stack: ItemStack) -> void:
	_menu_grid = grid
	_menu_stack = stack
	_menu.clear()
	if ItemDB.kind(stack.id) == "heal":
		_menu.add_item("Use", MenuAction.USE)
	if stack.count > 1:
		_menu.add_item("Split", MenuAction.SPLIT)
	_menu.add_item("Put in " + container.display_name if container != null and grid != container.grid else "Drop", MenuAction.DROP)
	_menu.position = Vector2i(get_global_mouse_position())
	_menu.reset_size()
	_menu.popup()


func _on_menu(action: int) -> void:
	var grid := _menu_grid
	var stack := _menu_stack
	if grid == null or stack == null or not grid.stacks.has(stack):
		return
	match action:
		MenuAction.USE:
			player.use_item(grid, stack)
		MenuAction.SPLIT:
			split_stack(grid, stack)
		MenuAction.DROP:
			drop_stack(grid, stack)
	_update_labels()


## Moves half a stack into a free spot: the same grid if there's room, otherwise another of yours.
func split_stack(grid: GridInventory, stack: ItemStack) -> bool:
	var half := stack.count / 2
	if half <= 0:
		return false
	var candidates: Array[GridInventory] = [grid]
	for other in player.inventory.grids():
		if other != grid:
			candidates.append(other)
	for target in candidates:
		var spot := target.find_spot(stack.id)
		if not spot.is_empty():
			stack.count -= half
			grid.changed.emit()
			target.place(ItemStack.new(stack.id, half, spot[0], spot[1], spot[2]))
			return true
	return false


## Drop on the ground, or into the open container.
func drop_stack(grid: GridInventory, stack: ItemStack) -> void:
	if container != null and grid != container.grid:
		quick_move(grid, stack)
		return
	grid.remove(stack)
	var drop_pos := player.global_position - player.global_basis.z * 0.8
	LootContainer.spawn_bag(player.get_tree().current_scene, drop_pos, "Dropped Items", [stack])
	_after_move()


# --- Info / labels ---------------------------------------------------------------

func show_info(stack: ItemStack) -> void:
	var data := ItemDB.item(stack.id)
	var rarity: String = data["rarity"]
	var cells := ItemDB.size(stack.id)
	var parts: PackedStringArray = [ItemDB.display_name(stack.id), rarity.capitalize(), "%d×%d" % [cells.x, cells.y]]
	match ItemDB.kind(stack.id):
		"heal":
			parts.append("heals %d" % int(data["heal"]))
		"ammo":
			parts.append("ammo")
	if stack.count > 1:
		parts.append("x%d (%s)" % [stack.count, ItemDB.money(stack.value())])
	else:
		parts.append(ItemDB.money(stack.value()))
	_info_label.text = "  ·  ".join(parts)
	_info_label.add_theme_color_override("font_color", ItemDB.color(stack.id))


func _update_labels() -> void:
	if _value_label != null:
		_value_label.text = "Carrying %s" % ItemDB.money(player.inventory.total_value())


# --- Layout --------------------------------------------------------------------

func _clear_views() -> void:
	_views.clear()
	for box in [_container_box, _player_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()


func _rebuild_layout() -> void:
	if not visible:
		return
	_clear_views()
	var has_container := container != null and is_instance_valid(container)
	_container_panel.visible = has_container
	if has_container:
		_container_box.add_child(_title(container.display_name.to_upper(), 22))
		_add_view(_container_box, container.grid)

	_player_box.add_child(_title("INVENTORY", 22))
	_value_label = _small("")
	_player_box.add_child(_value_label)
	var inventory := player.inventory
	for grid in inventory.grids():
		_player_box.add_child(_small(grid.title))
		_add_view(_player_box, grid)
	_update_labels()


func _add_view(box: VBoxContainer, grid: GridInventory) -> void:
	var view := GridView.new(grid, self)
	box.add_child(view)
	_views.append(view)


func _refresh_views() -> void:
	for view in _views:
		view.rebuild()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	root.add_child(columns)
	_container_panel = _panel(columns)
	_container_box = _container_panel.get_meta("box")
	var player_panel := _panel(columns)
	_player_box = player_panel.get_meta("box")

	_info_label = _small("Hover an item for details")
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_info_label)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)
	footer.add_child(_small("Drag to move · R rotate · Shift+click quick-move · Right-click Use/Split/Drop · Tab/E close · the raid doesn't pause!"))
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	footer.add_child(close_button)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


func _panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(260, 0)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	panel.set_meta("box", box)
	return panel


func _title(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _small(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.7)
	label.add_theme_font_size_override("font_size", 13)
	return label
