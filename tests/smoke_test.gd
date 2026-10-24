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
	"shoot", "reload", "ads", "accuracy", "recoil", "ttk", "scav_shoots", "knife", "scav_hit", "senses", "spotting", "close_range", "lost_close", "crest", "melee", "spawn_budget", "zones", "sniper", "boss", "teamwork", "pathing", "ai_vault", "patrol", "ai_lod", "scav_looting", "cover", "lean", "hurt", "raiders", "hud",
	"movement", "stealth", "jump", "vault", "window_vault", "bushes_bars", "fall", "stuck", "ladder", "prone", "containers", "items", "doors", "crate_model", "characters", "grid", "inventory",
	"equipment", "loot_ui", "dropped_gun", "heal", "meds", "downed", "extract", "death", "profile", "hideout", "settings",
	"ghost_stack", "owner_rules", "matchmaking", "net", "pvp", "online_ai", "online_loot", "old_bloxov", "leave_raid", "attachments", "leaves", "new_guns", "ai_loadouts", "mouse", "look",
	"sound",
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
	# it runs faster than real time; the whole test is about 200 game seconds.)
	create_timer(300.0, true).timeout.connect(func() -> void:
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
	# (the player may still be dropping onto the floor at the start: airborne spread would throw the shot off)
	for i in 120:
		if player.is_on_floor():
			break
		await physics_frame
	# (no leftover flinch or bloom: a scav may have shot at you by now)
	gun._flinch_spread = 0.0
	gun._bloom = 0.0
	player.add_kick(0.0, 0.0)
	_aim(dummy.global_position + Vector3(0, 1.0, 0))
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
	_check(raider_probe.armor == "armor_light" and raider_probe.helmet == "helmet_basic"
		and hits_to_kill.call(raider_health.max_health, ak_damage * (1.0 - ItemDB.item(raider_probe.armor)["reduction"])) == 5,
		"Raiders wear light armor and an old helmet: 5 AK body shots")
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
		_check(Quests.raid_kills.has([scene.get_file().get_basename(), "knife"]), "the kill is noted for quests (%s with the knife)" % scene.get_file().get_basename())
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
	# Crouch: slower, lower, nearly silent. Walking makes noise.
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
	_check(noises.max() <= 2.0 if not noises.is_empty() else true, "crouch-walking is nearly silent (heard only right next to you)")
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


## Stuck inside something (0.19.4, owner: a friend vaulted into a dirt bank and couldn't get out): map collision is
## solid from both sides, so the player checks twice a second and is put on the nearest free spot.
func _section_stuck() -> void:
	var spot := START_SPOT + Vector3(6, 0, 6)
	var floor_hit := player.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 20.0, spot + Vector3.DOWN * 20.0, 1, [player.get_rid()]))
	var inside := Vector3(spot.x, floor_hit.position.y + 0.05, spot.z)
	var lump := BoxMap.new()
	lump.colors = PackedColorArray([Color.GRAY])
	lump.boxes = PackedFloat32Array([spot.x, inside.y + 1.0, spot.z, 4, 2, 4, 0, 0, 0, 1])
	main.add_child(lump)
	await physics_frame
	await physics_frame
	_check(BoxMap.inside_solid(player, inside + Vector3.UP * 0.3) and not BoxMap.inside_solid(player, inside + Vector3(5, 0.3, 0)),
		"a spot inside a lump counts as inside it, one beside it doesn't")
	player.teleport_to(inside)
	await create_timer(1.6).timeout
	var at := player.global_position
	_check(not BoxMap.inside_solid(player, at + Vector3.UP * 0.3) and at.distance_to(inside) < 4.0 and at.y > inside.y + 1.9,
		"a player stuck inside it is put on a free spot nearby (on top: %s)" % at)
	lump.queue_free()


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
	_check(jump_height > 0.85 and jump_height < 1.15, "jump height %.2fm (0.18.3: about 1 m)" % jump_height)


## Vaulting (0.13.0): Space while walking into waist-high cover goes over it, chest-high climbs onto it,
## head-high is a plain jump.
func _section_vault() -> void:
	var spot := Vector3(40, 0, -40)
	var cases := [
		# [height, thickness, what should happen]
		[0.9, 0.3, "over"],
		[1.1, 0.15, "over"],   # a fence (0.14.14: its top used to be missed)
		[1.5, 2.0, "onto"],
		[2.4, 0.3, "none"],
	]
	for case: Array in cases:
		var box := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var size := Vector3(3.0, case[0], case[1])
		shape.shape = BoxShape3D.new()
		(shape.shape as BoxShape3D).size = size
		box.add_child(shape)
		main.add_child(box)
		box.global_position = spot + Vector3(0, size.y * 0.5, 1.0 + size.z * 0.5)
		player.teleport_to(spot + Vector3(0, 0.1, 0))
		player.rotation.y = PI  # facing +z, at the box
		await create_timer(0.3).timeout
		var start := player.global_position
		var stamina := player.stamina
		Input.action_press("move_forward")
		Input.action_press("jump")
		await physics_frame
		await physics_frame
		Input.action_release("jump")
		var vaulted := player.is_vaulting()
		_check(not player.hands_free() or not vaulted, "no shooting mid-vault (%.1fm)" % case[0])
		await create_timer(1.0).timeout
		Input.action_release("move_forward")
		var pos := player.global_position
		var far_side := box.global_position.z + size.z * 0.5
		match case[2]:
			"over":
				_check(vaulted and pos.z > far_side and pos.y < 0.3,
					"vaulted over %.1fm cover (z %.2f past %.2f, y %.2f)" % [case[0], pos.z, far_side, pos.y])
				_check(player.stamina < stamina, "vaulting costs stamina")
			"onto":
				_check(vaulted and pos.y > case[0] - 0.1, "climbed onto %.1fm ledge (y %.2f)" % [case[0], pos.y])
			"none":
				_check(not vaulted and pos.z < box.global_position.z, "no vault over %.1fm wall (z %.2f)" % [case[0], pos.z])
		_check(not player.is_vaulting() and player.hands_free(), "vault finished (%.1fm)" % case[0])
		box.queue_free()
		await physics_frame
		_check(start.distance_to(spot) < 0.5, "vault test spot is flat ground (%s)" % start)
	# A stair ramp ahead (34 degrees, 3 m up over 4.4 m, a thin plank like the map's) is walked up, not vaulted
	# (0.14.19: AI halfway up "vaulted" over the rising ramp and dropped through it to the floor below).
	var ramp := StaticBody3D.new()
	var plank := CollisionShape3D.new()
	var plank_mesh := BoxMesh.new()
	plank_mesh.size = Vector3(2.2, 0.2, 5.3)
	plank.shape = plank_mesh.create_trimesh_shape()   # (the map's collision is triangles, hit from both sides)
	(plank.shape as ConcavePolygonShape3D).backface_collision = true
	ramp.add_child(plank)
	main.add_child(ramp)
	ramp.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-34.3)), spot + Vector3(0, 1.4, 3.0))
	var landing := CollisionShape3D.new()   # the floor upstairs, past the top end
	landing.shape = BoxShape3D.new()
	(landing.shape as BoxShape3D).size = Vector3(2.2, 0.2, 3.0)
	landing.transform = ramp.global_transform.affine_inverse() * Transform3D(Basis(), spot + Vector3(0, 2.8, 6.7))
	ramp.add_child(landing)
	await physics_frame
	var on_ramp := []
	for along: float in [1.0, 1.5, 2.0, 2.5, 3.0, 3.5]:
		var at := spot + Vector3(0, 0, along)
		var hit := (main as Node3D).get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.5, at + Vector3.DOWN, 1, [player.get_rid()]))
		player.teleport_to(hit.position + Vector3.UP * 0.02)
		await physics_frame
		var move := Vault.plan(player, Vector3(0, 0, 1), 0.4, 2.05, 1.2, 0.5, Vault.VAULT_HEIGHT)
		if not move.is_empty():
			on_ramp.append("%.1f m in: %s" % [along, move["path"]])
	_check(on_ramp.is_empty(), "no vault up a stair ramp (%s)" % [on_ramp])
	ramp.queue_free()
	await physics_frame


## Fall damage (0.13.3): a jump is free, a drop past 3.5 m hurts, armor or not.
## Windows (0.13.10): a wall with a window (sill 1 m, gap to 2.2 m, as on the map): vault in through it, and back out.
func _section_window_vault() -> void:
	var spot := Vector3(-30, 0, 30)
	var wall := StaticBody3D.new()
	for part: Array in [[Vector3(-2.2, 1.5, 0), Vector3(3.0, 3.0, 0.3)], [Vector3(2.2, 1.5, 0), Vector3(3.0, 3.0, 0.3)],
			[Vector3(0, 0.5, 0), Vector3(1.4, 1.0, 0.3)], [Vector3(0, 2.6, 0), Vector3(1.4, 0.8, 0.3)]]:
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		(shape.shape as BoxShape3D).size = part[1]
		shape.position = part[0]
		wall.add_child(shape)
	main.add_child(wall)
	wall.global_position = spot
	for way: float in [1.0, -1.0]:
		player.teleport_to(spot + Vector3(0.15, 0.1, 1.2 * way))   # a little off centre
		player.rotation.y = 0.0 if way > 0.0 else PI   # facing the window
		await create_timer(0.3).timeout
		Input.action_press("move_forward")
		Input.action_press("jump")
		await physics_frame
		await physics_frame
		Input.action_release("jump")
		var vaulted := player.is_vaulting()
		var lowest_head_room := INF
		for i in 50:
			await physics_frame
			if player.is_vaulting():
				lowest_head_room = minf(lowest_head_room, 2.2 - player.eye_position().y)
		Input.action_release("move_forward")
		var z := player.global_position.z - spot.z
		_check(vaulted and z * way < -0.3 and lowest_head_room > 0.0,
			"vaulted through a window (%s; ended %.2f m past, camera under the top: %s)" % [
			"in" if way > 0.0 else "out", -z * way, lowest_head_room > 0.0])
	# A crate under the window (0.14.22, owner): still vault through, from the crate's side (long way or side
	# on) or onto it from the other side.
	for case: Array in [[1.0, Vector3(1.1, 0.5, 0.6), 1.2], [1.0, Vector3(0.6, 0.5, 1.1), 1.7], [-1.0, Vector3(1.1, 0.5, 0.6), 1.2]]:
		var crate := StaticBody3D.new()
		var box := CollisionShape3D.new()
		box.shape = BoxShape3D.new()
		(box.shape as BoxShape3D).size = case[1]
		box.position = Vector3(0, 0.25, 0.15 + case[1].z * 0.5)
		crate.add_child(box)
		main.add_child(crate)
		crate.global_position = spot
		var way: float = case[0]
		player.teleport_to(spot + Vector3(0.15, 0.1, case[2] * way))
		player.rotation.y = 0.0 if way > 0.0 else PI
		await create_timer(0.3).timeout
		Input.action_press("move_forward")
		Input.action_press("jump")
		await physics_frame
		await physics_frame
		Input.action_release("jump")
		var vaulted := player.is_vaulting()
		for i in 60:
			await physics_frame
		Input.action_release("move_forward")
		var z := player.global_position.z - spot.z
		_check(vaulted and z * way < -0.3, "vaulted through a window with a crate %s it (%s; ended %.2f m past)" % [
			"in front of" if way > 0.0 else "behind", "side on" if case[1].z > 1.0 else "long way", -z * way])
		crate.queue_free()
		await physics_frame
	wall.queue_free()
	await physics_frame


func _section_fall() -> void:
	var spot := Vector3(30, 0.1, -30)
	var hurt := []
	for height: float in [3.0, 6.0, 9.0]:
		player.health.heal(player.health.max_health)
		player.teleport_to(spot + Vector3(0, height, 0))
		var before := player.health.current
		for i in 120:
			await physics_frame
			if player.is_on_floor():
				break
		await physics_frame
		hurt.append(before - player.health.current)
	_check(hurt[0] == 0 and hurt[1] > 15 and hurt[1] < 40 and hurt[2] > hurt[1] + 20,
		"fall damage from 3 / 6 / 9 m: %s" % str(hurt))
	player.health.heal(player.health.max_health)


## Ladders (0.13.5): W up onto a 4 m platform, then back off the edge, caught by the ladder, S down: no fall damage.
func _section_ladder() -> void:
	var spot := Vector3(30, 0, 30)
	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(3, 4, 3)
	block.add_child(shape)
	main.add_child(block)
	block.global_position = spot + Vector3(0, 2, -1.5)   # its +Z face at z = spot.z
	var ladder := (load("res://scenes/ladder.tscn") as PackedScene).instantiate() as Ladder
	ladder.height = 4.0
	main.add_child(ladder)
	ladder.global_position = spot
	player.teleport_to(spot + Vector3(0, 0.1, 1.2))
	player.rotation.y = 0.0   # facing -Z, at the ladder
	await create_timer(0.3).timeout
	Input.action_press("move_forward")
	var climbed := false
	for i in 60 * 4:
		await physics_frame
		climbed = climbed or player.is_climbing()
		if climbed and not player.is_climbing():
			break
	Input.action_release("move_forward")
	await create_timer(0.3).timeout
	var top := player.global_position
	_check(climbed and top.y > 3.9 and top.y < 4.2 and top.z < spot.z and not player.is_climbing(),
		"W climbs the ladder onto the platform (at %s)" % str(top.snapped(Vector3.ONE * 0.1)))
	_check(player.hands_free() or player.is_climbing(), "hands free again off the ladder")
	# Back off the edge over the ladder: it catches you; hold S to climb down.
	var hp := player.health.current
	player.rotation.y = 0.0
	Input.action_press("move_back")
	for i in 60 * 5:
		await physics_frame
	Input.action_release("move_back")
	await create_timer(0.5).timeout
	_check(player.global_position.y < 0.3 and player.health.current == hp,
		"backing off the top, the ladder catches you and S climbs down (y %.2f, hp %d -> %d)" % [
		player.global_position.y, hp, player.health.current])
	ladder.queue_free()
	block.queue_free()
	await physics_frame


## Prone (0.13.6): Z lies you down (low, slow, quiet), Z gets you up, not under a low roof; others' hits use the
## lying-down boxes.
func _section_prone() -> void:
	player.rotation.y = PI
	player.set_prone(true)   # (what Z does; pressed actions don't reach _unhandled_input in the test)
	Input.action_press("move_forward")
	await create_timer(1.2).timeout
	var speed := player.horizontal_speed()
	Input.action_release("move_forward")
	_check(player.is_prone and absf(speed - player.prone_speed) < 0.2, "Z: prone, crawling at ~%.1f m/s (%.2f)" % [player.prone_speed, speed])
	await create_timer(0.3).timeout
	_check(player.eye_height() < 0.6, "prone lowers the camera (%.2f)" % player.eye_height())
	var state := RemotePlayer.capture(player)
	var at: Vector3 = state[0]
	var body := at + Basis(Vector3.UP, state[1]) * Vector3(0, 0.3, -0.7)   # the lying body, ahead of the feet
	_check(state[4] & Hitbox.FLAG_PRONE != 0 and Hitbox.trace(state, at + Vector3(-3, 1.2, 0), at + Vector3(3, 1.2, 0)).is_empty()
		and not Hitbox.trace(state, body + Vector3(-3, 0, 0), body + Vector3(3, 0, 0)).is_empty(),
		"online, a prone player is hit lying down (not at standing height)")
	# Leaning works prone too (0.13.7): the head moves over, and so does its hitbox online.
	Input.action_press("lean_right")
	await create_timer(0.6).timeout
	var leaned := RemotePlayer.capture(player)
	Input.action_release("lean_right")
	_check(player.head.position.x > 0.2 and Hitbox.prone_head_center(leaned[3]).x > 0.2,
		"prone, E leans the head over (%.2f m)" % player.head.position.x)
	# A low roof overhead: can't stand (or crouch) up.
	var roof := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(4, 0.2, 4)
	roof.add_child(shape)
	main.add_child(roof)
	roof.global_position = player.global_position + Vector3(0, 1.0, 0)
	await physics_frame
	player.set_prone(false)
	_check(player.is_prone, "can't get up under a low roof")
	roof.queue_free()
	await physics_frame
	player.set_prone(false)
	_check(not player.is_prone and not player.is_crouching, "Z again stands you up")


func _section_containers() -> void:
	# Loot containers rolled their contents.
	var rolled := 0
	for node in get_nodes_in_group("loot_containers"):
		var container := node as LootContainer
		if container.loot_table != "" and not container.grid.is_empty():
			rolled += 1
	_check(rolled >= 10, "containers have loot (%d)" % rolled)
	_check(ItemDB.money(1234567) == "$1,234,567", "money formatting")


