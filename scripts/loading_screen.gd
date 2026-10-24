class_name LoadingScreen
extends Control
## The loading screen (Look update 0.19.3, owner picked look B "map vista"): a shot of the map with the late
## afternoon look, the map's name, a random tip and ENTERING THE RAID. The hideout puts it up when START RAID is
## pressed; the web build can't draw while the raid loads, so it's a still picture, not a moving bar. The raid then
## puts the same screen (same tip) over its first second, while it settles (shaders, the AI's map), and fades it out.
## The picture is `tools/render_views.gd`'s "town" view with the current look, saved as a .jpg.

const PICTURE := "res://assets/textures/loading_battlegrounds.jpg"
const MAP_NAME := "Bloxov Battlegrounds"
## How long the raid keeps it up (seconds, counted once the raid is drawing) and how long the fade takes.
const HOLD := 0.8
const FADE := 0.5
## Gameplay tips (true for desktop and phones alike: no keys named).
const TIPS := [
	"Crouch-walking is quiet: scavs hear sprinting footsteps from much farther away.",
	"Crouching or standing still makes you harder for scavs to spot.",
	"An extract only works while it's open. Check the map for yours before the timer runs out.",
	"Searching containers takes time. Listen out while you loot.",
	"Items found in raid can be handed in for quests at the traders.",
	"Kills only count for quests if you make it out alive.",
	"Low walls, sandbags and crates can be vaulted. Jump at them.",
	"Lean round corners to shoot while showing less of yourself.",
	"Some doors need keys. The bunker and the bank vault hide the best loot.",
	"Bandages stop bleeding. Heal up in cover before you push.",
]

## The tip picked for this load, so the raid shows the same one the hideout did.
static var tip := ""

## Set on the raid's copy: fade out (and free its layer) once the raid has settled.
var fades := false


## A new loading screen (picks a new tip).
static func make() -> LoadingScreen:
	tip = TIPS.pick_random()
	var screen := LoadingScreen.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	return screen


## Puts the loading screen over `raid` (a raid scene being made) and fades it once the raid has settled.
## Not on servers or headless runs.
static func cover(raid: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.name = "LoadingCover"
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS   # (the HUD pauses the raid until the mouse is captured)
	var screen := make() if tip == "" else _again()
	screen.fades = true
	layer.add_child(screen)
	raid.add_child(layer)


static func _again() -> LoadingScreen:
	var keep := tip
	var screen := make()
	tip = keep
	return screen


func _ready() -> void:
	var picture := TextureRect.new()
	picture.texture = load(PICTURE)
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(picture)
	# Dark from the middle down, so the words read on any picture.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([Color(0.04, 0.04, 0.05, 0.0), Color(0.04, 0.04, 0.05, 0.0), Color(0.04, 0.04, 0.05, 0.92)])
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = gradient
	shade_texture.fill_from = Vector2(0, 0)
	shade_texture.fill_to = Vector2(0, 1)
	shade.texture = shade_texture
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = MAP_NAME.to_upper()
	HudStyle.style_label(title, 50)
	column.add_child(title)
	var bar := ColorRect.new()
	bar.color = HudStyle.BRASS
	bar.custom_minimum_size = Vector2(380, 5)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(bar)
	var tip_label := Label.new()
	tip_label.text = "TIP: " + tip
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.style_label(tip_label, 22, HudStyle.INK, false)
	tip_label.add_theme_font_override("font", HudStyle.tape_font())
	column.add_child(tip_label)
	var entering := Label.new()
	entering.text = "ENTERING THE RAID..."
	entering.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	HudStyle.style_label(entering, 30, HudStyle.BRASS)
	column.add_child(entering)
	if fades:
		_fade_out()


## Waits for the raid to settle (HOLD seconds of drawing), then fades out and frees its layer.
func _fade_out() -> void:
	var tree := get_tree()
	for i in 3:   # (the first frames after a load take long; start the clock once frames are coming)
		await tree.process_frame
	await tree.create_timer(HOLD, true, false, true).timeout
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE)
	await tween.finished
	tip = ""
	get_parent().queue_free()
