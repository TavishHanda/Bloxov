class_name Inventory
extends Node
## Everything the player carries: pockets (always) and a backpack grid.
## (Step 2 of the inventory redesign adds equipment slots, a backpack slot and the secure pocket.)

signal changed

@export var pockets_size := Vector2i(4, 1)
@export var backpack_size := Vector2i(5, 4)

var pockets: GridInventory
var backpack: GridInventory


func _ready() -> void:
	pockets = GridInventory.new("Pockets", pockets_size.x, pockets_size.y)
	backpack = GridInventory.new("Backpack", backpack_size.x, backpack_size.y)
	for grid in grids():
		grid.changed.connect(changed.emit)


## Grids in the order items are added: pockets first, then backpack.
func grids() -> Array[GridInventory]:
	return [pockets, backpack]


## Adds items, filling stacks and free space across all grids. Returns how many didn't fit.
func add(id: String, count := 1) -> int:
	var left := count
	# Top up existing stacks anywhere first, then free space in order.
	for grid in grids():
		for stack in grid.stacks:
			if left > 0 and stack.id == id and stack.space_left() > 0:
				var moved := mini(left, stack.space_left())
				stack.count += moved
				left -= moved
	for grid in grids():
		if left > 0:
			left = grid.add(id, left)
	changed.emit()
	return left


func count_of(id: String) -> int:
	var total := 0
	for grid in grids():
		total += grid.count_of(id)
	return total


## Removes up to `amount`, backpack first so pocket stacks stay handy. Returns how many were removed.
func take(id: String, amount: int) -> int:
	var taken := 0
	for grid in [backpack, pockets]:
		if taken < amount:
			taken += grid.take(id, amount - taken)
	return taken


func total_value() -> int:
	var total := 0
	for grid in grids():
		total += grid.total_value()
	return total


func clear() -> void:
	for grid in grids():
		grid.clear()


## Every stack the player carries, e.g. for the end-of-raid screen.
func all_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for grid in grids():
		result.append_array(grid.stacks)
	return result


## [grid, stack] of the heal item that best fits how hurt you are, or [] if none.
func find_heal(missing_health: int) -> Array:
	var best: Array = []
	var best_score := INF
	for grid in grids():
		for stack in grid.stacks:
			if ItemDB.kind(stack.id) != "heal":
				continue
			# Prefer the item whose heal amount is closest to what's missing (don't waste a medkit on a scratch).
			var score := absf(float(ItemDB.item(stack.id)["heal"]) - missing_health)
			if score < best_score:
				best_score = score
				best = [grid, stack]
	return best
