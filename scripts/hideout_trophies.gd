class_name HideoutTrophies
extends Node3D
## The trophy shelf (lively hideout, owner 2026-11-09: "trophies that show progress"): a steel shelf by the record
## board that fills up as you play. Everything on it comes from what the profile already keeps (no new tracking):
##   top:    Bon's mask (his quest, Big Game), a token from each trader you've levelled up (a star a level past 2)
##   middle: a medal for 1, 10, 25, 50 and 100 extracts; cash piling up with the money you've made
##   bottom: a jar of spent casings filling with your raids, the workbench's gold wrench at its top level, a stack
##           of finished job folders
## Look at one and the prompt says what it's for. Looks only: nothing collides, nothing's sent online; rebuilt each
## time you leave the menu (HideoutWorld.fill_boards), so it's always your current profile (PvE or PvP).

const EXTRACT_MEDALS := [1, 10, 25, 50, 100]
const CASH_STEPS := [5000, 25000, 100000, 250000, 500000, 1000000]
const JAR_FULL := 100           # raids for a full jar
const FOLDERS_EVERY := 3        # one folder per this many jobs done
const LOOK_REACH := 3.2         # metres: you see what a trophy is from this close
const LOOK_CONE := 0.985        # (the dot of your view and the way to it)
const SPOT := Vector3(27.3, 0.0, 4.22)   # (hideout coordinates: the armory's end, against its wall)
const TROPHY_SCALE := 1.5
const TRADER_TOKENS := ["guns", "supplies", "valuables", "ming", "meds"]

## What's on the shelf now: [{"node": Node3D, "label": String}] (for the prompt and the tests).
var trophies: Array[Dictionary] = []
var cabinet: Node3D
var shelf: Node3D               # the trophies (cleared and refilled by refresh)
var _materials := {}
var _on := false


## Builds the shelf beside the record board (`level`'s Boards/stats) and fills it.
func setup(level: Node3D) -> void:
	if not Reacts.wanted(self):
		return
	if level == null:
		return
	_on = true
	# (0.34.1, owner: "in the middle of nowhere", wants it "in its own little area up where stash/wardrobe is"): at the
	# far end of the armory, past the workbench, its back to the south wall, facing across the room.
	position = SPOT
	rotation = Vector3.ZERO
	cabinet = Node3D.new()
	cabinet.name = "Cabinet"
	add_child(cabinet)
	_build_cabinet()
	shelf = Node3D.new()
	shelf.name = "Shelf"
	add_child(shelf)
	refresh()


## Fills the shelf from the profile (call after anything that could change it: back from a raid, levelling up...).
func refresh() -> void:
	if not _on:
		return
	trophies.clear()
	for child in shelf.get_children():
		shelf.remove_child(child)
		child.queue_free()
	_top_shelf()
	_middle_shelf()
	_bottom_shelf()


## The trophy you're looking at (its label), or "" (from your eye at `eye`, looking along `ahead`).
func looked_at(eye: Vector3, ahead: Vector3) -> String:
	var best := ""
	var best_dot := LOOK_CONE
	for t: Dictionary in trophies:
		var to: Vector3 = (t["node"] as Node3D).global_position - eye
		var d := to.length()
		if d > LOOK_REACH or d < 0.05:
			continue
		var dot := ahead.dot(to / d)
		if dot > best_dot:
			best_dot = dot
			best = t["label"]
	return best


# --- What goes on it -----------------------------------------------------------------------------------------------

const SHELF_Y := [1.42, 0.92, 0.42]   # top of each shelf board
const WIDTH := 1.9
const DEPTH := 0.46


func _top_shelf() -> void:
	var y: float = SHELF_Y[0]
	# Bon's mask on a stand, at the left end: once you've killed him (Big Game, done or the kill counted).
	if Profile.quests_done.has("big_game") or int(Profile.quest_progress.get("big_game", 0)) >= 1:
		_bon_mask(Vector3(-0.58, y, 0.0))
	# A token from each trader past level 1, in a row, with a star for each level past 2.
	for i in TRADER_TOKENS.size():
		var id: String = TRADER_TOKENS[i]
		var level := int(Profile.trader_levels.get(id, 1))
		if level < 2:
			continue
		var at := Vector3(-0.2 + i * 0.22, y, 0.02)
		var token := _token(id, at)
		for s in level - 2:
			_box(token, Vector3(0.035, 0.035, 0.01), Vector3(-0.04 + s * 0.045, -0.035, -0.06), GOLD)
		_add(token, "%s's token: level %d" % [Traders.title(id), level])


