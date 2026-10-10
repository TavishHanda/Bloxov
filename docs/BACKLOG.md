# Backlog

Notes from playtesting. Nothing here is scheduled yet; we tackle one area at a time.

## Owner's notes (after 0.3.0)
- **Art:** owner makes models in Blender, but **placeholders everywhere until M4 (vertical slice)**. Pipeline proven with the crate (0.3.3-0.3.4).
- **Movement:** 0.3.1 (speed, sprint pose, raise time, jumps) and 0.3.2 (footsteps/noise, crouch, stamina) done.
  Later: vaulting, fall damage, stairs/ladders, real arms/sprint animation once there are models.
  **Leaning done (0.6.10, Q/E; interact moved to F; tap-to-toggle option for touch).**
- **Weight from loot:** on hold until the inventory redesign.
- **Inventory:** redesign in progress, see `docs/INVENTORY_DESIGN.md`.
- **Sound:** needs a full redesign (current sounds are generated placeholders from `tools/make_sounds.py`). Later.
- **Scav/PMC pathing bug (owner, 0.5.0):** walk right up into an enemy and it can't shoot you; it just walks into you.
  Fix with the scav/AI pass (close-range behavior: back off or shoot point-blank, don't push into the player).
- **Body bags should despawn when fully looted (owner, 0.5.7).** Moving the last item out already removes the bag
  (tested since 0.5.7). If one still stays in play, note how it was emptied (used an item from it? dropped?).
- **Scav spawns:** *how many and when* is done (0.6.4 spawn budget). Still to do with the maps: *where*
  (hand-placed spawn points per area) and retuning the budget/timings for the real raid flow (owner).

## Next after the multiplayer update (owner, 0.7.x)
Owner: before moving on to the next big thing, a polish round. Starts with:
- **HUD** fixes (owner will say what bugs them).
- **Inventory screen** fixes.
- **Guns as separate models (owner, 0.7.11).** Today every character .glb has a rifle built in (`Gun` node), so
  players/scavs/Raiders always look like they hold that rifle (0.7.11 hides it on unarmed players). Plan:
  - **Owner, Blender:** in pmc/scav/raider, replace the gun meshes with an empty `GunSocket` where the hands hold a
    gun (same place the `Gun` node is now: 0.10, 1.12, -0.43; barrel pointing -Z). Make each gun its own file
    (`assets/models/guns/ak.glb`, `pistol.glb`, `rpk.glb`), origin at the grip, barrel along -Z, with a `Muzzle`
    empty at the barrel tip. Same 16 px/m texel density (`docs/ART_SPEC.md`).
  - **Code:** attach the right gun model to `GunSocket`: other players get what they're holding (synced), scavs
    and Raiders get theirs; muzzle flash/tracers from the gun's `Muzzle`. The first-person guns could use the
    same models later.
- **Item descriptions (owner writes them, after 0.8.2).** A short description per item, shown in the inventory's
  details area under the stats (needs a `desc` field per item in `scripts/item_db.gd`).
- **Mobile: hold an item to see its details** (no hover on touch screens), when the touch controls come.
- **Loading screen (owner asked, 0.8.2):** the web build shows Godot's logo while it downloads and starts. Both the
  page's loading screen and the engine's boot splash can show Bloxov's own logo/colors instead (export preset +
  `application/boot_splash` settings). The wait itself is the download; the browser caches it after the first visit.
- Then other things the owner wants to talk through.

## Owner's wishlist (after 0.5.9)
Agreed order: core gameplay first (scavs next), then the co-op test (M3), then map, then content and art.
- **Playable characters with their own perks (owner wants this; M5 content).** Plan discussed:
  **real named characters with lore and personality** (owner: not generic "scout/tank" classes), each with
  traits the owner will design later. Traits should be **tradeoffs**, not pure buffs.
  Progression inside each character unlocks **options** (pick 1 of 2 perks per slot), not bigger numbers,
  plus unlocking more characters. A separate global permanent skill tree on top: **not planned** (stacks power
  on veterans, two progression systems to balance, makes characters feel the same). Revisit if the owner wants.
  Design-doc rule to keep in mind: progression = access, not power.
- **More traders** (after the map, when there are more items/guns to sell; each trader with its own stock/rules).
- **Walkable 3D hideout** (presentation feature, later polish; the menu hideout works until then).
- **More loot and items** (content; best once combat and the map give them a purpose and a place).
- **Food and water: MAYBE.** The design doc lists hunger/thirst as "not building" (chores in short raids).
  If it comes back, keep it light pressure (Tarkov-style), not a survival sim. Owner's call later.
- **Maps** (layout with risk zones like the bunker, plus scav spawns; after scavs and the co-op test) and
  **models** (owner in Blender, at the vertical slice, M4).

## AI faction vs. real PMCs (owner, after 0.6.10)
- **Owner wants co-op AND PvP** (after 0.6.15): real players are the PMCs, in raids with each other and the AI.
- **PMCs are meant to be real players** (multiplayer). The AI "PMCs" became **Raiders** (owner's name, 0.6.15):
  same behavior. Own Raider model since 0.7.10 (`raider.glb`, built by `make_character.py`).
- **The PMC model (`assets/models/characters/pmc.glb`) stays untouched for actual players.**

## Ground textures (owner, 0.11.9)
- The ground needs real textures (dead grass, mud, scorch, dirt paths), not flat coloured boxes (0.11.8's flat
  dead-grass patches looked bad and were removed). Plan: a ground shader that blends a few tiling textures
  (grass, dead grass, dirt, burnt) by a mask image the map generator paints (round junk, craters, trenches,
  buildings). Do it with the owner's art/model pass, so the textures match the models (`docs/ART_SPEC.md`).

## Review order
Going through every mechanic in 0.3.0 one by one to hone it. See the list in the chat / CHANGELOG.
- **Inventory screen:** show the player's own character model (paper-doll) once there's a player model.
- **Meds wheel (owner, 0.9.3):** more medical items are planned. If meds grow past ~4 types, turn "hold 3" into a
  radial wheel (hold, drag/move onto a med, release). `Inventory.cycle_meds()` already keeps the options as a list.
- **First-person spectate (owner, 0.9.5):** a toggle (Space) between the over-the-shoulder view (`Spectator`, default)
  and the teammate's eyes, with their body hidden. Wait for separate gun models (`GunSocket`, above) so the view can
  show the gun they're actually holding; until then it would be a floating camera with a placeholder gun.
- **0.9 leftovers (owner paused 0.9 after 0.9.5):** a real playtest of downed/revive/spectate with friends;
  "teammate down" alert (sound, a line on screen, an edge-of-screen arrow to them); a squad line on the end screen
  ("Bravo: extracted / killed"); rejoining a raid after a disconnect.
- **Code cleanup after 0.10 (owner, 0.10.0):** once the map phase closes, a cleanup pass over the code before the
  next big update (Scavs 2.0 / Items).
