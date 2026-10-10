class_name MapHUD
extends Control
## The map (0.10.2, owner): M opens it over the raid (you keep moving; M again closes it). It shows the map from
## above with the names of places, the extracts open for you this raid, your teammates and you (an arrow pointing
## where you look). It's the only place extracts show now: no tags or list on screen (owner).
## The map's look comes from the map scene's `minimap` metadata (written by its generator, e.g.
## tools/gen_old_bloxov.py; RaidMap copies it onto the raid scene). Without it (the test map) only the extracts,
## teammates and you are drawn.

const GRASS := Color("3d5232")
const YARD := Color("57543c")
const TREES := Color("2c4224")
const ROAD := Color("8a8a84")
const WATER := Color("4f7fa6")
const RAIL := Color("6b4a2f")
const BUILDING := Color("b9b3a3")
const BUILDING_EDGE := Color("1e2125")
const YOU := Color("f4c430")
## Map metres shown when the raid has no map data (the test map).
const FALLBACK_SIZE := 140.0

var player: Player
var raid: Raid
## The map's drawing data (see the generator): size/offset (metres), buildings, yards, woods, roads, water, rail,
## labels, relief (ground heights on a grid, 0.11.17 hills).
var data := {}
## The hills, shaded (lit from the north-west, hilltops lighter), drawn under everything else. Null without relief.
var _relief: ImageTexture


func _init(owner_player: Player, owner_raid: Raid) -> void:
	player = owner_player
	raid = owner_raid
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := raid.get_parent()
	if root != null:
		data = root.get_meta("minimap", {})
	_relief = _shade_relief(data.get("relief", PackedFloat32Array()), int(data.get("relief_cells", 0)))


## A small picture of the hills from `heights` (cells x cells, row by row from the north-west corner).
static func _shade_relief(heights: PackedFloat32Array, cells: int) -> ImageTexture:
	if cells < 2 or heights.size() != cells * cells:
		return null
	var image := Image.create(cells, cells, false, Image.FORMAT_RGBA8)
	var light := Vector3(-1.0, 1.4, -1.0).normalized()
	var at := func(i: int, j: int) -> float: return heights[clampi(j, 0, cells - 1) * cells + clampi(i, 0, cells - 1)]
	for j in cells:
		for i in cells:
			var normal := Vector3(at.call(i - 1, j) - at.call(i + 1, j), 2.0, at.call(i, j - 1) - at.call(i, j + 1)).normalized()
			var lit := clampf((normal.dot(light) - light.y) * 1.6, -0.12, 0.12) + clampf(at.call(i, j) * 0.008, -0.03, 0.06)
			var shade := GRASS.lightened(lit) if lit > 0.0 else GRASS.darkened(-lit)
			image.set_pixel(i, j, shade)
	return ImageTexture.create_from_image(image)


## M: open the map, or close it.
func toggle() -> void:
	visible = not visible


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## Map size and the world position of its top-left corner (metres).
func _size() -> float:
	return float(data.get("size", FALLBACK_SIZE))


func _offset() -> float:
	return float(data.get("offset", -FALLBACK_SIZE * 0.5))


## The open extracts, as the map shows them: [{name, at (world x, z)}].
func open_extracts() -> Array:
	var result := []
	for zone in raid.get_extracts():
		if zone.is_open:
			result.append({"name": zone.extract_name, "at": Vector2(zone.global_position.x, zone.global_position.z)})
	return result


## Where the map is drawn on screen (a square, as big as fits).
func map_rect() -> Rect2:
	# (clear of the raid timer at the top and the hotbar at the bottom)
	var side := floorf(minf(size.x - 80.0, size.y - 180.0))
	return Rect2(((size - Vector2(side, side)) * 0.5 + Vector2(0, 14)).round(), Vector2(side, side))


