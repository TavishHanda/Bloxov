class_name InvLook
extends RefCounted
## The inventory's look (0.19.6, "Glow", owner picked B): dark tiles with the item's rarity color rising from the
## bottom and a thin edge, a flat dark grid with faint lines and corner dots, names in the HUD's pixel font.
## Used by ItemTile, GridView, SlotGridView and EquipSlotView.

const TILE := Color("121417")
const GRID := Color("101215")
## How strong the rarity color gets at the bottom of a tile.
const GLOW := 0.42


## A tile's background: dark, with its rarity color rising from the bottom.
static func draw_tile(ci: CanvasItem, rect: Rect2, color: Color) -> void:
	ci.draw_rect(rect, TILE)
	var top := Color(color, 0.0)
	var low := Color(color, GLOW)
	ci.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, low, low]))


## A tile's edge (over its picture): a black hairline and a faint rarity line inside it.
static func draw_edge(ci: CanvasItem, rect: Rect2, color: Color) -> void:
	ci.draw_rect(rect, Color(0, 0, 0, 0.9), false, 1.0)
	ci.draw_rect(rect.grow(-1), Color(color, 0.35), false, 1.0)


## An empty grid of `cells`, `cell` pixels each: flat dark, faint lines, a dot where lines cross.
static func draw_cells(ci: CanvasItem, cells: Vector2i, cell: float) -> void:
	var area := Vector2(cells) * cell
	ci.draw_rect(Rect2(Vector2.ZERO, area).grow(2), HudStyle.OUTLINE)
	ci.draw_rect(Rect2(Vector2.ZERO, area), GRID)
	for x in cells.x + 1:
		ci.draw_line(Vector2(x * cell, 0), Vector2(x * cell, area.y), Color(1, 1, 1, 0.045))
	for y in cells.y + 1:
		ci.draw_line(Vector2(0, y * cell), Vector2(area.x, y * cell), Color(1, 1, 1, 0.045))
	for x in cells.x + 1:
		for y in cells.y + 1:
			ci.draw_rect(Rect2(Vector2(x, y) * cell - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 1, 0.12))


## A gear slot's background: like a grid, with dots in its corners only.
static func draw_slot(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect.grow(2), HudStyle.OUTLINE)
	ci.draw_rect(rect, GRID)
	for p in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)).intersection(rect), Color(1, 1, 1, 0.12))


## A gear slot's name (PRIMARY, Hound...) in the HUD's pixel font with a hard shadow.
static func style_slot_label(label: Label) -> void:
	label.add_theme_font_override("font", HudStyle.spaced_font(20))
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("line_spacing", -6)
