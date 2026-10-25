class_name LootUI
extends Control
## Inventory screen (Tab), and the container + inventory screen when you open loot (F).
## Also used in the hideout (no player): the "other side" is the stash instead of a container, items can be
## sold, and the hideout adds the trader as an extra column (add_column).
## Columns (owner, 0.8.2): [gear: your character, equipment slots] [carried: pockets, secure pocket, backpack]
## [the container you're looting, or the stash in the hideout] (+ [trader] in the hideout).
## Drag & drop items between grids and equipment slots, R rotates while dragging, Shift+click quick-moves,
## right-click for Use / Bind / Unbind / Equip / Unequip / Split / Put in (container or stash) / Drop / Sell.
## Attachments (0.15.1): drop one on a gun to put it on, or right-click it for "Attach to <gun>" (one tap on a
## phone, no dragging needed); right-click a gun to take its attachments off.
## The raid keeps running while this is open.

const CELL := GridView.CELL
const PICKUP_SOUND := preload("res://audio/mag_in.wav")
## Your character on the gear side (the PMC model, for now; owner: swap for new art later).
const CHARACTER_MODEL := preload("res://assets/models/characters/pmc.glb")
const PIXEL_MODEL_SCRIPT := preload("res://scripts/pixel_model.gd")
enum MenuAction { USE, SPLIT, DROP, EQUIP, UNEQUIP, BIND, UNBIND, SELL, GROUND, LOAD, UNLOAD }
## Menu ids past the actions: take attachment slot i off the gun (DETACH + i), put the attachment on your primary
## (ATTACH) or secondary (ATTACH + 1).
const DETACH := 100
const ATTACH := 200
const GUN_SLOTS: Array[String] = ["primary", "secondary"]

## The player in a raid, or null in the hideout.
var player: Player
## Whose inventory this screen shows (the player's, or the hideout's loadout).
var inventory: Inventory
var container: LootContainer = null:
	set(value):
		if container != value:
			# (a dropped backpack's lid opens while you're in it and shuts when you leave it, 0.17.10)
			if is_instance_valid(container):
				container.set_open(false)
			if is_instance_valid(value):
				value.set_open(true)
		container = value
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

var _dim: ColorRect
var _center: CenterContainer
var _columns: HBoxContainer
## Left column: the open container, or the stash in the hideout.
var _other_panel: Control
var _other_box: VBoxContainer
var _player_box: VBoxContainer
var _value_label: Label
## Details for the item under the mouse (or a message like "No room"): its name, then its stats.
var _info_label: Label
var _info_detail: Label
## The item's description line (0.14.0).
var _info_desc: Label
## A gun's stat bars under its details (0.15.12).
var _stat_bars: GunStatBars
var _doll: SubViewportContainer
var _carried_panel: Control
var _carried_box: VBoxContainer
var _footer_hint: Label
var _close_button: Button
## The stash's scroll box, so a rebuild (equipping, putting an attachment on your gun) keeps where you were
## scrolled to instead of jumping back to the top (0.17.13, owner).
var _stash_scroll: ScrollContainer
## In a raid (0.17.13, owner): INVENTORY / QUESTS tabs (bottom left), so the inventory key also shows your quests.
var _tabs: HBoxContainer
var _inventory_tab: Button
var _quests_tab: Button
var _quest_page: QuestTracker
var _info_box: VBoxContainer


func _init(owner_player: Player, owner_inventory: Inventory = null) -> void:
	player = owner_player
	inventory = owner_inventory if owner_inventory != null else owner_player.inventory
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
	_tabs.visible = player != null
	show_quests(false)
	if player != null:
		player.interactor.blocked = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_layout()


## Hideout: show the stash opposite your loadout, always open, no dimmed backdrop.
func open_stash(stash_grid: GridInventory) -> void:
	stash = stash_grid
	_dim.visible = false
	_close_button.visible = false
	_footer_hint.text = "Drag to move/equip · Drag rounds onto a gun to load it · R rotate · Shift+click quick-move · Right-click to sell or for options"
	open_for(null)


## Leaves room at the top of the screen (the hideout's top bar).
func set_top_margin(pixels: float) -> void:
	_center.offset_top = pixels


## Extra panel (e.g. the trader) added as a column on the right.
func add_column(panel: Control) -> void:
	_columns.add_child(panel)


## `recapture` false (Escape, 0.15.2): leave the mouse free. The HUD shows "Click to keep playing" instead.
func close(recapture := true) -> void:
	if not visible:
		return
	_cancel_drag()
	visible = false
	container = null
	_clear_views()
	if player != null:
		player.interactor.blocked = false
		if recapture and not player.controls_locked():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	if player.out_of_fight():
		close()
		return
	# Walked away (or the bag was emptied): keep your inventory open, drop the container.
	if container != null and (not is_instance_valid(container) or container.global_position.distance_to(player.global_position) > 3.5):
		_cancel_drag()
		container = null
		_rebuild_layout()


## True while a container is open (and still exists).
func _has_container() -> bool:
	return container != null and is_instance_valid(container)


## The grid opposite your inventory: the open container's, or the stash in the hideout.
func other_grid() -> GridInventory:
	if _has_container():
		return container.grid
	return stash


## Every grid on the other side: a body's gear slots and pockets, a container's grid, or the stash.
func other_grids() -> Array[GridInventory]:
	if _has_container():
		return container.all_grids()
	var list: Array[GridInventory] = []
	if stash != null:
		list.append(stash)
	return list


func _other_title() -> String:
	if _has_container():
		return container.display_name
	return "Stash"


# --- Moving items --------------------------------------------------------------

## Moves `stack` from `from` to `to` with its top-left at `cell`. If there's a matching stack with room at
## `merge_cell`, merges into it instead. Returns true if anything moved.
func move_stack(stack: ItemStack, from: GridInventory, to: GridInventory, cell: Vector2i, rotated: bool, merge_cell := Vector2i(-1, -1)) -> bool:
	var target := _merge_target(stack, to, merge_cell)
	if target != null:
		var moved := mini(stack.count, target.space_left())
		target.count += moved
		target.merge_marks(stack.marks())
		stack.count -= moved
		if stack.count <= 0:
			from.remove(stack)
		else:
			from.changed.emit()
		to.changed.emit()
		_after_move()
		return true
	if not to.fits(stack.id, cell.x, cell.y, rotated, stack if to == from else null):
		return _swap(stack, from, to, merge_cell, rotated, cell)
	if to == from:
		stack.set_spot(cell, rotated)
		from.changed.emit()
	else:
		from.remove(stack)
		stack.set_spot(cell, rotated)
		to.place(stack)
	# Heals bind themselves when they come in from outside (rearranging your own stuff keeps unbinds).
	if inventory.grids().has(to) and not inventory.grids().has(from):
		inventory.auto_bind(stack.id)
	_after_move()
	return true


