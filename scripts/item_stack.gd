class_name ItemStack
extends RefCounted
## One item (or a stack of identical items) sitting in a grid at cell (x, y).

var id: String
var count: int
var x: int
var y: int
## Rotated 90 degrees: width and height swap.
var rotated := false


func _init(item_id: String, amount := 1, cell_x := 0, cell_y := 0, is_rotated := false) -> void:
	id = item_id
	count = amount
	x = cell_x
	y = cell_y
	rotated = is_rotated


## Size in cells, taking rotation into account.
func size() -> Vector2i:
	var base := ItemDB.size(id)
	return Vector2i(base.y, base.x) if rotated else base


func space_left() -> int:
	return ItemDB.max_stack(id) - count


func value() -> int:
	return ItemDB.value(id) * count
