# Controls: touch and keybinds

Moved out of `CLAUDE.md` on 2026-11-13. Read before adding or changing any control, button or on-screen key hint.

- **Touch controls** (0.29.9, `scripts/touch_controls.gd`, state/settings in `scripts/touch_input.gd`): on phones always,
  on computers after the first touch. Buttons send the same input actions as keys (`InputEventAction`); code that
  asked "is the mouse captured?" to mean "playing" asks `TouchInput.playing()` instead. New raid controls need a touch
  button or a spot in the ITEM wheel. The hideout walk has its own (`scripts/hideout_touch.gd`, 0.29.10).
  `tools/touch_view.gd` takes screenshots.
- **Keybinds** (0.26, `scripts/keybinds.gd`): rebinding in OPTIONS, saved in the settings. Show keys with
  `Keybinds.name_of` / `cap`, never hard-coded letters. The web build refuses Ctrl (owner).
