class_name TimerHUD
extends Control
## Top-center raid timer (0.8.7, "Ammo Can"): the time left on a gunmetal plate with a hazard strip along the bottom.
## The last minute turns it red (rim, digits, stripes) and the plate punches on every tick.
## Stays on screen while the inventory is open (the raid doesn't pause).

const PLATE_SIZE := Vector2(104, 38)

var raid: Raid
var _punch := 0.0
var _last_second := -1


func _init(owner_raid: Raid) -> void:
	raid = owner_raid
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -PLATE_SIZE.x * 0.5
	offset_right = PLATE_SIZE.x * 0.5
	offset_top = 12
	offset_bottom = 12 + PLATE_SIZE.y


func seconds_left() -> int:
	return maxi(ceili(raid.time_left), 0)


func text() -> String:
	var seconds := seconds_left()
	return "%02d:%02d" % [seconds / 60, seconds % 60]


func _process(delta: float) -> void:
	var seconds := seconds_left()
	if seconds <= 60 and seconds != _last_second and _last_second != -1:
		_punch = 0.15
	_last_second = seconds
	_punch = maxf(_punch - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var last_minute := seconds_left() <= 60
	var scale_by := 1.0 + 0.1 * _punch / 0.15
	draw_set_transform(PLATE_SIZE * 0.5 * (1.0 - scale_by), 0.0, Vector2.ONE * scale_by)
	var accent := HudStyle.BLOOD if last_minute else HudStyle.HAZARD
	HudStyle.draw_plate(self, Rect2(Vector2.ZERO, PLATE_SIZE), HudStyle.BLOOD if last_minute else HudStyle.OUTLINE)
	HudStyle.draw_hazard(self, Rect2(Vector2(3, PLATE_SIZE.y - 6), Vector2(PLATE_SIZE.x - 6, 3)), 1.0, 6.0, 0.0, accent)
	HudStyle.draw_centered(self, text(), Rect2(Vector2.ZERO, Vector2(PLATE_SIZE.x, PLATE_SIZE.y - 4)), 30,
		HudStyle.BLOOD if last_minute else HudStyle.INK)
	draw_set_transform(Vector2.ZERO)