func _middle_shelf() -> void:
	var y: float = SHELF_Y[1]
	var extracts := int(Profile.stats.get("extracts", 0))
	for i in EXTRACT_MEDALS.size():
		var need: int = EXTRACT_MEDALS[i]
		if extracts < need:
			break
		var medal := _medal(Vector3(-0.78 + i * 0.2, y, -0.05), i)
		_add(medal, "Medal: %d extract%s" % [need, "" if need == 1 else "s"])
	var earned := int(Profile.stats.get("earned", 0))
	var piles := 0
	for step: int in CASH_STEPS:
		if earned >= step:
			piles += 1
	if piles > 0:
		var cash := _node(Vector3(0.45, y, 0.0), "Cash")
		for k in piles:   # (bundles stacked up in a little pile, more of them the more you've made)
			var row := k % 3
			var layer := k / 3
			_box(cash, Vector3(0.16, 0.05, 0.08), Vector3(-0.12 + row * 0.12, 0.025 + layer * 0.05, (row % 2) * 0.03),
				CASH, "", (row - 1) * 0.12)
			_box(cash, Vector3(0.03, 0.052, 0.082), Vector3(-0.12 + row * 0.12, 0.025 + layer * 0.05, (row % 2) * 0.03),
				BAND, "", (row - 1) * 0.12)
		_add(cash, "Cash pile: $%s made selling loot" % _money(earned))


func _bottom_shelf() -> void:
	var y: float = SHELF_Y[2]
	var raids := int(Profile.stats.get("raids", 0))
	if raids > 0:
		var jar := _node(Vector3(-0.65, y, 0.0), "Jar")
		var fill := clampf(float(raids) / JAR_FULL, 0.06, 1.0) * 0.2
		_box(jar, Vector3(0.17, fill, 0.17), Vector3(0.0, fill * 0.5 + 0.01, 0.0), BRASS)     # the casings in it
		for k in 6:   # (a few casings on top so it reads as casings, not a block)
			var a := k * TAU / 6.0
			_box(jar, Vector3(0.02, 0.05, 0.02), Vector3(cos(a) * 0.05, fill + 0.02, sin(a) * 0.05), BRASS_DARK, "",
				0.0, 0.5)
		_glass(jar, Vector3(0.2, 0.24, 0.2), Vector3(0.0, 0.12, 0.0))
		_box(jar, Vector3(0.21, 0.03, 0.21), Vector3(0.0, 0.255, 0.0), STEEL)                 # the lid
		_add(jar, "Casings jar: %d raid%s" % [raids, "" if raids == 1 else "s"])
	if Profile.bench_level >= Crafting.max_level():
		var wrench := _node(Vector3(0.0, y, 0.0), "Wrench")
		_box(wrench, Vector3(0.36, 0.025, 0.05), Vector3(0.0, 0.0125, 0.0), GOLD, "", 0.3)
		_box(wrench, Vector3(0.09, 0.026, 0.1), Vector3(0.17, 0.0125, -0.055), GOLD, "", 0.3)
		_box(wrench, Vector3(0.04, 0.03, 0.04), Vector3(0.18, 0.0125, -0.075), SHADOW, "", 0.3)
		_box(wrench, Vector3(0.22, 0.02, 0.14), Vector3(0.0, -0.0, 0.0), WOOD_DARK)            # (on a little plinth)
		_add(wrench, "Gold wrench: the workbench at its top level")
	var done := Profile.quests_done.size()
	var folders := done / FOLDERS_EVERY
	if folders > 0:
		var stack := _node(Vector3(0.6, y, 0.0), "Folders")
		for k in mini(folders, 12):
			_box(stack, Vector3(0.26, 0.022, 0.2), Vector3(0.0, 0.011 + k * 0.023, 0.0),
				[MANILA, OLIVE, MANILA, MAROON][k % 4], "", (k % 3 - 1) * 0.06)
		_add(stack, "Job folders: %d job%s done" % [done, "" if done == 1 else "s"])


# --- The pieces ----------------------------------------------------------------------------------------------------

