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
	"shoot", "reload", "ads", "accuracy", "recoil", "ttk", "scav_shoots", "knife", "scav_hit", "senses", "spotting", "close_range", "crest", "melee", "spawn_budget", "zones", "sniper", "boss", "teamwork", "pathing", "patrol", "scav_looting", "cover", "lean", "hurt", "raiders", "hud",
	"movement", "stealth", "jump", "containers", "crate_model", "characters", "grid", "inventory",
	"equipment", "loot_ui", "dropped_gun", "heal", "meds", "downed", "extract", "death", "profile", "hideout", "settings",
	"ghost_stack", "owner_rules", "matchmaking", "net", "pvp", "online_ai", "online_loot", "old_bloxov",
]
## Sections that build on what an earlier one left behind. Running one also runs these (recursively).
const NEEDS := {
	"scav_hit": ["scav_shoots"],  # shoots and kills the scav spawned there
	"equipment": ["inventory"],  # counts the bandages picked up there (hotbar key 3)
	"loot_ui": ["equipment"],  # moves the watch/bandages from "inventory", swaps the heavy armor and pistol
	"heal": ["loot_ui"],  # uses one of the 7 bandages; adjusts the expected loot value
	"meds": ["heal"],  # puts the inventory and health back as "heal" left them
	"extract": ["heal"],  # checks the loot value carried out
	"death": ["extract"],
	"profile": ["death"],  # extracting saved the equipment
	"hideout": ["profile"],  # sells the gold watch put in the stash there
}
const PROFILE_PATH := "user://profile.json"
## Where the player stands for most tests: facing the dummy, open road behind.
const START_SPOT := Vector3(0, 0.1, -10)
const SCAV_SCENE := "res://scenes/scav.tscn"
const SNIPER_SCENE := "res://scenes/sniper.tscn"
const BOSS_SCENE := "res://scenes/boss.tscn"
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
	# Watchdog: if a script error stops the test mid-way, fail instead of hanging CI. (Game time: with --fixed-fps
	# it runs faster than real time; the whole test is about 150 game seconds.)
	create_timer(200.0, true).timeout.connect(func() -> void:
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
	# The checks below are built around the raid scene's small test map (real maps get their own section).
	RaidMap.scene_path = ""
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
	# Only the first hit of a flinch holds its fire: a stream of hits can't keep it from ever shooting back (0.11.16).
	enemy._fire_timer = 0.0
	enemy.health.take_damage(1, player.global_position)
	_check(enemy._fire_timer == 0.0 and enemy._flinch_left > 0.0, "more hits while flinching don't keep holding its fire")

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
	# Wading (0.11.20, owner): in water you're slower and can't sprint.
	player.set_meta(BoxMap.WADE_META, 1)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await create_timer(1.0).timeout
	_check(not player.is_sprinting() and absf(player.horizontal_speed() - player.walk_speed * player.wade_multiplier) < 0.3,
		"wading: no sprint, %.1f m/s (got %.2f)" % [player.walk_speed * player.wade_multiplier, player.horizontal_speed()])
	Input.action_release("move_forward")
	Input.action_release("sprint")
	player.remove_meta(BoxMap.WADE_META)
	await create_timer(0.8).timeout
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
	_check(inv.heal_count() == inv.count_of("bandage") + inv.count_of("medkit") and inv.heal_count() > 0 and not inv.hotbar.has("bandage"),
		"picked-up heals count on hotbar key 3 (Meds) instead of binding one by one (owner, 0.8.1)")


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
	# Bodies (owner, 0.11.13): their loadout shows as gear slots you can loot like your own.
	var corpse := LootContainer.spawn_bag(main, player.global_position, "Raider Body",
		[["ak", 1], ["armor_heavy", 1], ["pistol", 1], ["pistol", 1], ["bandage", 2]], 0.0, true)
	_check(corpse.gear["primary"].count_of("ak") == 1 and corpse.gear["armor"].count_of("armor_heavy") == 1
		and corpse.gear["secondary"].count_of("pistol") == 1 and corpse.grid.count_of("pistol") == 1 and corpse.grid.count_of("bandage") == 2,
		"a body's gear goes in its slots (one per slot), the rest in its pockets")
	_check(not corpse.gear["primary"].fits("pistol", 0, 0, false) and not corpse.gear["armor"].fits("armor_light", 0, 0, false),
		"a body's slot only takes its kind of item, one at a time")
	loot_ui.open_for(corpse)
	await process_frame
	var slot_views := loot_ui._views.filter(func(v: Control) -> bool: return v is SlotGridView)
	_check(slot_views.size() == 4, "the loot screen shows a body's 4 gear slots (%d)" % slot_views.size())
	var body_ak: ItemStack = corpse.gear["primary"].stacks[0]
	var my_ak := inv.equipped("primary")
	_check(loot_ui.equip_from_grid(corpse.gear["primary"], body_ak, "primary") and inv.equipped("primary") == body_ak
		and corpse.gear["primary"].stacks == [my_ak], "drag the body's AK onto your Primary: yours swaps into its slot")
	_check(loot_ui.equip_from_grid(corpse.gear["primary"], my_ak, "primary") and inv.equipped("primary") == my_ak, "and back")
	var body_pistol: ItemStack = corpse.gear["secondary"].stacks[0]
	loot_ui.quick_move(corpse.gear["secondary"], body_pistol)
	_check(corpse.gear["secondary"].is_empty() and inv.equipped("secondary") == body_pistol, "shift+click a body's pistol: straight into your empty Secondary slot")
	var my_bandage := _find_stack(inv.all_stacks(), "bandage")
	var bandages_moved := my_bandage.count
	loot_ui.quick_move(inv.pockets if inv.pockets.stacks.has(my_bandage) else inv.backpack, my_bandage)
	_check(corpse.gear["secondary"].is_empty() and corpse.grid.count_of("bandage") == 2 + bandages_moved, "shift+clicking a bandage into a body skips its gear slots")
	corpse.grid.take("bandage", bandages_moved)
	inv.add("bandage", bandages_moved)
	loot_ui.unequip_to_inventory("secondary")
	var my_pistol := _find_stack(inv.all_stacks(), "pistol")
	var pistol_grid := inv.pockets if inv.pockets.stacks.has(my_pistol) else inv.backpack
	loot_ui.quick_move(pistol_grid, my_pistol)
	_check(corpse.gear["secondary"].stacks == [my_pistol], "shift+click a pistol into a body: it fills the empty Secondary slot first")
	loot_ui.close()
	corpse.queue_free()
	expected_value = inv.total_value()
	# Pressing F to close the loot screen doesn't reopen it (F has to be let go first).
	var it := player.interactor
	loot_ui.open_for(null)
	await physics_frame
	var f_down := InputEventAction.new()
	f_down.action = "interact"
	f_down.pressed = true
	Input.action_press("interact")
	main.get_node("HUD")._input(f_down)  # the HUD closes the screen on the F press
	await physics_frame
	await physics_frame
	_check(not loot_ui.visible and not it.blocked, "F closes the loot screen")
	_check(it._open_needs_release, "holding the F that closed it can't open a container again")
	Input.action_release("interact")
	await physics_frame
	_check(not it._open_needs_release, "after letting go of F, F opens containers again")


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


func _section_meds() -> void:
	# Key 3 / the meds slot (owner): tap uses the med shown, hold switches it (Auto = best fit, like H).
	var saved := Profile.capture_inventory(inv)
	var hp := player.health.current
	for id in ["bandage", "medkit"]:
		inv.take(id, inv.count_of(id))
	inv.add("bandage", 1)
	inv.add("medkit", 1)
	player.health.current = player.health.max_health - 10
	# Hold 3 to switch meds (owner): Auto -> bandage -> medkit -> Auto, smallest first; a tap uses the pick.
	var meds_bar := HotbarHUD.new(player)
	root.add_child(meds_bar)
	var hold := Player.MEDS_HOLD_TIME + 0.1
	_check(inv.meds_choice == "" and meds_bar.slot_info(2).get("auto", false), "meds start on Auto (the slot shows the A)")
	player.meds_press()
	await create_timer(hold).timeout
	player.meds_release()
	_check(inv.meds_choice == "bandage" and not player.is_healing() and meds_bar._switch_text == "BANDAGE x1",
		"holding 3 switches to the bandage without using it (tape: %s)" % meds_bar._switch_text)
	player.meds_press()
	await create_timer(hold).timeout
	player.meds_release()
	_check(inv.meds_choice == "medkit" and meds_bar.slot_info(2).get("item") == "medkit" and not meds_bar.slot_info(2)["auto"],
		"holding 3 again switches to the medkit, and the slot shows it")
	# A touch on the meds slot is a tap of key 3: it uses the picked medkit even for a scratch.
	var at := meds_bar.get_global_transform_with_canvas() * meds_bar.slot_rect(2).get_center()
	for down in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = at
		touch.pressed = down
		meds_bar._input(touch)
	_check(player.is_healing() and inv.count_of("medkit") == 0 and inv.count_of("bandage") == 1, "tapping the meds slot uses the picked medkit")
	player.heal_time_left = 0.0
	_check(inv.find_meds(10)[1].id == "bandage" and meds_bar.slot_info(2)["auto"], "out of the picked med: back to Auto (bandage)")
	inv.meds_choice = ""
	meds_bar.queue_free()
	Profile.apply_inventory(inv, saved)
	player.health.current = hp


func _section_downed() -> void:
	# Downed (0.9.2, owner): in a squad 0 HP knocks you down; a bar drains 100 -> 0 over 30 s, hits take from it,
	# and at 0 you die. Solo you just die.
	var h := Health.new()
	root.add_child(h)
	h.can_go_down = func() -> bool: return true
	h.take_damage(150)
	_check(h.is_downed and not h.is_dead and h.current == 0 and h.down_hp == Health.DOWN_HP, "0 HP with a teammate up: downed (bar at 100), not dead")
	h.bleed(15.0)
	_check(is_equal_approx(h.down_hp, 50.0), "the downed bar drains 100 -> 0 in 30 s (50 after 15 s: %.1f)" % h.down_hp)
	h.take_damage(20)
	h.heal(50)
	_check(is_equal_approx(h.down_hp, 30.0) and h.current == 0 and not h.is_dead, "hits take from the downed bar; healing doesn't work while down")
	h.revive(30)
	_check(not h.is_downed and h.current == 30, "revived: back up at 30 HP")
	h.take_damage(30)
	h.take_damage(100)
	_check(h.is_dead and not h.is_downed, "shot to 0 on the downed bar: dead")
	h.queue_free()
	var bleeder := Health.new()
	root.add_child(bleeder)
	bleeder.can_go_down = func() -> bool: return true
	bleeder.take_damage(100)
	bleeder.bleed(29.0)
	var alive_at_29 := not bleeder.is_dead
	bleeder.bleed(1.1)
	_check(alive_at_29 and bleeder.is_dead, "nobody comes: dead after 30 s")
	bleeder.queue_free()
	var solo := Health.new()
	root.add_child(solo)
	solo.take_damage(100)
	_check(solo.is_dead and not solo.is_downed, "solo (nobody to revive you): 0 HP is dead, as before")
	solo.queue_free()

	# The player, with a stand-in teammate: down, crawling, hands off everything, scavs leave you alone, revive.
	player.squad_check = func() -> bool: return true
	var heals := inv.count_of("bandage")
	player.health.take_damage(9999)
	await physics_frame
	_check(player.downed and not player.is_dead and not player.controls_locked() and player.out_of_fight(), "the player is downed, not dead")
	player.try_heal()
	_check(not player.hands_free() and not player.knife.swing() and not player.is_healing() and inv.count_of("bandage") == heals and not gun.visible,
		"downed: no shooting (gun put away), knife or healing")
	var scav := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 6)) as Scav
	scav.shot_damage = 0
	await physics_frame
	_check(scav._pick_target() == null, "scavs ignore a downed player (owner)")
	scav.queue_free()
	Input.action_press("move_forward")
	await create_timer(1.0).timeout
	var crawl := player.horizontal_speed()
	Input.action_release("move_forward")
	_check(absf(crawl - player.walk_speed * 0.25) < 0.15, "downed players crawl at 1/4 walk speed (%.2f)" % crawl)
	await create_timer(0.5).timeout
	_check(player.head.position.y < 0.6, "the view drops to the ground (eyes at %.2f)" % player.head.position.y)
	var hud: Node = main.get_node("HUD")
	_check(hud.downed_hud.revive_fraction() < 0.0 and hud.prompt_hud.current().is_empty(), "the downed bar shows; no revive bar until someone revives you")
	player.set_being_revived(true)
	await create_timer(1.0).timeout
	var shown: float = hud.downed_hud.revive_fraction()
	_check(shown > 0.1 and shown < 0.4, "a teammate holding F: the REVIVING bar fills over 5 s (%.2f after 1 s)" % shown)
	var bar_before := player.health.down_hp
	player.revive()
	await physics_frame
	_check(not player.downed and player.health.current == player.revive_health and player.hands_free() and gun.visible and bar_before < 98.0,
		"revived: back up at %d HP, gun out" % player.revive_health)
	player.squad_check = player.teammate_can_revive
	_check(not player.teammate_can_revive(), "offline there's no teammate (solo still dies at 0)")


