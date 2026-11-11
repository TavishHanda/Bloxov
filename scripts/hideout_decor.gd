class_name HideoutDecor
extends Node3D
## Your corner (lively hideout, owner 2026-11-09: "customizable hideout, stuff that shows personality"): the bottom
## bunk at the west end of the quarters is yours. A poster over it, beside it a flag on the wall over a shelf with a
## lamp on it and a plant under it, a rug in front, your blanket on the mattress: each picked from Decor's list
## at the corner (USE: "Decorate your corner", DecorPicker). Looks only: nothing collides, nothing's sent online,
## and a headless run (the server, the tests) builds none of it unless `force_reacts` is set.

const BUNK := Vector3(-3.4, 0.0, 29.6)      # your bunk (make_hideout.py LAY.bunk_list[1]; foot at the wall)
const WALL_X := -4.43                        # the quarters' west wall
const REACH := 2.4                           # metres from the corner you can decorate it from
const AIM := Vector3(-3.3, 0.9, 28.9)        # the middle of the corner (what you look at to decorate)

var walker: Node3D
var spots := {}                              # spot -> its Node3D (rebuilt by refresh)
var _materials := {}
var _on := false


func setup(level: Node3D, who: Node3D) -> void:
	walker = who
	if not Reacts.wanted(self) or level == null:
		return
	_on = true
	# The wall shelf the lamp stands on (always there: it's part of the corner).
	var fixed := _spot_node("Shelf", Vector3(WALL_X + 0.01, 0.0, 28.0), PI * 0.5)
	_box(fixed, Vector3(0.55, 0.03, 0.42), Vector3(0.0, 0.94, 0.21), STEEL)
	for s: float in [-0.16, 0.16]:
		_box(fixed, Vector3(0.03, 0.18, 0.2), Vector3(s, 0.84, 0.1), STEEL_DARK, 0.0, 0.0)
	refresh()


func is_on() -> bool:
	return _on


## Rebuilds every spot from what's picked (Decor.showing).
func refresh() -> void:
	if not _on:
		return
	for spot: String in Decor.SPOTS:
		if spots.has(spot):
			var old: Node3D = spots[spot]
			remove_child(old)
			old.queue_free()
		spots[spot] = _build(spot, Decor.showing(spot))


## True if you're by your corner and looking roughly at it.
func in_reach() -> bool:
	if not _on or walker == null:
		return false
	var to := (global_transform * AIM) - walker.global_position
	if absf(to.y) > 1.6:
		return false
	to.y = 0.0
	var d := to.length()
	if d > REACH:
		return false
	var ahead: Vector3 = walker.call(&"facing") if walker.has_method(&"facing") else Vector3.FORWARD
	return ahead.dot(to / maxf(d, 0.01)) > 0.4


# --- The pieces: each spot's node has its front (+z) facing into the room ------------------------------------------

func _build(spot: String, id: String) -> Node3D:
	match spot:
		"poster":
			var n := _spot_node("Poster", Vector3(WALL_X, 1.08, BUNK.z), PI * 0.5)
			_poster(n, id)
			return n
		"flag":
			var n := _spot_node("Flag", Vector3(WALL_X, 1.95, 28.3), PI * 0.5)
			_flag(n, id)
			return n
		"rug":
			var n := _spot_node("Rug", Vector3(-1.75, 0.0, BUNK.z - 0.1), PI * 0.5)
			_rug(n, id)
			return n
		"lamp":
			var n := _spot_node("Lamp", Vector3(WALL_X + 0.2, 0.955, 28.0), PI * 0.5)
			n.scale = Vector3.ONE * 1.6   # (made at real size: a bit bigger so it reads from across the room)
			_lamp(n, id)
			return n
		"plant":
			var n := _spot_node("Plant", Vector3(-4.1, 0.0, 28.78), PI * 0.5)
			_plant(n, id)
			return n
		"blanket":
			var n := _spot_node("Blanket", Vector3(BUNK.x - 0.3, 0.47, BUNK.z), PI * 0.5)
			_blanket(n, id)
			return n
	return _spot_node(spot, Vector3.ZERO, 0.0)


