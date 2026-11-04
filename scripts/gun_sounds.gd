class_name GunSounds
extends RefCounted
## Each gun's shot and working sounds (0.15.12, owner: "make sounds for the new guns ... keep any remaining sounds").
## The Hound keeps the original shot.wav (pitched by its shot_pitch); the Stinger, Wasp, Mauler and Lancer have their
## own (tools/make_sounds.py). Used by the player's gun and by the AI, so a scav with a Mauler sounds like one.
##
## Sound 2.0 (0.30.0/0.30.1): the same shot at distance, indoors, through a floor and from behind, made from the gun's
## own file by tools/make_sound_variants.py. The near sound is today's file, untouched; the other variants are
## RMS-matched to it (floor -2 dB, behind -1.5 dB), so the existing distance/volume maths still decides loudness and
## nothing sounds quieter just for being a variant.

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
## Through a wall, a shut door or a whole pane: today's -5 dB (Hearing.MUFFLED_DB) on top of the far variant's 900 Hz
## cut. A shot through an opening is only 3 dB down and arrives 20 ms late (it came round the doorway).
const OPENING_DB := -3.0
const BLOCKED_DB := Hearing.MUFFLED_DB
const OPENING_DELAY := 0.02

## One set per base sound: ak uses "default" (the original shot.wav), the pistol its own since 0.30.0.
const VARIANTS := {
	"default": {
		"mid": preload("res://audio/guns/default_mid.wav"),
		"far": preload("res://audio/guns/default_far.wav"),
		"room": preload("res://audio/guns/default_room.wav"),
		"room_far": preload("res://audio/guns/default_room_far.wav"),
		"floor": preload("res://audio/guns/default_floor.wav"),
		"behind": preload("res://audio/guns/default_behind.wav"),
	},
	"pistol": {
		"mid": preload("res://audio/guns/pistol_mid.wav"),
		"far": preload("res://audio/guns/pistol_far.wav"),
		"room": preload("res://audio/guns/pistol_room.wav"),
		"room_far": preload("res://audio/guns/pistol_room_far.wav"),
		"floor": preload("res://audio/guns/pistol_floor.wav"),
		"behind": preload("res://audio/guns/pistol_behind.wav"),
	},
	"wasp": {
		"mid": preload("res://audio/guns/wasp_mid.wav"),
		"far": preload("res://audio/guns/wasp_far.wav"),
		"room": preload("res://audio/guns/wasp_room.wav"),
		"room_far": preload("res://audio/guns/wasp_room_far.wav"),
		"floor": preload("res://audio/guns/wasp_floor.wav"),
		"behind": preload("res://audio/guns/wasp_behind.wav"),
	},
	"mauler": {
		"mid": preload("res://audio/guns/mauler_mid.wav"),
		"far": preload("res://audio/guns/mauler_far.wav"),
		"room": preload("res://audio/guns/mauler_room.wav"),
		"room_far": preload("res://audio/guns/mauler_room_far.wav"),
		"floor": preload("res://audio/guns/mauler_floor.wav"),
		"behind": preload("res://audio/guns/mauler_behind.wav"),
	},
	"lancer": {
		"mid": preload("res://audio/guns/lancer_mid.wav"),
		"far": preload("res://audio/guns/lancer_far.wav"),
		"room": preload("res://audio/guns/lancer_room.wav"),
		"room_far": preload("res://audio/guns/lancer_room_far.wav"),
		"floor": preload("res://audio/guns/lancer_floor.wav"),
		"behind": preload("res://audio/guns/lancer_behind.wav"),
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


## The sound to play for gun `id` heard `distance` metres away, from `place`, through `block` (0.30.0/0.30.1). A shot
## picks its variant when it is fired and keeps it: no crossfades, no popping. Up close outdoors it is today's file.
## Precedence: floor > wall/door/whole pane > room > behind > distance band.
static func shot_for(id: String, distance: float, place: Place, block: int, behind: bool) -> AudioStream:
	var near := shot(id)
	var variants: Dictionary = VARIANTS.get(base_key(id), {})
	if block == Hearing.Block.FLOOR:
		return variants.get("floor", near)
	if block == Hearing.Block.WALL or block == Hearing.Block.DOOR or block == Hearing.Block.GLASS:
		# Indoors the wall's 900 Hz cut is the far half of room_far, so the room tail is kept.
		return variants.get("room_far" if place == Place.ROOM else "far", near)
	if place == Place.ROOM:
		return variants.get("room_far" if distance > BAND_NEAR else "room", near)
	if behind and block == Hearing.Block.NONE and distance <= BAND_NEAR:
		return variants.get("behind", near)
	if distance > BAND_FAR:
		return variants.get("far", near)
	if distance > BAND_NEAR:
		return variants.get("mid", near)
	return near


## How much quieter `block` makes the shot on top of its baked file (0.30.1): the floor and behind files already carry
## their own level, a wall/door/whole pane keeps today's -5 dB, and an opening is 3 dB down.
static func block_db(block: int) -> float:
	match block:
		Hearing.Block.OPENING:
			return OPENING_DB
		Hearing.Block.WALL, Hearing.Block.DOOR, Hearing.Block.GLASS:
			return BLOCKED_DB
	return 0.0


## How late a shot through `block` starts (0.30.1): an opening is a beat behind, as if it came round the doorway.
static func block_delay(block: int) -> float:
	return OPENING_DELAY if block == Hearing.Block.OPENING else 0.0
