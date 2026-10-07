class_name LootContainer
extends StaticBody3D
## Anything you can search with E: crates, lockers, safes, scav bodies, dropped bags.
## Holds a list of item ids. Rolls its contents from `loot_table` when the raid starts.

@export var display_name := "Crate"
## Table in ItemDB.LOOT_TABLES. Empty = starts empty (bags filled from code).
@export var loot_table := "crate"
@export var min_items := 1
@export var max_items := 3
## Seconds of holding E to search it the first time. You're exposed while searching.
@export var search_time := 1.5
## If > 0, finishing the search makes noise that alerts enemies in this radius.
@export var noise_radius := 0.0
## Bags disappear once emptied.
@export var remove_when_empty := false

var items: Array[String] = []
var searched := false


func _ready() -> void:
	add_to_group("loot_containers")
	if loot_table != "":
		for i in randi_range(min_items, max_items):
			items.append(ItemDB.roll(loot_table))


func prompt() -> String:
	if not searched:
		return "Search " + display_name
	if items.is_empty():
		return display_name + " (empty)"
	return "Open " + display_name


## Hold time for the next interaction (0 = instant).
func interact_time() -> float:
	return 0.0 if searched else search_time


func mark_searched() -> void:
	searched = true
	if noise_radius > 0.0:
		get_tree().call_group("enemies", "hear_noise", global_position, noise_radius)


## Drops a bag of items in the world (scav bodies, items you drop).
static func spawn_bag(world: Node, pos: Vector3, bag_name: String, contents: Array[String], search := 0.0) -> LootContainer:
	var bag := (load("res://scenes/loot_bag.tscn") as PackedScene).instantiate() as LootContainer
	bag.display_name = bag_name
	bag.loot_table = ""
	bag.items = contents
	bag.search_time = search
	bag.searched = search <= 0.0
	bag.remove_when_empty = true
	world.add_child(bag)
	bag.global_position = pos
	bag.rotation.y = randf() * TAU
	return bag
