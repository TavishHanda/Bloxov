class_name HudStyle
extends RefCounted
## The raid HUD's look (0.8.4, "Ammo Can"): chunky beveled blocks of gunmetal-painted steel, built like the voxels
## of the world (lit top/left edge, dark bottom/right edge, hard black outline), with brass, hazard stripes and
## masking-tape labels as the scavenged details. Fonts (all OFL, in assets/fonts/, see the README there):
## - "Bloxov Jersey" for numbers and text (font(size)): the Jersey pixel family, one design per size, each drawn at
##   exactly 1 screen pixel per font pixel (0.8.13): size 20 = Jersey 10, 30 = Jersey 15, 40 = Jersey 20,
##   50 = Jersey 25. Only use those sizes: in between, pixels land between screen pixels and letters look uneven.
##   (Jersey 10 also has a redrawn square-topped A, 0.8.12.)
## - Silkscreen Bold for tiny stenciled labels (size 8), Pixelify Sans for writing on tape.
## Used by the HUD widgets (health, ammo, hotbar, crosshair...).

# Painted steel.
const FACE := Color("353a40")
const FACE_HI := Color("545b63")
const FACE_DK := Color("1e2125")
const DEEP := Color("121417")
const OUTLINE := Color(0, 0, 0, 0.85)
# Markings.
const INK := Color("efe6c4")
const INK_DIM := Color("efe6c49e")
const BRASS := Color("e2a83e")
const BRASS_HI := Color("f0c873")
const BRASS_DK := Color("9c6a1e")
const COPPER := Color("b8692f")
const HAZARD := Color("f4c430")
const BLOOD := Color("d33b2c")
const LIFE := Color("8fd14f")
const TAPE := Color("dccb98")
const TAPE_INK := Color("1d1b22")
const WOOD := Color("7a4a26")
const EXTRACT := Color("57e07a")

# Older names (0.8.3), mapped onto the new palette.
const PLATE := FACE
const PLATE_EDGE := OUTLINE
const PLATE_HI := FACE_HI
const WELL := DEEP
const TEXT := INK
const TEXT_DIM := INK_DIM
const HP_GOOD := LIFE
const HP_MID := HAZARD
const WARN := BLOOD
const STAMINA := HAZARD
const ACTIVE := HAZARD
const NOTCH := 3.0

## The Jersey design for each text size (each 1x at its size; built by tools/make_bloxov_font.py).
const FONT_PATHS := {
	20: "res://assets/fonts/BloxovJersey10-Regular.ttf",
	30: "res://assets/fonts/BloxovJersey15-Regular.ttf",
	40: "res://assets/fonts/BloxovJersey20-Regular.ttf",
	50: "res://assets/fonts/BloxovJersey25-Regular.ttf",
}
const LABEL_FONT_PATH := "res://assets/fonts/Silkscreen-Bold.ttf"
const TAPE_FONT_PATH := "res://assets/fonts/PixelifySans.ttf"

## Pixel icons ("#" = a pixel, "=" = a pixel of handle/wood), drawn with draw_icon().
const RIFLE := ["..........#.....", "################", "#####.#####.....", "##...##.##......", "##.....##......."]
const PISTOL := ["########", "########", "###.#...", "##......", "##......"]
const MED := ["..###..", "..###..", "#######", "#######", "#######", "..###..", "..###.."]
## A rolled bandage (side view: the roll and its loose end), for the meds slot when it'll use a bandage.
const BANDAGE := [".#####...", "#######..", "##...##..", "##.#.##..", "##...##..", "#######..", ".########"]
const KNIFE := [".....#............", "=====#############", "=====############.", "=====##########...", ".....#............"]
const GRENADE := [".##...", "####..", ".####.", "######", "######", "######", ".####."]
const FLAG := ["#....", "####.", "#####", "####.", "#....", "#....", "#...."]

