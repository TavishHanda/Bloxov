class_name LootUI
extends Control
## Inventory screen (Tab), and the container + inventory screen when you open loot (E).
## Also used in the hideout (no player): the "other side" is the stash instead of a container, and items can be sold.
## Columns: [container] [equipment, pockets, secure pocket] [backpack].
## Drag & drop items between grids and equipment slots, R rotates while dragging, Shift+click quick-moves,
## right-click for Use / Equip / Bind to hotbar / Split / Drop. The raid keeps running while this is open.

const CELL := GridView.CELL
const PICKUP_SOUND := preload("res://audio/mag_in.wav")
enum MenuAction { USE, SPLIT, DROP, EQUIP, UNEQUIP, BIND, UNBIND, SELL }

## The player in a raid, or null in the hideout.
var player: Player
## Whose inventory this screen shows (the player's, or the hideout's loadout).
var inventory: Inventory
var container: LootContainer = null
## Hideout: the stash shown opposite your inventory (when there's no container).
var stash: GridInventory = null
## Hideout: if set, right-click offers "Sell"; called with (grid, stack).
var sell_handler: Callable
## Hideout: returns the sell price of a stack (for the menu label).
var price_handler: Callable

## The stack being dragged (stays in its grid until dropped), where it came from, and its rotation.
var drag_stack: ItemStack = null
var drag_from: GridInventory = null
## Set instead of drag_from when dragging an item out of an equipment slot.
var drag_slot := ""
var drag_rotated := false
## The GridView or EquipSlotView under the mouse while dragging.
var hover_view: Control = null

var _grab_cell := Vector2i.ZERO
var _preview: ItemTile = null
var _views: Array[Control] = []
var _menu: PopupMenu
var _menu_grid: GridInventory
var _menu_stack: ItemStack
var _menu_slot := ""

var _container_panel: Control
var _container_box: VBoxContainer
var _player_box: VBoxContainer
var _backpack_panel: Control
var _backpack_box: VBoxContainer
var _value_label: Label
var _info_label: Label


func _init(owner_player: Player, owner_inventory: Inventory = null) -> void:
	player = owner_player
	inventory = owner_inventory if owner_inventory != null else owner_inventory
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _ready() -> void:
	inventory.changed.connect(_update_labels)
	inventory.equipment_changed.connect(_on_equipment_changed)


func _on_equipment_changed() -> void:
	if visible:
		_rebuild_layout.call_deferred()


func open_for(target: LootContainer) -> void:
	container = target
	visible = true
	if player != null:
		player.interactor.blocked = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_layout()


## Hideout: show the stash opposite your loadout, always open, no dimmed backdrop.
func open_stash(stash_grid: GridInventory) -> void:
	stash = stash_grid
	_dim.visible = false
	_close_button.visible = false
	_footer_hint.text = "Drag to move/equip · R rotate · Shift+click quick-move · Right-click to sell or for options"
	open_for(null)


## Leaves room at the top of the screen (the hideout's top bar).
func set_top_margin(pixels: float) -> void:
	_center.offset_top = pixels


## Extra panel (e.g. the trader) added as a column on the right.
func add_column(panel: Control) -> void:
	_columns.add_child(panel)


func close() -> void:
	if not visible:
		return
	_cancel_drag()
	visible = false
	container = null
	_clear_views()
	if player != null:
		player.interactor.blocked = false
		if not player.controls_locked():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	if player.controls_locked():
		close()
		return
	# Walked away (or the bag was emptied): keep your inventory open, drop the container.
	if container != null and (not is_instance_valid(container) or container.global_position.distance_to(player.global_position) > 3.5):
		_cancel_drag()
		container = null
		_rebuild_layout()


## The grid opposite your inventory: the open container's, or the stash in the hideout.
func other_grid() -> GridInventory:
	if container != null and is_instance_valid(container):
		return container.grid
	return stash


func _other_title() -> String:
	if container != null and is_instance_valid(container):
		return container.display_name
	return "Stash"


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
	if inventory.grids().has(to):
		inventory.auto_bind(stack.id)
	_after_move()
	return true


## Shift+click: send a stack straight to the other side (container <-> your inventory).
func quick_move(grid: GridInventory, stack: ItemStack) -> void:
	var other := other_grid()
	if other == null:
		return
	# Shift+clicking something in the container/stash sends it to you, and vice versa.
	var to_player := grid == other
	var destinations: Array[GridInventory] = []
	if to_player:
		destinations = inventory.grids()
	else:
		destinations.append(other)
	# Gear goes straight into an empty equipment slot.
	var slot := ItemDB.equip_slot(stack.id)
	if to_player and slot != "" and inventory.equipped(slot) == null:
		grid.remove(stack)
		inventory.equip(slot, stack)
		_after_move()
		return
	if ItemDB.max_stack(stack.id) == 1:
		# Move the same object (keeps a gun's loaded rounds).
		var target := _find_room(stack, destinations)
		if target != null:
			grid.remove(stack)
			target.place(stack)
			_after_move()
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
	if to_player:
		inventory.auto_bind(stack.id)
	_after_move()