func _section_items() -> void:
	# Items update (0.14.0): every item has a description; armor and keys wear.
	var bare := ItemDB.ITEMS.keys().filter(func(id: String) -> bool: return ItemDB.description(id) == "")
	_check(bare.is_empty(), "every item has a description (missing: %s)" % [bare])
	# Item pictures (0.19.4): every item has one, the item's grid size at ItemIcons.PX per cell
	# (xvfb-run -a godot --rendering-driver opengl3 -s tools/render_icons.gd after adding an item).
	var no_icon := ItemDB.ITEMS.keys().filter(func(id: String) -> bool:
		var icon := ItemIcons.get_icon(id)
		return icon == null or Vector2i(icon.get_size()) != Vector2i(ItemDB.item(id)["w"], ItemDB.item(id)["h"]) * ItemIcons.PX)
	_check(no_icon.is_empty(), "every item has an inventory picture of its grid size (missing or wrong: %s)" % [no_icon])
	# Nothing wears for now (owner, 0.14.3: durability is its own update later).
	var worn := ItemDB.ITEMS.keys().filter(func(id: String) -> bool: return ItemDB.max_durability(id) > 0)
	_check(worn.is_empty(), "no item has durability yet (%s)" % [worn])
	# Armor protects the body, a helmet the head (0.14.2).
	var inv := player.inventory
	var old_armor := inv.unequip("armor") if inv.equipped("armor") != null else null
	var old_helmet := inv.unequip("helmet") if inv.equipped("helmet") != null else null
	var vest := ItemStack.new("armor_light")
	var helm := ItemStack.new("helmet_basic")
	inv.equip("armor", vest)
	inv.equip("helmet", helm)
	var hp := player.health.current
	player.health.take_damage(30)
	player.health.take_damage(30)
	_check(player.health.current == hp - 48 and is_equal_approx(player.health.damage_multiplier, 0.8),
		"light armor takes 20%% off body hits, and doesn't wear (%d HP lost)" % (hp - player.health.current))
	hp = player.health.current
	player.health.take_damage(40, Vector3.ZERO, false, true)
	_check(player.health.current == hp - 30 and is_equal_approx(player.health.head_multiplier, 0.75),
		"the old helmet takes 25% off head hits")
	inv.unequip("helmet")
	_check(player.health.head_multiplier == 1.0 and Scav.HEAD_HIT_CHANCE > 0.0, "no helmet: head hits get through (AI land some hits on the head)")
	inv.unequip("armor")
	if old_helmet != null:
		inv.equip("helmet", old_helmet)
	if old_armor != null:
		inv.equip("armor", old_armor)
	player.health.current = player.health.max_health
	# AI wear their gear: it protects them like a player, and ends up on their body.
	var gear_raider := _spawn(RAIDER_SCENE, player.global_position + Vector3(30, 0, 30)) as Scav
	await physics_frame
	_check(is_equal_approx(gear_raider.health.damage_multiplier, 0.8) and is_equal_approx(gear_raider.health.head_multiplier, 0.75),
		"a Raider's light armor and old helmet protect it")
	var raider_name := gear_raider.body_name
	gear_raider.health.take_damage(1000)
	await physics_frame
	await physics_frame
	var raider_body: LootContainer = null
	for bag in get_nodes_in_group("loot_containers"):
		if bag.display_name == raider_name:
			raider_body = bag
	_check(raider_body != null and raider_body.gear["armor"].count_of("armor_light") == 1 and raider_body.gear["helmet"].count_of("helmet_basic") == 1,
		"its body has the armor and helmet it wore")
	if raider_body != null:
		raider_body.queue_free()
	# Grenades (0.14.5): picked up onto key 4; the blast hurts what it can see, most up close; walls stop it.
	inv.unbind(inv.hotbar[1]) if inv.hotbar[1] != "" else null
	inv.add("grenade", 2)
	_check(inv.hotbar[1] == "grenade", "a grenade goes on key 4 by itself")
	var probe := Grenade.new()
	_check(probe.damage == 80 and probe.damage_at(0.0) == 80 and probe.damage_at(3.5) == 40 and probe.damage_at(7.5) == 0,
		"blast damage (0.14.18): 80 on a direct hit, half at 3.5 m, none past 7 m")
	probe.free()
	var near_scav := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 25)) as Scav
	var far_scav := _spawn(SCAV_SCENE, player.global_position + Vector3(14, 0, 25)) as Scav
	await physics_frame
	var blast := Grenade.spawn(main, near_scav.global_position + Vector3(2, 0.2, 0), Vector3.ZERO)
	blast.fuse = 0.05
	await create_timer(0.2).timeout
	_check(not is_instance_valid(blast) and (not is_instance_valid(near_scav) or near_scav.health.current < near_scav.health.max_health)
		and far_scav.health.current == far_scav.health.max_health, "a grenade 2 m from a scav kills or hurts it, one 14 m off isn't touched")
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	wall_shape.shape = BoxShape3D.new()
	(wall_shape.shape as BoxShape3D).size = Vector3(4, 3, 0.3)
	wall.add_child(wall_shape)
	main.add_child(wall)
	wall.global_position = far_scav.global_position + Vector3(0, 1.5, -1.0)
	await physics_frame
	var hp_before := far_scav.health.current
	blast = Grenade.spawn(main, far_scav.global_position + Vector3(0, 0.2, -2.0), Vector3.ZERO)
	blast.fuse = 0.05
	await create_timer(0.2).timeout
	_check(far_scav.health.current == hp_before, "a wall between it and the blast keeps it safe")
	wall.queue_free()
	for s2 in [near_scav, far_scav]:
		if is_instance_valid(s2):
			s2.queue_free()
	# From the hotbar (0.14.17): key 4 pulls it out (gun lowered), a click throws it, and it flies off where you look.
	var count_before := inv.count_of("grenade")
	player.use_hotbar(1)
	_check(player.is_throwing() and player.hand.is_up() and inv.count_of("grenade") == count_before, "key 4 pulls a grenade out")
	player.use_hotbar(1)
	await create_timer(0.1).timeout
	_check(not player.is_throwing() and inv.count_of("grenade") == count_before, "key 4 again puts it away")
	await create_timer(0.6).timeout
	player.use_hotbar(1)
	await create_timer(player.NADE_PULL_TIME + 0.1).timeout
	player.throw_held_grenade()
	await create_timer(player.NADE_WINDUP_TIME + 0.05).timeout
	var flying: Array = main.get_children().filter(func(n: Node) -> bool: return n is Grenade)
	_check(inv.count_of("grenade") == count_before - 1 and flying.size() == 1 and (flying[0] as Grenade).velocity.length() > 10.0,
		"a click throws it (%d left)" % inv.count_of("grenade"))
	_check(player.is_throwing() and not player.gun.is_ready_to_fire(), "you can't shoot while throwing")
	player.interactor.blocked = true
	Input.action_press("aim")
	_check(not player.gun.wants_aim(), "right-click with the inventory open doesn't aim")
	Input.action_release("aim")
	player.interactor.blocked = false
	for g in flying:
		g.queue_free()
	inv.take("grenade", 10)
	# Energy drink: fills stamina, then a boost.
	inv.add("energy_drink")
	player.stamina = 10.0
	var drink := inv.find("energy_drink")
	player.use_item(drink[0], drink[1])
	_check(player.is_drinking(), "drinking an energy drink takes a moment")
	await create_timer(ItemDB.item("energy_drink")["use_time"] + 0.2).timeout
	var full := player.stamina
	player._use_stamina(30.0)
	_check(full >= player.max_stamina - 1.0 and player.stamina == full and player.drink_boost_left > 8.0 and inv.count_of("energy_drink") == 0,
		"it fills your stamina, and sprinting costs none for 10 s")
	player.drink_boost_left = 0.0
	# Cancel (0.14.17, owner): the same key again, only after 1 s, and you get the item back.
	inv.add("energy_drink")
	drink = inv.find("energy_drink")
	player.use_item(drink[0], drink[1])
	player.cancel_heal()
	var early := player.is_drinking() and not player.can_cancel_heal()
	await create_timer(player.HEAL_CANCEL_AFTER + 0.1).timeout
	var right_click := InputEventAction.new()
	right_click.action = &"aim"
	right_click.pressed = true
	player._unhandled_input(right_click)
	var cancelled := not player.is_drinking()
	_check(early and cancelled and inv.count_of("energy_drink") == 1,
		"a drink can't be cancelled in its first second, then right-click cancels it, and you keep it")
	inv.take("energy_drink", 1)
	# Dog tags.
	var tag_raider := (load(RAIDER_SCENE) as PackedScene).instantiate() as Scav
	var tag_boss := (load("res://scenes/boss.tscn") as PackedScene).instantiate() as Scav
	_check(tag_raider.extra_drops.has("dog_tag") and tag_boss.extra_drops.has("bon_tag"), "Raiders carry dog tags, Bon his own")
	# Playtest fixes (0.14.14, owner): dog tags only come off bodies, the vault key from Raiders (10%) and crates (2%),
	# medkits are 2x1 and stack to 3.
	_check(not ItemDB.LOOT_TABLES.values().any(func(t: Dictionary) -> bool: return t.has("bank_vault_key"))
		and ItemDB.TABLE_CHANCES["raider"]["bank_vault_key"] == 0.02 and ItemDB.TABLE_CHANCES["locker"]["bank_vault_key"] == 0.02
		and not ItemDB.TABLE_CHANCES.has("crate") and ItemDB.max_stack("scrap") == 3
		and not ItemDB.PLACE_LOOT.values().any(func(t: Dictionary) -> bool: return t.has("bunker_key"))
		and ItemDB.item("dog_tag").get("special", false) and ItemDB.size("medkit") == Vector2i(2, 1) and ItemDB.item("medkit")["stack"] == 3,
		"tags only off bodies, the bank key from Raiders and lockers (2%), the bunker key only off Bon, medkits 2x1 stacking to 3, scrap to 3")
	# Sell items (0.14.8, owner's picks): valuables, found by place, and Bon carries the Exion Medal.
	var sellables := ["fuel_can", "med_supplies", "novarra_badge", "hard_drive", "exion_medal", "gpu", "diamond_ring", "bolts", "wires", "gunpowder", "cpu"]
	_check(sellables.all(func(id: String) -> bool: return ItemDB.kind(id) == "valuable" and ItemDB.description(id) != "")
		and tag_boss.extra_drops.has("exion_medal") and ItemDB.PLACE_LOOT["GasStation"].has("fuel_can")
		and ItemDB.PLACE_LOOT["Bank"].has("diamond_ring"), "the new sell items exist and are found by place")
	# 0.15.16 (owner): bolts stack to 10; a place's loot is most of what it has (a pharmacy crate is mostly meds).
	var heals := [0, 0]
	for i in 400:
		for j in 2:
			var rolled := ItemDB.roll("crate", "Pharmacy" if j == 0 else "")
			if ItemDB.kind(rolled) == "heal":
				heals[j] += 1
	_check(ItemDB.max_stack("bolts") == 10 and heals[0] > 160 and heals[0] > heals[1] * 2,
		"bolts stack to 10, pharmacy crates are mostly meds (%d vs %d of 400)" % heals)
	# The Holy Grail (0.14.12, owner): never from random rolls, only its one-off finds, in containers the map has.
	var map_text := FileAccess.get_file_as_string("res://scenes/maps/old_bloxov.tscn")
	var grail_rolled := false
	for i in 300:
		grail_rolled = grail_rolled or ItemDB._random_valuable("legendary") == "holy_grail"
	var grails := 0
	for i in 1500:
		var grail_box := LootContainer.new()
		grail_box.name = "Bunker_Safe1"
		root.add_child(grail_box)
		grails += grail_box.grid.count_of("holy_grail")
		grail_box.free()
	_check(not grail_rolled and grails >= 3 and grails < 40 and ItemDB.value("holy_grail") > ItemDB.value("golden_toilet")
		and ItemDB.SPECIAL_FINDS.keys().all(func(n: String) -> bool: return n.begins_with("Bank_Safe") or n.begins_with("Bunker_Safe"))
		and ItemDB.item("golden_toilet").get("special", false) and ItemDB.TABLE_CHANCES["safe"]["golden_toilet"] == 0.03
		and ItemDB.TABLE_CHANCES["scav"]["backpack_small"] == 0.07
		and ItemDB.SPECIAL_FINDS["Bank_Safe1"]["holy_grail"] == 0.03 and ItemDB.SPECIAL_FINDS["Bank_Safe2"]["golden_toilet"] == 0.03
		and ItemDB.SPECIAL_FINDS.keys().all(func(n: String) -> bool: return map_text.contains('name="%s"' % n)),
		"the Holy Grail: 1%% in bank vault and bunker safes (%d in 1500); golden toilet 3%% of safes; scav backpacks 7%%" % grails)
	tag_raider.free()
	tag_boss.free()
	# 0.15.21 (owner: a vault safe came up empty): a safe always has something, even when it rolls a large backpack.
	var empty_safes := 0
	var safe_scene := load("res://scenes/loot_safe.tscn") as PackedScene
	for i in 300:
		var safe_box := safe_scene.instantiate() as LootContainer
		safe_box.set_meta("place", "Bank")
		root.add_child(safe_box)
		if safe_box.grid.stacks.is_empty():
			empty_safes += 1
		safe_box.free()
	var large_safe := safe_scene.instantiate() as LootContainer
	root.add_child(large_safe)
	var large_fits := large_safe.grid.width >= 4 and large_safe.grid.height >= 4
	large_safe.free()
	_check(empty_safes == 0 and large_fits, "vault safes are never empty (%d of 300), and a large backpack (4x4) fits in a safe" % empty_safes)
	# Loot by place: a gun store locker is mostly guns, ammo and attachments, a pharmacy crate mostly meds.
	var guns := 0
	var meds := 0
	for i in 400:
		if ItemDB.kind(ItemDB.roll("locker", "GunStore")) in ["weapon", "ammo", "attachment"]:
			guns += 1
		if ItemDB.roll("crate", "Pharmacy") in ["bandage", "medkit", "med_supplies"]:
			meds += 1
	_check(guns > 160 and meds > 160, "loot by place: gun store lockers %d/400 guns or ammo, pharmacy crates %d/400 meds" % [guns, meds])
	var tagged: LootContainer = (load("res://scenes/loot_crate.tscn") as PackedScene).instantiate()
	tagged.set_meta("place", "Pharmacy")
	tagged.min_items = 30
	tagged.max_items = 30
	tagged.grid_size = Vector2i(12, 12)
	main.add_child(tagged)
	var tagged_meds := tagged.grid.count_of("bandage") + tagged.grid.count_of("medkit")
	_check(tagged_meds >= 8, "a crate tagged Pharmacy rolls from the pharmacy's loot (%d meds in 30 rolls)" % tagged_meds)
	tagged.queue_free()
	# Key doors: shut, a wall; with the key on you, F unlocks it and uses the key up.
	var door: KeyDoor = (load("res://scenes/key_door.tscn") as PackedScene).instantiate()
	door.name = "BankVaultDoor"
	door.key = "bank_vault_key"
	main.add_child(door)
	door.global_position = player.global_position + Vector3(0, 0, -1.6)
	await physics_frame
	await physics_frame
	var space := player.get_world_3d().direct_space_state
	var through := PhysicsRayQueryParameters3D.create(door.global_position + Vector3(0, 1, 1), door.global_position + Vector3(0, 1, -1), 1)
	_check(space.intersect_ray(through).get("collider") == door and door.is_in_group(&"nav_source"), "a shut key door is a wall (and the AI's paths go round it)")
	_check(door.prompt(inv) == "Locked: needs Bank Vault Key" and not door.unlock(inv) and not door.is_open, "no key: it stays locked")
	inv.add("bank_vault_key")
	var key := inv.key_for("BankVaultDoor")
	_check(key != null and door.prompt(inv) == "Unlock with Bank Vault Key", "with the key on you: [F] Unlock")
	_check(door.unlock(inv) and door.is_open and inv.key_for("BankVaultDoor") == key, "unlocking opens it; the key is kept (no uses for now)")
	await physics_frame
	await physics_frame
	_check(space.intersect_ray(through).is_empty(), "the open door lets you through")
	inv.take("bank_vault_key", 1)
	door.queue_free()
	var boss := (load("res://scenes/boss.tscn") as PackedScene).instantiate()
	_check(boss.extra_drops.has("bunker_key"), "Bon always carries the bunker key")
	boss.free()


func _section_doors() -> void:
	# Doors (0.17): shut, they stop people and the AI's eyes but not bullets; F swings one away from you; the AI
	# open a shut door when they walk up to it.
	var spot := Vector3(40, 0, 60)
	var door: Door = (load("res://scenes/door.tscn") as PackedScene).instantiate()
	door.name = "TestDoor"
	main.add_child(door)
	door.global_position = spot
	await physics_frame
	await physics_frame
	# 0.18.12 (fewer draw calls): no shadow, and it stops drawing far out (sooner with a roof over both sides).
	var leaves := door.find_children("*", "GeometryInstance3D", true, false)
	_check(not leaves.is_empty() and leaves.all(func(node: GeometryInstance3D) -> bool:
		return node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and node.visibility_range_end == Door.HIDE_BEYOND)
		and not PixelModel.roofed(door, spot + Vector3(0, 0, 1)),
		"a door casts no shadow and stops drawing past %d m (out here, no roof)" % Door.HIDE_BEYOND)
	var space := door.get_world_3d().direct_space_state
	var mid := spot + Vector3(-0.5, 1.2, 0)
	var walk := PhysicsRayQueryParameters3D.create(mid + Vector3(0, 0, 1), mid + Vector3(0, 0, -1), Door.LAYER)
	var shot := PhysicsRayQueryParameters3D.create(mid + Vector3(0, 0, 1), mid + Vector3(0, 0, -1), 1 | 4)
	_check(space.intersect_ray(walk).get("collider") == door and space.intersect_ray(shot).is_empty(),
		"a shut door blocks people (layer %d) but not bullets" % Door.LAYER)
	_check(player.collision_mask & Door.LAYER != 0 and not door.is_in_group(&"nav_source"),
		"players bump into doors; the AI's paths go through doorways")
	_check(door.prompt() == "Open door" and not door.is_open(), "shut: [F] Open door")
	door.use(spot + Vector3(0, 1, 2))
	_check(door.state == 1 and door.prompt() == "Close door", "F opens it, away from you")
	for i in 30:
		await physics_frame
	_check(space.intersect_ray(walk).is_empty(), "the open door lets you through")
	var leaf: Node3D = door.get_child(0)
	_check(door.to_local(leaf.to_global(Vector3(0.5, 0, 0))).z < -0.3, "it swung to the far side")
	door.use(spot + Vector3(0, 1, 2))
	_check(door.state == 0, "F again shuts it")
	for i in 30:
		await physics_frame
	var scav := _spawn(SCAV_SCENE, spot + Vector3(0, 0.1, -1.0)) as Scav
	for i in 10:
		await physics_frame
	_check(door.state == -1, "a scav walking up to a shut door opens it (away from them)")
	scav.queue_free()
	door.queue_free()
	# Wrecked doors (World art round 3): only a picture, nothing to bump into or press F on.
	var wreck: Door = (load("res://scenes/door.tscn") as PackedScene).instantiate()
	wreck.broken = "hanging"
	main.add_child(wreck)
	wreck.global_position = spot + Vector3(6, 0, 0)
	await physics_frame
	await physics_frame
	var through := PhysicsRayQueryParameters3D.create(mid + Vector3(6, 0, 1), mid + Vector3(6, 0, -1), 0xFFFF)
	_check(wreck.collision_layer == 0 and not wreck.is_in_group(Door.GROUP) and space.intersect_ray(through).is_empty(),
		"a wrecked door blocks nothing and can't be opened")
	wreck.queue_free()


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
		# 0.18.12 (fewer draw calls): the parts showing merge into a mesh per moving part; picking again re-merges.
		var showing_parts := func() -> Array:
			return model.find_children("*", "MeshInstance3D", true, false).filter(
				func(node: Node) -> bool: return (node as MeshInstance3D).is_visible_in_tree())
		var parts_before: int = showing_parts.call().size()
		var tris := func() -> int:
			var total := 0
			for node: MeshInstance3D in showing_parts.call():
				total += node.mesh.surface_get_array_index_len(0) if node.mesh.surface_get_array_index_len(0) > 0 \
					else node.mesh.surface_get_array_len(0)
			return total
		var tris_before: int = tris.call()
		model.merge_parts()
		var parts_merged: int = showing_parts.call().size()
		var tris_merged: int = tris.call()
		model.pick_outfit(model.outfit.duplicate())
		await process_frame
		var still_merged: int = showing_parts.call().size()
		model.unmerge_parts()
		await process_frame
		_check(parts_merged <= parts_before / 2 and tris_merged == tris_before and still_merged <= parts_before / 2
			and showing_parts.call().size() == parts_before and model.get_node("Gun").visible,
			"%s: its %d parts showing draw as %d meshes (same %d triangles), still after picking it again, and come apart again %s"
			% [character.name, parts_before, parts_merged, tris_before, [tris_merged, still_merged,
			showing_parts.call().size(), model.get_node("Gun").visible]])
		var muzzle_local := character.to_local(character.muzzle.global_position)
		_check(muzzle_local.z < -0.6 and absf(muzzle_local.y - 1.26) < 0.1,
			"%s faces forward, gun at shoulder height (muzzle at %s)" % [character.name, muzzle_local])
		_check(character.muzzle_flash.get_parent() == character.muzzle, "%s muzzle flash sits on the gun" % character.name)
		if path == SCAV_SCENE:
			# (0.17.5, owner) Every scav wears the small backpack, on its back.
			var pack := model.get_node_or_null("Backpack") as Node3D
			_check(pack != null and pack.visible and pack.position.z > 0.2 and pack.find_children("*", "MeshInstance3D").size() > 0,
				"scavs wear the small backpack on their back")
		var bags_before := get_nodes_in_group("loot_containers").size()
		character.health.take_damage(9999)
		await _frames(3)
		_check(not is_instance_valid(character), "%s dies" % path.get_file())
		_check(get_nodes_in_group("loot_containers").size() > bags_before, "%s drops a body bag" % path.get_file())
		if path == SCAV_SCENE:
			# 0.17.12 (owner): its body is the same body (loadout slots), shown as its backpack with a flap that opens.
			var dropped: LootContainer = null
			for node in get_nodes_in_group("loot_containers"):
				if (node as LootContainer).display_name == "Scav Body":
					dropped = node
			_check(dropped != null and dropped.gear.has("primary") and dropped.find_child("Lid", true, false) != null
				and dropped.find_child("Model", true, false) != null, "a dead scav's body (loadout slots and all) is its backpack on the ground")
			if dropped != null:
				loot_ui.open_for(dropped)
				await _frames(30)
				var lid := dropped.find_child("Lid", true, false) as Node3D
				var opened := lid.rotation.x
				loot_ui.close()
				await _frames(30)
				_check(opened > 1.5 and is_zero_approx(lid.rotation.x),
					"opening it swings the lid open, closing shuts it (%.2f rad open)" % opened)
				dropped.queue_free()


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
	# INVENTORY / QUESTS tabs in a raid (0.17.13, owner): the inventory key shows your quests too.
	loot_ui.open_for(null)
	_check(loot_ui._tabs.visible and loot_ui._columns.visible and not loot_ui.quests_shown(), "the inventory opens on its INVENTORY tab")
	loot_ui._quests_tab.pressed.emit()
	_check(loot_ui.quests_shown() and not loot_ui._columns.visible and loot_ui._quest_page._list.get_child_count() > 1,
		"the QUESTS tab lists your quests")
	loot_ui.close()
	loot_ui.open_for(null)
	_check(not loot_ui.quests_shown(), "it opens on the inventory again")
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
	# Drop one item onto another (0.14.16, owner): they swap places.
	var swap_grid := GridInventory.new("Swap", 4, 1)
	var duct := ItemStack.new("duct_tape", 1, 0, 0)
	var band := ItemStack.new("bandage", 2, 2, 0)
	swap_grid.place(duct)
	swap_grid.place(band)
	_check(loot_ui.move_stack(band, swap_grid, swap_grid, Vector2i(0, 0), false, Vector2i(0, 0))
		and band.x == 0 and duct.x == 2 and swap_grid.stacks.size() == 2, "dropping an item on another swaps them")
	var big := ItemStack.new("battery", 1, 0, 0)
	var swap_grid2 := GridInventory.new("Swap2", 3, 2)
	var tape2 := ItemStack.new("duct_tape", 1, 2, 0)
	swap_grid2.place(big)
	swap_grid2.place(tape2)
	_check(loot_ui.move_stack(tape2, swap_grid2, swap_grid2, Vector2i(0, 0), false, Vector2i(0, 0))
		and tape2.x == 0 and big.x == 1 and swap_grid2.stacks.size() == 2, "a big item that can't take the small one's spot moves to free space")
	# 0.15.21 (owner): every item swaps the same way, a grenade onto a medkit included, and a medkit over two
	# bandages moves both out of the way.
	var swap_grid3 := GridInventory.new("Swap3", 3, 1)
	var nade := ItemStack.new("grenade", 1, 0, 0)
	var kit := ItemStack.new("medkit", 1, 1, 0)
	swap_grid3.place(nade)
	swap_grid3.place(kit)
	var nade_ok := loot_ui.move_stack(nade, swap_grid3, swap_grid3, Vector2i(1, 0), false, Vector2i(1, 0))
	var swap_grid4 := GridInventory.new("Swap4", 3, 1)
	var kit2 := ItemStack.new("medkit", 1, 1, 0)
	swap_grid4.place(ItemStack.new("grenade", 1, 0, 0))
	swap_grid4.place(kit2)
	var pockets_test := GridInventory.new("Pockets", 2, 1)
	var band_a := ItemStack.new("bandage", 5, 0, 0)
	var band_b := ItemStack.new("bandage", 5, 1, 0)
	pockets_test.place(band_a)
	pockets_test.place(band_b)
	var over_two := loot_ui.move_stack(kit2, swap_grid4, pockets_test, Vector2i(0, 0), false, Vector2i(0, 0))
	_check(nade_ok and nade.x == 2 and kit.x == 0 and swap_grid3.stacks.size() == 2
		and over_two and pockets_test.stacks == [kit2] and swap_grid4.count_of("bandage") == 10,
		"a grenade swaps onto a medkit, and a medkit dropped on two bandages moves both out of the way (%s %d %d, %s %d %d)" % [nade_ok, nade.x, kit.x, over_two, pockets_test.stacks.size(), swap_grid4.count_of("bandage")])
	var full_grid := GridInventory.new("Full", 2, 1)
	var tiny := GridInventory.new("Tiny", 1, 1)
	var nade2 := ItemStack.new("grenade", 1, 0, 0)
	tiny.place(nade2)
	full_grid.place(ItemStack.new("medkit", 1, 0, 0))
	_check(not loot_ui.move_stack(nade2, tiny, full_grid, Vector2i(0, 0), false, Vector2i(0, 0))
		and tiny.stacks == [nade2] and full_grid.count_of("medkit") == 1, "a swap with no room anywhere leaves both where they were")
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
	_check(slot_views.size() == 5, "the loot screen shows a body's 5 gear slots (%d)" % slot_views.size())
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


