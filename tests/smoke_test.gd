extends SceneTree
## Headless gameplay test, run by CI:  godot --headless -s tests/smoke_test.gd
## Loads the main scene, fires the gun at the dummy, reloads, and lets a scav shoot the player.

var _failures := 0


func _initialize() -> void:
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
		if container.loot_table != "" and not container.items.is_empty():
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
		var box := crate_mesh.get_aabb().size
		_check(box.distance_to(Vector3(1.0, 0.75, 0.7)) < 0.05, "crate model is 1.0 x 0.75 x 0.7 m (got %s)" % box)
		var crate_material := crate_mesh.mesh.surface_get_material(0) as BaseMaterial3D
		_check(crate_material != null and crate_material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			and crate_material.albedo_texture != null, "crate texture is crisp (nearest filtering)")
	crate.queue_free()

	# Backpack slots.
	var inv := player.inventory
	inv.clear()
	_check(inv.add("golden_toilet") and inv.used_slots() == 4, "golden toilet takes 4 slots")
	_check(inv.add("vase") and inv.add("laptop") and inv.used_slots() == 9, "bag fills up")
	_check(not inv.add("laptop") and inv.add("gold_watch") and inv.free_slots() == 0, "full bag rejects big items")
	var expected_value := 50000 + 9000 + 4000 + 2500
	_check(inv.total_value() == expected_value, "bag value is %s" % ItemDB.money(inv.total_value()))

	# Healing (the scav hurt us earlier).
	inv.remove_at(inv.items.find("gold_watch"))
	inv.add("bandage")
	player.health.take_damage(30)
	var hurt_hp := player.health.current
	player.try_heal()
	_check(player.is_healing() and not inv.items.has("bandage"), "H starts healing and uses the bandage")
	await create_timer(2.4).timeout
	_check(player.health.current == mini(hurt_hp + 25, player.health.max_health), "bandage heals 25 (hp %d -> %d)" % [hurt_hp, player.health.current])

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
	_check(raid.loot_value == expected_value - 2500 and Raid.session_value == raid.loot_value, "extracted loot is counted")
	_check(player.controls_locked(), "controls lock after extracting")

	# Player death.
	player.health.take_damage(9999)
	await _frames(3)
	_check(player.is_dead, "player dies at 0 hp")

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


func _frames(n: int) -> void:
	for i in n:
		await process_frame
