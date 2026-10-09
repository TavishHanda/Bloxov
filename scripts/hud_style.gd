class_name HudStyle
extends RefCounted
## The raid HUD's look (0.7.15, "Stenciled Field Kit"): dark gunmetal plates with notched corners, a chunky
## stencil pixel font (Jersey 10, OFL) for numbers and short labels, and little pixel icons drawn on a grid.
## Matches the inventory screen's slate and slot colors. Used by the HUD widgets (health, ammo, hotbar...).

const PLATE := Color("1e2328d1")
const PLATE_EDGE := Color("3a4148")
const PLATE_HI := Color("4a535c")
const WELL := Color("121417eb")
const TEXT := Color("e9e6dc")
const TEXT_DIM := Color("8c9196")
const HP_GOOD := Color("6bd36b")
const HP_MID := Color("e8c547")
const WARN := Color("d9483b")
const STAMINA := Color("e8c547")
const ACTIVE := Color("f2c14e")
const EXTRACT := Color("57e07a")
const BRASS := Color("e8c547")
const NOTCH := 4.0

const FONT_PATH := "res://assets/fonts/Jersey10-Regular.ttf"

## Pixel icons ("#" = a pixel), drawn with draw_icon().
const RIFLE := ["..........#.....", "################", "#####.#####.....", "##...##.##......", "##.....##......."]
const PISTOL := ["########", "########", "###.#...", "##......", "##......"]
const MED := ["..###..", "..###..", "#######", "#######", "#######", "..###..", "..###.."]
const KNIFE := ["####.#######", "#####.######", "....#......."]
const GRENADE := [".##...", "####..", ".####.", "######", "######", "######", ".####."]
const FLAG := ["#....", "####.", "#####", "####.", "#....", "#....", "#...."]

static var _font: FontFile


## The pixel font, crisp (no smoothing). Use sizes in multiples of 10.
static func font() -> FontFile:
	if _font == null:
		# The imported font (the raw .ttf isn't in the web build), switched to crisp pixel rendering.
		_font = (load(FONT_PATH) as FontFile).duplicate()
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font.generate_mipmaps = false
	return _font


## Gives a Label the HUD look: the pixel font with a hard drop shadow (or the default font, outlined, for names).
static func style_label(label: Label, size: int, color := TEXT, pixel := true) -> void:
	if pixel:
		label.add_theme_font_override("font", font())
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		label.add_theme_constant_override("shadow_outline_size", 0)
		label.add_theme_constant_override("outline_size", 0)
	else:
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


## A notched plate: an octagon (corners cut by NOTCH px), a 2 px border and a 1 px highlight along the top.
static func draw_plate(ci: CanvasItem, rect: Rect2, border := PLATE_EDGE, fill := PLATE, notch := NOTCH) -> void:
	if rect.size.x <= notch * 2.0 + 1.0 or rect.size.y <= notch * 2.0 + 1.0:
		return  # too small to draw (e.g. behind empty text)
	var points := _octagon(rect, notch)
	ci.draw_colored_polygon(points, fill)
	var outline := points.duplicate()
	outline.append(points[0])
	ci.draw_polyline(outline, border, 2.0)
	ci.draw_line(rect.position + Vector2(notch + 1, 2), Vector2(rect.end.x - notch - 1, rect.position.y + 2), PLATE_HI, 1.0)


static func _octagon(rect: Rect2, notch: float) -> PackedVector2Array:
	var a := rect.position
	var b := rect.end
	return PackedVector2Array([
		Vector2(a.x + notch, a.y), Vector2(b.x - notch, a.y), Vector2(b.x, a.y + notch), Vector2(b.x, b.y - notch),
		Vector2(b.x - notch, b.y), Vector2(a.x + notch, b.y), Vector2(a.x, b.y - notch), Vector2(a.x, a.y + notch)])


## Draws a pixel icon (rows of "#"/".") at `origin`, each pixel `px` big, with a hard black shadow.
static func draw_icon(ci: CanvasItem, rows: Array, origin: Vector2, px: float, color: Color) -> void:
	for pass_index in 2:
		var offset := Vector2(px, px) * 0.5 if pass_index == 0 else Vector2.ZERO
		var c := Color(0, 0, 0, color.a * 0.8) if pass_index == 0 else color
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] == "#":
					ci.draw_rect(Rect2(origin + Vector2(x, y) * px + offset, Vector2(px, px)), c)


static func icon_size(rows: Array, px: float) -> Vector2:
	return Vector2(String(rows[0]).length(), rows.size()) * px


## Text in the pixel font with a hard shadow, at baseline `pos` (align: 0 left, 1 center, 2 right within `width`).
static func draw_text(ci: CanvasItem, text: String, pos: Vector2, size: int, color: Color, width := -1.0, align := 0) -> void:
	var h_align: HorizontalAlignment = [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT][align]
	ci.draw_string(font(), pos + Vector2(2, 2), text, h_align, width, size, Color(0, 0, 0, color.a))
	ci.draw_string(font(), pos, text, h_align, width, size, color)


## The health color for a fraction of max health.
static func health_color(fraction: float) -> Color:
	if fraction <= 0.3:
		return WARN
	return HP_MID if fraction <= 0.6 else HP_GOOD
