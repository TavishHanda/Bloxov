extends CanvasLayer
## Everything on screen: crosshair, hit markers, health, ammo, raid timer, loot prompts, extract info,
## the pause menu, the backpack/loot screen and the end-of-raid screen.
## The game pauses only while the pause menu is open (solo only: an online raid keeps going, like any online game).
## This node keeps running while paused.
## F3 toggles a debug overlay. F4 toggles raw mouse input (web only; press Esc and click to re-lock).

@export var player: Player
@export var raid: Raid

@onready var crosshair: Label = $Crosshair
@onready var hit_marker: Label = $HitMarker
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var ammo_label: Label = $AmmoLabel
@onready var timer_label: Label = $TimerLabel
@onready var prompt_label: Label = $Prompt
@onready var action_bar: ProgressBar = $ActionBar
@onready var extract_status: Label = $ExtractStatus
@onready var extract_list: Label = $ExtractList
@onready var vignette: ColorRect = $Vignette
@onready var damage_indicator: Control = $DamageIndicator
@onready var debug_label: Label = $Debug
@onready var menu: Control = $Menu
@onready var play_button: Button = $Menu/Margin/VBox/PlayButton
@onready var volume_slider: HSlider = $Menu/Margin/VBox/VolumeRow/Slider
@onready var volume_value: Label = $Menu/Margin/VBox/VolumeRow/Value
@onready var sensitivity_slider: HSlider = $Menu/Margin/VBox/SensitivityRow/Slider
@onready var damage_numbers_toggle: CheckBox = $Menu/Margin/VBox/DamageNumbers
@onready var lean_toggle: CheckBox = $Menu/Margin/VBox/LeanToggle
@onready var sensitivity_value: Label = $Menu/Margin/VBox/SensitivityRow/Value
@onready var menu_version: Label = $Menu/Margin/VBox/Version
@onready var corner_version: Label = $VersionCorner

var loot_ui: LootUI
var end_screen: RaidEndScreen
var hotbar: HotbarHUD

var _hit_marker_time := 0.0
var _indicator_time := 0.0
## Seconds the extract list stays up: a few at the start of the raid, and after pressing O.
var _extract_list_time := 6.0
var _health_fill: StyleBoxFlat
var _max_delta_timer := 0.0


func _ready() -> void:
	var version := "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	menu_version.text = version
	corner_version.text = version

	GameSettings.load_settings()
	volume_slider.value = GameSettings.volume * 100.0
	sensitivity_slider.value = GameSettings.sensitivity * 100.0
	_update_slider_labels()
	volume_slider.value_changed.connect(_on_volume_changed)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	damage_numbers_toggle.button_pressed = GameSettings.damage_numbers
	damage_numbers_toggle.toggled.connect(GameSettings.set_damage_numbers)
	lean_toggle.button_pressed = GameSettings.lean_toggle
	lean_toggle.toggled.connect(GameSettings.set_lean_toggle)
	play_button.pressed.connect(_capture_mouse)

	# Health: a bar with the number on it (green, turning red when low).
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.08, 0.08, 0.08, 0.75)
	back.set_corner_radius_all(3)
	health_bar.add_theme_stylebox_override("background", back)
	_health_fill = StyleBoxFlat.new()
	_health_fill.set_corner_radius_all(3)
	health_bar.add_theme_stylebox_override("fill", _health_fill)
	hotbar = HotbarHUD.new(player)
	add_child(hotbar)
	loot_ui = LootUI.new(player)
	add_child(loot_ui)
	end_screen = RaidEndScreen.new(raid)
	add_child(end_screen)
	# Keep the pause menu on top of everything.
	move_child(menu, -1)

	player.health.damaged.connect(_on_player_damaged)
	player.gun.hit_confirmed.connect(_on_hit_confirmed)
	player.knife.hit_confirmed.connect(_on_hit_confirmed)
	player.interactor.opened.connect(_on_container_opened)
	raid.ended.connect(_on_raid_ended)
	hit_marker.visible = false


