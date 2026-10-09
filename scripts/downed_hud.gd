class_name DownedHUD
extends Control
## Downed (0.9.2, "Ammo Can" look): under the crosshair, a gunmetal plate with a pulsing red cross, DOWNED, and the
## downed bar's number on a red tag; under it the bar itself, draining from 100 to 0 over 30 s (hits take from it
## too; at 0 you die, owner). While a teammate holds F on you, a second plate says REVIVING with a green bar.

const SIZE := Vector2(260, 44)
const BELOW_CENTER := 56.0
const TAG := Rect2(196, 7, 56, 30)
const BAR_H := 8.0
const REVIVE_H := 32.0

var player: Player
var _pulse := 0.0
var _shown := -1.0
var _shake := 0.0


func _init(owner_player: Player) -> void:
	player = owner_player
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_pulse += delta * TAU * 1.2
	var hp := player.health.down_hp
	if _shown >= 0.0 and hp < _shown - 1.0:
		_shake = 0.14  # a hit, not just the drain
	_shown = hp
	_shake = maxf(_shake - delta, 0.0)
	queue_redraw()


## 0..1 of the revive bar, or -1 when nobody is reviving us.
func revive_fraction() -> float:
	if not player.being_revived:
		return -1.0
	return clampf(1.0 - player.revive_time_left / Network.REVIVE_TIME, 0.0, 1.0)


func _draw() -> void:
	if not player.downed:
		return
	var health := player.health
	var fraction := clampf(health.down_hp / Health.DOWN_HP, 0.0, 1.0)
	var glow := 0.5 + 0.5 * cos(_pulse)
	var jolt := Vector2(randi_range(-2, 2), randi_range(-1, 1)) if _shake > 0.0 else Vector2.ZERO
	var rect := Rect2((Vector2(size.x * 0.5 - SIZE.x * 0.5, size.y * 0.5 + BELOW_CENTER) + jolt).round(), SIZE)
	HudStyle.draw_plate(self, rect)
	var cross := HudStyle.icon_size(HudStyle.MED, 4)
	var lead := Rect2(rect.position + Vector2(8, 6), Vector2(32, 32))
	HudStyle.draw_icon(self, HudStyle.MED, (lead.get_center() - cross * 0.5).round(), 4, HudStyle.BLOOD.lightened(0.3 * glow))
	HudStyle.draw_text(self, "DOWNED", Vector2(lead.end.x + 10, HudStyle.centered_baseline(rect.get_center().y, 30)), 30, HudStyle.INK)
	var tag := Rect2(rect.position + TAG.position, TAG.size)
	var face := HudStyle.BLOOD.lerp(HudStyle.BLOOD.lightened(0.25), glow)
	HudStyle.draw_block(self, tag, face, face.lightened(0.3), face.darkened(0.4), 2.0)
	HudStyle.draw_centered(self, str(ceili(health.down_hp)), tag, 30, HudStyle.INK, null, false)
	# The downed bar.
	var bar := Rect2(rect.position + Vector2(0, SIZE.y + 6), Vector2(SIZE.x, BAR_H))
	_bar(bar, fraction, HudStyle.BLOOD)
	# A teammate reviving us.
	var revive := revive_fraction()
	if revive < 0.0:
		return
	var plate := Rect2(Vector2(rect.position.x, bar.end.y + 12), Vector2(SIZE.x, REVIVE_H))
	HudStyle.draw_plate(self, plate)
	HudStyle.draw_centered(self, "REVIVING", plate, 20, HudStyle.LIFE)
	_bar(Rect2(plate.position + Vector2(0, REVIVE_H + 6), Vector2(SIZE.x, 6)), revive, HudStyle.LIFE)


func _bar(bar: Rect2, fraction: float, color: Color) -> void:
	draw_rect(bar.grow(2), HudStyle.OUTLINE)
	draw_rect(bar, HudStyle.DEEP)
	var fill := Rect2(bar.position, Vector2(roundf(bar.size.x * fraction), bar.size.y))
	draw_rect(fill, color)
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, 2)), color.lightened(0.35))
