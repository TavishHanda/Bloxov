# Art Spec

How models get from Blender into Bloxov. Sizes below are what the game uses today; match them so new art
fits the existing collision, doors and gameplay. Items marked **DECIDE** are style calls for the owner,
best made while doing the first test asset (a crate).

## 1. Units and scale
- **1 Blender unit = 1 meter = 1 Godot unit.** Blender's default (Metric, Unit Scale 1.0) is correct.
- Apply all transforms before export (Object > Apply > All Transforms) so scale is 1.0.

### Reference sizes (meters, width × height × depth)
| Thing | Size | Notes |
|---|---|---|
| Player | 0.8 wide, 1.8 tall | Eyes at 1.6 (1.0 crouched). Capsule radius 0.4 |
| Scav | 0.8 × ~2.1 × 0.6 | Body to 1.35, head 1.4–1.95, helmet to ~2.1. Head hitbox is 0.6 × 0.7 × 0.6 at 1.71 |
| PMC | same as Scav | Same hitboxes and rig as the scav. For real players (multiplayer) only |
| Raider | same as Scav | The tougher AI faction (0.7.10 model): dark gear, red armband, heavy armor, masks |
| Doorway | 2.0 wide, full wall height | Gap in the front wall |
| Walls | 0.5 thick | |
| Buildings | 3.5–4.0 tall (bunker 2.5) | Gas station 10×8, grocery 12×10, police 10×10, bunker 8×8 |
| Crate (loot) | 1.1 × 0.5 × 0.6 | Hard transport case, long and low. Too low to be cover (by choice) |
| Locker | 0.75 × 1.9 × 0.55 | |
| Safe | 0.8 × 0.85 × 0.7 | |
| Bag / body loot | 0.6 × 0.35 × 0.45 | Lies on the ground |
| Extract pad | 4 × 4 | |
| Map | 80 × 80 | |
| First-person rifle | ~0.08 × 0.15 × 0.8 | Seen up close; scale it by eye in the game, not in Blender |

## 2. Orientation and origin
- **Origin (pivot) at the bottom-center** of the object, so it sits on the floor when placed at y = 0.
- **Front faces Blender's +Y** (look at it from Blender's Back view, Ctrl+Numpad 1). glTF export turns
  that into Godot's forward (−Z), which is the way scavs and doors "face" in code.
  **Verify this with the crate test**: a crate with a marked front should face the player at spawn.
- Z is up in Blender. Leave the exporter's "+Y Up" option on (the default).

## 3. Export
- Format: **glTF Binary (`.glb`)**, one file per model, into `assets/models/<category>/` (e.g. `assets/models/props/crate.glb`).
- Include: selected objects, Apply Modifiers on, materials on, animations only for animated models.
- Keep `.blend` source files in `art_source/` (Godot ignores it). Don't import `.blend` directly into Godot:
  it needs Blender installed, and CI doesn't have it.
- Name objects and materials clearly (`crate`, `crate_mat`); Godot keeps the names.