## Finds the first grid with room for `stack` and sets the stack's x/y/rotation to that spot
## (it isn't added yet). Returns the grid, or null.
func _find_room(stack: ItemStack, grids: Array[GridInventory]) -> GridInventory:
	for grid in grids:
		var spot := grid.find_spot(stack.id)
		if not spot.is_empty():
			stack.x = spot[0]
			stack.y = spot[1]
			stack.rotated = spot[2]
			return grid
	return null


# --- Equipment -------------------------------------------------------------------

## Equip a stack from a grid into a slot. If the slot already has something, it swaps into the grid.
func equip_from_grid(grid: GridInventory, stack: ItemStack, slot: String) -> bool:
	if not inventory.slot_accepts(slot, stack.id):
		return false
	var old := inventory.equipped(slot)
	if old != null and not inventory.can_unequip(slot):
		_info_label.text = "Empty your backpack before swapping it"
		return false
	var old_x := stack.x
	var old_y := stack.y
	grid.remove(stack)
	if old != null:
		inventory.unequip(slot)
	inventory.equip(slot, stack)
	if old != null:
		_stow(old, grid, Vector2i(old_x, old_y))
	_after_move()
	return true


## Unequip into a specific grid cell (dragging out of a slot).
func unequip_to_grid(slot: String, grid: GridInventory, cell: Vector2i, rotated: bool) -> bool:
	var stack := inventory.equipped(slot)
	if stack == null or not inventory.can_unequip(slot):
		return false
	if slot == "backpack" and grid == inventory.backpack:
		return false
	if not grid.fits(stack.id, cell.x, cell.y, rotated):
		return false
	inventory.unequip(slot)
	stack.x = cell.x
	stack.y = cell.y
	stack.rotated = rotated
	grid.place(stack)
	_after_move()
	return true


## Shift+click / menu: take an item off into the first free spot (or the container, or the ground).
func unequip_to_inventory(slot: String) -> void:
	if not inventory.can_unequip(slot):
		_info_label.text = "Empty your backpack before taking it off"
		return
	var stack := inventory.unequip(slot)
	_stow(stack, null, Vector2i.ZERO)
	_after_move()


## Puts a loose stack somewhere sensible: `preferred` at `cell`, any of your grids, the open container, or the ground.
func _stow(stack: ItemStack, preferred: GridInventory, cell: Vector2i) -> void:
	if preferred != null:
		for rotated in [false, true]:
			if preferred.fits(stack.id, cell.x, cell.y, rotated):
				stack.x = cell.x
				stack.y = cell.y
				stack.rotated = rotated
				preferred.place(stack)
				return
	var candidates: Array[GridInventory] = inventory.grids()
	if other_grid() != null:
		candidates.append(other_grid())
	var target := _find_room(stack, candidates)
	if target != null:
		target.place(stack)
		return
	_drop_or_overflow(stack)


## Nowhere to put it: in a raid it drops on the ground; in the hideout the stash grows to fit it.
func _drop_or_overflow(stack: ItemStack) -> void:
	if player != null:
		var drop_pos := player.global_position - player.global_basis.z * 0.8
		LootContainer.spawn_bag(get_tree().current_scene, drop_pos, "Dropped Items", [stack])
	elif stash != null:
		stack.x = 0
		stack.y = stash.height
		stack.rotated = false
		stash.height += ItemDB.size(stack.id).y
		stash.place(stack)


func can_drop_on_slot(slot: String) -> bool:
	if drag_stack == null or not inventory.slot_accepts(slot, drag_stack.id):
		return false
	var current := inventory.equipped(slot)
	return current == null or current == drag_stack or (drag_slot == "" and inventory.can_unequip(slot))


func _after_move() -> void:
	Effects.sound(get_tree().current_scene, PICKUP_SOUND, -10.0)
	if container != null and is_instance_valid(container) and container.remove_when_empty and container.grid.is_empty():
		container.queue_free()
		container = null
		_rebuild_layout.call_deferred()
	_update_labels()


# --- Dragging ------------------------------------------------------------------

func start_drag_from_slot(slot: String, _grab_position: Vector2) -> void:
	if not inventory.can_unequip(slot):
		_info_label.text = "Empty your backpack before taking it off"
		return
	_cancel_drag()
	var stack := inventory.equipped(slot)
	drag_stack = stack
	drag_slot = slot
	drag_rotated = false
	_grab_cell = Vector2i.ZERO
	_start_preview(stack)


