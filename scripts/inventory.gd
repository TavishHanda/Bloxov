class_name Inventory
extends Node
## Everything the player carries:
##  - equipment slots: primary, secondary, armor, backpack (each holds one ItemStack or nothing)
##  - grids: pockets (always), the equipped backpack's grid, and the secure pocket (survives death)
##  - hotbar: item ids bound to keys 3-6

signal changed
## Something was equipped or unequipped (the screen rebuilds, the gun/armor update).
signal equipment_changed

const SLOTS: Array[String] = ["primary", "secondary", "armor", "backpack"]
const HOTBAR_SIZE := 4

@export var pockets_size := Vector2i(4, 1)
@export var secure_size := Vector2i(2, 2)

var pockets: GridInventory
var secure: GridInventory
## The equipped backpack's grid, or null with no backpack.
var backpack: GridInventory = null
var equipment := {"primary": null, "secondary": null, "armor": null, "backpack": null}
## Item ids bound to hotbar keys 3, 4, 5, 6 ("" = empty).
var hotbar: Array[String] = ["", "", "", ""]


func _ready() -> void:
	pockets = GridInventory.new("Pockets", pockets_size.x, pockets_size.y)
	secure = GridInventory.new("Secure Pocket", secure_size.x, secure_size.y)
	pockets.changed.connect(changed.emit)
	secure.changed.connect(changed.emit)


## Grids in the order items are added: pockets, backpack, then secure pocket.
func grids() -> Array[GridInventory]:
	var list: Array[GridInventory] = [pockets]
	if backpack != null:
		list.append(backpack)
	list.append(secure)
	return list


# --- Equipment -------------------------------------------------------------------

func equipped(slot: String) -> ItemStack:
	return equipment[slot]


func slot_accepts(slot: String, id: String) -> bool:
	return ItemDB.equip_slot(id) == slot


## Puts a stack into an empty slot. Returns false if the slot is taken or the item doesn't go there.
func equip(slot: String, stack: ItemStack) -> bool:
	if equipment[slot] != null or not slot_accepts(slot, stack.id):
		return false
	stack.rotated = false
	equipment[slot] = stack
	if slot == "backpack":
		var size: Array = ItemDB.item(stack.id)["grid"]
		backpack = GridInventory.new(ItemDB.display_name(stack.id), size[0], size[1])
		backpack.changed.connect(changed.emit)
	equipment_changed.emit()
	changed.emit()
	return true


## A backpack can only come off when it's empty (v1).
func can_unequip(slot: String) -> bool:
	if equipment[slot] == null:
		return false
	return slot != "backpack" or backpack == null or backpack.is_empty()


## Takes the item out of a slot and returns it (or null if it can't come off).
func unequip(slot: String) -> ItemStack:
	if not can_unequip(slot):
		return null
	var stack: ItemStack = equipment[slot]
	equipment[slot] = null
	if slot == "backpack":
		backpack = null
	equipment_changed.emit()
	changed.emit()
	return stack


## Armor damage reduction (0 to 1).
func armor_reduction() -> float:
	var armor: ItemStack = equipment["armor"]
	return float(ItemDB.item(armor.id)["reduction"]) if armor != null else 0.0


# --- Items -----------------------------------------------------------------------

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
	if left < count:
		auto_bind(id)
	changed.emit()
	return left


func count_of(id: String) -> int:
	var total := 0
	for grid in grids():
		total += grid.count_of(id)
	return total


## Removes up to `amount`: backpack, then pockets, then the secure pocket last. Returns how many were removed.
func take(id: String, amount: int) -> int:
	var taken := 0
	var order: Array[GridInventory] = []
	if backpack != null:
		order.append(backpack)
	order.append(pockets)
	order.append(secure)
	for grid in order:
		if taken < amount:
			taken += grid.take(id, amount - taken)
	return taken


## [grid, stack] of the first stack of an item, or [] if you don't have any.
func find(id: String) -> Array:
	for grid in grids():
		for stack in grid.stacks:
			if stack.id == id:
				return [grid, stack]
	return []


func total_value() -> int:
	var total := 0
	for stack in all_stacks():
		total += stack.value()
	return total


## Empties the grids (equipment stays).
func clear() -> void:
	for grid in grids():
		grid.clear()


## Every stack the player has: equipment and all grids.
func all_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for slot in SLOTS:
		if equipment[slot] != null:
			result.append(equipment[slot])
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


# --- Hotbar ----------------------------------------------------------------------

## Binds an item to the first free hotbar key. Returns the index (0 = key 3) or -1.
func bind_to_hotbar(id: String) -> int:
	if hotbar.has(id):
		return hotbar.find(id)
	var free := hotbar.find("")
	if free >= 0:
		hotbar[free] = id
		changed.emit()
	return free


func unbind(id: String) -> void:
	var index := hotbar.find(id)
	if index >= 0:
		hotbar[index] = ""
		changed.emit()


## Heals bind themselves to the hotbar when you pick them up, if there's a free key.
func auto_bind(id: String) -> void:
	if ItemDB.kind(id) == "heal" and not hotbar.has(id):
		bind_to_hotbar(id)
