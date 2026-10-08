class_name GameSettings
extends RefCounted
## Player settings (volume, mouse sensitivity), saved to user://settings.cfg.
## On web, user:// is stored in the browser, so settings survive reloads.

const PATH := "user://settings.cfg"

## 0.0 to 1.0
static var volume := 0.6
## Multiplier on the player's base mouse sensitivity.
static var sensitivity := 1.0
## Floating damage numbers on hits (off by default: Bloxov keeps hit feedback subtle).
static var damage_numbers := false

static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		volume = cfg.get_value("audio", "volume", volume)
		sensitivity = cfg.get_value("controls", "sensitivity", sensitivity)
		damage_numbers = cfg.get_value("gameplay", "damage_numbers", damage_numbers)
	apply()


static func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	apply()
	save()


static func set_sensitivity(value: float) -> void:
	sensitivity = clampf(value, 0.1, 3.0)
	save()


static func set_damage_numbers(on: bool) -> void:
	damage_numbers = on
	save()


static func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	# Squared so the slider feels even (ears hear loudness logarithmically).
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume * volume, 0.0001)))


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("controls", "sensitivity", sensitivity)
	cfg.set_value("gameplay", "damage_numbers", damage_numbers)
	cfg.save(PATH)
