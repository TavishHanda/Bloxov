# Trader character models plan

Goal: the five hideout traders become actual characters standing in their stalls, not empty counters. They should be
recognisable from the spawn point by silhouette, look like they belong in a cave market, and reuse the existing
jointed-character rig so they can breathe, shift, turn and gesture without new animation technology.

This is part of the hideout-life pass (`docs/HIDEOUT_LIFE_PLAN.md`), after the Stash update (0.31.x). The steps below
are 0.32.1.

## What exists today

- `scripts/traders.gd`: the identities. **Ponta** (guns, "GUNSMITH"), **Medic** (meds; still a placeholder name),
  **Big Don** / "The Big Don" (supplies, "SUPPLIER"), **Supreme** (valuables, "SUPREME"), **Ming** (boxes, "MING").
  Each has stock, levels and quests; none has a body.
- `art_source/scripts/make_hideout.py`: five tin-roofed bays in a row on the west ledge, each with a stocked counter,
  steel racking, crates and a sign. `TRADERS = ("guns", "meds", "supplies", "valuables", "ming")`.
- `scripts/hideout_world.gd`: the `Level/Stations/<id>` markers open the right trader screen. There are no NPC nodes.
- `art_source/scripts/make_character.py`: the jointed rig and outfit system for Scav, PMC and Raider. Plain Python,
  no Blender; writes `assets/models/characters/<name>.glb` plus a 16 px/m atlas.
- `scripts/body_pose.gd`: poses the joints for standing, walking, crouching, prone, downed and dead.
- `scripts/pixel_model.gd`: crisp textures, outfit slots (`Slot__option`), and merging parts into fewer draw calls.

## Direction (decided 2026-11-06)

The owner picked **grounded, worn, slightly stylised**: military surplus and cave-market improvisation, not clean
uniforms and not fantasy. Each trader should read at 10 m by shape alone. No real brands or logos
(`docs/STORE_RULES.md`). The alternatives are kept below as history, not as open options.

Five **separate** models, one per trader, built by a shared `trader_body` helper in `make_character.py`. Separate
models are simpler than outfit slots here: each trader has a fixed look and different proportions, and nothing needs
to randomise or swap. They still use the same joint names, the same atlas size and the same texel density as the
raiders, so `BodyPose` and `PixelModel` work unchanged.

| Trader | Silhouette | Look |
| --- | --- | --- |
| **Ponta** (guns) | Lean, slightly stooped, angular | 50s gunsmith. Grey knit sweater under an olive work apron, fingerless gloves, safety glasses pushed up on the forehead, a cigarette behind one ear, a tool belt with a screwdriver and a bore brush. Rolled sleeves, burn scar on one forearm. |
| **Medic** | Upright, tidy, hands often in pockets | 30s. Off-white coat over olive scrubs, a stethoscope, a headlamp on a strap, a mask hanging at the neck, short hair, tired eyes. A pen and a small notebook in the chest pocket. |
| **Big Don** (supplies) | Wide, heavy, planted | 50s. Bald with a thick beard, a padded olive jacket with a fur collar, a gold chain, rings, a cigar, a heavy belt. Arms that don't quite hang straight. Warm, not menacing. |
| **Supreme** (valuables) | Tall, narrow, sharp | 40s. Long dark coat, a flat cap or ushanka, small sunglasses indoors, leather gloves, a gold watch, a cane or a folded umbrella. Stands very still; appraises you before he speaks. |
| **Ming** (boxes) | Compact, bright, restless | 20s. A colourful puffer jacket (red/teal, the one loud thing in the market), a cap or headphones round the neck, fingerless gloves, a box cutter on a lanyard, a grin. Leans on the counter. |

Sixth body: a **cat** asleep on the supplies crates (approved 2026-11-06). It is a character, not a prop: a small
jointed or two-part model with a breathing idle, built with the same helpers. It lives in the hideout-life step, not
in the five trader models.

Alternatives that were not picked:

- **Ex-military only:** all five in surplus gear, rank and trade shown by kit rather than costume. More grounded,
  less readable at a distance.
- **Market eccentrics:** push Supreme and Ming further into colour and jewellery; Ponta and the Medic stay drab.
  More fun, slightly less serious.
- **One shared body with outfit slots:** cheaper to build, but Big Don and Supreme lose their silhouettes. Not
  recommended for "actual character models".

## Technical plan

### 1. Models (`art_source/scripts/make_character.py`)