func _section_attachments() -> void:
	# Attachments (0.15.1): slots on the gun, stats added, on and off from the inventory screen, kept in saves.
	var ak := ItemStack.new("ak")
	ak.attachments = {"mag": "ext_mag", "grip": "foregrip"}
	var stats := ItemDB.weapon_stats(ak)
	_check(int(stats["mag"]) == 45 and is_equal_approx(float(stats["recoil"]), 1.2 * 0.8), "extended mag + foregrip: 45 rounds, 20%% less kick")
	var wasp := ItemStack.new("smg")
	var wasp_plain := int(ItemDB.weapon_stats(wasp)["mag"])
	wasp.attachments = {"mag": "ext_mag"}
	_check(wasp_plain == 25 and int(ItemDB.weapon_stats(wasp)["mag"]) == 35, "the Wasp holds 25, 35 with an extended mag (0.15.27)")
	_check(ItemDB.attachment_slot_for("pistol", "red_dot") == "sight" and ItemDB.attachment_slot_for("ak", "red_dot") == "scope"
		and ItemDB.attachment_slot_for("pistol", "foregrip") == "" and ItemDB.attachment_slot_for("ak", "scope_8x") == "",
		"attachments only go on the guns they fit")
	_check(ak.value() == ItemDB.value("ak") + ItemDB.value("ext_mag") + ItemDB.value("foregrip"), "a gun is worth more with its attachments")
	# Saves and network data keep them, and drop anything that isn't a real attachment for that gun.
	var copy := GridInventory.data_stack(GridInventory.stack_data(ak))
	_check(copy.attachments == ak.attachments, "attachments survive the network format")
	_check(Profile._read_stack(Profile._write_stack(ak)).attachments == ak.attachments, "attachments survive a save")
	var junk := GridInventory.data_stack(["ak", 1, 0, 0, false, 0, 0, {"scope": "medkit", "barrel": "choke", "mag": "ext_mag"}])
	_check(junk.attachments == {"mag": "ext_mag"}, "bad attachment data is ignored (%s)" % junk.attachments)
	# On the gun in your hands, from the pockets.
	var rifle := inv.equipped("primary")
	_check(rifle != null and rifle.id == "ak" and gun.weapon == rifle, "holding the AK")
	var old_mag := gun.mag_size
	var old_ads := gun.ads_time
	var part := ItemStack.new("ext_mag")
	var grid := GridInventory.new("Parts", 4, 2)
	grid.place(part)
	loot_ui.attach_from_grid(grid, part, rifle, null)
	_check(rifle.attachments.get("mag") == "ext_mag" and grid.stacks.is_empty(), "attach an extended mag from a grid")
	_check(gun.mag_size == roundi(old_mag * 1.5), "the gun in your hands takes the bigger mag (%d)" % gun.mag_size)
	var dot := ItemStack.new("red_dot", 1, 0, 0)
	grid.place(dot)
	loot_ui.attach_from_grid(grid, dot, rifle, null)
	_check(gun.ads_time < old_ads, "a red dot aims faster")
	var scope := ItemStack.new("scope_4x", 1, 1, 0)
	grid.place(scope)
	loot_ui.attach_from_grid(grid, scope, rifle, null)
	_check(rifle.attachments.get("scope") == "scope_4x" and grid.count_of("red_dot") == 1 and gun.ads_fov == 30.0,
		"a 4x scope replaces the red dot, which comes back to the grid")
	# Taking the mag off with more rounds loaded than the normal mag holds unloads the extra.
	rifle.loaded = 45
	var ammo_before := inv.count_of("rifle_ammo") + grid.count_of("rifle_ammo")
	loot_ui.detach(rifle, "mag", grid)
	_check(rifle.loaded == old_mag and gun.mag_size == old_mag, "mag off: back to %d rounds" % old_mag)
	_check(inv.count_of("rifle_ammo") + grid.count_of("rifle_ammo") == ammo_before + 15 and grid.count_of("ext_mag") == 1,
		"the 15 extra rounds and the mag come back")
	loot_ui.detach(rifle, "scope", grid)
	_check(rifle.attachments.is_empty() and gun.ads_time == old_ads, "all off: the gun is back to normal")
	rifle.loaded = old_mag
	# The equipped gun's slot shows its attachment slots; clicking one takes that attachment off (0.15.17, owner).
	var slot_view := EquipSlotView.new("primary", inv, loot_ui, Vector2i(4, 2))
	main.add_child(slot_view)
	var dot_again := ItemStack.new("red_dot")
	grid.place(dot_again)
	loot_ui.attach_from_grid(grid, dot_again, rifle, null)
	var rects := slot_view._part_rects()
	_check(rects.map(func(r: Array) -> String: return r[0]) == ["scope", "barrel", "grip", "mag"], "the Hound's slot shows scope, barrel, grip and mag")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = (rects[0][1] as Rect2).get_center()
	slot_view._gui_input(click)
	_check(rifle.attachments.is_empty() and inv.count_of("red_dot") + grid.count_of("red_dot") >= 1, "clicking the red dot's slot takes it off")
	inv.take("red_dot", inv.count_of("red_dot"))
	slot_view.free()
	# Attachments on an AI's gun are found in raid, and stay found when taken off (0.17.13, owner); a bought part put
	# on a found gun doesn't.
	var looted := AILoadouts.dropped_gun("ak", ["scope_4x", "foregrip"], 0.0)
	looted.mark_found()
	var bench := GridInventory.new("Bench", 6, 4)
	bench.place(looted)
	loot_ui.detach(looted, "scope", bench)
	var off := _find_stack(bench.stacks, "scope_4x")
	_check(off != null and off.found, "a scope off a looted gun is found in raid")
	var bought := ItemStack.new("red_dot", 1, 5, 3)
	bench.place(bought)
	loot_ui.attach_from_grid(bench, bought, looted, bench)
	loot_ui.detach(looted, "scope", bench)
	_check(not _find_stack(bench.stacks, "red_dot").found, "a bought part put on a found gun comes off unfound")
	_check(GridInventory.data_stack(GridInventory.stack_data(looted)).found_parts == looted.found_parts
		and Profile._read_stack(Profile._write_stack(looted)).found_parts == ["grip"], "found attachments survive saves and the network")


func _section_new_guns() -> void:
	# The Guns update's guns (0.15.2): Wasp (SMG), Mauler (shotgun), Lancer (sniper), each with its own ammo.
	for id in ["smg", "shotgun", "sniper"]:
		var data := ItemDB.item(id)
		_check(ItemDB.kind(id) == "weapon" and ItemDB.kind(data["ammo"]) == "ammo" and data["slot"] == "primary", "%s is a primary gun with its own ammo" % data["name"])
	_check(ItemDB.item("smg")["ammo"] != ItemDB.item("pistol")["ammo"], "the SMG has its own ammo (owner)")
	_check(ceili(100.0 / ItemDB.item("sniper")["damage"]) == 2 and ItemDB.item("sniper")["damage"] * ItemDB.item("sniper")["head"] >= 100,
		"sniper: 2 body shots or 1 headshot")
	_check(is_equal_approx(ItemDB.falloff_mult(ItemDB.item("smg")["falloff"], 10.0), 1.0)
		and is_equal_approx(ItemDB.falloff_mult(ItemDB.item("smg")["falloff"], 60.0), 0.7), "SMG damage drops off past 25 m")
	_check(ItemDB.attachment_slot_for("sniper", "scope_8x") == "scope" and ItemDB.attachment_slot_for("shotgun", "choke") == "barrel"
		and ItemDB.attachment_slot_for("shotgun", "scope_4x") == "", "the 8x scope and choke go on their guns")
	# Hold the shotgun (the AK goes back after).
	var rifle := inv.unequip("primary")
	var shotgun := ItemStack.new("shotgun")
	shotgun.loaded = 6
	inv.equip("primary", shotgun)
	gun.select_slot("primary")
	_check(gun.weapon == shotgun and gun.pellets == 8 and gun.model.visible and gun.model.name == "ShotgunModel", "holding the Mauler (its own model)")
	gun.base_spread_deg = 0.0
	gun.hip_spread_deg = 0.0
	gun.moving_spread_deg = 0.0
	gun._flinch_spread = 0.0
	gun._bloom = 0.0
	player.teleport_to(dummy.global_position + Vector3(0, 0, 5))
	await _frames(3)
	_aim(dummy.global_position + Vector3(0, 1.0, 0))
	await physics_frame
	var before := dummy_health.current
	gun.shoot_once()
	var close := before - dummy_health.current
	_check(close >= 60 and gun.in_mag == 5, "a shotgun blast at 5 m does %d (most of 8 x 14)" % close)
	await create_timer(1.0).timeout
	player.teleport_to(dummy.global_position + Vector3(0, 0, 35))
	await _frames(3)
	_aim(dummy.global_position + Vector3(0, 1.0, 0))
	await physics_frame
	before = dummy_health.current
	gun.shoot_once()
	_check(before - dummy_health.current < close * 0.5, "at 35 m it does much less (%d)" % (before - dummy_health.current))
	# Shells load one at a time, and firing stops the loading.
	inv.add("shells", 10)
	gun.in_mag = 2
	gun.start_reload()
	await create_timer(gun.reload_time * 2.5).timeout
	_check(gun.in_mag == 4 and gun.is_reloading, "two shells loaded one at a time (%d)" % gun.in_mag)
	await create_timer(1.0).timeout
	gun.shoot_once()
	_check(not gun.is_reloading, "firing stops the loading")
	inv.take("shells", inv.count_of("shells"))
	inv.unequip("primary")
	inv.equip("primary", rifle)
	gun.select_slot("primary")
	_check(gun.weapon == rifle and gun.pellets == 1 and gun.load_one == false, "back to the AK")
	# Every gun's shots land where you aim, body and head (owner asked to check the new guns' hits, 0.15.17).
	var spare := inv.unequip("secondary")
	var old_max := dummy_health.max_health
	dummy_health.max_health = 100000
	dummy_health.current = 100000
	player.teleport_to(dummy.global_position + Vector3(0, 0, 8))
	await _frames(3)
	for id: String in ["pistol", "ak", "smg", "shotgun", "sniper"]:
		var test_gun := ItemStack.new(id)
		test_gun.loaded = 5
		var slot := ItemDB.equip_slot(id)
		var held := inv.unequip(slot)
		if id == "sniper":
			test_gun.attachments = {"scope": "scope_8x"}
		inv.equip(slot, test_gun)
		gun.select_slot(slot)
		await create_timer(0.5).timeout
		gun.base_spread_deg = 0.0
		gun.hip_spread_deg = 0.0
		gun.moving_spread_deg = 0.0
		gun.pellet_spread_deg = 0.0
		var results: Array[int] = []
		for height: float in [1.0, 1.65]:
			gun._flinch_spread = 0.0
			gun._bloom = 0.0
			_aim(dummy.global_position + Vector3(0, height, 0))
			await physics_frame
			var hp := dummy_health.current
			gun.shoot_once()
			results.append(hp - dummy_health.current)
			await create_timer(60.0 / gun.rounds_per_minute + 0.05).timeout
		var body := roundi(gun.damage * gun.pellets)
		var head := roundi(gun.damage * gun.headshot_multiplier * gun.pellets)
		_check(results == [body, head], "%s: body %d, head %d at 8 m (got %s)" % [ItemDB.display_name(id), body, head, str(results)])
		inv.unequip(slot)
		if held != null:
			inv.equip(slot, held)
	dummy_health.max_health = old_max
	dummy_health.current = old_max
	if spare != null:
		inv.equip("secondary", spare)
	gun.select_slot("primary")


func _section_ai_loadouts() -> void:
	# AI loadouts (0.15.5, owner's plan): scavs and Raiders roll a gun; it changes how they shoot and is what they drop.
	var seen := {}
	for i in 200:
		seen[AILoadouts.pick("scav")] = true
	_check(seen.size() == 4 and seen.has("ak") and seen.has("smg") and seen.has("shotgun") and seen.has("pistol"), "scavs carry AKs, SMGs, shotguns and pistols")
	_check(AILoadouts.pick("sniper") == "sniper" and not AILoadouts.TABLES["raider"].has("pistol"), "sniper scavs carry the Lancer; Raiders no pistols")
	var probe := (load(SCAV_SCENE) as PackedScene).instantiate() as Scav
	var base_damage := probe.shot_damage
	var base_range := probe.shoot_range
	AILoadouts.apply_style(probe, "shotgun")
	_check(probe.shot_damage > base_damage * 2 and probe.burst_size == 1 and probe.shoot_range < 25.0, "a shotgun AI hits hard, one shot at a time, only up close")
	var base_chase := (load(SCAV_SCENE) as PackedScene).instantiate() as Scav
	_check(probe.chase_range == probe.shoot_range and probe.chase_cover_chance < base_chase.chase_cover_chance
		and probe.push_speed > base_chase.push_speed, "a shotgun AI rushes: chases from as far as it can hit, faster, hardly stops for cover")
	probe.free()
	probe = (load(SCAV_SCENE) as PackedScene).instantiate() as Scav
	AILoadouts.apply_style(probe, "smg")
	_check(probe.shot_damage < base_damage and probe.burst_size > 3 and probe.shoot_range < base_range, "an SMG AI fires longer bursts that hurt less")
	_check(probe.chase_range > base_chase.chase_range and probe.chase_range <= probe.shoot_range
		and probe.suppress_chance > base_chase.suppress_chance, "an SMG AI chases from farther and pins you down more")
	probe.free()
	probe = (load(SCAV_SCENE) as PackedScene).instantiate() as Scav
	AILoadouts.apply_style(probe, "pistol")
	_check(probe.chase_range < base_chase.chase_range and probe.chase_cover_chance > base_chase.chase_cover_chance,
		"a pistol AI is careful: chases only up close, takes cover more")
	probe.free()
	probe = (load(SCAV_SCENE) as PackedScene).instantiate() as Scav
	AILoadouts.apply_style(probe, "ak")
	_check(probe.chase_range == base_chase.chase_range and probe.shoot_range == base_range, "an AK AI fights as before")
	probe.free()
	base_chase.free()
	# Each gun's sound (0.15.12) and the gun sent to puppets online.
	probe = (load(SCAV_SCENE) as PackedScene).instantiate() as Scav
	probe.loadout = "shotgun"
	main.add_child(probe)
	_check(probe.carried_gun == "shotgun" and probe.shot_sound == GunSounds.shot("shotgun") and probe.shot_sound != GunSounds.DEFAULT_SHOT,
		"a shotgun AI sounds like the Mauler")
	probe.free()
	var all_guns := ["sniper"]
	for table: Dictionary in AILoadouts.TABLES.values():
		all_guns.append_array(table.keys())
	_check(all_guns.all(func(g: String) -> bool: return AILoadouts.NET_GUNS.has(g)), "every AI gun can be sent to puppets")
	_check(GunSounds.shot("smg") != GunSounds.shot("sniper") and GunSounds.shot("ak") == GunSounds.DEFAULT_SHOT
		and GunSounds.shot("pistol") == GunSounds.DEFAULT_SHOT, "the Wasp, Mauler and Lancer have their own shots; the Hound and Stinger keep theirs")
	# Stat bars in the inventory (0.15.12).
	var hound := ItemStack.new("ak")
	var bare := GunStatBars.scores(ItemDB.weapon_stats(hound))
	hound.attachments = {"grip": "foregrip", "barrel": "suppressor", "scope": "scope_4x"}
	var dressed := GunStatBars.scores(ItemDB.weapon_stats(hound))
	_check(dressed[3] > bare[3] and dressed[5] > bare[5] and dressed[4] < bare[4] and dressed[0] == bare[0],
		"stat bars: a grip adds control, a suppressor quiet, a scope costs handling")
	var mauler := GunStatBars.scores(ItemDB.item("shotgun"))
	var lancer := GunStatBars.scores(ItemDB.item("sniper"))
	var wasp := GunStatBars.scores(ItemDB.item("smg"))
	_check(mauler[0] > bare[0] and lancer[2] > bare[2] and mauler[2] < wasp[2] and wasp[1] > bare[1] and lancer[3] < bare[3],
		"stat bars compare guns: Mauler hits hardest, Lancer reaches farthest, Wasp fires fastest")
	var choked := ItemStack.new("shotgun")
	choked.attachments = {"barrel": "choke"}
	_check(GunStatBars.scores(ItemDB.weapon_stats(choked))[2] > mauler[2], "a choke gives the Mauler more range")
	# A spawned one: its gun is what it drops.
	var scav := (load(SCAV_SCENE) as PackedScene).instantiate() as Scav
	main.add_child(scav)
	scav.global_position = Vector3(30, 0.1, 30)
	await physics_frame
	_check(AILoadouts.TABLES["scav"].has(scav.weapon_drop) and scav.muzzle != null and scav.muzzle.is_inside_tree(), "a spawned scav rolls a gun (%s)" % scav.weapon_drop)
	scav.queue_free()
	var boss_gun := AILoadouts.dropped_gun("ak", ["scope_4x", "foregrip"], 0.0)
	_check(boss_gun.attachments == {"scope": "scope_4x", "grip": "foregrip"}, "Bon's AK drops with a scope and grip")
	var with_part := 0
	for i in 100:
		if not AILoadouts.dropped_gun("shotgun", [], 0.25).attachments.is_empty():
			with_part += 1
	_check(with_part > 8 and with_part < 45, "a Raider's dropped gun sometimes has an attachment (%d/100)" % with_part)


func _section_dropped_gun() -> void:
	# A gun dropped into a bag (a body's weapon, or dropping it yourself) keeps the rounds loaded in it.
	var pistol := ItemStack.new("pistol")
	pistol.loaded = 12
	var bag := LootContainer.spawn_bag(main, player.global_position + Vector3(3, 0, 0), "Dropped", [pistol])
	var in_bag := _find_stack(bag.grid.stacks, "pistol")
	_check(in_bag != null and in_bag.loaded == 12, "a gun dropped in a bag keeps its 12 loaded rounds (%s)" % (str(in_bag.loaded) if in_bag != null else "missing"))
	bag.queue_free()
	# 0.15.16 (owner: "really cluttered"): things you drop one after another go on one pile.
	loot_ui._drop_or_overflow(ItemStack.new("phone"))
	loot_ui._drop_or_overflow(ItemStack.new("golden_toilet"))
	loot_ui._drop_or_overflow(ItemStack.new("battery"))
	var piles := RaidScope.nodes(main, &"loot_containers").filter(func(c: Node) -> bool: return (c as LootContainer).display_name == "Dropped Items")
	_check(piles.size() == 1 and (piles[0] as LootContainer).grid.stacks.size() == 3, "items you drop go on one pile (%d piles)" % piles.size())
	for pile in piles:
		pile.queue_free()


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
	# (what you carry is worth what it is now: the hits earlier wore the armor down, 0.14.0)
	expected_value = player.inventory.total_value()
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
	player.inventory.secure.clear()
	player.inventory.secure.add("crystal")
	player.health.take_damage(9999)
	await _frames(3)
	_check(player.downed and not player.is_dead, "player goes down at 0 hp with a teammate up")
	teammate_up[0] = false
	await _frames(3)
	_check(player.is_dead and not player.downed, "player dies once nobody is left to revive them (both down)")
	# The death screen's lost loot leaves out the secure pocket, which comes home (owner, 0.14.19).
	var expected_lost := 0
	for stack in player.inventory.all_stacks():
		if not stack in player.inventory.secure.stacks:
			expected_lost += stack.value()
	var real_result := raid.result
	raid.result = "killed"
	raid._tally_loot()
	raid.result = real_result
	_check(raid.loot_value == expected_lost and raid.loot_summary.size() == player.inventory.all_stacks().size() - 1,
		"what you lost leaves out the secure pocket (%s)" % ItemDB.money(raid.loot_value))
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
	# (0.17.5, owner) New players start with $50,000; a save from before keeps its own money and everything in it.
	_check(Profile.START_MONEY == 50000, "new players start with $50,000")
	var old_save := {"version": Profile.VERSION, "money": 1234, "stash_size": [8, 30], "saved_at": 50.0,
		"stash": [{"id": "gold_watch", "count": 1, "x": 0, "y": 0}],
		"loadout": {"equipment": {"primary": {"id": "ak", "count": 1, "loaded": 30}}, "pockets": [], "backpack": [], "secure": [], "hotbar": ["", "", ""]},
		"stats": {"raids": 7, "extracts": 3, "deaths": 4, "earned": 9000}, "trader_spent": {"guns": 500}}
	var current_file := FileAccess.get_file_as_string(Profile.PATH)
	var file := FileAccess.open(Profile.PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(old_save))
	file.close()
	Profile._loaded = false
	Profile.load_profile()
	_check(Profile.money == 1234 and Profile.stash.height == 30 and Profile.stash.count_of("gold_watch") == 1
		and Profile.loadout["equipment"].has("primary") and int(Profile.stats["raids"]) == 7,
		"an old save keeps its money, stash, loadout and stats (money %d)" % Profile.money)
	Profile.reset()
	_check(Profile.money == 50000, "a brand new profile gets $50,000")
	file = FileAccess.open(Profile.PATH, FileAccess.WRITE)
	file.store_string(current_file)
	file.close()
	Profile._loaded = false
	Profile.load_profile()
	_check(Profile.money == money_before, "back to the test's own save")
	# (0.17.5) One tab plays (TabLock); off the web nothing is shared, so the game always owns its saves.
	_check(TabLock.owns(), "off the web the game always plays and saves")
	# Web keeps a second copy in localStorage: loading takes whichever copy was saved last.
	var older := JSON.stringify({"version": Profile.VERSION, "saved_at": 100.0})
	var newer := JSON.stringify({"version": Profile.VERSION, "saved_at": 200.0})
	_check(Profile.newer_save(older, newer) == newer and Profile.newer_save(newer, older) == newer
		and Profile.newer_save("", older) == older and Profile.newer_save(older, "") == older
		and Profile.newer_save("{}", newer) == newer and Profile.newer_save(older, "{}") == older,
		"loading picks the newest of the file and web copies of the save")


## Loading guns in the stash, keeping the stash's scroll, and found-in-raid attachments (0.17.13, owner).
func _stash_tools(hideout: Node) -> void:
	var ui: LootUI = hideout.screen
	var stash: GridInventory = ui.stash
	var carried: Inventory = hideout.inventory
	# Load / unload a gun in the stash from the stash's rounds; dragging rounds onto a gun loads it too.
	var hound := ItemStack.new("ak")
	var spot := stash.find_spot("ak")
	hound.set_spot(Vector2i(spot[0], spot[1]), spot[2])
	stash.place(hound)
	stash.add("rifle_ammo", 50)
	var rounds_before := stash.count_of("rifle_ammo") + carried.count_of("rifle_ammo")
	var mag := int(ItemDB.weapon_stats(hound)["mag"])
	_check(ui.can_load(hound) and ui.load_gun(hound) == mag and hound.loaded == mag
		and stash.count_of("rifle_ammo") + carried.count_of("rifle_ammo") == rounds_before - mag, "load a gun in the stash (%d rounds)" % hound.loaded)
	_check(not ui.can_load(hound) and ui.unload_gun(hound, stash) and hound.loaded == 0
		and stash.count_of("rifle_ammo") + carried.count_of("rifle_ammo") == rounds_before, "unload it: the rounds come back")
	var loose := _find_stack(stash.stacks, "rifle_ammo")
	ui.load_gun(hound, loose, stash)
	_check(hound.loaded == mag, "rounds dropped onto a gun load it")
	ui.unload_gun(hound, stash)
	ui.open_menu(stash, hound)
	var entries: Array[String] = []
	for i in ui._menu.item_count:
		entries.append(ui._menu.get_item_text(i))
	ui._menu.hide()
	_check(entries.has("Load"), "a gun's menu in the stash offers Load (%s)" % ", ".join(entries))
	stash.remove(hound)
	_check(not loot_ui.can_load(ItemStack.new("ak")), "in a raid, loading is reloading (no Load in the menu)")
	# Re-laying the screen out (equipping, an attachment on your gun) keeps the stash where it was scrolled to.
	await process_frame
	var scroll := ui._stash_scroll
	scroll.scroll_vertical = 200
	await process_frame
	var scrolled := scroll.scroll_vertical
	ui._rebuild_layout()
	await process_frame
	await process_frame
	_check(scrolled > 0 and ui._stash_scroll.scroll_vertical == scrolled, "the stash stays scrolled after a rebuild (%d -> %d)" % [scrolled, ui._stash_scroll.scroll_vertical])


