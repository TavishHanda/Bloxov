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