func _section_extract() -> void:
	# Extraction: walk into an open extract and wait.
	var open_zone: ExtractZone = null
	var open_count := 0
	for zone in raid.get_extracts():
		if zone.is_open:
			open_count += 1
			open_zone = zone
	_check(open_count == raid.open_extract_count, "%d of 3 extracts are open" % open_count)
	# Near your spawn = closed for you (0.10.3); a small map fills in with the farthest ones.
	var picked := Raid.pick_open(raid.get_extracts(), player.global_position, 2)
	_check(picked.size() == 2, "two extracts open even when they're all near the spawn (test map)")
	player.teleport_to(open_zone.global_position + Vector3(0, 0.2, 0))
	await create_timer(open_zone.extract_time + 1.0).timeout
	_check(raid.result == "extracted" and raid.extract_used == open_zone.extract_name, "standing in an open extract extracts (%s)" % raid.result)
	_check(raid.loot_value == expected_value, "extracted loot is counted (%s, expected %s)" % [ItemDB.money(raid.loot_value), ItemDB.money(expected_value)])
	_check(not raid.loot_summary.is_empty(), "end screen lists the loot")
	_check(player.controls_locked(), "controls lock after extracting")
	var end_screen: RaidEndScreen = main.get_node("HUD").end_screen
	var shown := end_screen.summary()
	_check(end_screen.visible and shown["stamp"] == "EXTRACTED" and String(shown["value"]).begins_with("KEPT"),
		"the end screen stamps EXTRACTED and tags what you kept (%s, %s)" % [shown["stamp"], shown["value"]])


func _section_death() -> void:
	# In a squad: downed first; once nobody is left who could revive you (they went down too), you die.
	var teammate_up := [true]
	player.squad_check = func() -> bool: return teammate_up[0]
	player.health.take_damage(9999)
	await _frames(3)
	_check(player.downed and not player.is_dead, "player goes down at 0 hp with a teammate up")
	teammate_up[0] = false
	await _frames(3)
	_check(player.is_dead and not player.downed, "player dies once nobody is left to revive them (both down)")
	player.squad_check = player.teammate_can_revive


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
	# Web keeps a second copy in localStorage: loading takes whichever copy was saved last.
	var older := JSON.stringify({"version": Profile.VERSION, "saved_at": 100.0})
	var newer := JSON.stringify({"version": Profile.VERSION, "saved_at": 200.0})
	_check(Profile.newer_save(older, newer) == newer and Profile.newer_save(newer, older) == newer
		and Profile.newer_save("", older) == older and Profile.newer_save(older, "") == older
		and Profile.newer_save("{}", newer) == newer and Profile.newer_save(older, "{}") == older,
		"loading picks the newest of the file and web copies of the save")


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
	_check(hideout._online_panel != null and not hideout._online_box.visible and hideout.online_status() == "ONLINE", "the online panel starts offline")
	hideout._message("Sold Antique Vase for $1,200,000 and some more words so the message is long")
	_check(not hideout._message_label.clip_text and hideout._message_label.autowrap_mode != TextServer.AUTOWRAP_OFF, "long hideout messages aren't cut off")
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
	# Squads spawn together (owner, 0.9.5): one spawn slot per squad, places side by side.
	var slots := Matchmaker.spawn_slots([[11, 12], [13], [14, 15]], 42)
	_check(slots[11][0] == slots[12][0] and slots[11][1] == 0 and slots[12][1] == 1 and slots[13][0] != slots[11][0]
		and slots[14][0] != slots[11][0] and slots[14][0] != slots[13][0] and slots == Matchmaker.spawn_slots([[11, 12], [13], [14, 15]], 42),
		"each squad gets its own spawn, squadmates side by side (%s)" % str(slots))
	var points := main.get_node("PlayerSpawns").get_children()
	var first := Raid.spawn_position(points, 1, 0)
	var second := Raid.spawn_position(points, 1, 1)
	var wrapped := Raid.spawn_position(points, points.size() + 1, 0)
	_check(is_equal_approx(first.distance_to(second), Raid.SQUAD_SPACING) and first.distance_to(wrapped) > 3.0
		and Raid.spawn_position(points.duplicate(), 1, 0) == first, "spawn slots: the same point on every machine, squadmates next to each other")
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
	mm.add_player(11, "  Big\tBoss  [x]  ")
	mm.add_player(12, "sh1t head")
	mm.add_player(13, "f u c k")
	_check(mm.players[11]["name"] == "BigBoss x" and mm.players[12]["name"] == "Player 12" and mm.players[13]["name"] == "Player 13",
		"names are cleaned for other players: odd characters dropped, rude words (even spelled with numbers or spaces) replaced (%s)"
		% [[mm.players[11]["name"], mm.players[12]["name"], mm.players[13]["name"]]])
	_check(NameFilter.clean("Torpedo Grape", "x") == "Torpedo Grape" and NameFilter.clean("abcdefghijklmnopqrstu", "x").length() == NameFilter.MAX_LENGTH,
		"ordinary names stay as they are (cut to 16 letters)")


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
	_check(c1.raid_spawn.size() == 2 and c1.raid_spawn[0] == c2.raid_spawn[0] and c1.raid_spawn[1] != c2.raid_spawn[1]
		and c3.raid_spawn[0] != c1.raid_spawn[0], "squads spawn together, other squads elsewhere (%s %s %s)" % [c1.raid_spawn, c2.raid_spawn, c3.raid_spawn])

	# States are relayed within the raid: Charlie sees Alpha where Alpha is, and never sees himself.
	var sent := [Vector3(4, 0.1, -6), 1.2, 0.3, 1.0, RemotePlayer.FLAG_CROUCH]
	await _until(func() -> bool:
		c1.send_state(sent)
		return c3.states.has(c1_id) and c3.states[c1_id][0].is_equal_approx(Vector3(4, 0.1, -6)))
	_check(c3.states.has(c1_id) and c3.states[c1_id] == sent, "Charlie sees Alpha's position, facing, crouch and lean")
	_check(not c3.states.has(c3.multiplayer.get_unique_id()), "you don't see yourself as another player")
	_check(not Network.is_valid_state([Vector3.ZERO, "hi"]) and Network.is_valid_state(RemotePlayer.capture(player)),
		"the server only relays well-formed states")

	# Reviving goes through the server: only your squad, only close by, only after holding F long enough.
	server.revive_min_hold = 0.1
	var revive_log := []
	c2.revive_changed.connect(func(on: bool) -> void: revive_log.append(on))
	c2.revived.connect(func() -> void: revive_log.append("up"))
	await _until(func() -> bool:
		c2.send_state([Vector3(4, 0.1, -7), 0.0, 0.0, 0.0, Hitbox.FLAG_DOWNED])
		c1.send_state([Vector3(4, 0.1, -6), 0.0, 0.0, 0.0, 0])
		return server.can_revive(c1_id, c2_id))
	var c3_id: int = c3.multiplayer.get_unique_id()
	_check(server.can_revive(c1_id, c2_id) and not server.can_revive(c3_id, c2_id) and not server.can_revive(c2_id, c1_id),
		"only a teammate who is up can revive a downed player")
	c3.send_reviving(c2_id, true)
	c3.send_revive(c2_id)
	c1.send_reviving(c2_id, true)
	c1.send_revive(c2_id)
	await _until(func() -> bool: return revive_log.size() >= 2)
	_check(revive_log == [true, false], "a revive that wasn't held long enough doesn't count (%s)" % str(revive_log))
	revive_log.clear()
	c1.send_reviving(c2_id, true)
	await _until(func() -> bool: return revive_log.size() >= 1)
	OS.delay_msec(150)
	c1.send_revive(c2_id)
	await _until(func() -> bool: return revive_log.size() >= 2)
	_check(revive_log == [true, "up"], "the downed player sees the revive start, then gets back up (%s)" % str(revive_log))
	c1.send_state(sent)

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
	_check(not body.gun_model.visible, "an unarmed player shows no gun")
	body.push_state([Vector3(2, 0.1, -12), 0.0, 0.0, 0.0, RemotePlayer.FLAG_ARMED], 10.07)
	body.update_view(10.07, 0.016)
	_check(body.gun_model.visible and RemotePlayer.capture(player)[4] & RemotePlayer.FLAG_ARMED, "a player holding a gun shows it")
	body.push_state([Vector3(2, 0.1, -12), 0.0, 0.0, 0.0, RemotePlayer.FLAG_DEAD], 10.1)
	for i in 60:
		body.update_view(10.1, 0.016)
	_check(body.model.rotation.x > 1.3 and body.body_shape.disabled, "a dead player lies down")
	body.push_state([Vector3(2, 0.1, -12), 0.0, 0.0, 0.0, RemotePlayer.FLAG_DOWNED], 10.2)
	for i in 60:
		body.update_view(10.2, 0.016)
	_check(body.model.rotation.x < -1.3 and not body.body_shape.disabled and body.head_shape.position.z < -1.5 and body.head_shape.position.y < 0.5,
		"a downed player lies face down (hitboxes too) and can still be shot")
	_check(not body.can_be_revived(), "only teammates can revive")
	var lying := [Vector3(0, 0, 0), 0.0, 0.0, 0.0, Hitbox.FLAG_DOWNED]
	_check(Hitbox.trace(lying, Vector3(-3, 1.5, -0.5), Vector3(3, 1.5, -0.5)).is_empty()
		and Hitbox.trace(lying, Vector3(0, 3, -1.7), Vector3(0, -1, -1.7)).get("headshot") == true,
		"the server's downed hitbox: low to the ground, head in front")
	net_raid.sync_remotes({})
	await _frames(1)
	_check(net_raid.remotes.is_empty() and not is_instance_valid(body), "a player who leaves disappears")

	# Reviving (0.9.2): stand next to a downed teammate and hold F for 5 s ([F] REVIVE), then let go before the next.
	Network.main.teammates = [78]
	net_raid.sync_remotes({78: [player.global_position + Vector3(0.5, 0, 0.5), 0.0, 0.0, 0.0, RemotePlayer.FLAG_DOWNED]})
	var mate: RemotePlayer = net_raid.remotes.get(78)
	var it := player.interactor
	it.revive_target = it.find_revive_target()
	_check(mate != null and mate.can_be_revived() and it.revive_target == mate, "a downed teammate next to you can be revived")
	var finished := []
	it.revive_finished.connect(func(peer: int) -> void: finished.append(peer))
	for i in 60 * 4:
		it.update_revive(1.0 / 60.0, true)
	var midway := it.is_reviving() and it.revive_progress > 0.75 and finished.is_empty()
	for i in 70:
		it.update_revive(1.0 / 60.0, true)
	_check(midway and finished == [78], "holding F for 5 s revives them")
	it.update_revive(1.0 / 60.0, true)
	_check(not it.is_reviving(), "a finished revive doesn't start over until F is let go")
	mate.global_position += Vector3(6, 0, 0)
	_check(it.find_revive_target() == null, "too far away: no revive")

	# Dead with a teammate still in the raid (0.9.5): watch them over the shoulder until they're out.
	var hud: Node = main.get_node("HUD")
	var spectator: Spectator = hud.spectator
	var ended := []
	spectator.finished.connect(func() -> void: ended.append(true), CONNECT_ONE_SHOT)
	mate.push_state([mate.global_position, 0.0, 0.0, 0.0, 0])
	mate.update_view(Time.get_ticks_msec() / 1000.0, 0.016)
	_check(spectator.start(78) and spectator.visible and spectator.camera.current, "spectating a teammate switches to a camera on them")
	var behind := spectator.camera.global_position - mate.global_position
	_check(behind.z > 1.5 and behind.y > 1.5 and absf(behind.x) < 0.5, "the camera is behind their head, looking where they look (%s)" % behind)
	mate.shown = [mate.global_position, 0.0, 0.0, 0.0, RemotePlayer.FLAG_EXTRACTED]
	spectator._process(0.016)
	_check(not spectator.visible and ended == [true], "once they're out, back to the end-of-raid screen")
	_check(not spectator.start(999), "nobody to watch: no spectating")
	_check(hud.end_screen.summary().get("spectate", "x") == "" and Spectator.watchable_teammate() == 0, "offline there's nobody to spectate")
	player.camera.make_current()
	net_raid.sync_remotes({})
	Network.main.teammates = []
	await _frames(1)

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
	_check(at_then.get("peer") == 901 and not at_now.has("peer"), "shots are checked against where the target was when you fired")
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


