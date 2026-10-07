extends CanvasLayer
## Crosshair, hit markers, health, ammo, damage flash, hit-direction arrow, pause menu and death screen.
## The game pauses whenever the mouse isn't captured (menu open). This node keeps running while paused.
## F3 toggles a debug overlay. F4 toggles raw mouse input (web only; press Esc and click to re-lock).

@export var player: Player

@onready var crosshair: Label = $Crosshair
@onready var hit_marker: Label = $HitMarker
@onready var health_label: Label = $HealthLabel
@onready var ammo_label: Label = $AmmoLabel
@onready var vignette: ColorRect = $Vignette
@onready var damage_indicator: Control = $DamageIndicator
@onready var death_screen: ColorRect = $DeathScreen
@onready var death_label: Label = $DeathScreen/DeathLabel
@onready var debug_label: Label = $Debug
@onready var menu: Control = $Menu
@onready var play_button: Button = $Menu/Margin/VBox/PlayButton
@onready var volume_slider: HSlider = $Menu/Margin/VBox/VolumeRow/Slider
@onready var volume_value: Label = $Menu/Margin/VBox/VolumeRow/Value
@onready var sensitivity_slider: HSlider = $Menu/Margin/VBox/SensitivityRow/Slider
@onready var sensitivity_value: Label = $Menu/Margin/VBox/SensitivityRow/Value
@onready var menu_version: Label = $Menu/Margin/VBox/Version
@onready var corner_version: Label = $VersionCorner

var _hit_marker_time := 0.0
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
	play_button.pressed.connect(_capture_mouse)

	player.health.damaged.connect(_on_player_damaged)
	player.health.died.connect(_on_player_died)
	player.gun.hit_confirmed.connect(_on_hit_confirmed)
	hit_marker.visible = false
	death_screen.visible = false


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
	menu.visible = not captured and not player.is_dead
	get_tree().paused = menu.visible
	crosshair.visible = captured and not player.is_dead

	var gun := player.gun
	ammo_label.text = "RELOADING..." if gun.is_reloading else "%d / %d" % [gun.in_mag, gun.reserve]
	ammo_label.modulate = Color(1, 0.4, 0.3) if gun.in_mag == 0 and not gun.is_reloading else Color.WHITE
	var hp := player.health.current
	health_label.text = "HP %d" % hp
	health_label.modulate = Color(1, 0.35, 0.3) if hp <= 30 else Color.WHITE

	if not get_tree().paused:
		# Red flash when hit; a faint red edge stays while health is low.
		var low_health_alpha := 0.18 if hp <= 30 and not player.is_dead else 0.0
		vignette.color.a = maxf(vignette.color.a - delta * 1.5, low_health_alpha)
		_hit_marker_time -= delta
		_indicator_time -= delta
	hit_marker.visible = _hit_marker_time > 0.0
	damage_indicator.modulate.a = clampf(_indicator_time, 0.0, 1.0)

	_update_debug(delta)


func _capture_mouse() -> void:
	if not player.is_dead:
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


func _on_hit_confirmed(killed: bool, headshot: bool) -> void:
	_hit_marker_time = 0.25 if killed else 0.1
	if killed:
		hit_marker.modulate = Color(1, 0.25, 0.2)
		hit_marker.scale = Vector2(1.6, 1.6)
	elif headshot:
		hit_marker.modulate = Color(1, 0.85, 0.1)
		hit_marker.scale = Vector2(1.25, 1.25)
	else:
		hit_marker.modulate = Color.WHITE
		hit_marker.scale = Vector2.ONE


func _on_player_damaged(_amount: int, source_position: Vector3) -> void:
	vignette.color.a = 0.45
	# Point the arrow toward whoever hit us (0 = straight ahead).
	var local := player.global_basis.inverse() * (source_position - player.global_position)
	damage_indicator.rotation = atan2(local.x, -local.z)
	_indicator_time = 1.2


func _on_player_died() -> void:
	death_screen.visible = true
	death_label.text = "YOU DIED\n\nKills: %d\n\nClick to try again" % player.gun.kills


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