func start_drag(grid: GridInventory, stack: ItemStack, grab_position: Vector2) -> void:
	_cancel_drag()
	drag_stack = stack
	drag_from = grid
	drag_rotated = stack.rotated
	_grab_cell = Vector2i(floori(grab_position.x / CELL), floori(grab_position.y / CELL))
	_start_preview(stack)


func _start_preview(stack: ItemStack) -> void:
	_preview = ItemTile.new(stack, null, self, true)
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
	if drag_slot != "":
		if drag_slot == "backpack" and view.grid == inventory.backpack:
			return false
		return view.grid.fits(drag_stack.id, cell.x, cell.y, drag_rotated)
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
	var slot := drag_slot
	var rotated := drag_rotated
	var view := hover_view
	_cancel_drag()
	if view is GridView:
		var grid_view := view as GridView
		var cell := drop_cell(grid_view)
		if slot != "":
			unequip_to_grid(slot, grid_view.grid, cell, rotated)
		else:
			move_stack(stack, from, grid_view.grid, cell, rotated, cell + _grab_cell)
	elif view is EquipSlotView and slot == "":
		equip_from_grid(from, stack, (view as EquipSlotView).slot)
	_refresh_views()


func _cancel_drag() -> void:
	drag_stack = null
	drag_from = null
	drag_slot = ""
	hover_view = null
	if _preview != null:
		_preview.queue_free()
		_preview = null


# --- Right-click menu ----------------------------------------------------------

func open_menu(grid: GridInventory, stack: ItemStack) -> void:
	_menu_grid = grid
	_menu_stack = stack
	_menu_slot = ""
	_menu.clear()
	if ItemDB.kind(stack.id) == "heal" and player != null:
		_menu.add_item("Use", MenuAction.USE)
		if inventory.hotbar.has(stack.id):
			_menu.add_item("Unbind (key %d)" % (inventory.hotbar.find(stack.id) + 3), MenuAction.UNBIND)
		elif inventory.hotbar.has(""):
			_menu.add_item("Bind to hotbar", MenuAction.BIND)
	if ItemDB.equip_slot(stack.id) != "":
		_menu.add_item("Equip", MenuAction.EQUIP)
	if stack.count > 1:
		_menu.add_item("Split", MenuAction.SPLIT)
	if other_grid() != null and grid != other_grid():
		_menu.add_item("Put in " + _other_title(), MenuAction.DROP)
	elif player != null:
		_menu.add_item("Drop", MenuAction.DROP)
	if sell_handler.is_valid():
		_menu.add_item("Sell for %s" % ItemDB.money(price_handler.call(stack)), MenuAction.SELL)
	_popup_menu()


func open_slot_menu(slot: String) -> void:
	_menu_slot = slot
	_menu_grid = null
	_menu_stack = null
	_menu.clear()
	_menu.add_item("Unequip", MenuAction.UNEQUIP)
	if other_grid() != null:
		_menu.add_item("Put in " + _other_title(), MenuAction.DROP)
	elif player != null:
		_menu.add_item("Drop", MenuAction.DROP)
	_popup_menu()


func _popup_menu() -> void:
	_menu.position = Vector2i(get_global_mouse_position())
	_menu.reset_size()
	_menu.popup()


func _on_menu(action: int) -> void:
	if _menu_slot != "":
		_on_slot_menu(action)
		return
	var grid := _menu_grid
	var stack := _menu_stack
	if grid == null or stack == null or not grid.stacks.has(stack):
		return
	match action:
		MenuAction.EQUIP:
			equip_from_grid(grid, stack, ItemDB.equip_slot(stack.id))
		MenuAction.BIND:
			inventory.bind_to_hotbar(stack.id)
		MenuAction.UNBIND:
			inventory.unbind(stack.id)
		MenuAction.SELL:
			sell_handler.call(grid, stack)
		MenuAction.USE:
			if player != null:
				player.use_item(grid, stack)
		MenuAction.SPLIT:
			split_stack(grid, stack)
		MenuAction.DROP:
			drop_stack(grid, stack)
	_update_labels()


func _on_slot_menu(action: int) -> void:
	var slot := _menu_slot
	_menu_slot = ""
	if inventory.equipped(slot) == null:
		return
	match action:
		MenuAction.UNEQUIP:
			unequip_to_inventory(slot)
		MenuAction.DROP:
			if not inventory.can_unequip(slot):
				_info_label.text = "Empty your backpack first"
				return
			var stack := inventory.unequip(slot)
			var into: Array[GridInventory] = []
			if other_grid() != null:
				into.append(other_grid())
			var target := _find_room(stack, into)
			if target != null:
				target.place(stack)
			else:
				_drop_or_overflow(stack)
			_after_move()