func _poster(n: Node3D, id: String) -> void:
	var w := 0.5
	var h := 0.66
	var sheet: Color = {"bloxov": OLIVE_DARK, "nova": NOVA_BLUE, "exion": BLACK, "cat": SKY, "map": PAPER,
		"wanted": PAPER}.get(id, PAPER)
	_box(n, Vector3(w, h, 0.006), Vector3(0.0, 0.0, 0.003), sheet)
	for s: float in [-1.0, 1.0]:   # (taped up at the corners)
		_box(n, Vector3(0.07, 0.025, 0.004), Vector3(s * (w * 0.5 - 0.02), h * 0.5 - 0.02, 0.008), TAPE, 0.0, 0.0, s * 0.6)
	match id:
		"bloxov":
			_text(n, "BLOXOV", Vector3(0.0, 0.17, 0.008), 0.0026, YELLOW)
			_text(n, "NO MAN'S LAND", Vector3(0.0, 0.09, 0.008), 0.0011, PAPER)
			for k in 3:   # (a column of blocks: the game's look)
				_box(n, Vector3(0.09, 0.09, 0.01), Vector3(-0.1 + k * 0.1, -0.1 - (k % 2) * 0.05, 0.01), [YELLOW, KHAKI, RUST][k])
		"nova":
			_star(n, Vector3(0.0, 0.08, 0.008), 0.16, WHITE)
			_text(n, "NOVA", Vector3(0.0, -0.13, 0.008), 0.0022, WHITE)
			_text(n, "NEEDS YOU", Vector3(0.0, -0.22, 0.008), 0.0011, WHITE)
		"exion":
			_x_mark(n, Vector3(0.0, 0.07, 0.008), 0.3, RED)
			_text(n, "X1", Vector3(0.0, -0.17, 0.008), 0.0026, RED)
		"cat":
			_box(n, Vector3(0.022, 0.2, 0.006), Vector3(0.0, 0.24, 0.008), BRANCH)   # (the cat hangs off a branch)
			_box(n, Vector3(0.4, 0.03, 0.006), Vector3(0.0, 0.25, 0.009), BRANCH)
			_box(n, Vector3(0.16, 0.14, 0.008), Vector3(0.0, 0.06, 0.01), ORANGE)
			for s: float in [-1.0, 1.0]:
				_box(n, Vector3(0.04, 0.05, 0.008), Vector3(s * 0.055, 0.15, 0.01), ORANGE)            # ears
				_box(n, Vector3(0.025, 0.025, 0.004), Vector3(s * 0.035, 0.07, 0.015), BLACK)          # eyes
				_box(n, Vector3(0.03, 0.1, 0.008), Vector3(s * 0.06, 0.17, 0.012), ORANGE)            # paws up
			_box(n, Vector3(0.02, 0.015, 0.004), Vector3(0.0, 0.035, 0.015), PINK)
			_text(n, "HANG IN THERE", Vector3(0.0, -0.22, 0.008), 0.0011, WHITE)
		"map":
			_box(n, Vector3(0.42, 0.56, 0.004), Vector3(0.0, 0.0, 0.007), KHAKI)
			for k in 5:
				_box(n, Vector3(0.08 + k * 0.012, 0.06, 0.004), Vector3(-0.13 + (k % 3) * 0.12, 0.18 - k * 0.09, 0.009), GRASS)
			for k in 6:   # (a river)
				_box(n, Vector3(0.02, 0.1, 0.004), Vector3(0.12 - k * 0.04, -0.22 + k * 0.08, 0.01), NOVA_BLUE, 0.0, 0.0, 0.5)
			_x_mark(n, Vector3(-0.08, -0.05, 0.011), 0.07, RED)
		"wanted":
			_text(n, "WANTED", Vector3(0.0, 0.24, 0.008), 0.0019, BLACK)
			_box(n, Vector3(0.24, 0.24, 0.004), Vector3(0.0, 0.03, 0.007), KHAKI)
			_box(n, Vector3(0.14, 0.15, 0.006), Vector3(0.0, 0.04, 0.01), BONE)      # Bon's skull mask
			for s: float in [-1.0, 1.0]:
				_box(n, Vector3(0.04, 0.035, 0.004), Vector3(s * 0.033, 0.06, 0.014), BLACK)
			_box(n, Vector3(0.025, 0.12, 0.004), Vector3(0.05, 0.04, 0.015), RED, 0.0, 0.0, 0.35)
			_text(n, "BON", Vector3(0.0, -0.14, 0.008), 0.0019, BLACK)
			_text(n, "$10,000", Vector3(0.0, -0.23, 0.008), 0.0012, RUST)


