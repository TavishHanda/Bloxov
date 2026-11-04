# Sound 2.0 (0.30.x): plan

Status: **steps 1, 2 and the hideout ambience shipped** (0.30.0 variants and selector, 0.30.1 occlusion/floor/behind,
0.30.2 a steady bunker room tone). Still to build: 0.30.3 (ambience ducking, routing); 0.30.4 (hi-fi) is optional.
This is the last unbuilt M4 (vertical slice) item.
Written 2026-11-04 for a dev session that has not seen the 0.20 Sound update being built; everything it needs is in
here and in the files it names. The owner's brief is the "Sound 2.0" entry in `docs/ROADMAP.md`; this file turns it
into work.

Read first: `CLAUDE.md` (rules), `docs/DEV_HANDOFF.md` §3 code map and §6 gotchas, `docs/CLAUDE_HANDOFF.md` (how the
owner works). Nothing here changes gameplay: it is all sound.

---

## 1. The owner's brief

From `docs/ROADMAP.md` (owner, 2026-10-26), verbatim:

> shooter-grade hearing, built only from today's sounds (they stay as they are; no outside recordings). Each gun gets
> near/mid/far and indoor versions made from its own shot; "through the floor" versions for above/below you, slightly
> duller from behind; sound comes through open doors and broken windows instead of only muffled through walls;
> footsteps and enemy shots cut through while ambience dips in a fight. Echo and muffle are baked into the files, since
> the web skips bus effects. Footstep range and your own gun's loudness stay as today (owner).

Hard constraints that come with that:

- **Only add sounds.** Today's files must not be replaced, retuned or regenerated differently. (The same rule built
  0.20: "only ADDING new sounds ... keep today's sounds, at most small tweaks, never replace them".)
- **No outside recordings.** Every new file is made from the files already in `audio/`.
- **The web is a first-class target** and the browser skips bus effects (measured in 0.20.8, see `CHANGELOG.md`), so
  reverb, muffle and distance colour have to live **in the WAV files**, not in runtime filters.
- **Footstep range and your own gun's loudness stay as today.** Variants change *what it sounds like*, not how far it
  carries or how loud it is.
- Every change follows `docs/STORE_RULES.md` (no real brands; nothing that breaks the age rating; audio pauses with the
  app in the background — already handled by the engine).

## 2. What exists today (0.29.14)

### Files

| Thing | File | Notes |
|---|---|---|
| Shot streams | `scripts/gun_sounds.gd` | Hound (ak) and Stinger (pistol) share `audio/shot.wav`; Wasp/Mauler/Lancer have `shot_wasp/mauler/lancer.wav` |
| 3D playback + cap | `scripts/effects.gd` `sound()` / `sound_at()` | `MAX_SOUNDS = 40`, far sounds skipped past 25 m when busy, `PANNING = 2.0` |
| Occlusion, distance, snap | `scripts/hearing.gd` | one ray from the ear to the source, mask 1; `MUFFLED_CUTOFF = 900`, `MUFFLED_DB = -5`; far boom from 45 m, full at 90; snap < 3 m |
| Your own shot | `scripts/gun.gd` (~`shoot`) | **2D** `Effects.sound(...)`, no distance and no muffle |
| AI shot | `scripts/scav_fight.gd` `net_fired()` | `Effects.sound_at(..., shot_unit_size)` + `Hearing.gunshot()` |
| Other players' shots | `scripts/net_raid.gd` (~line 363) | same pattern, `-6 dB` world / `-12 dB` boom if suppressed |
| AI shot stats | `scripts/scav_base.gd` | `shot_volume_db = -3.0`, `shot_unit_size = 6.0` |
| Footsteps | `scripts/surfaces.gd` `step()` | surface lookup in `BoxMap`; own steps 2D, others 3D with a range |
| Background | `scripts/ambience.gd` | wind/woods/room/creek/waterfall beds, war rumbles, the hideout's bunker beds |
| Buses | `default_bus_layout.tres` | Master -> World (reverb, enabled only indoors), Voices, Ambience, UI |
| Mix settings | `scripts/game_settings.gd` | **owns the bus volumes**: never write a bus volume for ducking |
| Generator | `tools/make_sounds.py` | 888 lines, `RATE = 22050`, mono 16-bit, `write()` normalises each file's peak to 0.9 |

Weapon ids: `ak`, `pistol`, `smg`, `shotgun`, `sniper`. They map to four base shot sounds (`shot.wav` for ak+pistol).

