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
## Riptide's sub bay power (0.33.3): the switch, and the klaxon it sets off.
const POWER_ON := preload("res://audio/world/power_on.wav")
const ALARM := preload("res://audio/world/alarm.wav")
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

## More sounds (0.31.14, owner 2026-11-07). All soft: players and the AI stay the loudest thing you hear.
const ARMOR_HIT := preload("res://audio/world/armor_hit.wav")
const GEAR_BREAK := preload("res://audio/world/gear_break.wav")
const KEY_BREAK := preload("res://audio/world/key_break.wav")
const GRENADE_BOUNCE := preload("res://audio/world/grenade_bounce.wav")
const DOWNED := preload("res://audio/world/downed.wav")
const REVIVING := preload("res://audio/world/reviving.wav")
const GET_UP := preload("res://audio/world/get_up.wav")
const CROWS: Array[AudioStream] = [preload("res://audio/world/crow1.wav"), preload("res://audio/world/crow2.wav")]
const FLAG := preload("res://audio/world/flag.wav")
const CAN := preload("res://audio/world/can.wav")
const BOTTLE := preload("res://audio/world/bottle.wav")
const LAMP_CREAK := preload("res://audio/world/lamp_creak.wav")
const CURTAIN := preload("res://audio/world/curtain.wav")
const CASINGS: Array[AudioStream] = [preload("res://audio/world/casing1.wav"), preload("res://audio/world/casing2.wav"),
	preload("res://audio/world/casing3.wav")]
const HEARTBEAT := preload("res://audio/world/heartbeat.wav")
const BREATH := preload("res://audio/world/breath.wav")
## How loud each is (dB), and how far the ones out in the world carry (m).
const ARMOR_DB := -9.0
const GEAR_BREAK_DB := -6.0
const KEY_BREAK_DB := -8.0
const BOUNCE_DB := -6.0
const BOUNCE_RANGE := 30.0
const DOWNED_DB := -6.0
const REVIVING_DB := -11.0
const GET_UP_DB := -9.0
const TEAMMATE_RANGE := 30.0
const CROW_DB := -16.0
const CROW_RANGE := 110.0
const FLAG_DB := -20.0
const FLAG_RANGE := 22.0
const CAN_DB := -14.0
const CAN_RANGE := 20.0
const LAMP_DB := -20.0
const LAMP_RANGE := 14.0
const CURTAIN_DB := -16.0
const CURTAIN_RANGE := 12.0
const CASING_DB := -22.0            # on wood, metal or concrete; on the ground it is softer still
const CASING_GROUND_DB := -30.0
const HEARTBEAT_DB := -16.0
const BREATH_DB := -20.0
## Their own dice for pitch (not the game's: the smoke test seeds that).
static var rng := RandomNumberGenerator.new()


## One of the newer sounds of your own (2D), on its own dice.
static func own_soft(node: Node, stream: AudioStream, volume_db: float, jitter := 0.06) -> void:
	if node == null or not node.is_inside_tree():
		return
	Effects.sound(node.get_tree().current_scene, stream, volume_db, jitter, 1.0, rng)


## One of the newer sounds out in the world at `pos` (in `world`), heard `range` m at most, on its own dice.
static func at_soft(world: Node, stream: AudioStream, pos: Vector3, volume_db: float, range: float, pitch := 1.0,
		jitter := 0.06) -> void:
	if world == null or not world.is_inside_tree():
		return
	Effects.sound_at(world, stream, pos, volume_db, jitter, pitch, 3.0, range, &"", true, 0.0, rng)


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
