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
## Armor points left, or a key's uses left (0.14.0). Items that don't wear keep 0.
var durability := 0
## Weapons only (0.15.1): attachment slot -> attachment item id, e.g. {"scope": "red_dot"}.
var attachments := {}
## A PMC dog tag's owner (0.15.28, owner): the player it was taken off. Shown as "Name's Dog Tag".
var label := ""
const LABEL_MAX := 24
## From the free kit (0.16.5, owner): worth nothing to traders, so the kit can't be sold for money. The same item
## found or bought sells as normal. Free kit stacks only stack with other free kit stacks (0.16.6: the rounds and
## bandage are marked too).
var free := false
## Found in raid (0.16.13, owner): looted in a raid rather than bought or brought in. Only found items count for
## trader quest hand-ins. Found stacks only stack with found stacks (like free kit ones), so buying can't top them up.
var found := false
## Both marks as one number, for adding and stacking (items only stack when their marks match).
const FREE := 1
const FOUND := 2


func marks() -> int:
	return (FREE if free else 0) | (FOUND if found else 0)


## Whether stacks of `item_id` with these marks stack together. Free kit only with free kit; the found mark only
## matters while an open quest wants the item (0.17.2, owner: ammo and the rest stack again). Stacking a found stack
## with an unfound one leaves it unfound (see merge_marks).
static func stackable(item_id: String, a: int, b: int) -> bool:
	if a & FREE != b & FREE:
		return false
	return a & FOUND == b & FOUND or not Quests.wants(item_id)


## Can `other` be stacked onto this one (same item, marks that stack)?
func stacks_with(other_id: String, other_marks: int) -> bool:
	return other_id == id and stackable(id, marks(), other_marks)


## Something with `other_marks` was stacked onto this: it's only found if both were.
func merge_marks(other_marks: int) -> void:
	found = found and other_marks & FOUND != 0


func set_marks(value: int) -> void:
	free = value & FREE != 0
	found = value & FOUND != 0


func _init(item_id: String, amount := 1, cell_x := 0, cell_y := 0, is_rotated := false) -> void:
	id = item_id
	count = amount
	x = cell_x
	y = cell_y
	rotated = is_rotated
	durability = ItemDB.max_durability(item_id)


## The name to show: a PMC dog tag's carries its owner's name.
func title() -> String:
	if label != "":
		return "%s's Dog Tag" % label
	return ItemDB.display_name(id)


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


## How worn it is: 1 = new, 0 = worn out (always 1 for items that don't wear).
func condition() -> float:
	var most := ItemDB.max_durability(id)
	return clampf(float(durability) / most, 0.0, 1.0) if most > 0 else 1.0


## What it's worth: worn gear and part-used keys are worth less (30% when worn out). A gun's attachments count too.
func value() -> int:
	var total := 0 if free else roundi(ItemDB.value(id) * count * (0.3 + 0.7 * condition()))
	for slot: String in attachments:
		total += ItemDB.value(attachments[slot])
	return total


## Keeps only attachments that are real items and fit this gun (saves and network data aren't trusted).
func clean_attachments(data: Variant) -> void:
	attachments = {}
	if not data is Dictionary:
		return
	for slot: Variant in data:
		var part: Variant = data[slot]
		if slot is String and part is String and ItemDB.ITEMS.has(part) and ItemDB.attachment_slot_for(id, part) == slot:
			attachments[slot] = part