## Moves half a stack into a free spot: the same grid if there's room, otherwise another of yours.
func split_stack(grid: GridInventory, stack: ItemStack) -> bool:
	var half := stack.count / 2
	if half <= 0:
		return false
	var candidates: Array[GridInventory] = [grid]
	for other in inventory.grids():
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


## Drop on the ground, or into the open container / stash.
func drop_stack(grid: GridInventory, stack: ItemStack) -> void:
	if other_grid() != null and grid != other_grid():
		quick_move(grid, stack)
		return
	if player == null:
		return
	grid.remove(stack)
	_drop_or_overflow(stack)
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
		"weapon":
			parts.append("%s · %d dmg · %d rpm · %s loaded" % [str(data["slot"]).capitalize(), int(data["damage"]), int(data["rpm"]), str(stack.loaded)])
		"armor":
			parts.append("-%d%% damage" % roundi(float(data["reduction"]) * 100.0))
		"backpack":
			parts.append("%d×%d storage" % [int(data["grid"][0]), int(data["grid"][1])])
	if stack.count > 1:
		parts.append("x%d (%s)" % [stack.count, ItemDB.money(stack.value())])
	else:
		parts.append(ItemDB.money(stack.value()))
	_info_label.text = "  ·  ".join(parts)
	_info_label.add_theme_color_override("font_color", ItemDB.color(stack.id))


func _update_labels() -> void:
	if _value_label != null:
		_value_label.text = "Carrying %s" % ItemDB.money(inventory.total_value())


# --- Layout --------------------------------------------------------------------

func _clear_views() -> void:
	_views.clear()
	for box in [_container_box, _player_box, _backpack_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()


func _rebuild_layout() -> void:
	if not visible:
		return
	_clear_views()
	var other := other_grid()
	_container_panel.visible = other != null
	if other != null:
		_container_box.add_child(_title(_other_title().to_upper(), 22))
		if other == stash:
			# The stash is tall: scroll it.
			var scroll := ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.custom_minimum_size = Vector2(other.width * CELL + 14, 520)
			_container_box.add_child(scroll)
			_add_view(scroll, other)
		else:
			_add_view(_container_box, other)

	_player_box.add_child(_title("EQUIPMENT", 22))
	_value_label = _small("")
	_player_box.add_child(_value_label)
	_add_slot(_player_box, "primary", Vector2i(4, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_player_box.add_child(row)
	_add_slot(row, "secondary", Vector2i(2, 2))
	_add_slot(row, "armor", Vector2i(2, 2))
	_add_slot(_player_box, "backpack", Vector2i(2, 2))
	_player_box.add_child(_small(inventory.pockets.title))
	_add_view(_player_box, inventory.pockets)
	_player_box.add_child(_small(inventory.secure.title + " (kept if you die)"))
	_add_view(_player_box, inventory.secure)

	_backpack_panel.visible = inventory.backpack != null
	if inventory.backpack != null:
		_backpack_box.add_child(_title("BACKPACK", 22))
		_backpack_box.add_child(_small(inventory.backpack.title))
		_add_view(_backpack_box, inventory.backpack)
	_update_labels()


func _add_slot(box: Container, slot: String, cells: Vector2i) -> void:
	var view := EquipSlotView.new(slot, inventory, self, cells)
	box.add_child(view)
	_views.append(view)


func _add_view(box: Container, grid: GridInventory) -> void:
	var view := GridView.new(grid, self)
	box.add_child(view)
	_views.append(view)


func _refresh_views() -> void:
	for view in _views:
		view.call("rebuild")


var _dim: ColorRect
var _columns: HBoxContainer
var _center: CenterContainer
var _footer_hint: Label
var _close_button: Button


func _build() -> void:
	var dim := ColorRect.new()
	_dim = dim
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_center = center

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	root.add_child(columns)
	_columns = columns
	_container_panel = _panel(columns)
	_container_box = _container_panel.get_meta("box")
	var player_panel := _panel(columns)
	_player_box = player_panel.get_meta("box")
	_backpack_panel = _panel(columns)
	_backpack_box = _backpack_panel.get_meta("box")

	_info_label = _small("Hover an item for details")
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_info_label)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)
	_footer_hint = _small("Drag to move/equip · R rotate · Shift+click quick-move · Right-click for options · Tab/E close · the raid doesn't pause!")
	footer.add_child(_footer_hint)
	var close_button := Button.new()
	_close_button = close_button
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
