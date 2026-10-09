extends SceneTree
## Headless gameplay test, run by CI:  godot --headless --fixed-fps 60 -s tests/smoke_test.gd
## (--fixed-fps 60 makes every frame exactly 1/60 s of game time, so the test is deterministic and runs
## much faster than real time; it also works without the flag, just slower.)
##
## Loads the raid scene and plays through it: shooting the dummy, reloading, aiming, accuracy and recoil,
## time-to-kill numbers, a scav shooting you, the knife, movement/crouch/stamina/jump, loot containers and
## models, the grid inventory, equipment, the inventory screen (incl. no empty "ghost" stack after using up a
## dragged item, and dropped guns keeping their rounds), healing, extracting, dying, the saved profile,
## the hideout (buy/sell/free kit) and settings.
##
## Each block of checks is a named section, run in order with the player reset in between (see _reset).
## Run only some of them (their dependencies come along, see NEEDS):
##   godot --headless --fixed-fps 60 -s tests/smoke_test.gd -- section=knife,heal
##   SECTION=knife godot --headless --fixed-fps 60 -s tests/smoke_test.gd
## Your saved profile (user://profile.json) is backed up at the start and put back before the test quits.

## Every section, in the order they run.
const SECTIONS: Array[String] = [
	"shoot", "reload", "ads", "accuracy", "recoil", "ttk", "scav_shoots", "knife", "scav_hit", "senses", "spotting", "close_range", "melee", "spawn_budget", "pathing", "patrol", "scav_looting", "cover", "lean", "hurt", "raiders",
	"movement", "stealth", "jump", "containers", "crate_model", "characters", "grid", "inventory",
	"equipment", "loot_ui", "dropped_gun", "heal", "extract", "death", "profile", "hideout", "settings",
	"ghost_stack", "owner_rules", "matchmaking", "net", "pvp",
]
## Sections that build on what an earlier one left behind. Running one also runs these (recursively).
const NEEDS := {
	"scav_hit": ["scav_shoots"],  # shoots and kills the scav spawned there
	"equipment": ["inventory"],  # bandages picked up there bind to the hotbar
	"loot_ui": ["equipment"],  # moves the watch/bandages from "inventory", swaps the heavy armor and pistol
	"heal": ["loot_ui"],  # uses one of the 7 bandages; adjusts the expected loot value
	"extract": ["heal"],  # checks the loot value carried out
	"death": ["extract"],
	"profile": ["death"],  # extracting saved the equipment
	"hideout": ["profile"],  # sells the gold watch put in the stash there
}
const PROFILE_PATH := "user://profile.json"
## Where the player stands for most tests: facing the dummy, open road behind.
const START_SPOT := Vector3(0, 0.1, -10)
const SCAV_SCENE := "res://scenes/scav.tscn"
const RAIDER_SCENE := "res://scenes/raider.tscn"

var _failures := 0
## Contents of the profile save before the test ran (null = there wasn't one).
var _profile_backup: Variant = null
var _started_msec := 0

# Shared between sections.
var main: Node
var player: Player
var raid: Raid
var gun: Gun
var dummy: Node3D
var dummy_health: Health
var inv: Inventory
var loot_ui: LootUI
## The scav from "scav_shoots" (shot and killed in "scav_hit").
var enemy: Scav = null
## Value the player should be carrying out at extraction (set in "inventory", kept up to date after).
var expected_value := 0


func _initialize() -> void:
	_backup_profile()
	# Watchdog: if a script error stops the test mid-way, fail instead of hanging CI.
	create_timer(150.0, true).timeout.connect(func() -> void:
		print("SMOKE TEST: TIMED OUT (a script error probably stopped the test; see errors above)")
		_quit(1))
	_run.call_deferred()


func _run() -> void:
	_started_msec = Time.get_ticks_msec()
	var selected := _selected_sections()
	if selected.is_empty():
		_quit(1)
		return
	await _setup()
	for section in selected:
		print("[%s]" % section)
		await Callable(self, "_section_" + section).call()
		await _reset()
	print("SMOKE TEST: %s (%d sections, %.1fs)" % ["PASSED" if _failures == 0 else "%d FAILED" % _failures,
		selected.size(), (Time.get_ticks_msec() - _started_msec) / 1000.0])
	_quit(1 if _failures > 0 else 0)


## Sections to run, from `-- section=a,b` or the SECTION environment variable (default: all),
## plus what they need, in the normal order. Empty = a bad section name.
func _selected_sections() -> Array[String]:
	var wanted := OS.get_environment("SECTION")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("section="):
			wanted = arg.trim_prefix("section=")
	if wanted.strip_edges() == "":
		return SECTIONS.duplicate()
	var include := {}
	var todo: Array = Array(wanted.split(",", false)).map(func(s: String) -> String: return s.strip_edges())
	while not todo.is_empty():
		var name: String = todo.pop_back()
		if not SECTIONS.has(name):
			print("Unknown section '%s'. Sections: %s" % [name, ", ".join(SECTIONS)])
			return []
		if not include.has(name):
			include[name] = true
			todo.append_array(NEEDS.get(name, []))
	var result: Array[String] = []
	for name in SECTIONS:
		if include.has(name):
			result.append(name)
	print("Running sections: %s" % ", ".join(result))
	return result


func _setup() -> void:
	# Start from a fresh profile, so a save left over from an earlier run can't change the starting kit.
	Profile.reset()
	Profile.save_profile()
	# Seed before the scene exists, so the raid's spawn point and loot rolls are the same every run.
	seed(12345)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	# The HUD pauses the game while the mouse isn't captured (always, in headless). Turn that off.
	main.get_node("HUD").process_mode = Node.PROCESS_MODE_DISABLED
	paused = false
	await _frames(5)

	# A raid starts with exactly the spawner's initial_count enemies (owner: 3).
	var spawner := main.get_node("EnemySpawner")
	var at_start := get_nodes_in_group("enemies").size()
	_check(at_start == spawner.initial_count and spawner.initial_count == 3, "raid starts with 3 enemies (%d)" % at_start)
	# Clear out spawned enemies so the test is predictable.
	spawner.queue_free()
	for node in get_nodes_in_group("enemies"):
		node.queue_free()
	await _frames(5)

	player = main.get_node("Player") as Player
	raid = main.get_node("Raid") as Raid
	# The raid puts the player at a random spawn; use the one facing the dummy.
	player.teleport_to(START_SPOT)
	await physics_frame
	gun = player.gun
	inv = player.inventory
	loot_ui = main.get_node("HUD").loot_ui
	dummy = main.get_node("TargetDummy") as Node3D
	dummy_health = dummy.get_node("Health") as Health
	_check(player != null and gun != null and dummy_health != null, "scene has player, gun and dummy")


## Between sections: let go of every key and put the player back to a clean state at START_SPOT.
## Deliberately leaves the gun's magazine and stats alone (sections set those up themselves).
func _reset() -> void:
	for action in InputMap.get_actions():
		Input.action_release(action)
	if player != null and is_instance_valid(player) and not player.controls_locked():
		player.set_crouching(false)
		player.teleport_to(START_SPOT)  # also zeroes velocity
		player.rotation.y = PI
		player.head.rotation.x = 0.0
		player.recoil.rotation = Vector3.ZERO
		player._recoil_debt = Vector2.ZERO
		player.stamina = player.max_stamina
		player.is_exhausted = false
		player.health.heal(player.health.max_health)
		gun._bloom = 0.0
		gun._flinch_spread = 0.0
	await physics_frame
	await physics_frame


# --- Sections ------------------------------------------------------------------

func _section_shoot() -> void:
	# Aim straight at the dummy's chest and fire one perfectly accurate shot.
	gun.base_spread_deg = 0.0
	gun.hip_spread_deg = 0.0
	gun.moving_spread_deg = 0.0
	_aim(dummy.global_position + Vector3(0, 1.0, 0))
	await physics_frame
	await physics_frame
	var before := dummy_health.current
	gun.shoot_once()
	_check(dummy_health.current == before - gun.damage, "body shot deals %d damage (got %d)" % [gun.damage, before - dummy_health.current])
	_check(gun.in_mag == gun.mag_size - 1, "shooting uses ammo")

	# Headshot.
	await create_timer(0.3).timeout
	_aim(dummy.global_position + Vector3(0, 1.65, 0))
	await physics_frame
	await physics_frame
	before = dummy_health.current
	gun.shoot_once()
	var expected := roundi(gun.damage * gun.headshot_multiplier)
	_check(before - dummy_health.current == expected, "headshot deals %d damage (got %d)" % [expected, before - dummy_health.current])


func _section_reload() -> void:
	gun.start_reload()
	await create_timer(gun.reload_time + 0.3).timeout
	_check(gun.in_mag == gun.mag_size and not gun.is_reloading, "reload refills the magazine")


