class_name TraderIdle
extends RefCounted
## How a trader stands behind their counter in the walkable hideout (HideoutCrew). Owner (0.36.40): they were
## "dilly dallying around doing some weird stuff with their arms": every arm was swung by fixed angles, so hands
## waved about in mid-air. Now each hand is put somewhere real (flat on the counter, on the job in front of them,
## under the chin, arms folded) and the arm bends to reach it (BodyPose._reach), and they go from one thing to the
## next now and then: mostly their own job (the guns trader wipes down a rifle lying on the counter, the supplier
## counts cash, the jeweller looks a watch over close up, Ming shuffles, the medic writes notes), between it leaning
## on the counter, drumming their fingers, arms folded, a think with the chin in a hand, a look back at the shelves.
## When you walk up they stop and lean on the counter, ready to deal. Looks only (never on the server).
##
## Places are in the trader's own space: metres from their feet, +x their right, -z ahead (the counter's back edge
## is 0.35 ahead, its top 0.96 up; make_hideout.py stalls()).

const COUNTER_Y := 0.99      # a hand resting on the counter top (its middle)
const EASE := 3.2            # how fast hands and body move to the next thing (per second)
## What each one does, and how much more often than the rest they do it.
const BEATS := {
	"guns": {"work": 4.0, "lean": 1.5, "fold": 1.0, "tap": 1.0, "shelf": 0.8},
	"supplies": {"work": 3.0, "lean": 1.5, "fold": 1.0, "think": 0.8, "shelf": 0.8},
	"valuables": {"work": 3.5, "lean": 1.5, "think": 1.0, "tap": 1.0, "shelf": 0.6},
	"ming": {"work": 3.5, "lean": 1.5, "fold": 0.8, "tap": 1.0, "shelf": 0.6},
	"meds": {"work": 4.0, "lean": 1.2, "fold": 0.8, "think": 1.0, "shelf": 0.8},
}

var trader := ""
var model: Node3D
var pose: BodyPose
var beat := "work"
var _left := 0.0             # seconds left at this beat
var _t := 0.0
var _dice: RandomNumberGenerator
## Where the hands are going to (trader space) and how bent forward / turned the body is, all eased.
var _hand_l := Vector3(-0.36, COUNTER_Y, -0.45)
var _hand_r := Vector3(0.36, COUNTER_Y, -0.45)
var _spine := Vector3.ZERO
var _neck := Vector3.ZERO
var _pole_l := Vector3(-1, 0, 1)
var _pole_r := Vector3(1, 0, 1)
## Things in their hands, shown only on the job ({node: [side, offset, turn degrees]}), and on the counter.
var _held := {}


func _init(id: String, body: Node3D, body_pose: BodyPose, dice: RandomNumberGenerator) -> void:
	trader = id
	model = body
	pose = body_pose
	_dice = dice
	_t = dice.randf() * 50.0
	_left = dice.randf_range(2.0, 8.0)
	_props()
	var want := _want()
	_hand_l = want["l"]
	_hand_r = want["r"]
	_spine = want["spine"]
	_neck = want["neck"]


## A step: `near` is true while you're at their counter. Returns the neck angles (degrees) for the crew's look-at.
func update(delta: float, near: bool) -> Vector3:
	_t += delta
	_left -= delta
	if near and beat != "lean":
		_go("lean")
	elif not near and _left <= 0.0:
		_go(_pick())
	var want := _want()
	var k := 1.0 - exp(-EASE * delta) if delta > 0.0 else 1.0
	_hand_l = _hand_l.lerp(want["l"], k)
	_hand_r = _hand_r.lerp(want["r"], k)
	_spine = _spine.lerp(want["spine"], k)
	_neck = _neck.lerp(want["neck"], k)
	_pole_l = _pole_l.lerp(want["pole_l"], k)
	_pole_r = _pole_r.lerp(want["pole_r"], k)
	var spine := pose.joint("Spine")
	spine.rotation += Vector3(deg_to_rad(_spine.x), deg_to_rad(_spine.y), deg_to_rad(_spine.z))
	var to := model.global_transform
	var b := model.global_basis
	pose._reach("L", to * _hand_l, b * _pole_l)
	pose._reach("R", to * _hand_r, b * _pole_r)
	_show(delta)
	return _neck


func _go(next: String) -> void:
	beat = next
	_left = _dice.randf_range(7.0, 13.0) if next == "work" else _dice.randf_range(3.5, 6.5)


## The next thing to do: by their weights, never the same twice running (after anything else, back to work more).
func _pick() -> String:
	var weights: Dictionary = BEATS.get(trader, BEATS["guns"])
	var total := 0.0
	for key: String in weights:
		if key != beat:
			total += float(weights[key]) * (2.0 if key == "work" else 1.0)
	var roll := _dice.randf() * total
	for key: String in weights:
		if key == beat:
			continue
		roll -= float(weights[key]) * (2.0 if key == "work" else 1.0)
		if roll <= 0.0:
			return key
	return "work"