## Dropped onto other items it doesn't merge with (owner, 0.14.16; 0.15.21: works the same for every item): it
## goes where it was dropped (or where the item under the pointer starts), and whatever it covers moves out of the
## way: to the spot it came from if it fits there, else any free space on that side, else the other side. If
## something can't go anywhere, nothing moves.
func _swap(stack: ItemStack, from: GridInventory, to: GridInventory, cell: Vector2i, rotated: bool, drop_cell := Vector2i(-1, -1)) -> bool:
	if cell.x < 0 or cell.y < 0:
		return false
	var other := to.stack_at(cell)
	if other == null or other == stack:
		return false
	var old_spot := Vector2i(stack.x, stack.y)
	# Where it was dropped first, then anywhere else on the item under the pointer, nearest first (a grenade dropped
	# on the front of a medkit can sit on its back half, leaving the medkit room to go where the grenade was).
	var size := ItemDB.rotated_size(stack.id, rotated)
	var aim := drop_cell if drop_cell.x >= 0 and drop_cell.y >= 0 else Vector2i(other.x, other.y)
	var spots: Array[Vector2i] = [aim, Vector2i(other.x, other.y)]
	var others: Array[Vector2i] = []
	var area := other.rect()
	for y in range(area.position.y - size.y + 1, area.end.y):
		for x in range(area.position.x - size.x + 1, area.end.x):
			others.append(Vector2i(x, y))
	others.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - aim).length_squared() < (b - aim).length_squared())
	spots.append_array(others)
	for spot in spots:
		if _swap_at(stack, from, to, spot, rotated, old_spot):
			if inventory.grids().has(to) and not inventory.grids().has(from):
				inventory.auto_bind(stack.id)
			_after_move()
			return true
	return false


func _swap_at(stack: ItemStack, from: GridInventory, to: GridInventory, spot: Vector2i, rotated: bool, old_spot: Vector2i) -> bool:
	var size := ItemDB.rotated_size(stack.id, rotated)
	if spot.x < 0 or spot.y < 0 or spot.x + size.x > to.width or spot.y + size.y > to.height:
		return false
	var area := Rect2i(spot, size)
	var covered: Array[ItemStack] = []
	for other in to.stacks:
		if other != stack and other.rect().intersects(area):
			covered.append(other)
	if covered.is_empty():
		return false
	# Remember everything, so it can all go back.
	var before := {}
	for item in covered + [stack]:
		before[item] = [Vector2i(item.x, item.y), item.rotated]
	from.stacks.erase(stack)
	for item in covered:
		to.stacks.erase(item)
	var placed := true
	if not to.fits(stack.id, spot.x, spot.y, rotated):
		placed = false
	else:
		stack.set_spot(spot, rotated)
		to.stacks.append(stack)
	var moved: Array = []   # [item, grid]
	if placed:
		for item in covered:
			var home := _make_room_for(item, from, to, old_spot)
			if home == null:
				placed = false
				break
			moved.append([item, home])
	if not placed:
		# Put everything back the way it was.
		to.stacks.erase(stack)
		for entry in moved:
			(entry[1] as GridInventory).stacks.erase(entry[0])
		for item in before:
			(item as ItemStack).set_spot(before[item][0], before[item][1])
		from.stacks.append(stack)
		for item in covered:
			to.stacks.append(item)
		return false
	from.changed.emit()
	to.changed.emit()
	for entry in moved:
		if inventory.grids().has(entry[1]) and not inventory.grids().has(to):
			inventory.auto_bind((entry[0] as ItemStack).id)
	return true


## Somewhere for an item that was moved out of the way: where the dropped item came from, then any free space on
## the side it was on, then the other side. Places it and returns that grid, or null if there's no room.
func _make_room_for(item: ItemStack, from: GridInventory, to: GridInventory, old_spot: Vector2i) -> GridInventory:
	for turn in [item.rotated, not item.rotated]:
		if from.fits(item.id, old_spot.x, old_spot.y, turn):
			item.set_spot(old_spot, turn)
			from.stacks.append(item)
			return from
	for grid: GridInventory in [to, from]:
		var free := grid.find_spot(item.id)
		if not free.is_empty():
			item.set_spot(Vector2i(free[0], free[1]), free[2])
			grid.stacks.append(item)
			return grid
	return null


## The stack in `grid` at `cell` that `stack` would merge into (same item, has room), or null.
func _merge_target(stack: ItemStack, grid: GridInventory, cell: Vector2i) -> ItemStack:
	if cell.x < 0 or cell.y < 0:
		return null
	var target := grid.stack_at(cell)
	if target != null and target != stack and target.stacks_with(stack.id, stack.marks()) and target.space_left() > 0:
		return target
	return null


## Shift+click: send a stack straight to the other side (container or stash <-> your inventory).
func quick_move(grid: GridInventory, stack: ItemStack) -> void:
	var others := other_grids()
	if others.is_empty():
		return
	# Shift+clicking something in the container/stash sends it to you, and vice versa.
	var to_player := others.has(grid)
	var destinations: Array[GridInventory] = inventory.grids() if to_player else others
	# Gear goes straight into an empty equipment slot.
	var slot := ItemDB.equip_slot(stack.id)
	if to_player and slot != "" and inventory.equipped(slot) == null:
		grid.remove(stack)
		inventory.equip(slot, stack)
		UISounds.play(self, UISounds.EQUIP, -10.0)
		_after_move()
		return
	if ItemDB.max_stack(stack.id) == 1:
		# Move the same object (keeps a gun's loaded rounds).
		if _place_in_first(stack, destinations, grid.remove.bind(stack)):
			if to_player:
				inventory.auto_bind(stack.id)
			_after_move()
		else:
			_no_room(to_player)
		return
	var left := stack.count
	for destination in destinations:
		if left > 0:
			left = destination.add(stack.id, left, stack.marks())
	if left == stack.count:
		_no_room(to_player)
		return
	if left <= 0:
		grid.remove(stack)
	else:
		stack.count = left
		grid.changed.emit()
	if to_player:
		inventory.auto_bind(stack.id)
	_after_move()


