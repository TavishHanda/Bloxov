class_name GridInventory
extends RefCounted
## A Tetris-style grid of cells holding ItemStacks (pockets, backpack, containers, stash).

signal changed

var title: String
var width: int
var height: int
var stacks: Array[ItemStack] = []
## A body's gear slot ("primary", "armor", ...): holds one item that goes in that slot, whatever its size
## (it sits at 0, 0). Empty = a normal grid.
var slot := ""


func _init(grid_title: String, grid_width: int, grid_height: int) -> void:
	title = grid_title
	width = grid_width
	height = grid_height


func is_empty() -> bool:
	return stacks.is_empty()


## True if an item of this id/rotation can sit with its top-left at (x, y). `ignore` is skipped (the stack being moved).
func fits(id: String, x: int, y: int, rotated: bool, ignore: ItemStack = null) -> bool:
	if slot != "":
		# (a player's body's TAG slot holds their PMC dog tag, 0.15.28)
		var goes_here := id == "player_tag" if slot == "tag" else ItemDB.equip_slot(id) == slot
		return goes_here and stacks.all(func(stack: ItemStack) -> bool: return stack == ignore)
	var size := ItemDB.rotated_size(id, rotated)
	if x < 0 or y < 0 or x + size.x > width or y + size.y > height:
		return false
	var rect := Rect2i(x, y, size.x, size.y)
	for stack in stacks:
		if stack != ignore and rect.intersects(stack.rect()):
			return false
	return true


func stack_at(cell: Vector2i) -> ItemStack:
	for stack in stacks:
		if stack.rect().has_point(cell):
			return stack
	return null


## First free spot for an item, as [x, y, rotated], or [] if it doesn't fit anywhere.
func find_spot(id: String) -> Array:
	for rotated in [false, true]:
		for y in height:
			for x in width:
				if fits(id, x, y, rotated):
					return [x, y, rotated]
	return []


## Adds up to `count` of an item to existing stacks only (no new stacks). Returns how many didn't fit.
## `marks` (ItemStack.FREE/FOUND): free kit items (0.16.6) only stack with free kit items, so they can't be mixed into
## sellable stacks; found-in-raid ones (0.16.13) only with found ones while a quest wants them (0.17.2).
func top_up(id: String, count: int, marks := 0) -> int:
	var left := count
	for stack in stacks:
		if left <= 0:
			break
		if stack.stacks_with(id, marks) and stack.space_left() > 0:
			var moved := mini(left, stack.space_left())
			stack.count += moved
			stack.merge_marks(marks)
			left -= moved
	if left < count:
		changed.emit()
	return left


## Adds `count` of an item: tops up existing stacks first, then uses free space. Returns how many didn't fit.
func add(id: String, count := 1, marks := 0) -> int:
	var left := top_up(id, count, marks)
	while left > 0:
		var spot := find_spot(id)
		if spot.is_empty():
			break
		var amount := mini(left, ItemDB.max_stack(id))
		var stack := ItemStack.new(id, amount, spot[0], spot[1], spot[2])
		stack.set_marks(marks)
		stacks.append(stack)
		left -= amount
	changed.emit()
	return left


## Puts an existing stack at its own x/y (caller checked `fits`).
func place(stack: ItemStack) -> void:
	if slot != "":
		stack.set_spot(Vector2i.ZERO, false)
	stacks.append(stack)
	changed.emit()


## Auto sort (0.15.16, owner, the stash's SORT button): tops up part stacks, then lays everything out again by
## kind (guns, gear, ammo, meds... valuables last), big items first. Adds rows if something no longer fits.
const SORT_ORDER: Array[String] = ["weapon", "armor", "helmet", "backpack", "attachment", "ammo", "throwable", "heal",
	"drink", "key", "valuable"]