func _flag(n: Node3D, id: String) -> void:
	if id == "none":
		return
	var w := 0.95
	var h := 0.6
	_box(n, Vector3(0.025, 0.025, 0.025), Vector3(-w * 0.5, h * 0.5, 0.012), STEEL_DARK)   # (two nails)
	_box(n, Vector3(0.025, 0.025, 0.025), Vector3(w * 0.5, h * 0.5, 0.012), STEEL_DARK)
	var cloth := _spot_node("Cloth", Vector3(0.0, 0.0, 0.02), 0.0, n)
	cloth.rotation.x = -0.04   # (hangs a little off the wall at the bottom)
	match id:
		"bloxov":
			_box(cloth, Vector3(w, h, 0.01), Vector3.ZERO, OLIVE)
			_box(cloth, Vector3(w, 0.12, 0.012), Vector3.ZERO, YELLOW)
			_text(cloth, "BLOXOV", Vector3(0.0, 0.0, 0.008), 0.0018, OLIVE_DARK)
		"nova":
			_box(cloth, Vector3(w, h, 0.01), Vector3.ZERO, NOVA_BLUE)
			_box(cloth, Vector3(w, 0.1, 0.012), Vector3(0.0, -0.2, 0.0), WHITE)
			_star(cloth, Vector3(0.0, 0.05, 0.007), 0.13, WHITE)
		"exion":
			_box(cloth, Vector3(w, h, 0.01), Vector3.ZERO, BLACK)
			_x_mark(cloth, Vector3(0.0, 0.0, 0.007), 0.4, RED)
		"skull":
			_box(cloth, Vector3(w, h, 0.01), Vector3.ZERO, BLACK)
			_box(cloth, Vector3(0.22, 0.2, 0.012), Vector3(0.0, 0.05, 0.0), WHITE)
			_box(cloth, Vector3(0.14, 0.06, 0.012), Vector3(0.0, -0.08, 0.0), WHITE)
			for s: float in [-1.0, 1.0]:
				_box(cloth, Vector3(0.06, 0.06, 0.004), Vector3(s * 0.05, 0.06, 0.008), BLACK)
				_box(cloth, Vector3(0.36, 0.05, 0.012), Vector3(0.0, -0.17, 0.0), WHITE, 0.0, 0.0, s * 0.45)   # crossbones
		"checker":
			for i in 8:
				for j in 5:
					_box(cloth, Vector3(w / 8.0, h / 5.0, 0.01),
						Vector3(-w * 0.5 + (i + 0.5) * w / 8.0, -h * 0.5 + (j + 0.5) * h / 5.0, 0.0),
						WHITE if (i + j) % 2 == 0 else BLACK)


func _rug(n: Node3D, id: String) -> void:
	if id == "none":
		return
	var w := 1.7    # (along the bunk: the node's x)
	var d := 1.0    # (out into the room)
	match id:
		"olive":
			_box(n, Vector3(w, 0.012, d), Vector3(0.0, 0.006, 0.0), OLIVE)
			_box(n, Vector3(w, 0.013, 0.06), Vector3(0.0, 0.006, d * 0.38), OLIVE_DARK)
			_box(n, Vector3(w, 0.013, 0.06), Vector3(0.0, 0.006, -d * 0.38), OLIVE_DARK)
		"red":
			_box(n, Vector3(w, 0.012, d), Vector3(0.0, 0.006, 0.0), RUST)
			_box(n, Vector3(w - 0.2, 0.013, d - 0.2), Vector3(0.0, 0.006, 0.0), MAROON)
			_box(n, Vector3(w - 0.5, 0.014, d - 0.5), Vector3(0.0, 0.006, 0.0), RUST)
		"persian":
			_box(n, Vector3(w, 0.012, d), Vector3(0.0, 0.006, 0.0), NAVY)
			_box(n, Vector3(w - 0.14, 0.013, d - 0.14), Vector3(0.0, 0.006, 0.0), MAROON)
			_box(n, Vector3(0.36, 0.014, 0.36), Vector3(0.0, 0.006, 0.0), GOLDISH, 0.785)
			for s: float in [-1.0, 1.0]:
				_box(n, Vector3(0.18, 0.014, 0.18), Vector3(s * 0.5, 0.006, 0.0), NAVY, 0.785)
				for k in 6:   # tassels
					_box(n, Vector3(0.015, 0.01, 0.06), Vector3(s * (w * 0.5 + 0.03), 0.005, -0.4 + k * 0.16), PAPER, PI * 0.5)
		"bear":
			_box(n, Vector3(1.1, 0.03, 0.75), Vector3(0.0, 0.015, 0.0), FUR)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_box(n, Vector3(0.18, 0.025, 0.28), Vector3(sx * 0.42, 0.012, sz * 0.42), FUR, sz * sx * 0.5)   # legs
			_box(n, Vector3(0.26, 0.16, 0.24), Vector3(0.66, 0.08, 0.0), FUR)          # the head
			_box(n, Vector3(0.12, 0.08, 0.12), Vector3(0.82, 0.05, 0.0), FUR_DARK)     # snout
			for s: float in [-1.0, 1.0]:
				_box(n, Vector3(0.06, 0.06, 0.04), Vector3(0.62, 0.18, s * 0.09), FUR)   # ears
				_box(n, Vector3(0.02, 0.025, 0.025), Vector3(0.76, 0.12, s * 0.06), BLACK)


