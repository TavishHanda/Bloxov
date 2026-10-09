class_name PauseMenuStyle
extends RefCounted
## Gives the pause menu (HUD/Menu in main.tscn) the "Ammo Can" look (0.8.14): a gunmetal plate, BLOXOV in the big
## pixel font, a hazard-yellow PLAY button, sliders with a brass fill and a gunmetal handle, checkboxes as small
## sunk-in boxes with a yellow block when ticked. The long controls list stays in the plain font (easier to read).
## Only restyles: the nodes, their names and what they do stay as they are in the scene.


const WIDTH := 640.0


static func apply(menu: PanelContainer) -> void:
	LootUI.skin_panel(menu)
	# Wide enough that the controls list doesn't wrap mid-line.
	menu.offset_left = -WIDTH * 0.5
	menu.offset_right = WIDTH * 0.5
	var box := menu.get_node("Margin/VBox")
	HudStyle.style_label(box.get_node("Title"), 50)
	var version: Label = box.get_node("Version")
	HudStyle.style_label(version, 20, Color(HudStyle.INK, 0.45))
	version.modulate = Color.WHITE
	var play: Button = box.get_node("PlayButton")
	LootUI.style_button(play, 30, HudStyle.HAZARD)
	for row_name in ["VolumeRow", "SensitivityRow"]:
		var row := box.get_node(row_name)
		var title: Label = row.get_node("Label")
		HudStyle.style_label(title, 20, HudStyle.INK_DIM)
		title.add_theme_font_override("font", HudStyle.spaced_font(20))
		HudStyle.style_label(row.get_node("Value"), 20)
		style_slider(row.get_node("Slider"))
	for check_name in ["DamageNumbers", "LeanToggle"]:
		style_check(box.get_node(check_name))
	var controls: Label = box.get_node("Controls")
	controls.modulate = Color.WHITE
	controls.add_theme_color_override("font_color", HudStyle.INK_DIM)
	controls.text = reflow(controls.text, controls.get_theme_font("font"), controls.get_theme_font_size("font_size"), WIDTH - 70.0)


## Re-flows the controls list so lines only break between controls ("A · B · C"), never inside one.
## Lines without " · " (sentences) are kept as they are.
static func reflow(text: String, font: Font, size: int, width: float) -> String:
	var items: PackedStringArray = []
	var rest: PackedStringArray = []
	for line in text.split("\n"):
		if line.contains(" · "):
			items.append_array(line.split(" · "))
		else:
			rest.append(line)
	var lines: PackedStringArray = []
	var current := ""
	for item in items:
		var candidate := item if current == "" else current + " · " + item
		if current != "" and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			lines.append(current)
			current = item
		else:
			current = candidate
	if current != "":
		lines.append(current)
	lines.append_array(rest)
	return "\n".join(lines)


## A slider: a sunk-in track that fills with brass up to the handle, and a small gunmetal handle with a brass line.
static func style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = HudStyle.DEEP
	track.border_color = Color.BLACK
	track.set_border_width_all(2)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = HudStyle.BRASS
	fill.border_color = Color.BLACK
	fill.set_border_width_all(2)
	fill.border_width_right = 0
	slider.add_theme_stylebox_override("grabber_area", fill)
	var fill_hover := fill.duplicate() as StyleBoxFlat
	fill_hover.bg_color = HudStyle.BRASS_HI
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hover)
	slider.add_theme_icon_override("grabber", _handle(HudStyle.FACE_HI))
	slider.add_theme_icon_override("grabber_highlight", _handle(HudStyle.FACE_HI.lightened(0.2)))


## A checkbox: the label in the pixel font, and a small sunk-in box (yellow block inside when ticked).
static func style_check(check: CheckBox) -> void:
	check.add_theme_font_override("font", HudStyle.spaced_font(20))
	check.add_theme_font_size_override("font_size", 20)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		check.add_theme_color_override(color_name, HudStyle.INK)
	check.add_theme_constant_override("h_separation", 10)
	check.add_theme_icon_override("unchecked", _box(false))
	check.add_theme_icon_override("checked", _box(true))
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		check.add_theme_stylebox_override(state, StyleBoxEmpty.new())


## The slider handle: a 12x22 gunmetal block (black outline, lit top edge) with a brass line down the middle.
static func _handle(face: Color) -> ImageTexture:
	var image := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.fill_rect(Rect2i(2, 2, 8, 18), face)
	image.fill_rect(Rect2i(2, 2, 8, 2), face.lightened(0.25))
	image.fill_rect(Rect2i(2, 18, 8, 2), face.darkened(0.35))
	image.fill_rect(Rect2i(5, 6, 2, 10), HudStyle.BRASS)
	return ImageTexture.create_from_image(image)


## The checkbox: an 18x18 sunk-in box; ticked = a hazard-yellow block inside.
static func _box(ticked: bool) -> ImageTexture:
	var image := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.fill_rect(Rect2i(2, 2, 14, 14), HudStyle.DEEP)
	image.fill_rect(Rect2i(2, 2, 14, 2), Color(0, 0, 0, 1))
	if ticked:
		image.fill_rect(Rect2i(5, 5, 8, 8), HudStyle.HAZARD)
		image.fill_rect(Rect2i(5, 5, 8, 2), HudStyle.HAZARD.lightened(0.35))
	return ImageTexture.create_from_image(image)