func _section_online_ai() -> void:
	# Everyone sees the same AI (0.7.8): scavs and Raiders run on the server (one raid world each); players see
	# puppets. Scavs see/hear/shoot/bash players through proxy bodies; players' shots and knives hit server scavs.
	var server := _net_peer("AiServer")
	var c1 := _net_peer("AiClient1")
	var c2 := _net_peer("AiClient2")
	server.start_server(19083)
	var got := {"hits": [], "bashes": 0, "confirmed": 0, "kills": 0, "events": []}
	c1.got_hit.connect(func(amount: int, _from: Vector3, _h: bool) -> void: got["hits"].append(amount))
	c1.bashed.connect(func(_a: int, _f: Vector3, _s: float, _b: float) -> void: got["bashes"] += 1)
	c1.shot_confirmed.connect(func(_h: bool) -> void: got["confirmed"] += 1)
	c1.kill_confirmed.connect(func() -> void: got["kills"] += 1)
	c1.enemy_event.connect(func(id: int, kind: String, pos: Vector3) -> void: got["events"].append([id, kind, pos]))
	for c in [c1, c2]:
		c.go_online("localhost:19083", "AiTester")
	await _until(func() -> bool: return c1.is_client() and c2.is_client() and c1.party_code != "" and c2.party_code != "")
	c1.start_now()
	c2.start_now()
	await _until(func() -> bool: return c1.in_raid and c2.in_raid and server._worlds.size() == 2)
	var c1_id: int = c1.multiplayer.get_unique_id()
	var c2_id: int = c2.multiplayer.get_unique_id()
	var w1: RaidWorld = server._worlds[server.matchmaker.players[c1_id]["raid"]]
	var w2: RaidWorld = server._worlds[server.matchmaker.players[c2_id]["raid"]]
	for i in 6:
		c1.send_state([Vector3(0, 0.1, -30), 0.0, 0.0, 0.0, 0])
		c2.send_state([Vector3(0, 0.1, -30), 0.0, 0.0, 0.0, 0])
		await _frames(3)
	var scavs1 := RaidScope.nodes(w1.raid, &"enemies")
	_check(scavs1.size() == 3 and RaidScope.nodes(w2.raid, &"enemies").size() == 3, "each online raid spawns its own 3 scavs on the server")
	_check(scavs1.all(func(e: Node) -> bool: return RaidScope.nodes(e, &"player") == [w1.proxies.get(c1_id)]),
		"a raid's scavs only see that raid's players (one proxy each)")
	await _until(func() -> bool: return c1.enemies.size() == 3)
	_check(c1.enemies.size() == 3 and c1.enemies[0][2].size() == 4, "players get the raid's scavs (position, facing, pose, hits)")

	# Puppets: copies that only follow the server.
	var net_raid := main.get_node("NetRaid") as NetRaid
	net_raid.sync_enemies(c1.enemies)
	var puppet: Scav = net_raid.enemy_puppets.values()[0]
	_check(net_raid.enemy_puppets.size() == 3 and puppet.puppet and puppet.is_in_group("enemies"), "the raid shows the 3 scavs as puppets")
	var puppet_state := puppet.state
	puppet.hear_noise(puppet.global_position, 50.0)
	puppet.notice_near_miss(puppet.global_position)
	_check(puppet.state == puppet_state, "puppets don't think for themselves (no reacting to noise)")

	# Scavs hurt and bash players through their proxy: passed on to the player's game; the proxy stays alive.
	var proxy: Node = w1.proxies[c1_id]
	proxy.health.take_damage(15, Vector3(0, 0, -20))
	proxy.take_bash(20, Vector3(0, 0, -29), 6.0, 0.6)
	await _until(func() -> bool: return got["hits"].size() == 1 and got["bashes"] == 1)
	_check(got["hits"] == [15] and got["bashes"] == 1 and proxy.health.current == proxy.health.max_health,
		"a scav's shot and bash reach the player's game (the server's copy of them never dies)")

	# Players' shots hit server scavs (and make noise they hear).
	var target: Node3D = scavs1[0]
	for i in 3:
		c1.send_state([target.global_position + Vector3(0, 0, 6), 0.0, 0.0, 0.0, 0])
		await _frames(2)
	var before: int = target.health.current
	OS.delay_msec(60)
	var eye := target.global_position + Vector3(0, 1.5, 6)
	c1.send_shot(eye, (target.global_position + Vector3(0, 0.8, 0) - eye).normalized(), "ak")
	await _until(func() -> bool: return got["confirmed"] >= 1)
	_check(got["confirmed"] == 1 and target.health.current < before, "a player's shot hits a server scav (%d -> %d)" % [before, target.health.current])
	var listener: Node = scavs1[1]
	listener.set("state", Scav.State.IDLE)
	w1.shot_noise(listener.global_position, listener.global_position, 25.0, listener.global_position + Vector3(5, 0, 0))
	_check(listener.state != Scav.State.IDLE, "server scavs hear online gunshots")

	# A scav dying on the server: everyone sees it pop (its puppet goes).
	var dead_id := target.get_instance_id()
	target.health.take_damage(9999)
	await _until(func() -> bool: return got["events"].any(func(e: Array) -> bool: return e[0] == dead_id and e[1] == "died"))
	for e in got["events"]:
		net_raid.on_enemy_event(e[0], e[1], e[2])
	_check(not net_raid.enemy_puppets.has(dead_id), "a scav killed on the server disappears from players' screens")

	net_raid.sync_enemies([])
	await _frames(1)
	_check(net_raid.enemy_puppets.is_empty(), "puppets go when the server's scavs do")
	for c in [c1, c2]:
		c.go_offline()
	await _until(func() -> bool: return server.matchmaker.players.is_empty())
	await _frames(2)
	server.multiplayer.multiplayer_peer.close()
	for n in [server, c1, c2]:
		n.get_parent().queue_free()
	await _frames(2)
	_check(RaidScope.nodes(main, &"enemies").is_empty(), "nothing from online raids is left in the solo raid")


