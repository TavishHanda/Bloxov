class_name WorldSounds
extends RefCounted
## Movement and world sounds (Sound update 0.20.2): jumping, landing, vaulting, ladders, going prone, doors, locks,
## searching, safes and bullet impacts by surface. Each plays on top of whatever played there before (the old step
## sounds on a landing or a vault stay).

const JUMP := preload("res://audio/world/jump.wav")
const LAND := preload("res://audio/world/land.wav")
const VAULT := preload("res://audio/world/vault.wav")
const RUNG := preload("res://audio/world/rung.wav")
const PRONE := preload("res://audio/world/prone.wav")
const DOOR_OPEN := preload("res://audio/world/door_open.wav")
const DOOR_CLOSE := preload("res://audio/world/door_close.wav")
const LOCKED := preload("res://audio/world/locked.wav")
const UNLOCK := preload("res://audio/world/unlock.wav")
const HEAVY_DOOR := preload("res://audio/world/heavy_door.wav")
const RUMMAGE := preload("res://audio/world/rummage.wav")
const SAFE := preload("res://audio/world/safe.wav")
## Bullet impacts by what they hit (BoxMap surfaces: ground, wood, metal, concrete, water).
const IMPACTS: Array[AudioStream] = [preload("res://audio/world/impact_dirt.wav"), preload("res://audio/world/impact_wood.wav"),
	preload("res://audio/world/impact_metal.wav"), preload("res://audio/world/impact_concrete.wav"),
	preload("res://audio/world/impact_dirt.wav")]
const IMPACT_RANGE := 40.0
## Someone else's bullets landing (0.22.8): this much quieter, so you hear the gun shooting at you over them.
const OTHERS_IMPACT_DB := -8.0
## Using an item (0.20.3), by item id; today's heal sound still plays with them.
const ITEMS := {
	"bandage": preload("res://audio/items/bandage.wav"),
	"medkit": preload("res://audio/items/medkit.wav"),
	"energy_drink": preload("res://audio/items/drink.wav"),
}
const PIN := preload("res://audio/items/pin.wav")
## World sounds others make (doors): heard this far.
const DOOR_RANGE := 30.0


## Your own body's sound (2D: jump, landing, vault, ladder, prone, searching).
static func own(node: Node, stream: AudioStream, volume_db := 0.0) -> void:
	Effects.sound(node.get_tree().current_scene, stream, volume_db, 0.06)


## A sound out in the world at `pos`, heard `range` m at most.
static func at(node: Node, stream: AudioStream, pos: Vector3, volume_db := 0.0, range := DOOR_RANGE) -> void:
	Effects.sound_at(node.get_tree().current_scene, stream, pos, volume_db, 0.06, 1.0, 4.0, range)


## A bullet hitting the map at `pos` (surface facing `normal`): a sound for what it hit (`others`: not your shot).
static func impact(world: Node, pos: Vector3, normal: Vector3, others := false) -> void:
	if world == null:
		return
	var camera := Hearing.listener(world)
	if camera == null or camera.global_position.distance_to(pos) > IMPACT_RANGE:
		return
	var surface := BoxMap.SURFACE_GROUND
	for map in RaidScope.nodes(world, &"box_maps"):
		surface = (map as BoxMap).surface_hit(pos - normal * 0.05)
		if surface != BoxMap.SURFACE_GROUND:
			break
	Effects.sound_at(world, IMPACTS[surface], pos, -8.0 + (OTHERS_IMPACT_DB if others else 0.0), 0.12, 1.0, 3.0, IMPACT_RANGE)