func _lamp(n: Node3D, id: String) -> void:
	match id:
		"desk":
			_box(n, Vector3(0.14, 0.025, 0.1), Vector3(0.0, 0.0125, 0.0), STEEL_DARK)
			_box(n, Vector3(0.02, 0.24, 0.02), Vector3(0.0, 0.13, 0.0), STEEL_DARK, 0.0, 0.0, 0.25)
			var head := _spot_node("Head", Vector3(-0.06, 0.26, 0.0), 0.0, n)
			head.rotation.z = 0.9
			_box(head, Vector3(0.1, 0.06, 0.1), Vector3.ZERO, OLIVE)
			_glow(head, Vector3(0.07, 0.01, 0.07), Vector3(0.0, -0.032, 0.0), LIGHT)
		"lantern":
			_box(n, Vector3(0.12, 0.02, 0.12), Vector3(0.0, 0.01, 0.0), RUST)
			_glow(n, Vector3(0.08, 0.13, 0.08), Vector3(0.0, 0.085, 0.0), LIGHT)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_box(n, Vector3(0.015, 0.15, 0.015), Vector3(sx * 0.05, 0.085, sz * 0.05), RUST)
			_box(n, Vector3(0.12, 0.03, 0.12), Vector3(0.0, 0.17, 0.0), RUST)
			_box(n, Vector3(0.06, 0.012, 0.012), Vector3(0.0, 0.2, 0.0), STEEL_DARK)
		"lava":
			_box(n, Vector3(0.1, 0.05, 0.1), Vector3(0.0, 0.025, 0.0), STEEL)
			_glow(n, Vector3(0.07, 0.2, 0.07), Vector3(0.0, 0.15, 0.0), Color(0.95, 0.35, 0.55))
			_glow(n, Vector3(0.05, 0.05, 0.05), Vector3(0.0, 0.11, 0.0), Color(1.0, 0.75, 0.3))
			_glow(n, Vector3(0.04, 0.04, 0.04), Vector3(0.0, 0.2, 0.0), Color(1.0, 0.75, 0.3))
			_box(n, Vector3(0.08, 0.04, 0.08), Vector3(0.0, 0.27, 0.0), STEEL)
		"neon":   # (an X1 sign on the wall over the shelf)
			var sign := _spot_node("Sign", Vector3(0.0, 0.3, -0.12), 0.0, n)
			_box(sign, Vector3(0.38, 0.24, 0.02), Vector3.ZERO, BLACK)
			for s: float in [-1.0, 1.0]:
				_glow(sign, Vector3(0.02, 0.2, 0.012), Vector3(-0.07, 0.0, 0.015), NEON, s * 0.6)
			_glow(sign, Vector3(0.02, 0.18, 0.012), Vector3(0.09, 0.0, 0.015), NEON)
			_glow(sign, Vector3(0.04, 0.02, 0.012), Vector3(0.075, 0.08, 0.015), NEON, -0.6)