## Puts `stack` in the first free spot of the first grid in `grids` that has room. `before_place` (if valid)
## runs after the spot is found and set, just before the stack is placed (e.g. removing it from its old grid).
## Returns false (and changes nothing) if none of them has room.
func _place_in_first(stack: ItemStack, grids: Array[GridInventory], before_place := Callable()) -> bool:
	for grid in grids:
		var spot := grid.find_spot(stack.id)
		if not spot.is_empty():
			stack.set_spot(Vector2i(spot[0], spot[1]), spot[2])
			if before_place.is_valid():
				before_place.call()
			grid.place(stack)
			return true
	return false


# --- Equipment -------------------------------------------------------------------

## Equip a stack from a grid into a slot. If the slot already has something, it swaps into the grid.
func equip_from_grid(grid: GridInventory, stack: ItemStack, slot: String) -> bool:
	if not inventory.slot_accepts(slot, stack.id):
		return false
	var old := inventory.equipped(slot)
	if old != null and not inventory.can_unequip(slot):
		_say("Empty your backpack first")
		return false
	var old_cell := Vector2i(stack.x, stack.y)
	grid.remove(stack)
	if old != null:
		inventory.unequip(slot)
	inventory.equip(slot, stack)
	if old != null:
		_stow(old, grid, old_cell)
	UISounds.play(self, UISounds.EQUIP, -10.0)
	_after_move()
	return true


## Unequip into a specific grid cell (dragging out of a slot).
func unequip_to_grid(slot: String, grid: GridInventory, cell: Vector2i, rotated: bool) -> bool:
	var stack := inventory.equipped(slot)
	if stack == null or not inventory.can_unequip(slot):
		return false
	if not _slot_item_fits(slot, grid, cell, rotated):
		return false
	inventory.unequip(slot)
	stack.set_spot(cell, rotated)
	grid.place(stack)
	_after_move()
	return true


## True if the item in `slot` can go into `grid` at `cell` (a backpack can't go inside itself).
func _slot_item_fits(slot: String, grid: GridInventory, cell: Vector2i, rotated: bool) -> bool:
	var stack := inventory.equipped(slot)
	if stack == null:
		return false
	if slot == "backpack" and grid == inventory.backpack:
		return false
	return grid.fits(stack.id, cell.x, cell.y, rotated)


## Shift+click / menu: take an item off into the first free spot (see _stow for where it ends up).
func unequip_to_inventory(slot: String) -> void:
	if not inventory.can_unequip(slot):
		_say("Empty your backpack first")
		return
	var stack := inventory.unequip(slot)
	_stow(stack, null, Vector2i.ZERO)
	_after_move()


## Puts a loose stack somewhere sensible: `preferred` at `cell`, any of your grids, the container or stash,
## and failing that, the ground in a raid (or a new row at the bottom of the stash in the hideout).
func _stow(stack: ItemStack, preferred: GridInventory, cell: Vector2i) -> void:
	if preferred != null:
		for rotated in [false, true]:
			if preferred.fits(stack.id, cell.x, cell.y, rotated):
				stack.set_spot(cell, rotated)
				preferred.place(stack)
				return
	var candidates: Array[GridInventory] = inventory.grids()
	candidates.append_array(other_grids())
	if not _place_in_first(stack, candidates):
		_drop_or_overflow(stack)


## Nowhere to put it: in a raid it drops on the ground; in the hideout the stash grows to fit it.
func _drop_or_overflow(stack: ItemStack) -> void:
	if player != null and Network.main.in_online_raid():
		# Online, the server makes the bag (so everyone sees the same one).
		Network.main.drop_items([GridInventory.stack_data(stack)])
	elif player != null:
		var drop_pos := player.global_position - player.global_basis.z * 0.8
		var pile := LootContainer.pile_near(player, drop_pos)
		if pile != null:
			pile.add_to_pile([stack])
		else:
			LootContainer.spawn_bag(get_tree().current_scene, drop_pos, "Dropped Items", [stack])
	elif stash != null:
		stack.set_spot(Vector2i(0, stash.height), false)
		stash.height += ItemDB.size(stack.id).y
		stash.place(stack)


func can_drop_on_slot(slot: String) -> bool:
	if drag_stack != null and drag_slot == "" and _fits_gun(inventory.equipped(slot), drag_stack):
		return true
	var gun := inventory.equipped(slot)
	if drag_stack != null and drag_slot == "" and gun != null and ItemDB.kind(gun.id) == "weapon" and ItemDB.kind(drag_stack.id) == "ammo":
		return str(ItemDB.item(gun.id)["ammo"]) == drag_stack.id and can_load(gun)
	if drag_stack == null or not inventory.slot_accepts(slot, drag_stack.id):
		return false
	var current := inventory.equipped(slot)
	return current == null or current == drag_stack or (drag_slot == "" and inventory.can_unequip(slot))


func _after_move() -> void:
	Effects.sound(get_tree().current_scene, PICKUP_SOUND, -10.0)
	if _has_container() and container.remove_when_empty and container.is_empty():
		container.queue_free()
		container = null
		_rebuild_layout.call_deferred()
	_update_labels()


# --- Dragging ------------------------------------------------------------------

func start_drag_from_slot(slot: String) -> void:
	if not inventory.can_unequip(slot):
		_say("Empty your backpack first")
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
	return ItemDB.rotated_size(drag_stack.id, drag_rotated)


## Top-left cell the dragged item would land on in `view`.
func drop_cell(view: GridView) -> Vector2i:
	return view.cell_at_global(get_global_mouse_position()) - _grab_cell


func can_drop_at(view: GridView, cell: Vector2i) -> bool:
	if attach_target(view) != null or (drag_slot == "" and _ammo_target(view, drag_stack) != null):
		return true
	if drag_slot != "":
		return _slot_item_fits(drag_slot, view.grid, cell, drag_rotated)
	if _merge_target(drag_stack, view.grid, cell + _grab_cell) != null:
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
		# Only the visible part counts: a view inside a ScrollContainer (the stash) is clipped by it.
		var rect := view.get_global_rect()
		var scroll := view.get_parent() as ScrollContainer
		if scroll != null:
			rect = rect.intersection(scroll.get_global_rect())
		if rect.has_point(mouse):
			hover_view = view
		view.queue_redraw()