## Hand-drawn 3x5 key glyphs (the small stencil font's "4" has an odd flag): hotbar keys and key caps.
const KEY_GLYPHS := {
	"1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["##.", "..#", ".#.", "#..", "###"],
	"3": ["##.", "..#", ".#.", "..#", "##."],
	"4": ["#.#", "#.#", "###", "..#", "..#"],
	"5": ["###", "#..", "##.", "..#", "##."],
	"6": [".##", "#..", "##.", "#.#", ".#."],
	"V": ["#.#", "#.#", "#.#", "#.#", ".#."],
	"F": ["###", "#..", "##.", "#..", "#.."],
	"O": [".#.", "#.#", "#.#", "#.#", ".#."],
	"H": ["#.#", "#.#", "###", "#.#", "#.#"],
	"A": [".#.", "#.#", "###", "#.#", "#.#"],
	"M": ["#.#", "###", "###", "#.#", "#.#"],
}

static var _fonts := {}


## The pixel font for text drawn at `size` (20, 30, 40 or 50: the Jersey design made for it), crisp.
static func font(size := 20) -> FontFile:
	return _crisp(FONT_PATHS[design_size(size)])


## The closest of the sizes the fonts are made for (20, 30, 40, 50).
static func design_size(size: int) -> int:
	return clampi(roundi(size / 10.0) * 10, 20, 50)


## The pixel font at `size` with 1 px between letters, for words in mixed case ("Unarmed", item names).
static func spaced_font(size := 20) -> FontVariation:
	var key := "spaced%d" % design_size(size)
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = font(size)
		f.spacing_glyph = 1
		_fonts[key] = f
	return _fonts[key]


## Tiny stenciled labels (Silkscreen Bold). Use sizes in multiples of 8.
static func label_font() -> FontFile:
	return _crisp(LABEL_FONT_PATH)


## Marker writing on tape (Pixelify Sans).
static func tape_font() -> FontFile:
	return _crisp(TAPE_FONT_PATH)


static func _crisp(path: String) -> FontFile:
	if not _fonts.has(path):
		# The imported font (the raw .ttf isn't in the web build), switched to crisp pixel rendering.
		var f := (load(path) as FontFile).duplicate()
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.generate_mipmaps = false
		_fonts[path] = f
	return _fonts[path]


## Gives a Label the HUD look: the number font with a hard drop shadow (or the default font, outlined, for names).
static func style_label(label: Label, size: int, color := INK, pixel := true) -> void:
	if pixel:
		label.add_theme_font_override("font", font(size))
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 2 if size >= 20 else 1)
		label.add_theme_constant_override("shadow_outline_size", 0)
		label.add_theme_constant_override("outline_size", 0)
	else:
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


## A beveled voxel block: dark base, a lit top/left bevel, the face inset by `bevel`, and a 2 px outline.
static func draw_block(ci: CanvasItem, rect: Rect2, face := FACE, hi := FACE_HI, dk := FACE_DK, bevel := 3.0, outline := OUTLINE) -> void:
	if outline.a > 0.0:
		ci.draw_rect(rect.grow(2), outline)
	ci.draw_rect(rect, dk)
	var a := rect.position
	var b := rect.end
	ci.draw_colored_polygon(PackedVector2Array([a, Vector2(b.x, a.y), Vector2(b.x - bevel, a.y + bevel),
		Vector2(a.x + bevel, b.y - bevel), Vector2(a.x, b.y)]), hi)
	ci.draw_rect(Rect2(a + Vector2(bevel, bevel), rect.size - Vector2(bevel, bevel) * 2.0), face)


## A gunmetal plate (a block). `border` replaces the black outline (e.g. red on the timer's last minute).
static func draw_plate(ci: CanvasItem, rect: Rect2, border := OUTLINE, fill := FACE, bevel := NOTCH) -> void:
	if rect.size.x <= bevel * 2.0 + 1.0 or rect.size.y <= bevel * 2.0 + 1.0:
		return  # too small to draw (e.g. behind empty text)
	var hi := FACE_HI if fill == FACE else fill.lightened(0.25)
	var dk := FACE_DK if fill == FACE else fill.darkened(0.4)
	draw_block(ci, rect, fill, hi, dk, bevel, border)