func _section_online_loot() -> void:
	# Shared loot (0.7.9): containers live on the server; one player at a time has one open; bodies (scavs and
	# players) and dropped items are bags everyone sees.
	var server := _net_peer("LootServer")
	var c1 := _net_peer("LootClient1")
	var c2 := _net_peer("LootClient2")
	server.start_server(19084)
	server.matchmaker.queue_countdown = 0.2
	var got := {}
	for c in [c1, c2]:
		got[c] = {"opened": {}, "busy": [], "bags": {}, "gone": []}
		c.container_opened.connect(func(id: String, data: Array) -> void: got[c]["opened"][id] = data)
		c.container_busy.connect(func(id: String) -> void: got[c]["busy"].append(id))
		c.bag_spawned.connect(func(id: String, _p: Vector3, _y: float, title: String, _s: float) -> void: got[c]["bags"][id] = title)
		c.bag_removed.connect(func(id: String) -> void: got[c]["gone"].append(id))
	c1.go_online("localhost:19084", "Looter")
	c2.go_online("localhost:19084", "Rival")
	await _until(func() -> bool: return c1.is_client() and c2.is_client() and c1.party_code != "" and c2.party_code != "")
	c1.set_queued(true)
	c2.set_queued(true)
	await _until(func() -> bool: return c1.in_raid and c2.in_raid)
	for i in 4:
		c1.send_state([Vector3(0, 0.1, -10), 0.0, 0.0, 0.0, 0])
		c2.send_state([Vector3(2, 0.1, -10), 0.0, 0.0, 0.0, 0])
		await _frames(2)
	var world: RaidWorld = server._worlds.values()[0]
	var crate := world.container("Crate0")
	_check(crate != null and not crate.grid.is_empty(), "the server rolls the raid's container contents")

	# One looter at a time; changes are kept for the next person.
	c1.open_container("Crate0")
	await _until(func() -> bool: return got[c1]["opened"].has("Crate0"))
	c2.open_container("Crate0")
	await _until(func() -> bool: return got[c2]["busy"].has("Crate0"))
	_check(got[c1]["opened"]["Crate0"] == crate.grid.to_data() and got[c2]["busy"] == ["Crate0"],
		"the first player gets the crate's contents; the second is told someone's looting it")
	var taken: Array = got[c1]["opened"]["Crate0"].duplicate(true)
	taken[2].pop_front()
	c1.update_container("Crate0", taken)
	c1.close_container()
	await _frames(4)
	c2.open_container("Crate0")
	await _until(func() -> bool: return got[c2]["opened"].has("Crate0"))
	_check(got[c2]["opened"]["Crate0"] == taken, "what the first player took is gone for the second")
	c1.update_container("Crate0", [4, 3, []])
	await _frames(4)
	_check(crate.grid.to_data() == taken, "only the player who has a container open can change it")
	c2.close_container()

	# Dropped items, and bodies: bags everyone sees.
	c1.drop_items([["bandage", 2, 0, 0, false, 0]])
	await _until(func() -> bool: return got[c2]["bags"].size() >= 1)
	var drop_id: String = got[c2]["bags"].keys()[0]
	_check(got[c1]["bags"].get(drop_id) == "Dropped Items" and got[c2]["bags"].get(drop_id) == "Dropped Items", "dropped items become a bag both players see")
	c2.open_container(drop_id)
	await _until(func() -> bool: return got[c2]["opened"].has(drop_id))
	_check(got[c2]["opened"][drop_id][2].size() == 1 and got[c2]["opened"][drop_id][2][0][0] == "bandage", "the other player can loot it")
	c2.update_container(drop_id, [4, 4, []])
	await _until(func() -> bool: return got[c1]["gone"].has(drop_id))
	await _frames(2)
	_check(got[c1]["gone"] == [drop_id] and world.container(drop_id) == null, "an emptied bag disappears for everyone (%s)" % str(got[c1]["gone"]))
	c2.drop_items([["ak", 1, 0, 0, false, 30], ["gold_watch", 1, 0, 0, false, 0], ["not_an_item", 1, 0, 0, false, 0]], true)
	await _until(func() -> bool: return got[c1]["bags"].values().has("Rival's Body"))
	_check(got[c1]["bags"].values().has("Rival's Body"), "a dead player's gear becomes a body others can loot")
	var body_id: String = got[c1]["bags"].find_key("Rival's Body")
	var rival_body := world.container(body_id)
	_check(rival_body.gear["primary"].count_of("ak") == 1 and rival_body.grid.count_of("gold_watch") == 1
		and rival_body.all_grids().reduce(func(n: int, g: GridInventory) -> int: return n + g.stacks.size(), 0) == 2,
		"a dead player's AK is in their body's Primary slot, the rest in its pockets, fake items left out")
	# Bodies online: the gear slots go with the contents, and taking the gun is seen by the next player.
	c1.open_container(body_id)
	await _until(func() -> bool: return got[c1]["opened"].has(body_id))
	var body_data: Array = got[c1]["opened"][body_id]
	_check(body_data.size() == 4 and body_data[3][0][2].size() == 1 and body_data[3][0][2][0][0] == "ak" and body_data[3][0][2][0][5] == 30,
		"opening a body online sends its gear slots too (the AK keeps its 30 rounds)")
	body_data[3][0] = [1, 1, []]
	c1.update_container(body_id, body_data)
	await _frames(4)
	_check(rival_body.gear["primary"].is_empty() and rival_body.grid.count_of("gold_watch") == 1, "taking a body's gun online empties its Primary slot")
	var bad_data := body_data.duplicate(true)
	bad_data[3][2] = [1, 1, [["bandage", 1, 0, 0, false, 0]]]
	c1.update_container(body_id, bad_data)
	await _frames(4)
	_check(rival_body.gear["armor"].is_empty(), "a body's armor slot only takes armor")
	c1.close_container()
	await _frames(2)

	# A scav's body on the server: announced to everyone.
	var scav: Node = RaidScope.nodes(world.raid, &"enemies")[0]
	var body_name: String = scav.body_name
	scav.health.take_damage(9999)
	await _until(func() -> bool: return got[c1]["bags"].values().has(body_name))
	_check(got[c1]["bags"].values().has("Scav Body") or got[c1]["bags"].values().has("Raider Body"), "a scav killed on the server leaves a body bag for everyone")

	# The raid on players' screens: bags appear and go with the server's.
	var net_raid := main.get_node("NetRaid") as NetRaid
	net_raid.on_bag_spawned("Bag99", player.global_position + Vector3(2, 0, 0), 0.0, "Test Body", 0.0)
	var shown := net_raid.find_container("Bag99")
	_check(shown != null and shown.display_name == "Test Body", "a bag from the server shows up in the raid")
	net_raid.on_bag_removed("Bag99")
	await _frames(1)
	_check(not is_instance_valid(shown), "and goes when the server's does")
	# Opening: the screen shows the server's contents; closing it lets the container go.
	var local_crate := net_raid.find_container("Crate0")
	net_raid._asked = local_crate
	net_raid.on_container_opened("Crate0", [4, 3, [["gold_watch", 1, 0, 0, false, 0]]])
	_check(loot_ui.visible and loot_ui.container == local_crate and local_crate.grid.count_of("gold_watch") == 1,
		"the loot screen opens with the server's contents")
	local_crate.grid.add("bandage")
	_check(net_raid._dirty, "changes are noted to send to the server")
	net_raid._update_open_container()
	loot_ui.close()
	net_raid._update_open_container()
	_check(net_raid._open == null and not net_raid._dirty, "closing the screen lets the container go")

	# Leaving lets go of anything open.
	c1.open_container(body_id)
	await _until(func() -> bool: return got[c1]["opened"].has(body_id))
	c1.go_offline()
	await _until(func() -> bool: return server.matchmaker.players.size() == 1)
	await _frames(4)
	_check(not world.locks.has(body_id), "a player who leaves stops holding the container")
	c2.go_offline()
	await _until(func() -> bool: return server.matchmaker.players.is_empty())
	server.multiplayer.multiplayer_peer.close()
	for n in [server, c1, c2]:
		n.get_parent().queue_free()
	await _frames(2)


func _section_old_bloxov() -> void:
	# The first real map (0.10.0): Bloxov Battlegrounds (first called Old Bloxov), a 350 m gray box built by tools/gen_old_bloxov.py. Its pieces
	# replace the test map's when a raid scene is made. Checked on a server raid copy (its own world).
	const MAP := "res://scenes/maps/old_bloxov.tscn"
	var map := (load(MAP) as PackedScene).instantiate()
	_check(map.get_node("Extracts").get_child_count() == 6 and map.get_node("PlayerSpawns").get_child_count() == 8,
		"Bloxov Battlegrounds: 6 extracts and 8 player spawns")
	# Extracts near your spawn are closed for you (owner, 0.10.3): every spawn still has enough far ones to open.
	var short := []
	for spawn: Node3D in map.get_node("PlayerSpawns").get_children():
		var far := map.get_node("Extracts").get_children().filter(func(e: Node3D) -> bool:
			return Vector2(e.position.x - spawn.position.x, e.position.z - spawn.position.z).length() >= Raid.CLOSED_NEAR_SPAWN)
		if far.size() < 3:
			short.append(spawn.name)
	_check(short.is_empty(), "every spawn has 3+ extracts far enough away to be open for it (%s)" % [short])
	_check(map.has_node("KeyDoors/BunkerDoor") and map.has_node("KeyDoors/BankVaultDoor"),
		"key door placeholders at the bunker and the bank vault (owner: keys come in the Items update)")
	var minimap: Dictionary = map.get_meta("minimap", {})
	var names: Array = minimap.get("labels", []).map(func(l: Array) -> String: return l[0])
	_check(minimap.get("size", 0.0) == 350.0 and minimap.get("buildings", PackedFloat32Array()).size() >= 4 * 30
		and names.has("BANK") and names.has("TOWN HALL") and minimap.get("roads", []).size() >= 5,
		"the map (M) has Bloxov Battlegrounds' buildings, roads and place names (%d names)" % names.size())
	var spots: Array[Vector3] = []
	for node in map.get_node("PlayerSpawns").get_children() + map.get_node("Extracts").get_children():
		spots.append((node as Node3D).position)
	map.free()

	RaidMap.scene_path = MAP
	var world := RaidWorld.new()
	root.add_child(world)
	RaidMap.scene_path = ""
	var spawner := world.raid.get_node("EnemySpawner")
	var zone_names: Array = spawner.zones.map(func(z: Dictionary) -> String: return z.name)
	var start_ai: int = spawner.roamers
	for z: Dictionary in spawner.zones:
		start_ai += int(z.scavs) + int(z.raiders)
	var zone_spots := {}
	for m: Node in spawner.get_children():
		zone_spots[m.get_meta("zone", "")] = zone_spots.get(m.get_meta("zone", ""), 0) + 1
	_check(zone_names.has("PoliceBank") and zone_names.has("SouthEast") and start_ai >= 20 and start_ai <= 30
		and spawner.roamers == 3 and spawner.max_alive >= 30,
		"Scavs 2.0: the map has AI zones (%s), %d AI at the start, 3 roamers" % [zone_names, start_ai])
	_check(spawner.zones.all(func(z: Dictionary) -> bool: return zone_spots.get(z.name, 0) > int(z.scavs) + int(z.raiders)),
		"...and every zone has more spawn spots than AI starting there (%s)" % [zone_spots])
	var loot := world.raid.get_node("Loot").get_children()
	_check(loot.size() >= 80 and loot.all(func(c: Node) -> bool: return c is LootContainer and c.has_meta("place")),
		"%d loot containers, each tagged with its place (police, bunker, ...)" % loot.size())
	var nav := world.raid.get_node("Navigation") as NavBaker
	await _until(func() -> bool: return nav.is_baked)
	for i in 3:
		await physics_frame
	var nav_map := nav.get_navigation_map()
	var start := spots[0]
	var off_nav := spots.filter(func(p: Vector3) -> bool:
		return NavigationServer3D.map_get_closest_point(nav_map, p).distance_to(p) > 1.5)
	_check(off_nav.is_empty(), "every player spawn and extract is on walkable ground (%s)" % [off_nav])
	# Every container (upstairs, in the bunker, in the bank vault) can be walked to from a spawn: the AI's paths
	# go there too (ramps, doorways and stair landings wide enough for them).
	var unreachable: Array[String] = []
	var query := NavigationPathQueryParameters3D.new()
	query.map = nav_map
	query.start_position = start
	query.path_search_max_polygons = 0  # (as the scavs do: a path across the whole map)
	for c: Node3D in loot:
		var front := c.global_position + c.global_basis.z * -1.3 + Vector3.UP * 0.4
		query.target_position = front
		var result := NavigationPathQueryResult3D.new()
		NavigationServer3D.query_path(query, result)
		var path := result.path
		if path.is_empty() or path[path.size() - 1].distance_to(front) > 1.3:
			unreachable.append(String(c.name))
	_check(unreachable.is_empty(), "every loot container can be walked to (unreachable: %s)" % [unreachable])
	# Hills (0.11.17): the ground rolls, the AI can still walk from a spawn to every AI spawn point over it, and
	# spawns and extracts stand on the ground (not floating over a hollow or buried in a hill).
	var blocks := world.raid.get_node("Level/Blocks") as BoxMap
	var heights := blocks.terrain_heights
	var lowest := INF
	var highest := -INF
	for h in heights:
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	_check(highest - lowest > 8.0, "the ground has hills and hollows (%.1f m from lowest to highest)" % (highest - lowest))
	var stranded: Array[String] = []
	for marker: Node3D in spawner.get_children():
		query.target_position = marker.global_position
		var result := NavigationPathQueryResult3D.new()
		NavigationServer3D.query_path(query, result)
		if result.path.is_empty() or result.path[result.path.size() - 1].distance_to(marker.global_position) > 1.5:
			stranded.append(String(marker.name))
	_check(stranded.is_empty(), "every AI spawn point can be walked to over the hills (%s)" % [stranded])
	var space: PhysicsDirectSpaceState3D = (world.raid as Node3D).get_world_3d().direct_space_state
	var off_ground: Array[Vector3] = []
	for spot in spots:
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 3.0,
			spot + Vector3.DOWN * 3.0, 1))
		if hit.is_empty() or absf(hit.position.y - spot.y) > 0.3:
			off_ground.append(spot)
	_check(off_ground.is_empty(), "spawns and extracts stand on the ground (%s)" % [off_ground])
	# Scavs 2.0 zones: the raid starts with each zone's AI in it, they patrol only their zone, roamers anywhere.
	var ai := RaidScope.nodes(world.raid, &"enemies")
	var snipers := ai.filter(func(e: Node) -> bool: return (e as Scav).holds_position)
	var zoned := ai.filter(func(e: Node) -> bool: return (e as Scav).home_radius > 0.0 and not (e as Scav).holds_position)
	_check(ai.size() == start_ai + spawner.snipers + 4 and zoned.size() == start_ai - spawner.roamers + 4 and snipers.size() == 2,
		"the raid starts with %d AI, %d of them in zones, plus 2 snipers and the boss with 3 guards (%d, %d, %d)" % [start_ai, start_ai - spawner.roamers, ai.size(), zoned.size(), snipers.size()])
	var the_boss: Scav = spawner.boss_spawned
	var guards := ai.filter(func(e: Node) -> bool: return (e as Scav).leader == the_boss and the_boss != null)
	_check(the_boss != null and the_boss.net_kind == 3 and guards.size() == 3 and spawner.boss.zone == "TownHall"
		and Vector2(the_boss.global_position.x - the_boss.home_center.x, the_boss.global_position.z - the_boss.home_center.z).length() <= the_boss.home_radius + 3.0,
		"the boss and 3 guards start at the town hall (owner: every raid while testing)")
	# Snipers stand on their perches: high up (a roof or the hunting stand), on something solid.
	var perches := spawner.get_children().filter(func(m: Node) -> bool: return m.get_meta("perch", false))
	var bad_perches: Array[String] = []
	for perch: Marker3D in perches:
		var p := perch.global_position
		var roof: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 1.5, 1))
		if roof.is_empty() or p.y - roof.position.y > 0.6:
			bad_perches.append("%s: nothing under it" % perch.name)
	_check(perches.size() >= 4 and bad_perches.is_empty(), "%d sniper perches, each on a roof or stand (%s)" % [perches.size(), bad_perches])
	var strays := 0
	for e: Scav in zoned:
		if Vector2(e.global_position.x - e.home_center.x, e.global_position.z - e.home_center.z).length() > e.home_radius + 3.0:
			strays += 1
		for i in 4:
			var p := e._pick_patrol_point()
			if Vector2(p.x - e.home_center.x, p.z - e.home_center.z).length() > e.home_radius + 4.0:
				strays += 1
	_check(strays == 0, "zone AI spawn in their zone and pick patrol spots inside it (%d outside)" % strays)
	# The creek (0.11.20): real water in a dug channel (the bed under the surface), the AI can walk into it, and
	# anyone in it is wading (slower, owner).
	var water := blocks.water_points
	var mid := blocks.global_transform * water[water.size() / 2]
	var bed: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(mid + Vector3.UP * 3.0, mid + Vector3.DOWN * 3.0, 1))
	_check(water.size() > 20 and blocks.has_node("Water") and not bed.is_empty() and mid.y - bed.position.y > 0.4,
		"the creek is water over a dug bed (%.2f m deep)" % (mid.y - bed.position.y if not bed.is_empty() else 0.0))
	query.target_position = bed.get("position", mid)
	var to_creek := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, to_creek)
	_check(not to_creek.path.is_empty() and to_creek.path[to_creek.path.size() - 1].distance_to(bed.get("position", mid)) < 1.5,
		"the AI can walk into the creek")
	var wader: Node3D = RaidScope.nodes(world.raid, &"enemies")[0]
	wader.global_position = bed.get("position", mid) + Vector3.UP * 0.1
	for i in 4:
		await physics_frame
	_check(BoxMap.is_wading(wader), "an AI standing in the creek is wading")
	for enemy_node in RaidScope.nodes(world.raid, &"enemies"):
		enemy_node.queue_free()
	world.queue_free()
	await _frames(2)