func _plant(n: Node3D, id: String) -> void:
	if id == "none":
		return
	var tall := id == "sunflower"
	# (0.34.9, owner: "glitching textures going through each other"): the rim's top and the soil's top used to be the
	# same plane at y=0.22, so they fought for every pixel. The soil now sits a clear 1 cm proud of the rim.
	_box(n, Vector3(0.22, 0.2, 0.22), Vector3(0.0, 0.1, 0.0), TERRACOTTA)
	_box(n, Vector3(0.25, 0.04, 0.25), Vector3(0.0, 0.21, 0.0), TERRACOTTA)
	_box(n, Vector3(0.19, 0.04, 0.19), Vector3(0.0, 0.22, 0.0), SOIL)
	match id:
		"cactus":
			_box(n, Vector3(0.08, 0.3, 0.08), Vector3(0.0, 0.36, 0.0), CACTUS)
			_box(n, Vector3(0.12, 0.05, 0.05), Vector3(0.07, 0.36, 0.0), CACTUS)
			_box(n, Vector3(0.05, 0.12, 0.05), Vector3(0.11, 0.42, 0.0), CACTUS)
			_box(n, Vector3(0.03, 0.03, 0.03), Vector3(0.0, 0.52, 0.0), PINK)
		"fern":
			for k in 7:
				var a := k * TAU / 7.0
				_box(n, Vector3(0.05, 0.02, 0.32), Vector3(cos(a) * 0.12, 0.33, sin(a) * 0.12), GRASS, -a + PI * 0.5, 0.5)
		"sunflower":
			_box(n, Vector3(0.025, 0.62, 0.025), Vector3(0.0, 0.53, 0.0), CACTUS)
			_box(n, Vector3(0.14, 0.03, 0.06), Vector3(0.06, 0.45, 0.0), GRASS, 0.0, 0.0, 0.4)
			var head := _spot_node("Bloom", Vector3(0.0, 0.84, 0.03), 0.0, n)
			head.rotation.x = -0.35
			_box(head, Vector3(0.26, 0.26, 0.02), Vector3.ZERO, YELLOW, 0.0, 0.0, 0.785)
			_box(head, Vector3(0.26, 0.26, 0.022), Vector3.ZERO, YELLOW)
			_box(head, Vector3(0.12, 0.12, 0.03), Vector3.ZERO, SOIL)
		"bonsai":
			_box(n, Vector3(0.04, 0.16, 0.04), Vector3(0.0, 0.3, 0.0), BRANCH, 0.0, 0.0, 0.3)
			_box(n, Vector3(0.14, 0.03, 0.03), Vector3(0.06, 0.38, 0.0), BRANCH, 0.0, 0.0, -0.2)
			for p: Vector3 in [Vector3(-0.06, 0.42, 0.0), Vector3(0.12, 0.44, 0.02), Vector3(0.02, 0.48, -0.03)]:
				_box(n, Vector3(0.14, 0.07, 0.12), p, LEAF)
	if tall:
		pass


func _blanket(n: Node3D, id: String) -> void:
	var colour: Color = {"olive": OLIVE, "red": RUST, "blue": NAVY, "camo": OLIVE, "leopard": GOLDISH,
		"gold": GOLD}.get(id, OLIVE)
	# Laid over the foot end of the bottom mattress (2 m along the node's x... the bunk runs along the room's x).
	var cover := _spot_node("Cover", Vector3.ZERO, -PI * 0.5, n)
	_box(cover, Vector3(1.3, 0.03, 0.96), Vector3(-0.15, 0.06, 0.0), colour)
	_box(cover, Vector3(0.08, 0.05, 0.98), Vector3(0.46, 0.065, 0.0), colour)          # (folded back at the top)
	for s: float in [-1.0, 1.0]:
		_box(cover, Vector3(1.3, 0.12, 0.02), Vector3(-0.15, 0.0, s * 0.48), colour)   # (hanging over the sides)
	match id:
		"camo":
			for p: Vector3 in [Vector3(-0.5, 0.077, 0.2), Vector3(-0.1, 0.077, -0.25), Vector3(0.2, 0.077, 0.15),
					Vector3(-0.65, 0.077, -0.2)]:
				_box(cover, Vector3(0.24, 0.005, 0.16), p, OLIVE_DARK, 0.4)
			for p: Vector3 in [Vector3(-0.3, 0.078, 0.0), Vector3(0.05, 0.078, 0.3)]:
				_box(cover, Vector3(0.18, 0.005, 0.12), p, KHAKI, -0.3)
		"leopard":
			for k in 10:
				_box(cover, Vector3(0.06, 0.005, 0.05), Vector3(-0.7 + (k % 5) * 0.28, 0.077, -0.25 + (k / 5) * 0.4 + (k % 2) * 0.1), BLACK, k * 0.7)
		"red", "blue", "olive":
			_box(cover, Vector3(0.05, 0.004, 0.96), Vector3(-0.55, 0.077, 0.0), PAPER)
			_box(cover, Vector3(0.05, 0.004, 0.96), Vector3(-0.45, 0.077, 0.0), PAPER)