func _input(event: InputEvent) -> void:
	# Handled here (before the GUI) so Tab doesn't move button focus around.
	if event.is_action_pressed("inventory"):
		if loot_ui.visible:
			loot_ui.close()
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.controls_locked():
			loot_ui.open_for(null)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and loot_ui.visible:
		loot_ui.close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("extracts"):
		_extract_list_time = 0.0 if _extract_list_time > 0.0 else 6.0


func _unhandled_input(event: InputEvent) -> void:
	# Clicking anywhere outside the menu panel also resumes.
	if menu.visible and event is InputEventMouseButton and event.pressed:
		_capture_mouse()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			debug_label.visible = not debug_label.visible
		elif event.physical_keycode == KEY_F4 and OS.has_feature("web"):
			JavaScriptBridge.eval("window.bloxovRaw && (window.bloxovRaw.want = !window.bloxovRaw.want)", true)


func _process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var other_screen_open := loot_ui.visible or end_screen.visible
	menu.visible = not captured and not other_screen_open and not player.controls_locked()
	get_tree().paused = menu.visible and not Network.main.in_online_raid()
	# Aiming down sights uses the gun's own sight instead of the crosshair.
	crosshair.visible = captured and not player.controls_locked() and not player.gun.is_aiming()

	var gun := player.gun
	ammo_label.modulate = Color.WHITE
	if gun.weapon == null:
		ammo_label.text = "UNARMED"
	elif gun.is_reloading:
		ammo_label.text = "RELOADING..."
	else:
		ammo_label.text = "%d / %d" % [gun.in_mag, gun.reserve]
		if gun.in_mag == 0:
			ammo_label.modulate = Color(1, 0.4, 0.3)
	var hp := player.health.current
	health_bar.max_value = player.health.max_health
	health_bar.value = hp
	health_label.text = str(hp)
	var fraction := float(hp) / player.health.max_health
	_health_fill.bg_color = Color(0.85, 0.2, 0.15, 0.9) if fraction <= 0.3 else Color(0.3, 0.75, 0.3, 0.85).lerp(Color(0.9, 0.7, 0.2, 0.85), clampf((0.7 - fraction) / 0.4, 0.0, 1.0))
	stamina_bar.max_value = player.max_stamina
	stamina_bar.value = player.stamina
	stamina_bar.visible = player.stamina < player.max_stamina and not player.controls_locked()
	stamina_bar.modulate = Color(1, 0.35, 0.3, 0.9) if player.is_exhausted else Color(1, 0.9, 0.35, 0.85)


	var seconds := ceili(raid.time_left)
	timer_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	timer_label.modulate = Color(1, 0.35, 0.3) if seconds <= 60 else Color.WHITE

	_update_prompt()
	_update_extract_info(delta)

	if not get_tree().paused:
		# Red flash when hit; a faint red edge stays while health is low.
		var low_health_alpha := 0.18 if hp <= 30 and not player.controls_locked() else 0.0
		vignette.color.a = maxf(vignette.color.a - delta * 1.5, low_health_alpha)
		_hit_marker_time -= delta
		_indicator_time -= delta
	hit_marker.visible = _hit_marker_time > 0.0
	damage_indicator.modulate.a = clampf(_indicator_time, 0.0, 1.0)

	_update_debug(delta)


func _update_prompt() -> void:
	var interactor := player.interactor
	prompt_label.visible = false
	action_bar.visible = false
	if player.is_healing():
		prompt_label.text = "Healing..."
		prompt_label.visible = true
		action_bar.visible = true
		action_bar.value = 1.0 - player.heal_time_left / player.heal_duration
	elif interactor.target != null:
		prompt_label.text = "[F] " + interactor.target.prompt()
		prompt_label.visible = true
		if interactor.progress > 0.0:
			action_bar.visible = true
			action_bar.value = interactor.progress