func _section_hideout() -> void:
	# Hideout: loadout, buying, selling, free kit.
	var hideout = (load("res://scenes/hideout.tscn") as PackedScene).instantiate()
	root.add_child(hideout)
	await process_frame
	var hideout_inv: Inventory = hideout.inventory
	_check(hideout_inv.equipped("primary") != null and hideout.screen.visible, "hideout shows your loadout and stash")
	var version: String = ProjectSettings.get_setting("application/config/version")
	_check(hideout._version_label.text == "v" + version, "hideout shows the version (%s)" % hideout._version_label.text)
	# 0.19.6 (Glow look, bigger cells): the inventory screen with the trader column still fits the 1280 px wide screen,
	# and a long name on a 1-cell tile ("Bandage") fits its tile instead of being cut off.
	var columns_width: float = hideout.screen._columns.get_combined_minimum_size().x
	_check(columns_width <= 1280.0, "the hideout's inventory columns fit the screen (%d px)" % columns_width)
	var bandage_tile := ItemTile.new(ItemStack.new("bandage"), Profile.stash, hideout.screen)
	var name_label: Label = bandage_tile._name_label
	var name_width := name_label.get_theme_font("font").get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		name_label.get_theme_font_size("font_size")).x
	_check(name_label.text == "Bandage" and name_width <= name_label.size.x, "a 1-cell tile's name fits (%d of %d px)" % [name_width, name_label.size.x])
	bandage_tile.free()
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
	# What a gun is, before you buy it (0.18.8, owner): hovering (or tapping) a stock row shows its details.
	hideout.open_trader("guns")
	var gun_row: Control = null
	for row: Node in hideout._trader_rows.get_children():
		var labels := row.find_children("*", "Label", false, false)   # (after the item's picture)
		var label := labels[0] as Label if not labels.is_empty() else null
		if row is HBoxContainer and label != null and label.text == ItemDB.display_name("ak"):
			gun_row = row
	if gun_row != null:
		gun_row.mouse_entered.emit()
	_check(gun_row != null and gun_row.mouse_filter == Control.MOUSE_FILTER_STOP
		and hideout.screen._info_label.text.contains(ItemDB.display_name("ak"))
		and hideout.screen._info_detail.text.contains("damage") and hideout.screen._info_detail.text.contains("rpm")
		and hideout.screen._info_desc.text == ItemDB.description("ak"),
		"hovering a gun at the trader shows what it is before you buy it (%s)" % hideout.screen._info_detail.text)
	money = Profile.money
	hideout.buy("pistol", 1)
	var bought_pistol := _find_stack(Profile.stash.stacks, "pistol")
	_check(bought_pistol != null and Profile.money == money - hideout.buy_price("pistol", 1), "buy a pistol")
	money = Profile.money
	hideout.sell(Profile.stash, bought_pistol)
	_check(Profile.money == money + roundi(ItemDB.value("pistol") * 0.6), "gear sells for 60%")
	# Auto sort (0.15.16, owner): part stacks merge, guns go first, valuables last.
	Profile.stash.add("bandage", 1)
	var loose := ItemStack.new("bandage", 1)
	var loose_spot := Profile.stash.find_spot("bandage")
	if not loose_spot.is_empty():
		loose.set_spot(Vector2i(loose_spot[0], loose_spot[1]), loose_spot[2])
		Profile.stash.place(loose)
	var stash_value := Profile.stash.total_value()
	var sort_button := hideout.screen.find_child("SortButton", true, false) as Button
	_check(sort_button != null and sort_button.custom_minimum_size.y >= 44, "the stash has a SORT button big enough to tap")
	if sort_button != null:
		sort_button.pressed.emit()
		_check(sort_button.text == "SURE?" and Profile.stash.total_value() == stash_value, "SORT asks first (\"SURE?\")")
		sort_button.pressed.emit()
	var first: ItemStack = null
	for stack in Profile.stash.stacks:
		if first == null or stack.y < first.y or (stack.y == first.y and stack.x < first.x):
			first = stack
	var best_kind := GridInventory.SORT_ORDER.size()
	for stack in Profile.stash.stacks:
		best_kind = mini(best_kind, GridInventory.SORT_ORDER.find(ItemDB.kind(stack.id)))
	var part_bandages := Profile.stash.stacks.filter(func(st: ItemStack) -> bool: return st.id == "bandage" and st.space_left() > 0).size()
	_check(Profile.stash.total_value() == stash_value and part_bandages <= 1 and first != null and GridInventory.SORT_ORDER.find(ItemDB.kind(first.id)) == best_kind,
		"sorting the stash keeps everything, merges part stacks and puts guns and gear first (%s)" % (first.id if first != null else "-"))
	# START RAID (0.18.10, owner: the game froze on the press): a loading plate goes up before the raid loads.
	hideout._show_loading()   # (what start_raid() puts up before it loads the raid scene)
	_check(hideout._loading is LoadingScreen and hideout._loading.visible and hideout._loading.get_child(0) is TextureRect,
		"START RAID puts the loading screen up before the raid loads")
	_check(not hideout.can_take_free_kit(), "no free kit while you carry anything")
	# (0.15.28, owner) Only with a completely empty loadout: nothing equipped, nothing in any pocket.
	for loadout_grid in hideout_inv.grids():
		for stack in loadout_grid.stacks.duplicate():
			loadout_grid.remove(stack)
	for slot in Inventory.SLOTS:
		if hideout_inv.equipped(slot) != null:
			hideout_inv.unequip(slot)
	_check(hideout_inv.all_stacks().is_empty() and hideout.can_take_free_kit() and hideout.take_free_kit()
		and hideout_inv.equipped("secondary") != null, "empty loadout: the free kit gives you a pistol")
	var kit_pack := hideout_inv.equipped("backpack")
	_check(kit_pack != null and kit_pack.id == "backpack_small" and kit_pack.free and hideout.sell_price(kit_pack) == 0,
		"the free kit includes a small backpack that sells for $0")
	_check(not hideout.can_take_free_kit(), "free kit is gone once you carry something")
	# (0.16.5, owner) The kit's pistol sells for nothing; a bought or found one still sells. The mark is saved.
	var kit_pistol := hideout_inv.equipped("secondary")
	_check(kit_pistol.free and hideout.sell_price(kit_pistol) == 0, "the free kit's pistol sells for $0")
	_check(hideout.sell_price(ItemStack.new("pistol")) > 0, "a normal Stinger still sells")
	var saved_kit := GridInventory.data_stack(GridInventory.stack_data(kit_pistol))
	_check(saved_kit.free and Profile._read_stack(Profile._write_stack(kit_pistol)).free, "the free kit mark survives saving and the network")
	# (0.16.6, owner: nothing in the kit sells) The rounds and bandage too, and they never mix into sellable stacks.
	var kit_extras := hideout_inv.all_stacks().filter(func(st: ItemStack) -> bool: return st.id in ["pistol_ammo", "bandage"])
	_check(kit_extras.size() == 2 and kit_extras.all(func(st: ItemStack) -> bool: return st.free and hideout.sell_price(st) == 0),
		"the free kit's rounds and bandage sell for nothing")
	# (0.16.7, owner) Selling one still works, for $0, so you can clear free kit items out.
	var kit_bandage: ItemStack = kit_extras.filter(func(st: ItemStack) -> bool: return st.id == "bandage")[0]
	var bandage_grid: GridInventory = null
	for g in hideout_inv.grids():
		if kit_bandage in g.stacks:
			bandage_grid = g
	var money_kit := Profile.money
	hideout.sell(bandage_grid, kit_bandage)
	_check(Profile.money == money_kit and not kit_bandage in bandage_grid.stacks, "a free kit item sells for $0 (it's gone, no money)")
	hideout_inv.add("pistol_ammo", 10)
	var ammo_stacks := hideout_inv.all_stacks().filter(func(st: ItemStack) -> bool: return st.id == "pistol_ammo")
	_check(ammo_stacks.size() == 2 and ammo_stacks.any(func(st: ItemStack) -> bool: return not st.free and st.count == 10)
		and ammo_stacks.any(func(st: ItemStack) -> bool: return st.free and st.count == 30), "bought rounds don't merge into free kit rounds")
	var free_ammo: ItemStack = ammo_stacks.filter(func(st: ItemStack) -> bool: return st.free)[0]
	var ammo_grid: GridInventory = null
	for g in hideout_inv.grids():
		if free_ammo in g.stacks:
			ammo_grid = g
	hideout.screen.quick_move(ammo_grid, free_ammo)
	var moved_free := Profile.stash.stacks.filter(func(st: ItemStack) -> bool: return st.id == "pistol_ammo" and st.free)
	_check(not moved_free.is_empty() and hideout_inv.count_of("pistol_ammo") == 10, "free kit rounds stay free kit rounds when moved to the stash")
	for st: ItemStack in moved_free:
		Profile.stash.remove(st)
	hideout_inv.take("pistol_ammo", 10)
	# Online (0.16.3, owner: you couldn't go online with the free kit): TAKE FREE KIT puts it on you and stays online.
	for loadout_grid in hideout_inv.grids():
		for stack in loadout_grid.stacks.duplicate():
			loadout_grid.remove(stack)
	for slot in Inventory.SLOTS:
		if hideout_inv.equipped(slot) != null:
			hideout_inv.unequip(slot)
	# (0.16.4, owner) Once per raid: emptied again right away, there's no second kit (no selling it for money forever).
	_check(hideout_inv.all_stacks().is_empty() and not hideout.can_take_free_kit() and not hideout.take_free_kit(),
		"no second free kit until you've been on a raid")
	Profile.stats["raids"] += 1
	var old_mode = Network.main.mode
	Network.main.mode = Network.Mode.CLIENT
	hideout._refresh()
	_check(hideout._free_kit_button.visible and hideout._free_kit_button.text == "TAKE FREE KIT", "online, the free kit button reads TAKE FREE KIT")
	hideout.start_with_free_kit()
	_check(hideout_inv.equipped("secondary") != null and Network.main.is_client() and hideout.is_inside_tree(),
		"online, the free kit goes on you and you stay online in the hideout to queue")
	Network.main.mode = old_mode
	hideout._refresh()
	hideout.save_now()
	var saved_loadout: Dictionary = Profile.loadout.get("equipment", {})
	_check(saved_loadout.has("secondary"), "hideout changes are saved to the profile")
	# Traders (0.16.0, Economy update): levels from money spent unlock stock; each trader buys its own kind.
	var every_item_has_buyer := ItemDB.ITEMS.keys().all(func(id: String) -> bool: return Traders.buyer_for(id) in Traders.LIST)
	_check(every_item_has_buyer and Traders.buyer_for("gold_watch") == "valuables" and Traders.buyer_for("medkit") == "meds"
		and Traders.buyer_for("ak") == "guns" and Traders.buyer_for("armor_light") == "supplies", "every item has a trader that buys it")
	_check(Traders.trader_for("armor_heavy") == "" and Traders.trader_for("ak") == "guns", "heavy armor stays loot-only")
	Profile.trader_spent = {}
	Profile.quests_done = []
	Profile.quest_progress = {}
	Profile.trader_levels = {}
	Profile.money = 100000
	var money2 := Profile.money
	_check(Profile.trader_level("guns") == 1 and not hideout.buy("ak", 1) and Profile.money == money2, "a level 2 gun can't be bought at level 1")
	# Quests (0.16.13, owner): a level needs its quests done, plus (for some) money spent with the trader.
	Profile.trader_spent["guns"] = int(Traders.LIST["guns"]["levels"][1]["spent"])
	_check(Profile.trader_level("guns") == 1, "money alone doesn't level a trader any more")
	Quests.raid_started()
	for i in 5:
		Quests.record_kill("scav", "pistol")
	for i in 3:
		Quests.record_kill("scav", "shotgun")
	Quests.raid_ended(false, 0)
	_check(Quests.progress("zeroing_in") == 0 and Quests.raid_kills.is_empty(), "kills don't count if you don't get out")
	Quests.raid_started()
	for i in 5:
		Quests.record_kill("scav", "pistol")
	for i in 3:
		Quests.record_kill("scav", "shotgun")
	Quests.record_kill("sniper", "pistol")
	money2 = Profile.money
	Quests.raid_ended(true, 0)
	_check(Profile.quests_done.has("zeroing_in") and Profile.quests_done.has("field_test") and Quests.progress("overwatch") == 0
		and Profile.money == money2 + 5000 and Quests.just_finished.size() == 2,
		"extracting counts the raid's kills: two gun quests done, rewards paid, level 3 quests not open yet")
	hideout._announce_quests()
	_check(hideout._message_label.text.begins_with("Quest done") and Quests.just_finished.is_empty(), "the hideout says which quests the raid finished")
	# Hand-ins take only items found in raid.
	Profile.stash.add("red_dot", 1)
	_check(hideout.hand_in("spare_parts") == 0 and Profile.trader_level("guns") == 1, "a bought attachment can't be handed in")
	Profile.stash.add("foregrip", 1, ItemStack.FOUND)
	Profile.stash.add("suppressor", 1, ItemStack.FOUND)
	var found_grip: ItemStack = Profile.stash.stacks.filter(func(st: ItemStack) -> bool: return st.id == "foregrip")[0]
	_check(Profile._read_stack(Profile._write_stack(found_grip)).found and GridInventory.data_stack(GridInventory.stack_data(found_grip)).found,
		"the found in raid mark survives saving and the network")
	# The hand-in window (0.16.14, owner): your found items on one side, the trader's box on the other; part of a
	# quest can be handed in now and the rest later.
	hideout.open_hand_in("spare_parts")
	var window: HandInWindow = hideout.hand_in_window
	_check(window.visible and window._yours.get_child_count() == 2 and window._box.get_child_count() == 0,
		"the hand-in window lists your 2 found attachments (not the bought red dot)")
	window.offer(found_grip)
	window.offer(found_grip)
	_check(window.boxed() == 1 and window._box.get_child_count() == 1 and window._yours.get_child_count() == 1, "tap an item: one goes into the trader's box")
	window.confirm()
	_check(not window.visible and Quests.progress("spare_parts") == 1 and Profile.stash.count_of("foregrip") == 0
		and Profile.stash.count_of("suppressor") == 1 and Profile.trader_level("guns") == 1, "hand in part of a quest (1/2)")
	_check(hideout.hand_in("spare_parts") == 1 and Profile.stash.count_of("suppressor") == 0 and Profile.stash.count_of("red_dot") == 1
		and Profile.trader_level("guns") == 1 and Profile.can_level_up("guns"), "handing in the rest finishes the last quest: the Gunsmith can level up")
	hideout.open_trader("guns")
	var level_button := hideout._trader_rows.get_node_or_null("LevelUp") as Button
	_check(level_button != null and not level_button.disabled and level_button.text == "LEVEL UP TO 2", "the trader shows a LEVEL UP button (0.17.1)")
	level_button.pressed.emit()
	_check(Profile.trader_level("guns") == 2 and not Profile.can_level_up("guns") and hideout._message_label.text.contains("is now level 2")
		and hideout.buy("ak", 1), "LEVEL UP: level 2, the Hound unlocks")
	# The quest tracker in the pause menu (0.17.1): open quests with progress, and what this raid adds once out.
	var tracker := QuestTracker.new()
	root.add_child(tracker)
	Quests.raid_started()
	Quests.record_kill("sniper", "ak")
	var no_menu := Control.new()
	tracker.refresh(no_menu)
	no_menu.free()
	var tracker_text := ""
	for label in tracker.find_children("*", "Label", true, false):
		tracker_text += (label as Label).text + "\n"
	_check(tracker_text.contains("OVERWATCH") and tracker_text.contains("Kill 2 snipers, then extract. +1 when you extract.") and not tracker_text.contains("ZEROING IN"),
		"the quest tracker lists the open quests and this raid's kills (%s)" % tracker_text.replace("\n", " | "))
	Quests.raid_started()
	tracker.free()
	Profile.stash.add("bandage", 1)
	Profile.stash.add("bandage", 1, ItemStack.FOUND)
	var bandage_stacks := Profile.stash.stacks.filter(func(st: ItemStack) -> bool: return st.id == "bandage")
	_check(bandage_stacks.size() == 2, "found bandages don't stack with bought ones (a quest wants found bandages)")
	# 0.17.2 (owner): the found mark only matters for items an open quest wants; the rest stack with everything.
	Profile.stash.add("pistol_ammo", 5)
	Profile.stash.add("pistol_ammo", 5, ItemStack.FOUND)
	var round_stacks := Profile.stash.stacks.filter(func(st: ItemStack) -> bool: return st.id == "pistol_ammo")
	_check(not Quests.wants("pistol_ammo") and Quests.wants("bandage") and round_stacks.size() == 1 and round_stacks[0].count == 10
		and not round_stacks[0].found, "found and bought ammo stack together (no quest wants it)")
	var crate := LootContainer.new()
	crate.loot_table = "crate"
	crate.min_items = 2
	crate.max_items = 2
	crate._ready()
	_check(not crate.grid.stacks.is_empty() and crate.grid.stacks.all(func(st: ItemStack) -> bool: return st.found), "loot in containers is found in raid")
	crate.free()
	hideout.open_trader("meds")
	_check(hideout._trader_title.text == "MEDIC" and hideout._trader_rows.get_child_count() == Traders.stock("meds").size() + Quests.for_level("meds", 2).size() + 2,
		"the trader tabs switch the stock shown, with the next level's quests on top")
	var trader_panel := hideout._trader_title.get_parent().get_parent().get_parent() as Control
	var widths := {}
	for trader: String in Traders.LIST:
		hideout.open_trader(trader)
		widths[trader_panel.get_combined_minimum_size().x] = true
	_check(widths.size() == 1, "the trader column is the same width for every trader (0.17.2: %s)" % str(widths.keys()))
	# Stash upgrades (0.16.0): more rows for money, up to the top size.
	Profile.stash.height = Profile.STASH_ROWS[0]
	money = Profile.money
	var cost := Profile.next_stash_cost()
	_check(Profile.stash_level() == 1 and hideout.upgrade_stash() and Profile.stash.height == Profile.STASH_ROWS[1]
		and Profile.money == money - cost, "buy a stash upgrade")
	Profile.money = 0
	_check(not hideout.upgrade_stash() and Profile.stash.height == Profile.STASH_ROWS[1], "no stash upgrade without the money")
	Profile.money = 1000000
	while Profile.next_stash_cost() > 0:
		hideout.upgrade_stash()
	_check(Profile.stash.height == Profile.STASH_ROWS[-1] and not hideout.upgrade_stash(), "the stash stops at its top size")
	Profile.save_profile()
	Profile.trader_spent = {}
	Profile.quests_done = []
	Profile._loaded = false
	Profile.load_profile()
	_check(Profile.trader_level("guns") == 2 and Profile.stash.height == Profile.STASH_ROWS[-1], "trader levels and stash size are saved")
	# Ming's mystery boxes (0.16.2, owner): earned money in, one random item from the box into the stash, odds shown.
	var odds_ok := Traders.BOXES.keys().all(func(box: String) -> bool:
		var sum := 0.0
		for entry: Array in Traders.box_odds(box):
			sum += entry[1]
		return absf(sum - 100.0) < 0.01)
	_check(odds_ok and Traders.BOXES.keys().all(func(box: String) -> bool:
		return Traders.BOXES[box]["odds"].keys().all(func(key: String) -> bool:
			return ItemDB.ITEMS.has(key) or key in ["common", "uncommon", "rare", "epic", "legendary"])),
		"every Ming box lists real items and its odds add up to 100%")
	Profile.money = 50000
	money = Profile.money
	var stash_count := Profile.stash.stacks.size()
	var won: String = hideout.open_box("gun_box")
	_check(won in Traders.BOXES["gun_box"]["odds"] and Profile.money == money - int(Traders.BOXES["gun_box"]["price"])
		and Profile.stash.stacks.size() == stash_count + 1, "a Ming gun box takes its price and puts a gun in the stash (%s)" % won)
	var won_stack := _find_stack(Profile.stash.stacks, won)
	_check(won_stack != null and not won_stack.found, "a gambled gun isn't found in raid (0.17.13: no quest hand-ins)")
	won = hideout.open_box("loot_box")
	_check(won != "" and ItemDB.kind(won) == "valuable" and not ItemDB.item(won).get("special", false), "a Ming loot box gives a valuable")
	_check(Profile.stash.stacks.all(func(s: ItemStack) -> bool: return s.id != won or not s.found), "a gambled valuable isn't found in raid")
	Profile.money = 10
	_check(hideout.open_box("gun_box") == "" and Profile.money == 10, "no Ming box without the money")
	hideout.open_trader("ming")
	_check(hideout._trader_title.text == "MING" and hideout._trader_rows.get_child_count() == Traders.BOXES.size() * 2,
		"Ming's tab shows each box with its odds")
	await _stash_tools(hideout)
	hideout.queue_free()
	await process_frame


