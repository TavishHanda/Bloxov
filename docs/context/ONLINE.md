# Online: the server, multiplayer code, hosting, the website and CI

Moved out of `CLAUDE.md` on 2026-11-13. Read before touching `scripts/net*.gd`, `raid_world.gd`, `matchmaker.gd`,
`server/`, the Dockerfile, the export presets or `.github/workflows/`. Capacity and costs: `docs/HOSTING_CAPACITY.md`.
Accounts and the PvP stash: `docs/archive/STASH_UPDATE_PLAN.md`.

- Multiplayer (0.7.x, `docs/MULTIPLAYER_PLAN.md`): `scripts/net.gd` is the `Net` autoload; scripts use it as
  `Network.main` (autoload names don't compile in the `-s` test). Offline by default. Server:
  `godot --headless -- --server [--port=9080]`. The `net` test section runs a server + two clients in one process.
  Hosted on Heroku (owner's student credit; `Dockerfile` + `heroku.yml`, CI job `heroku`, needs the `HEROKU_API_KEY`
  secret; app `bloxov-server`, one Basic dyno): wss://bloxov-server-0f9c9a343ceb.herokuapp.com.
  CI restarts the server (kicking raiders) right away only for a `config/net_version` raise, server infra (`server/`,
  `Dockerfile`, `heroku.yml`, `export_presets.cfg`) or a manual "Run workflow" on the Web build (job `changes`,
  `tools/server_deploy_check.sh`); other game changes wait for the nightly run (`server_nightly.yml`, 11:00 UTC), which
  also restarts an up-to-date dyno. Docs-only pushes run nothing.
  `net.gd` is an autoload: it must not reference player/gun scripts (directly or via class names), or a fresh
  import (CI) fails on their sound preloads. Check with a fresh clone: `git clone . /tmp/x && cd /tmp/x && godot --headless --import`.
  Server raids are SubViewports (`RaidWorld`) in one process: node groups are global, so AI/spawner/nav code looks
  up groups with `RaidScope.nodes(self, group)` (only its own raid), never `get_tree().get_nodes_in_group`.
  The server runs a stripped pack (0.30.9, export preset "Server", strip visuals): no real meshes/textures/materials
  on the server, only placeholders with bounds; CI's `tools/server_pack_check.gd` runs raids inside it.
  Local Docker works here after starting `dockerd` (container apt has no network; copy the local Godot binary in to test).
- Live game: https://tavishhanda.github.io/Bloxov/ (capital B; the lowercase URL 404s).
  Moving to bloxov.com (owner is buying it): `docs/DOMAIN_MOVE.md`. Saves follow players via `web/move_in.js`
  (on bloxov.com) and the move page `web/move/index.html` (hosted on the old site from its own repo, `bloxov-move`).
- CI (`.github/workflows/web.yml`) runs `tests/smoke_test.gd` headless, then exports and deploys to GitHub Pages.
  The web export is split into content-named packs the browser keeps across updates (0.29.6, `tools/split_pck.py` via
  `cache_bust.py`; `scripts/web_packs.gd` mounts them and must stay the FIRST autoload, referencing no game scripts).
  Extend the smoke test when adding gameplay.

## The net version (0.35.2)
`config/net_version` in `project.godot` is a whole number, separate from `config/version`. A client sends it in `_hello`
(as text); the server lets in the same number, tells a lower one (or an old game's "0.35.1") "update" and a higher one
"server_updating" (reserved `_rejected` reasons; the client words them for web or desktop, `Network.reason_text`).
Different game versions with the same net version play together, so ordinary updates don't lock anyone out.
- **Raise it** (and deploy the server and web together) when an @rpc is added, removed, renamed or changes arguments;
  message shapes change; item ids/sizes/prices, trader stock, recipes, quests or loadout rules change; the map list or a
  map's geometry, spawns, loot or extracts change; or a number the server judges changes (gun damage, health, speed).
- **Don't** for menus, art, sound, hideout looks, controls, text, performance or PvE-only changes.
- The `netlock` smoke section fails when the @rpc list or a rule file in `tools/net_lock_core.gd` (`RULE_FILES`) differs
  from `tests/net_lock.txt` (comment and blank lines don't count). Decide, raise the net version if needed, then
  re-record: `godot --headless -s tools/net_lock.gd`. Map scenes aren't in the lock yet: raise it by hand for them.
