class_name Look
extends Resource
## A saved lighting look (Look update, 0.19): the sky, ambient light, colour grading and sun of a raid, in one file
## under assets/looks/. Every raid scene (players' games and the server's raid copies) puts `current` on its
## WorldEnvironment and Sun as it's made, so changing the look of the game = pointing `current` at another file.
## `classic.tres` is the look up to 0.18 (the owner asked to keep it, so it can always be put back: point `current`
## at CLASSIC). 0.19.1: `late_afternoon.tres` (the owner picked option C: low warm sun, light haze, less saturated).
## 0.20.10: its tonemap is Filmic (was ACES) with a bit more ambient light, so dark colours indoors aren't crushed to black.
## Looks only: nothing here changes what the AI or players can see through.

const CLASSIC := "res://assets/looks/classic.tres"

## The look every raid uses.
static var current := "res://assets/looks/late_afternoon.tres"

@export var title := ""
@export var environment: Environment
@export var sun_transform := Transform3D.IDENTITY
@export var sun_color := Color.WHITE
@export var sun_energy := 1.0
@export var cloud_color := Color(0.97, 0.98, 1.0)


## Puts the look at `path` on `raid`'s WorldEnvironment, Sun and Clouds (whichever it has).
static func apply(raid: Node, path: String = current) -> void:
	var look := load(path) as Look
	if look == null:
		push_error("Look: can't load %s" % path)
		return
	var world := raid.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and look.environment != null:
		world.environment = look.environment
	var sun := raid.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		# (only the turn: the sun node's position doesn't matter to a directional light)
		sun.basis = look.sun_transform.basis
		sun.light_color = look.sun_color
		sun.light_energy = look.sun_energy
		GameSettings.shadows_on(sun)
	var clouds := raid.get_node_or_null("Clouds")
	if clouds != null:
		clouds.set("color", look.cloud_color)
