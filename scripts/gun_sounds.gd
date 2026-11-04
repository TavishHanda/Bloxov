class_name GunSounds
extends RefCounted
## Each gun's shot and working sounds (0.15.12, owner: "make sounds for the new guns ... keep any remaining sounds").
## The Hound and Stinger keep the original shot.wav (pitched by their shot_pitch); the Wasp, Mauler and Lancer have
## their own (tools/make_sounds.py). Used by the player's gun and by the AI, so a scav with a Mauler sounds like one.
##
## Sound 2.0 (0.30.0): the same shot at distance and indoors, made from the gun's own file by
## tools/make_sound_variants.py. The near sound is today's file, untouched; the other variants are RMS-matched to it, so
## the existing distance/volume maths still decides loudness and nothing sounds quieter just for being a variant.

const DEFAULT_SHOT := preload("res://audio/shot.wav")
const PISTOL_SHOT := preload("res://audio/shot_pistol.wav")
const SHOTS := {
	"smg": preload("res://audio/shot_wasp.wav"),
	"shotgun": preload("res://audio/shot_mauler.wav"),
	"sniper": preload("res://audio/shot_lancer.wav"),
	"pistol": PISTOL_SHOT,
}
## Working the action between shots (ItemDB "cycle").
const CYCLES := {
	"pump": preload("res://audio/pump.wav"),
	"bolt": preload("res://audio/bolt.wav"),
}
const SHELL_IN := preload("res://audio/shell_in.wav")
## Sound update 0.20.3: each gun's reload is today's mag out/in sounds pitched a little (lighter guns higher), plus
## a clack when you swap guns and a cloth rustle when you aim.
const RELOAD_PITCH := {"pistol": 1.2, "smg": 1.1, "ak": 1.0, "sniper": 0.88}
const DRAW := preload("res://audio/items/draw.wav")
const AIM := preload("res://audio/items/aim.wav")

## Where the listener is (0.30.0): a shot heard indoors has the room's tail baked in, because the web build skips bus
## effects (CHANGELOG 0.20.8).
enum Place { OUTDOOR, ROOM }
## Past this the shot is the mid version; past BAND_FAR, the far one. They sit either side of the 0.20 far boom (45 m).
const BAND_NEAR := 20.0
const BAND_FAR := 50.0

## One set per base sound: ak uses "default" (the original shot.wav), the pistol its own since 0.30.0.
const VARIANTS := {
	"default": {
		"mid": preload("res://audio/guns/default_mid.wav"),
		"far": preload("res://audio/guns/default_far.wav"),
		"room": preload("res://audio/guns/default_room.wav"),
		"room_far": preload("res://audio/guns/default_room_far.wav"),
	},
	"pistol": {
		"mid": preload("res://audio/guns/pistol_mid.wav"),
		"far": preload("res://audio/guns/pistol_far.wav"),
		"room": preload("res://audio/guns/pistol_room.wav"),
		"room_far": preload("res://audio/guns/pistol_room_far.wav"),
	},
	"wasp": {
		"mid": preload("res://audio/guns/wasp_mid.wav"),
		"far": preload("res://audio/guns/wasp_far.wav"),
		"room": preload("res://audio/guns/wasp_room.wav"),
		"room_far": preload("res://audio/guns/wasp_room_far.wav"),
	},
	"mauler": {
		"mid": preload("res://audio/guns/mauler_mid.wav"),
		"far": preload("res://audio/guns/mauler_far.wav"),
		"room": preload("res://audio/guns/mauler_room.wav"),
		"room_far": preload("res://audio/guns/mauler_room_far.wav"),
	},
	"lancer": {
		"mid": preload("res://audio/guns/lancer_mid.wav"),
		"far": preload("res://audio/guns/lancer_far.wav"),
		"room": preload("res://audio/guns/lancer_room.wav"),
		"room_far": preload("res://audio/guns/lancer_room_far.wav"),
	},
}


## The reload sounds' pitch for gun `id` (1 = today's).
static func reload_pitch(id: String) -> float:
	return RELOAD_PITCH.get(id, 1.0)


## The shot sound of gun `id` ("" or a gun without its own: the original). The near sound: today's file.
static func shot(id: String) -> AudioStream:
	return SHOTS.get(id, DEFAULT_SHOT)


## The set of variants a gun uses (its base sound's name).
static func base_key(id: String) -> String:
	match id:
		"pistol":
			return "pistol"
		"smg":
			return "wasp"
		"shotgun":
			return "mauler"
		"sniper":
			return "lancer"
	return "default"


## The sound to play for gun `id` heard `distance` metres away, from `place` (0.30.0). A shot picks its variant when it
## is fired and keeps it: no crossfades, no popping. Up close outdoors it is today's file.
static func shot_for(id: String, distance: float, place: Place) -> AudioStream:
	var near := shot(id)
	var variants: Dictionary = VARIANTS.get(base_key(id), {})
	if place == Place.ROOM:
		return variants.get("room_far" if distance > BAND_NEAR else "room", near)
	if distance > BAND_FAR:
		return variants.get("far", near)
	if distance > BAND_NEAR:
		return variants.get("mid", near)
	return near