### Facts that shape the design

- Every file is **22 050 Hz, mono, 16-bit**; QOA-compressed at import. `*.import` is gitignored (`.gitignore`), so
  **per-file import settings are not committed**; anything that must be set per file is set in code (see
  `Ambience.looped()` for the pattern).
- The smoke test has an `_section_sound()` and runs 81 sections; **tests run faster than real time** (documented
  gotcha, and it is what made the 0.29.14 pendulum check flaky). Test sound logic by calling functions and by counting
  `AudioStreamPlayer`s, not by listening or by waiting on the wall clock.
- Buses must never be added at runtime: Godot's web audio puts a late bus in the wrong place and loses Master
  (0.20.8). Use the four buses in `default_bus_layout.tres` or `Master`.
- `Hearing.indoors` is a static flag the local player updates every 0.3 s by casting up for a roof
  (`Hearing.listen`). It is per-client, which is all a listener needs.
- On the web, per-player attenuation filters and bus effects are lighter or missing (`CHANGELOG.md` 0.20.8 note). Treat
  everything you can hear as needing a baked version if it must match desktop.
- Existing levels to preserve: player's own shot `shot_db` default `-4` (Wasp `-6`, Mauler `-1`, Lancer `-1`);
  scav shots `-3` at `unit_size 6`; far boom from 45 m; snap `-13` at 3 m.

### Two routing bugs found while reading (fix as part of step 3)

`scripts/movers.gd` (clock ticks) and `scripts/hideout_doors.gd` ask for a bus called `&"SFX"` that does not exist in
`default_bus_layout.tres`, so they silently fall back to `Master`: they ignore the MIX settings and the indoor echo.
They should use `World` (the same bus as every other world sound).

## 3. The design

### 3.1 Variants, all made from the existing file