func _section_settings() -> void:
	GameSettings.set_volume(0.0)
	_check(AudioServer.is_bus_mute(0), "volume 0 mutes audio")
	GameSettings.set_volume(0.5)
	_check(not AudioServer.is_bus_mute(0) and AudioServer.get_bus_volume_db(0) < 0.0, "volume 50% lowers audio")
	# Graphics (0.19): LOW drops the sun's shadows, draws 3D at a lower scale and switches buildings to their far mesh
	# sooner; HIGH puts it all back. Three buttons in the pause menu.
	var sun := main.get_node("Sun") as DirectionalLight3D
	var buttons := main.get_node("HUD/Menu/Margin/VBox/GraphicsRow/Buttons")
	_check(buttons.get_child_count() == 3, "the pause menu has LOW / MEDIUM / HIGH graphics buttons")
	GameSettings.set_graphics(GameSettings.LOW)
	_check(not sun.shadow_enabled and root.scaling_3d_scale < 1.0 and FarView.distance() < FarView.FROM,
		"LOW graphics: no sun shadows, lower render scale, far meshes sooner")
	GameSettings.set_graphics(GameSettings.HIGH)
	_check(sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, 60.0) and
		is_equal_approx(root.scaling_3d_scale, 1.0) and is_equal_approx(FarView.distance(), FarView.FROM),
		"HIGH graphics: shadows to 60 m, full render scale, far meshes from %d m" % FarView.FROM)


func _section_mouse() -> void:
	# 0.17.7: a fast turn (big moves that build up and keep going) must not be dropped as a glitch;
	# a lone huge jump out of slow movement still is, but never twice in a row.
	var t := 100000
	var used := 0
	for move in [20.0, 60.0, 180.0, 450.0, 900.0, 1400.0, 1200.0, 800.0, 300.0]:
		t += 16
		if not player.is_mouse_spike(move, t):
			used += 1
	_check(used == 9, "a fast turn on a high-DPI mouse is used in full (%d of 9 moves)" % used)
	t += 16
	_check(not player.is_mouse_spike(5.0, t), "a slow move is used")
	t += 16
	_check(player.is_mouse_spike(1500.0, t), "a lone huge jump out of a slow move is dropped")
	t += 16
	_check(not player.is_mouse_spike(1500.0, t), "a second big move in a row is used (a real flick)")
	t += 500
	_check(player.is_mouse_spike(900.0, t) and not player.is_mouse_spike(950.0, t + 16), "a flick from rest loses at most one move")


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
	# Every point gets used (0.17.13, owner: online, a lone squad always started at the first point): slot 0 over
	# many raid seeds lands on each point about as often.
	var used := {}
	for seed_value in 400:
		var at := Raid.spawn_position(points, 0, 0, seed_value)
		used[at] = int(used.get(at, 0)) + 1
	var fair := used.size() == points.size() and used.values().all(func(n: int) -> bool: return n > 400 / points.size() / 2)
	_check(fair, "spawn points are used evenly over raids (%d points: %s)" % [points.size(), used.values()])
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
	# They hold the model of the gun they have out (0.18.1): the gun goes in the flags' top bits.
	var held_index := AILoadouts.NET_GUNS.find(player.gun.weapon.id) if player.gun.weapon != null else -1
	_check(held_index <= 0 or RemotePlayer.capture(player)[4] >> Hitbox.GUN_SHIFT == held_index, "the gun a player holds is sent with their state")
	body.push_state([Vector3(2, 0.1, -12), 0.0, 0.0, 0.0, RemotePlayer.FLAG_ARMED | AILoadouts.NET_GUNS.find("shotgun") << Hitbox.GUN_SHIFT], 10.075)
	body.update_view(10.075, 0.016)
	_check(body.gun_model == body.model.get_node("Gun") and body.gun_model.get_meta("gun", "") == "shotgun"
		and body.gun_model.has_node("Art/Body") and body.gun_model.has_node("Muzzle") and body.gun_model.visible,
		"another player holding a Mauler shows the Mauler model")
	for id: String in HeldGun.MODELS:
		var art := HeldGun.instance(id)
		_check(art.has_node("Body") and art.has_node("Muzzle") and art.has_node("Grip") and art.has_node("Sight") and art.has_node("Optic"),
			"the %s model has its parts and markers" % id)
		art.free()
	var view_gun := player.get_node("Head/Recoil/Camera3D/Gun")
	for key in ["Model", "PistolModel", "SmgModel", "ShotgunModel", "SniperModel"]:
		_check(view_gun.has_node(key + "/Art/Body"), "first person shows the real model in %s" % key)
	# You hear other players walk (0.12.35, owner: teammates were silent online).
	var steps_before := main.get_tree().current_scene.find_children("*", "AudioStreamPlayer3D", false, false).size()
	for k in 40:
		body.push_state([Vector3(2 + 0.08 * (k + 1), 0.1, -12), 0.0, 0.0, 0.0, RemotePlayer.FLAG_ARMED], 10.08 + 0.016 * k)
		body.update_view(10.08 + 0.016 * k, 0.016)
	var steps_after := main.get_tree().current_scene.find_children("*", "AudioStreamPlayer3D", false, false).size()
	_check(steps_after > steps_before, "another player walking makes footstep sounds (%d)" % (steps_after - steps_before))
	body._buffer.clear()
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
	# 0.16.11 (owner): extracted online with a teammate still in, you can spectate them too.
	var was := [Network.main.mode, Network.main.in_raid, raid.result, Network.main.states.get(78)]
	Network.main.mode = Network.Mode.CLIENT
	Network.main.in_raid = true
	Network.main.states[78] = [mate.global_position, 0.0, 0.0, 0.0, 0]
	raid.result = "extracted"
	hud.end_screen.show_result(0)
	_check(String(hud.end_screen.summary().get("spectate", "")).begins_with("SPECTATE"), "extracted online: SPECTATE your teammate still in the raid")
	hud.end_screen.visible = false
	Network.main.mode = was[0]
	Network.main.in_raid = was[1]
	raid.result = was[2]
	if was[3] == null:
		Network.main.states.erase(78)
	else:
		Network.main.states[78] = was[3]
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
	var got := {"hits": [], "confirmed": [], "kills": 0, "heard": [], "feed": []}
	c2.player_fired.connect(func(_peer: int, _from: Vector3, _end: Vector3, weapon: String, _quiet: bool) -> void: got["heard"].append(weapon))
	# (The target's game reports what each hit did after its armor; here, armor that takes 25% off.)
	c2.got_hit.connect(func(amount: int, _from: Vector3, headshot: bool) -> void:
		got["hits"].append([amount, headshot])
		c2.report_damage(roundi(amount * 0.75)))
	c1.shot_confirmed.connect(func(headshot: bool, amount: int, _pos: Vector3) -> void:
		got["confirmed"].append(headshot)
		got["shown"] = got.get("shown", []) + [amount])
	c1.damage_shown.connect(func(amount: int, _headshot: bool, _pos: Vector3) -> void:
		got["after_armor"] = got.get("after_armor", []) + [amount])
	for client in [c1, c2]:
		client.kill_feed.connect(func(killer: String, victim: String, mine: bool, ours: bool) -> void:
			got["feed"].append(["%s>%s" % [killer, victim], mine, ours]))
	c1.kill_confirmed.connect(func(target: String) -> void:
		got["kills"] += 1
		got["target"] = target)
	c1.go_online("localhost:19082", "Shooter")
	c2.go_online("localhost:19082", "Target")
	await _until(func() -> bool: return c1.is_client() and c2.is_client() and c1.party_code != "" and c2.party_code != "")
	c1.set_queued(true)
	c2.set_queued(true)
	await _until(func() -> bool: return c1.in_raid and c2.in_raid)
	var world: RaidWorld = server._worlds.values()[0] if not server._worlds.is_empty() else null
	_check(world != null and world.get_node_or_null("Main/Level") != null and world.get_node_or_null("Main/Player") == null,
		"each online raid gets its own copy of the map on the server (map only)")
	# (Only the players' shots here: the raid's AI hitting the target made the hit list flaky.)
	if world != null:
		for connection in world.player_hit.get_connections():
			world.player_hit.disconnect(connection["callable"])
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
	c1.send_shot(Vector3(0, 1.5, -4), PackedVector3Array([(Vector3(0, 0.8, -10) - Vector3(0, 1.5, -4)).normalized()]), "ak")
	await _until(func() -> bool: return not got["hits"].is_empty())
	_check(got["hits"] == [[28, false]] and got["confirmed"] == [false], "an AK body shot hits the other player for 28 (%s)" % str(got["hits"]))
	await _until(func() -> bool: return got.has("after_armor"))
	_check(got.get("shown", []) == [0] and got.get("after_armor", []) == [21],
		"online, the shooter's damage number is what the hit did after the target's armor (0.17.1: %s)" % str(got.get("after_armor", [])))
	await _until(func() -> bool: return not got["heard"].is_empty())
	_check(got["heard"] == ["ak"], "the other player hears the shot (0.15.28: %s)" % str(got["heard"]))
	await _frames(4)
	OS.delay_msec(60)
	c1.send_shot(Vector3(0, 1.5, -4), PackedVector3Array([(Vector3(0, 1.75, -10) - Vector3(0, 1.5, -4)).normalized()]), "ak")
	await _until(func() -> bool: return got["hits"].size() >= 2)
	_check(got["hits"].size() == 2 and got["hits"][1] == [56, true], "a headshot does double (%s)" % str(got["hits"]))
	OS.delay_msec(60)
	c1.send_shot(Vector3(0, 1.5, -4), PackedVector3Array([Vector3(1, 0, 0)]), "ak")
	OS.delay_msec(60)
	c1.send_shot(Vector3(0, 1.5, -4), PackedVector3Array([(Vector3(0, 0.8, -10) - Vector3(0, 1.5, -4)).normalized()]), "gold_watch")
	OS.delay_msec(60)
	c1.send_shot(Vector3(30, 1.5, -4), PackedVector3Array([Vector3(0, 0, -1)]), "ak")
	await _frames(20)
	_check(got["hits"].size() == 2, "misses, non-weapons and shots from somewhere else don't count")

	# Walls block shots (the north wall at z = 40.5).
	await stand.call(c2, Vector3(0, 0.1, 43))
	await stand.call(c1, Vector3(0, 0.1, 38))
	OS.delay_msec(60)
	c1.send_shot(Vector3(0, 1.5, 38), PackedVector3Array([Vector3(0, -0.05, 1).normalized()]), "ak")
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
	c1.send_shot(Vector3(0, 1.5, -4), PackedVector3Array([(Vector3(0, 0.8, -10) - Vector3(0, 1.5, -4)).normalized()]), "pistol")
	await _until(func() -> bool: return got["hits"].size() >= 3)
	_check(got["hits"].size() == 3 and got["hits"][2] == [17, false], "pistol body shot: 17")
	# The new guns online (0.15.17): Wasp and Lancer body shots, a Lancer headshot.
	var head_dir := (Vector3(0, 1.75, -10) - Vector3(0, 1.5, -4)).normalized()
	var body_dir := (Vector3(0, 0.8, -10) - Vector3(0, 1.5, -4)).normalized()
	for shot: Array in [["smg", body_dir], ["sniper", body_dir], ["sniper", head_dir]]:
		OS.delay_msec(60)
		var n: int = got["hits"].size()
		c1.send_shot(Vector3(0, 1.5, -4), PackedVector3Array([shot[1]]), shot[0])
		await _until(func() -> bool: return got["hits"].size() > n)
	_check(got["hits"].slice(3, 6) == [[20, false], [90, false], [180, true]],
		"online: Wasp body 20, Lancer body 90, Lancer headshot 180 (%s)" % str(got["hits"].slice(3, 6)))
	# A shotgun's pellets (0.15.2): all of them that hit add up into one hit; more pellets than it fires don't count.
	var chest := (Vector3(0, 0.8, -10) - Vector3(0, 1.5, -4)).normalized()
	var too_many := PackedVector3Array()
	too_many.resize(9)
	too_many.fill(chest)
	OS.delay_msec(60)
	c1.send_shot(Vector3(0, 1.5, -4), too_many, "shotgun")
	OS.delay_msec(60)
	too_many.resize(8)
	c1.send_shot(Vector3(0, 1.5, -4), too_many, "shotgun")
	await _until(func() -> bool: return got["hits"].size() >= 7)
	_check(got["hits"].size() == 7 and got["hits"][6] == [8 * 14, false], "8 shotgun pellets up close: one hit of 112 (%s)" % str(got["hits"]))
	c2.send_state([Vector3(0, 0.1, -10), 0.0, 0.0, 0.0, RemotePlayer.FLAG_DEAD])
	await _until(func() -> bool: return got["kills"] == 1)
	_check(got["kills"] == 1 and got.get("target") == "player", "the killer is told about the kill (and that it was a player)")
	# The kill feed (0.18.9): everyone in the raid is told who killed whom, each from their own side.
	await _until(func() -> bool: return got["feed"].size() >= 2)
	var feed_lines: Array = got["feed"]
	_check(feed_lines.size() == 2 and feed_lines[0][0] == "Shooter>Target" and feed_lines[0][1] != feed_lines[1][1]
		and feed_lines[0][2] != feed_lines[1][2],
		"the kill feed goes to the whole raid, marked for the killer and the one who died (%s)" % [feed_lines])
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
	c1.shot_confirmed.connect(func(_h: bool, _amount: int, _pos: Vector3) -> void: got["confirmed"] += 1)
	c1.kill_confirmed.connect(func(_target: String) -> void: got["kills"] += 1)
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
	var sounds_before := main.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer3D).size()
	net_raid.on_player_fired(5, Vector3(0, 1.5, -4), Vector3(0, 1.5, -20), "smg", true)
	net_raid.on_player_fired(5, Vector3(0, 1.5, -4), Vector3(0, 1.5, -20), "not_a_gun", false)
	_check(main.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer3D).size() == sounds_before + 1,
		"another player's shot plays where they stand (0.15.28)")
	net_raid.sync_enemies(c1.enemies)
	var puppet: Scav = net_raid.enemy_puppets.values()[0]
	_check(net_raid.enemy_puppets.size() == 3 and puppet.puppet and puppet.is_in_group("enemies"), "the raid shows the 3 scavs as puppets")
	var same_gun := true
	for e: Scav in scavs1:
		var copy: Scav = net_raid.enemy_puppets.get(e.get_instance_id())
		same_gun = same_gun and copy != null and copy.carried_gun == e.carried_gun and copy.shot_sound == e.shot_sound and copy.shot_damage == e.shot_damage
	_check(same_gun, "each puppet carries, sounds and shoots like its server scav's real gun")
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
	# (0.16.9, owner: a friend took no damage from scav bursts online) A server scav's real shots hit the proxy.
	var shooter: Node = scavs1[1]
	shooter.global_position = proxy.global_position + Vector3(0, 0, 8)
	shooter.accuracy_near = 1.0
	shooter.accuracy_far = 1.0
	shooter.point_blank_accuracy = 1.0
	shooter.moving_target_penalty = 0.0
	shooter._target = proxy
	await _frames(2)
	var hits_before: int = got["hits"].size()
	for i in 5:
		shooter._fire_at_target(8.0)
	await _until(func() -> bool: return got["hits"].size() >= hits_before + 5)
	_check(got["hits"].size() - hits_before == 5, "online, a server scav's shots hit the player (%d of 5)" % (got["hits"].size() - hits_before))

	# Players' shots hit server scavs (and make noise they hear).
	var target: Node3D = scavs1[0]
	# (Held still where it is, shot from whichever side has a clear line: a fighting scav can end up by a wall.)
	target.process_mode = Node.PROCESS_MODE_DISABLED
	w1.enemy_history.clear()   # (where it walked a moment ago doesn't count: it stands here now)
	var side := Vector3(0, 0, 6)
	for try_side: Vector3 in [Vector3(0, 0, 6), Vector3(0, 0, -6), Vector3(6, 0, 0), Vector3(-6, 0, 0)]:
		var probe := PhysicsRayQueryParameters3D.create(target.global_position + try_side + Vector3(0, 1.5, 0), target.global_position + Vector3(0, 0.8, 0), 1)
		if w1.find_world_3d().direct_space_state.intersect_ray(probe).is_empty():
			side = try_side
			break
	for i in 3:
		c1.send_state([target.global_position + side, 0.0, 0.0, 0.0, 0])
		await _frames(2)
	# (States go unreliably: wait until the server has us standing there, or it rejects the shot's origin.)
	var stand_at: Vector3 = target.global_position + side
	await _until(func() -> bool:
		c1.send_state([stand_at, 0.0, 0.0, 0.0, 0])
		return server._player_states.has(c1_id) and (server._player_states[c1_id][0] as Vector3).distance_to(stand_at) < 0.1)
	var before: int = target.health.current
	OS.delay_msec(60)
	var eye := target.global_position + side + Vector3(0, 1.5, 0)
	c1.send_shot(eye, PackedVector3Array([(target.global_position + Vector3(0, 0.8, 0) - eye).normalized()]), "ak")
	await _until(func() -> bool: return got["confirmed"] >= 1)
	_check(got["confirmed"] == 1 and target.health.current < before, "a player's shot hits a server scav (%d -> %d)" % [before, target.health.current])
	# (0.15.28) Shots at AI are checked where the shooter saw them, like players: a moving AI isn't missed.
	var t_now: float = server._now()
	var start := target.global_position
	w1.enemy_history.clear()
	w1.record_enemies(t_now - 0.3)
	target.global_position = start + Vector3(3, 0, 0)
	w1.record_enemies(t_now)
	var eye2 := start + side + Vector3(0, 1.5, 0)
	var aim := (start + Vector3(0, 0.8, 0) - eye2).normalized()
	var seen_then := w1.trace_shot(c1_id, eye2, aim, 50.0, t_now - 0.3, t_now)
	var seen_now := w1.trace_shot(c1_id, eye2, aim, 50.0, t_now, t_now)
	_check(seen_then.get("enemy") == target and not seen_now.has("enemy") and target.global_position.is_equal_approx(start + Vector3(3, 0, 0)),
		"a shot at a moving AI counts where the shooter saw it (then %s, now %s)" % [str(seen_then.keys()), str(seen_now.keys())])
	target.global_position = start
	target.process_mode = Node.PROCESS_MODE_INHERIT
	w1.enemy_history.clear()
	var allowed := 0
	for i in 4:
		allowed += 1 if server._spend_shot(777, 900.0) else 0
	_check(allowed == 4 and not server._spend_shot(777, 900.0), "shots that arrive bunched up all count; an impossible rate doesn't")
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
		got[c] = {"opened": {}, "busy": [], "bags": {}, "gone": [], "lids": []}
		c.lid_moved.connect(func(id: String, open: bool) -> void: got[c]["lids"].append([id, open]))
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
	c1.drop_items([["phone", 1, 0, 0, false, 0]])
	await _frames(6)
	_check(got[c2]["bags"].size() == 1, "a second drop goes on the same pile online")
	c2.open_container(drop_id)
	await _until(func() -> bool: return got[c2]["opened"].has(drop_id))
	_check(got[c2]["opened"][drop_id][2].size() == 2 and got[c2]["opened"][drop_id][2][0][0] == "bandage", "the other player can loot it")
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
	# PMC dog tag (0.15.28, owner): only on a player killed by another player, named, in its own slot.
	_check(not rival_body.gear.has(LootContainer.TAG_SLOT), "a player who wasn't killed by a player leaves no dog tag")
	var c1_peer: int = c1.multiplayer.get_unique_id()
	var c2_peer: int = c2.multiplayer.get_unique_id()
	server._last_attacker[c2_peer] = [c1_peer, server._now()]
	var bodies_before: int = got[c1]["bags"].size()
	c2.drop_items([["bandage", 1, 0, 0, false, 0]], true)
	await _until(func() -> bool: return got[c1]["bags"].size() > bodies_before)
	var tagged := world.container(got[c1]["bags"].keys()[-1])
	var tag_stack: ItemStack = tagged.gear[LootContainer.TAG_SLOT].stacks[0] if tagged != null and tagged.gear.has(LootContainer.TAG_SLOT) and not tagged.gear[LootContainer.TAG_SLOT].is_empty() else null
	_check(tag_stack != null and tag_stack.id == "player_tag" and tag_stack.title() == "Rival's Dog Tag",
		"killed by another player: \"Rival's Dog Tag\" in the body's own Dog Tag slot")
	var copy := LootContainer.new()
	copy.grid = GridInventory.new("Pockets", 4, 3)
	copy.load_net_data(tagged.net_data())
	_check(copy.gear.has(LootContainer.TAG_SLOT) and copy.gear[LootContainer.TAG_SLOT].stacks[0].title() == "Rival's Dog Tag"
		and not copy.gear[LootContainer.TAG_SLOT].fits("bandage", 0, 0, false), "the tag slot and name go over the network; the slot only takes a dog tag")
	copy.free()
	var saved := ItemStack.new("player_tag")
	saved.label = "Rival"
	_check(Profile._read_stack(Profile._write_stack(saved)).title() == "Rival's Dog Tag", "a dog tag keeps its name in your stash")

	# A Raider's body on the server: announced to everyone. A scav in a backpack leaves only the backpack (0.17.12).
	var raider: Node = null
	var scav: Node = null
	for enemy: Node in RaidScope.nodes(world.raid, &"enemies"):
		if enemy.has_node("Model/Backpack"):
			scav = enemy
		elif raider == null:
			raider = enemy
	if raider != null:
		var body_name: String = raider.body_name
		raider.health.take_damage(9999)
		await _until(func() -> bool: return got[c1]["bags"].values().has(body_name))
		_check(got[c1]["bags"].values().has(body_name), "an AI without a backpack killed on the server leaves a body for everyone")
	_check(scav != null, "the test raid has a scav in a backpack")
	if scav != null:
		var bags_before: int = got[c2]["bags"].size()
		var scav_body: String = scav.body_name
		scav.health.take_damage(9999)
		await _until(func() -> bool: return got[c2]["bags"].size() > bags_before)
		await _frames(10)
		var pack_id: Variant = got[c2]["bags"].find_key(scav_body)
		_check(pack_id != null and scav_body in LootContainer.BACKPACK_BODIES and got[c2]["bags"].size() == bags_before + 1,
			"a scav killed on the server leaves one body, shown as its backpack (%d new bags)" % (got[c2]["bags"].size() - bags_before))
		if pack_id != null:
			c1.open_container(pack_id)
			await _until(func() -> bool: return got[c2]["lids"].has([pack_id, true]))
			c1.close_container()
			await _until(func() -> bool: return got[c2]["lids"].has([pack_id, false]))
			_check(got[c2]["lids"] == [[pack_id, true], [pack_id, false]], "the other player sees its flap open and shut (0.17.10)")

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