func _section_hud() -> void:
	# HUD look (0.8.4 "Ammo Can"): its fonts load, a hit knocks health cubes off, a reload shows the tape.
	_check(HudStyle.font() != null and HudStyle.label_font() != null and HudStyle.tape_font() != null, "the HUD fonts load")
	# Pixel-perfect text (0.8.13): sizes 20/30/40/50 use Jersey 10/15/20/25 at exactly 1 screen pixel per font pixel.
	_check(String(HudStyle.FONT_PATHS[HudStyle.design_size(30)]).contains("Jersey15") and String(HudStyle.FONT_PATHS[HudStyle.design_size(50)]).contains("Jersey25")
		and HudStyle.font(30) != HudStyle.font(20) and HudStyle.cap_height(HudStyle.font(40), 40) == 20.0, "each text size uses its own Jersey design")
	var health_widget := HealthHUD.new(player)
	var ammo_widget := AmmoHUD.new(player)
	root.add_child(health_widget)
	root.add_child(ammo_widget)
	await _frames(2)
	player.health.heal(player.health.max_health)
	await _frames(2)
	var old_multiplier := player.health.damage_multiplier
	player.health.damage_multiplier = 1.0
	player.health.take_damage(25)
	player.health.damage_multiplier = old_multiplier
	await _frames(2)
	_check(health_widget._chips.size() == 2, "100 -> 75 HP knocks 2 cubes off the health bar (%d)" % health_widget._chips.size())
	player.health.heal(player.health.max_health)
	gun.is_reloading = true  # (a fake long reload: no ammo or sound needed)
	gun._reload_left = 99.0
	await _frames(10)
	_check(ammo_widget._reload_tape > 0.5, "reloading shows the RELOADING tape")
	gun.is_reloading = false
	health_widget.queue_free()
	ammo_widget.queue_free()
	# Hotbar (0.8.6): the gun in your hands pops up; empty gun slots show a faint ghost of what goes there.
	var bar := HotbarHUD.new(player)
	root.add_child(bar)
	await _frames(20)
	_check(bar.held_slot() == 0 and bar.slot_rect(0).position.y < bar.slot_rect(2).position.y, "the held rifle's slot pops up above the others")
	_check(bar._ghost_icon(1) == HudStyle.PISTOL and bar._ghost_icon(3) == HudStyle.GRENADE and bar._ghost_icon(5).is_empty(), "empty slots ghost a pistol (2) and a grenade (4)")
	bar.queue_free()
	# Damage numbers (0.8.16): a marker the HUD draws in the pixel font (no blurry Label3D), gone after a moment.
	Effects.damage_number(main, player.global_position + Vector3(0, 1, -3), 28, true)
	var numbers := get_nodes_in_group(Effects.WORLD_LABELS).filter(func(n: Node) -> bool: return n.get_meta("label_kind", "") == "damage")
	_check(numbers.size() == 1 and numbers[0].get_meta("label_text") == "28!" and not numbers[0] is Label3D,
		"a damage number is a HUD-drawn marker (28!)")
	await create_timer(Effects.DAMAGE_NUMBER_LIFE + 0.2).timeout
	_check(get_nodes_in_group(Effects.WORLD_LABELS).filter(func(n: Node) -> bool: return n.get_meta("label_kind", "") == "damage").is_empty(),
		"damage numbers disappear on their own")
	# Pause menu (0.8.14): the controls list is re-flowed to fit, with every control still in it.
	var listed := "WASD move · Mouse look · Click shoot · Right-click aim · R reload\nQ/E lean · F search/loot\nFind loot, then extract."
	var flowed := PauseMenuStyle.reflow(listed, HudStyle.font(20), 20, 200.0)
	var kept := true
	for item in ["WASD move", "Right-click aim", "R reload", "Q/E lean", "F search/loot", "Find loot, then extract."]:
		kept = kept and flowed.contains(item)
	_check(kept and flowed.count("\n") >= 3, "the pause menu's controls list re-flows without losing a control")
	# Timer (0.8.7): the timer reads the raid clock. Map (0.10.2): M opens and closes it, it shows the open extracts.
	var hud_node := main.get_node("HUD")
	var old_time := raid.time_left
	raid.time_left = 75.2
	_check(hud_node.timer_hud.text() == "01:16", "the raid timer shows 01:16 (%s)" % hud_node.timer_hud.text())
	raid.time_left = old_time
	var map_hud: MapHUD = hud_node.map_hud
	var press := InputEventAction.new()
	press.action = "map"
	press.pressed = true
	hud_node._input(press)
	_check(map_hud.visible, "M opens the map (loot screen open: %s)" % hud_node.loot_ui.visible)
	_check(map_hud.open_extracts().size() == raid.open_extract_count, "the map shows the open extracts (%d)" % map_hud.open_extracts().size())
	_check(map_hud.get_viewport_rect().encloses(map_hud.map_rect()), "the map fits on screen")
	await _frames(2)
	hud_node._input(press)
	_check(not map_hud.visible, "M closes the map")
	# O (0.11.1, owner): a list of the extracts open for you, only when you press it.
	var extracts: ExtractHUD = hud_node.extract_hud
	_check(not extracts.is_list_showing(), "the extract list is hidden until you press O")
	var press_o := InputEventAction.new()
	press_o.action = "extracts"
	press_o.pressed = true
	hud_node._input(press_o)
	_check(extracts.is_list_showing() and extracts.open_extracts().size() == raid.open_extract_count,
		"O shows the open extracts (%d)" % extracts.open_extracts().size())
	hud_node._input(press_o)
	_check(not extracts.is_list_showing(), "O again hides the list")

func _section_owner_rules() -> void:
	# Damage numbers use the damage actually dealt: an AK body shot on an armored Raider shows 22, not 28.
	var raider := _spawn(RAIDER_SCENE, player.global_position + Vector3(0, 0, 30))
	var dealt: int = (raider.get_node("Health") as Health).take_damage(ItemDB.item("ak")["damage"])
	_check(dealt == 22, "armored Raider takes (and shows) 22 from an AK body shot (%d)" % dealt)
	raider.queue_free()

	# Hotbar (owner, 0.8.1): 1-2 guns, 3 = all your meds (best fit, like H), 4-5 bindable (later: grenades), 6 = knife.
	inv.clear()
	inv.add("bandage", 2)
	inv.add("medkit", 1)
	_check(inv.heal_count() == 3 and not inv.can_bind("bandage") and inv.bind_to_hotbar("medkit") == -1 and not inv.hotbar.has("medkit"),
		"heals don't bind to keys: key 3 holds all of them (3)")
	var old_save := Profile.capture_inventory(inv)
	old_save["hotbar"] = ["bandage", "medkit", "", ""]
	Profile.apply_inventory(inv, old_save)
	_check(inv.hotbar == ["", "", ""], "old saves with heals on the hotbar load with them on key 3 instead")
	var bar := HotbarHUD.new(player)
	root.add_child(bar)
	var meds := bar.slot_info(2)
	var knife := bar.slot_info(4)
	# The meds slot shows what key 3 would use now: at full health a bandage (the closest fit), badly hurt the medkit.
	if not player.controls_locked():
		player.health.heal(100)
		player.health.take_damage(10)
		meds = bar.slot_info(2)
		_check(meds.get("item") == "bandage" and meds["icon"] == HudStyle.BANDAGE and meds["count"] == "x2", "meds slot: a scratch would use a bandage (x2)")
		player.health.take_damage(70)
		_check(bar.slot_info(2).get("item") == "medkit" and bar.slot_info(2)["icon"] == HudStyle.MED, "meds slot: badly hurt, it shows the medkit")
		player.health.heal(100)
	meds["count"] = "x3"
	_check(meds["count"] == "x3" and knife["icon"] == HudStyle.KNIFE and bar.slot_info(3)["state"] == "empty",
		"the hotbar shows meds on key 3, 4 empty, and the knife (V) last (%s %s)" % [meds["count"], knife["state"]])
	inv.take("bandage", 2)
	inv.take("medkit", 1)
	_check(bar.slot_info(2)["state"] == "out", "no heals left: the meds slot is crossed out")
	inv.add("bandage", 2)
	inv.add("medkit", 1)
	bar.queue_free()
	if not player.controls_locked():
		player.health.take_damage(10)
		player.use_hotbar(Inventory.MEDS_KEY)
		_check(player.is_healing() and inv.count_of("bandage") == 1, "key 3 uses the best-fitting heal (a bandage for a scratch)")
		player.heal_time_left = 0.0

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
	# 0.12.14: it hunts around that spot (30 s in the game; shortened here), checking places, then patrols, wary.
	_check(hunter._hunting, "...and hunts for you around there")
	hunter.hunt_time = 5.0
	var start_spot := hunter.global_position
	var roamed := 0.0
	for i in int((hunter.hunt_time + 0.5) * 60):
		await physics_frame
		roamed = maxf(roamed, hunter.global_position.distance_to(start_spot))
	_check(roamed > 2.5, "it walks around checking spots nearby (up to %.1f m away)" % roamed)
	_check(hunter.state == Scav.State.IDLE and hunter._wary_left > 0.0, "after searching a while it goes back to wandering, wary")
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
	gun.noise_radius = 20.0  # (a quiet gun: the AK carries 50 m now, and the test map is small)
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

	# Shot while unaware (from behind): it's startled, turns and shoots back quickly instead of dying before it reacts.
	var victim := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 20)) as Scav
	victim.look_at(victim.global_position + Vector3(0, 0, 10))  # facing away
	victim._wander_time = 99.0
	victim._wander_dir = Vector3.ZERO
	victim.shot_damage = 0
	var shots := [0]
	victim.fired.connect(func(_end: Vector3) -> void: shots[0] += 1)
	await physics_frame
	victim.health.take_damage(10, player.global_position)
	_check(victim.state == Scav.State.ALERT and victim._reaction == victim.startle_reaction_time, "getting shot startles an unaware scav")
	for i in int((victim.startle_reaction_time + victim.aim_time + 0.1) * 60):
		await physics_frame
	_check(shots[0] > 0, "a startled scav shoots back within about half a second")
	victim.queue_free()


