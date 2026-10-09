# Design handoff (for the "designer" session)

The owner runs a separate Claude session, **designer**, for visual/UI design. This file catches it up. The main
session keeps doing gameplay, multiplayer and systems. Read `CLAUDE.md` first (the project rules apply to both).

## What Bloxov looks like today (0.8.3)
- **Game:** blocky voxel (16 px/m pixel textures) first-person extraction shooter, goofy but tense ("Loot weird stuff,
  get attached to it, try to make it out alive"). Web first (Godot 4.5, Compatibility renderer), mobile later.
  Tone and art rules: `docs/GAME_DESIGN.md`, `docs/ART_SPEC.md` (models are the owner's Blender work).
- **Raid HUD (0.8.3, "Stenciled Field Kit"):** a first pass from a design brief, built in code. The owner wants the
  designer to **redo it with more creativity and personality**. Current pieces:
  - `scripts/hud_style.gd` (`HudStyle`): palette consts, the Jersey 10 pixel font (`assets/fonts/`, OFL, loaded
    crisp in code since `.import` files aren't committed), `draw_plate()` (notched plates), `draw_icon()` (pixel
    icons from `#`/`.` rows: rifle, pistol, med cross, knife, grenade, flag), `draw_text()`, `style_label()`.
  - `scripts/health_hud.gd`: health (10 blocks that chip off when hit, low-health pulse) + stamina bar.
  - `scripts/ammo_hud.gd`: bullet pips + loaded/reserve, reloading, unarmed.
  - `scripts/hotbar_hud.gd`: 6 slots (layout rules below), key tabs, icons, held-gun rise, switch name.
  - `scripts/crosshair_hud.gd`: pixel crosshair + hit marker. `scripts/hud_plate.gd`: plate behind a label.
  - `scripts/hud.gd`: wires everything; timer, extract list, [F] prompt, extract status, damage vignette and
    direction indicator, pause menu (`scenes/main.tscn` HUD nodes).
- **Inventory screen (0.8.2):** `scripts/loot_ui.gd` (+ `grid_view.gd`, `item_tile.gd`, `equip_slot_view.gd`).
  Owner likes it much more than the HUD: **change it only lightly.** Layout: gear (PMC character view + equipment
  slots) | carried (pockets, secure pocket, backpack) | container or stash (+ trader column in the hideout).
  Item details show on hover (no placeholder text: owner removed "Hover an item for details").
- **Hideout:** `scripts/hideout.gd` (top bar, stash/loadout/trader via LootUI, ONLINE panel: name + Go online,
  party code, QUEUE, Start now; the ONLINE button shows "IN QUEUE (1/2)" / "RAID IN 21s").
- **Other screens:** pause menu (in `main.tscn` + `hud.gd`), end-of-raid screen (`scripts/raid_end_screen.gd`).

## Owner rules for the UI (decided, don't undo without asking)
- **Hit feedback stays subtle:** no kill marker, no flashy damage numbers by default (toggle exists). Kill sound stays.
- **Hotbar layout:** 1 and 2 = guns, 3 = Meds (all heals, uses the best fit, same as H), 4 and 5 = free for later
  (grenades...), 6 = Knife (V). Heals don't bind to keys one by one.
- **Health = a bar/blocks with the number on it.** No "Carrying $" on the raid HUD (only in the inventory).
- **Extract list** shows a few seconds at raid start and when O is pressed, then hides.
- **While the inventory is open** the HUD hides except the raid timer (the raid doesn't pause).
- Teammates' name tags are small; other players get none (PvP).
- No placeholder/instruction clutter on screen.
- Placeholder art until the vertical slice (M4); the owner makes models in Blender. Item icons will replace the text
  tiles later.

## Backlog items that are design work (see `docs/BACKLOG.md`)
- Redo the raid HUD (owner's main ask for the designer).
- Light polish of the inventory screen; item icons later; item descriptions (owner writes the text).
- Custom loading screen / boot splash (Bloxov logo instead of Godot's).
- Guns as separate models (owner, Blender) with a `GunSocket` on characters.
- Mobile: hold an item to see details; touch controls (later).

## How to work without breaking things
- **Versions:** 0.8 is the HUD & inventory phase (yours). The game is on **0.8.3**; your next update is 0.8.4, then
  0.8.5... (0.8.0-0.8.3 were first released as 0.7.12-0.7.15 and renumbered).
- Same rules as `CLAUDE.md`: version bump + CHANGELOG entry per change, tests before every push (gate the push on
  the test log), commits as `TavishHanda <tavishhanda@hotmail.com>`, **no Claude co-author trailer**.
- Look at it, don't guess: render real frames with `xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver
  opengl3 --resolution 1280x720 -s <script>` and save screenshots (check over bright sky, green ground, dark rooms).
- Two sessions push to `main`: **pull/rebase right before you start and before you push**, keep commits small, and
  stay in the UI files above unless the change needs more. If you touch shared scripts (`hud.gd`, `loot_ui.gd`,
  `hideout.gd`), say so in the commit message.
- `scripts/net.gd` is an autoload: don't make it depend on UI/player scripts (fresh imports in CI break).
- Extend `tests/smoke_test.gd` for new UI states (e.g. the hotbar test uses `HotbarHUD.slot_info()`).
