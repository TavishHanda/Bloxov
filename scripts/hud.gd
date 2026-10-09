extends CanvasLayer
## Everything on screen: crosshair, hit markers, health, ammo, raid timer, loot prompts, extract info,
## the pause menu, the backpack/loot screen and the end-of-raid screen.
## The game pauses only while the pause menu is open (solo only: an online raid keeps going, like any online game).
## This node keeps running while paused.
## F3 toggles a debug overlay. F4 toggles raw mouse input (web only; press Esc and click to re-lock).

@export var player: Player
@export var raid: Raid

@onready var vignette: ColorRect = $Vignette
@onready var damage_indicator: Control = $DamageIndicator
@onready var debug_label: Label = $Debug
@onready var menu: PanelContainer = $Menu
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
## The raid HUD's widgets (0.8.4+ "Ammo Can" look, see HudStyle): health + stamina, ammo, hotbar, crosshair,
## raid timer, the [F] prompt, extract list/status.
var hotbar: HotbarHUD
var health_hud: HealthHUD
var ammo_hud: AmmoHUD
var crosshair: CrosshairHUD
var timer_hud: TimerHUD
var prompt_hud: PromptHUD
var extract_hud: ExtractHUD
var world_labels: WorldLabelsHUD
var downed_hud: DownedHUD
var spectator: Spectator

var _indicator_time := 0.0
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
	PauseMenuStyle.apply(menu)

	hotbar = HotbarHUD.new(player)
	add_child(hotbar)
	health_hud = HealthHUD.new(player)
	add_child(health_hud)
	ammo_hud = AmmoHUD.new(player)
	add_child(ammo_hud)
	crosshair = CrosshairHUD.new()
	add_child(crosshair)
	timer_hud = TimerHUD.new(raid)
	add_child(timer_hud)
	prompt_hud = PromptHUD.new(player)
	add_child(prompt_hud)
	extract_hud = ExtractHUD.new(player, raid)
	add_child(extract_hud)
	downed_hud = DownedHUD.new(player)
	add_child(downed_hud)
	damage_indicator.add_child(DamageArrowHUD.new())
	world_labels = WorldLabelsHUD.new()
	add_child(world_labels)  # (after the extract tags: damage numbers go on top of them)
	loot_ui = LootUI.new(player)
	add_child(loot_ui)
	spectator = Spectator.new()
	add_child(spectator)
	end_screen = RaidEndScreen.new(raid)
	add_child(end_screen)
	end_screen.spectate_pressed.connect(spectate)
	spectator.finished.connect(func() -> void: end_screen.show_result(player.kills))
	# Keep the pause menu on top of everything.
	move_child(menu, -1)

	player.health.damaged.connect(_on_player_damaged)
	player.gun.hit_confirmed.connect(_on_hit_confirmed)
	player.knife.hit_confirmed.connect(_on_hit_confirmed)
	player.interactor.opened.connect(_on_container_opened)
	raid.ended.connect(_on_raid_ended)


func _input(event: InputEvent) -> void:
	# Handled here (before the GUI) so Tab doesn't move button focus around.
	if event.is_action_pressed("inventory"):
		if loot_ui.visible:
			loot_ui.close()
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.out_of_fight():
			loot_ui.open_for(null)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and loot_ui.visible:
		loot_ui.close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("extracts"):
		extract_hud.toggle_list()


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
	# Aiming down sights uses the gun's own sight instead of the crosshair (the hit marker still shows).
	crosshair.show_crosshair = captured and not player.out_of_fight() and not player.gun.is_aiming()
	var hp := player.health.current

	# The inventory screen gets the whole view: only the raid timer stays (owner, 0.8.2).
	# The end-of-raid screen hides all of it (the raid is over, 0.8.10).
	for element: CanvasItem in [health_hud, ammo_hud, hotbar, crosshair, prompt_hud, extract_hud, world_labels, downed_hud]:
		element.visible = not loot_ui.visible and not end_screen.visible and not spectator.visible
	# Spectating a teammate: their name tag stays.
	world_labels.visible = world_labels.visible or spectator.visible
	timer_hud.visible = not end_screen.visible

	if not get_tree().paused:
		# Red flash when hit; a faint red edge stays while health is low.
		# Downed: a heavier red edge.
		var low_health_alpha := 0.18 if hp <= 30 and not player.controls_locked() else 0.0
		if player.downed:
			low_health_alpha = 0.32
		vignette.color.a = maxf(vignette.color.a - delta * 1.5, low_health_alpha)
		_indicator_time -= delta
	damage_indicator.modulate.a = clampf(_indicator_time, 0.0, 1.0)

	_update_debug(delta)


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
	crosshair.flash_hit(headshot)


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


## Dead: watch a teammate instead of the end screen (it comes back when they're out).
func spectate(peer: int) -> void:
	if spectator.start(peer):
		end_screen.visible = false


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