func _section_close_range() -> void:
	# Point blank (even standing right on its gun barrel), a scav's shots still hit.
	var scav := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 0.9)) as Scav
	_face_player(scav)
	scav.set_physics_process(false)
	scav._target = player
	scav.point_blank_accuracy = 1.0   # (this checks the bullet's path, not the dice: 90% could roll 3 of 6)
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


func _section_crest() -> void:
	# Over a hill crest (0.11.17 hills): the scav sees the player's head over the ridge but its chest-height line
	# hits the ground. It shoots from its eyes at what it can see instead of into the hill.
	var scav := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 10)) as Scav
	_face_player(scav)
	scav.set_physics_process(false)
	scav._target = player
	scav.accuracy_near = 1.0
	scav.accuracy_far = 1.0
	var ridge := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(4, 1.45, 0.5)
	ridge.add_child(shape)
	main.add_child(ridge)
	ridge.global_position = player.global_position + Vector3(0, 0.725, 5)
	await physics_frame
	await physics_frame
	_check(scav._has_line_of_sight(), "the scav can see the player's head over the ridge")
	var hits := 0
	for i in 4:
		var before := player.health.current
		scav._fire_at_target(10.0)
		if player.health.current < before:
			hits += 1
	_check(hits == 4, "...and its shots go over the crest and hit (%d of 4), not into the ground" % hits)
	# Taller ridge, nothing of the player showing: no clear line, so it holds fire.
	(shape.shape as BoxShape3D).size = Vector3(4, 4, 0.5)
	await physics_frame
	var hp := player.health.current
	scav._fire_at_target(10.0)
	_check(player.health.current == hp, "with no clear line it doesn't fire into the hill")
	ridge.queue_free()
	scav.queue_free()
	player.health.heal(player.health.max_health)
	player.teleport_to(START_SPOT)
	await physics_frame


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
	# (1, or 2 if it came as a duo: 15% of Raiders bring a partner.)
	_check(raiders_at[110] == 0 and raiders_at[125] in [1, 2], "the first Raider arrives around minute 2 (%d)" % raiders_at[125])
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


func _section_zones() -> void:
	# Scavs 2.0: AI zones. Each zone starts with its own scavs and Raiders (who patrol only there), roamers start
	# anywhere, and later arrivals go only to zones with a trickle weight (the hot zones).
	var spawner := EnemySpawner.new()
	spawner.enemy_scene = load(SCAV_SCENE)
	spawner.raider_scene = load(RAIDER_SCENE)
	spawner.set_physics_process(false)
	var hot := {"name": "Hot", "center": player.global_position + Vector3(60, 0, 0), "radius": 15.0, "scavs": 2, "raiders": 1, "trickle": 1.0}
	var quiet := {"name": "Quiet", "center": player.global_position + Vector3(-60, 0, 0), "radius": 15.0, "scavs": 1, "raiders": 0, "trickle": 0.0}
	spawner.zones = [hot, quiet]
	spawner.roamers = 1
	spawner.scav_budget = 8
	spawner.raider_budget = 2
	spawner.max_alive = 20
	spawner.raider_times = PackedFloat32Array([30.0])
	spawner.scav_interval_min = 10.0
	spawner.scav_interval_max = 10.0
	for zone: Dictionary in [hot, quiet, {"name": ""}]:
		for i in 4:
			var marker := Marker3D.new()
			marker.position = zone.get("center", player.global_position + Vector3(0, 0, 70)) + Vector3(i * 3.0, 0, 0)
			if zone.name != "":
				marker.set_meta("zone", zone.name)
			spawner.add_child(marker)
	main.add_child(spawner)
	await _frames(2)
	var in_zone := func(zone: Dictionary) -> Array:
		var found := []
		for e: Scav in get_nodes_in_group("enemies"):
			var gap := Vector2(e.global_position.x - zone.center.x, e.global_position.z - zone.center.z).length()
			if e.home_radius > 0.0 and e.home_center == zone.center and gap < 15.0:
				found.append(e)
		return found
	var roamers := get_nodes_in_group("enemies").filter(func(e: Scav) -> bool: return e.home_radius == 0.0)
	_check(in_zone.call(hot).size() == 3 and in_zone.call(quiet).size() == 1 and roamers.size() == 1,
		"each zone starts with its own AI (hot 3, quiet 1) plus 1 roamer (%d, %d, %d)" % [in_zone.call(hot).size(), in_zone.call(quiet).size(), roamers.size()])
	_check(spawner.raiders_spawned == 1 and in_zone.call(hot).filter(func(e: Scav) -> bool: return e.scene_file_path == RAIDER_SCENE).size() == 1,
		"the hot zone's Raider starts there")
	for second in 60:
		spawner.tick(1.0)
	_check(in_zone.call(hot).size() >= 7 and in_zone.call(quiet).size() == 1 and spawner.raiders_spawned == 2,
		"later arrivals (scavs and the 0:30 Raider) all go to the hot zone (hot %d, quiet %d)" % [in_zone.call(hot).size(), in_zone.call(quiet).size()])
	# 0.12.23 (owner): a zone's AI start inside its buildings about half the time (indoor_chance).
	var indoor := Marker3D.new()
	indoor.position = quiet.center + Vector3(0, 0, 8)
	indoor.set_meta("zone", quiet.name)
	indoor.set_meta("indoor", true)
	spawner.add_child(indoor)
	var landed := func(chance: float) -> bool:
		spawner.indoor_chance = chance
		spawner._spawn(spawner.enemy_scene, quiet, false)
		var newest := get_nodes_in_group("enemies").back() as Scav
		return newest.global_position.distance_to(indoor.global_position) < 3.0
	_check(landed.call(1.0) and not landed.call(0.0), "a zone's AI can start inside a building (or outside)")
	for enemy in get_nodes_in_group("enemies"):
		enemy.remove_from_group("enemies")
		enemy.queue_free()
	spawner.queue_free()
	await _frames(2)


func _section_sniper() -> void:
	# Sniper scavs (Scavs 2.0, owner): stay on their perch, shoot slow heavy single shots from far, sound different
	# from scavs, and show a scope glint when looking your way so you can spot them.
	var sniper := _spawn(SNIPER_SCENE, player.global_position + Vector3(0, 0, 35)) as Scav
	_face_player(sniper)
	sniper.home_center = sniper.global_position
	sniper.home_radius = 3.0
	sniper.shot_damage = 0  # just watching it
	var scav := load(SCAV_SCENE).instantiate() as Scav
	_check(sniper.holds_position and sniper.glint and sniper.shoot_range >= 100.0 and sniper.burst_size == 1
		and sniper.shot_damage == 0 and scav.shot_damage < 35 and sniper.shot_pitch < scav.shot_pitch
		and sniper.shot_volume_db > scav.shot_volume_db and sniper.shot_unit_size > scav.shot_unit_size,
		"snipers: long range single shots, a deeper and louder shot heard from farther away")
	scav.free()
	var eye := player.camera.global_position
	_check(sniper.glint_strength(eye) > 0.0 and sniper.glint_strength(eye) < 0.6, "an unaware sniper looking your way glints faintly")
	sniper._alert(player.global_position)
	var shots := [0]
	sniper.fired.connect(func(_end: Vector3) -> void: shots[0] += 1)
	var start := sniper.global_position
	var farthest := 0.0
	for i in 300:
		await physics_frame
		farthest = maxf(farthest, Vector2(sniper.global_position.x - start.x, sniper.global_position.z - start.z).length())
	_check(shots[0] >= 1 and shots[0] <= 3, "it fires slow single shots (%d in 5 s)" % shots[0])
	_check(farthest <= 3.2, "it stays on its perch while fighting (moved %.1f m)" % farthest)
	_check(sniper.glint_strength(player.camera.global_position) >= 0.9, "aiming at you, its scope glints brightly")
	sniper.rotation.y += PI
	_check(sniper.glint_strength(player.camera.global_position) == 0.0, "facing away: no glint")
	sniper.queue_free()
	player.health.heal(player.health.max_health)
	await physics_frame


func _section_boss() -> void:
	# The boss (Scavs 2.0, owner): a Raider commander, tougher and better armed than a Raider, with Raider guards
	# that follow it round its zone and keep patrolling the zone if it dies.
	var spawner := EnemySpawner.new()
	spawner.enemy_scene = load(SCAV_SCENE)
	spawner.raider_scene = load(RAIDER_SCENE)
	spawner.set_physics_process(false)
	var hall := {"name": "Hall", "center": player.global_position + Vector3(0, 0, 60), "radius": 12.0, "scavs": 0, "raiders": 0, "trickle": 0.0}
	spawner.zones = [hall]
	spawner.boss = {"zone": "Hall", "guards": 3, "chance": 1.0}
	var marker := Marker3D.new()
	marker.position = hall.center
	marker.set_meta("zone", "Hall")
	spawner.add_child(marker)
	# 0.12.18 (owner): it starts inside its building (a boss start spot), then goes out on patrol.
	var inside := Marker3D.new()
	inside.position = hall.center + Vector3(3, 0, 0)
	inside.set_meta("boss_start", true)
	spawner.add_child(inside)
	main.add_child(spawner)
	await _frames(2)
	var the_boss := spawner.boss_spawned
	var guards := get_nodes_in_group("enemies").filter(func(e: Scav) -> bool: return e.leader == the_boss)
	var raider := load(RAIDER_SCENE).instantiate() as Scav
	_check(the_boss != null and guards.size() == 3 and get_nodes_in_group("enemies").size() == 4, "a boss with 3 guards")
	_check(Vector2(the_boss.global_position.x - inside.global_position.x, the_boss.global_position.z - inside.global_position.z).length() < 0.5, "the boss starts at its start spot inside its building")
	_check(the_boss.get_node("Health").max_health > 2 * raider.get_node("Health").max_health and the_boss.shot_damage > raider.shot_damage
		and the_boss.heals > raider.heals and the_boss.weapon_drop_chance == 1.0 and the_boss.max_drops > raider.max_drops,
		"the boss is much tougher than a Raider, hits harder and always carries its rifle and more loot")
	_check(the_boss.body_name == "Bon" and the_boss.extra_drops.has("armor_heavy"), "the boss is Bon and always carries heavy armor (owner)")
	raider.free()
	var offsets := guards.map(func(g: Scav) -> Vector3: return g.follow_offset)
	_check(offsets.size() == 3 and offsets[0] != offsets[1] and offsets[1] != offsets[2], "each guard has its own spot round the boss")
	# 0.12.20 (owner: Bon and his guards stood still): they walk through each other, so the guards can't box him in.
	var apart := true
	for g: Scav in guards:
		for o in guards + [the_boss]:
			if o != g and not g.get_collision_exceptions().has(o):
				apart = false
	_check(apart, "the boss and its guards don't block each other")
	# The boss walks off on patrol; its guards keep up.
	the_boss._wander_point = hall.center + Vector3(8, 0, 0)
	for i in 240:
		await physics_frame
	var near := guards.filter(func(g: Scav) -> bool: return g.global_position.distance_to(the_boss.global_position) < 7.0)
	_check(near.size() == 3, "the guards stay with the boss while it patrols (%d of 3 close)" % near.size())
	the_boss.get_node("Health").take_damage(10000)
	await _frames(2)
	_check(guards.all(func(g: Scav) -> bool: return g.home_radius == 12.0), "without the boss, the guards keep to its zone")
	for enemy in get_nodes_in_group("enemies"):
		enemy.remove_from_group("enemies")
		enemy.queue_free()
	spawner.queue_free()
	await _frames(2)


