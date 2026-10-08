# Backlog

Notes from playtesting. Nothing here is scheduled yet; we tackle one area at a time.

## Owner's notes (after 0.3.0)
- **Art:** owner makes models in Blender, but **placeholders everywhere until M4 (vertical slice)**. Pipeline proven with the crate (0.3.3-0.3.4).
- **Movement:** 0.3.1 (speed, sprint pose, raise time, jumps) and 0.3.2 (footsteps/noise, crouch, stamina) done.
  Later: vaulting, leaning, fall damage, stairs/ladders, real arms/sprint animation once there are models.
- **Weight from loot:** on hold until the inventory redesign.
- **Inventory:** redesign in progress, see `docs/INVENTORY_DESIGN.md`.
- **Sound:** needs a full redesign (current sounds are generated placeholders from `tools/make_sounds.py`). Later.
- **Scav/PMC pathing bug (owner, 0.5.0):** walk right up into an enemy and it can't shoot you; it just walks into you.
  Fix with the scav/AI pass (close-range behavior: back off or shoot point-blank, don't push into the player).
- **Scav spawns:** need control over where scavs spawn (currently random spawn points kept away from the player).

## Review order
Going through every mechanic in 0.3.0 one by one to hone it. See the list in the chat / CHANGELOG.
- **Inventory screen:** show the player's own character model (paper-doll) once there's a player model.
