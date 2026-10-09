class_name HotbarHUD
extends Control
## Bottom-center hotbar (owner's layout, 0.8.1; look 0.8.6 "Ammo Can"): 1 = primary, 2 = secondary, 3 = meds (all
## your heals; uses the best fit), 4 = one bound item (for later: grenades...), V = the knife (owner, 0.9.0: 1, 2, 3, 4, V).
## Each slot is a gunmetal lid with its key in the corner (hand-drawn pixel digits), a pixel icon, a count and a rarity stripe.
## The gun in your hands pops up: lighter lid, hazard-yellow rim and caution stripes, yellow key. Switching guns
## slaps its name on a strip of tape above it for a moment. Empty slots are sunk-in wells with a faint ghost of
## what goes there; no meds left = the cross is crossed out in red.

const SLOT_SIZE := Vector2(54, 48)
const GAP := 8.0
const RISE := 7.0
## Room above the slots for the switch tape.
const TAPE_ROOM := 34.0
const SLOTS := 2 + Inventory.HOTBAR_SIZE
const SWITCH_TIME := 1.3

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
	offset_top = -18 - SLOT_SIZE.y - RISE - TAPE_ROOM
	offset_bottom = -18


func _process(delta: float) -> void:
	var held := held_slot()
	if held != _held_slot:
		if held >= 0 and _held_slot != -1:
			_switch_text = ItemDB.display_name(player.gun.weapon.id).to_upper()
			_switch_left = SWITCH_TIME
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


func slot_rect(i: int) -> Rect2:
	var top := TAPE_ROOM + RISE * (1.0 - _rise[i])
	return Rect2(Vector2(i * (SLOT_SIZE.x + GAP), top), SLOT_SIZE)


func _draw() -> void:
	var held := held_slot()
	for i in SLOTS:
		var info := slot_info(i)
		var rect := slot_rect(i)
		var active := i == held
		var state: String = info["state"]
		var key := "V" if i - 2 == Inventory.KNIFE_KEY else str(i + 1)
		var count: String = info["count"]
		# Icon area above the count (the whole slot when there's no count); count area along the bottom.
		var icon_box := Rect2(rect.position + Vector2(0, 4), Vector2(SLOT_SIZE.x, 26 if count != "" else SLOT_SIZE.y - 8))
		var count_box := Rect2(rect.position + Vector2(0, 28), Vector2(SLOT_SIZE.x, 14))
		if state == "empty":
			HudStyle.draw_well(self, rect, 0.8)
			var ghost: Array = _ghost_icon(i)
			if not ghost.is_empty():
				var px := 2.0 if String(ghost[0]).length() > 9 else 3.0
				var size := HudStyle.icon_size(ghost, px)
				HudStyle.draw_icon(self, ghost, (rect.get_center() - size * 0.5).round(), px, Color(HudStyle.INK, 0.14), Color(0, 0, 0, 0))
			HudStyle.draw_key(self, key, rect.position + Vector2(5, 5), Color(HudStyle.INK, 0.5), 1.0, false)
			continue
		var face := HudStyle.FACE.lerp(HudStyle.FACE_HI, 0.45 * _rise[i])
		HudStyle.draw_block(self, rect, face, face.lightened(0.25), HudStyle.FACE_DK, 3.0,
			HudStyle.HAZARD if active else HudStyle.OUTLINE)
		if _rise[i] > 0.0:
			# Caution stripes along the popped-up lid's top edge.
			HudStyle.draw_hazard(self, Rect2(rect.position + Vector2(3, 3), Vector2(SLOT_SIZE.x - 6, 3)), _rise[i], 6.0)
		var alpha := 0.35 if state == "out" else 1.0
		var icon: Array = info["icon"]
		if not icon.is_empty():
			var px := 2.0 if String(icon[0]).length() > 9 else 3.0
			var size := HudStyle.icon_size(icon, px)
			var color := HudStyle.BLOOD if icon == HudStyle.MED else HudStyle.INK
			HudStyle.draw_icon(self, icon, (icon_box.get_center() - size * 0.5).round(), px, Color(color, alpha))
		elif info["text"] != "":
			HudStyle.draw_centered(self, info["text"], icon_box, 8, Color(HudStyle.INK, alpha), HudStyle.label_font())
		if state == "out":
			# Crossed out: a stepped red pixel line over the icon.
			var c := icon_box.get_center()
			for k in range(-6, 7):
				draw_rect(Rect2(c + Vector2(k * 2 - 1, -k * 2 - 1), Vector2(3, 3)), Color(0, 0, 0, 0.6))
			for k in range(-6, 7):
				draw_rect(Rect2(c + Vector2(k * 2 - 1, -k * 2 - 2), Vector2(2, 2)), HudStyle.BLOOD)
		if count != "":
			HudStyle.draw_centered(self, count, count_box, 20, HudStyle.BLOOD if state == "out" else HudStyle.INK)
		var stripe: Color = info["stripe"]
		if stripe.a > 0.0:
			draw_rect(Rect2(rect.position + Vector2(6, SLOT_SIZE.y - 5), Vector2(SLOT_SIZE.x - 12, 2)), Color(stripe, alpha))
		HudStyle.draw_key(self, key, rect.position + Vector2(5, 8 if _rise[i] > 0.0 else 5), HudStyle.HAZARD if active else HudStyle.INK_DIM)
	# Switching guns: its name on a strip of tape, slapped on above the slot (drops in, then fades).
	if _switch_left > 0.0 and held >= 0:
		var t := SWITCH_TIME - _switch_left
		var alpha := clampf(_switch_left / 0.3, 0.0, 1.0)
		var drop := (1.0 - clampf(t / 0.1, 0.0, 1.0)) * -6.0
		var width := HudStyle.tape_width(_switch_text, 14)
		var over := slot_rect(held)
		var x := clampf(over.get_center().x - width * 0.5, 0.0, size.x - width)
		HudStyle.draw_tape(self, Rect2(Vector2(x, over.position.y - 26 + drop), Vector2(width, 20)), _switch_text, -2.0, alpha, 14)


## A faint picture of what goes in an empty slot (1 rifle, 2 pistol, 4-5 a grenade).
func _ghost_icon(i: int) -> Array:
	if i == 0:
		return HudStyle.RIFLE
	if i == 1:
		return HudStyle.PISTOL
	return HudStyle.GRENADE if i - 2 in Inventory.BINDABLE_KEYS else []
