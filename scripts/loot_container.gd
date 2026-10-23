@tool
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
## Bodies of AI that wear the small backpack (0.17.12, owner): the same body (loadout slots and all), shown as the
## backpack lying on the ground, with a flap that opens.
const BACKPACK_BODIES: Array[String] = ["Scav Body", "Sniper Body"]
## A player killed by another player (0.15.28, owner): their body has one more slot, the PMC dog tag's.
const TAG_SLOT := "tag"
## Container looks (World art 0.17, owner: containers should fit their place). The map gives a container a `look`
## (metadata): its name, its size (the collision box; it stands on the floor, front facing -z) and its model,
## assets/models/loot/<look>.glb (art_source/scripts/make_loot.py). What's inside still comes from `loot_table`.
const LOOKS := {
	"safe": ["Safe", Vector3(0.8, 0.9, 0.7)], "locker": ["Locker", Vector3(0.75, 2.0, 0.5)],
	"wardrobe": ["Wardrobe", Vector3(1.0, 2.0, 0.55)], "gun_cabinet": ["Gun Cabinet", Vector3(0.9, 1.9, 0.45)],
	"filing": ["Filing Cabinet", Vector3(0.5, 1.3, 0.6)], "med_cabinet": ["Medicine Cabinet", Vector3(0.8, 1.6, 0.4)],
	"toolbox": ["Tool Chest", Vector3(0.8, 1.2, 0.5)], "dresser": ["Dresser", Vector3(1.0, 0.9, 0.5)],
	"kitchen": ["Kitchen Cabinet", Vector3(1.0, 0.95, 0.6)], "chest": ["Old Chest", Vector3(0.9, 0.6, 0.55)],
	"hard_case": ["Hard Case", Vector3(1.0, 0.6, 0.6)], "weapon_case": ["Weapon Case", Vector3(1.2, 0.5, 0.55)],
	"duffel": ["Duffel Bag", Vector3(0.9, 0.4, 0.45)], "stock_boxes": ["Stock Boxes", Vector3(1.0, 0.8, 0.6)],
	"stock_meds": ["Medicine Boxes", Vector3(1.0, 0.8, 0.6)], "stock_tv": ["TV Boxes", Vector3(1.0, 0.65, 0.6)],
	"stock_shoes": ["Shoe Boxes", Vector3(1.0, 0.7, 0.6)], "laundry_cart": ["Laundry Cart", Vector3(1.0, 1.0, 0.6)],
}

## Pockets: the loose loot (for bodies, everything that isn't in a gear slot).
var grid: GridInventory
## Bodies only (owner, 0.11.13: loot a body's loadout): slot -> one-item GridInventory. Empty for other containers.
var gear := {}
var searched := false


func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_preview()
		return
	_apply_look()
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


## Swaps in the model, name and collision box of this container's `look` (if the map gave it one).
func _apply_look() -> void:
	if has_meta("prop"):
		_apply_prop(get_meta("prop"))
		return
	var look: String = get_meta("look", "")
	if not LOOKS.has(look):
		return
	display_name = LOOKS[look][0]
	var size: Vector3 = LOOKS[look][1]
	var back := maxf(0.0, (0.6 - size.z) / 2.0)   # thin ones stand back against the wall
	for child in get_children():
		if child is CollisionShape3D:
			var box := BoxShape3D.new()
			box.size = size
			child.shape = box
			child.position = Vector3(0, size.y / 2.0, back)
		else:
			remove_child(child)
			child.queue_free()
	if DisplayServer.get_name() != "headless":
		var model: Node3D = (load("res://assets/models/loot/%s.glb" % look) as PackedScene).instantiate()
		model.name = "Model"
		model.position.z = back
		add_child(model)
		PixelModel.make_crisp(model)


## A prop of a building's model you can search (0.18.4, owner: anything that looks lootable is lootable): the model
## already draws it, so this is only its box (`prop`: its size; it stands on the floor), with no model of its own.
## It's on the interactable layer only: the map's own box for it (if any) is what you bump into.
func _apply_prop(size: Vector3) -> void:
	collision_layer = 8
	for child in get_children():
		if child is CollisionShape3D:
			var box := BoxShape3D.new()
			box.size = size + Vector3(0.04, 0.02, 0.04)   # (a hair outside the model's own box, so your look ray finds it)
			child.shape = box
			child.position = Vector3(0, size.y / 2.0, 0)
		else:
			remove_child(child)
			child.queue_free()


## In the Godot editor (the script is @tool for this only): show the container's real model instead of the scene's
## default one, so the map looks in the editor the way it does in a raid. Nothing here is saved into the scene.
func _editor_preview() -> void:
	var look: String = get_meta("look", "")
	if not LOOKS.has(look) or not ResourceLoader.exists("res://assets/models/loot/%s.glb" % look):
		return
	var back := maxf(0.0, (0.6 - (LOOKS[look][1] as Vector3).z) / 2.0)
	for child in get_children():
		if child is Node3D and not child is CollisionShape3D:
			child.visible = false
	var model: Node3D = (load("res://assets/models/loot/%s.glb" % look) as PackedScene).instantiate()
	model.position.z = back
	add_child(model)


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


## Swings the lid (a "Lid" node, e.g. a dropped backpack) open or shut (0.17.10, owner). Others online see it too.
func set_open(open: bool) -> void:
	var lid := find_child("Lid", true, false) as Node3D
	if lid == null or not lid.is_inside_tree():
		return
	var tween := lid.create_tween()
	tween.tween_property(lid, "rotation:x", deg_to_rad(lid.get("open_deg") if lid.get("open_deg") != null else 110.0) if open else 0.0, 0.3 if open else 0.25) \
		.set_trans(Tween.TRANS_BACK if open else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func mark_searched() -> void:
	searched = true
	if noise_radius > 0.0:
		RaidScope.call_all(self, &"enemies", &"hear_noise", [global_position, noise_radius])


## Drops a bag in the world holding `contents` ([id, count] pairs, or ItemStacks). Bodies and dropped items.
## A body (`body`) gets gear slots: the first gun/armor/backpack for each slot goes there, the rest in its pockets.
static func spawn_bag(world: Node, pos: Vector3, bag_name: String, contents: Array, search := 0.0, body := false) -> LootContainer:
	var scene := "res://scenes/backpack_bag.tscn" if bag_name in BACKPACK_BODIES else "res://scenes/loot_bag.tscn"
	var bag := (load(scene) as PackedScene).instantiate() as LootContainer
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
		stack.mark_found()
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