func _section_ads() -> void:
	# Aim down sights: hold RMB -> zoom in, gun centered, crosshair off, tighter spread, slower walk, no sprint.
	var hip_fov := player.camera.fov
	Input.action_press("aim")
	await create_timer(gun.ads_time + 0.2).timeout
	_check(gun.aim == 1.0 and gun.is_aiming(), "holding aim fully aims in after %.2fs" % gun.ads_time)
	_check(absf(player.camera.fov - gun.ads_fov) < 0.5 and player.camera.fov < hip_fov, "aiming zooms the camera (%.0f -> %.0f)" % [hip_fov, player.camera.fov])
	player.rotation.y = PI
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await create_timer(1.0).timeout
	_check(not player.is_sprinting() and absf(player.horizontal_speed() - player.walk_speed * player.ads_move_multiplier) < 0.3,
		"aiming blocks sprint and slows you (%.2f m/s)" % player.horizontal_speed())
	Input.action_release("sprint")
	Input.action_release("move_forward")
	Input.action_release("aim")
	await create_timer(gun.ads_time + 0.2).timeout
	_check(gun.aim == 0.0 and absf(player.camera.fov - hip_fov) < 0.5, "releasing aim goes back to hip")
	var ak_data := ItemDB.item("ak")
	_check(ak_data["hip_spread"] > ak_data["spread"] * 4.0, "hip fire is much looser than aimed fire")
	player.teleport_to(START_SPOT)
	await create_timer(0.5).timeout


func _section_accuracy() -> void:
	# Accuracy targets (AK, scav chest 0.5 m wide at 20 m; shots land evenly inside the spread circle).
	gun._apply_weapon(gun.weapon)  # restore the real stats ("shoot" zeroed the spread)
	var target_deg := rad_to_deg(atan(0.25 / 20.0))
	var hit_rate := func(spread: float) -> float: return minf(1.0, pow(target_deg / spread, 2.0))
	var rates := {
		"hip standing": hit_rate.call(gun.spread_for(0.0, false, false, false)),
		"hip crouched": hit_rate.call(gun.spread_for(0.0, false, true, false)),
		"hip walking": hit_rate.call(gun.spread_for(0.0, true, false, false)),
		"aimed standing": hit_rate.call(gun.spread_for(1.0, false, false, false)),
		"aimed crouched": hit_rate.call(gun.spread_for(1.0, false, true, false)),
		"aimed walking": hit_rate.call(gun.spread_for(1.0, true, false, false)),
	}
	_check(rates["hip standing"] > 0.7 and rates["hip standing"] < 0.8, "hip fire standing hits ~75%% at 20 m (%.0f%%)" % (rates["hip standing"] * 100))
	_check(rates["hip crouched"] > 0.85 and rates["hip crouched"] < 0.95, "hip fire crouched hits ~90%% (%.0f%%)" % (rates["hip crouched"] * 100))
	_check(rates["hip walking"] < 0.3, "hip fire while walking is hard (%.0f%%)" % (rates["hip walking"] * 100))
	_check(rates["aimed standing"] > 0.99 and rates["aimed crouched"] > 0.99, "aimed shots standing/crouched hit 100%")
	_check(rates["aimed walking"] > 0.85 and rates["aimed walking"] < 0.97, "aimed while walking hits ~90%% (%.0f%%)" % (rates["aimed walking"] * 100))


func _section_recoil() -> void:
	# Recoil: a burst climbs your view; it settles back after you stop. Getting shot flinches your aim.
	var pitch_before := player.head.rotation.x
	for i in 8:
		gun.in_mag = gun.mag_size
		gun.shoot_once()
		await create_timer(0.1).timeout
	var climb := rad_to_deg(player.head.rotation.x - pitch_before)
	_check(climb > 5.0, "an 8-round burst climbs the view (%.1f°)" % climb)
	await create_timer(1.2).timeout
	var left := rad_to_deg(player.head.rotation.x - pitch_before)
	_check(absf(left) < 0.2, "recoil settles back after the burst (%.2f° left)" % left)
	var spread_before := gun.current_spread()
	player.health.take_damage(25, player.global_position + Vector3(5, 0, 0))
	await process_frame
	_check(gun.current_spread() > spread_before + 0.5 and player.recoil.rotation.length() > 0.01, "getting shot flinches your aim")
	player.health.heal(player.health.max_health)
	await create_timer(1.5).timeout


func _section_ttk() -> void:
	# Time to kill ("lethal-leaning middle"): scavs die in 4 AK body shots or 2 headshots; you die in ~7 scav hits.
	var ak_damage: int = ItemDB.item("ak")["damage"]
	var scav_probe := (load(SCAV_SCENE) as PackedScene).instantiate() as Scav
	var raider_probe := (load(RAIDER_SCENE) as PackedScene).instantiate() as Scav
	var scav_hp: int = scav_probe.get_node("Health").max_health
	var raider_health := raider_probe.get_node("Health") as Health
	var hits_to_kill := func(hp: int, dmg: float) -> int: return ceili(hp / maxf(roundf(dmg), 1.0))
	_check(hits_to_kill.call(scav_hp, ak_damage) == 4 and hits_to_kill.call(scav_hp, ak_damage * gun.headshot_multiplier) == 2,
		"scav: 4 AK body shots or 2 headshots")
	_check(hits_to_kill.call(raider_health.max_health, ak_damage * raider_health.damage_multiplier) == 5, "armored Raider: 5 AK body shots")
	var pistol_data := ItemDB.item("pistol")
	_check(hits_to_kill.call(scav_hp, pistol_data["damage"]) == 6 and hits_to_kill.call(scav_hp, pistol_data["damage"] * pistol_data["head"]) == 3,
		"pistol: 6 body shots or 3 headshots")
	var to_kill_player: int = hits_to_kill.call(player.health.max_health, scav_probe.shot_damage)
	_check(to_kill_player >= 6 and to_kill_player <= 7, "you die in %d scav hits" % to_kill_player)
	_check(hits_to_kill.call(player.health.max_health, scav_probe.shot_damage * (1.0 - ItemDB.item("armor_light")["reduction"])) > to_kill_player,
		"light armor makes you last longer")
	scav_probe.free()
	raider_probe.free()


func _section_scav_shoots() -> void:
	# A scav behind the player should spot them and shoot.
	enemy = _spawn(SCAV_SCENE, player.global_position + player.global_basis.z * 8.0) as Scav
	_face_player(enemy)
	var hp := player.health.current
	# Wait for the first hit (scavs are deadly now; waiting the full time could kill the player).
	for i in 40:
		await create_timer(0.1).timeout
		if player.health.current < hp:
			break
	_check(player.health.current < hp, "scav shoots the player (hp %d -> %d)" % [hp, player.health.current])


func _section_knife() -> void:
	# Knife (V): 45 from the front, one-hit kill from behind. Pause the shooting scav (if any) meanwhile.
	var shooter := enemy if is_instance_valid(enemy) else null
	if shooter != null:
		shooter.process_mode = Node.PROCESS_MODE_DISABLED
	var player_front := player.global_position - player.global_basis.z * 1.5
	var stab_target := _spawn(SCAV_SCENE, Vector3(player_front.x, player.global_position.y, player_front.z)) as Scav
	stab_target.set_physics_process(false)
	_face_player(stab_target)
	player.head.rotation.x = deg_to_rad(-10.0)
	await physics_frame
	_check(player.knife.swing() and player.knife.is_swinging(), "V swings the knife")
	await create_timer(player.knife.swing_time + 0.1).timeout
	_check(stab_target.health.current == stab_target.health.max_health - player.knife.damage,
		"knife hit from the front: %d (hp %d)" % [player.knife.damage, stab_target.health.current])
	stab_target.queue_free()
	await create_timer(player.knife.swing_time).timeout
	# Backstabs with the AI running (the swing mustn't alert the victim before the blade lands),
	# on a scav and on an armored Raider.
	for scene in [SCAV_SCENE, RAIDER_SCENE]:
		# Stand still first: footsteps (e.g. sliding from a knockback) would alert the victim.
		player.velocity = Vector3.ZERO
		player.teleport_to(START_SPOT)
		player_front = player.global_position - player.global_basis.z * 1.4
		await create_timer(0.3).timeout
		var victim := _spawn(scene, Vector3(player_front.x, player.global_position.y, player_front.z)) as Scav
		_face_player(victim)
		victim.rotate_y(PI)
		# Hold still (no random wandering) so it stays facing away.
		victim._wander_time = 99.0
		victim._wander_dir = Vector3.ZERO
		await create_timer(0.2).timeout
		var was_idle := victim.state == Scav.State.IDLE
		var diag := "state %d, behind %s" % [victim.state, player.knife._is_behind(victim)]
		player.knife.swing()
		await create_timer(player.knife.swing_time + 0.1).timeout
		_check(was_idle and (not is_instance_valid(victim) or victim.health.is_dead), "backstab kills an unaware %s in one hit (%s)" % [scene.get_file().get_basename(), diag])
		if is_instance_valid(victim):
			victim.queue_free()
	player.head.rotation.x = 0.0
	if shooter != null and is_instance_valid(shooter):
		shooter.process_mode = Node.PROCESS_MODE_INHERIT


func _section_scav_hit() -> void:
	# Shooting a scav flinches it: it holds fire for a moment and aims worse.
	enemy.health.take_damage(10, player.global_position)
	_check(enemy._flinch_left > 0.0 and enemy._fire_timer >= enemy.flinch_fire_delay - 0.001, "hit scav flinches (holds fire, aims worse)")

	# Killing the enemy removes it.
	enemy.health.take_damage(9999)
	await _frames(3)
	_check(not is_instance_valid(enemy), "dead enemy is removed")
	player.health.heal(player.health.max_health)


func _section_movement() -> void:
	# Movement: hold keys and measure. Face down the open road (+Z).
	player.teleport_to(START_SPOT)
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