func _update_extract_info(delta: float) -> void:
	extract_status.visible = false
	var open_lines: PackedStringArray = []
	for zone in raid.get_extracts():
		if zone.player_inside == player and raid.result == "":
			extract_status.visible = true
			if zone.is_open:
				extract_status.text = "EXTRACTING  %.1f" % maxf(zone.extract_time - zone.progress, 0.0)
				extract_status.modulate = Color(0.45, 1.0, 0.5)
			else:
				extract_status.text = "EXTRACT CLOSED"
				extract_status.modulate = Color(1.0, 0.4, 0.35)
		if zone.is_open:
			var dist := roundi(zone.global_position.distance_to(player.global_position))
			open_lines.append("%s  %dm" % [zone.extract_name, dist])
	_extract_list_time -= delta
	extract_list.visible = _extract_list_time > 0.0
	extract_list.text = "EXTRACTS  (O)\n" + "\n".join(open_lines)


func _capture_mouse() -> void:
	if not player.controls_locked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_volume_changed(value: float) -> void:
	GameSettings.set_volume(value / 100.0)
	_update_slider_labels()


func _on_sensitivity_changed(value: float) -> void:
	GameSettings.set_sensitivity(value / 100.0)
	_update_slider_labels()


func _update_slider_labels() -> void:
	volume_value.text = "%d%%" % roundi(volume_slider.value)
	sensitivity_value.text = "%.2fx" % (sensitivity_slider.value / 100.0)


## Kills get no special marker on purpose (like Tarkov): you see the body drop, or hear the kill sound.
func _on_hit_confirmed(_killed: bool, headshot: bool) -> void:
	_hit_marker_time = 0.1
	if headshot:
		hit_marker.modulate = Color(1, 0.85, 0.1)
		hit_marker.scale = Vector2(1.25, 1.25)
	else:
		hit_marker.modulate = Color.WHITE
		hit_marker.scale = Vector2.ONE


## Online, containers are shared: the raid asks the server first (NetRaid opens the screen when it says yes).
func _on_container_opened(container: LootContainer) -> void:
	var net_raid := get_node_or_null("../NetRaid") as NetRaid
	if Network.main.in_online_raid() and net_raid != null:
		net_raid.request_open(container)
	else:
		loot_ui.open_for(container)


func _on_player_damaged(_amount: int, source_position: Vector3) -> void:
	vignette.color.a = 0.45
	# Point the arrow toward whoever hit us (0 = straight ahead).
	var local := player.global_basis.inverse() * (source_position - player.global_position)
	damage_indicator.rotation = atan2(local.x, -local.z)
	_indicator_time = 1.2


func _on_raid_ended(_result: String) -> void:
	loot_ui.close()
	end_screen.show_result(player.kills)


func _update_debug(delta: float) -> void:
	if not debug_label.visible:
		return
	var raw := "n/a (not web)"
	if OS.has_feature("web"):
		var want = JavaScriptBridge.eval("window.bloxovRaw ? window.bloxovRaw.want : null", true)
		var active = JavaScriptBridge.eval("window.bloxovRaw ? window.bloxovRaw.active : null", true)
		raw = "wanted=%s active=%s (F4 toggles, then Esc + click)" % [want, active]
	debug_label.text = "FPS: %d\nRaw mouse: %s\nBiggest mouse move (last 1s): %d px\nSpikes dropped: %d\nRecent X moves: %s\nEnemies: %d" % [
		Engine.get_frames_per_second(), raw, roundi(player.debug_max_delta),
		player.debug_spikes_dropped, str(player.debug_recent_dx),
		get_tree().get_nodes_in_group("enemies").size()]
	_max_delta_timer += delta
	if _max_delta_timer >= 1.0:
		_max_delta_timer = 0.0
		player.debug_max_delta = 0.0