func _finish_drag() -> void:
	var stack := drag_stack
	var from := drag_from
	var slot := drag_slot
	var rotated := drag_rotated
	var view := hover_view
	_cancel_drag()
	# The stack was used up or moved while being dragged (e.g. a heal used from the hotbar): nothing to drop.
	if slot == "" and (from == null or not from.stacks.has(stack)):
		_refresh_views()
		return
	var gun: ItemStack = null
	if view != null:
		drag_stack = stack   # (attach_target looks at what's being dragged)
		drag_from = from
		gun = attach_target(view)
		drag_stack = null
		drag_from = null
	var loading := _ammo_target(view, stack) if slot == "" else null
	if gun != null:
		attach_from_grid(from, stack, gun, (view as GridView).grid if view is GridView else null)
	elif loading != null:
		load_gun(loading, stack, from)
	elif view is GridView:
		var grid_view := view as GridView
		var cell := drop_cell(grid_view)
		if slot != "":
			unequip_to_grid(slot, grid_view.grid, cell, rotated)
		else:
			move_stack(stack, from, grid_view.grid, cell, rotated, cell + _grab_cell)
	elif view is EquipSlotView and slot == "":
		equip_from_grid(from, stack, (view as EquipSlotView).slot)
	elif view == null and _can_drop_out(from, slot) and not _over_panels(get_global_mouse_position()):
		# Let go on empty space, outside the inventory (owner, 0.16.10): drop it on the ground.
		if slot != "":
			_drop_or_overflow(inventory.unequip(slot))
			_after_move()
		else:
			drop_to_ground(from, stack)
	_refresh_views()


## Only your own things, and only in a raid (the hideout has no ground).
func _can_drop_out(from: GridInventory, slot: String) -> bool:
	if player == null:
		return false
	if slot != "":
		return inventory.can_unequip(slot)
	return from != null and inventory.grids().has(from)


## True when `pos` (screen) is on or between the inventory's panels, where letting go does nothing.
func _over_panels(pos: Vector2) -> bool:
	return _columns.get_global_rect().grow(12.0).has_point(pos)


# --- Attachments (0.15.1) ---------------------------------------------------------

## The gun the attachment being dragged would go on if dropped on `view` (a grid cell, a body's slot or your own
## equipment slot), or null.
func attach_target(view: Control) -> ItemStack:
	if drag_stack == null or drag_slot != "":
		return null
	var gun: ItemStack = null
	if view is SlotGridView:
		var grid := (view as SlotGridView).grid
		gun = grid.stacks[0] if not grid.stacks.is_empty() else null
	elif view is GridView:
		gun = (view as GridView).grid.stack_at(drop_cell(view as GridView) + _grab_cell)
	elif view is EquipSlotView:
		gun = inventory.equipped((view as EquipSlotView).slot)
	return gun if _fits_gun(gun, drag_stack) else null


## Hideout: the gun that rounds `ammo` dropped on `view` would load (0.17.13: drag rounds onto a gun), or null.
func _ammo_target(view: Control, ammo: ItemStack) -> ItemStack:
	if view == null or ammo == null or ItemDB.kind(ammo.id) != "ammo":
		return null
	var gun: ItemStack = null
	if view is GridView:
		gun = (view as GridView).grid.stack_at(drop_cell(view as GridView) + _grab_cell)
	elif view is EquipSlotView:
		gun = inventory.equipped((view as EquipSlotView).slot)
	if gun == null or gun == ammo or ItemDB.kind(gun.id) != "weapon" or str(ItemDB.item(gun.id)["ammo"]) != ammo.id:
		return null
	return gun if can_load(gun) else null


func _fits_gun(gun: ItemStack, part: ItemStack) -> bool:
	return (gun != null and part != null and gun != part and ItemDB.kind(gun.id) == "weapon"
		and ItemDB.attachment_slot_for(gun.id, part.id) != "")


## Takes attachment `part` out of `from` and puts it on `gun` (in `gun_grid`, or equipped when null). Whatever it
## replaces, and rounds a smaller mag can't hold, go back near where they came from.
func attach_from_grid(from: GridInventory, part: ItemStack, gun: ItemStack, gun_grid: GridInventory) -> void:
	var spot := Vector2i(part.x, part.y)
	from.remove(part)
	var result := inventory.attach(gun, part.id, part.found)
	_return_parts(result, gun.id, from if from != null else gun_grid, spot)
	(gun_grid if gun_grid != null else from).changed.emit()
	_say("%s on the %s" % [ItemDB.display_name(part.id), ItemDB.display_name(gun.id)])
	_after_move()


## Takes the attachment in `slot` off `gun` (in `gun_grid`, or equipped when null).
func detach(gun: ItemStack, slot: String, gun_grid: GridInventory) -> void:
	var result := inventory.detach(gun, slot)
	if result[0] == "":
		return
	_return_parts(result, gun.id, gun_grid, Vector2i(-1, -1))
	if gun_grid != null:
		gun_grid.changed.emit()
	_after_move()


## [attachment id or "", spare rounds, found] from Inventory.attach/detach: puts them in `grid` (at `cell` if it
## fits), else anywhere of yours, else the other side, else the ground.
func _return_parts(result: Array, gun_id: String, grid: GridInventory, cell: Vector2i) -> void:
	var loose: Array[ItemStack] = []
	if result[0] != "":
		var part := ItemStack.new(result[0])
		part.found = result[2]   # (a part off a looted gun stays found in raid, 0.17.13)
		loose.append(part)
	if int(result[1]) > 0:
		loose.append(ItemStack.new(ItemDB.item(gun_id)["ammo"], int(result[1])))
	for stack in loose:
		if grid != null and cell.x >= 0 and grid.fits(stack.id, cell.x, cell.y, false):
			stack.set_spot(cell, false)
			grid.place(stack)
			cell = Vector2i(-1, -1)
			continue
		var candidates: Array[GridInventory] = []
		if grid != null:
			candidates.append(grid)
		candidates.append_array(inventory.grids())
		candidates.append_array(other_grids())
		if not _place_in_first(stack, candidates):
			_drop_or_overflow(stack)


