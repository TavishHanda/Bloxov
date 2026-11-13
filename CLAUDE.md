# Bloxov: notes for Claude

Godot 4.7, GDScript, Compatibility renderer (web is the main target, then Steam, then phones). The owner, Tavish,
makes every gameplay call. Design doc: `docs/GAME_DESIGN.md`. Where the project stands and what is next:
`docs/RELEASE_PLAN.md` "Where it stands".

## Read only what the task needs
This file is loaded into every session, so it holds only the rules that apply to every change. Before touching an
area, read its notes (and nothing else):

| Touching... | Read first |
|---|---|
| Anything a past update built (guns, AI, hideout, looks, sound, durability, crafting, movers...) | that phase's entry in `docs/context/PHASES.md` |
| Net code, the server, accounts, hosting, CI, export presets, the website | `docs/context/ONLINE.md` |
| A map, a building or outdoor model, collision, navigation, the far view | `docs/context/MAPS.md` |
| A control, a button, a key hint | `docs/context/CONTROLS.md` |
| Anything players pay for, write, or that touches privacy, violence or accounts | `docs/STORE_RULES.md` |
| Art and models | `docs/ART_SPEC.md` |
| UI and visual design (the owner's separate designer session) | `docs/DESIGN_HANDOFF.md` |
| How the owner works, art taste, why things were built this way | `docs/CLAUDE_HANDOFF.md`, `docs/DEV_HANDOFF.md` §1, §4, §6 (their "where things stand" parts are old) |

Plan: `docs/ROADMAP.md`. Parked ideas: `docs/BACKLOG.md`. The code map is each script's own header comment
(every file in `scripts/` starts with one): `head -5 scripts/<file>.gd`, or `grep -n "^## " scripts/*.gd`.

## Rules for every change
- **Versioning:** every change bumps `config/version` in `project.godot` and adds a `CHANGELOG.md` entry.
  A new roadmap phase bumps the middle number (0.2.x → 0.3.0); anything else bumps the last (0.2.3 → 0.2.4).
  Docs/CI-only changes don't bump. Start the commit message with the version (`v0.2.4: ...`).
  No git tags (GitHub blocks creating them from the sandbox/CI, and the owner doesn't want to do it by hand).
  Version history = CHANGELOG.md + version-prefixed commit messages. Don't ask the owner to tag.
  When telling the owner about an update, lead with its version and a short name (e.g. "**0.5.1: Recoil & accuracy**").
  **Only one phase can be current:** other work waits for the phase to close or is built on a branch and released
  as the next phase. Phase history and what each phase built: `docs/context/PHASES.md`.
- **Any gameplay change goes to the owner first**, even one that comes up while fixing something else
  (e.g. 0.5.7 gave scavs a view cone during a knife fix without asking). Bug fixes that restore intended
  behavior are fine; anything that changes how the game plays (AI, numbers, rules) gets proposed, not shipped.
- **App Store + Google Play rules apply to everything** (owner, 2026-10-10: the game will ship on phones). Read
  `docs/STORE_RULES.md` and check every change against it (violence/age rating, player-made text, privacy/data,
  accounts, real-money purchases and loot odds, ads, no downloaded code). Anything that would break a rule gets
  proposed to the owner in a compliant form, not shipped. Whenever a rule becomes relevant to the work at hand, mention it
  to the owner (they asked to be reminded). Text other players see goes through `NameFilter`.
- **Two sessions:** the owner runs a separate **designer** session for UI/visual design (catch-up: `docs/DESIGN_HANDOFF.md`).
  Both push to `main`: pull/rebase right before working and before pushing; keep commits small.
- Plan: `docs/ROADMAP.md` (milestones). Parked ideas/notes: `docs/BACKLOG.md`.
  Keep new code co-op-friendly: don't add new single-player assumptions (see ROADMAP rules).
- **Run the tests locally before every push** (the sandbox can download Godot):
  `curl -L -o /tmp/godot.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`,
  unzip, then from the repo root: `godot --headless --import` and `godot --headless --fixed-fps 60 -s tests/smoke_test.gd`
  (~1 s; must print `SMOKE TEST: PASSED` with no `SCRIPT ERROR`). Don't push untested code to find out from CI.
  One part only: add `-- section=knife,heal` (pulls in what it depends on). Only push if the tests passed
  (chain the push after the test with `&&`, never after a command that ignores failures).
  CI (`.github/workflows/web.yml`) runs the same test, then exports and deploys. Extend the smoke test when adding
  gameplay.
- **Commits:** author as `TavishHanda <tavishhanda@hotmail.com>` (the owner's GitHub email).
  The owner asked not to have Claude listed as a contributor: no `Co-Authored-By: Claude` trailer in commit messages.

## Tripwires (one line each; the detail is in the file named)
- `scripts/web_packs.gd` must stay the FIRST autoload and reference no game scripts (`ONLINE.md`).
- `scripts/net.gd` is an autoload: it must not reference player/gun scripts, directly or by class name; check with
  a fresh clone import (`ONLINE.md`). Scripts reach it as `Network.main`.
- Server raids share one process: look up groups with `RaidScope.nodes(self, group)`, never
  `get_tree().get_nodes_in_group`. The server has no real meshes, textures or materials (`ONLINE.md`).
- Looks-only things (reacts, movers, hideout life) are never synced and never run on the server (`PHASES.md`).
- The real map is generated: edit `tools/gen_old_bloxov.py` and re-run it, never the scene. After changing map
  geometry re-bake navigation; after rebuilding a building re-bake its far mesh and re-run the window audit (`MAPS.md`).
- After changing character models or poses, run `tools/fit_hitboxes.gd`; after adding materials or new kinds of
  things, re-run `tools/gen_shader_warm.gd` (`PHASES.md`, 0.23 and 0.29).
- New raid controls need a touch button or a spot in the ITEM wheel; show keys with `Keybinds.name_of`/`cap`,
  never hard-coded letters (`CONTROLS.md`).
- After changing `scripts/item_db.gd`, re-run `python3 tools/gen_item_list.py` (`docs/ITEMS.md` is the owner's list).
- Text other players see goes through `NameFilter`.

## How the game is put together
- Scenes are hand-written `.tscn` files. Node lookups in scripts use `$Path`, so keep names in sync.
- Flow: `scenes/title.tscn` (main scene, 0.21.13: PLAY, OPTIONS, PRIVACY, CREDITS) -> `scenes/hideout_world.tscn` (walk round the hideout; Tab / E at a station opens `scenes/hideout.tscn`, the menu: stash, loadout, trader) -> START RAID -> `scenes/main.tscn` -> end screen -> hideout.
  Persistent data lives in `scripts/profile.gd` (static, saved to `user://profile.json`). The inventory screen
  (`loot_ui.gd`) works with or without a player (hideout passes an `Inventory` and the stash).
- Seeing it: `xvfb-run -a godot --rendering-driver opengl3 -s <script>` renders real frames (screenshots via
  `get_viewport().get_texture().get_image().save_png()`); use it to check visuals, not just tests.