func _section_leave_raid() -> void:
	# LEAVE RAID in the pause menu (0.14.24, owner): asks first, then counts as dying. On a fresh raid scene.
	var raid_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(raid_scene)
	raid_scene.get_node("HUD").process_mode = Node.PROCESS_MODE_DISABLED
	paused = false
	await _frames(3)
	var hud = raid_scene.get_node("HUD")
	var leaver: Player = raid_scene.get_node("Player")
	var leave_raid: Raid = raid_scene.get_node("Raid")
	_check(hud.leave_button.get_index() == hud.play_button.get_index() + 1 and hud.leave_button.visible and not hud.leave_confirm.visible,
		"the pause menu has LEAVE RAID under PLAY")
	hud.leave_button.pressed.emit()
	_check(not hud.leave_button.visible and hud.leave_confirm.visible and leave_raid.result == "", "LEAVE RAID asks first")
	var confirm_buttons := {}
	for button: Button in hud.leave_confirm.find_children("*", "Button", true, false):
		confirm_buttons[button.text] = button
	confirm_buttons["STAY"].pressed.emit()
	_check(hud.leave_button.visible and not hud.leave_confirm.visible and leave_raid.result == "" and not leaver.is_dead, "STAY keeps you in the raid")
	var deaths: int = Profile.stats["deaths"]
	hud.ask_leave()
	confirm_buttons["LEAVE"].pressed.emit()
	_check(leave_raid.result == "left" and leaver.is_dead and Profile.stats["deaths"] == deaths + 1, "LEAVE counts as dying")
	_check(hud.end_screen.visible and hud.end_screen.summary()["stamp"] == "LEFT THE RAID", "the end screen says you left (%s)" % hud.end_screen.summary()["stamp"])
	raid_scene.queue_free()
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
	_check(map.get_node_or_null("KeyDoors/BunkerDoor") is KeyDoor and map.get_node("KeyDoors/BunkerDoor").key == "bunker_key"
		and map.get_node_or_null("KeyDoors/BankVaultDoor") is KeyDoor and map.get_node("KeyDoors/BankVaultDoor").key == "bank_vault_key",
		"locked doors at the bunker and the bank vault, with their keys (0.14.0)")
	var doors := map.get_node("Doors").get_children()
	var clash := doors.filter(func(d: Node3D) -> bool:
		return d.position.distance_to(map.get_node("KeyDoors/BankVaultDoor").position) < 1.0)
	_check(doors.size() > 50 and doors.all(func(d: Node) -> bool: return d is Door) and clash.is_empty(),
		"%d doors in the inner doorways, none on top of a key door (0.17)" % doors.size())
	var wrecks := doors.filter(func(d: Door) -> bool: return d.broken != "")
	_check(wrecks.size() > 10 and doors.size() - wrecks.size() > 50
		and wrecks.any(func(d: Door) -> bool: return d.broken == "fallen")
		and wrecks.any(func(d: Door) -> bool: return d.broken == "hanging"),
		"%d of them wrecked (lying on the floor or hanging off), the rest work (round 3)" % wrecks.size())
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
	# The map's edge (outdoor step 9): the wall is collision only now (a border fence, the land outside and its forest
	# are looks), but it still stops everyone. Rays out across the edge at walking and jumping height hit it, and the
	# AI's walkable area stays inside.
	var edge_map := RaidScope.nodes(world.raid, &"box_maps")[0] as BoxMap
	var edge_space := edge_map.get_world_3d().direct_space_state
	var open_edge := []
	for k in 28:
		var t := -170.0 + k * 340.0 / 27.0
		for out: Vector3 in [Vector3(t, 0, -175), Vector3(t, 0, 175), Vector3(-175, 0, t), Vector3(175, 0, t)]:
			var inward := -Vector3(signf(out.x) if absf(out.x) == 175.0 else 0.0, 0, signf(out.z) if absf(out.z) == 175.0 else 0.0)
			var from := out + inward * 4.0
			if is_nan(edge_map.ground_height(from)):   # (over a hole: the waterfall's room, walled all round)
				continue
			for lift: float in [1.0, 3.5]:
				var a := Vector3(from.x, edge_map.ground_height(from) + lift, from.z)
				var hit := edge_space.intersect_ray(PhysicsRayQueryParameters3D.create(a, a - inward * 10.0, 1))
				if hit.is_empty():
					open_edge.append(Vector2(out.x, out.z))
	var nav_out := NavigationServer3D.map_get_closest_point(nav_map, Vector3(-200, 0, 0)).x < -175.5 \
		or NavigationServer3D.map_get_closest_point(nav_map, Vector3(200, 0, 40)).x > 175.5 \
		or NavigationServer3D.map_get_closest_point(nav_map, Vector3(30, 0, -200)).z < -175.5 \
		or NavigationServer3D.map_get_closest_point(nav_map, Vector3(-40, 0, 200)).z > 175.5
	_check(open_edge.is_empty() and not nav_out,
		"the map's edge still stops players and the AI all the way round (open at %s)" % [open_edge])
	# Far view (outdoor step 10): every building model has a far version (tools/far_bake.gd; re-bake after rebuilding one).
	var no_far := []
	for file in DirAccess.get_files_at(FarView.MODELS):
		if file.ends_with(".glb"):
			var far := FarView.FAR + file.get_basename() + ".res"
			if not FileAccess.file_exists(far):
				no_far.append(file.get_basename())
	_check(no_far.is_empty(), "every building has a far version (run tools/far_bake.gd for %s)" % [no_far])
	# Nobody starts under the hills (0.12.35, owner's screenshot): squadmates stand off to the side of a spawn marker,
	# where the slope can be higher; they're lifted onto the ground. And anyone who ends up under it gets put back on
	# top, but not someone down in the bunker (it has its own ceiling).
	var ground_map := RaidScope.nodes(world.raid, &"box_maps")[0] as BoxMap
	var map_copy := (load(MAP) as PackedScene).instantiate()
	var spawn_node := map_copy.get_node("PlayerSpawns")
	map_copy.remove_child(spawn_node)
	map_copy.free()
	world.raid.add_child(spawn_node)   # (a server raid has no player spawns of its own)
	var markers := spawn_node.get_children()
	var under := []
	for slot in markers.size() * 2:
		for place in 4:
			var at := BoxMap.above_ground(ground_map, Raid.spawn_position(markers, slot, place), 0.0)
			if at.y < ground_map.ground_height(at) - 0.02:
				under.append("%d/%d" % [slot, place])
	_check(under.is_empty(), "no squad spawn spot is under the ground (%s)" % [under])
	var sunk := Vector3(-150.0, 0.0, 120.0)
	sunk.y = ground_map.ground_height(sunk) - 1.5
	var bunker := Vector3(-60.0, 0.0, -24.0)
	var floor_hit := ground_map.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(bunker.x, ground_map.ground_height(bunker) - 1.6, bunker.z), Vector3(bunker.x, -20.0, bunker.z), 1))
	bunker.y = (floor_hit.position as Vector3).y + 0.1 if not floor_hit.is_empty() else 0.0
	_check(BoxMap.above_ground(ground_map, sunk).y > sunk.y + 1.0 and BoxMap.above_ground(ground_map, bunker) == bunker
		and bunker.y < ground_map.ground_height(bunker) - 2.0,
		"someone stuck under the ground is put back on top, but not someone down in the bunker (floor %.1f)" % bunker.y)
	spawn_node.queue_free()
	# Every container (upstairs, in the bunker, in the bank vault) can be walked to from a spawn: the AI's paths
	# go there too (ramps, doorways and stair landings wide enough for them).
	var unreachable: Array[String] = []
	var query := NavigationPathQueryParameters3D.new()
	query.map = nav_map
	query.start_position = start
	query.path_search_max_polygons = 0  # (as the scavs do: a path across the whole map)
	for c: Node3D in loot:
		# (A searchable prop of a building's model, 0.18.4, may face any way: one of its sides will do.)
		var size: Vector3 = c.get_meta("prop", Vector3.ZERO)
		var fronts := [c.global_basis.z * -1.3]
		if c.has_meta("prop"):
			fronts = [c.global_basis.z * -(size.z / 2 + 0.6), c.global_basis.z * (size.z / 2 + 0.6),
				c.global_basis.x * (size.x / 2 + 0.6), c.global_basis.x * -(size.x / 2 + 0.6)]
		var reached := false
		for offset: Vector3 in fronts:
			var front: Vector3 = c.global_position + offset + Vector3.UP * 0.4
			query.target_position = front
			var result := NavigationPathQueryResult3D.new()
			NavigationServer3D.query_path(query, result)
			var path := result.path
			reached = reached or not (path.is_empty() or path[path.size() - 1].distance_to(front) > (2.0 if c.has_meta("prop") else 1.3))
		# (The east woods cabin's loft is up a ladder, which the AI doesn't climb.)
		var loft := String(c.get_meta("place", "")) == "Cabin3" and c.global_position.y > ground_map.ground_height(c.global_position) + 2.0
		if reached == c.has_meta("locked") and not loft:
			unreachable.append(String(c.name))
	_check(unreachable.is_empty(), "every loot container can be walked to, except behind the shut key doors (wrong: %s)" % [unreachable])
	var locked := loot.filter(func(c: Node) -> bool: return c.has_meta("locked"))
	_check(locked.size() == 8, "8 containers behind the bunker and bank vault doors (%d)" % locked.size())
	# The waterfall's secret room (World art 0.17): two safes behind the falling water, which has no collision (you
	# walk through it; the reach check above walks the AI's path in through the doorway).
	var cave := loot.filter(func(c: Node) -> bool: return String(c.get_meta("place", "")) == "Waterfall")
	var sheet := world.raid.find_child("WaterfallSheet", true, false)
	_check(cave.size() == 2 and cave.all(func(c: Node) -> bool: return c is LootContainer and c.get("loot_table") == "safe")
		and sheet is MeshInstance3D and sheet.get_child_count() == 0,
		"the waterfall room has two safes behind walk-through falling water (%d)" % cave.size())
	# 0.18.4 (owner: "anything that looks lootable should be lootable"): the drawers, cabinets, trunks, lockers and
	# crates the building models draw can be searched: each rolls loot, and looking at it finds it (not the wall of
	# the map's own box for it).
	var props := loot.filter(func(c: Node) -> bool: return c.has_meta("prop"))
	var not_found: Array[String] = []
	for c: LootContainer in props:
		var size: Vector3 = c.get_meta("prop")
		var found := false
		var mid: Vector3 = c.global_position + Vector3.UP * size.y * 0.6
		# (From above, or from in front or behind: something may stand on it, a lamp, a TV, wreckage.)
		for offset: Vector3 in [Vector3.UP * (size.y * 0.4 + 0.4), c.global_basis.z * (size.z / 2 + 0.5),
				c.global_basis.z * -(size.z / 2 + 0.5)]:
			var hit: Dictionary = world.raid.get_world_3d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters3D.create(mid + offset, mid, 1 | 8))
			found = found or (not hit.is_empty() and hit.collider == c)
		if not found or c.grid.is_empty() or c.display_name == "Crate":
			not_found.append(String(c.name))
	_check(props.size() >= 100 and not_found.is_empty(),
		"%d searchable props roll loot and are found by a look (wrong: %s)" % [props.size(), not_found])
	# Breakable windows (0.18.8, owner): the panes still glazed are the map's, not the models'; a shot through one
	# breaks it and carries on, and a broken one no longer stops anyone.
	var glass := world.raid.get_node("Level/Blocks") as BoxMap
	var panes := glass.panes()
	var pane_body := glass.get_node_or_null("Windows") as StaticBody3D
	var pane_at := glass._pane_transform(0)
	var ahead := pane_at.origin + pane_at.basis.z * 2.0
	var panes_space: PhysicsDirectSpaceState3D = world.raid.get_world_3d().direct_space_state
	var before: Dictionary = panes_space.intersect_ray(PhysicsRayQueryParameters3D.create(
		ahead, pane_at.origin - pane_at.basis.z * 2.0, BoxMap.WINDOW_LAYER))
	var broke := BoxMap.break_window_along(glass, ahead, pane_at.origin - pane_at.basis.z * 2.0, false)
	var after: Dictionary = panes_space.intersect_ray(PhysicsRayQueryParameters3D.create(
		ahead, pane_at.origin - pane_at.basis.z * 2.0, BoxMap.WINDOW_LAYER))
	# (Shots: the glass is only on its own layer, which no shot checks. A ray test here could meet a scav walking by.)
	var shot_through := pane_body != null and pane_body.collision_layer == BoxMap.WINDOW_LAYER
	_check(panes >= 60 and pane_body != null and not before.is_empty() and broke == 0 and after.is_empty()
		and not glass.pane_whole(0) and shot_through and glass.break_pane(0) == false,
		"%d window panes: one breaks once, then lets you through; shots never stopped by glass (%s)" % [panes,
		[not before.is_empty(), broke, after.is_empty(), shot_through]])
	# The server breaks a pane for the whole raid (online), and sends it on.
	var broken_sent := []
	world.window_broken.connect(func(pane: int) -> void: broken_sent.append(pane))
	world.break_window(1)
	world.break_window(1)
	_check(broken_sent == [1] and not glass.pane_whole(1), "the server breaks a pane once and tells the raid (%s)" % [broken_sent])
	# The ghost cloth over the bunker ramp (0.18.6, owner): it fades once someone goes through it.
	var cloth := world.raid.find_child("GhostCloth", true, false) as GhostCloth
	var walker := CharacterBody3D.new()
	walker.collision_layer = 2
	var walker_shape := CollisionShape3D.new()
	walker_shape.shape = CapsuleShape3D.new()
	walker.add_child(walker_shape)
	world.raid.add_child(walker)
	walker.global_position = cloth.global_position + Vector3(0, 30, 0) if cloth != null else Vector3.ZERO
	await physics_frame
	await physics_frame
	var untouched := cloth != null and not cloth.tripped and not cloth._runner().is_empty()
	walker.global_position = cloth.global_position if cloth != null else Vector3.ZERO
	for i in 3:
		await physics_frame
	var runner: Array = cloth._runner() if cloth != null else []
	_check(untouched and cloth.tripped and runner[0].get_surface_override_material(runner[1]) != null,
		"the ghost cloth over the bunker ramp fades once someone goes through it")
	walker.queue_free()
	# Online the server's copy of the map has the doors too; a player unlocking one opens it there and tells the raid.
	var opened := []
	world.door_opened.connect(func(id: String) -> void: opened.append(id))
	world.open_door("BunkerDoor")
	world.open_door("BunkerDoor")
	world.open_door("../Loot")
	var server_door := world.raid.get_node_or_null("KeyDoors/BunkerDoor") as KeyDoor
	_check(server_door != null and server_door.is_open and opened == ["BunkerDoor"], "the server opens a key door once and tells the raid (%s)" % [opened])
	var swung := []
	world.door_changed.connect(func(id: String, state: int) -> void: swung.append([id, state]))
	world.set_door("Door1", 1)
	world.set_door("Door1", 1)
	world.set_door("../Loot", 1)
	var server_swing := world.raid.get_node_or_null("Doors/Door1") as Door
	_check(server_swing != null and server_swing.state == 1 and swung == [["Door1", 1]],
		"the server swings a door a player opened and tells the raid once (%s)" % [swung])
	world.throw_grenade(Vector3(0, 40, 0), Vector3.ZERO)
	var server_nade := world.raid.get_children().filter(func(n: Node) -> bool: return n is Grenade)
	_check(server_nade.size() == 1 and server_nade[0].deals_damage, "a player's grenade flies in the server's raid, and does the damage there")
	# Hills (0.11.17): the ground rolls, the AI can still walk from a spawn to every AI spawn point over it, and
	# spawns and extracts stand on the ground (not floating over a hollow or buried in a hill).
	var blocks := world.raid.get_node("Level/Blocks") as BoxMap
	# 0.18.3 (owner: hitboxes didn't match the models; bushes stopped shots; barred windows were jumpable): boulders,
	# banks, crater rims and the train collide as drawn, every bush is walk-through, barred windows have their boxes.
	var solid_bushes := 0
	for i in range(0, blocks.boxes.size(), BoxMap.STRIDE):
		if blocks.colors[int(blocks.boxes[i + 8])].is_equal_approx(BoxMap.BUSH_COLOUR) and int(blocks.boxes[i + 9]) in [1, 2]:
			solid_bushes += 1
	_check(blocks.shaped_indices.size() > 3000 and blocks.bar_boxes.size() >= 7 * 10 and solid_bushes == 0,
		"the map collides as drawn (%d shaped triangles, %d barred windows, %d solid bushes)"
		% [blocks.shaped_indices.size() / 3, blocks.bar_boxes.size() / 7, solid_bushes])
	# 0.19.8/0.19.9 (owner: "i cannot shoot through these cracks in the bus stop, stuff like this needs to be fixed"):
	# the station square's bus shelter lets shots through its missing pane and glass, not its kick plate, and still
	# stops people; car windows, gaps under tables and the like are the same (shot triangles inside people boxes).
	var shelter := Vector3(221.5 - 175.0, 0.0, 175.5 - 175.0 + 0.8)
	var shelter_space: PhysicsDirectSpaceState3D = world.raid.get_world_3d().direct_space_state
	var shelter_floor: float = shelter_space.intersect_ray(PhysicsRayQueryParameters3D.create(
		shelter + Vector3(0, 20, -2), shelter + Vector3(0, -20, -2), 1)).position.y
	var through := func(x: float, h: float, mask: int) -> bool:
		var a := Vector3(shelter.x + x, shelter_floor + h, shelter.z - 1.5)
		return shelter_space.intersect_ray(PhysicsRayQueryParameters3D.create(a, a + Vector3(0, 0, 3), mask)).is_empty()
	_check(through.call(1.0, 1.5, 1 | 4) and through.call(-1.0, 1.5, 1 | 4) and not through.call(1.0, 0.25, 1 | 4)
		and not through.call(1.0, 1.5, BoxMap.BARS_LAYER) and not through.call(-1.0, 1.5, BoxMap.BARS_LAYER),
		"the bus shelter: shots go through its missing pane and its glass, not its kick plate; people can't")
	_check(blocks.shot_indices.size() / 3 > 50000 and blocks.bar_boxes.size() / 7 > 400,
		"see-through pieces: %d shot triangles inside %d people-only boxes" % [blocks.shot_indices.size() / 3, blocks.bar_boxes.size() / 7])
	# 0.19.4 (owner: a friend vaulted into a dirt bank and was stuck inside it): no vault ends inside a bank, from any
	# side of the one he was at, and someone inside one is found and has a free spot to be put on.
	var vaulter := CharacterBody3D.new()
	vaulter.collision_layer = 2
	world.raid.add_child(vaulter)
	await physics_frame
	var bank := Vector3(-18.95, 0.0, 83.62)
	var bank_space := vaulter.get_world_3d().direct_space_state
	var vaults := 0
	var into := 0
	for gx in range(-14, 15):
		for gz in range(-14, 15):
			var at := bank + Vector3(gx, 0.0, gz) * 0.5
			var ground_hit := bank_space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 40.0, at + Vector3.DOWN * 40.0, 1))
			if ground_hit.is_empty() or BoxMap.inside_solid(vaulter, ground_hit.position + Vector3.UP * 0.3):
				continue
			vaulter.global_position = ground_hit.position
			for k in 8:
				var move := Vault.plan(vaulter, Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0)), 0.4, 1.8, 1.2, 0.7)
				if move.is_empty():
					continue
				vaults += 1
				var path: PackedVector3Array = move["path"]
				if [0.7, 0.85, 1.0].any(func(t: float) -> bool: return BoxMap.inside_solid(vaulter, Vault.position_at(path, t) + Vector3.UP * 0.6)):
					into += 1
	var bank_top := bank_space.intersect_ray(PhysicsRayQueryParameters3D.create(bank + Vector3.UP * 40.0, bank, 1))
	var buried: Vector3 = bank_top.position + Vector3.DOWN * 0.5
	var freed := BoxMap.free_spot(vaulter, buried, 0.4, 1.8)
	_check(into == 0 and BoxMap.inside_solid(vaulter, buried) and freed != buried
		and not BoxMap.inside_solid(vaulter, freed + Vector3.UP * 0.3),
		"no vault ends inside the dirt bank (%d vaults, %d inside); someone inside it gets a free spot" % [vaults, into])
	vaulter.queue_free()
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
	# Every AI spawn spot is on a floor with head room (0.12.38, owner: scavs spawned with their heads in the ceiling).
	var cramped: Array[String] = []
	for m in spawner.get_children():
		if not m is Marker3D or m.get_meta("perch", false):
			continue
		var p: Vector3 = (m as Marker3D).global_position
		var down: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 3.0, 1))
		var floor_y: float = (down.position as Vector3).y if not down.is_empty() else -INF
		var up: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, floor_y + 0.05, p.z), Vector3(p.x, floor_y + 2.2, p.z), 1))
		if p.y - floor_y > 0.4 or not up.is_empty():
			cramped.append("%s %.1f m up, ceiling %s" % [m.name, p.y - floor_y, "%.1f" % ((up.position as Vector3).y - floor_y) if not up.is_empty() else "ok"])
	_check(cramped.is_empty(), "every AI spawn spot is on a floor with head room (%s)" % [cramped])
	var strays := 0
	for e: Scav in zoned:
		if Vector2(e.global_position.x - e.home_center.x, e.global_position.z - e.home_center.z).length() > e.home_radius + 3.0:
			strays += 1
		for i in 4:
			var p := e._pick_patrol_point()
			# (Bon also stops just outside his building, up to 12 m past its edge: 0.12.36, owner)
			if Vector2(p.x - e.home_center.x, p.z - e.home_center.z).length() > e.home_radius + (12.5 if e.outside_patrol > 0.0 else 4.0):
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
	wader._glide_frame = 0   # (a far AI mid LOD glide would slide itself back)
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
	_check(numbers.size() == 1 and numbers[0].get_meta("label_text") == "28" and numbers[0].get_meta("label_critical") and not numbers[0] is Label3D,
		"a damage number is a HUD-drawn marker (a headshot: 28, its own colour, no \"!\")")
	_check(HealthHUD.stamina_color(1.0) == HealthHUD.STAMINA_HIGH and HealthHUD.stamina_color(0.4) == HudStyle.HAZARD
		and HealthHUD.stamina_color(0.1) == HudStyle.BLOOD, "the stamina bar goes green, yellow, red as it runs down")
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
	# The kill feed (0.18.9, owner): your kills show up in it, the oldest lines drop off, and they fade away.
	var feed: KillFeedHUD = hud_node.kill_feed
	feed._lines.clear()   # (earlier sections shot a scav or two)
	player.killed.emit("scav")
	player.killed.emit("boss")
	var two := feed.lines()
	for i in KillFeedHUD.MOST + 2:
		feed.add_kill("Someone", "Someone Else")
	var most := feed.lines().size()
	for line: Array in feed._lines:
		line[3] = 0.01
	feed._process(0.1)
	_check(two == PackedStringArray(["You killed Scav", "You killed Bon"]) and most == KillFeedHUD.MOST
		and feed.lines().is_empty(), "the kill feed shows your kills, keeps the last %d and fades them (%s)" % [KillFeedHUD.MOST, two])
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

	# Escape (0.13.9): closes the inventory back to playing (a "click to keep playing" hint, not the pause menu,
	# since a browser won't recapture the mouse on Escape); Escape again, or Escape while playing, is the pause menu.
	var hud := main.get_node("HUD")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	loot_ui.open_for(null)
	hud._input(escape)
	hud._process(0.0)
	_check(not loot_ui.visible and not hud.menu.visible and hud.resume_pending, "Escape closes the inventory, back to playing (no pause menu)")
	hud._input(escape)
	hud._process(0.0)
	_check(hud.menu.visible and not hud.resume_pending, "Escape again opens the pause menu")
	paused = false

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
	# 0.15.19 (owner): right-click has "Drop" (on the ground) while looting too.
	var watch: ItemStack = inv.find("gold_watch")[1]
	loot_ui.open_menu(inv.pockets, watch)
	var labels := []
	for i in loot_ui._menu.item_count:
		labels.append(loot_ui._menu.get_item_text(i))
	loot_ui._menu.hide()
	loot_ui.drop_to_ground(inv.pockets, watch)
	_check(labels.has("Drop") and labels.any(func(t: String) -> bool: return t.begins_with("Put in")) and inv.count_of("gold_watch") == 0
		and full.grid.count_of("gold_watch") == 0, "while looting, right-click offers Drop as well as Put in (%s)" % ", ".join(labels))
	# 0.16.10 (owner): drag an item out onto empty space to drop it; letting go on a panel keeps it.
	var corner := Vector2(4, 4)
	_check(not loot_ui._over_panels(corner) and loot_ui._over_panels(loot_ui._columns.get_global_rect().get_center()),
		"the screen corner is empty space, the middle of the inventory isn't")
	inv.pockets.add("gold_watch")
	var dragged: ItemStack = inv.find("gold_watch")[1]
	loot_ui.start_drag(inv.pockets, dragged, Vector2(GridView.CELL, GridView.CELL) * 0.5)
	var away := InputEventMouseMotion.new()
	away.position = root.get_screen_transform() * corner
	away.global_position = away.position
	Input.parse_input_event(away)
	Input.flush_buffered_events()
	loot_ui._update_drag()
	loot_ui._finish_drag()
	_check(inv.count_of("gold_watch") == 0, "dragging an item onto empty space drops it on the ground")
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
	# 0.12.36 (owner: indoors it lost you the moment you broke line of sight): nearby, it still knows where you are
	# for a few seconds after losing sight, and sees you again the moment you're in view.
	var track_home := player.global_position
	player.teleport_to(Vector3(30, 0.1, -30))
	await _frames(5)
	var tracker := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 12)) as Scav
	_face_player(tracker)
	tracker.shot_damage = 0
	await physics_frame
	tracker._alert(player.global_position)
	tracker._set_state(Scav.State.ENGAGE)
	await _frames(20)
	var wall := _block(player.global_position + Vector3(0, 1.5, 6), Vector3(10, 3, 0.5))
	await _frames(12)
	var moved_to := player.global_position + Vector3(4, 0, 0)
	player.teleport_to(moved_to)
	await _frames(30)
	_check(tracker._last_seen.distance_to(moved_to) < 0.5 and tracker._lost_sight_time > 0.0,
		"out of sight close by, it still knows where you went for a few seconds (%.1f m off, lost %.2f s)" % [tracker._last_seen.distance_to(moved_to), tracker._lost_sight_time])
	wall.queue_free()
	await _frames(12)
	_check(tracker._lost_sight_time == 0.0, "...and sees you again the moment you're in view")
	player.teleport_to(Vector3(30, 0.1, -30))
	tracker.queue_free()
	# Its first instinct in the open is to shoot, not run for cover (0.12.36, owner).
	var opener := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 40)) as Scav
	_face_player(opener)
	opener.shot_damage = 0
	opener.flank_chance = 0.0
	var opener_shots := [0]
	opener.fired.connect(func(_end: Vector3) -> void: opener_shots[0] += 1)
	await physics_frame
	opener._alert(player.global_position)
	var first_plan := Scav.Tactic.NONE
	var shots_before_moving := -1
	for i in 60 * 3:
		await physics_frame
		if first_plan == Scav.Tactic.NONE and opener.tactic != Scav.Tactic.NONE:
			first_plan = opener.tactic
		if shots_before_moving < 0 and opener._cover_phase == Scav.Cover.MOVING:
			shots_before_moving = opener_shots[0]
	_check(first_plan == Scav.Tactic.STAND and opener_shots[0] > 0 and shots_before_moving != 0,
		"out of chase range in the open it shoots first, cover after (%d shots before moving)" % shots_before_moving)
	opener.queue_free()
	# 0.17.9 (owner: a Raider ran off the moment it saw him): even a Raider set to always flank, and from far off,
	# opens fire before any flank or cover run.
	for far in [20.0, 50.0]:
		var raider_opener := _spawn(RAIDER_SCENE, player.global_position + Vector3(0, 0, far)) as Scav
		_face_player(raider_opener)
		raider_opener.shot_damage = 0
		raider_opener.flank_chance = 1.0
		raider_opener._since_threat = 100.0
		var r_shots := [0]
		raider_opener.fired.connect(func(_end: Vector3) -> void: r_shots[0] += 1)
		await physics_frame
		raider_opener._alert(player.global_position)
		var ran_at := -1
		var ran_away := false
		for i in 60 * 8:
			await physics_frame
			if ran_at < 0 and raider_opener._cover_phase in [Scav.Cover.MOVING, Scav.Cover.FLANKING]:
				ran_at = r_shots[0]
			if raider_opener.global_position.distance_to(player.global_position) > far + 3.0:
				ran_away = true
			if r_shots[0] > 0 and ran_at < 0:
				break
		_check(r_shots[0] > 0 and ran_at != 0 and not ran_away,
			"a Raider %d m off shoots first, never runs on first sight (%d shots, %d before a cover/flank run)" % [far, r_shots[0], ran_at])
		raider_opener.queue_free()
	# ...and from there it strafes to cover still shooting (0.12.37, owner), unlike other cover runs.
	var strafer := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 40)) as Scav
	_face_player(strafer)
	strafer.shot_damage = 0
	strafer.flank_chance = 0.0
	var _cover_spot := _block(strafer.global_position + Vector3(4, 1.0, 1.5), Vector3(1.5, 2.0, 1.5))
	var strafe_shots := [0]
	strafer.fired.connect(func(_end: Vector3) -> void:
		if strafer._cover_phase == Scav.Cover.MOVING:
			strafe_shots[0] += 1)
	await physics_frame
	strafer._alert(player.global_position)
	var strafed := false
	for i in 60 * 6:
		await physics_frame
		strafed = strafed or (strafer._cover_phase == Scav.Cover.MOVING and strafer._strafe_to_cover)
	_check(strafed and strafe_shots[0] > 0, "out in the open it strafes to cover still shooting (%d shots on the way)" % strafe_shots[0])
	strafer.queue_free()
	_cover_spot.queue_free()
	# On its way to cover and you come at it, or you show up after it lost you: it stops and fights (0.14.11, owner:
	# one kept repositioning while he walked right up to it).
	var runner := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 30)) as Scav
	_face_player(runner)
	runner.shot_damage = 0
	var runner_shots := [0]
	runner.fired.connect(func(_end: Vector3) -> void: runner_shots[0] += 1)
	await physics_frame
	runner._alert(player.global_position)
	runner._set_state(Scav.State.ENGAGE)
	var send_off := func() -> void:
		runner.tactic = Scav.Tactic.COVER
		runner._cover_point = runner.global_position + Vector3(20, 0, 10)
		runner._cover_phase = Scav.Cover.MOVING
		runner._strafe_to_cover = false
		runner._note_move_start()
	await _frames(12)
	send_off.call()
	await _frames(20)
	_check(runner._cover_phase == Scav.Cover.MOVING, "a cover run with you in view 30 m off carries on")
	player.teleport_to(runner.global_position + Vector3(0, 0, -8))
	await _frames(6)
	_check(runner._cover_phase != Scav.Cover.MOVING, "...but stops when you come up close")
	runner_shots[0] = 0
	await _frames(60 * 2)
	_check(runner_shots[0] > 0, "...and it shoots at you (%d shots)" % runner_shots[0])
	player.teleport_to(runner.global_position + Vector3(0, 0, -25))
	var blind := _block(runner.global_position + Vector3(0, 1.5, -3), Vector3(10, 3, 0.5))
	await _frames(12)
	send_off.call()
	await _frames(20)
	_check(runner._cover_phase == Scav.Cover.MOVING and runner._move_seen_from == INF, "a run that starts with you out of sight")
	blind.queue_free()
	await _frames(12)
	_check(runner._cover_phase != Scav.Cover.MOVING, "...stops when you show up in range")
	runner.queue_free()
	player.teleport_to(track_home)


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


