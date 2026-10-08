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
	"shoot", "reload", "ads", "accuracy", "recoil", "ttk", "scav_shoots", "knife", "scav_hit", "senses",
	"movement", "stealth", "jump", "containers", "crate_model", "characters", "grid", "inventory",
	"equipment", "loot_ui", "dropped_gun", "heal", "extract", "death", "profile", "hideout", "settings",
	"ghost_stack", "owner_rules",
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
const PMC_SCENE := "res://scenes/pmc.tscn"

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
	var pmc_probe := (load(PMC_SCENE) as PackedScene).instantiate() as Scav
	var scav_hp: int = scav_probe.get_node("Health").max_health
	var pmc_health := pmc_probe.get_node("Health") as Health
	var hits_to_kill := func(hp: int, dmg: float) -> int: return ceili(hp / maxf(roundf(dmg), 1.0))
	_check(hits_to_kill.call(scav_hp, ak_damage) == 4 and hits_to_kill.call(scav_hp, ak_damage * gun.headshot_multiplier) == 2,
		"scav: 4 AK body shots or 2 headshots")
	_check(hits_to_kill.call(pmc_health.max_health, ak_damage * pmc_health.damage_multiplier) == 5, "armored PMC: 5 AK body shots")
	var pistol_data := ItemDB.item("pistol")
	_check(hits_to_kill.call(scav_hp, pistol_data["damage"]) == 6 and hits_to_kill.call(scav_hp, pistol_data["damage"] * pistol_data["head"]) == 3,
		"pistol: 6 body shots or 3 headshots")
	var to_kill_player: int = hits_to_kill.call(player.health.max_health, scav_probe.shot_damage)
	_check(to_kill_player >= 6 and to_kill_player <= 7, "you die in %d scav hits" % to_kill_player)
	_check(hits_to_kill.call(player.health.max_health, scav_probe.shot_damage * (1.0 - ItemDB.item("armor_light")["reduction"])) > to_kill_player,
		"light armor makes you last longer")
	scav_probe.free()
	pmc_probe.free()


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
	# on a scav and on an armored PMC.
	for scene in [SCAV_SCENE, PMC_SCENE]:
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
	# Character models (scav and PMC): imported .glb, one outfit option per slot, facing forward.
	for path: String in [SCAV_SCENE, PMC_SCENE]:
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


func _section_owner_rules() -> void:
	# Damage numbers use the damage actually dealt: an AK body shot on an armored PMC shows 22, not 28.
	var pmc := _spawn(PMC_SCENE, player.global_position + Vector3(0, 0, 30))
	var dealt: int = (pmc.get_node("Health") as Health).take_damage(ItemDB.item("ak")["damage"])
	_check(dealt == 22, "armored PMC takes (and shows) 22 from an AK body shot (%d)" % dealt)
	pmc.queue_free()

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
