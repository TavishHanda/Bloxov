class_name HandItem
extends Node3D
## Placeholder first-person animations (0.14.17, owner: "placeholders, we design the real stuff later"): a gloved
## hand that brings up a grenade, a med or a drink while the gun is lowered out of the way. Lives under the
## player's camera. `show_item(id)` raises it, `throw()` swings it forward and away, `put_away()` drops it.

const GLOVE := Color(0.16, 0.16, 0.15)
## Where the hand sits: out of sight, held up, and thrown forward.
const HIDDEN := Vector3(0.16, -0.55, -0.35)
const HELD := Vector3(0.17, -0.2, -0.42)
const WIND_UP := Vector3(0.24, -0.08, -0.25)
const THROWN := Vector3(0.05, -0.05, -0.9)

enum Pose { HIDDEN, HELD, WIND_UP, THROWN }

var pose := Pose.HIDDEN
var item_id := ""
var _item: Node3D
var _hand: MeshInstance3D
var _time := 0.0


func _ready() -> void:
	position = HIDDEN
	visible = false
	_hand = _box(Vector3(0.09, 0.09, 0.16), GLOVE)
	_hand.position = Vector3(0.02, -0.06, 0.06)
	add_child(_hand)


## Brings up the item (by ItemDB id) in the hand.
func show_item(id: String) -> void:
	if _item != null:
		_item.queue_free()
	item_id = id
	_item = _build(id)
	add_child(_item)
	visible = true
	pose = Pose.HELD


## Pulls back to throw (the grenade's last moment in the hand).
func wind_up() -> void:
	pose = Pose.WIND_UP


## The arm swings forward: the item leaves the hand (the real grenade flies from the camera).
func throw() -> void:
	pose = Pose.THROWN
	if _item != null:
		_item.visible = false


func put_away() -> void:
	pose = Pose.HIDDEN


func is_up() -> bool:
	return visible and pose != Pose.HIDDEN


func _process(delta: float) -> void:
	_time += delta
	var target: Vector3 = [HIDDEN, HELD, WIND_UP, THROWN][pose]
	var target_rot := Vector3.ZERO
	match pose:
		Pose.HELD:
			# A little sway, and a med being worked on wobbles.
			target += Vector3(sin(_time * 2.0) * 0.004, sin(_time * 3.1) * 0.004, 0)
			if ItemDB.ITEMS.has(item_id) and ItemDB.kind(item_id) != "throwable":
				target_rot = Vector3(sin(_time * 7.0) * 0.12, 0.3, sin(_time * 5.0) * 0.08)
		Pose.WIND_UP:
			target_rot = Vector3(0.7, 0, -0.3)
		Pose.THROWN:
			target_rot = Vector3(-0.9, 0, 0.2)
	var speed := 22.0 if pose == Pose.THROWN else 12.0
	position = position.lerp(target, minf(delta * speed, 1.0))
	rotation = rotation.lerp(target_rot, minf(delta * speed, 1.0))
	# Done going away (or thrown and drifted out): hide until next time.
	if pose == Pose.THROWN and position.distance_to(THROWN) < 0.05:
		pose = Pose.HIDDEN
	if pose == Pose.HIDDEN and position.distance_to(HIDDEN) < 0.03:
		visible = false


func _build(id: String) -> Node3D:
	var root := Node3D.new()
	match ItemDB.kind(id) if ItemDB.ITEMS.has(id) else "":
		"throwable":
			root.add_child(_box(Vector3(0.07, 0.1, 0.07), Color(0.25, 0.32, 0.18)))
			var lever := _box(Vector3(0.015, 0.07, 0.02), Color(0.55, 0.55, 0.5))
			lever.position = Vector3(0.04, 0.02, 0)
			root.add_child(lever)
			var ring := _box(Vector3(0.03, 0.03, 0.006), Color(0.7, 0.7, 0.65))
			ring.position = Vector3(-0.02, 0.07, 0)
			root.add_child(ring)
		"drink":
			var can := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.035
			cylinder.bottom_radius = 0.035
			cylinder.height = 0.13
			cylinder.radial_segments = 8
			cylinder.material = Effects.unshaded(Color(0.2, 0.6, 0.95))
			can.mesh = cylinder
			root.add_child(can)
			var stripe := _box(Vector3(0.072, 0.03, 0.072), Color(0.95, 0.85, 0.2))
			root.add_child(stripe)
		_:
			if id == "medkit":
				root.add_child(_box(Vector3(0.16, 0.1, 0.06), Color(0.75, 0.15, 0.15)))
				var cross_a := _box(Vector3(0.06, 0.018, 0.065), Color(0.95, 0.95, 0.95))
				var cross_b := _box(Vector3(0.018, 0.06, 0.065), Color(0.95, 0.95, 0.95))
				root.add_child(cross_a)
				root.add_child(cross_b)
			else:
				# A bandage roll.
				var roll := MeshInstance3D.new()
				var cylinder := CylinderMesh.new()
				cylinder.top_radius = 0.04
				cylinder.bottom_radius = 0.04
				cylinder.height = 0.06
				cylinder.radial_segments = 8
				cylinder.material = Effects.unshaded(Color(0.92, 0.9, 0.85))
				roll.mesh = cylinder
				roll.rotation.z = PI * 0.5
				root.add_child(roll)
	root.position = Vector3(0, 0.02, 0)
	return root


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = Effects.unshaded(color)
	mesh.mesh = box
	return mesh