func _section_stealth() -> void:
	# Crouch: slower, lower, silent. Walking makes noise.
	var noises: Array[float] = []
	var on_noise := func(_pos: Vector3, radius: float) -> void: noises.append(radius)
	player.noise_made.connect(on_noise)
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
	player.noise_made.disconnect(on_noise)


func _section_jump() -> void:
	# Let the player settle on the ground first (the reset drops them in from just above it).
	await create_timer(0.5).timeout
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


func _section_containers() -> void:
	# Loot containers rolled their contents.
	var rolled := 0
	for node in get_nodes_in_group("loot_containers"):
		var container := node as LootContainer
		if container.loot_table != "" and not container.grid.is_empty():
			rolled += 1
	_check(rolled >= 10, "containers have loot (%d)" % rolled)
	_check(ItemDB.money(1234567) == "$1,234,567", "money formatting")


func _section_crate_model() -> void:
	# Imported crate model: right size, crisp pixel filtering.
	var crate := _spawn("res://scenes/loot_crate.tscn", Vector3(0, 0, 60))
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


func _section_characters() -> void:
	# Character models (scav and Raider): imported .glb, one outfit option per slot, facing forward.
	for path: String in [SCAV_SCENE, RAIDER_SCENE]:
		var character := _spawn(path, Vector3(10, 0.1, 60)) as Scav
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


func _section_grid() -> void:
	# Grid inventory: sizes, rotation, stacking.
	var grid := GridInventory.new("Test", 2, 2)
	_check(grid.add("laptop") == 0 and grid.add("laptop") == 0 and grid.add("laptop") == 1, "two 2x1 laptops fill a 2x2 grid, a third doesn't fit")
	var tall := GridInventory.new("Tall", 1, 2)
	_check(tall.add("laptop") == 0 and tall.stacks[0].rotated, "a 2x1 laptop fits a 1x2 grid by rotating")
	_check(not grid.fits("vase", 0, 0, false) and GridInventory.new("Big", 2, 2).fits("vase", 0, 0, false), "2x2 vase needs a free 2x2 area")


func _section_inventory() -> void:
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
	expected_value = (ItemDB.value("golden_toilet") + 7 * ItemDB.value("bandage") + ItemDB.value("vase")
		+ ItemDB.value("laptop") + ItemDB.value("gold_watch") + gear_value)
	_check(inv.total_value() == expected_value, "carried value is %s" % ItemDB.money(inv.total_value()))


func _section_equipment() -> void:
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


func _section_loot_ui() -> void:
	# Inventory screen: open a container, move items around (same code the mouse uses).
	# A fully looted body bag disappears.
	var one_item_bag := LootContainer.spawn_bag(main, player.global_position, "Body", [["phone", 1]])
	loot_ui.open_for(one_item_bag)
	await process_frame
	loot_ui.quick_move(one_item_bag.grid, one_item_bag.grid.stacks[0])
	await process_frame
	await process_frame
	_check(not is_instance_valid(one_item_bag), "an emptied body bag despawns")
	loot_ui.close()
	inv.take("phone", 1)
	var box := LootContainer.spawn_bag(main, player.global_position, "Test Bag", [["crystal", 1], ["rifle_ammo", 30]])
	loot_ui.open_for(box)
	await process_frame
	_check(loot_ui.visible, "loot screen opens")
	var crystal := _find_stack(box.grid.stacks, "crystal")
	loot_ui.quick_move(box.grid, crystal)
	_check(inv.count_of("crystal") == 1 and box.grid.count_of("crystal") == 0, "shift+click moves an item into your inventory")
	var found := inv.find("gold_watch")
	var watch: ItemStack = found[1] if found.size() == 2 else null
	var watch_grid: GridInventory = found[0] if found.size() == 2 else null
	_check(loot_ui.move_stack(watch, watch_grid, box.grid, Vector2i(3, 2), false), "drag an item into the container")
	_check(box.grid.count_of("gold_watch") == 1 and inv.count_of("gold_watch") == 0, "the item moved")
	_check(not loot_ui.move_stack(box.grid.stacks[0], box.grid, box.grid, Vector2i(9, 9), false), "can't drop outside the grid")
	var bandages := _find_stack(inv.all_stacks(), "bandage", 5)
	var bandage_grid := inv.pockets if inv.pockets.stacks.has(bandages) else inv.backpack
	_check(loot_ui.split_stack(bandage_grid, bandages) and inv.count_of("bandage") == 7 and bandages.count == 3, "split a stack of 5 into 3 + 2")
	# Equip from the container, swap, unequip.
	box.grid.add("armor_light")
	var light := _find_stack(box.grid.stacks, "armor_light")
	_check(light != null and loot_ui.equip_from_grid(box.grid, light, "armor"), "drag light armor from the crate onto the armor slot")
	_check(inv.equipped("armor") == light and box.grid.count_of("armor_heavy") == 1, "the heavy armor swapped into the crate")
	loot_ui.unequip_to_inventory("secondary")
	_check(inv.equipped("secondary") == null and inv.count_of("pistol") == 1, "unequip the pistol into the inventory")
	_check(gun.weapon == inv.equipped("primary"), "still holding the AK")
	loot_ui.close()
	expected_value = inv.total_value()


func _section_dropped_gun() -> void:
	# A gun dropped into a bag (a body's weapon, or dropping it yourself) keeps the rounds loaded in it.
	var pistol := ItemStack.new("pistol")
	pistol.loaded = 12
	var bag := LootContainer.spawn_bag(main, player.global_position + Vector3(3, 0, 0), "Dropped", [pistol])
	var in_bag := _find_stack(bag.grid.stacks, "pistol")
	_check(in_bag != null and in_bag.loaded == 12, "a gun dropped in a bag keeps its 12 loaded rounds (%s)" % (str(in_bag.loaded) if in_bag != null else "missing"))
	bag.queue_free()


func _section_heal() -> void:
	# Healing: H uses one bandage from a stack.
	var bandage := ItemDB.item("bandage")
	player.health.take_damage(30)
	var hurt_hp := player.health.current
	player.try_heal()
	_check(player.is_healing() and inv.count_of("bandage") == 6, "H starts healing and uses one bandage")
	await create_timer(float(bandage["use_time"]) + 0.4).timeout
	var heal_amount: int = bandage["heal"]
	_check(player.health.current == mini(hurt_hp + heal_amount, player.health.max_health), "bandage heals %d (hp %d -> %d)" % [heal_amount, hurt_hp, player.health.current])
	expected_value -= ItemDB.value("bandage")


func _section_extract() -> void:
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
	_check(raid.loot_value == expected_value, "extracted loot is counted (%s, expected %s)" % [ItemDB.money(raid.loot_value), ItemDB.money(expected_value)])
	_check(not raid.loot_summary.is_empty(), "end screen lists the loot")
	_check(player.controls_locked(), "controls lock after extracting")


func _section_death() -> void:
	player.health.take_damage(9999)
	await _frames(3)
	_check(player.is_dead, "player dies at 0 hp")


func _section_profile() -> void:
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


func _section_hideout() -> void:
	# Hideout: loadout, buying, selling, free kit.
	var hideout = (load("res://scenes/hideout.tscn") as PackedScene).instantiate()
	root.add_child(hideout)
	await process_frame
	var hideout_inv: Inventory = hideout.inventory
	_check(hideout_inv.equipped("primary") != null and hideout.screen.visible, "hideout shows your loadout and stash")
	var version: String = ProjectSettings.get_setting("application/config/version")
	_check(hideout._version_label.text == "v" + version, "hideout shows the version (%s)" % hideout._version_label.text)
	hideout.go_online("  ", "Tester")
	_check(hideout._online_status.text.contains("address") and not Network.main.is_online(), "going online needs a server address")
	_check(hideout._online_panel != null and not hideout._online_box.visible, "the online panel starts offline")
	var money := Profile.money
	_check(hideout.buy("bandage", 1) and Profile.money == money - hideout.buy_price("bandage", 1) and Profile.stash.count_of("bandage") >= 1,
		"buy a bandage into the stash")
	money = Profile.money
	hideout.sell(Profile.stash, _find_stack(Profile.stash.stacks, "gold_watch"))
	_check(Profile.money == money + ItemDB.value("gold_watch") and Profile.stash.count_of("gold_watch") == 0, "sell a gold watch for full value")
	money = Profile.money
	hideout.buy("pistol", 1)
	var bought_pistol := _find_stack(Profile.stash.stacks, "pistol")
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
	await process_frame


func _section_settings() -> void:
	GameSettings.set_volume(0.0)
	_check(AudioServer.is_bus_mute(0), "volume 0 mutes audio")
	GameSettings.set_volume(0.5)
	_check(not AudioServer.is_bus_mute(0) and AudioServer.get_bus_volume_db(0) < 0.0, "volume 50% lowers audio")


func _section_ghost_stack() -> void:
	# Using up a stack while it's being dragged (e.g. a heal finishing mid-drag) mustn't leave an empty
	# "ghost" stack behind where it's dropped.
	inv.clear()
	inv.add("bandage", 1)
	var found := inv.find("bandage")
	var from: GridInventory = found[0]
	var stack: ItemStack = found[1]
	var to := inv.pockets if from != inv.pockets else inv.secure
	var bag := LootContainer.spawn_bag(main, player.global_position + Vector3(3, 0, 0), "Ghost Test", [["phone", 1]])
	loot_ui.open_for(bag)
	await _frames(2)  # let the containers lay out the grid views
	var target_view: GridView = null
	for view in loot_ui._views:
		if view is GridView and (view as GridView).grid == to:
			target_view = view
	var free_cell := Vector2i(to.width - 1, to.height - 1)
	loot_ui.start_drag(from, stack, Vector2(GridView.CELL, GridView.CELL) * 0.5)
	_check(loot_ui.drag_stack == stack, "drag a 1-count bandage stack")
	inv.take("bandage", 1)
	_check(stack.count == 0 and inv.count_of("bandage") == 0, "the dragged bandage gets used up mid-drag")
	# Point the mouse at a free cell of another grid, then let go there.
	if target_view != null:
		var motion := InputEventMouseMotion.new()
		# Input events are in window pixels; the UI may be scaled (stretch mode), so convert.
		var point := target_view.global_position + (Vector2(free_cell) + Vector2(0.5, 0.5)) * GridView.CELL
		motion.position = root.get_screen_transform() * point
		motion.global_position = motion.position
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		loot_ui._update_drag()
	_check(loot_ui.hover_view == target_view and target_view != null, "the drag hovers the %s grid" % to.title)
	loot_ui._finish_drag()
	var ghosts := 0
	for any_stack in inv.all_stacks():
		if any_stack.count <= 0:
			ghosts += 1
	_check(ghosts == 0, "no empty ghost stack is left in the inventory (%d)" % ghosts)
	loot_ui.close()
	bag.queue_free()


func _section_matchmaking() -> void:
	# Owner rules (0.7.3): duo parties by code, solos and duos share the queue, 2-6 players per raid,
	# a countdown once 2 are waiting, parties never split, no late joining, "start now" for one party.
	var mm := Matchmaker.new()
	mm.queue_countdown = 30.0
	for peer in [1, 2, 3, 4, 5, 6, 7]:
		mm.add_player(peer, "P%d" % peer)
	_check(mm.parties.size() == 7 and mm.party_of(1)["members"] == [1], "everyone starts in a party of their own (with a code)")
	var code1: String = mm.players[1]["party"]
	_check(mm.join_party(2, code1.to_lower()) == "" and mm.party_of(2)["members"] == [1, 2], "a friend joins your party with your code")
	_check(mm.join_party(3, code1).contains("full"), "parties are duos at most")
	_check(mm.join_party(3, "ZZZZ").begins_with("No party"), "a wrong code says so")
	_check(mm.set_queued(2, true).contains("leader"), "only the party leader queues")
	_check(mm.set_queued(1, true) == "" and mm.queued_count() == 2, "the duo is in the queue (2 players)")
	mm.tick(1.0)
	_check(mm.countdown_left > 28.0 and mm.raids.is_empty(), "2 waiting: the countdown starts, no raid yet")
	mm.set_queued(3, true)
	mm.tick(28.5)
	var started := mm.tick(1.0)
	_check(started.size() == 1 and mm.raids[started[0]]["players"].size() == 3, "when the countdown ends, everyone waiting gets one raid (3)")
	var raid: Dictionary = mm.raids[started[0]]
	_check(raid["teams"][1] == raid["teams"][2] and raid["teams"][1] != raid["teams"][3], "the duo are teammates, the solo isn't")
	_check(mm.join_party(4, code1).contains("full") and mm.set_queued(1, true).contains("back from"), "no joining or queueing a party that's in a raid")
	# A full raid starts at once; a duo isn't split to fill the last spot.
	mm.join_party(5, mm.players[4]["party"])
	for peer in [4, 6, 7]:
		mm.set_queued(peer, true)
	mm.leave_raid(3)
	mm.set_queued(3, true)
	_check(mm.queued_count() == 5, "5 waiting (a duo and three solos)")
	started = mm.tick(0.1)
	_check(started.is_empty(), "5 waiting: still counting down")
	mm.add_player(8, "P8")
	mm.add_player(9, "P9")
	mm.join_party(9, mm.players[8]["party"])
	mm.set_queued(8, true)
	started = mm.tick(0.1)
	_check(started.size() == 1 and mm.raids[started[0]]["players"].size() == 5 and mm.queued_count() == 2,
		"7 waiting: a raid starts at once with the first 5 (the last duo isn't split up; they wait)")
	mm.leave_raid(3)
	mm.set_queued(3, false)
	mm.leave_party(9)
	mm.tick(5.0)
	_check(mm.countdown_left < 0.0 and mm.queued_count() == 0, "a party that changes leaves the queue (no countdown)")
	# Start now, raids ending, people leaving.
	mm.leave_raid(1)
	mm.leave_raid(2)
	_check(not mm.raids.has(1), "a raid closes when everyone has left it")
	var why := []
	_check(mm.start_now(1, why) != 0 and mm.players[2]["raid"] == mm.players[1]["raid"], "start now: a raid with just your party")
	mm.remove_player(2)
	_check(mm.party_of(1)["members"] == [1], "a partner going offline leaves you in your party")
	mm.add_player(10, "  ")
	_check(mm.players[10]["name"] == "Player 10", "a blank name gets a default")


func _section_net() -> void:
	# Multiplayer over a real WebSocket server with three players, all in this one process. Each gets its own
	# branch of the tree with its own multiplayer API, so they talk over localhost like separate machines.
	var server := _net_peer("NetServer")
	var c1 := _net_peer("NetClient1")
	var c2 := _net_peer("NetClient2")
	var c3 := _net_peer("NetClient3")
	_check(server.start_server(19081) == OK and server.mode == server.Mode.SERVER, "server starts")
	server.matchmaker.queue_countdown = 0.3
	var log := {}
	for c in [c1, c2, c3]:
		log[c] = []
		c.connected.connect(func() -> void: log[c].append("connected"))
		c.connect_failed.connect(func(reason: String) -> void: log[c].append(reason))
		c.raid_started.connect(func() -> void: log[c].append("raid"))
		c.notice.connect(func(text: String) -> void: log[c].append(text))
	_check(server.join_problem("0.0.1").contains("Reload"), "an outdated game is told to reload")
	_check(server.join_problem(server.version()) == "", "the right version can come online")
	c1.go_online("localhost:19081", "Alpha")
	c2.go_online("localhost:19081", "Bravo")
	c3.go_online("localhost:19081", "Charlie")
	await _until(func() -> bool: return [c1, c2, c3].all(func(c: Network) -> bool: return c.is_client() and c.party_code != ""))
	_check([c1, c2, c3].all(func(c: Network) -> bool: return log[c].has("connected") and c.party_code.length() == 4), "three players come online, each with a party code")

	c2.join_party(c1.party_code)
	await _until(func() -> bool: return c1.party_names.size() == 2 and c2.party_code == c1.party_code)
	_check(c1.party_names == PackedStringArray(["Alpha", "Bravo"]) and c1.is_leader and not c2.is_leader, "Bravo joins Alpha's party (Alpha leads)")
	c2.set_queued(true)
	await _until(func() -> bool: return not log[c2].is_empty() and log[c2][-1].contains("leader"))
	_check(log[c2][-1].contains("leader"), "the server tells a non-leader they can't queue")
	c1.set_queued(true)
	c3.set_queued(true)
	await _until(func() -> bool: return [c1, c2, c3].all(func(c: Network) -> bool: return c.in_raid))
	_check([c1, c2, c3].all(func(c: Network) -> bool: return c.in_online_raid() and log[c].has("raid")), "the queue puts all three in one raid")
	_check(c1.raid_seed == c3.raid_seed and absf(c1.raid_time_left - c1.RAID_TIME) < 5.0 and c1.player_count() == 3,
		"same raid: same extract seed, a fresh clock, 3 players")
	var c1_id: int = c1.multiplayer.get_unique_id()
	var c2_id: int = c2.multiplayer.get_unique_id()
	_check(c1.teammates == [c2_id] and c3.teammates.is_empty() and c3.names.get(c1_id) == "Alpha", "Alpha and Bravo are teammates; Charlie knows their names")

	# States are relayed within the raid: Charlie sees Alpha where Alpha is, and never sees himself.
	var sent := [Vector3(4, 0.1, -6), 1.2, 0.3, 1.0, RemotePlayer.FLAG_CROUCH]
	await _until(func() -> bool:
		c1.send_state(sent)
		return c3.states.has(c1_id) and c3.states[c1_id][0].is_equal_approx(Vector3(4, 0.1, -6)))
	_check(c3.states.has(c1_id) and c3.states[c1_id] == sent, "Charlie sees Alpha's position, facing, crouch and lean")
	_check(not c3.states.has(c3.multiplayer.get_unique_id()), "you don't see yourself as another player")
	_check(not Network.is_valid_state([Vector3.ZERO, "hi"]) and Network.is_valid_state(RemotePlayer.capture(player)),
		"the server only relays well-formed states")

	# The raid shows other players as bodies, drawn smoothly between updates, and removes them when they leave.
	var net_raid := main.get_node("NetRaid") as NetRaid
	net_raid.sync_remotes({77: [Vector3(2, 0.1, -12), 0.0, 0.0, 0.0, 0]})
	var body: RemotePlayer = net_raid.remotes.get(77)
	_check(body != null and body.global_position.is_equal_approx(Vector3(2, 0.1, -12)) and body.collision_layer == 2, "another player appears as a body on the player layer")
	body.set_process(false)
	body._buffer.clear()
	body.push_state([Vector3(0, 0.1, -12), 0.0, 0.0, 0.0, 0], 10.0)
	body.push_state([Vector3(2, 0.1, -12), 0.0, 0.0, 1.0, RemotePlayer.FLAG_CROUCH], 10.05)
	body.update_view(10.025, 0.016)
	_check(is_equal_approx(body.global_position.x, 1.0), "between two updates the body is drawn halfway (x %.2f)" % body.global_position.x)
	for i in 60:
		body.update_view(10.05, 0.016)
	_check(body.model.scale.y < 0.7 and body.head_shape.position.y < 1.2 and body.head_shape.position.x > 0.2,
		"a crouching, leaning player looks it (and their head hitbox moves with it)")
	body.push_state([Vector3(2, 0.1, -12), 0.0, 0.5, 0.0, 0], 10.06)
	body.update_view(10.06, 0.016)
	_check(is_equal_approx(body.head_pivot.rotation.x, 0.5) and body.head_pivot.get_child_count() >= 3 and body.gun_model.rotation.x == 0.0,
		"looking up tilts their head, not their gun (owner)")
	body.push_state([Vector3(2, 0.1, -12), 0.0, 0.0, 0.0, RemotePlayer.FLAG_DEAD], 10.1)
	for i in 60:
		body.update_view(10.1, 0.016)
	_check(body.model.rotation.x > 1.3 and body.body_shape.disabled, "a dead player lies down")
	net_raid.sync_remotes({})
	await _frames(1)
	_check(net_raid.remotes.is_empty() and not is_instance_valid(body), "a player who leaves disappears")

	# Same seed = same open extracts on every machine.
	var a := raid.get_extracts()
	var b := raid.get_extracts()
	b.reverse()
	Raid.shuffle_seeded(a, 99)
	Raid.shuffle_seeded(b, 99)
	_check(a == b, "everyone in a room gets the same open extracts")

	# Back to the hideout: still online, same party; "start now" gives a raid of just your party.
	c3.leave_raid()
	await _until(func() -> bool: return server.matchmaker.players[c3.multiplayer.get_unique_id()]["raid"] == 0)
	c3.start_now()
	await _until(func() -> bool: return c3.in_raid)
	_check(c3.in_online_raid() and c3.player_count() == 1, "start now: Charlie gets a raid of his own")
	# Going offline: gone for the others, and the raid closes once everyone has left.
	c1.go_offline()
	await _until(func() -> bool: return server.matchmaker.players.size() == 2 and c2.party_names.size() == 1)
	_check(c2.party_names.size() == 1, "Bravo is left in his own party when Alpha goes offline")
	c2.go_offline()
	c3.go_offline()
	await _until(func() -> bool: return server.matchmaker.players.is_empty())
	_check(server.matchmaker.raids.is_empty() and server.matchmaker.parties.is_empty(), "everything closes when everyone has gone")
	server.multiplayer.multiplayer_peer.close()
	for n in [server, c1, c2, c3]:
		n.get_parent().queue_free()
	_check(not Network.main.is_online(), "solo raids stay offline")


## A Net node in its own branch of the tree, with its own multiplayer API (like a separate game).
func _net_peer(branch_name: String) -> Network:
	var branch := Node.new()
	branch.name = branch_name
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var net := Network.new()
	net.name = "Net"
	branch.add_child(net)
	return net


## Waits until `condition` is true (checked every frame, up to ~5 s).
func _until(condition: Callable) -> void:
	for i in 300:
		if condition.call():
			return
		await process_frame


func _section_pvp() -> void:
	# Shooting each other (0.7.7): the server checks every shot against its own copy of the map and the other
	# players where the shooter saw them (lag compensation); damage comes from the weapon, armor on the victim.
	var server := _net_peer("PvpServer")
	var c1 := _net_peer("PvpClient1")
	var c2 := _net_peer("PvpClient2")
	server.start_server(19082)
	server.matchmaker.queue_countdown = 0.2
	var got := {"hits": [], "confirmed": [], "kills": 0}
	c2.got_hit.connect(func(amount: int, _from: Vector3, headshot: bool) -> void: got["hits"].append([amount, headshot]))
	c1.shot_confirmed.connect(func(headshot: bool) -> void: got["confirmed"].append(headshot))
	c1.kill_confirmed.connect(func() -> void: got["kills"] += 1)
	c1.go_online("localhost:19082", "Shooter")
	c2.go_online("localhost:19082", "Target")
	await _until(func() -> bool: return c1.is_client() and c2.is_client() and c1.party_code != "" and c2.party_code != "")
	c1.set_queued(true)
	c2.set_queued(true)
	await _until(func() -> bool: return c1.in_raid and c2.in_raid)
	var world: RaidWorld = server._worlds.values()[0] if not server._worlds.is_empty() else null
	_check(world != null and world.get_node_or_null("Main/Level") != null and world.get_node_or_null("Main/Player") == null,
		"each online raid gets its own copy of the map on the server (map only)")
	await _frames(5)
	var c1_id: int = c1.multiplayer.get_unique_id()
	var c2_id: int = c2.multiplayer.get_unique_id()

	# Target stands still facing the shooter; the shooter fires at the body, then the head.
	# (Shots are checked where targets were ~0.1 s ago in real time, and the test runs faster than real time,
	# so each move is held for a moment of real time.)
	var stand := func(c: Network, pos: Vector3) -> void:
		for i in 4:
			c.send_state([pos, 0.0, 0.0, 0.0, 0])
			await _frames(2)
			OS.delay_msec(40)
	await stand.call(c2, Vector3(0, 0.1, -10))
	await stand.call(c1, Vector3(0, 0.1, -4))
	OS.delay_msec(60)
	c1.send_shot(Vector3(0, 1.5, -4), (Vector3(0, 0.8, -10) - Vector3(0, 1.5, -4)).normalized(), "ak")
	await _until(func() -> bool: return not got["hits"].is_empty())
	_check(got["hits"] == [[28, false]] and got["confirmed"] == [false], "an AK body shot hits the other player for 28 (%s)" % str(got["hits"]))
	await _frames(4)
	OS.delay_msec(60)
	c1.send_shot(Vector3(0, 1.5, -4), (Vector3(0, 1.75, -10) - Vector3(0, 1.5, -4)).normalized(), "ak")
	await _until(func() -> bool: return got["hits"].size() >= 2)
	_check(got["hits"].size() == 2 and got["hits"][1] == [56, true], "a headshot does double (%s)" % str(got["hits"]))
	OS.delay_msec(60)
	c1.send_shot(Vector3(0, 1.5, -4), Vector3(1, 0, 0), "ak")
	OS.delay_msec(60)
	c1.send_shot(Vector3(0, 1.5, -4), (Vector3(0, 0.8, -10) - Vector3(0, 1.5, -4)).normalized(), "gold_watch")
	OS.delay_msec(60)
	c1.send_shot(Vector3(30, 1.5, -4), Vector3(0, 0, -1), "ak")
	await _frames(20)
	_check(got["hits"].size() == 2, "misses, non-weapons and shots from somewhere else don't count")

	# Walls block shots (the north wall at z = 40.5).
	await stand.call(c2, Vector3(0, 0.1, 43))
	await stand.call(c1, Vector3(0, 0.1, 38))
	OS.delay_msec(60)
	c1.send_shot(Vector3(0, 1.5, 38), Vector3(0, -0.05, 1).normalized(), "ak")
	await _frames(20)
	_check(got["hits"].size() == 2, "a wall stops the shot")

	# Lag compensation: a shot counts where the target was on the shooter's screen.
	var now: float = server._now()
	world.record(901, [Vector3(10, 0.1, 0), 0.0, 0.0, 0.0, 0], now - 0.3)
	world.record(901, [Vector3(14, 0.1, 0), 0.0, 0.0, 0.0, 0], now)
	var at_then := world.trace_shot(c1_id, Vector3(10, 1.0, 6), Vector3(0, 0, -1), 50.0, now - 0.3, now)
	var at_now := world.trace_shot(c1_id, Vector3(10, 1.0, 6), Vector3(0, 0, -1), 50.0, now, now)
	_check(at_then.get("peer") == 901 and at_now.is_empty(), "shots are checked against where the target was when you fired")
	world.forget(901)

	# Dying credits the last attacker; the victim's own armor applies to hits.
	await stand.call(c2, Vector3(0, 0.1, -10))
	await stand.call(c1, Vector3(0, 0.1, -4))
	OS.delay_msec(60)
	c1.send_shot(Vector3(0, 1.5, -4), (Vector3(0, 0.8, -10) - Vector3(0, 1.5, -4)).normalized(), "pistol")
	await _until(func() -> bool: return got["hits"].size() >= 3)
	_check(got["hits"].size() == 3 and got["hits"][2] == [17, false], "pistol body shot: 17")
	c2.send_state([Vector3(0, 0.1, -10), 0.0, 0.0, 0.0, RemotePlayer.FLAG_DEAD])
	await _until(func() -> bool: return got["kills"] == 1)
	_check(got["kills"] == 1, "the killer is told about the kill")
	var net_raid := main.get_node("NetRaid") as NetRaid
	var before := player.health.current
	net_raid.apply_hit(28, Vector3(0, 0, -20), false)
	# (In a full run the player died in an earlier section, and a dead player takes no more hits.)
	var expected := 0 if player.controls_locked() else roundi(28 * player.health.damage_multiplier)
	_check(before - player.health.current == expected, "the victim takes the hit through their own armor (%d)" % expected)
	player.health.heal(100)

	for c in [c1, c2]:
		c.go_offline()
	await _until(func() -> bool: return server.matchmaker.players.is_empty())
	await _frames(2)
	_check(server._worlds.is_empty(), "the raid's map copy is removed when the raid ends")
	server.multiplayer.multiplayer_peer.close()
	for n in [server, c1, c2]:
		n.get_parent().queue_free()


