extends SceneTree
## Headless gameplay test, run by CI:  godot --headless -s tests/smoke_test.gd
## Loads the main scene, fires the gun at the dummy, reloads, and lets a scav shoot the player.

var _failures := 0


func _initialize() -> void:
	# Watchdog: if a script error stops the test mid-way, fail instead of hanging CI.
	create_timer(150.0).timeout.connect(func() -> void:
		print("SMOKE TEST: TIMED OUT (a script error probably stopped the test; see errors above)")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	# The HUD pauses the game while the mouse isn't captured (always, in headless). Turn that off.
	main.get_node("HUD").process_mode = Node.PROCESS_MODE_DISABLED
	paused = false
	seed(12345)
	await _frames(5)

	# Clear out spawned enemies so the test is predictable.
	main.get_node("EnemySpawner").queue_free()
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	await _frames(5)

	var player := main.get_node("Player") as Player
	var raid := main.get_node("Raid") as Raid
	# The raid puts the player at a random spawn; use the one facing the dummy.
	player.teleport_to(Vector3(0, 0.1, -10))
	await physics_frame
	var gun := player.gun
	var dummy := main.get_node("TargetDummy") as Node3D
	var dummy_health := dummy.get_node("Health") as Health
	_check(player != null and gun != null and dummy_health != null, "scene has player, gun and dummy")

	# Aim straight at the dummy's chest and fire one perfectly accurate shot.
	gun.base_spread_deg = 0.0
	gun.moving_spread_deg = 0.0
	_aim(player, dummy.global_position + Vector3(0, 1.0, 0))
	await physics_frame
	await physics_frame
	var before := dummy_health.current
	gun.shoot_once()
	_check(dummy_health.current == before - gun.damage, "body shot deals %d damage (got %d)" % [gun.damage, before - dummy_health.current])
	_check(gun.in_mag == gun.mag_size - 1, "shooting uses ammo")

	# Headshot.
	await create_timer(0.3).timeout
	_aim(player, dummy.global_position + Vector3(0, 1.65, 0))
	await physics_frame
	await physics_frame
	before = dummy_health.current
	gun.shoot_once()
	var expected := roundi(gun.damage * gun.headshot_multiplier)
	_check(before - dummy_health.current == expected, "headshot deals %d damage (got %d)" % [expected, before - dummy_health.current])

	# Reload.
	gun.start_reload()
	await create_timer(gun.reload_time + 0.3).timeout
	_check(gun.in_mag == gun.mag_size and not gun.is_reloading, "reload refills the magazine")

	# A scav behind the player should spot them and shoot.
	var enemy := (load("res://scenes/scav.tscn") as PackedScene).instantiate() as Scav
	main.add_child(enemy)
	enemy.global_position = player.global_position + player.global_basis.z * 8.0
	var hp := player.health.current
	await create_timer(4.0).timeout
	_check(player.health.current < hp, "scav shoots the player (hp %d -> %d)" % [hp, player.health.current])

	# Killing the enemy removes it.
	enemy.health.take_damage(9999)
	await _frames(3)
	_check(not is_instance_valid(enemy), "dead enemy is removed")

	# Movement: hold keys and measure. Face down the open road (+Z).
	player.teleport_to(Vector3(0, 0.1, -10))
	player.rotation.y = PI
	await create_timer(0.3).timeout
	Input.action_press("move_forward")
	await create_timer(1.0).timeout
	var walk := player.horizontal_speed()
	_check(absf(walk - player.walk_speed) < 0.3, "walk speed ~%.1f (got %.2f)" % [player.walk_speed, walk])
	Input.action_press("sprint")
	await create_timer(1.0).timeout
	var sprint := player.horizontal_speed()
	_check(player.is_sprinting() and absf(sprint - player.sprint_speed) < 0.3, "sprint speed ~%.1f (got %.2f)" % [player.sprint_speed, sprint])
	_check(not gun.is_ready_to_fire(), "can't fire while sprinting")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await physics_frame
	await physics_frame
	_check(not gun.is_ready_to_fire(), "gun needs a moment to come up after sprinting")
	await create_timer(gun.raise_time + 0.15).timeout
	_check(gun.is_ready_to_fire(), "gun is ready %.2fs after sprinting" % gun.raise_time)
	await create_timer(0.8).timeout
	_check(player.horizontal_speed() < 0.1, "player comes to a stop")
	# Sprint only works forwards.
	Input.action_press("move_back")
	Input.action_press("sprint")
	await create_timer(0.8).timeout
	_check(not player.is_sprinting() and player.horizontal_speed() < player.walk_speed, "can't sprint backwards (%.2f)" % player.horizontal_speed())
	Input.action_release("move_back")
	Input.action_release("sprint")
	await create_timer(0.8).timeout
	# Crouch: slower, lower, silent. Walking makes noise.
	var noises: Array[float] = []
	player.noise_made.connect(func(_pos: Vector3, radius: float) -> void: noises.append(radius))
	player.rotation.y = PI
	Input.action_press("move_forward")
	await create_timer(1.5).timeout
	_check(not noises.is_empty() and noises.max() == player.walk_noise, "walking footsteps make noise (%d steps)" % noises.size())
	noises.clear()
	player.set_crouching(true)
	await create_timer(1.5).timeout
	var crouch_speed := player.horizontal_speed()
	_check(player.is_crouching and absf(crouch_speed - player.crouch_speed) < 0.3, "crouch speed ~%.1f (got %.2f)" % [player.crouch_speed, crouch_speed])
	_check(player.eye_height() < player.stand_eye_height - 0.4, "crouching lowers the camera (%.2f)" % player.eye_height())
	_check(noises.is_empty(), "crouch-walking is silent")
	# Sprinting stands you up, and drains stamina until you can't sprint.
	Input.action_press("sprint")
	await create_timer(0.5).timeout
	_check(not player.is_crouching and player.is_sprinting(), "sprinting stands you up")
	await create_timer(1.0).timeout
	_check(noises.max() == player.sprint_noise, "sprinting is loud")
	_check(player.stamina < player.max_stamina - 10.0, "sprinting drains stamina (%.0f)" % player.stamina)
	player.stamina = 1.0
	await create_timer(0.5).timeout
	_check(player.is_exhausted and not player.is_sprinting(), "out of stamina = no sprint")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await create_timer(player.stamina_regen_delay + 2.0).timeout
	_check(player.stamina > 20.0, "stamina regenerates (%.0f)" % player.stamina)
	player.stamina = player.max_stamina
	player.is_exhausted = false
	await create_timer(0.5).timeout

	# Jump height.
	var ground_y := player.global_position.y
	var peak := ground_y
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	for i in 60:
		await physics_frame
		peak = maxf(peak, player.global_position.y)
	var jump_height := peak - ground_y
	_check(jump_height > 0.4 and jump_height < 0.9, "jump height %.2fm" % jump_height)

	# Loot containers rolled their contents.
	var rolled := 0
	for node in get_nodes_in_group("loot_containers"):
		var container := node as LootContainer
		if container.loot_table != "" and not container.grid.is_empty():
			rolled += 1
	_check(rolled >= 10, "containers have loot (%d)" % rolled)
	_check(ItemDB.money(1234567) == "$1,234,567", "money formatting")

	# Imported crate model: right size, crisp pixel filtering.
	var crate := (load("res://scenes/loot_crate.tscn") as PackedScene).instantiate() as Node3D
	main.add_child(crate)
	crate.global_position = Vector3(0, 0, 60)
	await process_frame
	var meshes := crate.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() > 0, "crate uses the imported model")
	if meshes.size() > 0:
		var crate_mesh := meshes[0] as MeshInstance3D
		# The model and its collision box must match, or bullets and players hit invisible walls.
		var box := crate_mesh.get_aabb().size
		var collision_size := ((crate.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D).size
		_check(box.distance_to(collision_size) < 0.05, "crate model %s matches its collision %s" % [box, collision_size])
		var crate_material := crate_mesh.mesh.surface_get_material(0) as BaseMaterial3D
		_check(crate_material != null and crate_material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			and crate_material.albedo_texture != null, "crate texture is crisp (nearest filtering)")
	crate.queue_free()

	# Character models (scav and PMC): imported .glb, one outfit option per slot, facing forward.
	for path: String in ["res://scenes/scav.tscn", "res://scenes/pmc.tscn"]:
		var character := (load(path) as PackedScene).instantiate() as Scav
		main.add_child(character)
		character.global_position = Vector3(10, 0.1, 60)
		await process_frame
		var model := character.model as PixelModel
		_check(model != null, "%s uses an imported pixel model" % character.name)
		if model == null:
			continue
		var slots := model.outfit_slots()
		var one_each := slots.size() >= 6
		for slot: String in slots:
			var showing := 0
			for option: String in slots[slot]:
				if (slots[slot][option][0] as Node3D).visible:
					showing += 1
			one_each = one_each and showing == 1
		_check(one_each, "%s shows one outfit option per slot (%d slots)" % [character.name, slots.size()])
		var tops := {}
		for i in 12:
			model.pick_outfit()
			tops[model.outfit["Top"]] = true
		_check(tops.size() >= 2, "%s outfits vary (%d different tops in 12 spawns)" % [character.name, tops.size()])
		var muzzle_local := character.to_local(character.muzzle.global_position)
		_check(muzzle_local.z < -0.6 and absf(muzzle_local.y - 1.26) < 0.1,
			"%s faces forward, gun at shoulder height (muzzle at %s)" % [character.name, muzzle_local])
		_check(character.muzzle_flash.get_parent() == character.muzzle, "%s muzzle flash sits on the gun" % character.name)
		var bags_before := get_nodes_in_group("loot_containers").size()
		character.health.take_damage(9999)
		await _frames(3)
		_check(not is_instance_valid(character), "%s dies" % path.get_file())
		_check(get_nodes_in_group("loot_containers").size() > bags_before, "%s drops a body bag" % path.get_file())

	# Grid inventory: sizes, rotation, stacking.
	var grid := GridInventory.new("Test", 2, 2)
	_check(grid.add("laptop") == 0 and grid.add("laptop") == 0 and grid.add("laptop") == 1, "two 2x1 laptops fill a 2x2 grid, a third doesn't fit")
	var tall := GridInventory.new("Tall", 1, 2)
	_check(tall.add("laptop") == 0 and tall.stacks[0].rotated, "a 2x1 laptop fits a 1x2 grid by rotating")
	_check(not grid.fits("vase", 0, 0, false) and GridInventory.new("Big", 2, 2).fits("vase", 0, 0, false), "2x2 vase needs a free 2x2 area")

	var inv := player.inventory
	inv.clear()
	_check(inv.add("rifle_ammo", 200) == 0 and inv.count_of("rifle_ammo") == 200, "200 rifle rounds fit")
	var ammo_stacks := 0
	for stack in inv.all_stacks():
		if stack.id == "rifle_ammo":
			ammo_stacks += 1
			_check(stack.count <= 120, "ammo stacks hold at most 120 (%d)" % stack.count)
	_check(ammo_stacks == 2, "200 rounds = 2 stacks (%d)" % ammo_stacks)
	gun.in_mag = 0
	gun.start_reload()
	await create_timer(gun.reload_time + 0.3).timeout
	_check(gun.in_mag == gun.mag_size and inv.count_of("rifle_ammo") == 200 - gun.mag_size, "reloading takes rounds from the inventory (%d left)" % inv.count_of("rifle_ammo"))
	_check(gun.reserve == inv.count_of("rifle_ammo"), "gun reserve = rounds carried")

	inv.clear()
	_check(inv.add("golden_toilet") == 0 and inv.backpack.count_of("golden_toilet") == 1, "golden toilet (2x3) goes in the backpack")
	_check(inv.add("bandage", 7) == 0 and inv.count_of("bandage") == 7, "bandages stack (7 = 5 + 2)")
	_check(inv.add("vase") == 0 and inv.add("laptop") == 0 and inv.add("gold_watch") == 0, "more loot fits")
	var gear_value := inv.equipped("primary").value() + inv.equipped("backpack").value()
	var expected_value := 50000 + 7 * 100 + 9000 + 4000 + 2500 + gear_value
	_check(inv.total_value() == expected_value, "carried value is %s" % ItemDB.money(inv.total_value()))

	# Equipment: starting kit, pistol + weapon switching, armor, backpack rules, secure pocket, hotbar.
	_check(inv.equipped("primary") != null and inv.equipped("primary").id == "ak" and gun.weapon == inv.equipped("primary"), "start with an AK equipped")
	_check(inv.secure.width == 2 and inv.secure.height == 2, "2x2 secure pocket")
	var pistol := ItemStack.new("pistol")
	pistol.loaded = 12
	_check(inv.equip("secondary", pistol) and gun.weapon != pistol, "equip a pistol (rifle stays out)")
	_check(not inv.equip("secondary", ItemStack.new("pistol")), "can't equip into a full slot")
	_check(not inv.equip("armor", ItemStack.new("pistol")), "a pistol doesn't go in the armor slot")
	await _press("weapon_2")
	_check(gun.weapon == pistol and not gun.auto and gun.mag_size == 12 and gun.ammo_id == "pistol_ammo", "key 2 switches to the semi-auto pistol")
	await _press("weapon_1")
	_check(gun.weapon == inv.equipped("primary") and gun.auto and gun.mag_size == 30, "key 1 switches back to the AK")
	inv.equip("armor", ItemStack.new("armor_heavy"))
	var hp_before := player.health.current
	player.health.take_damage(10)
	_check(hp_before - player.health.current == 6, "heavy armor takes 40%% off (10 -> %d)" % (hp_before - player.health.current))
	_check(not inv.can_unequip("backpack") and inv.unequip("backpack") == null, "can't take off a backpack with stuff in it")
	_check(inv.hotbar[0] == "bandage", "picked-up bandages bind to hotbar key 3")

	# Inventory screen: open a container, move items around (same code the mouse uses).
	var loot_ui: LootUI = main.get_node("HUD").loot_ui
	var box := LootContainer.spawn_bag(main, player.global_position, "Test Bag", [["crystal", 1], ["rifle_ammo", 30]])
	loot_ui.open_for(box)
	await process_frame
	_check(loot_ui.visible, "loot screen opens")
	var crystal: ItemStack = null
	for stack in box.grid.stacks:
		if stack.id == "crystal":
			crystal = stack
	loot_ui.quick_move(box.grid, crystal)
	_check(inv.count_of("crystal") == 1 and box.grid.count_of("crystal") == 0, "shift+click moves an item into your inventory")
	var watch: ItemStack = null
	for stack in inv.all_stacks():
		if stack.id == "gold_watch":
			watch = stack
	var watch_grid := inv.pockets if inv.pockets.stacks.has(watch) else inv.backpack
	_check(loot_ui.move_stack(watch, watch_grid, box.grid, Vector2i(3, 2), false), "drag an item into the container")
	_check(box.grid.count_of("gold_watch") == 1 and inv.count_of("gold_watch") == 0, "the item moved")
	_check(not loot_ui.move_stack(box.grid.stacks[0], box.grid, box.grid, Vector2i(9, 9), false), "can't drop outside the grid")
	var bandages: ItemStack = null
	for stack in inv.all_stacks():
		if stack.id == "bandage" and stack.count == 5:
			bandages = stack
	var bandage_grid := inv.pockets if inv.pockets.stacks.has(bandages) else inv.backpack
	_check(loot_ui.split_stack(bandage_grid, bandages) and inv.count_of("bandage") == 7 and bandages.count == 3, "split a stack of 5 into 3 + 2")
	# Equip from the container, swap, unequip.
	box.grid.add("armor_light")
	var light: ItemStack = null
	for stack in box.grid.stacks:
		if stack.id == "armor_light":
			light = stack
	_check(light != null and loot_ui.equip_from_grid(box.grid, light, "armor"), "drag light armor from the crate onto the armor slot")
	_check(inv.equipped("armor") == light and box.grid.count_of("armor_heavy") == 1, "the heavy armor swapped into the crate")
	loot_ui.unequip_to_inventory("secondary")
	_check(inv.equipped("secondary") == null and inv.count_of("pistol") == 1, "unequip the pistol into the inventory")
	_check(gun.weapon == inv.equipped("primary"), "still holding the AK")
	loot_ui.close()
	expected_value = inv.total_value()

	# Healing (the scav hurt us earlier): H uses one bandage from a stack.
	player.health.take_damage(30)
	var hurt_hp := player.health.current
	player.try_heal()
	_check(player.is_healing() and inv.count_of("bandage") == 6, "H starts healing and uses one bandage")
	await create_timer(2.4).timeout
	_check(player.health.current == mini(hurt_hp + 25, player.health.max_health), "bandage heals 25 (hp %d -> %d)" % [hurt_hp, player.health.current])
	expected_value -= 100

	# Extraction: walk into an open extract and wait.
	var open_zone: ExtractZone = null
	var open_count := 0
	for zone in raid.get_extracts():
		if zone.is_open:
			open_count += 1
			open_zone = zone
	_check(open_count == raid.open_extract_count, "%d of 3 extracts are open" % open_count)
	player.teleport_to(open_zone.global_position + Vector3(0, 0.2, 0))
	await create_timer(open_zone.extract_time + 1.0).timeout
	_check(raid.result == "extracted" and raid.extract_used == open_zone.extract_name, "standing in an open extract extracts (%s)" % raid.result)
	_check(raid.loot_value == expected_value and Raid.session_value == raid.loot_value, "extracted loot is counted (%s)" % ItemDB.money(raid.loot_value))
	_check(not raid.loot_summary.is_empty(), "end screen lists the loot")
	_check(player.controls_locked(), "controls lock after extracting")

	# Player death.
	player.health.take_damage(9999)
	await _frames(3)
	_check(player.is_dead, "player dies at 0 hp")

	# Profile: extracting saved what you carried; dying keeps only the secure pocket.
	var saved_equipment: Dictionary = Profile.loadout.get("equipment", {})
	_check(saved_equipment.has("primary"), "extracting keeps your equipment in the profile")
	var dead := Profile.death_loadout({"equipment": {"primary": {"id": "ak"}}, "pockets": [{"id": "beans"}],
		"secure": [{"id": "crystal", "count": 1, "x": 0, "y": 0}]})
	_check((dead["equipment"] as Dictionary).is_empty() and (dead["pockets"] as Array).is_empty() and (dead["secure"] as Array).size() == 1,
		"dying keeps only the secure pocket")

	# Save / load round trip.
	Profile.stash.add("gold_watch")
	var money_before := Profile.money
	Profile.save_profile()
	Profile.money = 0
	Profile.stash = GridInventory.new("Empty", 1, 1)
	Profile._loaded = false
	Profile.load_profile()
	_check(Profile.money == money_before and Profile.stash.count_of("gold_watch") == 1, "profile saves and loads (money + stash)")

	# Hideout: loadout, buying, selling, free kit.
	var hideout = (load("res://scenes/hideout.tscn") as PackedScene).instantiate()
	root.add_child(hideout)
	await process_frame
	var hideout_inv: Inventory = hideout.inventory
	_check(hideout_inv.equipped("primary") != null and hideout.screen.visible, "hideout shows your loadout and stash")
	var money := Profile.money
	_check(hideout.buy("bandage", 1) and Profile.money == money - hideout.buy_price("bandage", 1) and Profile.stash.count_of("bandage") >= 1,
		"buy a bandage into the stash")
	money = Profile.money
	var watch_stack: ItemStack = null
	for stack in Profile.stash.stacks:
		if stack.id == "gold_watch":
			watch_stack = stack
	hideout.sell(Profile.stash, watch_stack)
	_check(Profile.money == money + 2500 and Profile.stash.count_of("gold_watch") == 0, "sell a gold watch for full value")
	money = Profile.money
	hideout.buy("pistol", 1)
	var bought_pistol: ItemStack = null
	for stack in Profile.stash.stacks:
		if stack.id == "pistol":
			bought_pistol = stack
	_check(bought_pistol != null and Profile.money == money - hideout.buy_price("pistol", 1), "buy a pistol")
	money = Profile.money
	hideout.sell(Profile.stash, bought_pistol)
	_check(Profile.money == money + roundi(ItemDB.value("pistol") * 0.6), "gear sells for 60%")
	_check(not hideout.can_take_free_kit(), "no free kit while you own a weapon")
	# Lose every weapon and all your money.
	for slot in ["primary", "secondary"]:
		hideout_inv.unequip(slot)
	for loadout_grid in hideout_inv.grids():
		for stack in loadout_grid.stacks.duplicate():
			if ItemDB.kind(stack.id) == "weapon":
				loadout_grid.remove(stack)
	for stack in Profile.stash.stacks.duplicate():
		if ItemDB.kind(stack.id) == "weapon":
			Profile.stash.remove(stack)
	Profile.money = 0
	_check(hideout.can_take_free_kit() and hideout.take_free_kit() and hideout_inv.equipped("secondary") != null,
		"broke and unarmed: the free kit gives you a pistol")
	_check(not hideout.can_take_free_kit(), "free kit is gone once you have a weapon")
	hideout.save_now()
	var saved_loadout: Dictionary = Profile.loadout.get("equipment", {})
	_check(saved_loadout.has("secondary"), "hideout changes are saved to the profile")
	hideout.queue_free()

	# Settings.
	GameSettings.set_volume(0.0)
	_check(AudioServer.is_bus_mute(0), "volume 0 mutes audio")
	GameSettings.set_volume(0.5)
	_check(not AudioServer.is_bus_mute(0) and AudioServer.get_bus_volume_db(0) < 0.0, "volume 50% lowers audio")

	print("SMOKE TEST: %s" % ("PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _aim(player: Player, target: Vector3) -> void:
	var dir := (target - player.camera.global_position).normalized()
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.head.rotation.x = asin(dir.y)
	player.recoil.rotation = Vector3.ZERO


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)


## Sends a key action through the real input path (as if the key was pressed).
func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame
