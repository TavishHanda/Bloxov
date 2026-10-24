extends SceneTree
## A screenshot of the hideout's inventory screen with some loot in it, for checking the inventory look.
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 1600x900 -s tools/inventory_view.gd -- out=/tmp/inv.png


func _initialize() -> void:
	var out := "/tmp/inventory_view.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	root.size = Vector2i(1600, 900)
	Profile.reset()
	for entry in [["sniper", 1], ["backpack_large", 1], ["armor_light", 1], ["helmet_good", 1], ["holy_grail", 1], ["gpu", 1], ["gold_bar", 1], ["medkit", 1], ["rifle_ammo", 60], ["grenade", 2],
			["energy_drink", 1], ["cpu", 1], ["diamond_ring", 1], ["water", 1], ["beans", 2], ["scope_4x", 1]]:
		Profile.stash.add(entry[0], entry[1])
	var hideout = (load("res://scenes/hideout.tscn") as PackedScene).instantiate()
	root.add_child(hideout)
	await process_frame
	await process_frame
	var inv: Inventory = hideout.inventory
	for entry in [["bandage", 3], ["water", 1], ["phone", 1], ["duct_tape", 1], ["gunpowder", 1], ["dog_tag", 1]]:
		inv.add(entry[0], entry[1])
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
