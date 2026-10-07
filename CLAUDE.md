# Bloxov: notes for Claude

- Godot 4.5, GDScript, Compatibility renderer (web is the main target). Design doc: `docs/GAME_DESIGN.md`.
- **Versioning:** every change bumps `config/version` in `project.godot` and adds a `CHANGELOG.md` entry.
  A new roadmap phase bumps the middle number (0.2.x → 0.3.0); anything else bumps the last (0.2.3 → 0.2.4).
  After pushing, tag the commit: `git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z`.
- CI (`.github/workflows/web.yml`) runs `tests/smoke_test.gd` headless, then exports and deploys to GitHub Pages.
  Extend the smoke test when adding gameplay; it is the only way to verify changes without running Godot.
- Scenes are hand-written `.tscn` files. Node lookups in scripts use `$Path`, so keep names in sync.
- Collision layers: 1 world, 2 player, 3 enemies (bit value 4).
