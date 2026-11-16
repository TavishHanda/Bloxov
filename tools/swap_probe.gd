extends SceneTree
## Times swapping guns (primary <-> secondary) in a raid: the select_slot call and the next frames (0.35.28). Not part
## of the smoke test. Clear the shader cache first or results lie:
##   rm -rf ~/.local/share/godot/app_userdata/Bloxov/shader_cache; MAP="" xvfb-run -a godot --rendering-driver opengl3 -s tools/swap_probe.gd
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	RaidMap.scene_path = OS.get_environment("MAP")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 120: await process_frame
	var player := main.get_node("Player")
	var inv = player.get("inventory")
	var gun = player.get("gun")
	print("primary=", inv.equipped("primary").id if inv.equipped("primary") else null, " secondary=", inv.equipped("secondary").id if inv.equipped("secondary") else null)
	if inv.equipped("primary") == null:
		inv.equip("primary", ItemStack.new("ak"))
	if inv.equipped("secondary") == null:
		inv.equip("secondary", ItemStack.new("pistol"))
	gun.select_slot("primary")
	for i in 30: await process_frame
	for round in 4:
		for slot in ["secondary", "primary"]:
			var t := Time.get_ticks_usec()
			gun.select_slot(slot)
			var call_us := Time.get_ticks_usec() - t
			var frames := []
			for f in 6:
				var t2 := Time.get_ticks_usec()
				await process_frame
				frames.append((Time.get_ticks_usec() - t2) / 1000)
			print("round ", round, " -> ", slot, ": call ", call_us / 1000.0, " ms, frames ", frames)
			for i in 20: await process_frame
	quit()
