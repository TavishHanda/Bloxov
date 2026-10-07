class_name Inventory
extends Node
## The player's backpack: a list of item ids. Each item takes ItemDB.slots(id) of `capacity` slots.

signal changed

@export var capacity := 10

var items: Array[String] = []


func used_slots() -> int:
	var used := 0
	for id in items:
		used += ItemDB.slots(id)
	return used


func free_slots() -> int:
	return capacity - used_slots()


func can_fit(id: String) -> bool:
	return ItemDB.slots(id) <= free_slots()


func add(id: String) -> bool:
	if not can_fit(id):
		return false
	items.append(id)
	changed.emit()
	return true


func remove_at(index: int) -> String:
	var id := items[index]
	items.remove_at(index)
	changed.emit()
	return id


func clear() -> void:
	items.clear()
	changed.emit()


func total_value() -> int:
	var total := 0
	for id in items:
		total += ItemDB.value(id)
	return total


## Index of the heal item that best fits how hurt you are, or -1.
func find_heal(missing_health: int) -> int:
	var best := -1
	var best_score := INF
	for i in items.size():
		var id := items[i]
		if ItemDB.kind(id) != "heal":
			continue
		# Prefer the item whose heal amount is closest to what's missing (don't waste a medkit on a scratch).
		var score := absf(float(ItemDB.item(id)["heal"]) - missing_health)
		if score < best_score:
			best_score = score
			best = i
	return best
