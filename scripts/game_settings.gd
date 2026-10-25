class_name GameSettings
extends RefCounted
## Player settings (volume, mouse sensitivity, damage numbers, graphics), saved to user://settings.cfg.
## On web, user:// is stored in the browser, so settings survive reloads.

const PATH := "user://settings.cfg"

## 0.0 to 1.0
static var volume := 0.6
## The sound mix (Sound update 0.20.7), each 0.0 to 1.0 on top of `volume`: game effects, the AI's voices, the
## background ambience and the menus. Each is a sound bus (made by Hearing / UISounds when first used).
static var mix := {"effects": 1.0, "voices": 1.0, "ambience": 1.0, "ui": 1.0}
const MIX_BUSES := {"effects": &"World", "voices": &"Voices", "ambience": &"Ambience", "ui": &"UI"}
const MIX_NAMES := {"effects": "Effects", "voices": "Voices", "ambience": "Ambience", "ui": "Menus"}
## Multiplier on the player's base mouse sensitivity.
static var sensitivity := 1.0
## Floating damage numbers on hits (off by default: Bloxov keeps hit feedback subtle).
static var damage_numbers := false
## Lean: hold Q/E (false) or tap to toggle (true; planned default for touch screens).
static var lean_toggle := false
## Graphics (Look update 0.19, for phones and weak laptops): LOW, MEDIUM or HIGH. Changes how things are drawn
## (sun shadows, how close buildings switch to their far mesh, render scale), never what you can see through:
## bushes, grass and fog are the same on every setting. Phones start on LOW, everything else on HIGH.
static var graphics := HIGH
## Last server and name used to go online from the hideout.
static var server_address := ""
static var player_name := ""

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const GRAPHICS_NAMES := ["Low", "Medium", "High"]
## Per setting (LOW, MEDIUM, HIGH): sun shadow reach in metres (0 = no shadows), shadow map size, how far out
## buildings switch to their far mesh (times FarView.FROM), and the 3D render scale (off the web only: render_scale()).
const SHADOW_DISTANCE := [0.0, 40.0, 60.0]
const SHADOW_SIZE := [1024, 2048, 4096]
const FAR_SCALE := [0.65, 0.8, 1.0]
const RENDER_SCALE := [0.7, 0.85, 1.0]

static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		volume = cfg.get_value("audio", "volume", volume)
		for key: String in mix:
			mix[key] = clampf(float(cfg.get_value("audio", key, mix[key])), 0.0, 1.0)
		sensitivity = cfg.get_value("controls", "sensitivity", sensitivity)
		damage_numbers = cfg.get_value("gameplay", "damage_numbers", damage_numbers)
		lean_toggle = cfg.get_value("controls", "lean_toggle", lean_toggle)
		server_address = cfg.get_value("online", "server_address", server_address)
		player_name = cfg.get_value("online", "player_name", player_name)
	if not cfg.has_section_key("graphics", "quality"):
		graphics = LOW if is_phone() else HIGH
	else:
		graphics = clampi(cfg.get_value("graphics", "quality", graphics), LOW, HIGH)
	apply()


static func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	apply()
	save()


static func set_mix(key: String, value: float) -> void:
	mix[key] = clampf(value, 0.0, 1.0)
	apply_mix()
	save()


## Puts the mix on its buses (those made so far).
static func apply_mix() -> void:
	for key: String in mix:
		var bus := AudioServer.get_bus_index(MIX_BUSES[key])
		if bus >= 0:
			AudioServer.set_bus_mute(bus, mix[key] <= 0.001)
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(mix[key] * mix[key], 0.0001)))


static func set_sensitivity(value: float) -> void:
	sensitivity = clampf(value, 0.1, 3.0)
	save()


static func set_lean_toggle(on: bool) -> void:
	lean_toggle = on
	save()


static func set_damage_numbers(on: bool) -> void:
	damage_numbers = on
	save()


static func set_online(address: String, online_name: String) -> void:
	server_address = address
	player_name = online_name
	save()


static func set_graphics(value: int) -> void:
	graphics = clampi(value, LOW, HIGH)
	apply()
	save()


## A phone or tablet (the app, or the web game in a phone's browser).
static func is_phone() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


## Puts the graphics setting on the game's window and the raid being played (if any): render scale, the sun's
## shadows, and where buildings switch to their far mesh. Raids made later pick it up from Look.apply / FarView.
static func apply_graphics() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.root.scaling_3d_scale = render_scale()
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZE[graphics], true)
	var raid := tree.current_scene
	if raid != null:
		shadows_on(raid.get_node_or_null("Sun") as DirectionalLight3D)
	FarView.refresh(tree)


## The 3D render scale for the graphics setting. Always 1 in browsers (and anywhere Godot runs on ANGLE): there a
## scaled 3D picture makes Godot copy the depth buffer through the CPU every frame (ANGLE on Direct3D 11, i.e. every
## browser on Windows), which made Low and Medium slower than High (0.20.20).
static func render_scale() -> float:
	if OS.has_feature("web") or RenderingServer.get_video_adapter_name().contains("ANGLE"):
		return 1.0
	return RENDER_SCALE[graphics]


## Gives `sun` the graphics setting's shadows.
static func shadows_on(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	sun.shadow_enabled = SHADOW_DISTANCE[graphics] > 0.0
	sun.directional_shadow_max_distance = maxf(SHADOW_DISTANCE[graphics], 1.0)


static func apply() -> void:
	apply_graphics()
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	# Squared so the slider feels even (ears hear loudness logarithmically).
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume * volume, 0.0001)))
	apply_mix()


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	for key: String in mix:
		cfg.set_value("audio", key, mix[key])
	cfg.set_value("controls", "sensitivity", sensitivity)
	cfg.set_value("gameplay", "damage_numbers", damage_numbers)
	cfg.set_value("controls", "lean_toggle", lean_toggle)
	cfg.set_value("online", "server_address", server_address)
	cfg.set_value("online", "player_name", player_name)
	cfg.set_value("graphics", "quality", graphics)
	cfg.save(PATH)