## Where everything wants to be now, for the beat they're on: hands (l, r), the elbows' way out (pole_l, pole_r,
## trader space), the body's lean (spine) and the head (neck), degrees.
func _want() -> Dictionary:
	var t := _t
	var sway := sin(t * 0.45)
	# Resting on the counter: hands flat, shoulder-width, leaning on them a little, elbows out and back.
	var w := {"l": Vector3(-0.34, COUNTER_Y, -0.46), "r": Vector3(0.34, COUNTER_Y, -0.46),
		"pole_l": Vector3(-0.8, -0.2, 0.8), "pole_r": Vector3(0.8, -0.2, 0.8),
		"spine": Vector3(-11, 0, 2.0 * sway), "neck": Vector3(8, 0, 0)}
	match beat:
		"lean":   # weight from one hand to the other, a slow look round
			w["l"] += Vector3(0, 0, 0.03 * sway)
			w["r"] += Vector3(0, 0, -0.03 * sway)
			w["spine"] = Vector3(-13, 4.0 * sway, 3.0 * sway)
			w["neck"] = Vector3(10, 18.0 * sin(t * 0.23), 0)
		"tap":   # one hand flat, the other drumming its fingers, in bursts, looking off down the market
			var drum := maxf(0.0, sin(t * 0.9)) * absf(sin(t * 11.0))
			w["r"] = Vector3(0.3, COUNTER_Y + 0.035 * drum, -0.5)
			w["spine"] = Vector3(-8, -6, 3)
			w["neck"] = Vector3(4, 28.0 + 8.0 * sin(t * 0.3), 0)
		"fold":   # stood back, arms folded across the chest
			w["l"] = Vector3(0.02, 1.08, -0.3)
			w["r"] = Vector3(-0.02, 1.12, -0.33)
			w["pole_l"] = Vector3(-1, -0.4, -0.3)
			w["pole_r"] = Vector3(1, -0.4, -0.3)
			w["spine"] = Vector3(3, 0, 1.5 * sway)
			w["neck"] = Vector3(-2, 14.0 * sin(t * 0.27), 0)
		"think":   # chin in the right hand, that elbow held in the left, a slow rub
			w["r"] = Vector3(0.08, 1.37 + 0.01 * sin(t * 1.3), -0.34)
			w["l"] = Vector3(-0.02, 1.08, -0.3)
			w["pole_r"] = Vector3(0.4, -1, -0.4)
			w["pole_l"] = Vector3(-1, -0.5, -0.2)
			w["spine"] = Vector3(-4, 0, 0)
			w["neck"] = Vector3(-4, -10.0 + 6.0 * sin(t * 0.4), 4)
		"shelf":   # a look back at the stock on the racking behind, one hand still on the counter
			w["l"] = Vector3(-0.3, COUNTER_Y, -0.4)
			w["r"] = Vector3(0.42, 0.95, -0.12)   # (hand at the hip, turned away)
			w["pole_r"] = Vector3(1, 0, 0.6)
			w["spine"] = Vector3(-2, 18, 0)
			w["neck"] = Vector3(-8, 52.0 + 10.0 * sin(t * 0.5), 0)
		"work":
			w.merge(_work(t), true)
	return w


## Each trader's own job.
func _work(t: float) -> Dictionary:
	match trader:
		"guns":   # a rifle lying on the counter: the left hand holds it, the right wipes along the barrel with a rag
			var stroke := sin(t * 1.8)
			return {"l": Vector3(-0.28, COUNTER_Y + 0.03, -0.5), "r": Vector3(0.16 + 0.11 * stroke, COUNTER_Y + 0.05 + 0.012 * cos(t * 3.6), -0.53),
				"pole_l": Vector3(-0.8, -0.3, 0.8), "pole_r": Vector3(0.8, -0.3, 0.8),
				"spine": Vector3(-13, 3.0 * stroke, 0), "neck": Vector3(-8, 6.0 * stroke, 0)}
		"supplies":   # counting a wad of cash over the counter: a note at a time from the left hand to the right, a pause
			var count := fmod(t, 6.0)
			var flick := maxf(0.0, sin(count * TAU * 1.4)) if count < 3.6 else 0.0
			return {"l": Vector3(-0.12, COUNTER_Y + 0.06, -0.52), "r": Vector3(0.1 + 0.08 * flick, COUNTER_Y + 0.06 + 0.03 * flick, -0.52),
				"pole_l": Vector3(-0.9, -0.3, 0.7), "pole_r": Vector3(0.9, -0.3, 0.7),
				"spine": Vector3(-10, 0, 0), "neck": Vector3(-12, 0, 0)}
		"valuables":   # a gold watch held up by the eyeglass, turned a little now and then; the other hand on the counter
			var turn := sin(t * 0.7)
			return {"r": Vector3(0.2 + 0.02 * turn, 1.4 + 0.015 * sin(t * 1.1), -0.5), "pole_r": Vector3(1, -1, 0.3),
				"l": Vector3(-0.34, COUNTER_Y, -0.46), "spine": Vector3(-6, -4, 0), "neck": Vector3(-4, 14.0 + 4.0 * turn, 4)}
		"ming":   # shuffling over the counter: the two halves riffled together, squared up, again
			var cycle := fmod(t, 2.4)
			var riffle := absf(sin(t * 14.0)) * (1.0 if cycle < 1.4 else 0.0)
			var close := smoothstep(1.4, 1.8, cycle) * (1.0 - smoothstep(2.1, 2.4, cycle))
			var apart := 0.14 - 0.08 * close
			return {"l": Vector3(-apart, COUNTER_Y + 0.05 + 0.012 * riffle + 0.04 * close, -0.52),
				"r": Vector3(apart, COUNTER_Y + 0.05 + 0.012 * riffle + 0.04 * close, -0.52),
				"pole_l": Vector3(-0.9, -0.3, 0.7), "pole_r": Vector3(0.9, -0.3, 0.7),
				"spine": Vector3(-9, 0, 0), "neck": Vector3(-12, 0, 0)}
		"meds":   # writing on a clipboard lying on the counter, the left hand holding it still, a pen lift now and then
			var line := fmod(t, 3.0)
			var lift := smoothstep(2.6, 2.8, line) * (1.0 - smoothstep(2.8, 3.0, line))
			return {"l": Vector3(-0.12, COUNTER_Y + 0.02, -0.5), "r": Vector3(0.08 + 0.08 * line / 3.0 + 0.008 * sin(t * 13.0),
				COUNTER_Y + 0.04 + 0.006 * cos(t * 9.0) + 0.04 * lift, -0.52),
				"pole_l": Vector3(-0.8, -0.3, 0.8), "pole_r": Vector3(0.8, -0.3, 0.8),
				"spine": Vector3(-14, 0, 0), "neck": Vector3(-10, -4, 0)}
	return {}


