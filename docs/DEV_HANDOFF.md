# Developer handoff: everything the next Bloxov dev needs

Written by the previous dev session (0.5 → 0.9.1) for the next one. Read this once, fully, then `CLAUDE.md` (the
standing rules) and you're caught up. Where this file and the code disagree, the code wins: fix this file.

## 1. The owner and how to work with them
- **Tavish** owns the game and makes the calls. They play every build, often with friends, and report by
  screenshot. Short messages, casual tone; reply the same way: plain words, short, no jargon walls.
- **They decide gameplay.** Any change to how the game plays (AI, numbers, rules, controls, what's on screen) is
  *proposed with a recommendation*, not shipped. Bug fixes that restore intended behavior are fine. Give options
  as a short list with **"My pick: …"** and why; ask several questions at once, numbered, so they can answer
  "1. yes 2. no 3. …".
- **Lead every update report with its version and a short name**: "**0.9.1: Meds slot shows what it'll use**",
  then 3-6 bullets of what changed in player terms, then what's next / what you need from them.
- They like seeing proof: render a screenshot (xvfb, see §4) for anything visual and show it.
- They hate: placeholder/instruction clutter on screen, generic-looking UI, being asked things the code can answer,
  waiting without knowing what's happening (send a one-line status during long work).
- They run a separate **designer** session for UI/visual work (`docs/DESIGN_HANDOFF.md`). Phase 0.8 (HUD &
  inventory) was theirs and is closed. You may touch UI files, but follow the UI rules in that doc (HudStyle,
  pixel font sizes 20/30/40/50, `Effects.WORLD_LABELS` instead of Label3D, `LootUI.style_button()`), and say so
  in the commit message when you touch shared UI scripts. Pull before you start and before every push.

## 2. Where things stand (0.10.3, 2026-10-10)
- **Live:** https://tavishhanda.github.io/Bloxov/ (version at `/version.txt`) + game server on Heroku
  `wss://bloxov-server-0f9c9a343ceb.herokuapp.com` (both deploy from `main` via CI; see §5).
- **Phases:** 0.5 guns · 0.6 scavs · 0.7 multiplayer · 0.8 HUD & inventory (designer) · 0.9 raid flow (paused at
  0.9.5) · 0.10 Map & Spawn (Bloxov Battlegrounds gray box, first called Old Bloxov, player spawns, per-squad extracts) · 0.11 Scorched Earth (code cleanup + war-torn map; closed). Next: Scavs 2.0.
- **Done:** solo raids (hideout → raid → extract/die → hideout, stash/trader/profile in the browser), guns
  (ADS, recoil, spread, TTK, knife), smart scavs + tougher Raiders (senses, navmesh paths, patrols, cover, healing,
  duos, spawn budget), online play (parties, queue 2-6 players, several raids per server, server-checked shots with
  lag compensation, server-run AI with puppets, shared loot + lootable bodies), the "Ammo Can" HUD and inventory,
  downed/revive/spectate and per-player extract (0.9), the first real map with the M map (0.10).
- **Next:** see `docs/ROADMAP.md` ("Up next"): a playtest on the big map, then Scavs 2.0, then the Items update.
- Hotbar now: 1-2 guns, 3 meds, 4 one bindable slot (grenades later), V knife (`Inventory.MEDS_KEY/KNIFE_KEY/
  BINDABLE_KEYS`, `HOTBAR_SIZE = 3`).

## 3. Code map (scripts/)
- **Player side:** `player.gd` (movement, stamina, lean, crouch, heal, hotbar keys; `proxy` mode = server copy),
  `gun.gd` (shots, ADS, recoil; online it also sends every shot to the server), `knife.gd`, `health.gd`,
  `inventory.gd` + `grid_inventory.gd` + `item_stack.gd` (grid inventory; `to_data/load_data` for the network),
  `item_db.gd` (all items, loot tables; regenerate `docs/ITEMS.md` with `tools/gen_item_list.py` after edits),
  `profile.gd` (static save in `user://profile.json`), `interactor.gd`, `loot_container.gd`, `extract_zone.gd`.
- **Raid:** `raid.gd` (clock, extracts, end + profile save), `enemy_spawner.gd`, `nav_baker.gd` (runtime navmesh),
  `raid_map.gd` + `box_map.gd` (0.10.0: the real map is swapped into main.tscn; see `docs/MAP_PLAN.md`),
  `scav.gd` (the whole AI; `puppet` mode for online copies; Raiders are `scenes/raider.tscn` = same script,
  different exports; fights go through one decision layer since 0.12.29: `_fight` picks one `Tactic` in `_decide` and
  keeps it until `_should_rethink`; add new fight behavior as a tactic there, not as its own per-frame check),
  `ai_nav.gd` (navigation queries for the AI, safe before the map is ready). After AI movement changes also run
  the slow real-map check `tests/ai_sideways_check.gd` (must print `SIDEWAYS CHECK: PASSED`).
- **UI:** `hud.gd` + widgets (`health_hud`, `ammo_hud`, `hotbar_hud`, `crosshair_hud`, `timer_hud`, `prompt_hud`,
  `extract_hud`, `map_hud` (M map, 0.10.2), `damage_arrow_hud`, `world_labels_hud`), `hud_style.gd` (palette/fonts/plates/icons),
  `loot_ui.gd` (inventory screen, also used by the hideout), `hideout.gd` (hideout + ONLINE panel),
  `raid_end_screen.gd`, `game_settings.gd`.
- **Online:** `net.gd` (`Net` autoload, used as `Network.main`; client + server RPCs), `matchmaker.gd` (parties,
  queue, raids; pure logic), `raid_world.gd` (one SubViewport world per server raid: map, AI, proxies, shot checks,
  shared containers), `hitbox.gd` (shared player hitbox math + state flags), `net_raid.gd` (client side of a raid:
  remote players, enemy puppets, shared loot), `remote_player.gd`, `raid_scope.gd` (per-raid group lookups).
- **Online architecture in one breath:** browsers can't host, so a headless Godot server (`--server`) runs on
  Heroku. Clients send their state 20/s + shots/knife/loot actions; the server relays states, decides hits against
  its own map copy (rewound to the shooter's view time), runs scavs against proxy bodies and forwards their hits,
  owns container contents (one looter at a time). Each player's game still owns its own health/inventory/stash
  (trusted; fine with friends; accounts + server-side stash are planned before strangers play PvP).

## 4. How to work (the loop that kept quality high)
1. `git pull` (the designer session also pushes). Read the code you'll touch; reuse its idioms and comment style
   (`##` doc comments explaining *why*, owner decisions tagged like "(owner, 0.9.0)").
2. Propose gameplay changes first; build after the owner says yes.
3. Build in small, shippable steps, one version each: bump `config/version`, add a CHANGELOG entry written for the
   owner (player terms), update the relevant plan doc (`docs/*_PLAN.md`) and `CLAUDE.md` if a rule changed.
4. **Test before every push**, gated: `godot --headless --import` (also from a *fresh clone* when you touch
   autoloads/preloads), `godot --headless --fixed-fps 60 -s tests/smoke_test.gd > log`, then push only if
   `grep -q "SMOKE TEST: PASSED" log && ! (grep -E "SCRIPT ERROR|ERROR:" log | grep -v "still in use")`. Also run
   the hideout headless for 300 frames (`godot --headless --quit-after 300`) like CI does. Extend the smoke test for
   every behavior you add (sections + `NEEDS`, `-- section=name` to run one).
5. **Look at it.** `xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 -s
   script.gd` and save `get_viewport().get_texture().get_image()`; check over sky, grass and dark rooms.
6. **Online changes:** test with the in-process server + clients (`net`, `pvp`, `online_ai`, `online_loot`
   sections) *and* with real processes (a `--server` process + two game processes driving the hideout; a client
   script that calls `hideout.go_online(...)` then `Network.main.set_queued(true)`; `--countdown=1` shortens the
   queue). Real processes caught bugs the in-process tests didn't.
7. After pushing, check the CI run (GitHub MCP `actions_list` / `get_job_logs`) and `version.txt`; a scheduled
   check (`send_later`, ~6 min) works well. Tell the owner when it's live.

## 5. Deploy / infrastructure
- CI `.github/workflows/web.yml`: import → smoke test → hideout run → web export → GitHub Pages; jobs `heroku`
  (deploys the server with `HEROKU_API_KEY`; `HEROKU_ON: "true"`) and `server` (Fly.io, dormant without
  `FLY_API_TOKEN`). The server must run the **same version** as the web build (it rejects mismatched clients), so
  every push redeploys both.
- Heroku: app `bloxov-server`, one Basic dyno (flat ~$7/month, covered by the owner's student credit; usage can't
  spike: one dyno, `MAX_ONLINE` 40, `Matchmaker.MAX_RAIDS` 4). Kill switch: Heroku → Resources → turn the dyno off.
  The Docker image (`Dockerfile`, `heroku.yml`) downloads Godot 4.5.1 and imports the project at build time.
- No database yet: stash/progress live in each player's browser; the server keeps nothing permanent.
- Sandbox notes: Docker works after `dockerd &` (apt inside containers has no network: copy the local Godot binary
  in for tests). The sandbox can't reach the Heroku server directly (proxy); the owner's own test is the proof.

## 6. Gotchas learned the hard way
- `net.gd` is an autoload: never reference player/gun/scav scripts (types or `preload`) from it or from scripts
  it uses (`RaidWorld`, `Hitbox`, `Matchmaker`), or a **fresh import fails** in CI (sound preloads aren't imported
  yet). Load scenes by path at runtime. Check with a fresh clone.
- Autoload names don't compile in the `-s` test runner: use `Network.main`, never `Net.`.
- Server raids share one SceneTree: groups are global. Use `RaidScope.nodes(self, group)` / `call_all` in anything
  the server runs. Navigation in a new raid world isn't synced for a few frames: `scav.gd` guards queries
  (`_nav_ready`). Effects with no scene (server) are skipped (`Effects.*` return on null world).
- `SceneMultiplayer.server_relay = false` on the server, and `_peer_open()` before every send (sending to a
  closing peer logs errors that fail CI).
- The hideout calls `Network.main.leave_raid()` on load; `go_offline()` is a no-op in server mode (an earlier bug
  had the server disconnect itself when the hideout loaded).
- Random rolls shift when models/outfits change (e.g. the Raider model made the first Raider arrive as a duo):
  write tests that accept every valid outcome instead of one seed's outcome.
- Tests run faster than real time; the server's anti-cheat rate limits and lag-comp history use real time
  (`OS.delay_msec` in the PvP test).
- GDScript typing: values from untyped Arrays/Dictionaries need explicit types (`var t: float = ...`).
- Godot `Label3D` text blurs with the pixel font: world text goes through `Effects.WORLD_LABELS` + `WorldLabelsHUD`.
- `look_at()` only works in the tree: build transforms with `Basis.looking_at()` for nodes made in code.
- `.import` files aren't committed: import settings can't be set per file; set them in code (fonts in `HudStyle`).

## 7. Owner decisions worth remembering (details in the plan docs)
TTK "lethal-leaning middle" (AK 28 ×2 head, pistol 17 ×2.5, scav hits 15); subtle hit feedback (no kill marker,
damage numbers off by default); knife on V, backstab kills; Q/E lean, F interact; scavs a speed bump alone, dangerous
in groups; short hearing; factions don't fight each other; scavs heal (fall back at 30%, Raiders 40%); no
distance-based aggro loss; spawn budget 20 scavs + 5 Raiders, 15% Raider duos; Raiders = AI faction (own model),
PMCs = real players (PMC model); **co-op AND PvP**; duos max, 2-6 per raid, 30 s queue countdown, no late joining,
friendly fire on, downed on 0 HP in a squad (numbers pending), party codes + queue, solo stays (START RAID);
stash in the browser until accounts; separate gun models later (`GunSocket`, see BACKLOG).
**Phones too (2026-10-10): every change must follow the App Store and Google Play rules, see `docs/STORE_RULES.md`.**

## 8. Art & models (from the Artist session)
The owner runs a separate **Artist** chat on their PC with Blender (cloud sessions can't read it). Full rules are in
`docs/ART_SPEC.md`; this is the short version.

**Pipeline (proven):** Blender → `.glb` → Godot. 1 Blender unit = 1 m, origin at bottom-center, front faces Blender
+Y (= Godot −Z). 16 px/m texel density everywhere; only the 24 colours in `art_source/palette.gpl`. Imported models
get `scripts/pixel_model.gd` (`PixelModel`: nearest filtering, matte materials). Collision never comes from the
model: each scene has its own boxes. **The Python build scripts are the source of truth**, not hand edits in
Blender: edit the script, run it, export, push. With `REGENERATE_TEXTURE = False` (default) hand-painted textures
are kept. Headless: `blender --background art_source/<name>.blend --python art_source/scripts/<script>.py`
(uses the script's own settings, so set `EXPORT = True` in it first or nothing is exported).

| Model | Game file | Source / script | Size | Notes |
|---|---|---|---|---|
| Loot crate | `assets/models/props/crate.glb` | `crate.blend`, `make_crate.py` | 1.1 × 0.5 × 0.6 m (W×H×D) | Military hard case, 288 tris, 64×64 texture. Too low to be cover (deliberate) |
| Scav | `assets/models/characters/scav.glb` | `scav.blend`, `make_character.py` | ~0.8 wide, ~2.05 tall | Ragtag: tracksuits, jeans, balaclavas, ushankas; AK. 45,360 outfits |
| PMC | `characters/pmc.glb` | `pmc.blend` | same | Real players only. Modern operator, tan/green; M4 with optic. 69,120 outfits |
| Raider | `characters/raider.glb` | `raider.blend` | same | AI faction (own model since 0.7.10). Dark gear, red armband, skull/gas masks, visored helmets, RPK. 2,880 outfits |

Sources are in `art_source/`, textures in `art_source/textures/<name>.png`. One `make_character.py` builds all three
characters (`CHARACTER = "scav" | "pmc" | "raider"`); each `.glb` is 120–155 KB with every outfit option included,
128×128 texture. Character hitboxes live in the scenes: body 0.8 × 1.35 × 0.6 centred at y 0.675, head
0.62 × 0.72 × 0.62 at y 1.71.

**Character rig contract (code depends on these names):**
- `LegL` / `LegR`: empties at the hips (±0.19, 0.6). The walk animation swings them; pants and boots are children.
- `Gun` at (0.10, 1.12, −0.43) in Godot, with a `Muzzle` empty child at (0.10, 1.26, −1.0); the muzzle flash is
  moved onto it at runtime.
- Outfits: parts named `Slot__option` (`__L`/`__R` added on leg parts). An empty `Slot__none` makes "nothing" valid.
  `PixelModel` shows one random option per slot, or `pick_outfit_seeded()` online so every client sees the same
  outfit. New options or slots need no code changes.

**Decisions:** military / post-collapse style, not fantasy and not cartoony (the owner rejected the wooden crate,
then a chunky toy-like one). Each faction reads at a glance: Scavs mismatched civilians, PMCs tan/green kit, Raiders
dark with red. The crate lid emblem is a spray-painted skull in a 7×6 pixel space.

**Open items:**
- Guns as separate models (`docs/BACKLOG.md`): replace each character's built-in `Gun` with a `GunSocket` empty, then
  make `assets/models/guns/ak.glb`, `pistol.glb`, `rpk.glb` (origin at the grip, barrel along −Z, `Muzzle` empty);
  code attaches the right gun to the socket.
- Character height vs player capsule: models are ~2.05 m (inherited from the old box Scav), `player.tscn`'s capsule
  is 1.8 m. Scaling characters to ~1.8 m also changes hitboxes: a gameplay call for the owner.
- Map and props are the next big art job (M4 vertical slice): buildings, cover, lockers, safes. Same pipeline and
  reference sizes (`ART_SPEC.md` §1).
- `art_source/raider.blend` has uncommitted local changes on the owner's PC: check them before rebuilding.
