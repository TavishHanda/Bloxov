# Bloxov: notes for Claude

- Godot 4.5, GDScript, Compatibility renderer (web is the main target). Design doc: `docs/GAME_DESIGN.md`.
- **Versioning:** every change bumps `config/version` in `project.godot` and adds a `CHANGELOG.md` entry.
  A new roadmap phase bumps the middle number (0.2.x → 0.3.0); anything else bumps the last (0.2.3 → 0.2.4).
  Docs/CI-only changes don't bump. Start the commit message with the version (`v0.2.4: ...`).
  No git tags (GitHub blocks creating them from the sandbox/CI, and the owner doesn't want to do it by hand).
  Version history = CHANGELOG.md + version-prefixed commit messages. Don't ask the owner to tag.
- Plan: `docs/ROADMAP.md` (milestones). Parked ideas/notes: `docs/BACKLOG.md`.
  Keep new code co-op-friendly: don't add new single-player assumptions (see ROADMAP rules).
- Live game: https://tavishhanda.github.io/Bloxov/ (capital B; the lowercase URL 404s).
- CI (`.github/workflows/web.yml`) runs `tests/smoke_test.gd` headless, then exports and deploys to GitHub Pages.
  Extend the smoke test when adding gameplay; it is the only way to verify changes without running Godot.
- Scenes are hand-written `.tscn` files. Node lookups in scripts use `$Path`, so keep names in sync.
- Collision layers: 1 world, 2 player, 3 enemies (bit value 4), 4 interactables (bit value 8).
- Art pipeline and reference sizes: `docs/ART_SPEC.md`. Models are `.glb` in `assets/models/`; Blender sources in `art_source/` (ignored by Godot).
- **Commits:** author as `TavishHanda <tavishhanda@hotmail.com>` (the owner's GitHub email).
  The owner asked not to have Claude listed as a contributor: no `Co-Authored-By: Claude` trailer in commit messages.
