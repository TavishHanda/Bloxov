extends CanvasLayer
## Everything on screen: crosshair, hit markers, health, ammo, raid timer, loot prompts, extract status, the map (M),
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
var kill_feed: KillFeedHUD
var prompt_hud: PromptHUD
var extract_hud: ExtractHUD
var map_hud: MapHUD
var world_labels: WorldLabelsHUD
var downed_hud: DownedHUD
var spectator: Spectator

var _indicator_time := 0.0
## Escape closed the inventory (0.13.9): back to playing, not the pause menu. A browser won't take the mouse back
## on Escape (it only does on a click or another key), so until it's captured again a "click to keep playing"
## hint shows instead of the menu.
var resume_pending := false
## The "Click to keep playing" hint came from pressing Escape in the pause menu: the game stays paused under it.
var _resume_from_menu := false
var _resume_hint: Label
## PLAY/click-to-resume keeps asking for the mouse until this time (msec, 0.15.13): a browser refuses it for about a
## second after Escape let it go, so one quick click used to do nothing (owner: PLAY felt unresponsive).
var _capture_until := 0
var _capture_retry_at := 0
## LEAVE RAID (0.14.24, owner) under PLAY, and the "are you sure?" box that takes its place when pressed.
var leave_button: Button
var leave_confirm: VBoxContainer
## Open quests and progress, beside the pause menu (0.17.1).
var quest_tracker: QuestTracker
var _hit_from := Vector3.ZERO
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
	# On press, not release: resumes the moment you click.
	play_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	play_button.pressed.connect(_capture_mouse)
	PauseMenuStyle.apply(menu)
	_build_leave()
	quest_tracker = QuestTracker.new()
	add_child(quest_tracker)
	menu.visibility_changed.connect(_show_quests)

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
	kill_feed = KillFeedHUD.new()
	add_child(kill_feed)
	prompt_hud = PromptHUD.new(player)
	add_child(prompt_hud)
	extract_hud = ExtractHUD.new(player, raid)
	add_child(extract_hud)
	downed_hud = DownedHUD.new(player)
	add_child(downed_hud)
	damage_indicator.add_child(DamageArrowHUD.new())
	world_labels = WorldLabelsHUD.new()
	add_child(world_labels)
	map_hud = MapHUD.new(player, raid)
	add_child(map_hud)
	loot_ui = LootUI.new(player)
	add_child(loot_ui)
	spectator = Spectator.new()
	add_child(spectator)
	end_screen = RaidEndScreen.new(raid)
	add_child(end_screen)
	end_screen.spectate_pressed.connect(spectate)
	spectator.finished.connect(func() -> void: end_screen.show_result(player.kills))
	# Keep the pause menu (and the quest tracker beside it) on top of everything.
	move_child(menu, -1)
	move_child(quest_tracker, -1)
	_show_quests.call_deferred()

	player.health.damaged.connect(_on_player_damaged)
	player.gun.hit_confirmed.connect(_on_hit_confirmed)
	player.knife.hit_confirmed.connect(_on_hit_confirmed)
	player.interactor.opened.connect(_on_container_opened)
	# The kill feed (0.18.9): our kills, and online every player death in the raid.
	player.killed.connect(func(what: String) -> void:
		kill_feed.add_kill("You", KillFeedHUD.display_name(what), true))
	Network.main.kill_feed.connect(func(killer: String, victim: String, mine: bool, ours: bool) -> void:
		kill_feed.add_kill(KillFeedHUD.display_name(killer, true) if killer != "" else "Bloxov",
			KillFeedHUD.display_name(victim, true), mine, ours))
	raid.ended.connect(_on_raid_ended)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		# Escape: out of the inventory back to playing; otherwise (and again while the hint shows) the pause menu.
		if loot_ui.visible:
			# Don't ask for the mouse here (0.15.2): a browser that grabbed it right after an Escape could let go
			# again (Escape still down or repeating), dropping you in the pause menu. Wait for the click instead.
			loot_ui.close(false)
			resume_pending = true
			get_viewport().set_input_as_handled()
		elif menu.visible:
			# Escape in the pause menu closes it (0.17.5, owner: it did nothing, only a click got you out).
			# LEAVE RAID's question goes back to the menu first.
			if leave_confirm != null and leave_confirm.visible:
				cancel_leave()
			elif OS.has_feature("web"):
				# A browser never gives the mouse back on an Escape press, only on a click: hide the menu and
				# show "Click to keep playing" (still paused offline until that click).
				resume_pending = true
				_resume_from_menu = true
			else:
				_capture_mouse()
			get_viewport().set_input_as_handled()
		elif resume_pending:
			resume_pending = false
			get_viewport().set_input_as_handled()
		return
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
	elif event.is_action_pressed("map") and not loot_ui.visible and not end_screen.visible:
		map_hud.toggle()
	elif event.is_action_pressed("extracts"):
		extract_hud.toggle_list()


func _unhandled_input(event: InputEvent) -> void:
	# Clicking anywhere outside the menu panel also resumes.
	if (menu.visible or resume_pending) and event is InputEventMouseButton and event.pressed:
		_capture_mouse()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			debug_label.visible = not debug_label.visible
		elif event.physical_keycode == KEY_F4 and OS.has_feature("web"):
			JavaScriptBridge.eval("window.bloxovRaw && (window.bloxovRaw.want = !window.bloxovRaw.want)", true)


