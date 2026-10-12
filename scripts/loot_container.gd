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

## Bodies' gear slots, in the same order as the player's (Inventory.SLOTS; not referenced here so the server's
## loot code doesn't pull in player scripts).
const GEAR_SLOTS: Array[String] = ["primary", "secondary", "armor", "helmet", "backpack"]
## A player killed by another player (0.15.28, owner): their body has one more slot, the PMC dog tag's.
const TAG_SLOT := "tag"

## Pockets: the loose loot (for bodies, everything that isn't in a gear slot).
var grid: GridInventory
## Bodies only (owner, 0.11.13: loot a body's loadout): slot -> one-item GridInventory. Empty for other containers.
var gear := {}
var searched := false


func _ready() -> void:
	add_to_group("loot_containers")
	if grid == null:
		grid = GridInventory.new(display_name, grid_size.x, grid_size.y)
	if loot_table != "":
		# Loot by place (0.14.0): the container's `place` (map metadata) adds that place's loot to its table.
		var place: String = get_meta("place", "")
		# One-off finds go in first, so there's always room for them.
		var special: Dictionary = ItemDB.SPECIAL_FINDS.get(String(name), {})
		for id in special:
			if randf() < special[id]:
				grid.add(id, 1)
		for id in ItemDB.TABLE_CHANCES.get(loot_table, {}):
			if randf() < ItemDB.TABLE_CHANCES[loot_table][id]:
				grid.add(id, 1)
		# Something rolled that's too big for this container (a large backpack in a safe) is rolled again, so a
		# container never comes up empty (0.15.21, owner: a vault safe was empty).
		for i in randi_range(min_items, max_items):
			for attempt in 10:
				var id := ItemDB.roll(loot_table, place)
				var count := ItemDB.roll_count(id)
				if grid.add(id, count) < count:
					break
		for stack in grid.stacks:
			stack.durability = ItemDB.found_durability(stack.id)
			stack.found = true


## Pockets and gear slots: gear first (so quick-moving gear into a body fills its slots before the pockets).
func all_grids() -> Array[GridInventory]:
	var list: Array[GridInventory] = []
	for slot in GEAR_SLOTS:
		if gear.has(slot):
			list.append(gear[slot])
	if gear.has(TAG_SLOT):
		list.append(gear[TAG_SLOT])
	list.append(grid)
	return list


func is_empty() -> bool:
	return all_grids().all(func(g: GridInventory) -> bool: return g.is_empty())


## Gives it (empty) gear slots: it's a body.
func add_gear_slots(with_tag := false) -> void:
	if gear.is_empty():
		for slot in GEAR_SLOTS:
			var slot_grid := GridInventory.new(slot.capitalize(), 1, 1)
			slot_grid.slot = slot
			gear[slot] = slot_grid
	if with_tag and not gear.has(TAG_SLOT):
		var tag_grid := GridInventory.new("Dog Tag", 1, 1)
		tag_grid.slot = TAG_SLOT
		gear[TAG_SLOT] = tag_grid


## Everything in it, for the network: the pockets' GridInventory.to_data(), plus (bodies) each gear slot's.
func net_data() -> Array:
	return LootContainer.grids_data(all_grids())


## `grids` as from all_grids() (gear slots, then pockets).
static func grids_data(grids: Array[GridInventory]) -> Array:
	var data := grids[-1].to_data()
	if grids.size() > 1:
		var slots := []
		for i in grids.size() - 1:
			slots.append(grids[i].to_data())
		data.append(slots)
	return data


## Replaces the contents with net_data() from the other side. Ignores anything malformed.
func load_net_data(data: Array) -> void:
	if data.size() == 4 and data[3] is Array and data[3].size() in [GEAR_SLOTS.size(), GEAR_SLOTS.size() + 1]:
		var slots: Array[String] = GEAR_SLOTS.duplicate()
		if data[3].size() > GEAR_SLOTS.size():
			slots.append(TAG_SLOT)
		add_gear_slots(slots.has(TAG_SLOT))
		for i in slots.size():
			var slot_grid: GridInventory = gear[slots[i]]
			slot_grid.load_data(data[3][i] if data[3][i] is Array else [])
			slot_grid.width = 1
			slot_grid.height = 1
		data = data.slice(0, 3)
	grid.load_data(data)


func prompt() -> String:
	if not searched:
		return "Search " + display_name
	if is_empty():
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
## A body (`body`) gets gear slots: the first gun/armor/backpack for each slot goes there, the rest in its pockets.
static func spawn_bag(world: Node, pos: Vector3, bag_name: String, contents: Array, search := 0.0, body := false) -> LootContainer:
	var bag := (load("res://scenes/loot_bag.tscn") as PackedScene).instantiate() as LootContainer
	bag.display_name = bag_name
	bag.loot_table = ""
	bag.search_time = search
	bag.searched = search <= 0.0
	bag.remove_when_empty = true
	# Rolled loot (a scav's body) is found gear: armor turns up worn.
	contents = contents.map(func(entry: Variant) -> Variant:
		if entry is ItemStack:
			return entry
		var stack := ItemStack.new(entry[0], entry[1])
		stack.durability = ItemDB.found_durability(stack.id)
		stack.found = true
		return stack)
	if body:
		bag.add_gear_slots(contents.any(func(entry: Variant) -> bool: return entry is ItemStack and entry.id == "player_tag"))
		var loose := []
		for entry in contents:
			var id: String = entry.id if entry is ItemStack else entry[0]
			var slot := TAG_SLOT if id == "player_tag" else ItemDB.equip_slot(id)
			if slot != "" and bag.gear[slot].is_empty():
				var slot_grid: GridInventory = bag.gear[slot]
				if entry is ItemStack:
					slot_grid.place(entry)
				else:
					slot_grid.add(id, entry[1])
			else:
				loose.append(entry)
		contents = loose
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


## Dropped items go on the pile already at your feet, not a new bag each time (owner, 0.15.16: "really
## cluttered"). The "Dropped Items" bag within 2.5 m of `pos` in this raid, or null.
static func pile_near(world: Node, pos: Vector3) -> LootContainer:
	for node in RaidScope.nodes(world, &"loot_containers"):
		var bag := node as LootContainer
		if (bag != null and bag.remove_when_empty and bag.gear.is_empty() and bag.display_name == "Dropped Items"
				and not bag.is_queued_for_deletion() and bag.global_position.distance_to(pos) < 2.5):
			return bag
	return null


## Adds stacks to this bag, with more rows when they don't fit.
func add_to_pile(contents: Array) -> void:
	for stack: ItemStack in contents:
		var spot := grid.find_spot(stack.id)
		while spot.is_empty() and grid.height < 40:
			grid.height += 1
			spot = grid.find_spot(stack.id)
		if spot.is_empty():
			continue
		stack.set_spot(Vector2i(spot[0], spot[1]), spot[2])
		grid.place(stack)


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
				all_fit = bag.grid.add(stack.id, stack.count, stack.marks()) == 0 and all_fit
			else:
				stack.set_spot(Vector2i(spot[0], spot[1]), spot[2])
				bag.grid.place(stack)
		else:
			all_fit = bag.grid.add(entry[0], entry[1]) == 0 and all_fit
	return all_fit