# --- Loading guns in the hideout (0.17.13, owner: friends kept going into raids with empty guns) ------------

## Hideout only: in a raid, loading goes through reloading (it takes time there).
func can_load(gun: ItemStack) -> bool:
	return (player == null and gun != null and ItemDB.kind(gun.id) == "weapon"
		and gun.loaded < int(ItemDB.weapon_stats(gun)["mag"]) and _ammo_count(str(ItemDB.item(gun.id)["ammo"])) > 0)


func can_unload(gun: ItemStack) -> bool:
	return player == null and gun != null and ItemDB.kind(gun.id) == "weapon" and gun.loaded > 0


## Where loading takes rounds from: the stash first (so what you carry stays as spares), then what you carry.
func _ammo_grids() -> Array[GridInventory]:
	var grids: Array[GridInventory] = []
	if stash != null:
		grids.append(stash)
	grids.append_array(inventory.grids())
	return grids


func _ammo_count(ammo: String) -> int:
	var total := 0
	for grid in _ammo_grids():
		total += grid.count_of(ammo)
	return total


## Fills `gun`'s mag from your rounds (`from_stack` first, when you dragged a stack of rounds onto it).
## Returns how many rounds went in.
func load_gun(gun: ItemStack, from_stack: ItemStack = null, from_grid: GridInventory = null) -> int:
	if not can_load(gun):
		return 0
	var ammo := str(ItemDB.item(gun.id)["ammo"])
	var need := int(ItemDB.weapon_stats(gun)["mag"]) - gun.loaded
	var taken := 0
	if from_stack != null and from_grid != null and from_stack.id == ammo and from_grid.stacks.has(from_stack):
		taken = mini(need, from_stack.count)
		from_stack.count -= taken
		if from_stack.count <= 0:
			from_grid.remove(from_stack)
		else:
			from_grid.changed.emit()
	for grid in _ammo_grids():
		if taken < need:
			taken += grid.take(ammo, need - taken)
	gun.loaded += taken
	inventory.changed.emit()
	_say("Loaded %d into the %s (%d/%d)" % [taken, ItemDB.display_name(gun.id), gun.loaded, int(ItemDB.weapon_stats(gun)["mag"])])
	_after_move()
	_refresh_views()
	return taken


## Takes the rounds out of `gun` (in `grid`, or equipped when null): next to it, else anywhere you have room
## (what doesn't fit stays in the gun).
## Rounds from the free kit's gun stay free kit (they sell for nothing, like the kit).
func unload_gun(gun: ItemStack, grid: GridInventory) -> bool:
	if not can_unload(gun):
		return false
	var ammo := str(ItemDB.item(gun.id)["ammo"])
	var marks := ItemStack.FREE if gun.free else 0
	var grids: Array[GridInventory] = []
	if grid != null:
		grids.append(grid)
	for other in inventory.grids() + _ammo_grids():
		if not grids.has(other):
			grids.append(other)
	var left := gun.loaded
	for other in grids:
		if left > 0:
			left = other.add(ammo, left, marks)
	if left == gun.loaded:
		_no_room(true)
		return false
	gun.loaded = left   # (whatever found no room stays in the gun)
	inventory.changed.emit()
	_say("Unloaded the %s" % ItemDB.display_name(gun.id))
	_after_move()
	_refresh_views()
	return true


func _add_load_entries(gun: ItemStack) -> void:
	if can_load(gun):
		_menu.add_item("Load", MenuAction.LOAD)
	if can_unload(gun):
		_menu.add_item("Unload (%d)" % gun.loaded, MenuAction.UNLOAD)


## Menu entries to take each attachment off `gun`.
func _add_detach_entries(gun: ItemStack) -> void:
	var slots := ItemDB.attachment_slots(gun.id)
	for i in slots.size():
		if gun.attachments.has(slots[i]):
			_menu.add_item("Remove " + ItemDB.display_name(gun.attachments[slots[i]]), DETACH + i)


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
	if ItemDB.kind(stack.id) in ["heal", "drink"] and player != null:
		_menu.add_item("Use" if ItemDB.kind(stack.id) == "heal" else "Drink", MenuAction.USE)
		if inventory.hotbar.has(stack.id):
			_menu.add_item("Unbind (key %d)" % (inventory.hotbar.find(stack.id) + 3), MenuAction.UNBIND)
		elif inventory.can_bind(stack.id):
			_menu.add_item("Bind to hotbar", MenuAction.BIND)
	if ItemDB.equip_slot(stack.id) != "":
		_menu.add_item("Equip", MenuAction.EQUIP)
	if ItemDB.kind(stack.id) == "weapon":
		_add_load_entries(stack)
		_add_detach_entries(stack)
	elif ItemDB.kind(stack.id) == "attachment":
		for i in GUN_SLOTS.size():
			var gun := inventory.equipped(GUN_SLOTS[i])
			if _fits_gun(gun, stack):
				_menu.add_item("Attach to " + ItemDB.display_name(gun.id), ATTACH + i)
	if stack.count > 1:
		_menu.add_item("Split", MenuAction.SPLIT)
	_add_drop_entry(other_grids().has(grid))
	if sell_handler.is_valid():
		_menu.add_item("Sell for %s" % ItemDB.money(price_handler.call(stack)), MenuAction.SELL)
	_popup_menu()


func open_slot_menu(slot: String) -> void:
	_menu_slot = slot
	_menu_grid = null
	_menu_stack = null
	_menu.clear()
	_menu.add_item("Unequip", MenuAction.UNEQUIP)
	if ItemDB.kind(inventory.equipped(slot).id) == "weapon":
		_add_load_entries(inventory.equipped(slot))
		_add_detach_entries(inventory.equipped(slot))
	_add_drop_entry(false)
	_popup_menu()