func _section_owner_rules() -> void:
	# Damage numbers use the damage actually dealt: an AK body shot on an armored Raider shows 22, not 28.
	var raider := _spawn(RAIDER_SCENE, player.global_position + Vector3(0, 0, 30))
	var dealt: int = (raider.get_node("Health") as Health).take_damage(ItemDB.item("ak")["damage"])
	_check(dealt == 22, "armored Raider takes (and shows) 22 from an AK body shot (%d)" % dealt)
	raider.queue_free()

	# Heals only bind to the hotbar when they come from outside: rearranging your own inventory keeps an unbind.
	inv.clear()
	inv.add("bandage", 2)
	inv.unbind("bandage")
	var found := inv.find("bandage")
	var into := inv.backpack if found[0] != inv.backpack else inv.pockets
	var spot := into.find_spot("bandage")
	loot_ui.move_stack(found[1], found[0], into, Vector2i(spot[0], spot[1]), spot[2])
	_check(inv.count_of("bandage") == 2 and not inv.hotbar.has("bandage"), "moving an unbound heal inside your inventory doesn't re-bind it")
	var bag := LootContainer.spawn_bag(main, player.global_position + Vector3(3, 0, 0), "Bind Test", [["medkit", 1]])
	loot_ui.open_for(bag)
	await _frames(2)
	loot_ui.quick_move(bag.grid, bag.grid.stacks[0])
	_check(inv.hotbar.has("medkit"), "a medkit Shift+clicked in from a bag binds to the hotbar")

	# "Put in" a full container says so instead of doing nothing.
	var full := LootContainer.spawn_bag(main, player.global_position + Vector3(3, 0, 0), "Full Bag", [["phone", 1]])
	while full.grid.add("phone", 1) == 0:
		pass
	loot_ui.close()
	loot_ui.open_for(full)
	await _frames(2)
	inv.pockets.add("gold_watch")
	loot_ui.quick_move(inv.pockets, inv.find("gold_watch")[1])
	_check(inv.count_of("gold_watch") == 1 and loot_ui._info_label.text.begins_with("No room"), "putting into a full bag says \"No room\" (%s)" % loot_ui._info_label.text)
	loot_ui.close()
	full.queue_free()  # (the medkit bag despawned by itself once emptied)


func _section_senses() -> void:
	# Hearing: an unaware scav walks over to investigate roughly where a sound was; it doesn't lock on to you.
	var far_spot := player.global_position + Vector3(0, 0, 14)
	var scav := _spawn(SCAV_SCENE, far_spot) as Scav
	scav.look_at(far_spot + Vector3(0, 0, 10))  # facing away from the player
	scav._wander_time = 99.0
	scav._wander_dir = Vector3.ZERO
	await physics_frame
	scav.hear_noise(player.global_position, 20.0)
	_check(scav.state == Scav.State.INVESTIGATE, "a scav that hears you comes to investigate (not instantly fighting)")
	_check(scav._goal.distance_to(player.global_position) <= scav.noise_uncertainty + 0.01, "it heads roughly where the sound was")
	scav.hear_noise(player.global_position + Vector3(0, 0, 200), 20.0)
	_check(scav._goal.distance_to(player.global_position) <= scav.noise_uncertainty + 0.01, "sounds out of earshot are ignored")
	scav.queue_free()

	# Losing sight: a scav fighting you goes to where it last saw you and searches; it doesn't track you.
	var hunter := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 10)) as Scav
	_face_player(hunter)
	await physics_frame
	var seen_at := player.global_position
	player.teleport_to(player.global_position + Vector3(80, 0, 0))  # far out of sight range
	await create_timer(0.25).timeout  # let its sight check notice you're gone
	hunter._alert(seen_at)
	hunter._set_state(Scav.State.ENGAGE)
	var reached := false
	for i in 300:
		await physics_frame
		if hunter.state == Scav.State.SEARCH:
			reached = true
			break
	_check(reached and hunter.global_position.distance_to(seen_at) < 3.0,
		"lost sight: it goes to where it last saw you and searches (%.1f m away)" % hunter.global_position.distance_to(seen_at))
	for i in int((hunter.search_time + 0.5) * 60):
		await physics_frame
	_check(hunter.state == Scav.State.IDLE, "after searching a while it goes back to wandering")
	hunter.queue_free()


func _section_spotting() -> void:
	# Far away it takes a while to notice you; up close almost instantly.
	var far := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 32)) as Scav
	_face_player(far)
	far._wander_time = 99.0
	far._wander_dir = Vector3.ZERO
	await create_timer(0.4).timeout
	_check(far.state == Scav.State.IDLE, "a scav 32 m away hasn't noticed you after 0.4 s")
	await create_timer(2.5).timeout
	_check(far.state != Scav.State.IDLE, "...but does after a couple of seconds in view")
	far.queue_free()
	var near := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 4)) as Scav
	_face_player(near)
	near._wander_time = 99.0
	near._wander_dir = Vector3.ZERO
	await create_timer(0.45).timeout
	_check(near.state != Scav.State.IDLE, "a scav 4 m away notices you almost instantly")
	near.queue_free()

	# A bullet passing close to a scav that's too far to hear the shot still gets its attention.
	var distant := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 45)) as Scav
	distant.look_at(distant.global_position + Vector3(0, 0, 10))  # facing away
	distant._wander_time = 99.0
	distant._wander_dir = Vector3.ZERO
	await physics_frame
	_check(distant.global_position.distance_to(player.global_position) > gun.noise_radius, "the scav is out of earshot")
	gun.base_spread_deg = 0.0
	gun.hip_spread_deg = 0.0
	_aim(distant.global_position + Vector3(1.2, 1.2, 0))  # just past its shoulder
	await physics_frame
	gun.in_mag = gun.mag_size
	gun.shoot_once()
	_check(distant.state == Scav.State.ALERT, "a near miss alerts it even out of earshot")
	distant.queue_free()
	gun._apply_weapon(gun.weapon)


func _section_close_range() -> void:
	# Point blank (even standing right on its gun barrel), a scav's shots still hit.
	var scav := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 0.9)) as Scav
	_face_player(scav)
	scav.set_physics_process(false)
	scav._target = player
	await physics_frame
	var hp := player.health.current
	var hits := 0
	for i in 6:
		var before := player.health.current
		scav._fire_at_target(0.9)
		if player.health.current < before:
			hits += 1
	_check(hits >= 4, "point-blank scav shots hit (%d of 6)" % hits)
	player.health.heal(player.health.max_health)
	scav.queue_free()
	player.teleport_to(START_SPOT)  # the hits knocked the player back; start the next check still
	await physics_frame

	# Too close: it backs off instead of walking into you.
	var pusher := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 1.8)) as Scav
	_face_player(pusher)
	pusher._alert(player.global_position)
	pusher._set_state(Scav.State.ENGAGE)
	pusher.shot_damage = 0  # just watching it move
	for i in 90:
		await physics_frame
	var gap := pusher.global_position.distance_to(player.global_position)
	_check(gap >= pusher.min_distance - 0.3 and gap < pusher.min_distance + 2.5, "a scav that's too close backs off to about %.0f m (%.1f m)" % [pusher.min_distance, gap])
	pusher.queue_free()
	player.health.heal(player.health.max_health)


func _section_melee() -> void:
	# Get right up to a scav and it bashes you: damage, a shove, and a moment you can't aim.
	var scav := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 1.2)) as Scav
	_face_player(scav)
	scav.shot_damage = 0  # only the bash hurts here
	scav.min_distance = 0.0  # stand still and bash (don't back off out of reach)
	scav._alert(player.global_position)
	scav._set_state(Scav.State.ENGAGE)
	var hp := player.health.current
	var bashed := false
	for i in 120:
		await physics_frame
		if player.health.current < hp:
			bashed = true
			break
	_check(bashed and hp - player.health.current == scav.melee_damage, "a scav bashes you up close (-%d hp)" % (hp - player.health.current))
	_check(gun._aim_block_left > 0.0 and not gun.wants_aim(), "the bash knocks you out of aiming for a moment")
	_check(player.velocity.length() > 3.0, "the bash shoves you back (%.1f m/s)" % player.velocity.length())
	scav.queue_free()
	var raider := _spawn(RAIDER_SCENE, player.global_position + Vector3(0, 0, 30)) as Scav
	_check(raider.melee_damage > scav.melee_damage and raider.melee_cooldown < scav.melee_cooldown, "Raiders bash harder and faster")
	raider.queue_free()
	player.health.heal(player.health.max_health)


