# Changelog

Versions are `0.PHASE.CHANGE`: a new roadmap phase bumps the middle number, every change after that bumps the last.

## 0.7.6 (other players' heads look around)
- Other players' **heads** now tilt up and down with where they look; their gun stays put (owner: it was the gun
  that moved)

## 0.7.5 (Heroku server address)
- ONLINE now connects to the game server on Heroku (`bloxov-server-0f9c9a343ceb.herokuapp.com`) by default

## 0.7.4 (build fix)
- Fixes the web build, which stopped deploying at 0.7.2: on a fresh copy of the project (like the build
  server's), the online code loaded the player code before the game's sounds were imported. 0.7.2 and 0.7.3
  go live with this

## 0.7.3 (multiplayer: matchmaking)
- **ONLINE** in the hideout (was JOIN ONLINE): pick a name and **Go online**. Room codes are gone
- **Party up:** everyone gets a party code; a friend types it in to join you (duos max). Your party stays
  together between raids
- **Queue:** solos and duos queue into the same raids. Once 2 players are waiting, a **30-second countdown**
  gives others time to join, then everyone waiting goes into one raid together (up to 6; a full queue starts at
  once; a duo is never split up). **No joining a raid that's already running**
- **Start now:** an online raid with just you (or your party), no queue: for testing
- **Teammates get a green name tag** (friendly fire is on); other players get none
- One server now runs **several raids at once** (up to 4)
- START RAID is still the solo raid against the AI (offline)
- The game server goes up on Heroku (student credit)

## 0.7.2 (multiplayer: see each other properly)
- Other players now **crouch, lean, sprint and aim** where you can see it, their gun follows where they look,
  their legs walk, and they **fall over when they die** (and vanish when they extract)
- **Smooth movement:** other players are drawn a tenth of a second behind, gliding between updates instead of
  jumping 20 times a second
- Their hitboxes already follow their pose (crouched = smaller, leaning = head off to the side), ready for
  shooting each other in the next update
- The server ignores malformed updates (a broken or tampered game can't crash everyone else)

## 0.7.1 (online server)
- **There's a real server now** (once the owner's Fly.io account is connected): JOIN ONLINE goes to
  `wss://bloxov-server.fly.dev` by default, so you and your friends can join the same room from the live link
- The server updates together with the game, so versions always match
- It sleeps when nobody's online and wakes up when someone joins (the first join can take a few seconds)
- Typing an address without `ws://`/`wss://` now uses a secure connection (needed from the https page)

## 0.7.0 (multiplayer step 1: connect)
- **JOIN ONLINE** in the hideout: enter a server address and a room code, and everyone with the same code lands in
  the same raid (up to 6 players). START RAID is still solo and works exactly as before
- **You can see the other players** walking around (PMC model). They can't shoot or be shot yet (0.7.2)
- The server runs the raid clock (join late and you get the time that's left) and picks the open extracts, so
  everyone in the room has the same ones
- Online raids have **no scavs or Raiders yet** (they move to the server in 0.7.3), and loot is still separate
  for each player (shared in 0.7.4)
- The Esc menu doesn't pause an online raid
- Wrong code, full raid or an outdated game: the Join box says why
- Server: the same game, started with `godot --headless -- --server` (no server online yet: that's step 7)

## 0.6.15 (Raiders)
- **The AI "PMCs" are now called Raiders** (owner's name). Same behavior. Real PMCs will be other players once
  multiplayer exists
- **Raiders look different:** a red-brown recolor of the PMC model for now (own models later). The original PMC
  look is untouched and saved for real players
- Their bodies are "Raider Body" bags; their loot table is unchanged (just renamed)

## 0.6.14 (scavs fall back later)
- Hurt scavs now fall back to heal **below 30% health** (was 40%), so they stay in the fight longer.
  PMCs still fall back at 40%

## 0.6.13 (harder PMCs; scav teamwork removed)
- **PMCs are harder to fight** (scavs behave exactly as before):
  - They **hear gunshots twice as far away** and come toward fights
  - In a lull they sometimes **flank**: circle around to hit you from the side instead of taking cover
  - Closing in on you they **sneak**: slower, and their footsteps go silent
  - They **hunt longer** (chase 15 s, search 10 s) and take cover sooner and more often
  - They can **heal twice**
  - **15% of PMCs arrive as a duo**: a partner that sticks with them (still 5 PMCs per raid in total)
- **Removed scav radio calls** (0.6.12): owner didn't like it

## 0.6.12 (scavs: teamwork)
- **Scavs call for help:** when one spots you (or gets shot) it radios enemies within 30 m, and they **jog over**
  to roughly where you are. They don't know your exact spot. One scav is a speed bump; a group is a fight

## 0.6.11 (scavs: getting hurt)
- **Badly hurt scavs fall back and heal:** below 40% health a scav retreats to nearby cover and patches itself up
  (+40 HP over 4 seconds, once per life). You'll see it lean in while healing
- **Shooting it interrupts the heal**: a wounded scav that ran for cover is worth pushing

## 0.6.10 (leaning, owner idea)
- **Lean with Q / E** to peek around corners: your head shifts sideways and tilts. You walk slower and can't sprint
  while leaning, and you can't lean through a wall
- **Interact (search/loot) moved from E to F**
- **"Lean: tap to toggle"** option in the Esc menu (tap Q/E to lean, tap again to stop; planned for touch screens)
- Scavs see your leaning head: peek out and they can spot you, and if your body is behind cover they aim for your head

## 0.6.9 (scavs: cover during breaks, owner direction)
- **Fighting comes first:** while you're shooting at a scav it fights back from where it is
- **In a break** (about 2 seconds with no shots, hits or near misses, between its own bursts) it moves to a nearby
  spot you can't see, waits about 1.5 seconds, then peeks back out to keep fighting. At most once every 10 seconds
- It only picks spots it can actually walk to quickly (not the other side of a building)

## 0.6.8 (player-like scavs, owner idea)
- **Scavs "loot" like players:** at a crate they stop, lean in and search it for 3-6 seconds before moving on.
  They don't take anything (they only carry what they spawned with), but **while searching they're distracted**
  and slower to notice you: a good moment to sneak up or take the first shot
- **About 1 in 3 trips is a jog** instead of a walk
- Fixed: a scav's hit jolt and melee wind-up leaned the wrong way (forward instead of back)

## 0.6.7 (scavs: patrols, owner feedback)
- **Unaware scavs patrol the map** instead of hanging around where they spawned (the map edge): they walk to a
  destination (usually a loot spot, sometimes anywhere they can reach), pause there for 2-6 seconds, then move on
- **They walk at a normal pace** (~2 m/s, you walk at 3.4) instead of a slow 1 m/s stroll, and stand around less

## 0.6.6 (scavs: getting around)
- **Scavs find their way around buildings and crates** instead of walking into walls. The raid builds a map of
  where they can walk when it starts, and they follow paths when investigating a noise, chasing you to where
  they last saw you, closing in, or wandering
- Idle scavs stroll to spots they can actually reach (still calm and slow-turning)
- In a fight, strafing and backing off won't push them into a wall; they switch sides instead
- If they can't reach a spot (e.g. you're on top of something), they go as close as they can and search there

## 0.6.5 (more enemies per raid, owner)
- **20 scavs** per raid (3 at the start, then one every 25-35 seconds so they're spread over the whole raid)
- **5 PMCs**, arriving around minutes 2, 3½, 5, 6½ and 8
- Still never more than 5 alive at once

## 0.6.4 (limited enemies per raid, owner idea)
- **Each raid has a limited number of enemies**, spread over the 10 minutes. Clearing an area now actually
  makes it safer (it used to refill every 5 seconds, forever)
  - **12 scavs:** 3 at the start, then about one every 40-60 seconds
  - **3 PMCs:** they arrive around minutes 3, 5 and 8 (late-raid pressure)
  - Never more than 5 alive at once; new ones spawn away from you and out of your sight
- Numbers are placeholders until the maps exist (owner will retune)

## 0.6.3 (scavs: melee bash, owner idea)
- **Get within ~1.6 m of a scav and it bashes you with its rifle butt.** It leans back to wind up (0.3 s, you can
  see it coming), then hits: **20 damage, a hard shove, your aim jolts, and you can't aim down sights for 0.6 s**.
  1.5 s cooldown. It still prefers backing off and shooting; the bash is for when you close the gap anyway
- **PMCs bash harder and faster** (25 damage, quicker wind-up, 1.1 s cooldown)

## 0.6.2 (scavs: close range)
- **Fixed: running into a scav made its shots miss you.** Its bullets started at the tip of its gun barrel, so
  with you right in its face they started *past* you. They now start from its chest (the tracer and sound still
  come from the gun)
- **Point blank (under 4 m), scav shots almost always hit** (90%)
- **Scavs keep about 3 m away:** get closer and they back off (with a little sideways movement) while shooting,
  instead of walking into you

## 0.6.1 (scavs: spotting, near misses, calmer wandering)
- **Gradual spotting:** a scav needs you in view for a moment before it notices you: about 0.25 s up close,
  up to ~1.8 s at 40 m. **Crouching or standing still** makes you slower to notice, **sprinting** faster.
  Scavs that are already investigating or searching notice faster
- **Breaking line of sight works:** a scav that loses you has to re-spot you (faster than the first time)
  instead of tracking you anywhere it has a clear view
- **Near misses:** a bullet passing within 2.5 m of a scav gets its attention even if it's too far away to hear
  the shot. It turns toward roughly where the shot came from
- **Calmer idle scavs:** they change direction every 3.5-8 s (was 1.5-4), mostly small turns, and turn slowly,
  so sneaking up for a backstab is possible

## 0.6.0 (scavs update, step 1: senses)
Start of the scav update (`docs/SCAVS_PLAN.md`).
- **Hearing = investigating.** A scav that hears you (shots, footsteps, knife, searching a crate) walks over to
  *roughly* where the sound came from and looks around. It no longer instantly knows where you are
- **No more tracking through walls.** Lose its sight and it goes to where it **last saw** you, searches for a few
  seconds, then goes back to wandering. Breaking line of sight and moving is now a real escape
- Getting shot while unaware: it knows roughly where it came from and turns that way
- **Shorter hearing for gunshots** (owner): AK 35 → 25 m, pistol 25 → 18 m
- **Unaware scavs see 180°** in front of them (was 120°); only directly behind them is blind
- Scavs pick the closest player (ready for co-op)

## 0.5.9 (version in the hideout)
- The hideout's top bar shows the game version (next to "BLOXOV · HIDEOUT"), like the corner in a raid

## 0.5.8 (code cleanup + fixes)
Whole-codebase cleanup (no gameplay changes beyond the fixes below). Owner-approved changes:
- **Damage numbers show the real damage** after armor (an AK body shot on a PMC shows 22, not 28)
- **Raids start with 3 enemies** as intended (a timing quirk added a 4th right away)
- **Searching:** looking at a different container while holding E starts the search over (no more finishing
  crate B with crate A's progress)
- **Hotbar:** moving a heal around inside your own inventory no longer re-binds one you unbound
  (heals picked up from outside still bind; right-click > Bind to hotbar to add one yourself)
- **"No room in ..."** message when moving something into a full container/inventory (it used to silently do
  nothing, or drop gear on the ground)
- One wording for "Empty your backpack first"

Fixes:
- **Infinite healing exploit:** using your last bandage while dragging it left a 0-count bandage that healed forever
- Dropping a gun on the ground (or in a bag) no longer empties its magazine
- Dropping items below the stash's scroll area no longer puts them in rows you can't see
- Shift+clicking a medkit into your inventory binds it to the hotbar like bandages
- The hideout uses your saved volume (it ignored it until your first raid)
- Free kit no longer duplicates ammo when your pockets already hold some
- Saves are safer: removed/renamed items can't wipe your loadout, a broken save is backed up
  (`profile.bad.json`) instead of silently replaced, and a gun's loaded rounds survive a stash re-sort
- Crouching only shrinks your own hitbox (co-op prep)

Under the hood: gun and knife share their hit code and kills are counted per player; the inventory screen lost
~15 duplicated blocks; dead code and stale comments removed; docs updated (README, design docs, item list).
Tests: split into 28 named sections with a reset between them, run in ~1 s instead of ~40 s, can run one section,
and no longer touch your local save. CI fails on engine errors too and uses current GitHub actions.

## 0.5.7 (fixes: impact effects, sneaking, knife)
- **Fixed (since the start): bullet impacts, sparks and death bursts appeared in the middle of the map**
  instead of where they happened
- **Scavs can't see behind them anymore.** While unaware they only spot you inside a 120° view in front of them
  (they used to see in every direction). They still hear you walking: **crouch-walk to sneak up** on them.
  Once alerted they track you as before
- Knife fixes: backstabs now actually work in a real raid (the swing used to warn the scav before the blade hit),
  backstabs kill armored PMCs too, the stab is cancelled if you die or start healing mid-swing,
  no more one-frame flicker of the knife, and the swing has its own whoosh (it was playing the reload sound)

## 0.5.6 (knife, weaker pistol)
- **Knife on V.** Everyone always has one: it isn't an item, so you can't lose or sell it. Works with any gun out
  (cancels aiming and reloading). 45 damage from the front, **one-hit kill from behind**. Quiet (only very close
  enemies hear it). For point-blank fights and sneaking up on scavs
- **Pistol: 17 body damage, 2.5x headshots** (6 body shots or 3 headshots on a scav). A weak sidearm that rewards
  aiming for the head. Headshot multiplier is now per gun (AK stays 2x)

## 0.5.5 (AK kills slower)
- Headshots back to 2x (from 3x): the AK needs **2 headshots**, no more one-taps
- AK damage 34 → 28: **4 body shots** on a scav (about 0.3 s of full auto instead of 0.2 s), 5 on an armored PMC
- Pistol unchanged (4 body / 2 head). You still die in 7 scav hits

## 0.5.4 (hit feedback, kept subtle)
- **Scavs flinch when you hit them:** they stop firing for a moment, aim worse for ~1 second, and visibly jolt.
  Whoever lands the first hit has the edge now (same as your flinch when you get shot)
- **No more kill marker.** A kill looks like any other hit on the crosshair; you find out by seeing them drop
  (the kill sound stays)
- **Damage numbers are off by default.** Turn them on with "Show damage numbers" in the Esc menu

## 0.5.3 (time to kill: lethal-leaning middle)
- **You die in 7 scav hits** (was ~13). Light armor: 9 hits, heavy armor: 12. PMCs hit harder (6 hits)
- **Scavs have 100 HP, like you.** AK: 3 body shots, **1 headshot kills**. Pistol: 4 body shots, 2 headshots
- **PMCs wear armor** (take 80% damage): 4 AK body shots
- Headshots now do 3x damage (was 2x). AK damage 22 → 34, pistol 18 → 25
- Scavs and PMCs aim a bit worse, so the danger is getting caught in the open, not random hits from far away

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