# --- Helpers -------------------------------------------------------------------------------------------------------

const STEEL := Color(0.42, 0.44, 0.45)
const STEEL_DARK := Color(0.26, 0.27, 0.28)
const OLIVE := Color(0.36, 0.4, 0.22)
const OLIVE_DARK := Color(0.22, 0.25, 0.14)
const KHAKI := Color(0.7, 0.64, 0.45)
const PAPER := Color(0.9, 0.86, 0.74)
const TAPE := Color(0.85, 0.82, 0.68)
const YELLOW := Color(0.95, 0.78, 0.2)
const RUST := Color(0.66, 0.27, 0.14)
const MAROON := Color(0.42, 0.12, 0.13)
const NAVY := Color(0.16, 0.22, 0.4)
const NOVA_BLUE := Color(0.25, 0.48, 0.78)
const SKY := Color(0.45, 0.7, 0.88)
const BLACK := Color(0.08, 0.08, 0.08)
const WHITE := Color(0.95, 0.95, 0.92)
const RED := Color(0.78, 0.14, 0.12)
const ORANGE := Color(0.86, 0.47, 0.18)
const PINK := Color(0.93, 0.56, 0.6)
const BRANCH := Color(0.4, 0.27, 0.16)
const GRASS := Color(0.3, 0.56, 0.24)
const LEAF := Color(0.24, 0.47, 0.22)
const CACTUS := Color(0.33, 0.55, 0.3)
const TERRACOTTA := Color(0.7, 0.36, 0.22)
const SOIL := Color(0.25, 0.17, 0.11)
const BONE := Color(0.9, 0.87, 0.78)
const GOLD := Color(0.93, 0.74, 0.27)
const GOLDISH := Color(0.82, 0.6, 0.25)
const FUR := Color(0.36, 0.25, 0.17)
const FUR_DARK := Color(0.22, 0.15, 0.1)
const LIGHT := Color(1.0, 0.9, 0.6)
const NEON := Color(1.0, 0.25, 0.3)


func _spot_node(name_: String, at: Vector3, yaw: float, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.name = name_
	n.position = at
	n.rotation.y = yaw
	(parent if parent != null else self).add_child(n)
	return n


func _material(colour: Color, glow := false) -> StandardMaterial3D:
	var key := [colour, glow]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = 0.9
		if glow:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if colour == GOLD:
			m.metallic = 0.6
			m.roughness = 0.35
		_materials[key] = m
	return _materials[key]


func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color, yaw := 0.0, pitch := 0.0, roll := 0.0,
		glow := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.material_override = _material(colour, glow)
	box.position = at
	box.rotation = Vector3(pitch, yaw, roll)
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(box)
	return box


func _glow(parent: Node3D, size: Vector3, at: Vector3, colour: Color, roll := 0.0) -> MeshInstance3D:
	return _box(parent, size, at, colour, 0.0, 0.0, roll, true)


func _text(parent: Node3D, text: String, at: Vector3, pixel: float, colour: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = HudStyle.font(40)
	label.font_size = 40
	label.pixel_size = pixel
	label.modulate = colour
	label.outline_size = 0
	label.position = at
	label.double_sided = false
	parent.add_child(label)


## A five-pointed star out of five rotated bars.
func _star(parent: Node3D, at: Vector3, size: float, colour: Color) -> void:
	for k in 5:
		var a := k * TAU / 5.0
		_box(parent, Vector3(size * 0.22, size * 0.62, 0.006), at + Vector3(sin(a), cos(a), 0.0) * size * 0.22, colour, 0.0, 0.0, -a)
	_box(parent, Vector3(size * 0.34, size * 0.34, 0.006), at, colour, 0.0, 0.0, 0.0)


func _x_mark(parent: Node3D, at: Vector3, size: float, colour: Color) -> void:
	for s: float in [-1.0, 1.0]:
		_box(parent, Vector3(size * 0.2, size, 0.006), at, colour, 0.0, 0.0, s * 0.6)