func _section_spawn_budget() -> void:
	# A raid has a limited number of enemies, spread out: 3 scavs at the start, one every 25-35 s up to 20,
	# Raiders at minutes 2, 3.5, 5, 6.5 and 8. Never more than 5 alive. Dead ones don't come back.
	var spawner := EnemySpawner.new()
	spawner.enemy_scene = load(SCAV_SCENE)
	spawner.raider_scene = load(RAIDER_SCENE)
	spawner.set_physics_process(false)  # the test drives the raid clock itself
	for i in 6:
		var marker := Marker3D.new()
		marker.position = player.global_position + Vector3(70, 0, 0).rotated(Vector3.UP, i * TAU / 6.0)
		spawner.add_child(marker)
	main.add_child(spawner)
	await _frames(2)
	_check(spawner.scavs_spawned == 3 and spawner.raiders_spawned == 0, "raid starts with 3 scavs, no Raiders")
	var alive_max := 0
	var raiders_at := {}
	for second in 600:
		spawner.tick(1.0)
		alive_max = maxi(alive_max, get_nodes_in_group("enemies").size())
		if second == 110:
			raiders_at[110] = spawner.raiders_spawned
		if second == 125:
			raiders_at[125] = spawner.raiders_spawned
		if second == 20:
			raiders_at["scavs_30"] = spawner.scavs_spawned
		# Kill everything every 20 s so slots free up (like the player clearing areas).
		if second % 20 == 0:
			for enemy in get_nodes_in_group("enemies"):
				enemy.remove_from_group("enemies")
				enemy.queue_free()
	_check(raiders_at["scavs_30"] == 3, "no extra scavs in the first 20 s")
	_check(raiders_at[110] == 0 and raiders_at[125] == 1, "the first Raider arrives around minute 2")
	_check(spawner.scavs_spawned == spawner.scav_budget and spawner.raiders_spawned == spawner.raider_budget,
		"over a whole raid: exactly %d scavs and %d Raiders (%d, %d)" % [spawner.scav_budget, spawner.raider_budget, spawner.scavs_spawned, spawner.raiders_spawned])
	spawner.queue_free()
	await _frames(2)
	# The cap: with nobody dying and spawns due constantly, it stops at max_alive.
	var crowded := EnemySpawner.new()
	crowded.enemy_scene = load(SCAV_SCENE)
	crowded.raider_scene = load(RAIDER_SCENE)
	crowded.set_physics_process(false)
	crowded.initial_count = 0
	crowded.scav_budget = 20
	crowded.scav_interval_min = 1.0
	crowded.scav_interval_max = 1.0
	var marker := Marker3D.new()
	marker.position = player.global_position + Vector3(70, 0, 0)
	crowded.add_child(marker)
	main.add_child(crowded)
	for second in 60:
		crowded.tick(1.0)
		alive_max = maxi(alive_max, get_nodes_in_group("enemies").size())
	_check(get_nodes_in_group("enemies").size() == crowded.max_alive and alive_max <= crowded.max_alive,
		"never more than %d alive at once (max seen %d)" % [crowded.max_alive, alive_max])
	for enemy in get_nodes_in_group("enemies"):
		enemy.remove_from_group("enemies")
		enemy.queue_free()
	crowded.queue_free()
	await _frames(2)


func _section_pathing() -> void:
	# The raid builds a navigation map; a scav walks around a building instead of into its wall.
	var nav := main.get_node("Navigation") as NavBaker
	_check(nav.is_baked and nav.navigation_mesh.get_polygon_count() > 50, "the raid builds a navigation map (%d areas)" % nav.navigation_mesh.get_polygon_count())
	player.teleport_to(Vector3(-30, 0.1, -30))  # out of the way (it shouldn't spot you)
	# Behind the grocery's back wall (z 19.75); the goal is inside, so it has to go round to the front door.
	var scav := _spawn(SCAV_SCENE, Vector3(15, 0.1, 23)) as Scav
	scav.investigate_speed = 1.0
	await physics_frame
	var inside := Vector3(15, 0, 15)
	scav._goal = inside
	scav._set_state(Scav.State.INVESTIGATE)
	var last := scav.global_position
	var stuck_for := 0.0
	var arrived := false
	for i in 60 * 20:
		await physics_frame
		if scav.global_position.distance_to(last) < 0.005:
			stuck_for += 1.0 / 60.0
		else:
			stuck_for = 0.0
		last = scav.global_position
		if Vector2(scav.global_position.x - inside.x, scav.global_position.z - inside.z).length() < 1.5:
			arrived = true
			break
		if stuck_for > 2.0:
			break
	_check(scav._path.size() > 2, "its path goes around the building (%d points)" % scav._path.size())
	_check(arrived, "it walks around the grocery to a spot inside (ended at %s)" % str(scav.global_position.snapped(Vector3.ONE * 0.1)))
	scav.queue_free()


func _section_patrol() -> void:
	# Unaware scavs patrol across the map at a walking pace instead of idling where they spawned.
	player.teleport_to(Vector3(-30, 0.1, -30))
	var scav := _spawn(SCAV_SCENE, Vector3(30, 0.1, 30)) as Scav  # a corner spawn point
	await physics_frame
	var start := scav.global_position
	var farthest := 0.0
	var top_speed := 0.0
	# Only while it's unaware (left long enough it may well wander into view of the player and react).
	for i in 60 * 20:
		await physics_frame
		if scav.state != Scav.State.IDLE:
			break
		farthest = maxf(farthest, scav.global_position.distance_to(start))
		top_speed = maxf(top_speed, Vector2(scav.velocity.x, scav.velocity.z).length())
	_check(farthest > 15.0, "an unaware scav patrols away from its spawn (%.0f m in 20 s)" % farthest)
	_check(top_speed > 1.7 and top_speed < scav.move_speed, "it patrols at a walking pace (%.1f m/s)" % top_speed)
	scav.queue_free()


func _section_scav_looting() -> void:
	# Like a player, a patrolling scav stops at a loot container and searches it, but takes nothing (owner).
	player.teleport_to(Vector3(-30, 0.1, -30))
	var crate := main.get_node("Loot/Crate0") as LootContainer
	var before: int = crate.grid.stacks.size()
	var scav := _spawn(SCAV_SCENE, crate.global_position + Vector3(6, 0.1, 0)) as Scav
	await physics_frame
	scav._wander_dir = Vector3.ZERO
	scav._wander_time = 0.0
	scav.jog_chance = 0.0
	# Force this patrol leg to the crate.
	var map := scav.get_world_3d().navigation_map
	var looted := false
	for i in 60 * 15:
		if scav._wander_dir == Vector3.ZERO and scav._wander_time <= 0.0 and not looted:
			scav._wander_point = NavigationServer3D.map_get_closest_point(map, crate.global_position)
			scav._patrol_container = crate
			scav._wander_dir = Vector3.FORWARD
			scav._patrol_time = 0.0
		await physics_frame
		if scav._looting_left > 0.0:
			looted = true
			break
	_check(looted and scav.state == Scav.State.IDLE, "a patrolling scav stops to search a crate")
	var after: int = crate.grid.stacks.size()
	_check(after == before, "...but takes nothing from it (%d -> %d stacks)" % [before, after])
	scav.queue_free()
	# About a third of patrol legs are jogs.
	var tester := _spawn(SCAV_SCENE, Vector3(30, 0.1, 30)) as Scav
	await physics_frame
	var jogs := 0
	for i in 90:
		tester._pick_patrol_point()
		if tester._patrol_jog:
			jogs += 1
	_check(jogs > 15 and jogs < 45, "about 1 in 3 patrol legs is a jog (%d of 90)" % jogs)
	tester.queue_free()


func _section_cover() -> void:
	# Fighting comes first; in a break (nobody shooting at it for a bit) a scav ducks behind something nearby,
	# holds a moment, then comes back out to fight. Next to the police station (walls x -20..-10, z -20..-10).
	player.teleport_to(Vector3(-15, 0.1, 0))
	var scav := _spawn(SCAV_SCENE, Vector3(-8, 0.1, -8)) as Scav
	_face_player(scav)
	scav.shot_damage = 0  # watching it move, not dying
	scav._strafe_time = 99.0  # no random strafing, so the cover it finds doesn't depend on luck
	scav._strafe_dir = 0.0
	await physics_frame
	scav._alert(player.global_position)
	scav._set_state(Scav.State.ENGAGE)
	var took_cover := false
	var hidden_in_cover := false
	var came_back := false
	for i in 60 * 12:
		await physics_frame
		if scav._cover_phase == Scav.Cover.HOLDING and not took_cover:
			took_cover = true
			var eyes := player.camera.global_position
			var query := PhysicsRayQueryParameters3D.create(eyes, scav.global_position + Vector3(0, 1.3, 0), 1)
			hidden_in_cover = not scav.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		if took_cover and scav._cover_phase == Scav.Cover.NONE and scav._can_see:
			came_back = true
			break
	_check(took_cover and hidden_in_cover, "in a break in the fight, a scav moves to cover you can't see")
	_check(came_back, "...then comes back out to fight")
	scav.queue_free()
	# While you keep shooting, there's no break: it stays and fights.
	var fighter := _spawn(SCAV_SCENE, Vector3(-8, 0.1, -8)) as Scav
	_face_player(fighter)
	fighter.shot_damage = 0
	await physics_frame
	fighter._alert(player.global_position)
	fighter._set_state(Scav.State.ENGAGE)
	var ducked := false
	for i in 60 * 5:
		if i % 30 == 0:
			fighter.notice_threat()  # the player firing every half second
		await physics_frame
		if fighter._cover_phase != Scav.Cover.NONE:
			ducked = true
	_check(not ducked, "while you keep shooting it keeps fighting (no ducking)")
	fighter.queue_free()