## 4. Textures
- **Texel density: 16 px/m** (chosen for the crate test; confirm once it's seen in-game), i.e. texture pixels per meter. It must be the same on every asset, or some things
  look crisp and others blurry. Options:
  - **16 px/m:** chunky and blocky (Minecraft/Unturned). A 1 m crate face = 16×16 pixels.
  - **32 px/m:** still pixel-art, more detail for small items and guns.
  Small handheld items (guns, loot) may use double density since they're seen up close.
- Texture sizes: powers of two (16, 32, 64, 128, 256). Keep most textures ≤ 256 px for the web build.
- PNG, sRGB. One texture per model where possible (use a small atlas instead of many materials).
- **In Godot, pixel textures need "Nearest" filtering** (material > Sampling > Filter: Nearest Mipmap)
  or they'll look blurry. We'll set this up once in the import settings during the crate test.

## 5. Look and color
- **Style: military / scavenged / post-collapse, not fantasy and not cartoony.** Think olive-drab paint,
  stenciled codes, metal latches, worn edges. Blocky (it's voxel), but grounded: the owner rejected both the wooden
  "dungeon crate" and a chunky, toy-like version. The crate is a military hard case with a spray-painted skull.
- **Characters and gear have creative freedom** (owner, 2026-10-10): military, but not strictly realistic.
  Character, uniform, armor and faction designs (NOVA, EXION, scavs, Raiders) can be stylized and game-like rather
  than copies of real kit. The grounded rule above is about props and the world's look.
- Factions must read at a glance: Scavs are mismatched civilians, PMCs wear tan/green kit, Raiders are dark with red.
- **Palette: 24 colors in `art_source/palette.gpl`** (chosen for the crate test; confirm once it's seen in-game).
  Paint only with those. The `.gpl` loads in Aseprite, Krita and GIMP; `make_crate.py` has the same list as hex codes.
  Groups: neutrals/metal (black to bone), wood (dark to pale), accents (rust, red, hazard yellow), world/military
  (sand, olives, grass), extract greens, sky blue. Add colors to the file, not ad hoc.
- Readability first: loot and enemies should stand out from the world. Current placeholder rules:
  scavs are olive/dark (military), loot containers are warm (wood/metal), extracts are bright green.
- Lighting is simple (one sun with shadows plus sky light, web renderer). Flat, matte materials work best.
  Avoid relying on shiny/metallic effects; keep roughness high.

## 6. Budgets (web performance)
| Asset | Triangles | Texture |
|---|---|---|
| Small prop (crate, item) | < 300 | 16–64 px |
| Large prop (locker, car) | < 1,000 | 64–128 px |
| Character (one outfit showing) | < 2,500 | 128–256 px |
| First-person gun | < 1,500 | 64–256 px |
| Building | < 3,000 | atlas 256 px |
Voxel/blocky art is naturally cheap; these limits are generous on purpose.

## 7. Collision
- Collision is **not** taken from the model. Each scene in Godot has simple box/capsule shapes matching the sizes above.
  If a model's size changes a lot, tell Claude so the collision gets updated.
- Characters need the head and body as **separate meshes or bones** so the head can be the headshot zone.

### Characters and outfits
Built by `art_source/scripts/make_character.py` (0.23: plain Python, no Blender; `python3 art_source/scripts/make_character.py
[scav|pmc|raider]`, writes `assets/models/characters/<name>.glb` and its atlas `art_source/textures/<name>.png`).
The old models' sizes (owner: "the same as before"), now on joints so they can kneel, lie prone and crawl
(`scripts/body_pose.gd` turns them). The game relies on these names:
- Joints (empties): `Hips` > `Spine` > `Neck` (head parts), `ArmL`/`ArmR` > `ElbowL`/`ElbowR` (forearm and glove),
  `Hips` > `LegL`/`LegR` > `KneeL`/`KneeR` (shin and boot). Limbs hang down their joint's -Y.
- `Gun` beside `Hips` with a `Muzzle` empty: `HeldGun` swaps in the real gun, BodyPose puts it in the hands.
- Outfit parts are named `Slot__option__Joint` (`Hat__ushanka__Neck`, `Top__tracksuit_blue__ArmL`); the parts of
  one option on different joints share the slot and option. Every option ships in the one `.glb`;
  `scripts/pixel_model.gd` shows one random option per slot and merges the parts showing into one skinned mesh.
  An empty named `Slot__none` makes "nothing" a choice (no hat, no vest). Adding an option = one line in the script.
- Check the poses with `xvfb-run -a godot --rendering-driver opengl3 -s tools/body_preview.gd -- out=/tmp/pose boxes side`.

## 8. Swapping a placeholder for a model
Done so far: **crate** (0.3.3), see `scenes/loot_crate.tscn`: the `.glb` is instanced as a `Model` child with
`scripts/pixel_model.gd` attached (forces nearest filtering + matte), and the collision box stays in the scene.
**Scav and Raider** (0.3.5; the AI PMC became the Raider in 0.6.15), `scenes/scav.tscn` and `scenes/raider.tscn`, same setup; the muzzle flash lives in the
scene and is moved onto the model's `Muzzle` at runtime.

1. Export the `.glb` to `assets/models/...` and push it (or tell Claude where it is).
2. Claude replaces the placeholder box meshes in the matching scene (e.g. `scenes/loot_crate.tscn`) with the model,
   keeps the collision and scripts, and checks it in a CI build.

## First test asset: the crate
Goal: prove the pipeline, not make a final crate.
1. Model a 1.1 × 0.5 × 0.6 case (started as a 1.0 × 0.75 × 0.7 crate), origin bottom-center, front facing +Y, with a mark on the front.
2. Texture it at your chosen texel density with your palette.
3. Export `crate.glb` to `assets/models/props/`.
4. We drop it in and check: right size next to the player, front faces the right way, texture crisp (not blurry),
   looks good in the browser build. Then lock in the DECIDE items above.

## Buildings (World art, 0.17)
Buildings keep their gray box for everything that matters to play (walls, floors, furniture: collision, shots, AI
paths), and a model draws them. In `tools/gen_old_bloxov.py`, wrap a building's boxes in
`with modeled("<name>", x, z):` and give furniture a `kind` (`box(..., kind="shelf")`): re-running writes
`art_source/buildings/<name>.json`. `art_source/scripts/make_building.py` builds the model from it (shared kit
textures for walls, floors, ceilings and concrete in `art_source/textures/kit/`, one decal atlas per building for its
signs) and exports `assets/models/buildings/<name>.glb`; it runs in Blender or plain Python. Re-run the generator
afterwards: once the `.glb` exists, the map hides those boxes and places the model. Windows stay open holes (shots go
through them), so broken glass is only shards in the frame. Anything that looks solid must have a box, so it collides.
First one: the town gas station.

### Loot containers (World art, 0.17)
Each map container has a `look` that fits its place (owner: lockers in the school, safes where they make sense, the rest
remodelled): `LOOT_LOOKS` in `tools/gen_old_bloxov.py` picks it from (place, loot kind), `scripts/loot_container.gd`
`LOOKS` gives its name and collision box, and `python3 art_source/scripts/make_loot.py` builds the models
(`assets/models/loot/<look>.glb`, front facing -z, decals in `art_source/textures/loot/decals.png`). The loot inside
still comes from the crate / locker / safe table, so the economy doesn't change.