## "Put in <container/stash>" if there's another side and the item isn't already in it, and "Drop" (on the
## ground; raid only), also while looting something (0.15.19, owner).
func _add_drop_entry(in_other_grid: bool) -> void:
	if other_grid() != null and not in_other_grid:
		_menu.add_item("Put in " + _other_title(), MenuAction.DROP)
		if player != null:
			_menu.add_item("Drop", MenuAction.GROUND)
	elif player != null:
		_menu.add_item("Drop", MenuAction.DROP)


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
	if action >= ATTACH:
		var gun := inventory.equipped(GUN_SLOTS[action - ATTACH])
		if _fits_gun(gun, stack):
			attach_from_grid(grid, stack, gun, null)
		return
	if action >= DETACH:
		detach(stack, ItemDB.attachment_slots(stack.id)[action - DETACH], grid)
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
		MenuAction.GROUND:
			drop_to_ground(grid, stack)
		MenuAction.LOAD:
			load_gun(stack)
		MenuAction.UNLOAD:
			unload_gun(stack, grid)
	_update_labels()


func _on_slot_menu(action: int) -> void:
	var slot := _menu_slot
	_menu_slot = ""
	if inventory.equipped(slot) == null:
		return
	if action >= DETACH:
		var gun := inventory.equipped(slot)
		detach(gun, ItemDB.attachment_slots(gun.id)[action - DETACH], null)
		return
	match action:
		MenuAction.LOAD:
			load_gun(inventory.equipped(slot))
		MenuAction.UNLOAD:
			unload_gun(inventory.equipped(slot), null)
		MenuAction.UNEQUIP:
			unequip_to_inventory(slot)
		MenuAction.GROUND:
			if not inventory.can_unequip(slot):
				_say("Empty your backpack first")
				return
			_drop_or_overflow(inventory.unequip(slot))
			_after_move()
		MenuAction.DROP:
			if not inventory.can_unequip(slot):
				_say("Empty your backpack first")
				return
			var into := other_grids()
			if not into.is_empty() and into.all(func(g: GridInventory) -> bool: return g.find_spot(inventory.equipped(slot).id).is_empty()):
				_say("No room in %s" % _other_title())
				return
			var stack := inventory.unequip(slot)
			if not _place_in_first(stack, into):
				_drop_or_overflow(stack)
			_after_move()


func _no_room(to_player: bool) -> void:
	_say("No room in your inventory" if to_player else "No room in %s" % _other_title())


## Moves half a stack into a free spot: the same grid if there's room, otherwise another of yours.
func split_stack(grid: GridInventory, stack: ItemStack) -> bool:
	var half := stack.count / 2
	if half <= 0:
		return false
	var candidates: Array[GridInventory] = [grid]
	for other in inventory.grids():
		if other != grid:
			candidates.append(other)
	var shrink_original := func() -> void:
		stack.count -= half
		grid.changed.emit()
	var piece := ItemStack.new(stack.id, half)
	piece.set_marks(stack.marks())
	return _place_in_first(piece, candidates, shrink_original)


## Drop on the ground, even with a container open (0.15.19, owner: a Drop option while looting).
func drop_to_ground(grid: GridInventory, stack: ItemStack) -> void:
	if player == null:
		return
	grid.remove(stack)
	_drop_or_overflow(stack)
	_after_move()


## Drop on the ground, or into the open container / stash.
func drop_stack(grid: GridInventory, stack: ItemStack) -> void:
	if other_grid() != null and not other_grids().has(grid):
		quick_move(grid, stack)
		return
	if player == null:
		return
	grid.remove(stack)
	_drop_or_overflow(stack)
	_after_move()


# --- Info / labels ---------------------------------------------------------------

## A message in the details area ("No room in ...", "Empty your backpack first").
func _say(text: String) -> void:
	_info_label.text = text
	_info_label.remove_theme_color_override("font_color")
	_info_detail.text = ""
	_info_desc.text = ""
	_stat_bars.clear()


func show_info(stack: ItemStack) -> void:
	_info_label.text = stack.title() + ("  x%d" % stack.count if stack.count > 1 else "")
	if stack.free:
		_info_label.text += "  (free kit: sells for $0)"
	elif stack.found and Quests.wants(stack.id):
		_info_label.text += "  (found in raid)"
	_info_label.add_theme_color_override("font_color", ItemDB.color(stack.id))
	_info_detail.text = details(stack, price_handler.call(stack) if price_handler.is_valid() else -1)
	_info_desc.text = ItemDB.description(stack.id)
	_stat_bars.show_gun(stack)


## One line about an item: rarity, size, what it does, what it's worth (and sells for, if `sells_for` >= 0).
## Shared with the trader screen (0.21.4).
static func details(stack: ItemStack, sells_for := -1) -> String:
	var data := ItemDB.item(stack.id)
	var rarity: String = data["rarity"]
	var cells := ItemDB.size(stack.id)
	var parts: PackedStringArray = [rarity.capitalize(), "%d×%d" % [cells.x, cells.y]]
	match ItemDB.kind(stack.id):
		"heal":
			parts.append("Heals %d HP" % int(data["heal"]))
		"ammo":
			parts.append("Ammo")
		"weapon":
			parts.append("%s · %d damage · %d rpm · %d-round mag · %d loaded" % [str(data["slot"]).capitalize(), int(data["damage"]),
				int(data["rpm"]), int(ItemDB.weapon_stats(stack)["mag"]), stack.loaded])
			var on: PackedStringArray = []
			for slot: String in stack.attachments:
				on.append(ItemDB.display_name(stack.attachments[slot]))
			if not on.is_empty():
				parts.append("With " + ", ".join(on))
		"attachment":
			parts.append("Attachment · fits " + ", ".join(_guns_it_fits(stack.id)))
		"armor":
			parts.append("Takes %d%% off damage" % roundi(float(data["reduction"]) * stack.condition() * 100.0))
			if ItemDB.max_durability(stack.id) > 0:
				parts.append("Durability %d/%d" % [stack.durability, ItemDB.max_durability(stack.id)])
		"helmet":
			parts.append("Takes %d%% off hits to the head" % roundi(ItemDB.reduction(stack) * 100.0))
			if ItemDB.max_durability(stack.id) > 0:
				parts.append("Durability %d/%d" % [stack.durability, ItemDB.max_durability(stack.id)])
		"key":
			parts.append("Key" + (" · %d/%d uses left" % [stack.durability, ItemDB.max_durability(stack.id)] if ItemDB.max_durability(stack.id) > 0 else ""))
		"backpack":
			parts.append("%d×%d storage" % [int(data["grid"][0]), int(data["grid"][1])])
	parts.append("Worth %s" % ItemDB.money(stack.value()) + (" (%s each)" % ItemDB.money(ItemDB.value(stack.id)) if stack.count > 1 else ""))
	if sells_for >= 0:
		parts.append("Sells for %s" % ItemDB.money(sells_for))
	return "  ·  ".join(parts)


