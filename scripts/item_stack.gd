class_name ItemStack
extends RefCounted
## One item (or a stack of identical items) sitting in a grid at cell (x, y).

var id: String
var count: int
var x: int
var y: int
## Rotated 90 degrees: width and height swap.
var rotated := false
## Weapons only: rounds currently loaded in the gun.
var loaded := 0


func _init(item_id: String, amount := 1, cell_x := 0, cell_y := 0, is_rotated := false) -> void:
	id = item_id
	count = amount
	x = cell_x
	y = cell_y
	rotated = is_rotated


## Size in cells, taking rotation into account.
func size() -> Vector2i:
	return ItemDB.rotated_size(id, rotated)


## The cells it covers in its grid.
func rect() -> Rect2i:
	return Rect2i(Vector2i(x, y), size())


## Moves it to top-left `cell` with the given rotation (doesn't touch any grid).
func set_spot(cell: Vector2i, is_rotated: bool) -> void:
	x = cell.x
	y = cell.y
	rotated = is_rotated


func space_left() -> int:
	return ItemDB.max_stack(id) - count


func value() -> int:
	return ItemDB.value(id) * count
