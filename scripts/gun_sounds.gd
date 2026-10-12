class_name GunSounds
extends RefCounted
## Each gun's shot and working sounds (0.15.12, owner: "make sounds for the new guns ... keep any remaining sounds").
## The Hound and Stinger keep the original shot.wav (pitched by their shot_pitch); the Wasp, Mauler and Lancer have
## their own (tools/make_sounds.py). Used by the player's gun and by the AI, so a scav with a Mauler sounds like one.

const DEFAULT_SHOT := preload("res://audio/shot.wav")
const SHOTS := {
	"smg": preload("res://audio/shot_wasp.wav"),
	"shotgun": preload("res://audio/shot_mauler.wav"),
	"sniper": preload("res://audio/shot_lancer.wav"),
}
## Working the action between shots (ItemDB "cycle").
const CYCLES := {
	"pump": preload("res://audio/pump.wav"),
	"bolt": preload("res://audio/bolt.wav"),
}
const SHELL_IN := preload("res://audio/shell_in.wav")


## The shot sound of gun `id` ("" or a gun without its own: the original).
static func shot(id: String) -> AudioStream:
	return SHOTS.get(id, DEFAULT_SHOT)