## What they work with: a rifle and rag (guns), a wad and a note (supplies), a watch (valuables), two halves of a deck
## (ming), a clipboard on the counter and a pen (meds). The hand-held ones follow the hands and show only on the job.
func _props() -> void:
	match trader:
		"guns":
			var rifle := _box(model, Vector3(0.75, 0.05, 0.09), Color(0.18, 0.18, 0.19))
			rifle.position = Vector3(0.0, 0.985, -0.56)
			rifle.rotation_degrees = Vector3(0, 8, 0)
			var stock := _box(rifle, Vector3(0.24, 0.07, 0.07), Color(0.36, 0.25, 0.16))
			stock.position = Vector3(-0.42, 0.0, 0.0)
			var mag := _box(rifle, Vector3(0.06, 0.03, 0.12), Color(0.14, 0.14, 0.15))
			mag.position = Vector3(-0.08, -0.01, 0.08)
			_hold(_box(model, Vector3(0.1, 0.03, 0.08), Color(0.85, 0.82, 0.72)), "R", Vector3(0, -0.04, 0))
		"supplies":
			_hold(_box(model, Vector3(0.14, 0.035, 0.07), Color(0.42, 0.6, 0.38)), "L", Vector3(0.03, 0.03, -0.02))
			_hold(_box(model, Vector3(0.14, 0.006, 0.07), Color(0.46, 0.64, 0.42)), "R", Vector3(-0.02, 0.03, -0.02), Vector3(0, 0, 15))
		"valuables":
			_hold(_box(model, Vector3(0.05, 0.05, 0.015), Color(0.85, 0.68, 0.25)), "R", Vector3(-0.03, 0.03, -0.05))
		"ming":
			_hold(_box(model, Vector3(0.1, 0.04, 0.07), Color(0.93, 0.91, 0.86)), "L", Vector3(0.03, 0.02, -0.03))
			_hold(_box(model, Vector3(0.1, 0.04, 0.07), Color(0.93, 0.91, 0.86)), "R", Vector3(-0.03, 0.02, -0.03))
		"meds":
			var board := _box(model, Vector3(0.24, 0.015, 0.31), Color(0.55, 0.42, 0.28))
			board.position = Vector3(0.04, 0.968, -0.58)
			board.rotation_degrees = Vector3(0, 12, 0)
			var paper := _box(board, Vector3(0.2, 0.004, 0.25), Color(0.92, 0.91, 0.86))
			paper.position = Vector3(0, 0.009, 0.01)
			_hold(_box(model, Vector3(0.012, 0.11, 0.012), Color(0.15, 0.15, 0.18)), "R", Vector3(0, 0.04, -0.02), Vector3(-30, 0, 20))


func _hold(node: Node3D, side: String, offset: Vector3, turn := Vector3.ZERO) -> void:
	_held[node] = [side, offset, turn]


## Hand-held things go with the hands (where the arm really got to), facing the way the trader faces; they show
## only once the hands are at the job.
func _show(_delta: float) -> void:
	var on := beat == "work"
	for node: Node3D in _held:
		var spec: Array = _held[node]
		var elbow := pose.joint("Elbow" + String(spec[0]))
		var hand := model.to_local(elbow.global_transform * Vector3(0, -BodyPose.REACH, 0))
		node.position = hand + spec[1]
		node.rotation_degrees = spec[2]
		node.visible = on and hand.distance_to(_hand_r if spec[0] == "R" else _hand_l) < 0.12


func _box(parent: Node3D, size: Vector3, colour: Color) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	mesh.material = material
	box.mesh = mesh
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(box)
	return box
