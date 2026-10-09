class_name DamageArrowHUD
extends Control
## The "you got hit from there" arrow (0.8.7, "Ammo Can"): a red pixel chevron with a hard shadow, 150 px out from
## the crosshair. Its parent (HUD/DamageIndicator) turns toward the shooter and fades it out.

const CHEVRON := ["....##....", "...####...", "..######..", ".###..###.", "###....###", "##......##"]
const PX := 3.0
const DISTANCE := 150.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var chevron := HudStyle.icon_size(CHEVRON, PX)
	HudStyle.draw_icon(self, CHEVRON, Vector2(-chevron.x * 0.5, -DISTANCE - chevron.y), PX, HudStyle.BLOOD, Color(0, 0, 0, 0.85))