func _section_teamwork() -> void:
	# Smarter fights (0.12.3, owner: AI were "too dumb"): a scav that starts a fight calls unaware AI nearby over,
	# heads for cover when it spots you from far off, and pushes in while you heal or reload.
	var caller := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 25)) as Scav
	var buddy := _spawn(SCAV_SCENE, player.global_position + Vector3(12, 0, 40)) as Scav
	var far_away := _spawn(SCAV_SCENE, player.global_position + Vector3(-60, 0, 30)) as Scav
	for s: Scav in [caller, buddy, far_away]:
		s.shot_damage = 0
	await physics_frame
	caller._alert(player.global_position)
	_check(buddy.state == Scav.State.INVESTIGATE and buddy._answering_call and far_away.state == Scav.State.IDLE,
		"a scav that starts a fight calls nearby AI over (they jog toward it); AI far off don't hear it")
	far_away.queue_free()
	buddy.queue_free()
	# Spotted from 25 m: it goes for cover first (if there's any) instead of standing in the open.
	_check(caller.shoot_range >= 70.0, "it shoots back from far off (up to %.0f m) before heading for cover" % caller.shoot_range)
	caller.queue_free()
	await physics_frame
	# You heal (or reload): it pushes in on you instead of strafing.
	var pusher := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 18)) as Scav
	_face_player(pusher)
	pusher.shot_damage = 0
	pusher.flank_chance = 0.0
	pusher._cover_cooldown_left = 99.0
	pusher._alert(player.global_position)
	pusher._set_state(Scav.State.ENGAGE)
	for i in 20:
		await physics_frame
	var before := pusher.global_position.distance_to(player.global_position)
	player.heal_time_left = 2.0  # (as if patching up; reloading works the same)
	for i in 60:
		await physics_frame
	player.heal_time_left = 0.0
	var after := pusher.global_position.distance_to(player.global_position)
	_check(before - after > 1.5, "while you heal or reload it pushes in (%.1f m -> %.1f m)" % [before, after])
	pusher.queue_free()
	var bursts := load(SCAV_SCENE).instantiate() as Scav
	var close := {}
	var far := {}
	for i in 200:
		close[bursts._burst_length(5.0)] = true
		far[bursts._burst_length(35.0)] = true
	_check(close.size() >= 2 and far.size() >= 2 and close.keys().max() > far.keys().max() and far.keys().min() == 1,
		"bursts vary: longer up close (%s), short taps far away (%s)" % [close.keys(), far.keys()])
	bursts.free()
	var idle := load(SCAV_SCENE).instantiate() as Scav
	_check(idle.patrol_pause_max <= 3.0 and idle.loot_time_max <= 4.0, "shorter pauses on patrol, so they keep moving")
	idle.free()
	# 0.12.7 (owner: from a hill he shot lots of scavs that never noticed him).
	# A friend shot dead nearby: it turns toward where the shots came from.
	player.teleport_to(Vector3(-30, 0.1, -30))
	var victim := _spawn(SCAV_SCENE, Vector3(10, 0.1, 30)) as Scav
	var friend := _spawn(SCAV_SCENE, Vector3(16, 0.1, 30)) as Scav
	var loner := _spawn(SCAV_SCENE, Vector3(-25, 0.1, 30)) as Scav
	for s: Scav in [victim, friend, loner]:
		s._wander_time = 99.0
		s._wander_dir = Vector3.ZERO
	await physics_frame
	victim.health.take_damage(9999, Vector3(30, 0, 60))
	await physics_frame
	_check(friend.state == Scav.State.ALERT and loner.state == Scav.State.IDLE,
		"a friend dying next to it alerts it toward the shooter; AI far off don't notice")
	friend.queue_free()
	loner.queue_free()
	# Gunshots carry farther and alarm it (it hurries over).
	var listener := _spawn(SCAV_SCENE, Vector3(10, 0.1, 30)) as Scav
	await physics_frame
	listener.hear_noise(listener.global_position + Vector3(30, 0, 0), ItemDB.ITEMS["ak"]["noise"])
	_check(listener.state == Scav.State.INVESTIGATE and listener._alarmed, "it hears an AK from 30 m and hurries toward it")
	_check(listener.sight_range >= 75.0, "it can spot you from 75 m (players on hills)")
	# Patrol stops in the open prefer a spot next to cover.
	listener._set_state(Scav.State.IDLE)
	var covered := 0
	for i in 20:
		var spot := listener._pick_patrol_point()
		if listener._patrol_container != null or listener._has_cover_at(spot):
			covered += 1
	_check(covered >= 16, "patrol stops are next to cover or loot (%d of 20)" % covered)
	listener.queue_free()
	await physics_frame
	# 0.12.8 (owner): accuracy is a gradient, worse the farther you are, very poor at the edge of its range.
	var aim := load(SCAV_SCENE).instantiate() as Scav
	_check(aim.hit_chance(5.0) > aim.hit_chance(25.0) and aim.hit_chance(25.0) > aim.hit_chance(50.0)
		and aim.hit_chance(50.0) > aim.hit_chance(75.0) and aim.hit_chance(75.0) <= 0.11,
		"accuracy drops with range: %.2f at 5 m, %.2f at 25, %.2f at 50, %.2f at 75" % [aim.hit_chance(5.0), aim.hit_chance(25.0), aim.hit_chance(50.0), aim.hit_chance(75.0)])
	aim.free()
	# Pressed against a wall going nowhere: it gives up on that spot instead of hugging the wall.
	var hugger := _spawn(SCAV_SCENE, Vector3(10, 0.1, 30)) as Scav
	await physics_frame
	hugger._cover_phase = Scav.Cover.MOVING
	for i in 60 * 2:
		hugger._check_stuck(1.0 / 60.0, Vector3(3, 0, 0))   # wants to move, doesn't
	_check(hugger._cover_phase == Scav.Cover.NONE, "an AI stuck against a wall gives up on where it was going")
	hugger.queue_free()
	# 0.12.10 (owner: it didn't hide behind the tents): behind low cover it crouches, hitboxes and all.
	var croucher := _spawn(SCAV_SCENE, Vector3(10, 0.1, 30)) as Scav
	await physics_frame
	var head_up := (croucher.get_node("HeadShape") as Node3D).position.y
	croucher._set_state(Scav.State.ENGAGE)
	croucher._cover_low = true
	croucher._cover_phase = Scav.Cover.HOLDING
	croucher._cover_hold_left = 99.0
	croucher._target = player
	for i in 30:
		await physics_frame
	var head_down := (croucher.get_node("HeadShape") as Node3D).position.y
	_check(croucher._crouched and head_down < head_up * 0.7 and croucher.net_capture()[2] & Scav.NET_CROUCH,
		"behind low cover it crouches (head %.2f m -> %.2f m)" % [head_up, head_down])
	croucher.queue_free()
	# 0.12.11 (owner: a friend in town had to fight 8-9 at once): only a few come over; the rest hold, on alert.
	var crowd: Array[Scav] = []
	for i in 7:
		var c := _spawn(SCAV_SCENE, Vector3(-10 + i * 3.0, 0.1, 30)) as Scav
		c._wander_time = 99.0
		c._wander_dir = Vector3.ZERO
		crowd.append(c)
	await physics_frame
	for c in crowd:
		c.hear_noise(Vector3(0, 0, 0), 50.0)
	var coming := crowd.filter(func(c: Scav) -> bool: return c._is_responding())
	var holding := crowd.filter(func(c: Scav) -> bool: return c.state == Scav.State.SEARCH)
	_check(coming.size() == crowd[0].max_responders and holding.size() == crowd.size() - coming.size(),
		"a gunshot brings at most %d over; the other %d go on alert where they are" % [coming.size(), holding.size()])
	for c in crowd:
		c.queue_free()
	await physics_frame
	# 0.12.12 callouts: it says what it's doing (once per few seconds at most).
	var talker := _spawn(SCAV_SCENE, Vector3(10, 0.1, 30)) as Scav
	var said: Array[String] = []
	talker.barked.connect(func(kind: String) -> void: said.append(kind))
	await physics_frame
	talker._bark("spotted")
	talker._bark("hurt")
	_check(said == ["spotted"] and Scav.VOICE.has("man_down") and Scav.VOICE.has("flank"),
		"AI call out what they're doing, at most one callout every %.0f s (%s)" % [talker.bark_cooldown, said])
	talker.queue_free()
	# 0.12.12 (owner): Bon and his guards stick to their area: no running to far gunshots; a chase ends at the leash.
	var homebody := _spawn(SCAV_SCENE, Vector3(10, 0.1, 30)) as Scav
	homebody.stays_home = true
	homebody.home_center = homebody.global_position
	homebody.home_radius = 10.0
	homebody.leash = 20.0
	homebody._wander_time = 99.0
	homebody._wander_dir = Vector3.ZERO
	await physics_frame
	homebody.hear_noise(homebody.global_position + Vector3(0, 0, 40), 60.0)
	var ignored := homebody.state == Scav.State.IDLE
	homebody.global_position = homebody.home_center + Vector3(0, 0, 35)
	homebody._target = player
	homebody._set_state(Scav.State.ENGAGE)
	await physics_frame
	await physics_frame
	_check(ignored and homebody.state == Scav.State.IDLE and homebody._home_return_left > 0.0,
		"a boss ignores gunshots far from its area and gives up a chase past its leash")
	homebody.queue_free()
	# 0.12.13 wounded (owner): badly hurt it limps, shouts for help (calling nearby AI over) and won't push or flank.
	player.teleport_to(Vector3(-30, 0.1, -30))
	var bleeder := _spawn(SCAV_SCENE, Vector3(10, 0.1, 30)) as Scav
	var nearby := _spawn(SCAV_SCENE, Vector3(18, 0.1, 30)) as Scav
	nearby._wander_time = 99.0
	nearby._wander_dir = Vector3.ZERO
	bleeder.heals = 0
	bleeder._heals_left = 0
	var cries: Array[String] = []
	bleeder.barked.connect(func(kind: String) -> void: cries.append(kind))
	await physics_frame
	bleeder._target = player
	bleeder._set_state(Scav.State.ENGAGE)
	bleeder.health.take_damage(70, player.global_position)
	await physics_frame
	_check(bleeder.is_wounded() and "help" in cries and nearby.state == Scav.State.INVESTIGATE
		and bleeder.net_capture()[2] & Scav.NET_WOUNDED,
		"badly hurt it limps and calls for help (%s); a nearby AI comes over" % [cries])
	bleeder.queue_free()
	nearby.queue_free()
	await physics_frame
	# 0.12.17 rivals (owner): scavs never answer a Raider's call.
	var shouter := _spawn(RAIDER_SCENE, Vector3(10, 0.1, 30)) as Scav
	var other_side := _spawn(SCAV_SCENE, Vector3(16, 0.1, 30)) as Scav
	other_side._wander_time = 99.0
	other_side._wander_dir = Vector3.ZERO
	await physics_frame
	shouter._call_for_help(shouter.global_position)
	_check(other_side.state == Scav.State.IDLE, "a scav doesn't answer a Raider's call for help")
	shouter.queue_free()
	other_side.queue_free()
	await physics_frame
	# 0.12.15 suppress and push (owner): you duck out of sight with two on you: one keeps shooting where you were,
	# the other goes around.
	player.teleport_to(Vector3(-30, 0.1, -30))
	var pinner := _spawn(RAIDER_SCENE, Vector3(-30, 0.1, -12)) as Scav
	var mover := _spawn(RAIDER_SCENE, Vector3(-24, 0.1, -12)) as Scav
	var pin_shots := [0]
	pinner.fired.connect(func(_end: Vector3) -> void: pin_shots[0] += 1)
	var flank_wall := _block(Vector3(-21.6, 1.5, -29.6), Vector3(2, 3, 3))   # a flank spot you can't see (0.12.28)
	await physics_frame
	for s: Scav in [pinner, mover]:
		s.shot_damage = 0
		s._target = player
		s._set_state(Scav.State.ENGAGE)
	pinner._last_seen = player.global_position
	pinner._can_see = false
	pinner._lost_sight_time = 0.5
	_check(pinner._try_suppress() and mover._cover_phase == Scav.Cover.FLANKING,
		"you duck out of sight: one Raider suppresses where you were while the other flanks")
	for i in 120:
		pinner._can_see = false
		pinner._sight_check_time = 1.0
		await physics_frame
	_check(pin_shots[0] >= 2, "...firing at your cover while it does (%d shots)" % pin_shots[0])
	pinner.queue_free()
	mover.queue_free()
	flank_wall.queue_free()
	await physics_frame
	# Shot at from too far to shoot back: it doesn't just walk at you in the open.
	player.teleport_to(Vector3(-30, 0.1, -30))
	var far_one := _spawn(SCAV_SCENE, Vector3(25, 0.1, 25)) as Scav
	far_one.shot_damage = 0
	await physics_frame
	far_one._target = player
	far_one._alert(player.global_position)
	var space := far_one.get_world_3d().direct_space_state
	var exposed := 0.0
	for i in 60 * 4:
		await physics_frame
		var in_view := space.intersect_ray(PhysicsRayQueryParameters3D.create(player.eye_position(), far_one.global_position + Vector3(0, 1.2, 0), 1)).is_empty()
		if in_view and Vector2(far_one.velocity.x, far_one.velocity.z).length() > 0.5 and far_one._cover_phase == Scav.Cover.NONE:
			exposed += 1.0 / 60.0
	_check(far_one._peeks_left == 0 and exposed < 1.0,
		"from %.0f m it moves up cover to cover, not walking at you in the open (%.1f s in the open)" % [far_one.global_position.distance_to(player.global_position), exposed])
	far_one.queue_free()
	player.health.heal(player.health.max_health)
	await physics_frame
	player.health.heal(player.health.max_health)
	await physics_frame


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
	scav.flank_chance = 0.0  # (scavs flank sometimes since 0.12.3; this checks cover)
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
		if took_cover and scav._cover_phase == Scav.Cover.PEEKING and scav._can_see:
			came_back = true
			break
	_check(took_cover and hidden_in_cover, "in a break in the fight, a scav moves to cover you can't see")
	_check(came_back, "...then peeks back out to fight")
	scav.queue_free()
	# Two friends side by side don't pick the same cover spot (0.12.29: each gets its own, no bunching).
	var pair: Array[Scav] = []
	for x in [-8.0, -7.0]:
		var s := _spawn(SCAV_SCENE, Vector3(x, 0.1, -8)) as Scav
		_face_player(s)
		s.shot_damage = 0
		s.flank_chance = 0.0
		pair.append(s)
	await physics_frame
	for s in pair:
		s._target = player
		s._set_state(Scav.State.ENGAGE)
		s._try_take_cover()
	_check(pair[0]._cover_phase == Scav.Cover.MOVING and pair[1]._cover_phase == Scav.Cover.MOVING
		and pair[1]._spot_taken(pair[0]._cover_point) and pair[0]._cover_point.distance_to(pair[1]._cover_point) >= 2.0,
		"two scavs side by side head for different cover spots (%.1f m apart)" % pair[0]._cover_point.distance_to(pair[1]._cover_point))
	for s in pair:
		s.queue_free()
	# Fights from cover (0.12.6, owner): even while you keep shooting, between its bursts it gets to cover, then
	# peeks out to shoot from where it could see you, and ducks back in.
	var fighter := _spawn(SCAV_SCENE, Vector3(-8, 0.1, -8)) as Scav
	_face_player(fighter)
	fighter.shot_damage = 0
	fighter.flank_chance = 0.0
	await physics_frame
	fighter._alert(player.global_position)
	fighter._set_state(Scav.State.ENGAGE)
	var phases := {}
	var shots := [0]
	fighter.fired.connect(func(_end: Vector3) -> void:
		if fighter._cover_phase == Scav.Cover.PEEKING:
			shots[0] += 1)
	for i in 60 * 10:
		if i % 30 == 0:
			fighter.notice_threat()  # the player firing every half second
		await physics_frame
		phases[fighter._cover_phase] = true
	_check(phases.has(Scav.Cover.HOLDING) and phases.has(Scav.Cover.PEEKING) and shots[0] > 0,
		"under fire it fights from cover: ducks in, peeks out and shoots from there (%d shots peeking)" % shots[0])
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
	_check(scav.hearing_mult == 1.0 and scav.flank_chance > 0.0 and scav.flank_chance < raider.flank_chance and scav.sneak_range == 0.0
		and scav.give_up_time == 6.0 and scav.heals == 1,
		"scavs keep their behavior (no Raider tricks except flanking, less often: 0.12.3)")
	_check(raider.hearing_mult > 1.0 and raider.flank_chance > 0.0 and raider.sneak_range > 0.0 and raider.give_up_time > scav.give_up_time
		and raider.search_time > scav.search_time and raider.heals > scav.heals and raider.cover_cooldown < scav.cover_cooldown, "Raiders get the harder behavior")
	# Hears a gunshot from farther than a scav would (comes toward fights).
	for s in [scav, raider]:
		s._wander_time = 99.0
		s._wander_dir = Vector3.ZERO
	await physics_frame
	var shot_from := raider.global_position + Vector3(0, 0, -35)
	raider.hear_noise(shot_from, 25.0)
	scav.hear_noise(scav.global_position + Vector3(0, 0, -35), 25.0)
	_check(raider.state == Scav.State.INVESTIGATE and scav.state == Scav.State.IDLE, "a Raider hears a gunshot 35 m away (a scav doesn't)")
	# Sneaks (quiet, slower) when close to where it's going.
	raider._goal = raider.global_position + Vector3(0, 0, -8)
	_check(raider._sneaking(), "a Raider closing in moves quietly")
	# Weapon drops (owner, 0.11.11): Raiders sometimes leave their AK in the body bag; scavs don't drop guns this way.
	_check(raider.weapon_drop == "ak" and raider.weapon_drop_chance > 0.0 and raider.weapon_drop_chance < 1.0, "Raiders have a chance to drop an AK")
	_check(scav.weapon_drop_chance == 0.0, "scavs don't drop their gun")
	raider.weapon_drop_chance = 1.0
	raider.max_drops = 3
	raider.min_drops = 3
	var bags_before := get_nodes_in_group("loot_containers")
	raider.health.take_damage(9999)
	await _frames(3)
	var body: LootContainer = null
	for bag in get_nodes_in_group("loot_containers"):
		if not bag in bags_before:
			body = bag
	_check(body != null and not body.gear.is_empty() and body.gear["primary"].count_of("ak") == 1, "a Raider's AK is in its body's Primary slot")
	if body != null:
		body.queue_free()
	# The bag grows so an AK and a big backpack both fit.
	var packed := LootContainer.spawn_bag(main, Vector3(50, 0, 50), "Test Body", [["ak", 1], ["backpack_medium", 1], ["medkit", 1], ["medkit", 1]])
	_check(packed.grid.stacks.size() == 4, "a body bag fits an AK, a backpack and two medkits (%d of 4)" % packed.grid.stacks.size())
	packed.queue_free()
	scav.queue_free()
	# Flanking: in a lull, a Raider may circle around instead of trading shots, to a spot you can't see (0.12.28).
	player.teleport_to(Vector3(0, 0.1, -10))
	var flanker := _spawn(RAIDER_SCENE, Vector3(0, 0.1, 5)) as Scav
	_face_player(flanker)
	flanker.shot_damage = 0
	await physics_frame
	flanker._alert(player.global_position)
	flanker._set_state(Scav.State.ENGAGE)
	flanker._target = player
	flanker._try_flank(player.global_position - flanker.global_position, 15.0)
	_check(flanker._cover_phase != Scav.Cover.FLANKING, "with nowhere hidden to flank to, it doesn't run across in the open")
	var side_wall := _block(Vector3(6, 1.5, -7), Vector3(2, 3, 2))
	await physics_frame
	flanker._cover_phase = Scav.Cover.NONE
	flanker._try_flank(player.global_position - flanker.global_position, 15.0)
	var start := flanker.global_position
	var to_player := (player.global_position - start).normalized()
	var faced_ahead := 0
	for i in 120:
		await physics_frame
		if flanker._cover_phase == Scav.Cover.FLANKING and flanker.velocity.length() > 1.0:
			faced_ahead += 1 if (-flanker.global_basis.z).dot(flanker.velocity.normalized()) > 0.5 else 0
	var moved := flanker.global_position - start
	var sideways := absf(moved.dot(to_player.cross(Vector3.UP)))
	var hidden := flanker.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(flanker._cover_point + Vector3.UP * 1.5, player.eye_position(), 1))
	_check(sideways > 2.0 and not hidden.is_empty(), "a flanking Raider circles around to your side, somewhere you can't see (%.1f m sideways)" % sideways)
	_check(faced_ahead > 30, "it runs there facing where it's going, not sideways (%d frames)" % faced_ahead)
	flanker.queue_free()
	side_wall.queue_free()
	# Out in the open it fights with short side-steps, not long sideways runs (0.12.28, owner: "just moving sideways").
	var weaver := _spawn(SCAV_SCENE, Vector3(0, 0.1, 8)) as Scav
	_face_player(weaver)
	weaver.shot_damage = 0
	weaver.flank_chance = 0.0
	await physics_frame
	weaver._target = player
	weaver._alert(player.global_position)
	var run := 0
	var longest := 0
	var plan_changes := 0
	var last_plan := weaver.tactic
	for i in 60 * 8:
		await physics_frame
		if weaver.tactic != last_plan:
			plan_changes += 1
			last_plan = weaver.tactic
		var v := Vector3(weaver.velocity.x, 0, weaver.velocity.z)
		var to := Vector3(player.global_position.x - weaver.global_position.x, 0, player.global_position.z - weaver.global_position.z)
		if weaver._cover_phase == Scav.Cover.NONE and v.length() > 1.0 and absf(v.normalized().dot(to.normalized())) < 0.45:
			run += 1
			longest = maxi(longest, run)
		else:
			run = 0
	_check(longest < 50, "in the open it side-steps briefly, it doesn't keep running sideways (longest %.1f s)" % (longest / 60.0))
	# 0.12.29 fight brain (owner: AI felt "cluttered and messy"): one plan at a time, kept until something changes.
	_check(plan_changes <= 6, "it sticks to a plan instead of flip-flopping (%d plan changes in 8 s)" % plan_changes)
	weaver.queue_free()
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


## A solid world-layer box (cover for the AI checks).
func _block(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	body.add_child(shape)
	main.add_child(body)
	body.global_position = pos
	return body