## Names of the guns an attachment goes on.
static func _guns_it_fits(part_id: String) -> PackedStringArray:
	var names: PackedStringArray = []
	for id: String in ItemDB.ITEMS:
		if ItemDB.kind(id) == "weapon" and ItemDB.attachment_slot_for(id, part_id) != "":
			names.append(ItemDB.short_name(id))
	return names


func _update_labels() -> void:
	if _value_label != null:
		_value_label.text = "Carrying %s" % ItemDB.money(inventory.total_value())


# --- Layout --------------------------------------------------------------------

func _clear_views() -> void:
	_views.clear()
	for box in [_other_box, _player_box, _carried_box]:
		for child in box.get_children():
			box.remove_child(child)
			if child != _doll:
				child.queue_free()


func _rebuild_layout() -> void:
	if not visible:
		return
	var scrolled := _stash_scroll.scroll_vertical if is_instance_valid(_stash_scroll) else 0
	_stash_scroll = null
	_clear_views()
	_build_other_column()
	_build_equipment_column()
	_build_carried_column()
	_update_labels()
	if _stash_scroll != null and scrolled > 0:
		_restore_scroll.call_deferred(_stash_scroll, scrolled)


## (The new scroll box only takes the value once its contents are laid out.)
func _restore_scroll(scroll: ScrollContainer, value: int) -> void:
	if not is_instance_valid(scroll):
		return
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = value


## Right column: the open container, or the stash in the hideout (hidden if neither).
func _build_other_column() -> void:
	var other := other_grid()
	_other_panel.visible = other != null
	if other == null:
		return
	if other == stash:
		# Title, and a SORT button (0.15.16, owner: auto sort), big enough to tap.
		var header := HBoxContainer.new()
		var title := _title(_other_title().to_upper())
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var sort_button := Button.new()
		sort_button.name = "SortButton"
		sort_button.text = "SORT"
		sort_button.focus_mode = Control.FOCUS_NONE
		sort_button.custom_minimum_size = Vector2(96, 44)
		style_button(sort_button)
		# First tap asks "SURE?" (0.15.18, owner), the second sorts; it goes back to SORT after 3 s.
		sort_button.pressed.connect(func() -> void:
			_cancel_drag()
			if sort_button.text == "SORT":
				sort_button.text = "SURE?"
				style_button(sort_button, 20, HudStyle.BRASS)
				# (a Timer on the button, so it goes when the button does: a scene-tree timer outliving it errored)
				var back := Timer.new()
				back.one_shot = true
				back.wait_time = 3.0
				back.timeout.connect(func() -> void:
					back.queue_free()
					if sort_button.text == "SURE?":
						sort_button.text = "SORT"
						style_button(sort_button))
				sort_button.add_child(back)
				back.start()
				return
			sort_button.text = "SORT"
			style_button(sort_button)
			stash.sort())
		header.add_child(sort_button)
		_other_box.add_child(header)
	else:
		_other_box.add_child(_title(_other_title().to_upper()))
	if other == stash:
		# The stash is tall: scroll it.
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(other.width * CELL + 14, 480)  # (fits the hideout with its hint line under it)
		_other_box.add_child(scroll)
		_add_view(scroll, other)
		_stash_scroll = scroll
	elif _has_container() and not container.gear.is_empty():
		# A body: its loadout, then its pockets (owner, 0.11.13). A player's body killed by another player: their
		# dog tag in its own slot on top (0.15.28, owner).
		if container.gear.has(LootContainer.TAG_SLOT):
			_add_slot_view(_other_box, LootContainer.TAG_SLOT, Vector2i(2, 1))
		_add_slot_rows(_other_box, _add_slot_view)
		_other_box.add_child(_section("Pockets"))
		_add_view(_other_box, other)
	else:
		_add_view(_other_box, other)


func _add_slot_view(box: Container, slot: String, cells: Vector2i) -> void:
	var view := SlotGridView.new(container.gear[slot], self, cells)
	box.add_child(view)
	_views.append(view)


## Left column: your character and the equipment slots.
func _build_equipment_column() -> void:
	_player_box.add_child(_title("EQUIPMENT"))
	_value_label = _title("", 20)
	_value_label.add_theme_color_override("font_color", HudStyle.BRASS)
	_player_box.add_child(_value_label)
	_player_box.add_child(_doll)
	_add_slot_rows(_player_box, _add_slot)


## The equipment slots, laid out the same for you and for a body (owner, 0.14.7): primary on top, secondary under
## it (with the backpack), then armor and helmet together.
func _add_slot_rows(box: Container, add: Callable) -> void:
	add.call(box, "primary", Vector2i(4, 2))
	for pair in [["secondary", "backpack"], ["armor", "helmet"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		box.add_child(row)
		for slot: String in pair:
			add.call(row, slot, Vector2i(2, 2))


## Middle column: everything you carry: pockets, the backpack's grid, then the secure pocket at the bottom.
func _build_carried_column() -> void:
	_carried_box.add_child(_title("INVENTORY"))
	_carried_box.add_child(_section(inventory.pockets.title))
	_add_view(_carried_box, inventory.pockets)
	if inventory.backpack != null:
		_carried_box.add_child(_section(inventory.backpack.title))
		_add_view(_carried_box, inventory.backpack)
	else:
		_carried_box.add_child(_section("No backpack"))
	# Owner (0.9.0): the secure pocket goes last, under everything else.
	_carried_box.add_child(_section(inventory.secure.title + " (kept if you die)"))
	_add_view(_carried_box, inventory.secure)


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


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_center.add_child(root)

	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 10)
	root.add_child(_columns)
	_quest_page = QuestTracker.new()
	_quest_page.visible = false
	root.add_child(_quest_page)
	var player_panel := _panel(_columns)
	_player_box = player_panel.get_meta("box")
	_carried_panel = _panel(_columns)
	_carried_box = _carried_panel.get_meta("box")
	_other_panel = _panel(_columns)
	_other_box = _other_panel.get_meta("box")
	_doll = _build_doll()

	# Details: the item under the mouse (name in its rarity color, then its stats), or messages.
	# Empty until you point at something (owner: no placeholder text); keeps its height so nothing jumps.
	var info_box := VBoxContainer.new()
	_info_box = info_box
	info_box.custom_minimum_size = Vector2(0, 86)
	info_box.add_theme_constant_override("separation", 0)
	root.add_child(info_box)
	_info_label = _title("", 30)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_box.add_child(_info_label)
	_info_detail = _small("")
	_info_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_box.add_child(_info_detail)
	_info_desc = _small("")
	_info_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_desc.modulate = Color(1, 1, 1, 0.55)
	info_box.add_child(_info_desc)
	_stat_bars = GunStatBars.new()
	info_box.add_child(_stat_bars)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)
	# (In the footer, so the tabs don't make the screen taller: it's already tight at 720p.)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	footer.add_child(_tabs)
	_inventory_tab = _tab_button("INVENTORY", false)
	_quests_tab = _tab_button("QUESTS", true)
	_footer_hint = _small("Drag to move/equip · R rotate · Shift+click quick-move · Right-click for options · Tab/F close · the raid doesn't pause!")
	footer.add_child(_footer_hint)
	_close_button = Button.new()
	_close_button.text = "CLOSE"
	_close_button.focus_mode = Control.FOCUS_NONE
	style_button(_close_button)
	_close_button.pressed.connect(close)
	footer.add_child(_close_button)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