func _section_bushes_bars() -> void:
	# Bushes (0.18.3, owner: all walk-through, but slower; they stopped the scavs' shots): people and bullets pass,
	# the AI can't see through them but its shots go through; inside one you're slower. Barred windows: they stop
	# people and vaulting, not bullets. A low ledge (0.25 m) is stepped onto without jumping.
	var map := BoxMap.new()
	map.colors = PackedColorArray([Color(0.5, 0.5, 0.5), BoxMap.BUSH_COLOUR])
	var spot := Vector3(40, 0, -40)   # (the vault test's flat ground: the ledge and the bars; the bush further on)
	var back := player.global_position
	player.teleport_to(spot + Vector3(0, 0.1, 8))
	await create_timer(0.2).timeout
	var bush := player.global_position + Vector3(0, 1.0, 5)
	map.boxes = PackedFloat32Array([bush.x, bush.y, bush.z, 4, 2, 1, 0, 0, 1, 3,
		spot.x, 0.125, spot.z + 3.0, 3, 0.25, 2, 0, 0, 0, 1])
	map.bar_boxes = PackedFloat32Array([spot.x + 4, 1.5, spot.z, 0.5, 1.4, 1.5, 0])
	main.add_child(map)
	var scav := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, 10)) as Scav
	_face_player(scav)
	scav.set_physics_process(false)
	scav._target = player
	scav.accuracy_near = 1.0
	scav.accuracy_far = 1.0
	await physics_frame
	await physics_frame
	var space := (main as Node3D).get_world_3d().direct_space_state
	var through := space.intersect_ray(PhysicsRayQueryParameters3D.create(bush + Vector3(0, 0, -3), bush + Vector3(0, 0, 3), 1 | 2 | 4))
	_check(through.is_empty() and map.get_node_or_null("BushLeaves") != null, "bushes don't block people or bullets")
	_check(scav._has_line_of_sight() and scav._leaves_in_way(), "the AI can't see you through a bush")
	var hp := player.health.current
	for i in 4:
		scav._fire_at_target(10.0)
	_check(player.health.current < hp, "...but its shots go through one (%d -> %d)" % [hp, player.health.current])
	scav.queue_free()
	player.health.heal(player.health.max_health)
	player.teleport_to(bush + Vector3(0, -0.9, 0))
	await create_timer(0.2).timeout
	var slow := player._target_velocity(Vector2(0, -1)).length()
	_check(BoxMap.in_bush(player), "standing in a bush counts as in it")
	player.teleport_to(spot + Vector3(0, 0.1, 0))
	await create_timer(0.2).timeout
	var fast := player._target_velocity(Vector2(0, -1)).length()
	_check(not BoxMap.in_bush(player) and slow < fast * 0.8, "slower in a bush (%.1f vs %.1f m/s)" % [slow, fast])
	# Bars: bullets through, people and vaulting not.
	var bar := spot + Vector3(4, 1.5, 0)
	_check(space.intersect_ray(PhysicsRayQueryParameters3D.create(bar + Vector3(-2, 0, 0), bar + Vector3(2, 0, 0), 1 | 4)).is_empty(),
		"bullets go through barred windows")
	_check(player.test_move(player.global_transform, Vector3(5, 0, 0)), "players can't walk through barred windows")
	# The ledge: walked onto.
	player.rotation.y = PI
	Input.action_press("move_forward")
	await create_timer(1.2).timeout
	Input.action_release("move_forward")
	_check(player.global_position.y > 0.2 and player.global_position.z > spot.z + 2.2,
		"a 25 cm ledge is stepped onto (at %s)" % player.global_position)
	map.queue_free()
	await physics_frame
	player.teleport_to(back)
	await create_timer(0.2).timeout