Generate one set per **base sound**. There are five now (the pistol got its own in 0.30.0; before that it shared the
Hound's `shot.wav`). Seven variants per base, one of which is the base itself, so 6 new + 1 existing = 7 -> **30 new
files** when all are built, about 0.5-1.1 s each (roughly 0.8 MB raw, a few hundred KB in the web build). Step 1
(0.30.0) built the four distance/room ones (20 files); step 2 (0.30.1) added `floor` and `behind` (10 more).

| Variant | Made by | Heard when |
|---|---|---|
| `near` | the existing file, untouched | <= 20 m, clear line, outdoors |
| `mid` | low-pass ~3 kHz + a short 40 ms tail | 20-50 m |
| `far` | low-pass ~900 Hz + a 120 ms low boom tail, longer decay | > 50 m |
| `room` | the base + a small-room tail (RT60 ~0.5 s, wet ~0.18) and a 12 ms early reflection | indoors, <= 20 m |
| `room_far` | `far` + the same room tail | indoors, > 20 m |
| `floor` | low-pass ~400 Hz + a 45-60 Hz thump, no crack, short tail | the blocker is a floor/ceiling |
| `behind` | high shelf about -4 dB above 4 kHz, -1.5 dB overall | the shooter is behind the listener |

**File names** live in `audio/guns/`: `default_near.wav` is *not* made (use `audio/shot.wav`); the new ones are
`default_mid.wav`, `default_far.wav`, `default_room.wav`, `default_room_far.wav`, `default_floor.wav`,
`default_behind.wav`, and the same six for `pistol`, `wasp`, `mauler`, `lancer`. `GunSounds` keeps today's table as
the `near` versions, so the game up close sounds exactly as it does now.

A wall, a shut door or a whole pane has no file of its own: it plays `far` (or `room_far` indoors, which keeps the
room tail) plus today's -5 dB. An opening plays the normal distance variant, 3 dB down and 20 ms late.

### 3.2 Making them (new tool, existing generator untouched)

Add `tools/make_sound_variants.py`. It **reads the WAVs already in `audio/`** and writes `audio/guns/`. It does not
touch `tools/make_sounds.py`, so today's files cannot drift.

Rules for the script (these are the traps):

- Reuse the same output format: 22 050 Hz, mono, 16-bit. Read with `wave`, no external libraries (the repo has none).
- **Do not peak-normalise the variants.** `make_sounds.py`'s `write()` scales every file to 0.9 peak; doing that again
  would make a far shot as loud as a near one at the source and the distance attenuation would then over-quieten it.
  Match **RMS** to the base instead (within +/-0.5 dB), except `floor` (-2 dB) and `behind` (-1.5 dB).
- Soft-clip (`tanh`) before scaling so the added tails cannot wrap around.
- `room`/`room_far` need a small reverb: three comb filters (~29.7, 37.1, 41.1 ms) into two all-passes (~5.0, 1.7 ms),
  wet ~0.18, then a 0.5 s fade so the file ends in silence.
- Keep every file short: <= 1.2 s even for `room_far` (the Lancer's base is 0.6 s, the tail adds ~0.4 s).
- The script is rerunnable: it overwrites only `audio/guns/`.
- Add a `--check` mode that prints the RMS of each variant against its base, so a reviewer can see the level policy
  was followed without listening.

### 3.3 Choosing a variant

One pure function does the thinking, so it is testable without audio hardware:

```gdscript
# scripts/gun_sounds.gd
enum Place { OUTDOOR, ROOM }
enum Block { NONE, OPENING, WALL, FLOOR, DOOR, GLASS }
static func shot_for(id: String, distance: float, place: Place, block: Block, behind: bool) -> AudioStream
```

Order of precedence: `floor` > `room(_far)` > `behind` > distance band. `behind` only applies outdoors and up close
(it is the "slightly duller" case; indoors the room tail already tells you it is behind you). `distance` is the
listener-to-muzzle distance; bands are **20 m** and **50 m**, picked to sit either side of the existing far boom at
45 m.

The stream is chosen **once, when the shot is fired**; a shot never changes variant mid-flight, so no crossfades are
needed and there is no popping.

Call sites (all already call `GunSounds.shot(...)`):

- `scripts/gun.gd` (your own shot): distance 0, `place` from `Hearing.indoors`, no block, not behind.
- `scripts/scav_fight.gd` `net_fired()`: real distance from the local camera, `place` from `Hearing.indoors`,
  `block`/`behind` from the new occlusion call (below).
- `scripts/net_raid.gd` (other players' shots): the same.
- `scripts/gun.gd` also uses `shot_db`: **do not change it**. The variants are level-matched, so the existing
  distance/volume maths still decides loudness.

### 3.4 Occlusion: know *what* is in the way

Today `Hearing.blocked()` returns one bool from one ray with **mask 1**, which is map geometry only. That means a shut
door and a whole window pane are acoustically invisible, and a wall and a floor sound the same (muffled). Change it to:

```gdscript
# scripts/hearing.gd
enum Block { NONE, OPENING, WALL, FLOOR, DOOR, GLASS }
static func block_of(camera: Camera3D, pos: Vector3) -> int
static func blocked(camera: Camera3D, pos: Vector3) -> bool:   # kept: other callers use it
	var block := block_of(camera, pos)
	return block != Block.NONE and block != Block.OPENING   # an opening is not muffled again
```

- Cast the direct ray with a mask that adds doors and panes (`1 | 16 | 256`: world layer, `Door.LAYER = 16`,
  `BoxMap.WINDOW_LAYER = 256`; the earlier draft's `512` was the furniture layer, which does not stop sound);
  classify from the hit:
  - no hit -> `NONE`
  - hit normal mostly vertical (`absf(normal.y) >= 0.7`) -> `FLOOR` (a floor or ceiling)
  - hit a `Door` -> `DOOR` (only shut leaves collide, so an open door is already `NONE`)
  - hit a pane body -> `GLASS` (a broken pane's shape is disabled, so it is already `NONE`)
  - anything else -> `WALL`
- If the direct ray is blocked, cast a **five-ray fan** from the ear toward the source (centre, +/-10 deg side,
  +/-8 deg up/down) and use the same mask. Any clear ray -> `OPENING`: sound comes round the doorway or the broken
  window, so play the distance variant (not `floor`), 3 dB down, 20 ms later. This is the "through open doors and
  broken windows" line in the brief.
- Cost: five extra short rays, only for a gunshot that is already blocked. A 600 rpm fight adds ~50 rays a second;
  nothing. Do not run it every frame, and not on the server (no listener).
- Keep the old 0.6 m trim at the source end: a shooter leaning on a wall should not count that wall as blocking.

Baked variants mean the runtime `attenuation_filter_*` muffle in `Effects.sound_at()` should be **off** for gunshots
once this ships (otherwise desktop gets double muffling that the web cannot). Put it behind a constant
(`Hearing.RUNTIME_MUFFLE := false`) so the owner can A/B one line, and keep the same treatment for footsteps/impacts
until someone checks them on a phone.

### 3.5 Ambience dips in a fight

Do not write bus volumes; `game_settings.gd` owns them. Scale the ambience players instead:

- `Hearing` keeps a static `fight_left` timer (real seconds, decremented by delta). Any gunshot the player can hear
  within 50 m sets it to 4 s; the existing call sites already know the distance.
- `scripts/ambience.gd` multiplies every bed's target by `db_to_linear(duck_db)`, where `duck_db` ramps to
  **-5 dB** over 0.25 s while `fight_left > 0` and back afterwards. Rumbles and one-off bits keep their own levels.
- Enemy footsteps within 8 m (the `Surfaces.step(..., at_body = false)` path) add a **-2.5 dB, 0.4 s** dip on top, so
  someone walking up behind you is audible over the wind.
- This is delta-driven, so it is deterministic in tests and pauses with the menu.

### 3.6 The optional hi-fi remake (phase 4, owner decides)

Today everything is 22 050 Hz mono. A full-quality remake means generating the owner-picked sounds at 44 100 Hz and
adding an A/B switch. It is deliberately **last and optional**: the owner said "only for the sounds the owner picks
after comparing old and new". Approach: a `--rate 44100` mode in `make_sounds.py` for a named subset into
`audio/hifi/`, played instead of the base when `GameSettings` has the option on. Cost: double the file size for those
sounds and a mix-review session. Do not start it before step 3 has shipped.

## 4. Code plan, in order

Each step is independently shippable, gets its own version, `CHANGELOG.md` line and owner listen-check. Nothing here
touches gameplay, so no proposal is needed per step; the owner has already asked for the feature.

**0.30.0 - the variant files and the selector (shipped)**
1. `tools/make_sound_variants.py` + the 20 distance/room files in `audio/guns/` (4 per base × 5 bases), and
   `audio/shot_pistol.wav` from `main_pistol()` in `tools/make_sounds.py`.
2. `scripts/gun_sounds.gd`: the base table (today's streams) + `VARIANTS`, `Place`, `shot_for()`.
3. Wired `gun.gd`, `scav_fight.gd`, `net_raid.gd` to `shot_for()`; distance/volume maths unchanged. `Block` and the
   `floor`/`behind` variants were left to 0.30.1 so no file is unused.
4. Smoke test: every gun × every band × both places returns a real stream; the stream changes at 20 m and 50 m;
   indoors picks a `room` stream; up close it is still today's file; the Stinger no longer shares the Hound's shot.

**0.30.1 - occlusion, floor, behind (the hearing part) (shipped)**
5. `Hearing.block_of()` with the wider mask (`1 | 16 | 256`), classification, the five-ray fan and `Hearing.behind()`;
   `blocked()` stays as a wrapper and treats an OPENING as clear.
6. Passed `block`/`behind` from the three shot call sites; `Effects.shot_at()` keeps the runtime muffle off for gunshots
   (`Hearing.RUNTIME_MUFFLE = false`) and starts an OPENING shot 20 ms late. Wall/door/whole pane use the `far`
   variant (or `room_far` indoors) plus today's -5 dB; there is no separate wall file, which is why the plan's
   "baked wall variant" is the `far` half of `room_far`.
7. Tests: a wall/floor slab/2 m gap/shut door/whole vs broken pane, each asserted through `block_of()` using the
   same `BoxMap` + `Door` nodes the existing `_section_sound()` already builds; the fan finds the gap; `shot_for()`
   picks floor/far/near/behind and the room precedence; every gun has all six variants. The box checks use a fixed
   probe camera high above the map (the player drifts, and the fan is sensitive to that); the older lost-close AI
   check now builds its wall between the actual player and scav positions, so neither flakes.

**0.30.2 - the hideout's bunker ambience (shipped)**
8. Remade the three beds in `tools/make_sounds.py`: `bunker_air` is a steady deep room rumble with no surf-like
   swell, `bunker_vent` is a steady low fan rumble with no hiss or breathing, and `bunker_hum` is a steady 50 Hz
   electrical hum with no chug. Same 22 kHz mono format; the beds keep their -31/-35/-34 dB levels.
9. `scripts/ambience.gd`: fixed bed levels and pitches (no random drift), and removed every one-off (drips, ticks,
   creaks, clanks, vent breaths, dust and the occasional war rumble). The three different lengths still keep the loop
   from lining up.
10. Deleted the nine unused one-off WAVs and their generator functions. The smoke test now checks that `_bunker()`
    adds no children (no random noises) and that all three beds are still playing and quiet.

**0.30.3 - ambience ducking and routing**
11. `Hearing.fight_left`, `Hearing.heard_shot(world, pos)`; call it from the three shot paths.
12. `Ambience` duck ramp; footstep dip.
13. Route `movers.gd` and `hideout_doors.gd` from the nonexistent `SFX` bus to `World`.
14. Tests: a near shot sets the duck, a far one does not; the ambience target is lower while ducked and back after
    ~4 s of simulated frames; clock ticks and hideout doors are on the World bus; still no extra buses.

**0.30.4 - optional hi-fi pass**, only if the owner asks after listening.

## 5. Verification

Run these from the repo root (the local Godot binary is in `docs/DEV_HANDOFF.md`; CI runs the same jobs):

1. `godot --headless --import` - must be clean; the new WAVs must import before anything preloads them.
2. `godot --headless --fixed-fps 60 -s tests/smoke_test.gd` - `SMOKE TEST: PASSED`, no `SCRIPT ERROR`. Run it **three
   times**: this suite has produced real-time flakes before.
3. `godot --headless -s tools/headless_hideout.gd` (the CI hideout run) - unchanged.
4. Web export + Chromium, then listen on the real map:
   - each gun at ~5 m, ~30 m, ~80 m;
   - indoors, and through a wall, an open door, a broken pane, a whole pane;
   - one shooter above you and one below;
   - a shooter behind you;
   - a suppressed gun;
   - a close firefight: the ambience should step back and come up again;
   - phone-sized window: same, and no crackle from the 40-sound cap.
5. Compare the web build's size before/after (`web/` output). If it grew more than ~1 MB, drop `behind` (5 files)
   first, then `room_far` (fall back to `room` + distance band).
6. Owner listen-check after each step; the numbers are guesses until they hear them.

Optional but useful: a `tools/sound_ab.tscn` listening room (keys 1-7 play one gun's variants, labelled on screen) so
the owner can judge without playing a raid. It is a tool scene like `tools/render_*.gd`, not shipped in the game.

## 6. Pitfalls this will hit (all seen before)

- **`.import` files are not in git.** Loop points, compression and so on are defaults at import; do not rely on
  per-file settings. (Audio loops are already set in code: `Ambience.looped()`.)
- **Do not peak-normalise variants.** See 3.2.
- **Do not add buses** at runtime (web loses Master).
- **Do not write bus volumes** for ducking (`game_settings.gd` owns them).
- **Tests are not real time.** Drive countdowns with `delta`/`physics_frame`, never `Time.get_ticks_msec()`; the
  0.29.14 pendulum fix exists because of exactly this.
- **Autoloads don't compile in `-s` tests** (`Network.main`, never `Net.`).
- **`net.gd` must not preload player/gun scripts**, or a fresh import fails in CI; the new preloads belong in
  `gun_sounds.gd` (already imported before it is used).
- Keep all new audio inside `audio/`; the CI Docker image imports the project from scratch.
- The repo is public: no machine paths in this file, commit messages or code comments.

## 7. Decisions only the owner can make

**Answered 2026-11-04:** (1) the Stinger gets its own shot — built in 0.30.0; (3) no baked travel delay; (4) match
desktop and web (baked only); (5) duck at -5 dB. Still open: (2) and (6).

1. ~~**The Stinger's own shot.**~~ **Yes** — done in 0.30.0 (`shot_pistol.wav` + its variants).
2. **How muffled is "through a wall"?** The wall uses the `far` variant (900 Hz cut; `room_far` indoors) plus
   `GunSounds.BLOCKED_DB` (-5 dB). It can be anything from "clearly quieter and distant" to "almost silent": listen
   after 0.30.1 and say if the -5 dB or the 900 Hz cut should move.
3. ~~**Travel delay.**~~ **No baked delay** — every variant starts with the shot, so the tracer and the impact stay in
   sync.
4. ~~**Desktop bus reverb.**~~ **Match** — baked room tails only; the web and desktop hear the same thing.
5. ~~**Ducking strength.**~~ **-5 dB**, as planned; tune by ear after 0.30.3.
6. **Hi-fi pass.** After the variants, do you want the 44.1 kHz remakes, and for which sounds?