## A sunk-in well (an empty slot): dark, with the shadow on the top/left edge.
static func draw_well(ci: CanvasItem, rect: Rect2, alpha := 1.0) -> void:
	ci.draw_rect(rect.grow(2), Color(OUTLINE, OUTLINE.a * alpha))
	ci.draw_rect(rect, Color(DEEP, 0.55 * alpha))
	ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)), Color(0, 0, 0, 0.5 * alpha))
	ci.draw_rect(Rect2(rect.position, Vector2(2, rect.size.y)), Color(0, 0, 0, 0.5 * alpha))


## A little rivet (2x2 highlight on a 3x3 shadow).
static func draw_rivet(ci: CanvasItem, pos: Vector2) -> void:
	ci.draw_rect(Rect2(pos, Vector2(3, 3)), FACE_DK)
	ci.draw_rect(Rect2(pos, Vector2(2, 2)), FACE_HI.lightened(0.2))


## Diagonal hazard stripes (yellow on dark) filling `rect`; `scroll` shifts them sideways.
static func draw_hazard(ci: CanvasItem, rect: Rect2, alpha := 1.0, width := 6.0, scroll := 0.0, stripe := HAZARD) -> void:
	ci.draw_rect(rect, Color(DEEP, alpha))
	var h := rect.size.y
	var x := -h - width + fmod(scroll, width)
	while x < rect.size.x:
		var pts := PackedVector2Array()
		for p in [Vector2(x, h), Vector2(x + width * 0.5, h), Vector2(x + width * 0.5 + h, 0), Vector2(x + h, 0)]:
			pts.append(rect.position + Vector2(clampf(p.x, 0.0, rect.size.x), p.y))
		ci.draw_colored_polygon(pts, Color(stripe, alpha))
		x += width


## A strip of masking tape stuck on at an angle, with `text` written on it. `rect` is before the tilt.
static func draw_tape(ci: CanvasItem, rect: Rect2, text: String, angle_deg := -2.0, alpha := 1.0, size := 16) -> void:
	ci.draw_set_transform(rect.get_center(), deg_to_rad(angle_deg))
	var local := Rect2(-rect.size * 0.5, rect.size)
	ci.draw_colored_polygon(_torn(Rect2(local.position + Vector2(2, 3), local.size)), Color(0, 0, 0, 0.4 * alpha))
	ci.draw_colored_polygon(_torn(local), Color(TAPE, alpha))
	ci.draw_line(local.position + Vector2(4, 3), Vector2(local.end.x - 4, local.position.y + 3), Color(1, 1, 1, 0.18 * alpha), 1.0)
	draw_centered(ci, text, local, size, Color(TAPE_INK, alpha), tape_font(), false)
	ci.draw_set_transform(Vector2.ZERO)


## The width a tape strip needs for `text`.
static func tape_width(text: String, size := 16) -> float:
	return tape_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 20.0


## A rectangle with little zigzag (torn) ends.
static func _torn(rect: Rect2) -> PackedVector2Array:
	var a := rect.position
	var b := rect.end
	var pts := PackedVector2Array([a, Vector2(b.x, a.y)])
	var steps := maxi(int(rect.size.y / 4.0), 2)
	for i in range(1, steps):
		pts.append(Vector2(b.x - (2.0 if i % 2 else 0.0), a.y + i * rect.size.y / steps))
	pts.append_array([b, Vector2(a.x, b.y)])
	for i in range(steps - 1, 0, -1):
		pts.append(Vector2(a.x + (2.0 if i % 2 else 0.0), a.y + i * rect.size.y / steps))
	return pts


## Draws a pixel icon (rows of "#"/"=" /".") at `origin`, each pixel `px` big, with a hard shadow.
## "=" pixels are wood (a knife's handle) unless the icon is drawn faded.
static func draw_icon(ci: CanvasItem, rows: Array, origin: Vector2, px: float, color: Color, shadow := Color(0, 0, 0, 0.7)) -> void:
	for pass_index in 2:
		if pass_index == 0 and shadow.a <= 0.0:
			continue
		var offset := Vector2.ONE * maxf(px * 0.5, 1.0) if pass_index == 0 else Vector2.ZERO
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				var ch := row[x]
				if ch == "." or ch == " ":
					continue
				var c := Color(shadow, shadow.a * color.a)
				if pass_index == 1:
					c = Color(WOOD, color.a) if ch == "=" else color
				ci.draw_rect(Rect2(origin + Vector2(x, y) * px + offset, Vector2(px, px)), c)