## A tab button (the CLOSE button's size).
func _tab_button(text: String, quests: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	style_button(button)
	button.pressed.connect(show_quests.bind(quests))
	_tabs.add_child(button)
	return button


## Switches between your inventory and the QUESTS tab (the quest tracker's list).
func show_quests(quests: bool) -> void:
	if quests:
		_cancel_drag()
		_quest_page.refresh(null)
	_columns.visible = not quests
	_info_box.visible = not quests
	_quest_page.visible = quests
	_mark_tab(_inventory_tab, not quests)
	_mark_tab(_quests_tab, quests)


## The open tab: lighter, with a brass edge. (Restyling the stylebox only: style_button again would draw the text twice.)
func _mark_tab(button: Button, active: bool) -> void:
	for state in ["normal", "hover"]:
		var box := button.get_theme_stylebox(state) as StyleBoxFlat
		if box != null:
			box.bg_color = (HudStyle.FACE_HI if active else HudStyle.FACE).lightened(0.15 if state == "hover" else 0.0)
			box.border_color = HudStyle.BRASS if active else Color.BLACK


func quests_shown() -> bool:
	return _quest_page.visible


func _notification(what: int) -> void:
	# The character view is moved between layouts; free it if it's between them when the screen goes.
	if what == NOTIFICATION_PREDELETE and _doll != null and _doll.get_parent() == null:
		_doll.free()


## Your character, drawn by its own little camera (its own world, so it never shows up in the raid).
## Kept across rebuilds (only moved between layouts).
func _build_doll() -> SubViewportContainer:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(176, 150)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.size = Vector2i(176, 150)
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	holder.add_child(view)
	var model := CHARACTER_MODEL.instantiate()
	model.set_script(PIXEL_MODEL_SCRIPT)
	model.name = "Character"
	model.rotation.y = PI + 0.5
	view.add_child(model)
	var camera := Camera3D.new()
	camera.fov = 30.0
	# Aimed by its transform (it isn't in the scene tree yet, so look_at() can't be used).
	var eye := Vector3(0, 1.05, 4.6)
	camera.transform = Transform3D(Basis.looking_at(Vector3(0, 1.0, 0) - eye), eye)
	view.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.7, 0.5, 0)
	view.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	view.add_child(environment)
	return holder


## A column: a gunmetal plate (the raid HUD's "Ammo Can" look, 0.8.8) around a margin and a VBox (meta "box").
func _panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 0)  # (260 until 0.19.6: room for the bigger cells)
	skin_panel(panel)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	panel.set_meta("box", box)
	return panel


## Draws a PanelContainer as a gunmetal plate (also used by the hideout's trader column and top bar).
static func skin_panel(panel: PanelContainer, bevel := 4.0) -> void:
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.draw.connect(func() -> void: HudStyle.draw_plate(panel, Rect2(Vector2.ZERO, panel.size), HudStyle.OUTLINE, HudStyle.FACE, bevel))


## Headings and item names: the HUD's pixel number font (Jersey 10) with a hard shadow.
func _title(text: String, font_size := 30) -> Label:
	var label := Label.new()
	label.text = text
	HudStyle.style_label(label, font_size if font_size % 10 == 0 else 30)
	return label


## A section name over a grid (POCKETS, SECURE POCKET...): pixel caps, dimmed.
func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	HudStyle.style_label(label, 20, HudStyle.INK_DIM)
	return label


## Gives a Button the gunmetal look (lighter when hovered, darker when pressed) with the pixel font.
## `face` paints it another color (START RAID is hazard yellow, with dark text).
## The label is drawn by us, centered on its pixels in the face (the engine centers on font metrics, which left
## the pixel font off-center), in the letter-spaced font.
static func style_button(button: Button, font_size := 20, face := HudStyle.FACE) -> void:
	var dark_text := face.get_luminance() > 0.5
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = {"normal": face, "hover": face.lightened(0.15), "pressed": face.darkened(0.3),
			"disabled": HudStyle.DEEP, "focus": face}[state]
		box.border_color = Color.BLACK
		box.set_border_width_all(2)
		box.border_width_bottom = 4 if state != "pressed" else 2
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		button.add_theme_stylebox_override(state, box)
	# Sized with the real font; drawn by hand (the built-in text is made invisible).
	button.add_theme_font_override("font", HudStyle.spaced_font(font_size))
	button.add_theme_font_size_override("font_size", font_size)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(color_name, Color(0, 0, 0, 0))
	button.draw.connect(func() -> void:
		var pressed := button.get_draw_mode() == BaseButton.DRAW_PRESSED or button.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED
		var bottom := 2.0 if pressed else 4.0
		var face_rect := Rect2(2, 2, button.size.x - 4, button.size.y - 2 - bottom)
		var color := (HudStyle.DEEP if dark_text else HudStyle.INK) if not button.disabled else HudStyle.INK_DIM
		HudStyle.draw_centered(button, button.text, face_rect, font_size, color, HudStyle.spaced_font(font_size), not dark_text))


func _small(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.7)
	label.add_theme_font_size_override("font_size", 13)
	return label