func _section_lean() -> void:
	# Q/E lean: the head shifts and tilts; no sprinting while leaning. Interact moved to F.
	var interact_keys := InputMap.action_get_events("interact")
	_check(interact_keys.size() > 0 and (interact_keys[0] as InputEventKey).physical_keycode == KEY_F, "interact is on F")
	_check((InputMap.action_get_events("lean_left")[0] as InputEventKey).physical_keycode == KEY_Q
		and (InputMap.action_get_events("lean_right")[0] as InputEventKey).physical_keycode == KEY_E, "lean is on Q / E")
	Input.action_press("lean_right")
	await create_timer(0.5).timeout
	_check(player.lean > 0.9 and player.head.position.x > 0.3, "leaning right moves the head over (%.2f m)" % player.head.position.x)
	_check(player.camera.rotation.z < -0.15, "...and tilts the camera")
	player.rotation.y = PI
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await create_timer(0.5).timeout
	_check(not player.is_sprinting(), "can't sprint while leaning")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	Input.action_release("lean_right")
	await create_timer(0.5).timeout
	_check(absf(player.head.position.x) < 0.05, "letting go stops leaning")
	# Tap-to-toggle mode (the setting for touch screens).
	GameSettings.lean_toggle = true
	await _press("lean_left")
	await create_timer(0.5).timeout
	_check(player.lean < -0.9, "tap mode: one tap leans and stays leaning")
	await _press("lean_left")
	await create_timer(0.5).timeout
	_check(absf(player.lean) < 0.1, "tap mode: tapping again stops")
	GameSettings.lean_toggle = false
	# No leaning through walls: next to the grocery's west wall (surface at x 9.0), facing +Z so "left" is +X,
	# leaning left goes only as far as there's room.
	player.teleport_to(Vector3(8.5, 0.1, 15))
	player.rotation.y = PI
	await physics_frame
	Input.action_press("lean_left")
	await create_timer(0.5).timeout
	Input.action_release("lean_left")
	var head_x := player.head.global_position.x
	_check(head_x < 9.25 - 0.1, "leaning into a wall stops short of it (head at x %.2f, wall at 9.25)" % head_x)


func _section_hurt() -> void:
	# A badly hurt scav (below 30%) falls back to cover and patches up (+40 HP over 4 s); shooting it interrupts the heal.
	var checker := _spawn(SCAV_SCENE, Vector3(30, 0.1, 30)) as Scav
	await physics_frame
	checker.health.take_damage(65)  # 35 HP: hurt, but above 30%
	_check(not checker._wants_heal, "a scav at 35% keeps fighting (falls back below 30%)")
	checker.queue_free()
	player.teleport_to(Vector3(-15, 0.1, 0))
	var scav := _spawn(SCAV_SCENE, Vector3(-8, 0.1, -8)) as Scav
	_face_player(scav)
	scav.shot_damage = 0
	scav._strafe_time = 99.0
	scav._strafe_dir = 0.0
	await physics_frame
	scav._alert(player.global_position)
	scav._set_state(Scav.State.ENGAGE)
	scav.health.take_damage(75, player.global_position)  # 25 HP left: below 30%
	var hp_hurt := scav.health.current
	var healed := false
	var hid_to_heal := false
	for i in 60 * 10:
		await physics_frame
		if scav._cover_phase == Scav.Cover.HEALING and not hid_to_heal:
			var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, scav.global_position + Vector3(0, 1.3, 0), 1)
			hid_to_heal = not scav.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		if scav.health.current > hp_hurt:
			healed = true
			break
	_check(hid_to_heal, "a badly hurt scav falls back to cover to heal")
	_check(healed and scav.health.current == hp_hurt + scav.heal_amount, "it patches up (+%d HP: %d -> %d)" % [scav.heal_amount, hp_hurt, scav.health.current])
	scav.queue_free()
	# Shooting it while it heals interrupts the heal.
	var patient := _spawn(SCAV_SCENE, Vector3(-8, 0.1, -8)) as Scav
	patient.shot_damage = 0
	await physics_frame
	patient._alert(player.global_position)
	patient._set_state(Scav.State.ENGAGE)
	patient.health.take_damage(65)
	patient._start_heal()
	await create_timer(1.0).timeout
	patient.health.take_damage(5, player.global_position)
	await create_timer(3.5).timeout
	_check(patient._cover_phase != Scav.Cover.HEALING and patient.health.current == 30, "getting shot interrupts its heal (hp %d)" % patient.health.current)
	patient.queue_free()


func _section_raiders() -> void:
	# Raiders are harder (owner); scavs keep their behavior. Raiders: hear fights from farther, flank, sneak when close,
	# hunt longer, cover/heal better, and sometimes come as a duo.
	var scav := _spawn(SCAV_SCENE, Vector3(30, 0.1, 30)) as Scav
	var raider := _spawn(RAIDER_SCENE, Vector3(-30, 0.1, 30)) as Scav
	_check(scav.hearing_mult == 1.0 and scav.flank_chance == 0.0 and scav.sneak_range == 0.0 and scav.give_up_time == 6.0 and scav.heals == 1,
		"scavs keep their behavior (no Raider tricks)")
	_check(raider.hearing_mult > 1.0 and raider.flank_chance > 0.0 and raider.sneak_range > 0.0 and raider.give_up_time > scav.give_up_time
		and raider.search_time > scav.search_time and raider.heals > scav.heals and raider.cover_cooldown < scav.cover_cooldown, "Raiders get the harder behavior")
	# Hears a gunshot from farther than a scav would (comes toward fights).
	for s in [scav, raider]:
		s._wander_time = 99.0
		s._wander_dir = Vector3.ZERO
	await physics_frame
	var shot_from := raider.global_position + Vector3(0, 0, -40)
	raider.hear_noise(shot_from, 25.0)
	scav.hear_noise(scav.global_position + Vector3(0, 0, -40), 25.0)
	_check(raider.state == Scav.State.INVESTIGATE and scav.state == Scav.State.IDLE, "a Raider hears a gunshot 40 m away (a scav doesn't)")
	# Sneaks (quiet, slower) when close to where it's going.
	raider._goal = raider.global_position + Vector3(0, 0, -8)
	_check(raider._sneaking(), "a Raider closing in moves quietly")
	raider.queue_free()
	scav.queue_free()
	# Flanking: in a lull, a Raider may circle around instead of trading shots.
	player.teleport_to(Vector3(0, 0.1, -10))
	var flanker := _spawn(RAIDER_SCENE, Vector3(0, 0.1, 5)) as Scav
	_face_player(flanker)
	flanker.shot_damage = 0
	await physics_frame
	flanker._alert(player.global_position)
	flanker._set_state(Scav.State.ENGAGE)
	flanker._target = player
	flanker._try_flank(player.global_position - flanker.global_position, 15.0)
	var start := flanker.global_position
	var to_player := (player.global_position - start).normalized()
	for i in 120:
		await physics_frame
	var moved := flanker.global_position - start
	var sideways := absf(moved.dot(to_player.cross(Vector3.UP)))
	_check(sideways > 2.0, "a flanking Raider circles around to your side (%.1f m sideways)" % sideways)
	flanker.queue_free()
	# Duos: a Raider can arrive with a partner that follows it.
	var spawner := EnemySpawner.new()
	spawner.enemy_scene = load(SCAV_SCENE)
	spawner.raider_scene = load(RAIDER_SCENE)
	spawner.set_physics_process(false)
	spawner.initial_count = 0
	spawner.raider_duo_chance = 1.0
	var marker := Marker3D.new()
	marker.position = Vector3(30, 0.1, 30)
	spawner.add_child(marker)
	main.add_child(spawner)
	await physics_frame
	spawner._spawn(spawner.raider_scene)
	var partners := 0
	for e in get_nodes_in_group("enemies"):
		if e is Scav and (e as Scav).leader != null:
			partners += 1
	_check(spawner.raiders_spawned == 2 and partners == 1, "a Raider duo spawns (2 Raiders, one following the other)")
	for e in get_nodes_in_group("enemies"):
		e.remove_from_group("enemies")
		e.queue_free()
	spawner.queue_free()
	await _frames(2)


# --- Helpers -------------------------------------------------------------------

## Points the player's camera at `target` with no recoil.
func _aim(target: Vector3) -> void:
	var dir := (target - player.camera.global_position).normalized()
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.head.rotation.x = asin(dir.y)
	player.recoil.rotation = Vector3.ZERO
	player._recoil_debt = Vector2.ZERO


## First stack of `id` in `stacks` (with exactly `count` items, if given), or null.
func _find_stack(stacks: Array, id: String, count := -1) -> ItemStack:
	for stack: ItemStack in stacks:
		if stack.id == id and (count < 0 or stack.count == count):
			return stack
	return null


## Instances a scene into the level at `pos`.
func _spawn(path: String, pos: Vector3) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	main.add_child(node)
	node.global_position = pos
	return node


## Turns `node` (around Y only) to face the player.
func _face_player(node: Node3D) -> void:
	node.look_at(Vector3(player.global_position.x, node.global_position.y, player.global_position.z))


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


func _backup_profile() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		_profile_backup = FileAccess.get_file_as_bytes(PROFILE_PATH)


## Puts the player's own save back (or removes the test's save if there wasn't one).
func _restore_profile() -> void:
	if _profile_backup == null:
		if FileAccess.file_exists(PROFILE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
		return
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_buffer(_profile_backup)
		file.close()


func _quit(code: int) -> void:
	_restore_profile()
	quit(code)
