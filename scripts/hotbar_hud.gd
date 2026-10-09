class_name HotbarHUD
extends Control
## Bottom-center hotbar (owner's layout, 0.8.1; look 0.8.3): 1 = primary, 2 = secondary, 3 = meds (all your heals;
## uses the best fit), 4 and 5 = bound items (for later: grenades...), 6 = the knife (V).
## Each slot is a small plate with a stamped key tab, a pixel icon, a count, and a rarity stripe along the bottom.
## The gun in your hands rises and glows; switching shows its name for a moment. Empty slots are dashed ghosts;
## out-of-stock ones are crossed out.

const SLOT_SIZE := Vector2(64, 56)
const GAP := 6.0
const RISE := 6.0
const SLOTS := 2 + Inventory.HOTBAR_SIZE

var player: Player
## How far each slot has risen (0..1, the held gun rises).
var _rise: Array[float] = []
var _held_slot := -1
var _switch_text := ""
var _switch_left := 0.0


func _init(owner_player: Player) -> void:
	player = owner_player
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in SLOTS:
		_rise.append(0.0)


func _ready() -> void:
	var width := SLOTS * SLOT_SIZE.x + (SLOTS - 1) * GAP
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_top = -14 - SLOT_SIZE.y - RISE - 30
	offset_bottom = -14


func _process(delta: float) -> void:
	var held := held_slot()
	if held != _held_slot:
		if held >= 0 and _held_slot != -1:
			_switch_text = ItemDB.display_name(player.gun.weapon.id)
			_switch_left = 1.2
		_held_slot = held
	_switch_left -= delta
	for i in SLOTS:
		_rise[i] = move_toward(_rise[i], 1.0 if i == held else 0.0, delta / 0.09)
	queue_redraw()


## Which slot (0 = key 1) holds the gun in your hands, or -1.
func held_slot() -> int:
	var inventory := player.inventory
	if player.gun.weapon == null:
		return -1
	if player.gun.weapon == inventory.equipped("primary"):
		return 0
	return 1 if player.gun.weapon == inventory.equipped("secondary") else -1


## What a slot shows: {icon, text (item name for bound items), count, stripe (rarity color), state}.
## state: "filled", "empty" or "out" (out of stock).
func slot_info(i: int) -> Dictionary:
	var inventory := player.inventory
	var info := {"icon": [], "text": "", "count": "", "stripe": Color(0, 0, 0, 0), "state": "empty"}
	if i < 2:
		var weapon := inventory.equipped("primary" if i == 0 else "secondary")
		if weapon != null:
			info["icon"] = HudStyle.RIFLE if ItemDB.item(weapon.id)["slot"] == "primary" else HudStyle.PISTOL
			var ammo_id: String = ItemDB.item(weapon.id)["ammo"]
			var loaded := player.gun.in_mag if player.gun.weapon == weapon else weapon.loaded
			info["count"] = "%d/%d" % [loaded, inventory.count_of(ammo_id)]
			info["stripe"] = ItemDB.color(weapon.id)
			info["state"] = "filled"
	elif i - 2 == Inventory.MEDS_KEY:
		var heals := inventory.heal_count()
		info["icon"] = HudStyle.MED
		info["count"] = "x%d" % heals
		info["stripe"] = HudStyle.WARN
		info["state"] = "filled" if heals > 0 else "out"
	elif i - 2 == Inventory.KNIFE_KEY:
		info["icon"] = HudStyle.KNIFE
		info["state"] = "filled"
	else:
		var id := inventory.hotbar[i - 2]
		if id != "":
			var have := inventory.count_of(id)
			info["text"] = ItemDB.short_name(id)
			info["count"] = "x%d" % have
			info["stripe"] = ItemDB.color(id)
			info["state"] = "filled" if have > 0 else "out"
	return info


func _draw() -> void:
	var held := held_slot()
	for i in SLOTS:
		var info := slot_info(i)
		var top := 30.0 + RISE * (1.0 - _rise[i])
		var rect := Rect2(Vector2(i * (SLOT_SIZE.x + GAP), top), SLOT_SIZE)
		var active := i == held
		var state: String = info["state"]
		if state == "empty":
			_draw_dashed(rect, Color(HudStyle.PLATE_EDGE, 0.4))
			if i - 2 in Inventory.BINDABLE_KEYS:
				var ghost := HudStyle.icon_size(HudStyle.GRENADE, 3)
				HudStyle.draw_icon(self, HudStyle.GRENADE, rect.position + Vector2((SLOT_SIZE.x - ghost.x) * 0.5, 8), 3, Color(HudStyle.TEXT, 0.2))
		else:
			HudStyle.draw_plate(self, rect, HudStyle.ACTIVE if active else HudStyle.PLATE_EDGE)
			var icon: Array = info["icon"]
			var alpha := 0.35 if state == "out" else 1.0
			if not icon.is_empty():
				var px := 2.0 if String(icon[0]).length() > 9 else 3.0
				var size := HudStyle.icon_size(icon, px)
				var color := HudStyle.WARN if icon == HudStyle.MED else HudStyle.TEXT
				HudStyle.draw_icon(self, icon, rect.position + Vector2((SLOT_SIZE.x - size.x) * 0.5, 4 + (30 - size.y) * 0.5), px, Color(color, alpha))
			elif info["text"] != "":
				draw_string(get_theme_default_font(), rect.position + Vector2(6, 26), info["text"], HORIZONTAL_ALIGNMENT_LEFT, SLOT_SIZE.x - 12, 12, Color(HudStyle.TEXT, alpha))
			if state == "out":
				draw_line(rect.position + Vector2(8, 34), rect.position + Vector2(SLOT_SIZE.x - 8, 6), HudStyle.WARN, 2.0)
			if info["count"] != "":
				var count_color := HudStyle.WARN if state == "out" else HudStyle.TEXT
				HudStyle.draw_text(self, info["count"], rect.position + Vector2(4, 50), 20, count_color, SLOT_SIZE.x - 8, 2)
			var stripe: Color = info["stripe"]
			if stripe.a > 0.0:
				draw_rect(Rect2(rect.position + Vector2(HudStyle.NOTCH, SLOT_SIZE.y - 4), Vector2(SLOT_SIZE.x - HudStyle.NOTCH * 2, 3)), Color(stripe, alpha))
		# Key tab, stamped on top.
		var tab := Rect2(rect.position + Vector2((SLOT_SIZE.x - 20) * 0.5, -9), Vector2(20, 17))
		HudStyle.draw_plate(self, tab, HudStyle.ACTIVE if active else HudStyle.PLATE_EDGE, HudStyle.ACTIVE if active else HudStyle.PLATE_EDGE, 3.0)
		var key := "V" if i - 2 == Inventory.KNIFE_KEY else str(i + 1)
		HudStyle.draw_text(self, key, tab.position + Vector2(0, 15), 20, HudStyle.PLATE if active else HudStyle.TEXT, 20, 1)
	if _switch_left > 0.0:
		var alpha := clampf(_switch_left / 0.3, 0.0, 1.0)
		var font := get_theme_default_font()
		draw_string_outline(font, Vector2(0, 18), _switch_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, 3, Color(0, 0, 0, alpha))
		draw_string(font, Vector2(0, 18), _switch_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(HudStyle.TEXT, alpha))


func _draw_dashed(rect: Rect2, color: Color) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var length := a.distance_to(b)
		var t := 0.0
		while t < length:
			draw_line(a.lerp(b, t / length), a.lerp(b, minf(t + 4.0, length) / length), color, 2.0)
			t += 8.0
