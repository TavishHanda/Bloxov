# Bloxov: notes for Claude

**New dev session? Read `docs/DEV_HANDOFF.md` first** (owner, state, code map, workflow, gotchas, next work).

- Godot 4.5, GDScript, Compatibility renderer (web is the main target). Design doc: `docs/GAME_DESIGN.md`.
- **Versioning:** every change bumps `config/version` in `project.godot` and adds a `CHANGELOG.md` entry.
  A new roadmap phase bumps the middle number (0.2.x → 0.3.0); anything else bumps the last (0.2.3 → 0.2.4).
  Docs/CI-only changes don't bump. Start the commit message with the version (`v0.2.4: ...`).
  No git tags (GitHub blocks creating them from the sandbox/CI, and the owner doesn't want to do it by hand).
  Version history = CHANGELOG.md + version-prefixed commit messages. Don't ask the owner to tag.
  When telling the owner about an update, lead with its version and a short name (e.g. "**0.5.1: Recoil & accuracy**").
  Phases so far: 0.5 guns, 0.6 scavs, 0.7 multiplayer (to 0.7.11), 0.8 HUD & inventory (designer session, closed at
  0.8.16; 0.8.0-0.8.3 were first released as 0.7.12-0.7.15), 0.9 multiplayer raid flow (downed/revive, per-player extract; paused at 0.9.5), 0.10 the Map & Spawn update (Bloxov Battlegrounds, first called Old Bloxov;
  `docs/MAP_PLAN.md`, to 0.10.3), 0.11 **Scorched Earth** (owner's name: code cleanup, then the map turned war zone; closed; map follow-ups kept the 0.11.x numbers), 0.12 **Hot Zone** (Scavs 2.0; closed at 0.12.39), 0.13 **Over the Top** (Movement: vaulting, prone, ladders; to 0.13.9), 0.14 **Spoils of War** (Items: keys, loot by place), then 0.15 the **Guns** update (new guns, attachments, AI loadouts; plan in `docs/GUNS_PLAN.md`), 0.16 Economy, 0.17 World art (released as 0.18.x), 0.19 the **Look** update (lighting looks are files in
  `assets/looks/`, `Look.current` picks one; `classic.tres` = the look up to 0.18, keep it), 0.20 the **Sound** update (only ADD sounds, today's stay; plan in project files `sound/plan.md`), 0.21 the **Hideout** update (walkable 3D hideout: `scenes/hideout_world.tscn` is the main scene, `scenes/hideout.tscn` is its menu; the cave is built by `art_source/scripts/make_hideout.py`, plan in project files `hideout/plan.md`). 0.22 **World Reacts** (solid-looking props got hitboxes: `tools/walkthrough_audit.gd` finds walk-through spots, buildings'
  made-solid props go through `<name>_solids.json` from make_building.py; looks-only reactions in `scripts/reacts.gd`:
  swinging lamps, bushes/curtains parting, kickable cans; never synced, never on the server; closed at 0.22.9). 0.23 **jointed characters** (real kneel/prone/crawl/downed poses, `scripts/body_pose.gd`; models from `art_source/scripts/make_character.py`; crouch/prone/downed hitboxes are measured off the posed model: after changing either, run `tools/fit_hitboxes.gd` and paste into `hitbox.gd`, the smoke test checks they match). A Stash update (separate solo/online
  stashes, online stash on the server, device accounts) is planned for closer to release; until then solo and online share one stash (owner). Only one phase can be current: other work waits for the phase to close or is
  built on a branch and released as the next phase.
- **App Store + Google Play rules apply to everything** (owner, 2026-10-10: the game will ship on phones). Read
  `docs/STORE_RULES.md` and check every change against it (violence/age rating, player-made text, privacy/data,
  accounts, real-money purchases and loot odds, ads, no downloaded code). Anything that would break a rule gets
  proposed to the owner in a compliant form, not shipped. Whenever a rule becomes relevant to the work at hand, mention it
  to the owner (they asked to be reminded). Text other players see goes through `NameFilter`.
- **Any gameplay change goes to the owner first**, even one that comes up while fixing something else
  (e.g. 0.5.7 gave scavs a view cone during a knife fix without asking). Bug fixes that restore intended
  behavior are fine; anything that changes how the game plays (AI, numbers, rules) gets proposed, not shipped.
- **Two sessions:** the owner runs a separate **designer** session for UI/visual design (catch-up: `docs/DESIGN_HANDOFF.md`).
  Both push to `main`: pull/rebase right before working and before pushing; keep commits small.
- Plan: `docs/ROADMAP.md` (milestones). Parked ideas/notes: `docs/BACKLOG.md`.
  Keep new code co-op-friendly: don't add new single-player assumptions (see ROADMAP rules).
- Live game: https://tavishhanda.github.io/Bloxov/ (capital B; the lowercase URL 404s).
- CI (`.github/workflows/web.yml`) runs `tests/smoke_test.gd` headless, then exports and deploys to GitHub Pages.
  Extend the smoke test when adding gameplay.
- **Run the tests locally before every push** (the sandbox can download Godot):
  `curl -L -o /tmp/godot.zip https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_linux.x86_64.zip`,
  unzip, then from the repo root: `godot --headless --import` and `godot --headless --fixed-fps 60 -s tests/smoke_test.gd`
  (~1 s; must print `SMOKE TEST: PASSED` with no `SCRIPT ERROR`). Don't push untested code to find out from CI.
  One part only: add `-- section=knife,heal` (pulls in what it depends on). Only push if the tests passed
  (chain the push after the test with `&&`, never after a command that ignores failures).
- Scenes are hand-written `.tscn` files. Node lookups in scripts use `$Path`, so keep names in sync.
- Flow: `scenes/title.tscn` (main scene, 0.21.13: PLAY, OPTIONS, PRIVACY, CREDITS) -> `scenes/hideout_world.tscn` (walk round the hideout; Tab / E at a station opens `scenes/hideout.tscn`, the menu: stash, loadout, trader) -> START RAID -> `scenes/main.tscn` -> end screen -> hideout.
  Persistent data lives in `scripts/profile.gd` (static, saved to `user://profile.json`). The inventory screen
  (`loot_ui.gd`) works with or without a player (hideout passes an `Inventory` and the stash).
- Multiplayer (0.7.x, `docs/MULTIPLAYER_PLAN.md`): `scripts/net.gd` is the `Net` autoload; scripts use it as
  `Network.main` (autoload names don't compile in the `-s` test). Offline by default. Server:
  `godot --headless -- --server [--port=9080]`. The `net` test section runs a server + two clients in one process.
  Hosted on Heroku (owner's student credit; `Dockerfile` + `heroku.yml`, CI job `heroku`, needs the `HEROKU_API_KEY`
  secret; app `bloxov-server`, one Basic dyno): wss://bloxov-server-0f9c9a343ceb.herokuapp.com. A Fly.io setup also
  exists (`fly.toml`, CI job `server`, skipped without `FLY_API_TOKEN`) for later (one server per raid).
  `net.gd` is an autoload: it must not reference player/gun scripts (directly or via class names), or a fresh
  import (CI) fails on their sound preloads. Check with a fresh clone: `git clone . /tmp/x && cd /tmp/x && godot --headless --import`.
  Server raids are SubViewports (`RaidWorld`) in one process: node groups are global, so AI/spawner/nav code looks
  up groups with `RaidScope.nodes(self, group)` (only its own raid), never `get_tree().get_nodes_in_group`.
  Local Docker works here after starting `dockerd` (container apt has no network; copy the local Godot binary in to test).
- Collision layers: 1 world, 2 player, 3 enemies (bit value 4), 4 interactables (bit value 8), 5 doors (bit value 16,
  world-art branch), 6 tree tops (bit value 32: only the AI's sight and shots check it, `BoxMap.LEAVES_LAYER`), 7 bushes (bit
  value 64: only the AI's sight, `BoxMap.BUSH_LAYER`), 8 barred windows (bit value 128: stops players and vaulting,
  not bullets, `BoxMap.BARS_LAYER`), 9 glazed windows (bit value 256: stops people until the pane is broken, never
  shots, `BoxMap.WINDOW_LAYER`; the panes still whole come from each building's `<name>_panes.json`, drawn and broken
  by the map, and breaks are sent online by pane number), 10 props (bit value 512: furniture and the like, stops players and vaulting only, never the AI,
  shots or eyes, not in the nav bake, `BoxMap.PROPS_LAYER`, map flag 5 -> `prop_boxes`, 0.22.0).
- Outdoor pieces that aren't box-shaped (rocks, banks, crater rims, rubble, the train) collide with triangles from
  their models (0.18.3): after changing them run the generator, `art_source/scripts/make_outdoor.py`, then the
  generator again. `tools/collision_view.gd` draws what collides over the models.
- Maps: the real map is `scenes/maps/old_bloxov.tscn`, generated by `tools/gen_old_bloxov.py` (edit the script and
  re-run it, never the scene); `RaidMap` swaps it into `main.tscn`, whose built-in test map the smoke test uses.
  The ground has hills (0.11.17): build new pieces at height 0 with `box`/`obox` and `terrain()` lifts them onto it
  (composite props inside `with group():`); see `docs/MAP_PLAN.md` "Ground".
- Far view (0.17 world art, outdoor step 10): buildings switch to a baked far mesh 70 m out (`scripts/far_view.gd`,
  `assets/models/far/`), trees to cheap far cards 110 m out (`scripts/trees.gd`). After rebuilding a building model,
  re-bake it: `xvfb-run -a godot --rendering-driver opengl3 -s tools/far_bake.gd -- <model>` (the smoke test checks one exists).
- Enemy navigation: `scripts/nav_baker.gd` bakes the walkable area at raid start from nodes in the `nav_source`
  group (CSG boxes + world-layer box colliders). New solid map pieces must be under `Level`/`Loot` (or in that group).
- Seeing it: `xvfb-run -a godot --rendering-driver opengl3 -s <script>` renders real frames (screenshots via
  `get_viewport().get_texture().get_image().save_png()`); use it to check visuals, not just tests.
- Item list for the owner: `docs/ITEMS.md`, generated by `python3 tools/gen_item_list.py`. Re-run it whenever
  `scripts/item_db.gd` (items or loot tables) changes.
- Art pipeline and reference sizes: `docs/ART_SPEC.md`. Models are `.glb` in `assets/models/`; Blender sources in `art_source/` (ignored by Godot).
- **Commits:** author as `TavishHanda <tavishhanda@hotmail.com>` (the owner's GitHub email).
  The owner asked not to have Claude listed as a contributor: no `Co-Authored-By: Claude` trailer in commit messages.
