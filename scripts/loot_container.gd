class_name LootContainer
extends StaticBody3D
## Anything you can search with E: crates, lockers, safes, bodies, dropped bags.
## Holds a GridInventory. Rolls its contents from `loot_table` when the raid starts.

@export var display_name := "Crate"
## Table in ItemDB.LOOT_TABLES. Empty = starts empty (bags filled from code).
@export var loot_table := "crate"
@export var min_items := 1
@export var max_items := 3
@export var grid_size := Vector2i(4, 3)
## Seconds of holding F to search it the first time. You're exposed while searching.
@export var search_time := 1.5
## If > 0, finishing the search makes noise that alerts enemies in this radius.
@export var noise_radius := 0.0
## Bags disappear once emptied.
@export var remove_when_empty := false

var grid: GridInventory
var searched := false


func _ready() -> void:
	add_to_group("loot_containers")
	if grid == null:
		grid = GridInventory.new(display_name, grid_size.x, grid_size.y)
	if loot_table != "":
		for i in randi_range(min_items, max_items):
			var id := ItemDB.roll(loot_table)
			grid.add(id, ItemDB.roll_count(id))


func prompt() -> String:
	if not searched:
		return "Search " + display_name
	if grid.is_empty():
		return display_name + " (empty)"
	return "Open " + display_name


## Hold time for the next interaction (0 = instant).
func interact_time() -> float:
	return 0.0 if searched else search_time


func mark_searched() -> void:
	searched = true
	if noise_radius > 0.0:
		RaidScope.call_all(self, &"enemies", &"hear_noise", [global_position, noise_radius])


## Drops a bag in the world holding `contents` ([id, count] pairs, or ItemStacks). Bodies and dropped items.
static func spawn_bag(world: Node, pos: Vector3, bag_name: String, contents: Array, search := 0.0) -> LootContainer:
	var bag := (load("res://scenes/loot_bag.tscn") as PackedScene).instantiate() as LootContainer
	bag.display_name = bag_name
	bag.loot_table = ""
	bag.search_time = search
	bag.searched = search <= 0.0
	bag.remove_when_empty = true
	# Big enough for whatever's going in: at least as big as the biggest item, plus rows until everything fits.
	var cells := Vector2i(4, 3)
	for entry in contents:
		var id: String = entry.id if entry is ItemStack else entry[0]
		cells = cells.max(ItemDB.size(id))
	var rows := cells.y + 1
	while not _fill_bag(bag, bag_name, cells.x, rows, contents) and rows < cells.y + 12:
		rows += 1
	world.add_child(bag)
	bag.global_position = pos
	bag.rotation.y = randf() * TAU
	return bag


## Puts `contents` into a fresh w x h grid on the bag. False if something didn't fit.
static func _fill_bag(bag: LootContainer, bag_name: String, w: int, h: int, contents: Array) -> bool:
	bag.grid = GridInventory.new(bag_name, w, h)
	var all_fit := true
	for entry in contents:
		if entry is ItemStack:
			# Keep the stack itself (a gun keeps its loaded rounds).
			var stack := entry as ItemStack
			var spot := bag.grid.find_spot(stack.id)
			if spot.is_empty():
				all_fit = bag.grid.add(stack.id, stack.count) == 0 and all_fit
			else:
				stack.set_spot(Vector2i(spot[0], spot[1]), spot[2])
				bag.grid.place(stack)
		else:
			all_fit = bag.grid.add(entry[0], entry[1]) == 0 and all_fit
	return all_fit