func _draw() -> void:
	var rect := map_rect()
	var scale := rect.size.x / _size()
	var to_screen := func(p: Vector2) -> Vector2: return rect.position + p * scale
	var world_to_screen := func(p: Vector2) -> Vector2: return rect.position + (p - Vector2(_offset(), _offset())) * scale
	# Frame: a plate with the title and the M key cap.
	var frame := rect.grow(10).grow_side(SIDE_TOP, 28)
	HudStyle.draw_plate(self, frame)
	var title: String = raid.get_parent().get_meta("map_name", "MAP").to_upper() if raid.get_parent() != null else "MAP"
	HudStyle.draw_label(self, title, frame.position + Vector2(12, HudStyle.centered_baseline(19, 8, HudStyle.label_font())), HudStyle.INK_DIM)
	HudStyle.draw_keycap(self, Rect2(frame.position + Vector2(frame.size.x - 12 - 18, 10), Vector2(18, 18)), "M")
	draw_rect(rect, GRASS)
	if _relief != null:
		draw_texture_rect(_relief, rect, false)
	var yards: PackedFloat32Array = data.get("yards", PackedFloat32Array())
	for i in range(0, yards.size() - 3, 4):
		draw_rect(Rect2(to_screen.call(Vector2(yards[i], yards[i + 1])), Vector2(yards[i + 2] - yards[i], yards[i + 3] - yards[i + 1]) * scale), YARD)
	var woods: PackedFloat32Array = data.get("woods", PackedFloat32Array())
	for i in range(0, woods.size() - 2, 3):
		draw_circle(to_screen.call(Vector2(woods[i], woods[i + 1])), (woods[i + 2] + 3.0) * scale, TREES)
	_draw_lines(data.get("water", []), data.get("water_widths", PackedFloat32Array()), WATER, to_screen, scale)
	var rail: PackedVector2Array = data.get("rail", PackedVector2Array())
	if rail.size() >= 2:
		draw_line(to_screen.call(rail[0]), to_screen.call(rail[1]), RAIL, maxf(2.0, 2.0 * scale))
	_draw_lines(data.get("roads", []), data.get("road_widths", PackedFloat32Array()), ROAD, to_screen, scale)
	var buildings: PackedFloat32Array = data.get("buildings", PackedFloat32Array())
	for i in range(0, buildings.size() - 3, 4):
		var b := Rect2(to_screen.call(Vector2(buildings[i], buildings[i + 1])), Vector2(buildings[i + 2] - buildings[i], buildings[i + 3] - buildings[i + 1]) * scale)
		draw_rect(b, BUILDING)
		draw_rect(b, BUILDING_EDGE, false, 1.0)
	for label: Array in data.get("labels", []):
		var at: Vector2 = to_screen.call(Vector2(label[1], label[2]))
		if int(label[3]) == 1:
			var w := HudStyle.text_width(label[0], 20)
			HudStyle.draw_text(self, label[0], (at - Vector2(w * 0.5, -6)).round(), 20, HudStyle.INK_DIM)
		else:
			var w := HudStyle.text_width(label[0], 8, HudStyle.label_font())
			HudStyle.draw_label(self, label[0], (at - Vector2(w * 0.5, -3)).round(), HudStyle.INK)
	# Extracts open for you: a green flag and the name.
	var flag := HudStyle.icon_size(HudStyle.FLAG, 2)
	for extract: Dictionary in open_extracts():
		var at: Vector2 = world_to_screen.call(extract["at"])
		HudStyle.draw_icon(self, HudStyle.FLAG, (at - Vector2(1, flag.y)).round(), 2, HudStyle.EXTRACT)
		var name_w := HudStyle.text_width(extract["name"], 20)
		var x := clampf(at.x - name_w * 0.5, rect.position.x + 2, rect.end.x - name_w - 2)
		HudStyle.draw_text(self, extract["name"], Vector2(roundf(x), roundf(at.y - flag.y - 4)), 20, HudStyle.EXTRACT)
	# Teammates (their name tags' spots): a green dot and the name.
	for node in RaidScope.nodes(self, Effects.WORLD_LABELS):
		var spot := node as Node3D
		if spot == null or not spot.is_inside_tree() or spot.get_meta("label_kind", "name") != "name":
			continue
		var at: Vector2 = world_to_screen.call(Vector2(spot.global_position.x, spot.global_position.z))
		draw_circle(at, 4.0, Color.BLACK)
		draw_circle(at, 3.0, WorldLabelsHUD.TEAMMATE)
		HudStyle.draw_label(self, String(spot.get_meta("label_text", "")), (at + Vector2(6, 3)).round(), WorldLabelsHUD.TEAMMATE)
	# You: an arrow pointing where you look.
	if is_instance_valid(player) and player.is_inside_tree():
		var at: Vector2 = world_to_screen.call(Vector2(player.global_position.x, player.global_position.z))
		var forward := -player.global_basis.z
		var dir := Vector2(forward.x, forward.z).normalized() if Vector2(forward.x, forward.z).length() > 0.01 else Vector2.UP
		var side := Vector2(-dir.y, dir.x)
		var arrow := PackedVector2Array([at + dir * 9.0, at - dir * 6.0 + side * 6.0, at - dir * 3.0, at - dir * 6.0 - side * 6.0])
		var outline := PackedVector2Array(arrow)
		outline.append(arrow[0])
		draw_colored_polygon(arrow, YOU)
		draw_polyline(outline, Color.BLACK, 1.5)


func _draw_lines(items: Array, widths: PackedFloat32Array, colour: Color, to_screen: Callable, scale: float) -> void:
	for i in items.size():
		var points: PackedVector2Array = items[i]
		var screen := PackedVector2Array()
		for p in points:
			screen.append(to_screen.call(p))
		var width := (widths[i] if i < widths.size() else 4.0) * scale
		draw_polyline(screen, colour, maxf(width, 2.0))
		for p in [screen[0], screen[screen.size() - 1]]:   # round the ends so joins don't show gaps
			draw_circle(p, maxf(width, 2.0) * 0.5, colour)