const STEEL := Color(0.42, 0.44, 0.45)
const STEEL_DARK := Color(0.26, 0.27, 0.28)
const WOOD := Color(0.55, 0.4, 0.26)
const WOOD_DARK := Color(0.33, 0.23, 0.15)
const GOLD := Color(0.93, 0.74, 0.27)
const SILVER := Color(0.8, 0.82, 0.84)
const BRONZE := Color(0.72, 0.45, 0.24)
const BRASS := Color(0.78, 0.6, 0.28)
const BRASS_DARK := Color(0.6, 0.45, 0.2)
const CASH := Color(0.47, 0.62, 0.42)
const BAND := Color(0.9, 0.86, 0.72)
const BONE := Color(0.9, 0.87, 0.78)
const SHADOW := Color(0.08, 0.07, 0.07)
const RED := Color(0.72, 0.16, 0.14)
const BLUE := Color(0.2, 0.36, 0.6)
const OLIVE := Color(0.36, 0.4, 0.22)
const MANILA := Color(0.86, 0.76, 0.52)
const MAROON := Color(0.45, 0.14, 0.16)
const GREEN := Color(0.22, 0.55, 0.3)
const WHITE := Color(0.94, 0.94, 0.92)


func _build_cabinet() -> void:
	var w := WIDTH * 0.5
	var d := DEPTH * 0.5
	for x: float in [-w, w]:   # (four angle-iron uprights)
		for z: float in [-d, d]:
			_box(cabinet, Vector3(0.05, 2.05, 0.05), Vector3(x, 1.025, z), STEEL_DARK)
	for y: float in SHELF_Y + [0.06]:
		_box(cabinet, Vector3(WIDTH + 0.02, 0.04, DEPTH), Vector3(0.0, y - 0.02, 0.0), WOOD)
		_box(cabinet, Vector3(WIDTH + 0.06, 0.05, 0.03), Vector3(0.0, y - 0.025, -d - 0.005), STEEL)   # (a steel lip)
	_box(cabinet, Vector3(WIDTH, 2.0, 0.02), Vector3(0.0, 1.0, d - 0.01), WOOD_DARK)   # the back board
	# A sign on top, like the boards': TROPHIES.
	_box(cabinet, Vector3(1.1, 0.26, 0.04), Vector3(0.0, 2.2, 0.0), WOOD_DARK)
	var sign := Label3D.new()
	sign.text = "TROPHIES"
	sign.font_size = 48
	sign.pixel_size = 0.0035
	sign.modulate = BAND
	sign.outline_size = 0
	sign.position = Vector3(0.0, 2.2, -0.025)
	sign.rotation.y = PI   # (it reads from the front, -z)
	sign.font = HudStyle.font(40)
	cabinet.add_child(sign)


func _bon_mask(at: Vector3) -> void:
	var mask := _node(at, "BonMask")
	_box(mask, Vector3(0.05, 0.08, 0.05), Vector3(0.0, 0.04, 0.06), STEEL_DARK)          # the stand
	_box(mask, Vector3(0.16, 0.03, 0.12), Vector3(0.0, 0.015, 0.03), STEEL_DARK)
	var face := _node(Vector3(0.0, 0.2, 0.0), "Face", mask)
	face.rotation.x = -0.12   # (leant back a little)
	_box(face, Vector3(0.26, 0.28, 0.06), Vector3.ZERO, BONE)                            # a skull mask
	_box(face, Vector3(0.2, 0.08, 0.07), Vector3(0.0, -0.1, -0.005), BONE)               # (the jaw)
	for s: float in [-1.0, 1.0]:
		_box(face, Vector3(0.075, 0.07, 0.02), Vector3(s * 0.06, 0.03, -0.03), SHADOW)   # eye holes
	_box(face, Vector3(0.03, 0.04, 0.02), Vector3(0.0, -0.035, -0.03), SHADOW)            # nose
	for k in 5:
		_box(face, Vector3(0.012, 0.04, 0.02), Vector3(-0.06 + k * 0.03, -0.1, -0.035), SHADOW)   # teeth
	_box(face, Vector3(0.04, 0.2, 0.065), Vector3(0.095, 0.0, 0.0), RED, "", 0.0, 0.35)       # a red slash
	_add(mask, "Bon's mask: you killed Bon")