- Add `TRADER_LOOKS` (id -> proportions, skin, hair, clothing options) and `build_trader(b, look)`.
- Reuse `legs`, `tops`, `gloves`, `heads`, `hat_box`, `chest_rig` and the joint builder. Add only what a trader needs:
  apron, coat, fur collar, chain, glasses, headlamp, lanyard, cane, box cutter.
- Big Don gets a wider torso and a belly box; the Medic and Supreme get a slightly narrower one. Keep the joint
  positions and head height the same so `BodyPose` and the hitbox helpers stay valid.
- Add `ponta`, `medic`, `supplies`, `valuables`, `ming` to `BUILDERS`, writing
  `assets/models/characters/trader_<id>.glb` and `art_source/textures/trader_<id>.png`.
- Keep the `Gun` node out of trader models (they are not armed). `BodyPose.armed = false`.
- Budget: under 2,500 triangles per model and one 128-256 px atlas, per `docs/ART_SPEC.md`.

### 2. Scene and behaviour

- New `scenes/trader.tscn`: a `Node3D` with `Model` (the trader GLB, `PixelModel`, `randomize_outfit = false`), a
  `Name` marker for the greeting anchor, and an optional small `StaticBody3D` capsule so the player cannot walk
  through them if they get behind the counter. No health, no loot, no AI navigation.
- New `scripts/hideout_trader.gd`:
  - `BodyPose` with `armed = false`, `speed = 0`, and a small procedural idle on top of `update(delta)`:
    breathing (spine/chest a few millimetres), a slow weight shift, a head turn toward the player within ~4 m,
    and a rare gesture (a hand move, a shrug, a look at the shelf).
  - Keep it on the game clock, not wall time.
  - Optional `greet()`: one short line per trader when their screen opens, shown as a subtitle or in the screen's
    header. No dialogue tree and no voice files until the owner asks.
  - Skip all animation headless (`Reacts.wanted` or a simple `DisplayServer` check).
- `scripts/hideout_world.gd`: on `_ready`, read `Level/Traders`, instantiate one `trader.tscn` per marker, set its id
  and facing, and give it the walker for look-at. Keep the existing `Level/Stations` markers untouched; the trader
  stands behind the counter, the station stays in front of it.

### 3. Placement (`art_source/scripts/make_hideout.py`)

- In `bay()`, for a trader bay, add a marker at `F.P(depth - 1.5, 0, 0)` facing out (`-n`), just behind the counter
  and in front of the back racking. That is inside the existing collision-free stall, so no map collision changes.
- Export them as `Level/Traders/<id>` with a `yaw` meta, next to the existing `Level/Stations` markers.
- Keep the counter clutter clear of the body: the counter is at `depth - 0.5`, the trader at `depth - 1.5`.
- Do not move the station marker; the player still uses the counter from the front.

### 4. Polish

- A small nameplate or trade badge on the counter (already signed) is enough; no floating names by default.
- One prop per trader that says who they are: Ponta's cleaning rod, the Medic's clipboard, Don's ledger, Supreme's
  loupe, Ming's box cutter.
- A subtle idle sound per trader is optional (a cough, a page turn, a box rattle) and should be local and quiet.

## Steps

- [ ] **0.32.1a - Art direction sign-off.** Tone picked: grounded, worn, stylised (2026-11-06). Still open: the
      Medic's real name, which is a placeholder until dialogue is written.
- [ ] **0.32.1b - Pilot: Ponta and the Medic.** Build the shared `trader_body`, the two models, `trader.tscn`,
      `hideout_trader.gd`, and place them at their stalls. Play it. This is where proportion and scale get fixed.
- [ ] **0.32.1c - The other three, and the cat.** Big Don, Supreme, Ming, using the pilot's proportions and the same
      idle, plus the cat asleep on the supplies crates (approved 2026-11-06).
- [ ] **0.32.1d - Look-at and greetings.** Head turns, the rare gesture, one line per trader when their screen
      opens. Ask before adding voice.
- [ ] **0.32.1e - Polish and perf.** Merge parts, check draw calls and shadows, confirm headless and smoke tests are
      unaffected, ask the owner to walk the market.

## Acceptance

- From the spawn point, all five stalls read as staffed, and each trader is distinguishable by silhouette.
- Each trader breathes, shifts and turns to the player; nothing snaps or loops obviously.
- The models use the existing joints, `BodyPose` and `PixelModel`; no new animation system.
- The cat reads as asleep rather than dead, breathes slowly, and never blocks the counter or the player's path.
- A headless run builds none of the idle work, and the smoke tests still pass.
- No collision changes in the stalls, no new network traffic, no effect on stock, prices or quests.
- The owner is happy with the tone before the last three are modelled.
