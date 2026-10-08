# Changelog

Versions are `0.PHASE.CHANGE`: a new roadmap phase bumps the middle number, every change after that bumps the last.

## 0.5.2 (AK recoil way up)
- AK kicks about 3x harder: an 8-round burst climbs ~8°, a full 30-round spray ~20° if you don't pull down.
  Long sprays ease off a bit after ~12 rounds. More of the kick stays in your view (less is just visual)

## 0.5.1 (guns update: accuracy, recoil, flinch)
- **Accuracy by stance** (AK, scav chest at 20 m): hip fire standing ~75% hits, crouched ~90%, walking ~20%.
  Aimed: 100% standing or crouched, ~90% walking. Shots now land evenly in a circle instead of a square
- **Real recoil.** Each shot pushes your view up and it stays there while you fire: pull the mouse down against it.
  Full-auto has a learnable pattern (climbs hardest over the first shots, then drifts side to side).
  When you stop firing, any recoil you didn't pull down settles back. Crouching cuts recoil by 15%
- Pistol: stronger kick per shot that settles between taps, better hip fire than the AK
- **Getting shot flinches you:** your aim gets knocked and your next shots are looser for a moment
- Spraying blooms less while aimed

## 0.5.0 (guns update, step 1: aim down sights)
- **Hold right-click to aim down sights.** The gun comes to the center of the screen, the camera zooms in
  (AK more than the pistol) and the crosshair goes away: aim with the gun's sight
- Aimed shots are very accurate; **hip fire is much looser** now (AK more than the pistol), so aim for anything past close range
- While aiming you move at 70% speed and can't sprint (aiming wins if you hold both). Mouse look slows down with the zoom
- Aiming in takes a moment: AK 0.28 s, pistol 0.16 s. Reloading drops you out of aim
- Plan for the whole guns update: `docs/GUNS_PLAN.md`
- Test fix: the gameplay test starts from a fresh profile (a save left over from an earlier local run broke it)

## 0.4.0 (M1: stash & trader, the loop is complete)
- **Hideout** between raids (the game now starts here): your **stash** (8×30, scrolls), your **loadout**
  (equipment, pockets, secure pocket, backpack) and the **trader**. Drag freely between stash and loadout, then START RAID
- **Loot carries over.** Extract and you come back with everything you carried
- **Death / MIA:** you lose your loadout, **except the secure pocket**. Closing the tab mid-raid counts as dying
- **Trader:** buy AK, pistol, rifle rounds ×60, pistol rounds ×50, bandages, medkits, light armor, small/medium backpacks
  (120% of value). **Sell** anything with right-click: valuables for full value, gear for 60%