func _section_leaves() -> void:
	# Tree tops (0.17.13, owner: the AI shot through the leaves): people and bullets pass through them, but the AI
	# can't see or shoot through them.
	player.global_position = Vector3(40, 0.1, -25)   # (open ground, away from the target dummy)
	player.velocity = Vector3.ZERO
	await physics_frame
	var map := BoxMap.new()
	map.colors = PackedColorArray([Color(0.5, 0.5, 0.5), BoxMap.LEAVES_COLOUR])
	# A tree top between the player and the scav (center xyz, size xyz, yaw, pitch, colour, solid).
	var middle := player.global_position + Vector3(0, 1.5, -5)   # (behind the player: open road)
	map.boxes = PackedFloat32Array([middle.x, middle.y, middle.z, 4, 3, 1, 0, 0, 1, 0])
	main.add_child(map)
	var scav := _spawn(SCAV_SCENE, player.global_position + Vector3(0, 0, -10)) as Scav
	_face_player(scav)
	scav.set_physics_process(false)
	scav._target = player
	scav.accuracy_near = 1.0
	scav.accuracy_far = 1.0
	await physics_frame
	await physics_frame
	var through := get_root().get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(middle + Vector3(0, 0, -3), middle + Vector3(0, 0, 3), 1 | 2 | 4))
	_check(through.is_empty() and map.get_node_or_null("Leaves") != null, "leaves don't block people or bullets (%s)" % [through.get("collider")])
	_check(scav._has_line_of_sight() and scav._leaves_in_way(), "the AI can't see you through the leaves")
	var hp := player.health.current
	for i in 4:
		scav._fire_at_target(10.0)
		scav._fire_at_point(player.global_position + Vector3(0, 1.2, 0))
	_check(player.health.current == hp, "...or shoot you through them")
	map.queue_free()
	await physics_frame
	await physics_frame
	_check(scav._has_line_of_sight() and not scav._leaves_in_way(), "without the tree it sees you")
	scav.queue_free()
	player.health.heal(player.health.max_health)
	# A dead scav's backpack: its loot hitbox is on the model (0.17.13, owner: it was off to one side).
	var pack := (load("res://scenes/backpack_bag.tscn") as PackedScene).instantiate() as Node3D
	main.add_child(pack)
	var box := AABB()
	for mesh: MeshInstance3D in pack.find_children("*", "MeshInstance3D", true, false):
		var part := (pack.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		box = part if box.size == Vector3.ZERO else box.merge(part)
	var hit_shape := pack.get_node("CollisionShape3D") as CollisionShape3D
	var hit_box := AABB(hit_shape.position - (hit_shape.shape as BoxShape3D).size / 2, (hit_shape.shape as BoxShape3D).size)
	_check(hit_box.grow(0.05).encloses(box) and hit_box.get_center().distance_to(box.get_center()) < 0.1,
		"the backpack's hitbox fits the model (%s vs %s)" % [hit_box, box])
	pack.queue_free()


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
	# 0.12.31 (owner: a Raider's partner spawned stuck in a roof): a partner/guard spot that would be inside
	# something moves to a clear spot next to the leader instead.
	var origin := Vector3(-30, 0.1, 30)
	var shelf := _block(origin + Vector3(1.5, 1.0, 1.0), Vector3(1.6, 2.0, 1.6))
	var placer := EnemySpawner.new()
	placer.set_process(false)
	placer.set_physics_process(false)
	main.add_child(placer)
	await physics_frame
	var clear := placer.clear_spot_near(origin, Vector3(1.5, 0, 1.0))
	var shelf_box := AABB(shelf.global_position - Vector3(0.8, 1.0, 0.8), Vector3(1.6, 2.0, 1.6)).grow(0.3)
	_check(clear != origin and not shelf_box.has_point(clear + Vector3(0, 1.0, 0)) and absf(clear.y - origin.y) < 0.3,
		"a partner's spawn spot blocked by something moves to a clear spot beside the leader (%s)" % (clear - origin))
	shelf.queue_free()
	# ...and never into another AI (0.12.35, owner's screenshot: two in one spot stacked, one stuck in the ceiling).
	var squatter := _spawn(SCAV_SCENE, origin + Vector3(1.5, 0, 1.0)) as Scav
	squatter.set_physics_process(false)
	await physics_frame
	var beside := placer.clear_spot_near(origin, Vector3(1.5, 0, 1.0))
	_check(Vector2(beside.x - squatter.global_position.x, beside.z - squatter.global_position.z).length() > 0.9,
		"a spawn spot never lands inside another AI (%.1f m from it)" % beside.distance_to(squatter.global_position))
	squatter.queue_free()
	# Standing on another AI's head, it steps off.
	var bottom := _spawn(SCAV_SCENE, origin + Vector3(6, 0, 0)) as Scav
	var top := _spawn(SCAV_SCENE, origin + Vector3(6, 1.95, 0)) as Scav
	var low_ceiling := _block(origin + Vector3(6, 4.0, 0), Vector3(6, 0.2, 6))   # (its head stuck in it)
	bottom.set_physics_process(false)
	top._set_state(Scav.State.SEARCH)
	await _frames(90)
	low_ceiling.queue_free()
	_check(top.global_position.y < origin.y + 0.5, "an AI that lands on another's head steps off it (feet at %.1f m)" % (top.global_position.y - origin.y))
	bottom.queue_free()
	top.queue_free()
	placer.queue_free()


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
	_check(the_boss.body_name == "Bon" and the_boss.armor == "armor_heavy" and the_boss.helmet == "helmet_good"
		and is_equal_approx(the_boss.health.damage_multiplier, 0.6) and is_equal_approx(the_boss.health.head_multiplier, 0.55),
		"the boss is Bon and wears heavy armor and a combat helmet, which protect him like a player (owner)")
	raider.free()
	var offsets := guards.map(func(g: Scav) -> Vector3: return g.follow_offset)
	_check(offsets.size() == 3 and offsets[0] != offsets[1] and offsets[1] != offsets[2], "each guard has its own spot round the boss")
	_check(guards.all(func(g: Scav) -> bool: return g.body_name == "Bon's Guard"), "Bon's guards are named Bon's Guard (owner)")
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
	# 0.12.36 (owner): once or twice a raid it takes its guards on a trip to another building (the bank most
	# often), and some patrol stops are just outside its area. A fight on a trip doesn't send it straight home.
	_check(the_boss.excursions == 2 and the_boss.outside_patrol > 0.0, "the boss makes 1-2 trips a raid and patrols outside its building too")
	var far_spot := Node3D.new()
	far_spot.set_meta("place", "Bank")
	main.add_child(far_spot)
	far_spot.global_position = hall.center + Vector3(the_boss.home_radius + 20.0, 0, 0)
	var spots: Array[Node] = [far_spot]
	var trip := the_boss._pick_trip(spots)
	_check(trip != Vector3.ZERO and not the_boss._in_home(trip), "a trip goes to a building outside its area")
	the_boss._trip_point = trip
	_check(guards[0]._near_home(trip + Vector3(5, 0, 0)), "on a trip, a fight there counts as near home (no instant walk back)")
	the_boss._trip_point = Vector3.INF
	far_spot.queue_free()
	# 0.17.3 (owner: "more aggro, never runs to cover", but "there needs to be some break"): Bon never takes cover or
	# plays safe when hurt, chases from farther, and stops for a short pause (standing or stepping aside) between chases.
	var raider_ref := load(RAIDER_SCENE).instantiate() as Scav
	_check(the_boss.never_cover and not raider_ref.never_cover and the_boss.chase_range > raider_ref.chase_range,
		"Bon never takes cover and chases from farther than a Raider")
	raider_ref.free()
	the_boss._cover_cooldown_left = 0.0
	the_boss._try_take_cover()
	the_boss.health.current = 1
	_check(the_boss._cover_phase == Scav.Cover.NONE and not the_boss.is_hurt(), "Bon doesn't run to cover or play safe when badly hurt")
	the_boss.health.current = the_boss.health.max_health
	var bon_to := Vector3(0, 0, 20)
	the_boss._opening = false   # (past his opening volley, 0.17.9)
	the_boss._since_threat = 0.0   # (mid-fight, no lull: no random flank roll)
	the_boss._decide(true, bon_to, 20.0)
	var chased := the_boss.tactic == Scav.Tactic.CHASE
	the_boss._tactic_time = the_boss._chase_burst + 0.1
	var breaks := the_boss._should_rethink(true, 20.0)
	the_boss._decide(true, bon_to, 20.0)
	var paused := the_boss.tactic == Scav.Tactic.STAND and the_boss._pausing and not the_boss._should_rethink(true, 20.0)
	var opens_fire := the_boss._fire_timer <= 0.15
	the_boss._tactic_time = the_boss._stand_time + 0.1
	the_boss._decide(true, bon_to, 20.0)
	_check(chased and breaks and paused and opens_fire and the_boss.tactic == Scav.Tactic.CHASE and the_boss.flank_chance > 0.0,
		"Bon chases, takes a short break shooting (stands or steps aside), then chases again; he still flanks")
	the_boss.tactic = Scav.Tactic.NONE
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
	# 0.15.18 (owner): under 40% health counts too, and a proxy (online) goes by the flag its player's game sends.
	var real_health := player.health.current
	pusher._target = player
	player.health.current = 39
	var low_pushes: bool = pusher._target_busy() and int(RemotePlayer.capture(player)[4]) & Hitbox.FLAG_LOW != 0
	player.health.current = 41
	_check(low_pushes and not pusher._target_busy(), "under 40% health the AI push you")
	player.health.current = real_health
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
		and aim.hit_chance(50.0) > aim.hit_chance(75.0) and aim.hit_chance(75.0) <= 0.19,
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
		s._opening = false   # (mid-fight: both already opened fire, 0.17.9)
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


## No AI vaulting (0.14.20, owner: it made AI drop through stair ramps; scrapped): the navigation map has no links
## over cover, and a scav walks round a low wall to get to the far side.
func _section_ai_vault() -> void:
	var nav := main.get_node("Navigation") as NavBaker
	player.teleport_to(Vector3(-30, 0.1, -30))
	# A long sandbag-high wall in the open south-west, a scav on one side and its goal straight across.
	var wall := StaticBody3D.new()
	wall.add_to_group(NavBaker.SOURCE_GROUP)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(24, 1.0, 0.6)
	wall.add_child(shape)
	main.add_child(wall)
	wall.global_position = Vector3(-20, 0.5, 30)
	nav._bake()
	await nav.baked
	await physics_frame
	await physics_frame
	_check(nav.get_children().filter(func(c: Node) -> bool: return c is NavigationLink3D).is_empty(),
		"no navigation links over cover")
	var scav := _spawn(SCAV_SCENE, Vector3(-20, 0.1, 27)) as Scav
	await physics_frame
	var path := AINav.path(scav, scav.global_position, Vector3(-20, 0, 33))
	var round_end := false
	for p in path:
		round_end = round_end or absf(p.x + 20.0) > 12.0
	_check(path.size() > 2 and round_end and path[path.size() - 1].distance_to(Vector3(-20, 0.5, 33)) < 1.0,
		"a scav's path goes round low cover, not over it (%s)" % [path])
	scav.queue_free()
	wall.queue_free()
	await physics_frame
	nav._bake()
	await nav.baked


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
	# 0.12.31 (owner): a zone can keep its AI out of part of it (the town's scavs stay away from the town hall and the
	# bank) and send its patrols round the edges.
	var edger := _spawn(SCAV_SCENE, Vector3(0, 0.1, 30)) as Scav
	await physics_frame
	edger.home_center = Vector3(0, 0, 30)
	edger.home_radius = 25.0
	edger.home_avoid = [Vector3(10, 8.0, 30)]
	edger.home_edge = 0.45
	var in_avoid := 0
	var near_middle := 0
	for i in 40:
		var p := edger._pick_patrol_point()
		if Vector2(p.x - 10, p.z - 30).length() <= 8.0:
			in_avoid += 1
		if edger._patrol_container == null and Vector2(p.x, p.z - 30).length() < 25.0 * 0.3:
			near_middle += 1
	_check(in_avoid == 0 and near_middle == 0, "patrol stops stay out of the zone's no-go part and round its edges (%d in it, %d in the middle)" % [in_avoid, near_middle])
	# 0.15.16 (owner: four AI walking the same path): a patrol doesn't pick a stop another AI is already heading to.
	var walker := _spawn(SCAV_SCENE, Vector3(0, 0.1, 30)) as Scav
	await physics_frame
	walker._wander_point = Vector3(0, 0, 30)
	walker._wander_dir = Vector3.FORWARD
	_check(edger._patrol_taken(Vector3(5, 0, 30)) and not edger._patrol_taken(Vector3(0, 0, 0)),
		"patrols spread out: a stop near where another AI is going is taken")
	walker.queue_free()
	edger.queue_free()


func _section_ai_lod() -> void:
	# 0.14.4 (health check: 32 AI were too slow for phones): a calm AI far from every player thinks and moves 10 times
	# a second instead of every frame, but still moves smoothly, and anything that alerts it brings it straight back.
	player.teleport_to(Vector3(-30, 0.1, -30))
	var scav := _spawn(SCAV_SCENE, Vector3(30, 0.1, 30)) as Scav
	scav.sight_range = 20.0   # (the test map is small: "far" is past what it can see, plus a margin)
	await _frames(40)
	_check(scav._lod_far and scav.state == Scav.State.IDLE, "a calm AI far from the player goes to the slow rate")
	var slow_ticks := 0
	var frames := 0
	var biggest_step := 0.0
	var top_speed := 0.0
	var start := scav.global_position
	var last := scav.global_position
	for i in 60 * 15:
		await physics_frame
		if scav.state != Scav.State.IDLE:
			break
		frames += 1
		if scav._glide_frame == 1 and scav._tick_delta > 0.09:   # (just took a slow tick)
			slow_ticks += 1
		biggest_step = maxf(biggest_step, Vector2(scav.global_position.x - last.x, scav.global_position.z - last.z).length())
		top_speed = maxf(top_speed, Vector2(scav.velocity.x, scav.velocity.z).length())
		last = scav.global_position
	_check(slow_ticks > 0 and absf(frames / float(slow_ticks) - Scav.LOD_FRAMES) < 1.0,
		"it thinks every %d frames (%d slow ticks in %d frames)" % [Scav.LOD_FRAMES, slow_ticks, frames])
	_check(scav.global_position.distance_to(start) > 8.0 and top_speed < scav.move_speed,
		"it still patrols at a walking pace (%.0f m, %.1f m/s)" % [scav.global_position.distance_to(start), top_speed])
	_check(biggest_step < top_speed / 60.0 * 1.6 + 0.01,
		"it glides smoothly between ticks (biggest step in one frame %.3f m)" % biggest_step)
	# A noise reaches it at once and brings it back to every frame.
	scav.noise_uncertainty = 0.0   # (a random guess right where it stands would end the walk at once)
	scav.hear_noise(scav.global_position + Vector3(3, 0, 0), 20.0)
	await physics_frame
	await physics_frame
	_check(scav.state == Scav.State.INVESTIGATE and absf(scav._tick_delta - 1.0 / 60.0) < 0.001,
		"a noise wakes it straight away (%s, tick %.3f s)" % [Scav.State.keys()[scav.state], scav._tick_delta])
	# A player coming near brings it back too.
	scav._set_state(Scav.State.IDLE)
	await _frames(40)
	player.teleport_to(scav.global_position + Vector3(20, 0, 0))
	await _frames(40)
	_check(not scav._lod_far, "a player within range keeps it at full rate")
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
	# 0.15.26 (owner): sniped from beyond its range with no way to shoot back, it runs off and lies low.
	player.teleport_to(Vector3(-30, 0.1, -30))
	var sniped := _spawn(SCAV_SCENE, Vector3(-30, 0.1, -30) + Vector3(1, 0, 1).normalized() * 80.0) as Scav
	sniped.shot_damage = 0
	await _frames(5)
	var sniped_from := sniped.global_position.distance_to(player.global_position)
	sniped.health.take_damage(10, player.global_position + Vector3(0, 1.5, 0))
	for i in 60 * 10:
		await physics_frame
	var sniped_to := sniped.global_position.distance_to(player.global_position)
	_check(sniped._fled_left > 0.0 and sniped_to > sniped_from + 3.0,
		"sniped from out of its range, it runs off and hides (%.0f m -> %.0f m)" % [sniped_from, sniped_to])
	sniped.queue_free()
	await physics_frame
	# Fighting comes first; in a break (nobody shooting at it for a bit) a scav ducks behind something nearby,
	# holds a moment, then comes back out to fight. Next to the police station (walls x -20..-10, z -20..-10).
	player.teleport_to(Vector3(-15, 0.1, 0))
	var scav := _spawn(SCAV_SCENE, Vector3(-8, 0.1, -8)) as Scav
	_face_player(scav)
	scav.shot_damage = 0  # watching it move, not dying
	scav.flank_chance = 0.0  # (scavs flank sometimes since 0.12.3; this checks cover)
	scav.close_fight_range = 0.0  # (10 m away: up close it would shoot back first, 0.12.30)
	scav.chase_range = 0.0  # (and in range it would mostly chase you, 0.12.33)
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
	fighter.close_fight_range = 0.0
	fighter.chase_range = 0.0
	await physics_frame
	fighter._alert(player.global_position)
	fighter._set_state(Scav.State.ENGAGE)
	var phases := {}
	var shots := [0]
	fighter.fired.connect(func(_end: Vector3) -> void:
		if fighter._cover_phase == Scav.Cover.PEEKING:
			shots[0] += 1)
	# (Up to 16 s: how soon it gets a lull to duck in depends on the random rolls.)
	for i in 60 * 16:
		if i % 30 == 0:
			fighter.notice_threat()  # the player firing every half second
		await physics_frame
		phases[fighter._cover_phase] = true
		if phases.has(Scav.Cover.HOLDING) and phases.has(Scav.Cover.PEEKING) and shots[0] > 0:
			break
	_check(phases.has(Scav.Cover.HOLDING) and phases.has(Scav.Cover.PEEKING) and shots[0] > 0,
		"under fire it fights from cover: ducks in, peeks out and shoots from there (%d shots peeking)" % shots[0])
	fighter.queue_free()
	# In range to really hurt you it comes at you shooting (0.12.33, owner: "should prio chasing u"), all the way in
	# (0.12.36), and doesn't take cover first.
	var chaser := _spawn(SCAV_SCENE, Vector3(-15, 0.1, 22)) as Scav
	_face_player(chaser)
	chaser.shot_damage = 0
	chaser.flank_chance = 0.0
	chaser.chase_cover_chance = 0.0
	await physics_frame
	chaser._alert(player.global_position)
	chaser._set_state(Scav.State.ENGAGE)
	var chase_shots := [0]
	chaser.fired.connect(func(_end: Vector3) -> void: chase_shots[0] += 1)
	var chased := false
	var closest := 99.0
	for i in 60 * 13:   # (+3 s: it opens fire standing first, 0.17.9)
		await physics_frame
		chased = chased or chaser.tactic == Scav.Tactic.CHASE
		closest = minf(closest, chaser.global_position.distance_to(player.global_position))
	_check(chased and chase_shots[0] > 0 and closest < 3.5,
		"in range it chases you while shooting, all the way in (%d shots, got to %.1f m)" % [chase_shots[0], closest])
	chaser.queue_free()


func _section_lean() -> void:
	# Online (0.13.8): leaning tips the body's hitbox with the model, so a shoulder round a corner can be hit.
	var shoulder_shot := func(lean: float) -> bool:
		var state := [Vector3.ZERO, 0.0, 0.0, lean, 0]
		return not Hitbox.trace(state, Vector3(0.55, 1.2, 3), Vector3(0.55, 1.2, -3)).is_empty()
	_check(shoulder_shot.call(1.0) and not shoulder_shot.call(0.0), "online, a leaning player's shoulder is hittable past their feet")
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
	# 0.12.32 (owner): badly hurt AI don't run away. They play safer (no pushing or flanking) and keep fighting,
	# and patch up (+40 HP over 4 s) only once the fight goes quiet; shooting it interrupts the heal.
	var checker := _spawn(SCAV_SCENE, Vector3(30, 0.1, 30)) as Scav
	await physics_frame
	checker.health.take_damage(60)
	var hurt_at_40 := checker.is_hurt()
	checker.health.take_damage(15)
	_check(not hurt_at_40 and checker.is_hurt(), "a scav plays safer once badly hurt (not at 40 HP, yes at 25)")
	checker.queue_free()
	player.teleport_to(Vector3(-15, 0.1, 0))
	var scav := _spawn(SCAV_SCENE, Vector3(-8, 0.1, -8)) as Scav
	_face_player(scav)
	scav.shot_damage = 0
	scav.close_fight_range = 0.0
	await physics_frame
	scav._alert(player.global_position)
	scav._set_state(Scav.State.ENGAGE)
	scav.health.take_damage(75, player.global_position)  # 25 HP left: below 30%
	var hp_hurt := scav.health.current
	var hurt_shots := [0]
	scav.fired.connect(func(_end: Vector3) -> void: hurt_shots[0] += 1)
	var bold := false
	var hurt_start := scav.global_position
	var strayed := 0.0
	for i in 60 * 8:
		await physics_frame
		bold = bold or scav.tactic in [Scav.Tactic.PUSH, Scav.Tactic.FLANK, Scav.Tactic.CHASE]
		strayed = maxf(strayed, scav.global_position.distance_to(hurt_start))
	_check(hurt_shots[0] >= 1 and strayed < 8.0 and not bold,
		"badly hurt it repositions and keeps fighting: no running off, pushing or flanking (%d shots, moved %.1f m)" % [hurt_shots[0], strayed])
	# Out of sight and nothing shooting at it: it patches up after a few quiet seconds.
	var screen := _block((player.global_position + scav.global_position) / 2.0 + Vector3(0, 1.5, 0), Vector3(8, 3, 8))
	var healed := false
	for i in 60 * 12:
		await physics_frame
		if scav.health.current > hp_hurt:
			healed = true
			break
	_check(healed and scav.health.current == hp_hurt + scav.heal_amount, "once it's quiet it patches up (+%d HP: %d -> %d)" % [scav.heal_amount, hp_hurt, scav.health.current])
	screen.queue_free()
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
	await physics_frame
	# 0.12.30 (owner): up close with no cover a step away, its first instinct is to shoot back, not run round.
	player.teleport_to(Vector3(30, 0.1, -30))
	var brawler := _spawn(SCAV_SCENE, Vector3(30, 0.1, -36)) as Scav
	_face_player(brawler)
	brawler.shot_damage = 0
	var brawl_shots := [0]
	brawler.fired.connect(func(_end: Vector3) -> void: brawl_shots[0] += 1)
	await physics_frame
	brawler._alert(player.global_position)
	var backed := 0.0
	var brawl_dist := brawler.global_position.distance_to(player.global_position)
	for i in 60 * 2:
		await physics_frame
		backed = maxf(backed, brawler.global_position.distance_to(player.global_position) - brawl_dist)
	_check(brawl_shots[0] >= 2 and backed < 1.0, "up close it shoots back first, no running off (%d shots, backed off %.1f m)" % [brawl_shots[0], backed])
	brawler.queue_free()
	await physics_frame
	# 0.12.31 (owner: priorities felt wrong): badly hurt up close with no cover a few steps away, it keeps shooting
	# back instead of turning its back to run (or patching up in the open in front of you).
	var cornered := _spawn(SCAV_SCENE, Vector3(30, 0.1, -36)) as Scav
	_face_player(cornered)
	cornered.shot_damage = 0
	var cornered_shots := [0]
	cornered.fired.connect(func(_end: Vector3) -> void: cornered_shots[0] += 1)
	await physics_frame
	cornered._alert(player.global_position)
	await create_timer(0.4).timeout
	cornered.health.take_damage(75, player.global_position)
	var shots_before: int = cornered_shots[0]
	var cornered_start := cornered.global_position
	var cornered_moved := 0.0
	var healed_in_open := false
	for i in 60 * 2:
		await physics_frame
		cornered_moved = maxf(cornered_moved, cornered.global_position.distance_to(cornered_start))
		healed_in_open = healed_in_open or cornered._cover_phase == Scav.Cover.HEALING
	_check(cornered_shots[0] - shots_before >= 2 and cornered_moved < 4.0 and not healed_in_open,
		"hurt up close with no cover near, it fights back (%d shots, moved %.1f m, healed in the open: %s)" % [
			cornered_shots[0] - shots_before, cornered_moved, healed_in_open])
	cornered.queue_free()
	await physics_frame
	# 0.12.30 (owner): it hears you walk up behind it, looks round and spots you.
	player.teleport_to(Vector3(30, 0.1, -25))
	var listener := _spawn(SCAV_SCENE, Vector3(30, 0.1, -30)) as Scav
	listener.look_at(listener.global_position + Vector3(0, 0, -10))   # facing away from you
	listener._wander_time = 99.0
	listener._wander_dir = Vector3.ZERO
	listener.shot_damage = 0
	await physics_frame
	player._make_noise(player.walk_noise)
	var noticed := false
	for i in 90:
		await physics_frame
		if listener.state in [Scav.State.ALERT, Scav.State.ENGAGE]:
			noticed = true
			break
	_check(noticed, "a scav facing away hears your footsteps 5 m behind it, turns and spots you")
	listener.queue_free()


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
	# Weapon drops (owner, 0.11.11): Raiders sometimes leave their AK in the body bag; scavs too, less often (0.15.5).
	_check(raider.weapon_drop == "ak" and raider.weapon_drop_chance > 0.0 and raider.weapon_drop_chance < 1.0, "Raiders have a chance to drop an AK")
	_check(is_equal_approx(scav.weapon_drop_chance, 0.15), "scavs drop their gun 15% of the time (owner, 0.15.5)")
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
	var packed := LootContainer.spawn_bag(main, Vector3(50, 0, 50), "Test Body", [["ak", 1], ["backpack_medium", 1], ["medkit", 1], ["armor_light", 1]])
	_check(packed.grid.stacks.size() == 4, "a body bag fits an AK, a backpack, a medkit and armor (%d of 4)" % packed.grid.stacks.size())
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
	if node is Scav:
		# AI tests are built around the AK's numbers: no random gun (the "ai_loadouts" section checks those).
		(node as Scav).loadout = ""
	main.add_child(node)
	node.global_position = pos
	return node


## Turns `node` (around Y only) to face the player.
func _face_player(node: Node3D) -> void:
	node.look_at(Vector3(player.global_position.x, node.global_position.y, player.global_position.z))


func _section_sound() -> void:
	# The Sound update (0.20, owner: only ADD sounds, today's stay). 0.20.0: footsteps by surface. A box's colour
	# says what it sounds like; plain floors and the ground inside a building sound like the building's floor.
	var map := BoxMap.new()
	map.colors = PackedColorArray([Color.GRAY, Color.BROWN, Color.DIM_GRAY, Color.WHITE])
	map.colour_names = PackedStringArray(["grass", "wood", "metal", "slab"])
	var spot := Vector3(-40, 0, 40)
	map.boxes = PackedFloat32Array([spot.x, 0.1, spot.z, 2, 0.2, 2, 0, 0, 1, 1,
		spot.x + 4, 0.1, spot.z, 2, 0.2, 2, 0, 0, 2, 1,
		spot.x + 8, 0.1, spot.z, 2, 0.2, 2, 0, 0, 3, 1,
		spot.x + 12, 0.1, spot.z, 2, 0.2, 2, 30, 0, 1, 1])
	map.floor_rects = PackedFloat32Array([spot.x + 6, spot.z - 3, spot.x + 10, spot.z + 3, Surfaces.CONCRETE])
	main.add_child(map)
	var at := func(dx: float, y := 0.2) -> int: return map.surface_at(spot + Vector3(dx, y, 0.3))
	_check(at.call(0.0) == Surfaces.WOOD and at.call(4.0) == Surfaces.METAL and at.call(12.0) == Surfaces.WOOD,
		"footsteps by surface: wood and metal boxes (a turned one too)")
	_check(at.call(8.0) == Surfaces.CONCRETE and at.call(6.5, 0.0) == Surfaces.CONCRETE and at.call(2.0, 0.0) == Surfaces.GROUND
		and at.call(0.0, 1.5) == Surfaces.GROUND,
		"a plain floor and the ground in a building sound like its floor; outdoors and in mid-air, the ground")
	var back := player.global_position
	player.teleport_to(spot + Vector3(0, 0.3, 0))
	await create_timer(0.3).timeout
	_check(Surfaces.under(player) == Surfaces.WOOD, "the player standing on the wood box hears wood")
	player.set_meta(BoxMap.WADE_META, 1)
	_check(Surfaces.under(player) == Surfaces.WATER, "...and water while wading")
	player.remove_meta(BoxMap.WADE_META)
	var steps := main.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer).size()
	Surfaces.step(player, -9.0)
	_check(main.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer).size() == steps + 1,
		"a footstep plays")
	player.teleport_to(back)
	map.queue_free()
	var real := (load("res://scenes/maps/old_bloxov.tscn") as PackedScene).instantiate()
	var blocks := real.get_node("Level/Blocks") as BoxMap
	_check(blocks.colour_names.size() == blocks.colors.size() and blocks.floor_rects.size() >= 5 * 30,
		"Bloxov Battlegrounds names its colours and %d buildings' floors" % (blocks.floor_rects.size() / 5))
	real.free()
	await create_timer(0.1).timeout


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



## (0.15.28, owner: hide for 5 s up close and AI went back to patrolling) An AI that loses you up close mid-fight
## and can't get to where you were hunts for you (30 s), not a 5 s look round.
func _section_lost_close() -> void:
	var p := player.global_position
	var scav := _spawn(SCAV_SCENE, p + Vector3(0, 0, 10)) as Scav
	_face_player(scav)
	scav.shot_damage = 0
	scav._alert(p)
	await _frames(60)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(30, 4, 0.5)
	wall.add_child(shape)
	main.add_child(wall)
	wall.global_position = p + Vector3(0, 2, 2)
	for i in 600:
		if scav.state != Scav.State.ENGAGE:
			break
		await physics_frame
	var hunting := scav.state == Scav.State.SEARCH and scav._hunting
	await create_timer(12.0).timeout
	_check(hunting and scav.state == Scav.State.SEARCH, "lost you up close behind a wall: still hunting for you 12 s later (%s)" % Scav.State.keys()[scav.state])
	scav.queue_free()
	wall.queue_free()
	await physics_frame


## Look update (0.19): the raid wears the current look, and every saved look (the classic one included, the owner
## asked to keep it) loads with what a raid needs.
func _section_look() -> void:
	var current := load(Look.current) as Look
	var world := main.get_node("WorldEnvironment") as WorldEnvironment
	var sun := main.get_node("Sun") as DirectionalLight3D
	_check(current != null and world.environment == current.environment and is_equal_approx(sun.light_energy,
		current.sun_energy), "the raid uses the current look (%s)" % Look.current)
	var classic := load(Look.CLASSIC) as Look
	_check(classic != null and is_equal_approx(classic.sun_energy, 1.4) and classic.environment.sky != null,
		"the classic look is still there to put back")
	var bad := []
	for dir in ["res://assets/looks/", "res://assets/looks/options/"]:
		for file in DirAccess.get_files_at(dir):
			var path: String = dir + file.trim_suffix(".remap")
			if path.ends_with(".tres") and not (load(path) is Look and (load(path) as Look).environment != null):
				bad.append(path)
	_check(bad.is_empty(), "every saved look loads %s" % str(bad))
	# The loading screen (0.19.3): the map's picture, its name and a tip.
	var screen := LoadingScreen.make()
	root.add_child(screen)
	await _frames(1)
	var words := screen.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	_check(load(LoadingScreen.PICTURE) is Texture2D and LoadingScreen.tip in LoadingScreen.TIPS and
		("TIP: " + LoadingScreen.tip) in words and LoadingScreen.MAP_NAME.to_upper() in words,
		"the loading screen shows the map, its name and a tip")
	screen.queue_free()
