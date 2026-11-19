extends SceneTree
## Screenshots of the hideout menu at a window size, to check nothing runs off the screen (0.36.25).
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 1920x1080 -s tools/ui_fit_view.gd -- out=/tmp/fit.png


func _initialize() -> void:
	var out := "/tmp/ui_fit_view.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	Profile.reset()
	var hideout = (load("res://scenes/hideout.tscn") as PackedScene).instantiate()
	root.add_child(hideout)
	await process_frame
	# The widest inventory: the Raid Pack (7 wide), as in the owner's screenshot.
	hideout.inventory.unequip("backpack")
	hideout.inventory.equip("backpack", ItemStack.new("backpack_raid", 1))
	hideout.screen.open_stash(Profile.stash)
	for i in 10:
		await process_frame
	var cols: Control = hideout.screen._columns
	print("window ", root.size, " visible ", root.get_visible_rect().size, " factor ", root.content_scale_factor,
		" columns min ", cols.get_combined_minimum_size(), " root min ", cols.get_parent().get_combined_minimum_size(),
		" columns rect ", cols.get_global_rect())
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
