class_name KillFeedHUD
extends Control
## The kill feed (0.18.9, owner): who killed whom, top left, a few lines that fade away. (Top left because the
## quest tracker and the extract list live on the right.)
## Your own kills are brass; a kill you were on the wrong end of is red; everything else is plain.
## Lines come from the player's own kills (offline and online) and, online, from every player death in the raid
## (the server tells the whole raid). Other players' names go through NameFilter before they're shown.

## Where the list sits and how it's drawn.
const WIDTH := 260.0
const ROW_H := 20.0
const TOP := 12.0
const SIDE := 12.0
const SIZE := 16
## How long a line stays, and how long it takes to fade out at the end of that.
const LIFE := 7.0
const FADE := 1.0
## Never more than this many at once (the oldest goes).
const MOST := 5
## What the AI is called in the feed, by its scene's name.
const AI_NAMES := {"scav": "Scav", "sniper": "Sniper", "raider": "Raider", "boss": "Bon", "player": "PMC"}

## [killer, victim, colour, seconds left]
var _lines: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = SIDE
	offset_right = SIDE + WIDTH
	offset_top = TOP
	offset_bottom = TOP + ROW_H * MOST


## Adds a line. `mine`: our kill. `ours`: it was us who died.
func add_kill(killer: String, victim: String, mine := false, ours := false) -> void:
	var color := HudStyle.BRASS if mine else (HudStyle.BLOOD if ours else HudStyle.INK)
	_lines.append([killer, victim, color, LIFE])
	while _lines.size() > MOST:
		_lines.pop_front()
	queue_redraw()


## What the feed says right now (the test reads this).
func lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for line: Array in _lines:
		out.append("%s killed %s" % [line[0], line[1]])
	return out


## The name to show for something the AI runs ("scav" -> "Scav"), or a player's name, cleaned.
static func display_name(who: String, player := false) -> String:
	if player:
		return NameFilter.clean(who, "Player")
	return AI_NAMES.get(who, who.capitalize())


func _process(delta: float) -> void:
	if _lines.is_empty():
		return
	for line: Array in _lines:
		line[3] -= delta
	_lines = _lines.filter(func(line: Array) -> bool: return line[3] > 0.0)
	queue_redraw()


func _draw() -> void:
	var y := 0.0
	for line: Array in _lines:
		var alpha: float = clampf(line[3] / FADE, 0.0, 1.0)
		var killer: String = line[0]
		var victim: String = line[1]
		var color: Color = line[2]
		var text := "%s  >  %s" % [killer, victim]
		var width := HudStyle.font(SIZE).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x + 16.0
		var rect := Rect2(Vector2(0, y), Vector2(width, ROW_H - 3.0))
		HudStyle.draw_plate(self, rect, Color(HudStyle.OUTLINE, HudStyle.OUTLINE.a * alpha),
			Color(HudStyle.FACE, HudStyle.FACE.a * 0.8 * alpha))
		HudStyle.draw_text(self, text, rect.position + Vector2(8, ROW_H - 8.0), SIZE, Color(color, alpha))
		y += ROW_H