static func icon_size(rows: Array, px: float) -> Vector2:
	return Vector2(String(rows[0]).length(), rows.size()) * px


## Where a text's hard shadow goes: straight down (0.8.12; a diagonal one filled the 1-pixel gaps between letters
## and made them look squished together).
static func text_shadow(size: int) -> Vector2:
	return Vector2(0, 2) if size >= 20 else Vector2(0, 1)


## Text in the number font with a hard shadow, at baseline `pos` (align: 0 left, 1 center, 2 right within `width`).
static func draw_text(ci: CanvasItem, text: String, pos: Vector2, size: int, color: Color, width := -1.0, align := 0, f: Font = null) -> void:
	var h_align: HorizontalAlignment = [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT][align]
	if f == null:
		f = font(size)
	ci.draw_string(f, pos + text_shadow(size), text, h_align, width, size, Color(0, 0, 0, color.a * 0.9))
	ci.draw_string(f, pos, text, h_align, width, size, color)


## A key name ("1".."6", "V", "F", "O", "H") in the hand-drawn key glyphs, `px` per pixel, top-left at `pos`.
static func draw_key(ci: CanvasItem, key: String, pos: Vector2, color: Color, px := 1.0, shadow := true) -> void:
	var rows: Array = KEY_GLYPHS.get(key, KEY_GLYPHS["F"])
	draw_icon(ci, rows, pos, px, color, Color(0, 0, 0, 0.8) if shadow else Color(0, 0, 0, 0))


## A key cap: a small cream beveled block with the key's glyph centered on it (for "[F] Search"-style prompts).
static func draw_keycap(ci: CanvasItem, rect: Rect2, key: String) -> void:
	draw_block(ci, rect, INK, Color.WHITE, INK.darkened(0.45), 2.0)
	var px := maxf(floorf((rect.size.y - 8.0) / 5.0), 1.0)
	var glyph := Vector2(3, 5) * px
	draw_key(ci, key, (rect.get_center() - glyph * 0.5 - Vector2(0, 1)).round(), DEEP, px, false)


## A tiny stenciled label (Silkscreen, 8 px), with a 1 px shadow.
static func draw_label(ci: CanvasItem, text: String, pos: Vector2, color := INK_DIM, width := -1.0, align := 0) -> void:
	draw_text(ci, text, pos, 8, color, width, align, label_font())


static func text_width(text: String, size: int, f: Font = null) -> float:
	return (font(size) if f == null else f).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Text centered on its ink inside `rect` (both ways, on whole pixels). The fonts' glyphs sit right on the
## baseline (ink rows baseline-cap .. baseline-1) with capitals/digits `cap_height` tall, and leave ~1 px of spacing after the last glyph (measured).
static func draw_centered(ci: CanvasItem, text: String, rect: Rect2, size: int, color: Color, f: Font = null, shadow := true) -> void:
	if f == null:
		f = font(size)
	var ink_w := text_width(text, size, f) - 1.0
	var cap := cap_height(f, size)
	var pos := Vector2(roundf(rect.get_center().x - ink_w * 0.5), roundf(rect.get_center().y + cap * 0.5))
	if shadow:
		ci.draw_string(f, pos + text_shadow(size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.9))
	ci.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## The baseline that vertically centers a line of capitals/digits on `center_y` (for left/right-aligned text).
static func centered_baseline(center_y: float, size: int, f: Font = null) -> float:
	return roundf(center_y + cap_height(font(size) if f == null else f, size) * 0.5)


## How tall capitals/digits are in a HUD font at `size` (the Jersey designs: half the size; others measured).
static func cap_height(f: Font, size: int) -> float:
	if f == label_font():
		return roundf(size * 0.625)
	if f == tape_font():
		return roundf(size * 0.643)
	return design_size(size) * 0.5


## The health color for a fraction of max health.
static func health_color(fraction: float) -> Color:
	if fraction <= 0.3:
		return BLOOD
	return HAZARD if fraction <= 0.6 else LIFE