## A trader's token (on a small stand): each one theirs.
func _token(id: String, at: Vector3) -> Node3D:
	var t := _node(at, "Token_" + id)
	_box(t, Vector3(0.14, 0.02, 0.1), Vector3(0.0, 0.01, 0.0), WOOD_DARK)
	match id:
		"guns":        # Ponta: a gold round, standing
			_box(t, Vector3(0.03, 0.1, 0.03), Vector3(0.0, 0.07, 0.0), GOLD)
			_box(t, Vector3(0.022, 0.035, 0.022), Vector3(0.0, 0.135, 0.0), BRASS_DARK)
		"supplies":    # Big Don: a little crate with a red stamp
			_box(t, Vector3(0.1, 0.08, 0.08), Vector3(0.0, 0.06, 0.0), OLIVE)
			_box(t, Vector3(0.04, 0.04, 0.01), Vector3(0.0, 0.06, -0.042), RED)
		"valuables":   # Supreme: a gem
			_box(t, Vector3(0.07, 0.07, 0.07), Vector3(0.0, 0.07, 0.0), BLUE, "", 0.785, 0.0, 0.615)
		"ming":        # Ming: a gold die
			_box(t, Vector3(0.07, 0.07, 0.07), Vector3(0.0, 0.055, 0.0), GOLD, "", 0.4)
			_box(t, Vector3(0.02, 0.02, 0.01), Vector3(0.0, 0.055, -0.036), SHADOW, "", 0.4)
		"meds":        # the Medic: a white tin with a green cross
			_box(t, Vector3(0.1, 0.07, 0.07), Vector3(0.0, 0.055, 0.0), WHITE)
			_box(t, Vector3(0.05, 0.015, 0.01), Vector3(0.0, 0.055, -0.036), GREEN)
			_box(t, Vector3(0.015, 0.05, 0.01), Vector3(0.0, 0.055, -0.036), GREEN)
	return t


## A medal on a little easel: bronze, silver, gold, then gold with a star.
func _medal(at: Vector3, rank: int) -> Node3D:
	var m := _node(at, "Medal%d" % rank)
	var metal: Color = [BRONZE, SILVER, GOLD, GOLD, GOLD][rank]
	var ribbon: Color = [RED, BLUE, GREEN, MAROON, RED][rank]
	_box(m, Vector3(0.12, 0.02, 0.08), Vector3(0.0, 0.01, 0.02), WOOD_DARK)
	_box(m, Vector3(0.1, 0.22, 0.02), Vector3(0.0, 0.12, 0.04), WOOD_DARK, "", 0.0, -0.2)   # the easel's back
	_box(m, Vector3(0.05, 0.1, 0.01), Vector3(0.0, 0.17, 0.02), ribbon, "", 0.0, -0.2)
	_box(m, Vector3(0.012, 0.1, 0.012), Vector3(0.0, 0.17, 0.014), WHITE, "", 0.0, -0.2)     # (a stripe down it)
	_box(m, Vector3(0.075, 0.075, 0.015), Vector3(0.0, 0.1, 0.008), metal, "", 0.0, -0.2, 0.785)
	if rank >= 3:
		_box(m, Vector3(0.03, 0.03, 0.01), Vector3(0.0, 0.1, -0.002), WHITE if rank == 3 else RED, "", 0.0, -0.2, 0.785)
	return m


func _glass(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var box := _box(parent, size, at, Color(0.75, 0.88, 0.9, 0.25))
	var m := box.material_override as StandardMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.2


func _add(node: Node3D, label: String) -> void:
	trophies.append({"node": node, "label": label})


func _node(at: Vector3, name_: String, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.name = name_
	n.position = at if parent != null else Vector3(-at.x, at.y, at.z)   # (seen from the front, -z: +x is on your left)
	if parent == null:
		n.scale = Vector3.ONE * TROPHY_SCALE   # (made at about real size; a bit bigger so they read from the room)
	(parent if parent != null else shelf).add_child(n)
	return n


func _material(colour: Color) -> StandardMaterial3D:
	if not _materials.has(colour):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = 0.9 if colour.a >= 1.0 else 0.2
		if colour in [GOLD, SILVER, BRASS, BRONZE]:
			m.metallic = 0.6
			m.roughness = 0.35
		_materials[colour] = m
	return _materials[colour]


func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color, name_ := "", yaw := 0.0, pitch := 0.0,
		roll := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var box := MeshInstance3D.new()
	if name_ != "":
		box.name = name_
	box.mesh = mesh
	box.material_override = _material(colour) if colour.a >= 1.0 else _material(colour).duplicate()
	box.position = at
	box.rotation = Vector3(pitch, yaw, roll)
	parent.add_child(box)
	return box


static func _money(amount: int) -> String:
	var s := str(amount)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


## True if the shelf stands by the record board, clear of the hideout's walls and props (the tests): rays from its
## middle out to each corner, at a few heights, hit nothing.
func board_near(level: Node3D) -> bool:
	var board := level.get_node_or_null("Stations/workbench") as Node3D
	if board == null or not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	for h: float in [0.3, 1.0, 1.7]:
		for corner: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
			var from := global_transform * Vector3(0.0, h, 0.0)
			var to := global_transform * Vector3(corner.x * WIDTH * 0.55, h, corner.z * DEPTH * 0.6)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | 512))
			if not hit.is_empty():
				return false
	return global_position.distance_to(board.global_position) < 8.0