- **Free kit** (pistol, 30 rounds, bandage) when you own no weapon and can't afford one, so you can never get stuck
- **Saving:** money, stash, loadout (incl. each gun's loaded rounds and your hotbar) and stats are saved in your browser
- New profile: $3,000 and the usual starter kit
- End-of-raid screen goes back to the hideout and shows your money and stats

## 0.3.7 (inventory redesign, step 2: equipment + hotbar)
- **Equipment slots** in the inventory screen: Primary, Secondary, Armor, Backpack. Drag items on to equip, drag off
  to unequip (dropping onto a filled slot swaps), Shift+click to quick-equip/unequip, right-click Equip/Unequip/Drop
- **Guns are items.** AK Rifle (primary, full-auto) and a new **Pistol** (secondary, semi-auto, 12 rounds, pistol ammo).
  Each gun keeps its own loaded rounds. **1/2** switch weapons (short swap time); no gun = unarmed
- **Armor:** light (−20% damage) and heavy (−40%)
- **Backpacks:** small 4×3, medium 5×4, large 6×5. Your backpack grid is whatever you wear; no backpack = no grid.
  A backpack has to be empty to take it off
- **Secure pocket** (2×2), shown in the inventory. (Keeping it through death matters once the stash exists)
- **Hotbar** at the bottom of the screen: 1/2 weapons with loaded/carried ammo, **3–6** quick-use items.
  Heals bind themselves when picked up; right-click → Bind/Unbind
- Inventory screen is now three columns: container · equipment + pockets + secure · backpack
- Loot: pistols, pistol rounds, armor and backpacks show up in lockers, crates, safes and on scavs/PMCs
- Start kit: AK (loaded), medium backpack, 60 rifle rounds, a bandage

## 0.3.6 (inventory redesign, step 1: grids)
- Tarkov-style grid inventory: **pockets (4×1)** and a **backpack (5×4)**. Items have sizes (watch 1×1, laptop 2×1,
  medkit 2×2, golden toilet 2×3) and you fit them like Tetris
- Drag & drop between grids; **R rotates** while dragging; drop onto a matching stack to merge
- **Shift+click** quick-moves between a container and your inventory; **right-click** for Use / Split / Drop
- Stacking: rifle rounds ×120, pistol rounds ×50, bandages ×5
- **Ammo is now an item.** Rounds sit in your grid; reloading pulls them from your inventory. HUD shows rounds carried
- Loot containers are grids too (crate 4×3, locker 4×4, safe 3×3, bodies 4×3) and roll stacks (e.g. 20–60 rounds)
- Placeholder item icons: blocks sized to the item, rarity-colored border, short name and count
- You start each raid with 60 rifle rounds and a bandage (until the stash/loadout exists)
- HUD shows the value you're carrying; the end screen lists stacks ("Rifle Rounds x84")

## 0.3.5 (scav redesign, PMCs)
- Scavs use a new Blender model: ragtag scavengers in tracksuits, jeans, old jackets and hoodies, with balaclavas,
  beanies, caps, ushankas or old helmets, cheap chest rigs, and an old wood-stock AK
- New enemy: **PMC**. Modern operator look (helmet with headset, plate carrier, knee pads, gloves, black rifle with
  an optic). Tougher than a scav: 90 HP, quicker to react, more accurate, longer bursts, better loot. AI for now;
  they'll become other players later. About 1 in 4 spawns is a PMC
- Every scav and PMC spawns with a random outfit (hat, head, top, vest, pants, boots, gloves...), so no two look alike
- Legs now swing from the hips when walking

## 0.3.4
- Crate redesigned as a military hard transport case (1.1 × 0.5 × 0.6 m): olive paint, lid seam, latches, stencil
- Crate collision resized to match. It's now too low to use as cover (by design)

## 0.3.3 (first real art)
- Loot crates use the hand-made Blender crate model (16 px/m texture, Bloxov palette) instead of colored boxes
- Pixel-art models get crisp "nearest" texture filtering and matte materials automatically (`scripts/pixel_model.gd`)

## 0.3.2 (movement: noise, crouch, stamina)
- Footsteps: you hear your own steps, and scavs hear them too. Sprinting carries ~15 m, walking ~7 m, crouch-walking is silent. Landing is loud (~10 m)
- Scavs have footsteps, so you can hear them coming
- Crouch (C, toggle): 1.8 m/s, lower camera, smaller target, tighter spread. Sprint or jump to stand up
- Stamina: ~8 s of sprint, jumps cost stamina. Run dry and you can't sprint until it recovers to 25%. Bar shows under your HP when not full
- Scavs aim at your actual chest/eye height, so crouching behind cover matters

## 0.3.1 (movement pass)
- Slower, heavier movement: walk 3.4 m/s (was 5), sprint 5.6 m/s (was 8.5); slower backwards and sideways
- Sprint only works moving forward, lowers the gun across your body, and adds a small FOV boost
- Gun takes 0.3 s to come up after sprinting before you can fire (no more instant stop-and-shoot)
- Jumps are lower (~0.6 m) with very little air steering, a short cooldown, and a brief slowdown on landing
- Shooting in the air is much less accurate
- Head bob, strafe lean and landing dip on the camera; bigger gun bob while sprinting
- Getting shot pushes you less
- Scavs miss more when you're sprinting (same as before, now tied to actually sprinting)

## 0.3.0 (Phase 2: the loop)
- Raids: 10-minute timer, random spawn point, 2 of 3 extracts open each raid (green beam + name)
- Stand in an open extract for 7 seconds to get out; running out of time = Missing in Action
- Loot containers: crates outside, lockers in buildings, safes in the bunker (loud to crack). Hold E to search
- 14 items across 5 rarities (yes, including the Golden Toilet), ammo boxes, bandages and medkits
- 10-slot backpack (Tab): items take 1-4 slots; take, drop, put back, use
- Dead scavs drop a bag you can loot
- H heals with the best-fitting bandage/medkit (takes time, can't shoot meanwhile)
- End-of-raid screen with your loot, its value, and session totals
- HUD: raid timer, bag value, search prompts and progress, extract list (O)
- Starting reserve ammo lowered to 90, so ammo boxes matter

## 0.2.3
- Version number shown in the menu and the top-right corner
- This changelog; releases are tagged in git

## 0.2.2
- Web builds are cache-busted and the page reloads itself when a newer version is deployed (fixes Brave/Chrome showing an old build)

## 0.2.1
- Esc pause menu with volume and mouse sensitivity sliders (saved between sessions)
- Zombie rushers replaced by armed scavs: radio callout when they spot you, 3-round bursts, range-based accuracy, strafing
- Red arrow showing which direction you're being hit from

## 0.2.0 (Phase 1: move + shoot)
- Rifle: full-auto, spread and bloom, recoil, reload, headshots, tracers, muzzle flash, impact sparks, damage numbers, hit and kill markers
- Practice dummy in front of spawn
- Rusher enemies that chase and punch, and explode into voxels
- Health, ammo, damage flash and death screen
- Generated placeholder sound effects
- Automated gameplay test in CI

## 0.1.2
- F3 debug overlay (FPS, mouse input)
- Mouse is no longer re-captured on every click

## 0.1.1
- Fix camera randomly snapping in Chrome (raw mouse input + spike filter)

## 0.1.0 (Phase 0: setup)
- Godot project with a first-person controller
- Gray-box town: roads, buildings, crates, extraction markers
- Automatic web build and deploy to GitHub Pages