func sort() -> void:
	var list: Array[ItemStack] = []
	for stack in stacks:
		var merged := false
		if ItemDB.max_stack(stack.id) > 1:
			for other in list:
				if other.stacks_with(stack.id, stack.marks()) and other.space_left() > 0:
					var moved := mini(other.space_left(), stack.count)
					other.count += moved
					other.merge_marks(stack.marks())
					stack.count -= moved
					if stack.count == 0:
						merged = true
						break
		if not merged:
			list.append(stack)
	list.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		var ka := SORT_ORDER.find(ItemDB.kind(a.id))
		var kb := SORT_ORDER.find(ItemDB.kind(b.id))
		if ka != kb:
			return ka < kb
		var area_a := ItemDB.size(a.id).x * ItemDB.size(a.id).y
		var area_b := ItemDB.size(b.id).x * ItemDB.size(b.id).y
		if area_a != area_b:
			return area_a > area_b
		if a.id != b.id:
			return a.id < b.id
		return a.count > b.count)
	stacks.clear()
	for stack in list:
		var spot := find_spot(stack.id)
		while spot.is_empty():
			height += 1
			spot = find_spot(stack.id)
		stack.set_spot(Vector2i(spot[0], spot[1]), spot[2])
		stacks.append(stack)
	changed.emit()


func remove(stack: ItemStack) -> void:
	stacks.erase(stack)
	changed.emit()


func count_of(id: String) -> int:
	var total := 0
	for stack in stacks:
		if stack.id == id:
			total += stack.count
	return total


## Removes up to `amount` of an item (smallest stacks first). Returns how many were removed.
func take(id: String, amount: int) -> int:
	var matching: Array[ItemStack] = []
	for stack in stacks:
		if stack.id == id:
			matching.append(stack)
	matching.sort_custom(func(a: ItemStack, b: ItemStack) -> bool: return a.count < b.count)
	var taken := 0
	for stack in matching:
		if taken >= amount:
			break
		var moved := mini(amount - taken, stack.count)
		stack.count -= moved
		taken += moved
		if stack.count <= 0:
			stacks.erase(stack)
	if taken > 0:
		changed.emit()
	return taken


func total_value() -> int:
	var total := 0
	for stack in stacks:
		total += stack.value()
	return total


func clear() -> void:
	stacks.clear()
	changed.emit()


# --- Sending over the network (online loot) ------------------------------------------

## [width, height, [[id, count, x, y, rotated, loaded, durability, attachments], ...]]
func to_data() -> Array:
	var list := []
	for stack in stacks:
		list.append(stack_data(stack))
	return [width, height, list]


## Replaces the contents (and size) with `data` from to_data(). Ignores anything malformed.
func load_data(data: Array) -> void:
	stacks.clear()
	if data.size() == 3 and data[0] is int and data[1] is int and data[2] is Array:
		width = clampi(data[0], 1, 20)
		height = clampi(data[1], 1, 40)
		for entry in data[2]:
			var stack := data_stack(entry)
			if stack != null and fits(stack.id, stack.x, stack.y, stack.rotated):
				stacks.append(stack)
	changed.emit()


static func stack_data(stack: ItemStack) -> Array:
	return [stack.id, stack.count, stack.x, stack.y, stack.rotated, stack.loaded, stack.durability, stack.attachments, stack.label, stack.marks()]


## An ItemStack from stack_data(), or null if it isn't a real item.
static func data_stack(entry: Variant) -> ItemStack:
	if not (entry is Array and entry.size() in [6, 7, 8, 9, 10] and entry[0] is String and ItemDB.ITEMS.has(entry[0])):
		return null
	var stack := ItemStack.new(entry[0], clampi(int(entry[1]), 1, ItemDB.max_stack(entry[0])), int(entry[2]), int(entry[3]), bool(entry[4]))
	stack.loaded = maxi(int(entry[5]), 0)
	if entry.size() >= 7:
		stack.durability = clampi(int(entry[6]), 0, ItemDB.max_durability(stack.id))
	if entry.size() >= 8:
		stack.clean_attachments(entry[7])
	if entry.size() >= 9 and entry[8] is String and stack.id == "player_tag":
		stack.label = (entry[8] as String).left(ItemStack.LABEL_MAX)
	if entry.size() >= 10:
		# (0.16.6 sent a bool: the free mark; 0.16.13 sends both marks as a number)
		stack.set_marks(int(entry[9]) if not entry[9] is bool else (ItemStack.FREE if entry[9] else 0))
	return stack