func _process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _capture_until != 0:
		_retry_capture(captured)
	var other_screen_open := loot_ui.visible or end_screen.visible
	if captured or other_screen_open or player.controls_locked():
		resume_pending = false
	if _resume_hint == null:
		_resume_hint = Label.new()
		_resume_hint.text = "Click to keep playing"
		_resume_hint.add_theme_font_size_override("font_size", 22)
		_resume_hint.add_theme_color_override("font_outline_color", Color.BLACK)
		_resume_hint.add_theme_constant_override("outline_size", 6)
		_resume_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_resume_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_resume_hint.grow_vertical = Control.GROW_DIRECTION_BOTH
		_resume_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_resume_hint)
	_resume_hint.visible = resume_pending
	menu.visible = not captured and not other_screen_open and not player.controls_locked() and not resume_pending
	if not menu.visible:
		cancel_leave()
	if not resume_pending:
		_resume_from_menu = false
	get_tree().paused = (menu.visible or _resume_from_menu) and not Network.main.in_online_raid()
	# Aiming down sights uses the gun's own sight instead of the crosshair (the hit marker still shows).
	crosshair.show_crosshair = captured and not player.out_of_fight() and not player.gun.is_aiming()
	crosshair.reticle = player.gun.reticle() if captured and not player.out_of_fight() else ""
	var hp := player.health.current

	# The inventory screen gets the whole view: only the raid timer stays (owner, 0.8.2).
	# The end-of-raid screen hides all of it (the raid is over, 0.8.10).
	for element: CanvasItem in [health_hud, ammo_hud, hotbar, crosshair, prompt_hud, extract_hud, world_labels, downed_hud]:
		element.visible = not loot_ui.visible and not end_screen.visible and not spectator.visible
	# Spectating a teammate: their name tag stays.
	world_labels.visible = world_labels.visible or spectator.visible
	timer_hud.visible = not end_screen.visible
	if map_hud.visible and (loot_ui.visible or end_screen.visible or spectator.visible):
		map_hud.visible = false

	if not get_tree().paused:
		# Red flash when hit; a faint red edge stays while health is low.
		# Downed: a heavier red edge.
		var low_health_alpha := 0.18 if hp <= 30 and not player.controls_locked() else 0.0
		if player.downed:
			low_health_alpha = 0.32
		vignette.color.a = maxf(vignette.color.a - delta * 1.5, low_health_alpha)
		_indicator_time -= delta
	damage_indicator.modulate.a = clampf(_indicator_time, 0.0, 1.0)
	if _indicator_time > 0.0 and player != null:
		_point_indicator()

	_update_debug(delta)


## Big buttons (touch-friendly). The confirm's LEAVE is red and never has focus, so a stray Enter/Space can't press it.
func _build_leave() -> void:
	var box := play_button.get_parent()
	leave_button = Button.new()
	leave_button.name = "LeaveButton"
	leave_button.text = "LEAVE RAID"
	leave_button.custom_minimum_size = Vector2(0, 52)
	leave_button.focus_mode = Control.FOCUS_NONE
	LootUI.style_button(leave_button, 30)
	leave_button.pressed.connect(ask_leave)
	box.add_child(leave_button)
	box.move_child(leave_button, play_button.get_index() + 1)

	leave_confirm = VBoxContainer.new()
	leave_confirm.name = "LeaveConfirm"
	leave_confirm.add_theme_constant_override("separation", 10)
	leave_confirm.visible = false
	var question := Label.new()
	question.text = "Leave the raid? It counts as dying: everything you carried is lost (your secure pocket comes home)."
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.style_label(question, 20)
	leave_confirm.add_child(question)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	leave_confirm.add_child(row)
	for entry in [["STAY", HudStyle.FACE, cancel_leave], ["LEAVE", HudStyle.BLOOD, confirm_leave]]:
		var button := Button.new()
		button.name = entry[0].capitalize()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(0, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		LootUI.style_button(button, 30, entry[1])
		button.pressed.connect(entry[2])
		row.add_child(button)
	box.add_child(leave_confirm)
	box.move_child(leave_confirm, leave_button.get_index() + 1)


## The quest tracker shows (freshly filled) with the pause menu.
func _show_quests() -> void:
	quest_tracker.visible = menu.visible
	if menu.visible:
		quest_tracker.refresh(menu)


## LEAVE RAID pressed: ask first, in case it was a misclick.
func ask_leave() -> void:
	leave_button.visible = false
	leave_confirm.visible = true


func cancel_leave() -> void:
	if leave_confirm != null and leave_confirm.visible:
		leave_confirm.visible = false
		leave_button.visible = true


func confirm_leave() -> void:
	cancel_leave()
	raid.leave()


func _capture_mouse() -> void:
	if not player.controls_locked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_capture_until = Time.get_ticks_msec() + 2000
		_capture_retry_at = Time.get_ticks_msec() + 150


## Asks again (a few times a second) while a click to resume is still fresh and the browser hasn't given the mouse.
func _retry_capture(captured: bool) -> void:
	var now := Time.get_ticks_msec()
	if captured or now > _capture_until or player.controls_locked() or loot_ui.visible or end_screen.visible:
		_capture_until = 0
	elif now >= _capture_retry_at:
		_capture_retry_at = now + 150
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
	if Vector2(source_position.x - player.global_position.x, source_position.z - player.global_position.z).length() < 0.1:
		return   # from right here (a fall): no direction to show
	_hit_from = source_position
	_point_indicator()
	_indicator_time = 1.2


## Points the arrow toward whoever hit us (0 = straight ahead). Every frame while it shows, so it stays right while
## you turn (0.12.31, owner: it felt off when turning fast; it used to keep the angle from the moment of the hit).
func _point_indicator() -> void:
	var local := player.global_basis.inverse() * (_hit_from - player.global_position)
	damage_indicator.rotation = atan2(local.x, -local.z)


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
