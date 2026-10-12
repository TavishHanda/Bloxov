class_name GunStatBars
extends HBoxContainer
## A gun's stats as bars in the inventory's details area (0.15.12, owner OK'd): damage, fire rate, range, control,
## handling and quiet, so guns can be compared without firing them. Attachments show as a green gain or a red loss
## on top of the bare gun's bar. Empty (but keeping its height) for anything that isn't a gun.

const STATS := ["DAMAGE", "FIRE RATE", "RANGE", "CONTROL", "HANDLING", "QUIET"]
const BAR_SIZE := Vector2(64, 8)

var _bars: Array[Control] = []
## Per bar: [bare gun's score, score with attachments], each 0..1.
var _values: Array = []


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 18)
	custom_minimum_size = Vector2(0, 12)
	for stat: String in STATS:
		var entry := HBoxContainer.new()
		entry.add_theme_constant_override("separation", 6)
		add_child(entry)
		var label := Label.new()
		label.text = stat
		label.modulate = Color(1, 1, 1, 0.7)
		label.add_theme_font_size_override("font_size", 11)
		entry.add_child(label)
		var bar := Control.new()
		bar.custom_minimum_size = BAR_SIZE
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var index := _bars.size()
		bar.draw.connect(func() -> void: _draw_bar(bar, index))
		entry.add_child(bar)
		_bars.append(bar)
		_values.append([0.0, 0.0])
	clear()


## Shows `stack`'s bars (a gun), or clears them for anything else.
func show_gun(stack: ItemStack) -> void:
	if stack == null or ItemDB.kind(stack.id) != "weapon":
		clear()
		return
	var bare := scores(ItemDB.item(stack.id))
	var now := scores(ItemDB.weapon_stats(stack))
	for i in _bars.size():
		_values[i] = [bare[i], now[i]]
		_bars[i].queue_redraw()
	modulate.a = 1.0


func clear() -> void:
	modulate.a = 0.0


## 0..1 per STATS entry for a gun's stats (ItemDB.weapon_stats). Scaled so the best gun at each is near full.
static func scores(stats: Dictionary) -> Array:
	var pellets := int(stats.get("pellets", 1))
	var per_shot := float(stats["damage"]) * pellets
	# Range: where damage starts to fall off (none: long), shortened by spread (a tighter choke reaches farther).
	var falloff: Array = stats.get("falloff", [])
	var reach := float(falloff[0]) if not falloff.is_empty() else 150.0
	reach = minf(reach, 15.0 / maxf(float(stats["spread"]), 0.01))
	if pellets > 1:
		reach /= maxf(float(stats.get("pellet_spread", 3.0)) / 3.0, 0.1)
	return [
		clampf(per_shot / 100.0, 0.03, 1.0),
		clampf(float(stats["rpm"]) / 900.0, 0.03, 1.0),
		clampf(reach / 150.0, 0.03, 1.0),
		clampf(1.0 - float(stats["recoil"]) / 5.5, 0.03, 1.0),
		clampf(1.0 - (float(stats["ads_time"]) - 0.1) / 0.45, 0.03, 1.0),
		clampf(1.0 - float(stats["noise"]) / 70.0, 0.03, 1.0),
	]


func _draw_bar(bar: Control, index: int) -> void:
	var bare: float = _values[index][0]
	var now: float = _values[index][1]
	var w := bar.size.x
	var h := bar.size.y
	bar.draw_rect(Rect2(0, 0, w, h), HudStyle.DEEP)
	bar.draw_rect(Rect2(0, 0, w * minf(bare, now), h), HudStyle.INK)
	if now > bare + 0.005:
		bar.draw_rect(Rect2(w * bare, 0, w * (now - bare), h), HudStyle.LIFE)
	elif now < bare - 0.005:
		bar.draw_rect(Rect2(w * now, 0, w * (bare - now), h), HudStyle.BLOOD)
	bar.draw_rect(Rect2(0, 0, w, h), Color.BLACK, false, 1.0)
