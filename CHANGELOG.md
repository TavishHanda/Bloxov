# Changelog

Versions are `0.PHASE.CHANGE`: a new roadmap phase bumps the middle number, every change after that bumps the last.

<!-- Phases: 0.7 = multiplayer (0.7.0-0.7.11), 0.8 = HUD and inventory (0.8.0 onward). The first four 0.8
updates went out as 0.7.12-0.7.15 and were renumbered afterwards (owner). 0.11 = the Scorched Earth update
(owner's name: code cleanup, then the map turned into a war zone: craters, wrecks, blown-out buildings, trenches, hills). Update names (owner asked, 2026-10-11): 0.12 Hot Zone (Scavs 2.0), 0.13 Over the Top
(Movement), 0.14 Spoils of War (Items), 0.15 the Guns update, 0.16 the Economy update, 0.17 the World art update (built on a branch, released all at once as 0.18.0), 0.19 the Look update, 0.20 the Sound update (owner: only ADD sounds, today's stay as they are), 0.21 the Hideout update (the walkable hideout), 0.22 World Reacts (things that look solid are solid; lamps, bushes, curtains and cans react), 0.23 jointed characters (name to come from the owner), 0.24 the new-player tutorial (built on a branch while 0.23 is open), 0.25 **Checkpoint** (the security update: anti-cheat and server checks), 0.26 Keybinds (rebinding in OPTIONS), 0.27 Durability (wear and trader repairs), 0.29 the Engine update (Godot 4.7), 0.31 the Stash update (PvE and PvP stashes, accounts; `docs/STASH_UPDATE_PLAN.md`), 0.32 Crafting (the workbench, `scripts/crafting.gd`), 0.34 the Lively hideout update (0.33 is held by the Riptide map branch). -->

## 0.34.5 (Hideout shell and generator can be heard)
Owner: "when the bomb drops every 2-4 mins it didnt have any noises just effects". The shell's boom (0.34.0) was
almost all under 80 Hz, which phone and laptop speakers and most earbuds can't play, so it was silent for most people.
It now has a dull crump and a rumble at 100-400 Hz and a soft rattle of things shaken loose (still muffled through
the rock, no highs, same loudness setting). The generator's chug had the same problem (all 55 Hz) and now carries its
overtones. Other hideout sounds (drip, pipes, rat, snore, wrench, cat, grit) were already in the range speakers play.

## 0.34.4 (Extract cover)
- **Every Frontlines extract got its own cover** (owner: the extracts were "WAY too easy to extract camp"; then
  "make them a bit unique ... leave some lines where u can shoot from but make sure there are like safe corners"):
  - **Farm Road**, a container yard: two containers in an L (one stacked) cover the back left, sandbags on the right.
  - **Highway**, a roadblock: an army truck across the road in front, hesco on one side, concrete barriers on the other.
  - **Creek Trail**, dug in at the woods: a hesco L toward the hill, a second row out front, sandbags on the open side.
  - **Town Road**, the fort: walled all round in head-high hesco, in through a gap with a wall across it.
  - **Mill Lane**, a zig-zag: in at the front left behind a second row, stacked containers toward the church tower.
  - **South Road**, a container canyon: containers two high on both sides and across the front, in behind a hesco row.
- Each one still has lines in (over sandbags, past the truck, through the way in), and each has a corner of the square
  almost nobody further off can see. The ground a camper could watch a crouched player in the square from (20-130 m
  out, `tools/extract_camps.gd`, `corners=1` for each spot of the square) went from about 28,300 m² over the six
  extracts to about 6,300 m² (Farm Road, the most open, keeps about 4,500 of it).
- The tent camps beside the squares moved a few metres along the edge to make room; a power pole at Farm Road and
  Highway and a street lamp at Town Road went too. The rest of the map is unchanged; AI navigation re-baked.
## 0.34.3 (Crew get up)
- **Everyone in the hideout moves now** (owner: "are these two perma in this spot? they should move too", "one guy can
  be sleeping a lot but he should get up", "everyone can sleep but not at the same time", "do what's best as an expert
  game designer"): the crew no longer each own one spot. The hideout has 15 things to do, one person each: the bunk,
  the stove, two card seats, two places at the mess table to eat, the couch in front of the TV (two), the den's booth
  and two bar stools, the den itself, the war table, the generator and a coffee by the range. Everyone has a favourite
  they go back to more often and stay longer at (the sleeper still sleeps a lot), and when they're done they pick
  something free and walk there. Only one can be in the bunk, nobody takes a seat you're sat on, and the seat they're
  on isn't offered to you. What they hold goes with what they're doing (a spoon cooking or eating, the wrench at the
  generator, a mug with a coffee, the TV or at the bar, cards at the card table). Looks only, as before.
- **Faster walking** (owner: "they walk way too slow"): 1.25 m/s to 2.4 m/s.
- **No more standing about gesturing at nothing** (owner: "the npcs just kinda sit here like this sometimes"): the old
  walkers' stop by the stash was a spot with nothing to do. Stood about now means arms crossed or hands on hips, and
  talking with their hands only when someone else is there. Someone held up on the way finds the route again.
- `tools/hideout_crew_view.gd` takes a picture of someone at each thing to do.

## 0.34.2 (Hideout fixes)
- **Arms the right way round** (owner: "that guy's one arm is backwards, same with all the traders"): the crew's and
  traders' poses bent their elbows backwards. On the character models a positive elbow angle brings the forearm
  forward; `HideoutCrew._elbows` flips the ones written the other way, and what they hold moved with their hands.
- **Two of the crew walk round** (owner: "everyone seems to be still", "make sure the dudes can path to the secret room
  and chill there"): they go from spot to spot (war table, workbench, range, mess, the traders' row, the den), the
  den most often, and hang about at each: arms crossed, hands on hips or talking. They walk over the hideout's
  walkable area, `assets/hideout/nav.res`, baked by `tools/hideout_nav_bake.gd` (re-run it after `make_hideout.py`
  changes the cave). Everyone else glances about when you're not near, and the traders' idles are bigger.
- **The trophy shelf has its own spot** (owner: "in the middle of nowhere", wants it "up where stash/wardrobe is"):
  at the far end of the armory, past the workbench, against the wall.

## 0.34.1 (Clean raid models)
The scavs, raiders (Bon too) and your PMC get the clean look the hideout's traders got in 0.34.0 (owner: "looks fire").
Looks only: the bodies and hitboxes are exactly the same.
- Twice the pixels (32 px per metre, 256 px textures) and flat colours with only a faint mottle, so the random speckle
  is gone and the shapes read.
- Small real details: faces with eye whites, pupils and mouths, ears and proper haircuts; belts and buckles, drawstrings
  on tracksuit bottoms, boot soles, toes and laces; zips, buttons, collars, cuffs, chest and sleeve patches; pouch flaps
  and buckles on rigs and plate carriers; two-part knee pads; headset cups and a mic on helmets; a framed Altyn visor;
  a sharper skull mask and gas mask.
- Every outfit option keeps its name, so wardrobe looks and saved operators still work. Each part fits inside the box
  the old one had (details sit in shallow insets): `tools/check_character_bounds.py` checks it against git, and the
  smoke test's hitbox fit still matches. About 1,150 triangles per character at most (was ~480).
- `tools/character_sheet.gd` renders a row of outfits for each character (before/after pictures).

## 0.34.0 (Lively hideout)
The hideout felt dead (owner: "it does feel kinda dead"); he picked all six ideas. Everything here is looks only:
nothing collides, nothing is sent online, the server and headless runs build none of it.
- **The war upstairs**: every 2-4 minutes a shell lands far above (owner: "rare and tied to things"). Grit trickles
  off the roof around you, the hanging lamps swing, the lights dip and stutter and the view jolts a little
  (`scripts/hideout_war.gd`; where the roof is comes from `assets/hideout/roof.res`, baked by
  `tools/hideout_roof_bake.gd`: re-run it after `make_hideout.py` changes the cave).
- **Small things, each heard only near it**: a dripping tap in the washroom, water pipes that knock, the generator's
  fan turning with exhaust and a chug, a rat running under the washroom trough (`scripts/hideout_life.gd`).
- **The crew**: other PMCs living there: one asleep in a bunk (snoring), a cook at the stove, two playing cards in the
  mess, a mechanic at the generator (wrench sounds), one with a coffee by the range. They look round at you as you
  come close (`scripts/hideout_crew.gd`).
- **Traders behind their counters** in the owner's picked looks (Ponta: Old soldier, Big Don: Fixer, Supreme:
  Jeweller, Ming: Showman, Medic: Old doc), each busy with something and nodding when you walk up. Traders and crew
  use their own cleaner model, `assets/models/characters/trader.glb` (32 px a metre, flat clean colours, faces,
  hands, belts, boots), built by `make_character.py`'s `build_trader`; designs in `scripts/trader_looks.gd`, picture
  sheet from `tools/trader_sheet.gd`. Players', scavs' and raiders' models are unchanged.
- **The hideout cat**: a ginger tabby that lives by the stove. It wanders the quarters, sits and washes, loafs,
  naps by the fire and sometimes comes over to you; walk up and press USE to pet it and it purrs
  (`scripts/hideout_cat.gd`). Name to come from the owner.
- **The trophy shelf** beside the STATS board fills up as you play, only from what the profile already keeps: Bon's
  mask (Big Game), a token from each trader past level 1, medals for 1/10/25/50/100 extracts, a cash pile, a jar of
  casings for your raids, a gold wrench for a maxed workbench, folders for finished jobs. Look at one to see what
  it's for (`scripts/hideout_trophies.gd`).
- **Your corner** (owner picked "your corner, unlocked decor"): the bottom bunk at the end of the quarters is yours.
  USE there to pick a poster, flag, rug, lamp, plant and blanket; the first of each is free, the rest unlock with
  milestones (raids, extracts, money made, jobs, trader levels, killing Bon), nothing to buy. Saved with your
  profile like your look, so the same corner in PvE and PvP (`scripts/decor.gd`, `scripts/hideout_decor.gd`,
  `scripts/decor_picker.gd`).
- New sounds (all added, none changed): shell_far, grit, drip1/2, pipe_knock, generator, rat, snore, wrench, purr, meow
  (`tools/make_sounds.py` `main_lively`).
- Tools: `tools/hideout_life_view.gd`, `tools/hideout_cat_view.gd`, `tools/hideout_trophy_view.gd`,
  `tools/hideout_decor_view.gd` take screenshots.

## 0.33.7 (Riptide: the quay edge, the stern door, more ways below, on the branch)
- **The quay edge isn't one line of containers** (owner: "one dimensional"): each piece of cover along it is now one
  of eight kinds in a mixed order (`quay_cover`): containers (some doubled), blast walls with a blown-out notch,
  stepped crate stacks, watchman's huts you can go in, pipe piles, a wrecked lorry cab and its load, broken concrete
  slabs, cable drums and barriers.
- **The flickering stripe down the middle of the port is gone**: it was the seam between the ground's two halves at
  z 0; the ground is one piece across now.
- **The stern door sits at the barge's height** (owner: a hole in the hull under the water with a ramp in it): the hull
  is shut below the waterline, the ramp stays inside and a bridge plate crosses to the barge.
- **Four more ways down a floor** (owner: one side of the ship had no way in): a ramp through the deck into the
  hold's sea-side passage aft and another into the port-side passage forward (`COMPANIONS`), and a hull door off the
  launch and off the tug onto a landing with a ramp down (`BOAT_DOORS`). The AI can walk all of them.

## 0.33.6 (Riptide: swimming, on the branch)
- **You can swim** (owner: "swim slowly to a ladder"). Riptide's sea is deep water (`scripts/swim_zone.gd`,
  `Player._update_swim`): fall or jump in and you float with your head out and paddle at 1.6 m/s (walking is 3.1).
  No sprint, jump, crouch, gun, meds or looting while you swim, and the drop into the water doesn't hurt. Players
  only: the AI never goes in, but it sees and shoots swimmers as usual.
- **15 ladders out of the sea** (place `Water`): five up the quay (gaps cut in its parapet), the pier, the pontoon,
  the mole, three on the barges, the launch, the tug, the stern dinghy and the pilot cutter. A low sea wall rings
  the far water so nobody swims off the map. `tools/riptide_swim.gd` swims to every ladder and climbs out.
- Touch: nothing new to press (the stick swims, walking into a ladder grabs it).

## 0.33.5 (Riptide: the storm, on the branch)
- **Riptide is stormy** (owner OK'd): its own look, `assets/looks/storm.tres` (dark overcast sky, a weak cold sun,
  sea haze), picked by the map's `look` metadata; Frontlines keeps late afternoon. **Rain** (`scripts/rain.gd`, the
  map's `rain` metadata): streaks round the camera that stop under a roof, and a rain loop that drops low indoors
  (new sound, only added: `ambience/rain.wav`). Looks and sound only: never on the server, and the AI sees and
  hears as before.

## 0.33.4 (Riptide: Zero and his loot, on the branch)
- **Zero is his own boss** (`scenes/boss_zero.tscn`, on Bon's scene; a map's `boss` can name its `scene`). He fights
  like Bon (the AI is locked in) but carries the **Reaper** and wears **Assault Armor** and an **Assault Helmet**,
  and his guards are "Zero's Guard".
- **Zero's loot** (owner's list): **The Formula** (legendary, $100,000), the **Reaper** (epic rifle on Hound rounds,
  $30,000: damage 30 vs 28, 650 vs 600 rpm, a little less spread and kick, takes the Hound's parts), **Assault Armor**
  (0.5, $35,000), **Assault Helmet** (0.55, $25,000), **Raid Pack** (7x6, $18,000). Only off Zero: never in crates,
  crafts or traders. Icons are gray-box stand-ins (the Reaper uses the Hound's model for now).

## 0.33.3 (Riptide: 15-minute raids, the sub bay's power, on the branch)
- **Riptide raids last 15 minutes** (owner OK'd, 2026-11-09). A map can now tune its raid through `raid` metadata
  (`RaidMap.load_map`), like `spawner` tunes its AI. Frontlines stays at 10.
- **The sub bay needs power** (owner: "sub bay + alarm yes"): its extract stays shut (red) every raid until someone
  throws the power switch in the engine room (Hull B, by the stern, `scripts/map_switch.gd`). That opens it and sets
  off a klaxon over the switch and the sub bay for ~15 s, and every scav in earshot comes to look. It's never one of
  the random open extracts (`ExtractZone.needs_power`). New sounds (only added): `alarm.wav`, `power_on.wav`.
  Solo only for now, like Riptide itself; online it will need the server to throw it for everyone.

## 0.33.2 (Riptide: extracts and the moon pool, on the branch)
- **Extracts are harder to camp** (owner, 2026-11-09). The cove is a nook in tall rocks, the road-out gate is a
  walled truck bay with containers across the road in front, the boathouse has screens inside so neither its doors
  nor the water side look onto the zone, the bow pilot boat (now a cutter level with the pad) and the stern dinghy
  are covered. Every extract but the gate now has a spot inside that no outdoor spot can see (`tools/riptide_sight.gd`
  reports it); spots that can see into the zones from 8-150 m: cove 87 -> 1, gate 130 -> 11, boathouse 64 -> 35.
- **The way down to the lab is the moon pool now** (owner: "not a huge staircase, endlessly turning corners"): an
  open well through the whole ship, from the drill floor to the bottom of the hull, railed on every deck, then one lap
  of long ramps (each a different slope) round the walls of the trunk below, open to the middle so you see who's
  above and below; a side pod halfway; the riser (the drill pipe) down the middle with a catwalk out to it and a
  ladder down it, the fast and exposed way (until the lift is built). The trunk opens wide onto the dock. The old
  moon pool stairwell and the lift's placeholder ladder are gone; the drill floor is a ring round the well.

## 0.33.1 (Riptide v3: cover and a bigger port, on the branch)
- **The port is rebuilt** (owner, 2026-11-09: "too open, too small, more cover, tall buildings, no dying from across
  the map"). The quay now sits 60 m from the ship (was 120 m of open water) and the port behind it is 150 m deep: the
  cannery, fuel depot and lighthouse in the north, the container terminal (staggered stacks 1-3 high, a gantry crane),
  the harbor plaza with the six-floor **Harbor Tower** (two stairwells, closed roof) and the customs hall, the grain
  terminal (a 30 m silo bank, the headhouse), and the shipyard (an unfinished hull on the slipway, the fab shed).
  Transit sheds and a row of containers line the quay, so the ship can't see into the port.
- **Every way across has cover**: a shed on the pier, the breakwater got a wave wall, a signal hut and blocks, the
  barges carry cargo on alternating sides so the way across zigzags. New: the **grain gallery**, a covered walkway
  14 m up from the headhouse to a ship loader tower that steps down onto the deck, and the **pontoon** under it at the
  water (ladders at both ends, and up to the gallery halfway).
- **The ship's deck is broken up**: the **drill floor** (12 m up over the middle, the derrick on it, three ways up:
  two ramps and the moon pool stairs) roofs the midship and splits the deck; pipe racks and containers placed so no
  lane runs its length; cover on the forecastle.
- Measured with the new `tools/riptide_sight.gd`: open-air spots seen from far away (60-260 m) by 30+ others went from
  89% of the map to 9% (the port: 99% to 8%).

## 0.33.0 (Riptide, gray box: built on a branch, not released)
- (The 0.33.x numbers are the map branch's own; main went on to 0.34.0 meanwhile, so Riptide gets renumbered as its
  own phase when it is released.)
- **Map 2, RIPTIDE, as a gray box** (owner, 2026-11-09; plan in the "Map 2: the offshore lab" doc). The ship
  LEVIATHAN off THE LANDING, with SITE ZERO under it. Plain boxes only, to check the layout before any art.
  Generated by `tools/gen_riptide.py` -> `scenes/maps/riptide.tscn` (edit the script, never the scene).
- Four ways across (pier and gallery, breakwater to the bow, barge line to the stern ramp, sea-side boats with
  ladders), several ways up and down the ship (no single lift or stairwell), three ways into the lab, three into
  its core. 6 extracts (2 on the ship: bow pilot boat, stern; sub bay in the lab), 8 player spawns, 36 enemy spots.
- **Map picker** in the hideout (solo only: MAP button beside START RAID). PvP raids stay on Frontlines for now.
- New loot places for the ship and lab (existing items only). `tools/nav_bake.gd` bakes every map.
- Not built yet: swimming, the real lift, the sub bay power switch and alarm, Zero's loot and loadout, the storm
  look, 15-minute raids, online raids on Riptide, the AI on ladders.
## 0.32.3 (Pixel smoke)
- **The smoke over Frontlines' burning wrecks looks like smoke now** (owner: "less blocky and more like smoky", then "a
  bit too real, match the vibe of bloxov"; picked option D of four). The column was see-through cubes; each puff is now
  a flat pixel-art puff that always faces you, lighter on top and greyer below like the blocky clouds, drawn
  pixel-sharp and never turned so its pixels stay square. Same 80 puffs and one draw per column, but 2 triangles a
  puff instead of 12, plus one 16 x 16 picture (`assets/textures/smoke_puff.png`, from
  `art_source/scripts/make_smoke_puff.py`). Its shader is in the title screen's warm-up list. Embers and glow unchanged.
- `tools/smoke_view.gd` takes screenshots of a column (close, across town, from underneath).

## 0.32.2 (Fuller hands)
- **First-person hands are a bit fatter** (owner: "the hands in the first person model are too skinny"): thicker
  fingers (22 mm, were 17), palms, thumbs and wrists, and forearms and sleeves about a fifth wider. On every gun and
  on ladders (`make_hands.py`, `hands.glb`).

## 0.32.1 (Ladders, reworked)
- **Ladders got an overhaul** (owner: "ladder mechanics are ass and need to be overhauled"; the top was weird, they
  grabbed you when you didn't want them, a bit slow, felt dead). On Frontlines' ladders (the barn loft, the woods
  cabin) and every one to come (Riptide).
- **Getting on:** walk straight into one, or press E (your interact key) next to it (a **CLIMB** prompt shows; on phones the USE
  button). At the top, press it anywhere within a meter of the edge, or walk off the edge over the ladder, and
  you're swung round onto it facing it in one smooth move (it used to mean turning round, looking down and walking
  off). Walking past one at an angle, or falling or jumping past one, no longer snaps you onto it.
- **Getting off at the top:** one smooth climb up and over onto the floor, like a vault (it used to shove you).
  At the bottom you step off. Space lets go, pushed back off it, or off to the side holding A or D.
- **Climbing:** a little quicker, **2.8 m/s** (was 2.2), easing in and out instead of starting and stopping dead,
  held steady in the middle of the ladder. Hold **sprint** going down to slide (5 m/s). W still climbs the way you
  look (0.20.13). The view rocks gently with each pull.
- **Hands on the rungs:** both gloved hands grip the rungs and go hand over hand as you climb (in your character's
  gloves and sleeves, `scripts/climb_hands.gd`; new `climb_R`/`climb_L` in `make_hands.py`). The gun is slung out
  of view meanwhile. Other players see you climb too: facing the ladder, hands on the rungs, knees working (worked
  out from where you are, nothing new sent online).
- Tools: `tools/ladder_view.gd` (first-person screenshots on a ladder), `remote_view.gd only=climb`.

## 0.32.0 (Crafting)
- **The workbench works** (owner, 2026-11-09). Walk up to it in the hideout (or tap the new **CRAFT** tab on
  phones) and turn loot you bring home into gear. **Instant** (owner: no timers), with a selector (-, +, MAX) to make
  one or many at once. Parts come from your stash, never free-kit items; plain stacks are used before found-in-raid
  ones, so items a job wants go last. Crafted items are like bought ones: not found in raid.
- **No new items** (owner): every recipe uses and makes items already in the game. Level 1: bandages (2), medkit,
  energy drink, Hound / Wasp rounds (90), Mauler shells (30), Lancer rounds (20). Level 2 ($10,000 + 10 bolts,
  3 wires, 3 scrap): frag grenade, foregrip, suppressor, 4x scope. Heavy armor, the combat helmet and the large
  backpack stay loot-only (owner), so there's no level 3 for now. The list is in `docs/ITEMS.md` ("Crafting").
- **PvE and PvP have their own bench** (it's part of each stash). Online, the server checks every craft and bench
  upgrade (`Crafting.changes` in the hideout check): a craft without its parts, above the bench's level, or a free
  bench level is refused.
- Tests: new `crafting` section (parts taken, refused without parts / above the level / no room, free-kit parts
  ignored, found parts last, the screen's CRAFT, UPGRADE and selector), and the PvP hideout check crafts, upgrades
  and refuses faked crafts. The spent-case sound test no longer fails now and then (its 0.12 s gap is real time,
  so a shot just before it could skip the case).

## 0.31.15 (Trader jobs)
- **19 new quests, called jobs** (owner OK'd the list; Ming has none, owner). One-time side quests that pay money or
  gear but unlock nothing. They're open from the start, next to the level quests; each trader shows one job at a time
  and the next opens when it's done. Ponta 5 (Quiet Work, Long Shot, Gun Show, Powder Keg, Close Quarters), the
  Medic 3 (Restock, Pharmacy Run, Clean Record), The Big Don 5 (Fuel Run, Scrap Collector, Battery Life, Heavy
  Lifting, Long Haul), Supreme 6 (Pocket Change, Paper Trail, Trophy Shelf, Bank Job, Brotherhood Secrets, Below the
  Town Hall). Same rules as before: kills and extracts count once you're out, hand-ins take found-in-raid items, no
  quests for killing players. Names are placeholders.
- **New kinds of quest:** kills with a suppressor on, kills from 75 m or farther, grenade kills, searching something
  in a place (the Pharmacy, the bank vault, the bunker), extracting at a certain extract, and extracting raids in a
  row (dying or leaving starts it again). Online the server decides all of them from what it saw (its own count of a
  suppressor on you, where you and the AI were, which containers it let you open, the extract it accepted).
- **Reward items** (a 4x Scope, Medkits, a backpack...) go in your stash in the hideout; with no room they wait until
  there is. Online the server lets them in for free only for quests you've finished.
- Trader screens show "JOB x OF y" above the level quests; the quest board, records screen and pause-menu tracker
  list the jobs too.

## 0.31.14 (More sounds)
- **New sounds only** (owner: "do all of it", and none of it too loud, since you mostly want to hear other people
  and the AI). Nothing that was already in the game changed; 21 new files from `tools/make_sounds.py` (`main_more`),
  in the same synthesised style as the rest.
- **Armor and helmets:** a short clink on the plate when a hit is stopped (a touch louder on the helmet), and
  a crack with bits rattling when that hit wears it out. Only you hear your own.
- **Grenades** clunk as they land and bounce (heard 30 m, softer as they slow), so you hear one coming.
- **Downed and revived:** a body drop when you (or a teammate, heard where they are) go down, a cloth-and-bandage
  sound when a revive starts (on both sides), and a swish and a boot planting when you're back up.
- **The world's life:** crows caw now and then from the flock nearest you, the officer's flag flaps when you're
  close, cans and bottles clink when kicked, shot or bouncing (at most three a frame), hanging lamps creak when set
  swinging, curtains swish as someone pushes past. All looks-and-sound only, never on the server. (Bushes already
  rustled under your feet since 0.20.0.)
- **Spent cases** tink on a hard floor after you fire (softer on the ground, none in water; the Mauler's shells lower
  and softer). Yours only, at most one every 0.12 s.
- **Your body:** a soft breath when your stamina is low (a little louder when worn out), and a soft heartbeat under
  30% health. Owner asked these only if they fit the style: they're quiet, short and synthesised like the rest; easy
  to drop if they don't.
- **Repairs:** a wrench ratchet with the buy sound when a trader fixes your gear. **Keys:** a small snap on a key's
  last use.
- The new sounds roll their pitch on their own dice (`WorldSounds.rng`), so they don't shift the game's seeded rolls.
- Tests: an armor hit clinks and a wearing-out one cracks, a grenade clunks on landing, your case tinks on a wood
  floor, the heartbeat plays when badly hurt.

## 0.31.13 (Free camera: no scouting)
- **The free camera can't be used to scout** (owner: "make sure it's not exploitable"): it stays within 25 m of
  your character, stops at walls, doors, windows and the ground (sliding along them), and only goes where your
  character is still in sight, so no flying round a corner or in through a door to look for scavs or loot.
  (Online it stays off, as in 0.31.12; hide HUD is looks-only and gives nothing away.)
- Smoke test: the 25 m limit, a wall it can't pass, no moving out of sight.

## 0.31.12 (Recording tools)
- **Clips for videos** (owner): two new keys, both rebindable in OPTIONS (a new "Recording" group) and both in the
  raid's pause menu as buttons for touch screens:
  - **Hide HUD (F1):** everything off the screen but your first-person view, for clean footage. Works in any raid,
    solo or online, and while spectating a teammate. On touch, nothing is drawn but a faint pause button; every
    button still works where it was, and the pause menu's SHOW HUD brings them back.
  - **Free camera (F2, solo raids only):** fly round the raid. Move keys fly where you look, jump / crouch go
    straight up / down, sprint goes faster, the mouse wheel picks the speed (1 to 20 m/s), aim zooms in, and moves
    and turns ease in so clips come out smooth. **T** cycles slow motion, stopped time and back. Your character
    stays where you left them (shown as the body other players see, in your wardrobe outfit), takes no input and
    can still be shot. Touch: the stick flies, drag to look, UP / DOWN / SLOW buttons, CAM to come back.
    Online it's off: it would let you see round walls and corners (the Checkpoint rules).
- `tools/free_cam_view.gd` takes screenshots of it. Smoke test: the free camera flies while you stay put and can't
  shoot, touch looks turn it, slow motion / stop, and everything is put back after.

## 0.31.11 (Tutorial on phones)
- **The new-player tutorial runs on phones** (owner): the hideout walk no longer skips touch screens. Its steps
  name the on-screen controls (left thumb to move, drag to look, USE, MENU, FIRE, the range's pause button,
  < HIDEOUT) and switch between key and touch wording the moment the controls do (touch-screen laptops).
  SKIP TUTORIAL no longer starts a look drag when tapped.
- Raid tips: the search and movement tips have touch wording too (USE, BAG, JUMP, hold CROUCH to go prone).

## 0.31.10 (Sign in first)
- **PvP before signing in, the stash is covered** (owner): no moving, selling or buying with a stash that isn't
  yours yet, just "Sign in to use your PvP stash" and a SIGN IN button.

## 0.31.9 (Account button)
- **ACCOUNT / SIGN IN button next to the PvE/PvP switch** (PvP only, owner): opens the account page (sign out,
  download your data, delete) or the sign-in page, without going through the queue panel.

## 0.31.8 (One switch)
- **No separate ONLINE button** (owner): the PvE/PvP switch decides. In PvE, START RAID is a solo raid; in PvP,
  START RAID asks you to sign in, then opens the queue and party panel (and shows where you are in the queue).
  TAKE FREE KIT in PvP puts the kit on and opens the queue.

## 0.31.7 (Confirm password)
- **CREATE ACCOUNT has its own page** with a confirm-password box (owner); SET NEW PASSWORD asks twice too. Passwords
  that don't match are caught before anything is sent.

## 0.31.6 (fix: 0.31.5's checks)
- The server no longer prints an error each time it skips a player who dropped out of a raid (it failed the CI
  checks, so 0.31.5 never went out; 0.31.6 is 0.31.5 plus this).

## 0.31.5 (Stash update, step 4: reconnect, bans, your data)
- **2-minute reconnect in PvP** (owner, 2026-11-04): if your connection drops mid-raid, the server keeps your place
  (your body stays and can still be shot) and the game reconnects by itself and carries on where you are, with the
  same kit. Not back within 2 minutes, or killed meanwhile: the raid is lost, as before.
- **Bans** (24 hours, then 7 days, then for good, owner): an account the anti-cheat kicks twice in a day is banned;
  the owner can ban, unban or look up an account with `server/src/admin.js` (`heroku run`). Banned accounts can't
  sign in and are told until when.
- **DOWNLOAD MY PvP DATA** (ONLINE > PvP ACCOUNT): everything the database keeps about your account, as a file.
  The privacy pages say so; the store privacy form answers are drafted in `docs/STORE_PRIVACY_FORMS.md`.
- Smoke test: reconnecting carries on in the same raid; shot dead while away is lost; the data download; two kicks
  make a ban. Stash API tests: unban, find, the export never has a password or token.

## 0.31.4 (PvP for everyone, server-counted quests)
- **The PvE/PvP switch is on for everyone** (owner): plain bloxov.com has it, no `?pvp_stash` needed. PLAY / PvE
  stays your stash on this device; ONLINE switches to PvP, asks you to sign in or make an account, and opens your PvP
  stash (its own starter kit) and the queue.
- **PvP kill and extract quests are counted by the server** (owner: make what was still trusted server-side): the
  server counts each player's AI kills (and the gun) and moves the quests when they extract; the game can no longer
  report its own quest progress.

## 0.31.3 (Stash update, step 3: cheat-proof PvP hideout, sign-in flow, privacy)
- **The server checks every PvP hideout change** (`OnlineProfile.audit`): money, items, trader levels, repairs,
  stash rows and quests must add up to real buys and sells at the server's prices, starter kit stays unsellable, and
  found-in-raid marks can't be made up. A save that doesn't add up is refused and the hideout goes back to the
  server's copy.
- **Ming's boxes are opened on the server** in PvP.
- **ONLINE asks you to sign in**: pressing ONLINE switches to PvP, opens sign in / create account (or resumes a
  remembered session), then shows your PvP stash and the queue. New **PvP ACCOUNT** button on the online panel.
- **Privacy**: the in-game PRIVACY page and a new public page (`bloxov.com/privacy`, with a #delete section for the
  store forms) say what the PvP account keeps, how long, and how to delete it.
- Fix: the test run no longer crashes Godot as it quits (it failed the Windows CI check on 0.31.2).
- Smoke test: new `pvp_hideout` section (made-up money, items, levels, free repairs, found marks and quests are refused).

## 0.31.2 (Stash update, step 2: PvP accounts and the online stash)
- **PvP accounts** (still behind `?pvp_stash` until they go live): CREATE ACCOUNT (username + password, 10+
  characters; no email), SIGN IN, remember me (`SessionStore`), one session per account with **TAKE OVER HERE**, a
  one-time **recovery code** (shown once, "I saved it") and FORGOT PASSWORD?, SIGN OUT, and DELETE PvP ACCOUNT (type
  DELETE; 30-day grace, signing in cancels it). The PvE stash is never touched by any of it.
- **The Stash API** (`server/`, Node + Postgres): accounts, scrypt password hashes, hashed session tokens and
  recovery codes, lockout after 10 wrong passwords (15 min), bans (24 h, 7 days, for good), the 30-day delete and
  the 12-month inactive sweep, and the online profile with a revision check. Runs beside the game server on
  127.0.0.1 only when Heroku Postgres is attached (`server/start.sh`); its tests run in CI against a real Postgres
  (new job `stash_api`, the Heroku deploy waits for it).
- **The game server keeps the PvP stash** (`scripts/net_accounts.gd`, `OnlineProfile`): the signed-in player's
  profile lives on the server and is saved through the API after every change. As a raid starts the server **issues
  the kit** from the saved loadout (the game's own kit list no longer counts for PvP players) and saves the gear as
  at risk; dying or leaving saves the loss; extracting saves what came out, and coming out with more than the server
  counted is a strike. A raid lost to a server restart gives the gear back (owner, 2026-11-04).
- **PvP has no START NOW** (owner): PvP raids only come from the queue, with other players.
- Still on trust until the server runs the hideout (plan Phase 3): buys, sells and moves in the PvP hideout are sent
  as a whole profile and only checked for shape (real items, sane sizes). The server keeps its own raid stats.
- Smoke test: new `pvp_accounts` section (server + two players + an in-memory Stash API).

## 0.31.1 (PvP starter kit: 3 Stingers)
- The PvP starter stash has 3 Stingers, not 5 (owner): one worn, two in the stash. Still 3 Hounds and 250 Stinger
  rounds.

## 0.31.0 (Stash update, step 1: the PvE/PvP switch, hidden)
- **First step of the Stash update** (`docs/STASH_UPDATE_PLAN.md` Phase 1). Players see no change: the switch is
  hidden until PvP accounts go live. To try it, add `?pvp_stash` to the game's address (or `-- --pvp-stash` on
  desktop).
- **Two stashes.** `Profile.mode` is SOLO (the PvE stash: today's save on this device, unchanged format) or ONLINE
  (the PvP stash). `Profile.use_online` / `use_solo` swap them; saving while in PvP only writes the solo save's look
  and tutorial (account-wide), never PvP money or items.
- **The PvP starter stash** (`Profile.pvp_start_data`, plan §4.6): $50,000, 3 Hounds, 5 Stingers, a red dot, foregrip
  and extended mag per Hound, a suppressor, 360 Hound and 250 Stinger rounds, 5 bandages, 2 medkits, 3 energy drinks,
  a small backpack, and one ready kit worn (light armor, old helmet, medium backpack). For now PvP is a preview of it,
  never saved.
- **Hideout:** a `PvE · SOLO` / `PvP · ONLINE` button next to OPTIONS. START RAID and the free kit raid only from PvE,
  ONLINE only from PvP. Switching to PvP shows the sign-in panel (username, password, SIGN IN / CREATE ACCOUNT) with
  the "your current stash is now your PvE stash" message; it doesn't sign in yet.
- **Save backups are always the PvE stash**, even made or loaded while in PvP.
- New `SessionStore` (`scripts/session_store.gd`): the remember-me session for PvP sign-in, kept in
  `user://session.json` and localStorage. Not used yet.
- Smoke test: new `stash_modes` section.

## 0.30.9 (Server without graphics: 4 raids at once)
- **The online server now runs a stripped build with no graphics in it.** Godot's dedicated-server export (new
  preset "Server", *Strip Visuals*) swaps every model, texture and material for a placeholder (meshes keep their
  bounds), and the Dockerfile now builds that 10 MB pack and runs it instead of the whole project folder. The server
  never drew anything, so nothing about the game changes.
- Measured with real raids (six players and two minutes of AI each): idle server 202 -> 167 MB, one raid 399 -> 236 MB,
  three raids 549 -> 376 MB, four raids ~440 MB.
- **So the server takes 4 raids at once again** (`MAX_RAIDS` back to 4 from 0.30.5's 2) and still fits Heroku's
  512 MB Basic dyno with room to spare: up to ~24 people raiding at once.
- New CI check: `tools/server_pack_check.gd` exports the server pack and runs four busy raids inside it, failing on any
  error, so server code that would need a real model is caught before deploy.

## 0.30.8 (Smooth loading: everything is built behind a loading bar, not while you play)
- Owner: "people keep lagging when entering the game, in the hideout, and in raid... I want a way more clean
  experience loading on to the site, getting in to the hideout without any lag". Measured on a web build: the lag
  was the game building its graphics (shaders) while you were already playing. The title screen built them one a
  frame while you clicked round it (choppy for ~10-25 s on a first visit or after an update), the hideout's were
  built for the raid's sunlight, so the hideout built them all again as you walked in, and on LOW graphics the raid's
  were built for sun shadows LOW doesn't have.
- **The title screen opens with a loading bar** where PLAY and the buttons go, picking up from the web page's red
  bar ("GETTING READY", or "FIRST-TIME SETUP: GETTING THE GRAPHICS READY" the first time). Behind it the game builds
  the raid's and the hideout's shaders as fast as the machine allows (quick once the browser has built them before),
  then loads the hideout. Then the buttons fade in and the picture starts drifting: nothing is left to build. On a
  test web build the title had 14 hitches while its buttons were up before; now none.
- Each shader list is built under its own light: the raid's with the raid's look and the graphics setting's sun
  shadows, the hideout's underground with the hideout's own light (`Look.hideout_environment`, used by both).
- **Walking into the hideout** (from PLAY or back from a raid) fades in from the title picture once it's drawing
  smoothly, so its first frames' setup is hidden.
- **The raid's loading picture stays up until the raid draws smoothly** (12 frames in a row with no hitch, at least
  0.8 s as before, at most 8 s), instead of lifting after a fixed 0.8 s while the raid was still setting up.
- Tests: the title's buttons are up and the bar is gone once everything's built (headless), the hideout's light comes
  from one place, the loading covers lift within their limit.

## 0.30.7 (Player history)
- Owner asked for a history of how many people have been online, numbers only. With the `STATS_URL` setting on
  Heroku, the server now posts its counts (online, in the hideout, in raids, raids, version) every 5 minutes to a
  free Google Sheet (`tools/player_history.gs`, steps in `docs/PLAYER_HISTORY.md`). No names or addresses. Unset =
  nothing is sent. Nothing changes for players.

## 0.30.6 (Server: raids share the map's collision triangles)
- **Each online raid now uses ~10 MB less memory on the server.** Every raid kept its own copy of the map's solid
  triangles (`BoxMap.collision_faces`, ~909k corners, ~10 MB on Bloxov Frontlines) even though the collision shape
  itself was already shared (0.29.3). They now point at one copy kept with that shared shape. Nothing changes in game.
- Measured headless with real raid worlds: 3 raids 467 -> 443 MB (Godot static memory), 6 raids ~756 MB in all. Where
  the rest goes is in `docs/HOSTING_CAPACITY.md`.

## 0.30.5 (Server fits its dyno: two raids at once)
- **The online server now runs at most 2 raids at once (was 4).** Each raid is its own copy of the map on the server
  (~77 MB each on top of ~307 MB), so a 3rd raid would push Heroku's 512 MB Basic dyno over its memory limit and get
  the whole server restarted, dropping everyone. A 3rd group now waits in the queue until a raid ends. Measurements
  and the plan for more players (a VPS with several server processes) are in `docs/HOSTING_CAPACITY.md`.

## 0.30.3 (Sound 2.0: the ambience dips in a fight, and two sounds find their bus)
- **The ambience now ducks in a fight.** Any shot you can hear within **50 m** (your own, a scav's or another
  player's) takes the raid's wind, woods, water and room tone down **5 dB** for **4 s**, ramping over a quarter of a
  second. Someone else's footsteps within **8 m** add a shorter **-2.5 dB** dip on top, so they stand out over the wind.
  Rumbles keep their own level; the hideout's bunker beds do not duck.
- The timer is real seconds and runs from the player's own frame, so opening the menu pauses it, and it is cleared when
  you leave a raid.
- **The clock ticks and the hideout doors were on a bus that does not exist** (`SFX`), so they silently fell back to
  Master and ignored the MIX settings and the indoor echo. They now use `World`, like every other world sound. No bus
  was added (the layout still has Master, World, Voices, Ambience and UI).
- Tests: a near shot sets the duck and a far one does not; the duck reaches -5 dB and is back after ~4 s of simulated
  frames; a close enemy step dips it and a far one does not; clock ticks and hideout doors are on the World bus; there
  is no `SFX` bus.

## 0.30.2 (Hideout ambience: a steady underground bunker)
- The hideout's background sound was remade (owner: it sounded like the ocean). The three beds are now a **deep room
  rumble**, a **low ventilation rumble** and a **steady 50 Hz electrical hum**, all at the same quiet levels. The old
  surf-like swell, the vent hiss and the generator chug are gone.
- **All the random one-off noises are gone**: drips, pipe ticks, creaks, the far clank, vent breaths, falling dust and
  the occasional war rumble. The three beds are steady and of different lengths, so the loop still does not line up.
- Removed the nine unused one-off WAVs and their generator code.
- Next, planned in `docs/SOUND_2_PLAN.md`: 0.30.3, the ambience ducking in a fight and the two sounds on a nonexistent
  `SFX` bus.

## 0.30.1 (Sound 2.0: through a wall, a floor, or round the doorway)
- Sound 2.0, step 2: **through-the-floor** and **behind-you** versions of every gun's shot (10 new files in
  `audio/guns/`), made from that gun's own file. The floor one is a low thud with no crack; the behind one takes about
  4 dB off above 4 kHz. They are -2 dB and -1.5 dB against the base, as planned.
- **What is in the way is now known**, not just "something": `Hearing.block_of()` tells a wall, a floor/ceiling, a shut
  door and a whole window pane apart (doors and panes used to be acoustically invisible to the old single ray), and a
  five-ray fan finds the **opening** sound comes round.
- A shot through an opening uses the normal distance version, 3 dB down and 20 ms late; a wall/door/whole pane uses the
  far version (the room version indoors) with today's -5 dB. A shot from behind you, up close outdoors, is a little
  duller.
- **Gunshots are no longer muffled twice**: the muffle is baked into the variant file, so desktop and web hear the same
  thing (`Hearing.RUNTIME_MUFFLE` keeps the old filter one line away for an A/B). Footsteps and impacts still use the
  runtime filter for now.
- Tests: the new gap check and the older lost-close AI check now build their walls between the actual positions (and
  the box checks use a fixed probe camera), so neither flakes.
- Next, planned in `docs/SOUND_2_PLAN.md`: the ambience ducking in a fight, and the two sounds on a nonexistent `SFX`
  bus.

## 0.30.0 (Sound 2.0: the same shot near, far and indoors)
- Owner's Sound 2.0 brief, first step: each gun's shot has a **mid**, **far**, **indoor** and **indoor-far** version,
  made from that gun's own file by `tools/make_sound_variants.py`. No new recordings and nothing replaced: up close
  it is still today's sound, untouched. The variants are RMS-matched to it, so the existing distance attenuation still
  decides loudness instead of quietening a shot twice.
- **The Stinger has its own shot** (it played the Hound's file until now), so every gun is distinguishable by ear.
- Baked into the files, not filtered at runtime: the web build skips bus effects, so the room tail and the distance
  colour are in the WAVs and desktop and web hear the same thing (owner's call).
- A shot picks its version once, when it is fired, so nothing changes mid-flight: your own shot is the indoor one under
  a roof, and shots from AI or other players use the distance to your ear (mid past 20 m, far past 50 m).
- Next, planned in `docs/SOUND_2_PLAN.md`: through-the-floor and behind variants, sound through openings, and the
  ambience ducking in a fight.

## 0.29.15 (Housekeeping: the AI editor plugin)
- `addons/godot_ai_bridge/` (the local editor plugin that lets an AI drive Godot over a WebSocket) is ignored by git
  in `.gitignore` instead of only in this machine's `.git/info/exclude`. It is editor tooling, not part of the game,
  it has no licence file to redistribute, and it opens a local server; a fresh clone or a reset can no longer bring
  it back as an untracked folder. Reinstall it on a new machine when it is needed.

## 0.29.14 (Moving parts on the game's clock)
- Fix: the moving parts (clock pendulums, weathervanes, the porch swing, crane hooks) ran on the wall clock while the
  game's own time stopped behind the pause menu, so they jumped to a new position when you closed the menu. They now
  run on the game's clock like everything else.
- The smoke test's pendulum check sampled a fixed number of frames instead of real time; because the test runs faster
  than real time it caught the pendulum at the bottom of its swing and failed at random (seen while re-checking 0.29.13).
  It passes every run now.

## 0.29.13 (Housekeeping)
- `brag-output/` (the local capture/recording scratch folder: reels, screenshots, temp userdata) is ignored by git
  instead of showing up as untracked.

## 0.29.12 (Sharp loading screen)
- Owner: the loading screen's text looked low quality. The web page showed the poster with its lettering baked in,
  shrunk to the boot splash's 1280 px and then stretched back up by the browser, so it went soft twice. The page now
  shows the full-size poster with the lettering painted out (`web/brand/splash.jpg`, a smaller download than before)
  and lays BLOXOV, the red bar, NO MAN'S LAND and the gold line over it as a vector picture
  (`web/brand/splash_text.svg`), so the text stays pixel-sharp at any window size and on high-DPI screens. Same
  layout and look; made by `tools/make_web_branding.py --splash`, swapped in by `tools/web_seo.py`.
- The loading bar sits just under the gold line instead of over it on wide windows.

## 0.29.11 (Touch: walking and looking at once no longer jumps)
- Owner, on a phone: walking with the stick while dragging to look made the view freak out. The browser build works
  out each finger's movement against the wrong finger when two are down (Godot 4.7's web touch code keeps the last
  positions by order in the event, not by finger), so the look finger's moves were measured from the stick thumb.
  The touch controls (raid and hideout) now track each finger's last position themselves, and a single jump bigger
  than a quarter of the screen is ignored.

## 0.29.10 (Touch controls: the hideout, and a bigger HUD on phones)
Owner: "finish mobile for now". The two things 0.29.9 left:
- Walking round the hideout by touch (`scripts/hideout_touch.gd`): the same stick and look drag as the raid, JUMP
  and CROUCH (hold = prone), and the hideout's own USE and MENU buttons (they read just "USE" / "MENU" with touch).
  Phones now start in the walkable hideout like computers do (they used to open straight on the menu, which can't be
  closed there any more); the menu's phone tabs stay as a shortcut. Darts get a THROW button (hold to wind up, let
  go to throw); the shooting range uses the raid's touch controls (its pause button brings back the gun picker).
- On small phone screens the hotbar, health and ammo are drawn bigger (by the same amount as the touch buttons),
  each growing from its own corner. Computers and big screens are unchanged.
- The new-player tutorial still skips phones (its steps talk about the mouse and keys; rewording it for touch is
  its own job).
- Checked: smoke test (the hideout section walks and turns by touch), and a phone-sized web export in Chromium:
  the hideout walk, turning, MENU, and the bigger raid HUD.

## 0.29.9 (Touch controls)
Owner: build the mobile controls now, so they're ready (and work on touch screens in the browser). Follows the
mobile plan the owner OK'd: every feature kept, buttons merged. Mouse and keyboard play doesn't change at all.
- On phones the touch controls are always on. On a computer they turn on the first time the screen is touched and
  off again with a mouse click or a key (touch-screen laptops work either way). `scripts/touch_controls.gd`,
  settings and on/off state in `scripts/touch_input.gd`.
- Left thumb: a stick that appears where you put it down; push it past the edge going forward to sprint.
  Right thumb: drag anywhere to look (holding FIRE looks too, so you can aim while shooting).
- Six fight buttons: FIRE (hold; also aims down sights while held, can be turned off), AIM (tap on/off, CANCEL
  while a heal can be stopped), RELOAD, JUMP (vaults, climbs and lets go of ladders where it can), CROUCH (tap;
  hold = prone), ITEM (a quick wheel of every med, drink and grenade you carry, plus the knife).
- Only when they apply: USE (hold to search, open, unlock or revive) and LEAN left/right (next to cover by
  default; "always" or "off" in the pause menu). The hotbar slots take taps too: guns, meds, quick item, knife.
- Top edge: pause, BAG (inventory) and MAP (the full map, which shows the extracts).
- Pause menu (touch only): "Aim while holding FIRE", lean buttons, and TOUCH LAYOUT: drag any button to move it,
  make it bigger or smaller, or hide it; saved with the settings. On small phone screens the buttons are drawn
  bigger so they stay a comfortable thumb size.
- Prompts and raid tips name the touch buttons instead of keys while touch is on ("USE", "BAG").
- Checked: smoke test section `touch`, and a real web export in Chromium with a phone's touch screen and a
  touch laptop (walk, look with a second finger while walking, fire, pause). Screenshots: `tools/touch_view.gd`.
- Not yet: the hideout walk still opens straight on the menu on phones (moving round the hideout by touch is next),
  and the rest of the HUD (hotbar, health, ammo) isn't scaled up for small phones yet.

## 0.29.8 (Trees built while you're in the hideout)
Owner, after the loading fixes: "if we can build the trees faster then yeah do that". The raid no longer builds the
map's 8,089 trees while it loads (~1.3-1.9 s natively, more on the web): the hideout builds them a few milliseconds
each frame while you're there (`scripts/tree_prebuild.gd`, ~8 s of hideout time natively), and the raid only puts
them in place (~7 ms). Leave sooner and the raid finishes the rest; later raids in the same session reuse them.
- The map's tree list is now its own small file, `scenes/maps/old_bloxov_trees.tres`, written by the generator
  beside the map (the hideout reads it without loading the whole map).
- The exact same trees: checked vertex by vertex against 0.29.2's (`tools/tree_probe.gd` builds them both ways).

## 0.29.7 (The Big Don)
Owner: the supplies trader goes by "THE BIG DON" now. His trader screen title, the "SELL TO" header, the quest
board and quest tracker, and messages (bought, sold, repaired, level up) say "The Big Don". Short trader tabs,
buttons and lists keep "BIG DON" so they still fit on phones. `Traders.title(id)` gives the long name (a trader's
`"title"`, else its `"name"`).

## 0.29.6 (Updates download only what changed)
Owner: loading is slow, first of all the first load. Every update made every player download the whole game again
(~107 MB, ~60 MB compressed): the game data was one big pack renamed each update, and GitHub Pages gives every file
a new version tag on every deploy, so even the unchanged engine file was downloaded again after ten minutes.
- The web build's data is now split (`tools/split_pck.py`, run by `cache_bust.py`): a small main pack (scripts,
  scenes, the map: ~8 MB) and nine content packs for the big art (buildings, outdoor pieces, far views, the rest),
  each named by what's in it. `scripts/web_packs.gd` (the first autoload) mounts them before anything loads.
- The page keeps the engine and every pack in the browser's Cache Storage under its content hash. A return visit
  downloads nothing; an update downloads only what changed, usually just the main pack. A changed building model
  re-downloads only its quarter of the buildings. If the browser can't store them (private window, no space), the
  game downloads as before.
- Checked in Chromium on an exported build: first visit downloads everything, a reload downloads nothing, a new
  version downloads only the 8 MB main pack, and the hideout and the raid load and draw normally.
- Desktop and the server are unchanged (one pack as before).

## 0.29.5 (First raid loads faster: shaders built early)
- Owner: "i just want the first time you load into raid not to take so long, it took like 30 seconds first time".
  A browser builds each shader the first time something using it is drawn and keeps it for next time; after the
  Godot 4.7 update nothing was kept, so the first raid built ~390 shaders while it loaded (the second raid was fast).
- Now the game builds the raid's and the hideout's shaders while you're on the title screen and walking round the
  hideout, one stand-in a frame in a tiny hidden view with the raid's light and look (`scripts/shader_warm.gd`).
  Measured in a browser: the first raid now meets 46 new shaders instead of 390. The list comes from
  `tools/gen_shader_warm.gd` (re-run it after adding materials or new kinds of things to the raid or hideout).
- Until a raid has loaded once on this Godot version, the loading screen says "FIRST-TIME SETUP: GETTING THE
  GRAPHICS READY", so a long first load doesn't look stuck (remembered in the browser, web only).
## 0.29.4 (No more reloading on a slow first load)
Found while measuring a real web build for the loading fixes: on a slow load the page reloaded itself right after
the hideout appeared, back to the title screen, and could do it again and again. The one-tab check (TabLock, 0.17.5)
gives the browser 1.5 s to grant this tab the game; loading the hideout keeps the page busy longer than that, so the
timer and the browser's answer both ran late, the timer first, and the only open tab decided another tab had the
game and reloaded. Now the timer asks the browser whether this tab's request is really still waiting before calling
it blocked. A second tab still waits behind the notice as before.

## 0.29.3 (Faster raid loading, part 1)
Owner: "everything is really slow ... loading into raid". The first of a few loading fixes (the shader side is being
done separately). Looks and gameplay are unchanged.
- The map's trees (8,089 of them) are built when a raid loads. That now takes about half as long: the meshes are
  built straight into arrays with four corners a quad, not through a SurfaceTool with six. The exact same trees
  (checked vertex by vertex with `tools/tree_probe.gd`). Measured 2.8 s -> 1.3 s natively; the web is slower, so it
  saves more there.
- The enemy navigation is baked ahead instead of at the start of every raid (~1.3 s, on the server too):
  `tools/nav_bake.gd` saves it in `assets/nav/` under a fingerprint of the map's geometry, and a raid whose geometry
  matches loads it (~0.2 s). A map changed without re-baking just bakes at the start as before; the smoke test
  says so.
- Raids running the same map at once (the server) share the map's triangle collision shape instead of each building
  its own (~0.5 s, which stalled every raid on the server while a new one started).
- Raid scene setup measured 6.2 s -> 2.4 s (xvfb, warm shaders). New measuring tools: `tools/load_probe.gd` (each load
  step), `ready_probe.gd` (slowest nodes), `spike_probe.gd` (slow frames walking the map), `shader_probe.gd`
  (distinct shaders a scene uses).

## 0.29.2 (Bombed roofs look bombed)
Owner, playing 0.29.0: from inside Old House 7 "the roof is broken, you can see through it". Not a bug: the house's south
half has had its roof blown in since the World art update, but from the rooms that still have a roof it ended in a clean
line at the ridge and read as missing roof. The owner picked "make the damage read clearer": along every torn ridge of
the old houses (1, 7 and 8) the blown-off slope's rafters now hang snapped off the ridge beam with battens dangling, and
boards, slates and plaster lie along that side of the caved rooms. Looks only, no collision or gameplay change
(`dress_old_house` / `caved_old_house` in make_building.py; models and far views rebuilt).

## 0.29.1 (Fewer AI join a fight)
Owner, after 0.28.12: "change it to like at most 4 AI from elsewhere, still seems too much". One fight now pulls in at
most 4 AI from elsewhere (was 6); the 45 s quiet reset and everything else stay. `FightBudget.BUDGET`.

## 0.29.0 (Engine update: Godot 4.7)
- The game moves from Godot 4.5.1 to Godot 4.7.2, the newest stable version (owner: being outdated would hurt later
  work). Built and checked on its own branch first: every test section passes on both versions with the same
  results, and screenshots of the map, indoors, first-person hands and the inventory match the old ones.
- Godot 4.7 now builds distance versions (LODs) of the big building meshes, which 4.5 couldn't, so far-off buildings
  draw fewer triangles. The web download is about 7 MB bigger for it.
- Fixed (was in 4.5.1 too, desktop only, never on the web): leaving the hideout within a second or two of entering it
  (START RAID straight away, or quitting) could freeze the game. The map now warms up with Godot's own background
  loader, which never makes the game wait on it.
- CI, the server image (Dockerfile) and the docs use Godot 4.7.2.

## 0.28.12 (Fights stop flooding)
Owner: a friend fighting scavs and raiders in a house near the church had AI "flooding in all across town"; fights
drawing others in is good, but there needs to be a limit. The old cap (at most 4 heading over at once) only counted AI
while they walked over, so once they arrived the next 4 set off, and each arrival called for help again, chaining
outward. Now each fight (a spot, 50 m round) pulls in at most 6 AI from elsewhere in total, whether they heard the
shots, were called over or saw a buddy drop; any more go on alert where they are, looking toward it. After 45 s with no
gunfire there the fight is forgotten and can draw 6 again (owner picked 6 and 45 s). AI that see you still fight you.
Numbers in `scripts/fight_budget.gd` (`BUDGET`, `QUIET_RESET`, `RADIUS`). Smoke test checks it.

## 0.28.11 (Station beam fixed)
Owner: in the train station's waiting room "theres a wood beam near the door from the explosion, its hitbox is really
off blocking you from going through the door properly".
- Fallen beams and roof slabs that lie tilted now block only where they're drawn. Their block used to be as long as
  the whole piece stood upright, so the beam leaning down from the waiting room's ceiling stuck out right into the
  doorway to the booking hall. Now only the low stretch of a tilted piece (lower than your head) blocks you, over the
  floor it actually covers; you walk under the high end. The doorway is clear.
- Same fix everywhere else on the map with tilted wreckage (caved rooms in other buildings, the station's fallen
  slabs and the platform's wrecked canopy): their blocks now match the drawing. Shots, eyes and the AI are unchanged
  (these blocks only ever stopped players).

## 0.28.10 (Leaves come off the trees)
Owner: the falling leaves "look really bad and show up way too often ... make them look more like leaves ... and make
sure they actually come down from trees".
- No more leaves blowing past out of nowhere wherever you are outside. Now and then (one every 4 to 10 seconds) a leaf
  comes loose from a leafy tree within 30 m of you (broadleaf and birch; pines and dead trees don't drop any) and
  flutters down: a little pointed leaf with a stalk, in autumn browns, yellows and a faded green, swinging side to side
  and rocking as it falls, then lying on the ground a few seconds. Away from the trees, none. Paper in town is as
  before. Looks only, never on the server (`scripts/drift.gd`).

## 0.28.9 (Fun room film)
- Owner: "make the projector in the fun room the same as the tv". The movie room's screen shows the TV's changing
  picture now (`scripts/hideout_life.gd`), in place of four painted boxes. The TV's picture was upside down (sky at the
  bottom): fixed too. Looks only.

## 0.28.8 (Hideout: a real stove, curtains that part, signs that hang and swing)
- The mess's stove (owner: the drum "just looks bad") is now a cast-iron pot-belly stove on legs: a door with a grate
  the fire flickers behind, a glowing ash door, a hob with the steaming pot and a kettle, a flue with a damper up into
  the rock, a bucket of ash with a poker and a pile of split logs.
- Curtains and washing (owner: "it should move out of the way when u walk into it", "still one flat color"): they part
  to both sides round you now instead of only bulging, and they're woven fabric with folds, a hem, rings at the rail and
  grime at the bottom.
- The trader signs (owner: "arent even attached properly", "they should like move if u run into them too like sway
  abit"): their cables run up to the tunnel's roof, clipped to the tin; the signs sway a little all the time, nod when
  you walk under, swing when you jump into them, and shots and blasts knock them (`scripts/hanging_signs.gd`). They
  hang 15 cm lower so a jump reaches them. Looks only.
- Fix: the moving parts added in 0.28.0 (weathervane, clock pendulums, porch swing, crane hooks) were missing their
  import settings in the repo, so the live build may have drawn them in the wrong colours. Their settings are in now.

## 0.28.7 (Walk through the crops)
- Owner: "for the farm field, make it like bushes, we can walk through it, slows down movement ... also make that
  physics moving out of the way too". The five crop strips (wheat, maize, sunflowers) are walk-through now: you move
  slower in them, the AI can't see you through them, and the stalks part round whoever walks through, like the
  bushes. Like bushes they no longer stop bullets (they were solid waist-high cover before).
- The solid-looking block under the stalks is gone and the stalks are denser, so walking in doesn't clip through it.

## 0.28.6 (Farm hitboxes: barn stalls and the silo)
- Owner: "inside the barn the little stables that are opened are closed ... lowkey check whole farm". Each stall's gate
  is drawn swung open into the aisle, but an invisible wall closed the stall's whole front and the gate itself had no
  hitbox. Now the gate stops you where it's drawn and the open part of the stall is open, so you can walk into the stalls.
- The silo's hitbox was two crossed squares, whose eight corners stuck about a metre out of the round wall as
  invisible walls. It's a true octagon just inside the drawn silo now.
- Checked the rest of the farm (fences, farmhouse, machine shed, hay, crop rows, both tractors) against what's drawn:
  nothing else was off.

## 0.28.5 (Hideout: texture and life)
Owner: "things to sit on, lights, etc are just so bland we need to give it more texture and life in the hideout too".
- The cave's furniture had flat colours. Now: crates are painted planks with nails, chips and a steel-clasped lid band;
  the mess benches are worn wooden slats; tables, worktops and the war table's door are scratched sheet steel with
  rivets; mattresses are striped ticking with buttons, pillows striped cream; the couch is canvas and worn upholstery;
  duffels and bags are stitched canvas; pipes, drums, rails and scaffold are rusty black iron. Same colours as before,
  now with a surface (no extra materials: it's all one picture).
- Lamps: every bulb sits in a black socket; the tunnels' bulbs have wire cages; the lamps over the war table have green
  enamel shades; the work lamps have a guard over the glass, a handle and a cable.
- A little life (looks only, never on the server, `scripts/hideout_life.gd`): steam off the stove's pot and its fire
  flickering through the vents, dust drifting in the light over the war table, and the TV shows a changing picture
  instead of one blue glow.
## 0.28.4 (Sign backs read the right way round)
- Owner: "need to make sure back of signs are flipped". The Last Stop Motel's road sign, its NO VACANCY board and the
  OFFICE blade sign over the motel office read backwards from behind. Their back faces mirrored the picture on top
  of a mapping that already reads right from either side; both sides now read normally.
- Checked every other sign on the map and in the hideout: the rest were already right (one-sided, or two-sided like
  the station's BLOXOV board and departures board, which were fine).

## 0.28.3 (Hideout: behind the pillars, crouch and prone)
- Owner: "the stone pillars in the corner, i wanna make sure we can get behind them ... just for fun roaming around".
  The two corner rock pillars stood wedged against the tunnel mouths and a sandbag ring. They now stand a little
  further into the cave, and the sandbags behind the far one are gone, so you can walk all the way round both.
- Owner: "allow proning and crouching in the hideout". The raid's keys, speeds and heights: crouch and prone toggle,
  crouching from prone gets you to a crouch, jump stands you up, no sprinting while low, quieter steps crouched and
  none crawling. You can't stand up under something low. Sitting down or stepping up to the darts straightens you up.
- Roadmap: visiting friends' hideouts and hideout customizing are noted as later updates (owner: "add them on to the
  roadmap and we can deal with them when its the right time").

## 0.28.2 (Main screen lettering fixed)
- The 0.27.2 main screen's lettering looked off (owner: "the text looks off and everything"): NO MAN'S LAND and the
  gold line were game text drawn at an odd scale, so their pixels came out uneven on the web, spaced too wide, and the
  gold line ran nearly edge to edge.
- The name, red bar, NO MAN'S LAND and gold line are now one picture lettered like the poster
  (`assets/textures/title_text.png`, made by `tools/make_web_branding.py`), shown at the screen's size: even pixels on
  every screen, tighter spacing, the poster's proportions, and a little more room above PLAY.

## 0.28.1 (No more jams)
Owner: jams "take away from the arcade style of bloxov"; picked "a bit less accurate" instead.
- Worn guns never jam now. Instead a worn gun spreads more, growing with wear up to 20% more when worn out. It
  always fires. The inventory shows it ("Condition 40% (+12% spread)"). Wear per shot and repairs are unchanged.
- The trader screen's note says the repair list includes what you wear.

## 0.28.0 (The world comes alive)
A new update (owner: "anything that should have some sort of animation/life we need to give it", and it should be its
own update). Everything here is looks only: hitboxes, shots, the AI and how the game plays don't change, nothing is
sent online and the game server draws none of it. It's cheap on phones: the wind is in shaders, the moving parts are
a handful of small models.
- **Weathervane:** the rooster on the farmhouse roof turns with the wind, wandering slowly and twitching in gusts.
- **Clocks:** the grandfather clock's pendulum swings again (it used to be stopped), a rod and a bob behind the glass,
  and so does the bell tower clock's. Close up you hear it tick and tock (a new sound; no sound was replaced).
- **Porch swing:** the swing on the brick house's porch sways on its chains.
- **Cranes:** the junkyard crane's magnet and the car on it, and the depot's hand crane and its crate, sway a little.
- **Wind:** power lines swing gently between the poles (most in the middle), tent canvas ripples, and the camo nets
  lift and ripple, least where they're tied to their poles.
- **Wrecks:** the four burning wrecks that smoke now glow at the bottom and throw up embers.
- **Crows:** small flocks circle high over the farm's field, the churchyard and the junkyard, flapping and gliding.
- **Blowing leaves and paper:** a few dead leaves tumble along the wind wherever you are outside, with scraps of paper
  in town; they stop while you're under a roof.
- How it's built: make_building.py takes moving parts out of a building's model into their own small models
  (`assets/models/movers/`, "movers" in `<name>_solids.json`, drawn by `scripts/movers.gd`); swaying outdoor faces are a
  second atlas material (`kit_sway`, `assets/shaders/kit_sway.gdshader`); crows `scripts/birds.gd`, leaves and paper
  `scripts/drift.gd`. New shaders are drawn once at raid start so nothing stutters the first time you see them.

## 0.27.2 (Poster look)
- The owner's favourite picture (brag.jpg, now kept as `art_source/brag.jpg`) is the game's poster: owner, "use the
  brag.jpg for like our main screens like posters title screen etc, i like that picture a lot".
- Main screen laid out like it: the dusk town darkened warm, BLOXOV big in the middle with the red bar, NO MAN'S LAND
  and the gold "A BLOCKY FIRST-PERSON EXTRACTION SHOOTER" line, then PLAY with OPTIONS / PRIVACY / CREDITS in a row under
  it. Drawn live (not the picture itself) so it fits wide phones and narrow screens; the town still drifts behind it.
  OPTIONS, PRIVACY and CREDITS open in the middle, where the name was.
- bloxov.com's loading picture (while the game downloads) and the link preview Discord/Google show are now the
  poster itself (`tools/make_web_branding.py`). The icon/favicon is unchanged.

## 0.27.1 (The officer's flag waves)
- The Exion flag on the officer's house (the big house on the hill) waved about as much as a sheet of plywood (owner:
  "that flag should have like kinda a waving animation instead of being stiff"). It now ripples in the wind: waves
  run out from the pole and grow toward the torn end, with slow gusts, and it sags a little when the wind drops.
  Done in a shader (scripts/flags.gd, assets/shaders/flag.gdshader), so it costs about nothing on phones.
- Its torn edge was on the pole side; it's now the loose end, where a flag actually frays.
- Looks only: nothing about shooting, hitboxes or the AI changes, and the game server doesn't draw it.
- For later flags: make_building.py lists a flag's cloth in the building's `_solids.json` ("flags") instead of
  drawing it in the model, and the generator places it.

## 0.27.0 (Durability)
The Durability update. Owner picked trader repairs (no repair-kit items).
- Guns wear: each shot takes 1 point (Hound 1200, Stinger 800, Wasp 1500, Mauler 300, Lancer 250). Below 60% a
  trigger pull can jam, up to 5% a shot when worn out: a click, "JAMMED" on the ammo plate, and it clears itself in
  0.9 s (no extra button, so it works the same on phones). No round is lost.
- Armor and helmets wear again (the 0.14 code, switched on): Light Armor 60, Heavy Armor 120, Old Helmet 40, Combat
  Helmet 80. Each hit wears off the part it stops; worn gear stops less. A bar on the item shows what's left.
- Keys have uses: bunker key 3, bank vault key 5; the last use uses it up. Keys can't be repaired.
- Guns, armor and helmets found in a raid (crates, bodies) turn up worn, 40-100%. Bought ones are new. Your saved
  gear from before this update counts as new.
- Worn gear is worth less (as armor already was): 30% of its value when worn out.
- Repairs: Ponta fixes guns, Big Don armor and helmets, back to new. A REPAIR list sits above the SELL list on their
  screen (equipped gear included), and right-clicking a worn item in the hideout offers "Repair for $X". It costs 60%
  of the value the wear took off, which is exactly what repairing adds to its sell price, so repairing to sell never
  pays. The money counts as spent with that trader. Repairing never lowers an item's max (owner can change that).
- AI guns don't wear or jam (AI behaviour stays as it is).
- tools/economy_sim.gd prints repair costs per raid; smoke test checks wear, jams, key uses and repair prices.

## 0.26.1 (Hideout lights hung from the roof)
Owner: the lights in the middle of the hideout are "not even attached to the roof".
- The cluster of bulbs over the war table hung from a point in mid-air, 4 m under the rock. It now hangs from a steel
  ring on a cable that runs up into the crown.
- The lamps over the trader stalls, the armory bays and the mess tables stopped short of the tunnel arch; their cables
  now run all the way up to it (the bulbs stay at the same height, and still swing when knocked).
- The strings of bulbs across the hall end on the rock as it's actually shaped (they could stop up to a metre off a
  bump), with a steel eye at each end. Same for the fairy lights over the bunks (now wall to wall) and the string
  lights in the hangout and its loft (now fixed to the ceiling, they were 10 cm under it).

## 0.26.0 (Keybinds)
The Keybinds update (owner: its own small update before Steam). Owner on Ctrl: "on web build dont allow ctrl, cuz u
literally cant crouch and walk then".
- OPTIONS has a Controls list (main screen and the hideout menu): every action with the key it's on. Click one, press
  the new key or mouse button (mouse 4/5 and the middle button work too); Escape or clicking elsewhere cancels.
  RESET KEYS puts the defaults back. Saved with your settings, and a save backup carries them.
- Taking a key another action had swaps them, so nothing is ever left without a key ("Reload moved to G").
- In the browser Ctrl can't be bound: holding it while walking on W is Ctrl+W, which closes the tab, and a web page
  can't stop that. It will work in the Steam version. Also never: Escape, the Windows/Cmd key, the mouse wheel, F3
  and F4 (the game's own), and in the browser F11/F12. Checked in a web export: the game swallows every other key
  (F5, Ctrl+R and Tab don't reach the browser).
- Everything that shows a key follows your keys: the [F] prompt, the map and extract key caps, the hotbar slot
  numbers, the hideout's MENU/LEAVE buttons, the tutorial and raid tips, the inventory hint. Key caps fit any key
  (TAB, SPC, M4).
- Phones: no change (touch controls don't use keys; the list is hidden there).

## 0.25.38 (Quieter hideout ambience that doesn't loop)
- The hideout's background sound was too loud and you could hear it loop (owner). Its room tone was one 6-second
  clip on repeat; it's now three quiet layers (the still air, the vents, a faint hum of lights and a far generator),
  each a different length so they don't line up for many minutes, and each drifting slowly up and down in loudness
  and pitch at random. Over that, every 4-14 s one of eight little sounds plays at a random pitch and loudness: water
  dripping, a pipe ticking or groaning, something metal set down far off, the vents drawing harder (never the same one
  twice running), and sometimes grit trickles from the roof after the war rumbles overhead. All of it is about 5 dB
  quieter than before, and the rumbles 4 dB quieter. New sounds only: the raid's ambience is unchanged.
## 0.25.37 (Hangout smoothing)
Owner: "a gap on the roof showing the cave" over the loft stairs, "I can sit on snack bar chairs from upstairs",
"my head is going through walls and roofs", "lower the noise of the new door... make [its texture] match a bit more".
- The loft's ceiling now runs over the stairwell too: no more cave showing above the stairs.
- Seats and E stations only work on your own floor (station markers carry their floor height now; a seat has to be
  between 0.4 m under and 1.4 m over your feet, a station within 1.5 m).
- The loft has a solid ceiling (a jump used to put your head through it), and the passage's roof box sits as low as
  the arch is near its walls, so a jump there no longer pokes your eyes through the rock.
- The hidden door is much quieter (-20 dB, was -8), and its picture is now the exact concrete of the wall behind it,
  lined up with the wall's board marks and darkened by the same baked lamp light; its edges sit in shadow.
- Smoke test: a jump in the loft stops at the ceiling; no seat or station downstairs is in reach from the loft.

## 0.25.36 (Hangout loft and hidden door)
Owner: "you get stuck on the stairs", "make the roof match the room, I hate how it's cavey... maybe even a second
floor??", "a door that kinda blends in that auto opens to make it more hidden, but I like the spot".
- Stuck on the passage stairs, fixed (two causes): the bottom treads had collision boxes of their own you caught on,
  and walking back up, the armory's floor stuck out 0.1 m over the top of the slope. You walk a smooth slope both ways.
- The rooms have a ceiling now: cream pressed-tin tiles at 3.4 m, the tin walls going all the way up to it, string
  lights and lamps hung under it. No more rock overhead.
- A second floor: steel stairs from the games room go up to a movie loft, with a big screen (the film's on), a
  projector, two couches you can sit on, beanbags, a table football game and its own lamps. The stairwell has a rail.
- The way in is hidden: the armory's end wall is a concrete door painted like the wall round it. It slides aside
  with a heavy rumble as you walk up, from either side, and shuts again behind you. Same spot as before.

## 0.25.35 (Climb through windows again)
Owner: "Vaulting through windows is not working properly now" (online: "i could not vault through the window at all,
i just jumped"); picked "open plain windows too".
- **Plain windows are open to climb through again**: 178 windows in 25 buildings (houses, the school, the town hall,
  the offices, shops, the police and bank upstairs, and so on). Jump at one while walking into it and you vault
  through; a pane still glazed breaks as you go. Since 0.23.3 every window but the motel's stopped players, so Space
  at one just jumped, offline and online alike.
- Still shut (99): anything with something across it (boarded-up windows, the cabins' cross-barred sashes, the bell
  tower's stone tracery, a sign over the glass), barred windows, shop fronts, glass fronts and the church's windows.
  A new tool, `tools/window_audit.gd`, casts rays through every window of every building model and writes what's in
  the way to `art_source/buildings/window_audit.json`; the map generator opens a window only when under 15% of it is
  covered (and keeps any window the audit hasn't measured shut). Re-run it after rebuilding a building model.
- Shots, eyes, the AI and its navigation are as before (window boxes only ever stopped players). The server's
  movement check lets these vaults through (checked in a test online raid).
- Smoke test: on the real map, a vault in and back out through one of the school's windows; a cabin's window and a
  boarded-up one stay shut.

## 0.25.34 (Hangout doors)
Owner: "add doors? custom nice doors they can open... make sure textures don't glitch".
- Both of the hangout's doorways (into the snack bar and the booth room) have a pair of sliding doors: teal tin
  leaves in a steel frame, a lit round porthole, a red stripe, a pull and a kick plate, hung on a steel track over
  the doorway. They slide apart on their own as you walk up (no button, so it works the same on phones) and close
  behind you, with the door sounds.
- The leaves hang a few centimetres in front of the wall, never in its face, so nothing flickers as they slide.
  Looks only and hideout only (`scripts/hideout_doors.gd`); nothing is sent online.

## 0.25.33 (Hangout rooms)
Owner: "having rooms as well? making it sectioned makes it feel cozy almost".
- The lounge is split into three rooms by painted tin walls with doorways (steel posts, a header overhead): the snack
  bar on its own at the far end, the booth room in the side nook, and the games room in between with the pool table,
  the jukebox and a second hanging lamp.
- The four arcade cabinets stand in a row along the booth room's wall, facing the pool table.

## 0.25.32 (Rounder hangout)
Owner: "make it less of a square... I hate when things are fully cubes, feel free to make it a bit bigger too".
- The lounge is bigger (about 8 m from the middle to the walls, was 6.6) and no longer a rounded square: an uneven,
  lobed round room with a nook bulging out on the far side, the tin walls and tiled floor following its shape.
- The snack bar curves round the wall, with five stools and curved shelves behind it.
- The couch is now a round booth in the nook, round a drum table on a round rug, with its own lamp.
- Four arcade cabinets (was two), angled in pairs either side of the stairs; the room is a little taller.

## 0.25.31 (Prone on slopes)
- Prone and downed players on a slope lie along the ground (owner: "why are the legs gone when proning"). The lying
  body used to stay level, so on a hill half of it, usually the legs, sank into the ground. It now tilts with the ground
  under it (up to about 26 degrees along the body, less sideways). The hitboxes tilt the same way on other players'
  screens and in the server's hit checks, so they still match the body you see.

## 0.25.30 (Steadier pace, free kit fix)
- You move about 8% slower (owner: "the character moves too fast"): walking 3.1 m/s (was 3.4), sprinting 5.15 m/s
  (was 5.6), in raids and the hideout. Your speeds hadn't changed since 0.13.5; it felt faster because the AI got 7%
  slower in 0.24.2. You're still a little quicker than scavs (3.35 m/s). Crouch, prone and ladders unchanged.
- The free kit no longer goes missing when something is in your secure pocket (owner: the button sometimes didn't
  show with nothing on you). The secure pocket survives death, so anyone keeping something in it never got the kit
  back. Now only what's equipped, in your pockets and in your backpack counts (once per raid as before).

## 0.25.29 (Every gun its own reload)
- Each gun now reloads its own way in first person (owner: "the sniper has the pistol reload"). Before, every
  magazine gun shared one mag swap, and in the game the gun turned so far over that the hands and mag were out of view.
  - **Hound:** the left hand rocks the curved mag forward out of the gun, hooks the new one in and rocks it home; from
    empty it reaches under to the handle on the right and racks it.
  - **Wasp:** from empty the cocking handle is pulled back and locked up first, the mag swapped, then the handle is
    slapped down; otherwise a straight mag swap.
  - **Stinger:** the gun tips up, the mag drops out of the grip, the left hand brings a new one up from below and palms
    it in; from empty it racks the slide (the slide moves).
  - **Lancer:** bolt-action: the right hand turns the bolt up and draws it back, the left pushes rounds down into the
    open action, then the bolt goes home and the hand goes back to the grip.
  - **Mauler:** shells one at a time as before, now with the gun rolled so the loading port shows.
- Sounds: the same sounds as before, timed to each reload; the Lancer's bolt clicks as it opens and closes.
- The gun models gained a "Bolt" part (Hound and Wasp handles, the Stinger's slide, the Lancer's bolt; make_gun.py),
  so it can move. They look the same. `tools/reload_view.gd` renders each reload in the real raid scene.

## 0.25.28 (Hideout sound, backstabs, range guns)
- The hideout was really quiet (owner). You now hear your footsteps as you walk round it (the raid's steps on
  concrete, as loud and as often, and a thud when you land a jump), a low bunker room tone, and the war rumbling far
  overhead now and then. The radio, when it's on, is heard all over the hideout: loudest beside it, fading gently as
  you walk away (it used to cut out 22 m off).
- Backstabs do a set 100 damage (owner: they showed ~10k, enough to kill anything). Armor takes its share as with any
  hit, so a backstab still kills a scav or an unarmored player outright, but someone in a vest lives through it
  (a Raider in light armor is left on 20). Same online.
- Shooting range: the Hound and Lancer stayed locked after you levelled Ponta up (owner). The range's gun list was made
  once, when the hideout opened; it's now checked each time you step up to the bench.

## 0.25.27 (Map pass: cover and field crates)
- The roadmap's map pass, finished (owner said yes). Most of it was already in from the World art update; a check of
  the map (`tools/sightlines.gd`) found the open hill east of the depot was now the spot that saw the most AI ground
  (111 AI spawn points), so about 70 more pieces of cover went in where they cut the most long views: ruined walls,
  berms, containers and rocks. The east hill now sees 90, and the map's score (each player spawn's worst nearby spot,
  lower is better) went from 534 to 505. Roads, buildings and the layout are unchanged. The hunting stands and the
  climbable roofs keep their views (sniper perches on purpose).
- 10 army crates out in the countryside (owner: loot out there too, but the good loot stays in town): by the hunting
  stands, the derailed train, the east hill and some wrecked trucks and tank traps. They roll a new "field" table:
  only ammo, bandages, energy drinks, food and scrap (about $640 a crate; a town crate is about $2,000). None within
  30 m of a player spawn or 25 m of an extract.
- `tools/sightlines.gd -- plan=N hot=70` also plans cover for any spot that sees a lot, not just ones near spawns.
  The economy sim counts the field crates on their own; raid hauls and kit prices are unchanged (no price change).

## 0.25.26 (Prone stays out of walls)
- Prone (owner picked it): the whole lying body now collides, head to boots, so you can't crawl or turn with your head
  or legs in a wall (others used to see a prone head poking out the far side of thin walls, and could shoot it). You
  only lie down where there's room for your body; with a wall right ahead you stay as you were.
- Prone, your eyes are now in your lying body's head (0.59 m ahead of your middle), so you see from where others see
  you. Hitboxes unchanged.

## 0.25.25 (Hangout down below)
Owner: "the hideout can be a bit closer, so it's easier to find, then make a tunnel to it that goes deeper
underground", and "I like the colour but it looks so flat".
- The hangout moved from past the 100 m range to the end of the armory (the stash's tunnel): its end wall has split
  open onto a rock passage with steel stairs going 4.5 m down to the lounge, lit by bulbs along its roof.
- The range is back as it was before 0.25.17 (full firing line and backstop, end wall closed).
- The lounge has texture now: corrugated tin walls with seams, rivets, rust runs and chipped paint (same red, teal and
  yellow), worn chequered tiles with grout and cracks, felt on the pool table, a tufted vinyl couch, a tin bar front
  and jukebox.

## 0.25.24 (Bodies that move, fix)
- 0.25.22's build stopped on an engine error: the new "feet stay above the ground" step ran on bodies that weren't in
  the world yet (the server measuring hitboxes). It now skips those. No other change.

## 0.25.23 (Icon on Google)
- Google showed a plain globe next to bloxov.com instead of the Bloxov "B" (owner: "looks really unprofessional").
  Google only uses a site icon that is square and a multiple of 48 px, and ours was 256 px. The page now links the
  "B" at 48, 96 and 192 px (`web/brand/icon-*.png`), the tab icon is the 192 px one, and `/favicon.ico` holds 16, 32
  and 48 px. The search data also names Bloxov as the publisher with the icon as its logo. Google picks the new icon
  up the next time it re-reads the page (days to a few weeks). Website only; the game is unchanged.

## 0.25.22 (Bodies that move)
Other players (and the AI) as you see them, owner's list: "super static", "stiff", prone "really weird".
- Turning round while prone no longer swings the whole body round the feet: lying bodies (prone, downed, dead face
  down) are centred on where the player is and turn about their middle. The prone and downed hitboxes moved with them
  (the head is now about 0.6 m ahead of the player's spot instead of 1.6 m).
- Going prone, the legs no longer sink into the ground and pop back up: a foot that would go under the floor bends at
  the knee and stays on top.
- Legs facing backwards (owner's screenshot): after crouching, a body's legs were drawn turned half round, boots to
  the back. Fixed (the arms had the same flip).
- Heads are 15% smaller on every character (owner: "heads are kinda too big"). Head hitboxes shrank to match: standing
  0.53 x 0.61 m at 1.66 m (was 0.62 x 0.72 at 1.71), crouched still at the old height. This makes headshots a little
  harder, on players and the AI alike.
- Prone, the gun is out ahead by the head in both hands (it lay hidden under the chin).
- Walking and running move the whole body: the hips dip and sway with each step, hips and shoulders twist, sprinting
  leans in with bigger strides and higher knees, the gun bobs, crouch-walking takes real steps, crawling wiggles the
  hips and rolls the shoulders, standing still breathes, and turning on the spot steps the feet round.
- Getting shot makes the body flinch away from the shot and spring back. The shooter sees it the moment the server
  confirms the hit; everyone else sees it from the hit player's own game (a new "just hit" bit in their state).
- Looks only otherwise: nothing about how anyone moves or shoots changed. `tools/remote_view.gd` renders another
  player in motion for checking.

## 0.25.21 (Old house roofs)
- The bombed old houses (1, 7 and 8 in the old quarter): standing in an upstairs room whose roof was blown off and
  looking up, the torn roof flaps and the chimney's bottom looked like they floated in the air (owner). Each flap now
  has a rafter under it, a ridge beam runs under the ridge where the roof broke, and the chimney is a whole brick stack
  down to the attic floor instead of a stub poking through the boards. Looks only; the houses play the same.

## 0.25.20 (Hear your squad, raid check)
- Other players' footsteps online are easier to hear (owner: "still really hard to hear"): they were 3 dB quieter
  than the AI's. Walking is now 6 dB louder and sprinting 4 dB louder, fading more slowly with distance and heard
  10 m farther (45 m walking, 55 m sprinting). Crouch-walking is unchanged, so sneaking still works.
- START RAID asks "START RAID?" first (owner: in case of a misclick), with big BACK and START RAID buttons. With
  nothing on you, the NO GEAR warning asks instead, so it's still one question.

## 0.25.19 (No poking through walls)
- Online (owner: standing at a pillar, a friend saw their arms and body stick right through it): against a wall,
  other players' guns are pulled in and raised to the chest instead of reaching through it (the arms and gun used to
  reach 0.5 m past the body's collision). Looks only: your shots still come from your eyes.
- Leaning at a wall: others now see you lean only as far as you really did. Your camera already stopped short of the
  wall, but your body (and its hitboxes) tipped all the way, so your head showed on the far side. Your own lean now
  stops with room for the whole head (0.32 m from the wall, was 0.2).

## 0.25.18 (Wider signs)
- The signs whose words touched or ran off their edges got wider boards (owner picked wider over shorter words):
  the town hall's VOTE signs over the booths and the KEEP OUT sprayed by the bunker ramp, the grocery's STAFF ONLY
  signs and its window posters (SALE / HALF OFF now sits inside the frame), the calendars in the offices and the town
  hall, and the FOOD, SODA and MEDS labels on loot boxes (MEDS is back). The grocery's staff board has ROTA on its
  own note instead of written over the others.

## 0.25.17 (The hangout)
- Hideout: a secret room (owner picked it from four). Walk down the shooting range (there's now a gap at the east end
  of the firing line) to the 100 m end: past the backstop the end wall has split, and a narrow crack in the rock leads
  to an old mine chamber the PMCs fitted out as a lounge (owner: "make it more fun... get creative"). Rock overhead,
  painted tin walls with light strips, a black and white tiled floor, a snack bar with stools you can sit on and a glowing
  SNACKS sign (snacks and soda, not drinks: store age ratings), two arcade cabinets, a pool table under a hanging lamp, a jukebox you can switch on (a new tune; the
  radio's is unchanged), a couch on a rug, string lights and a mirror ball. Just for fun: nothing in it is saved or
  changes how you play.

## 0.25.16 (Signs that spilled over)
- Sign check (owner): the bank's cash machine had the top of CASH cut off, and the calendars in the offices and the
  town hall had MAY written over the days. Both moved to fit. The medicine boxes in loot spots said MEDS, one letter
  too wide for the box (the M and S were cut off); they say MED now.

## 0.25.15 (Top bunk and sign lettering)
- Hideout: you can jump up onto a top bunk (owner asked, just for fun). The far bunk on the right has a footlocker
  and two stacked ammo crates at its foot as steps; the bunks now collide up to the top mattress so you stand on it.
- Signs: no more stray gaps inside words. To centre text exactly, the sign painter used to widen one gap in the
  middle of a word ("ST ASH", "WARD ROBE", "SUPP LIER", "CANNE D FOOD"); now it widens a space between words, or
  sits the text half a pixel off centre. Every sign was repainted: the hideout, 34 map buildings and the loot boxes
  ("SO DA", "ME DS"). Only the sign pictures changed, nothing moved.

## 0.25.14 (Website visit counts)
- Owner asked to see how many people visit. The web page on bloxov.com now loads Cloudflare Web Analytics, which
  is free and cookieless: visits, pages, browsers, countries and load times, with nothing that identifies a player.
  The owner reads it in Cloudflare under Observability, Analytics, Web analytics. It's in the web build only, never
  in phone or desktop builds. Store rules: the in-game PRIVACY page and docs/STORE_RULES.md now say so.

## 0.25.13 (Player count in the server log)
- Owner asked how to see the player count. The online server now writes a line to its log every 5 minutes while
  anyone is on: how many are online, in the hideout and in raids, plus the peak, joins and raids since the server
  last started (Heroku restarts it daily). Counts only, no names or addresses. Read it in the Heroku dashboard
  (bloxov-server, More, View logs) and look for `stats:`. Nothing changes for players.

## 0.25.12 (Loading screen fills the window)
- The web loading picture now fills the browser window instead of leaving dark bars at the sides (Godot's own page
  style was overriding ours). Only a tall phone-shaped window still shows the whole picture with bars above and below,
  so the logo never gets cut off.

## 0.25.11 (Top bar buttons)
- The hideout menu's top bar buttons (< HIDEOUT, OPTIONS, ONLINE, LOADOUTS, RAID WITH FREE KIT, START RAID) are a
  few pixels shorter and sit inside the bar, no longer poking into its light top edge (owner).

## 0.25.10 (Findable on search)
- **The loading screen says what the game is:** a short intro (name, one line about the game, five features) sits at
  the top while the game downloads and goes away when it starts. It's real text in the page, so search engines can
  read it (the game itself is just a picture to them).
- **Tab title** is now "Bloxov: No Man's Land – Free Browser Extraction Shooter" and stays that way once the game starts.
- **For search engines:** `robots.txt`, `sitemap.xml` (for Google Search Console), a canonical link to
  `https://bloxov.com/`, and schema.org VideoGame data (free, plays in the browser, solo and online). All added to
  the web build by `tools/web_seo.py`; the intro text lives in `web/seo/`.

## 0.25.9 (Tab icon fix)
- The browser tab now shows the pixel "B" right away. Browsers keep tab icons cached much longer than other files,
  so anyone who opened the game before 0.25.7 kept seeing Godot's icon until the game finished loading. The icon
  links now carry the build version (like the game files do), and the site also has a `favicon.ico`.

## 0.25.8 (Link preview on bloxov.com)
- Link previews now point at `https://bloxov.com/` (the game moved there), so Discord and others fetch the picture
  straight from the new address.

## 0.25.7 (Bloxov loading screen)
- **The web page loads as Bloxov, not Godot:** while the game downloads you see the BLOXOV / NO MAN'S LAND logo over
  the title screen's dusk view with a red pixel progress bar, instead of the Godot logo. The desktop build shows the
  same splash.
- **Bloxov icon:** the browser tab (and phone home screen) icon is a pixel "B" instead of the Godot robot.
- **Link previews:** pasting the game's link in Discord (or X, Facebook, iMessage) now shows a 1200x630 Bloxov picture
  with the name and a one-line description. The pictures come from `tools/make_web_branding.py`.

## 0.25.6 (Dearer traders)
- **Traders charge 30% more** (owner, after the economy check): buy prices are now 1.56x an item's value (was 1.2x).
  Selling pays the same as before. A good Hound kit now costs about 2.2 quick raids instead of 1.7, closer to the
  "good kit in 2-3 raids" pace.
- **New profiles start with $65,000** (was $50,000) so a first kit still fits. Existing saves keep their own money.

## 0.25.5 (Save backups, ready for bloxov.com)
- **Save backup in OPTIONS** (title screen and hideout): **SAVE TO FILE** downloads your whole save (stash, money,
  loadouts, traders, quests, character, settings) as one file. **LOAD FROM FILE** reads one, says what's in it
  (money, raids, date) and asks before it replaces your progress. Files that aren't a save, are damaged or are from
  another save version are refused, and settings in a file are type-checked.
- **Getting ready to move to bloxov.com** (owner: nobody loses progress). Saves in a browser belong to one site,
  so the old address's save can't be read from bloxov.com. On bloxov.com, a browser with no save is sent once to a
  small move page on the old site, which reads the old save and comes straight back with it. Nothing happens on
  the current site; it only starts once the domain is set up (steps in `docs/DOMAIN_MOVE.md`).
- Settings now keep a second copy in the browser's localStorage too, like the profile already did.
- PRIVACY mentions the backup file.

## 0.25.4 (Ponta and Big Don)
- **Trader names (owner):** the Gunsmith is now **Ponta** and the Supplier is now **Big Don**. The shooting range's
  locked guns say "Ponta level 2" and so on. The Medic keeps its placeholder name for now.
- `tools/economy_sim.gd` compares kits by tier (bad, mid, good, really good) and adds what a raid actually carries
  home: it keeps the best value per cell that fits in pockets, the secure pocket and the backpack.

## 0.25.3 (Bloxov Frontlines)
- **The map is now called Bloxov Frontlines** (owner; it was Bloxov Battlegrounds). "Battlegrounds" is a trademark
  Krafton (PUBG) has enforced, so the new name keeps the game clear of it before a public release. The loading
  screen, the map screen (M) and every doc say the new name; file names still say `old_bloxov` and the loading
  picture keeps its file name

## 0.25.2 (Server-side health and extracts)
- **The server keeps its own count of your health online** (stops god mode). Other players' hits come off it
  through the best armor and helmet you carry (at full strength), and every heal you finish goes back on (only
  with a heal you carry). Your game still runs your health exactly as before; the server's count is never lower
  than yours (the AI's hits and falls don't count on it, and it gives you the best armor), so it can only catch a
  game that won't go down. If its count hits 0 and your game is still up 1.5 s later, you're dead on the server:
  your shots and looting stop counting, everyone sees you dead, and your game is told. Going down (downed) counts
  as down; a revive puts you on 30 again. A strike, too.
- **Extracting is checked online.** The server has to have seen you standing in an extract for its time (with
  1.5 s and half a metre of slack for lag). A game that says it extracted anywhere else isn't believed: you're
  still in the raid, where others can see and shoot you (no more vanishing out of a fight). A strike, too.
- Dead or extracted players can't open or change crates and bodies online any more.
- Code: `Network._check_health`, `_hurt`, `_healed`/`report_heal`, `_forced_dead`, `_track_extract`/`_extract_ok`,
  `RaidWorld.extract_at` (the server's map copy keeps the extracts now). Docs: DEV_HANDOFF "Anti-cheat".
- Store rules: the server log now records anti-cheat catches and kicks with player names; the privacy policy
  needs a line about it before release (STORE_RULES.md updated).

## 0.25.1 (The server knows what you carry)
- **The server keeps count of what every player carries online.** Your game tells it your kit as the raid starts;
  from then on it adds what you take from crates and bodies and takes off what you put in, drop, fire and throw.
  - Firing a gun you don't carry, or with no rounds left for it, doesn't count (no hit, no sound for others).
  - Putting an item in a crate or body that you never had is undone, and your screen gets the real contents back.
  - Dropped items and your body only hold what you carried: anything made up is left out (so made-up items can't
    end up in other players' stashes).
  - A grenade you don't have doesn't get thrown; a key door only opens if you carry its key.
  Each of these is a strike (0.25.0). An honest player never sees any of it. What you bring into a raid is still
  taken on trust: the stash lives in your browser until the Stash update moves the online one onto the server.
- Code: `NetGuard.count_stacks` / `move_items` / `take_entries` / `use_item`, `Network._kit` and `_carried`,
  `RaidWorld.door_key`. Online test sections send a test kit (`_send_test_kit`).

## 0.25.0 (Checkpoint: rate limits, movement checks, kicks)
First step of the security update (owner: online play locked down before the web beta). Nothing changes how the
game plays; this only stops things a cheat could send.
- **Rate limits** on everything a player sends the server (moves, shots, loot, doors, grenades, revives, the
  lobby). Each kind has an allowance well above what the game ever sends; anything over it is dropped.
- **Movement checks.** The server now checks every move: no faster than a generous speed limit (sprint is 5.6 m/s,
  the check allows 8 with ~1.5 s of lag-spike slack), no flying up, no teleports, no walking through walls (solid
  map at knee, waist and head height; vaulting a low wall or crouching under something is fine). Falling is never
  too fast, and going back to your spawn after falling out of the world is allowed. A move that fails isn't taken:
  the server keeps you where you were (shots come from there, others see you there) and puts your game back.
- **Dead stays dead** online: a game that says it died or extracted can't take it back in the same raid, and a
  body doesn't move.
- **Strikes and kicks** (owner's call: undo + log, kick on repeats). Each thing caught adds strike points that
  fade over time (one point every 10 s); 20 points = kicked from the server with a message. An honest player with
  a bad connection gets put back now and then and never comes close. Every catch is in the server log. No bans
  yet: with no accounts there's nothing to ban (the Stash update brings accounts).
- **Windows build in CI.** Every update now also runs the gameplay test on Windows, exports the Windows game
  (.exe) and starts it, so the future Steam build can't quietly break (owner, 2026-10-25). The .exe is kept for a
  week under the workflow run's Artifacts. It doesn't hold up the web deploy.
- Code: `scripts/net_guard.gd` (NetGuard: rate limits, movement, strikes), `RaidWorld.blocked`, `Network.kick`;
  smoke test section `anticheat`.

## 0.24.2 (Slower AI)
- **AI move about 7% slower** (owner: they felt faster since the jointed characters). 0.23 didn't change how fast
  they move (same speeds, same colliders; the new walk swings the legs at the same rate as before), but they're
  slowed anyway as asked: scavs 3.6 -> 3.35 m/s top speed, Raiders and Bon 3.9 -> 3.6. Every walk, jog, push and
  chase is a fraction of that, so all of them drop by the same share. Nothing else about the AI changed.

## 0.24.1 (Options in the hideout)
- **OPTIONS in the hideout menu** (owner: there was no way back to the settings once in the hideout). Next to your
  money on the top bar, away from the raid buttons: the same settings as the main screen's OPTIONS (sound, mouse,
  graphics, damage numbers, lean, raid tips) in a window over the menu. REPLAY TUTORIAL there drops you straight
  back into the hideout on step 1. Esc while walking round opens the menu, so it's two presses from anywhere.
  Both screens build their settings from one place now (`scripts/options_page.gd`).

## 0.24.0 (New-player tutorial)
- **A first walk round the hideout for new players** (owner picked "hideout, then first-raid hints"). A card at the
  top of the screen takes you through it one step at a time: walk and sprint, the shooting range (shoot the targets,
  aim, reload), your gear (what the loadout and the stash are, and that you lose what you take in if you die), a
  trader, and last the war table and START RAID. A marker over the next place shows where to go and how far.
  SKIP TUTORIAL ends it at any step (Esc frees the mouse to press it). `scripts/tutorial.gd`.
- **One-time tips in your first raids** (`scripts/raid_tips.gd`): how to get out (extracts, the map, the timer),
  searching, healing the first time you're hit, ladders, the extract timer, and after a minute vaulting, crouching
  and prone. Each shows once, for a few seconds under the raid timer. "Raid tips" in the pause menu and in OPTIONS
  turns them off; REPLAY TUTORIAL in OPTIONS runs the walk and the tips again.
- **Anyone who has already played skips it** (owner): a save with a raid, money earned or spent, anything in the
  stash, a quest or a trader level counts as played. Phones (no walking in the hideout yet) and online players
  coming back from a raid get only the raid tips.
- Store rules: nothing new is sent anywhere; "tutorial done" and the tips you've seen are saved with your profile
  on your own device. The tips name keys today and are written so touch buttons can stand in once phone controls exist.

## 0.23.4 (Motel blinds swing aside)
- **You can climb through the motel's windows again, and their blinds swing out of your way** (owner picked "climb
  through, blinds swing aside"). Jump into one of the 28 blinded windows and you vault through; the blinds swing up
  and away from you as you push through, then sway back and settle. A shot through them or a blast nearby sets them
  swaying too. Looks only: nothing about them collides, nothing is sent online, and the game server never draws them
  (`scripts/blinds.gd`; the motel model now draws only their head rails). Every other window stays shut (0.23.3).

## 0.23.3 (Windows shut, washrooms open)
- **You can't climb or walk through windows any more** (owner: "u can still go through broken windows, windows with
  blinds, windows with square like fittings in the middle, church windows, etc, like this needs to be fixed"). Every
  window on Bloxov Frontlines now stops players: smashed ones, glazed ones (shooting the glass out still breaks
  it, but leaves the frame shut), the motel's blinds, the framed shop and grocery fronts, the church's tall windows.
  265 windows in all, players only: shots and anyone's eyes still go through the openings as before, and nothing
  about the AI changes. Doorways, blast holes and the barn's hay door stay open.
- **Washroom doors are wider** (owner: "You cant walk into most of the washrooms in the map ... the doors need to
  be wider"): 1.05 m instead of 0.85, in all 42 washrooms (27 building models rebuilt). A walk test now gets a
  player into every one. Fixed on the way, as they also shut a washroom: an open door leaf joined to a toilet or bath
  as one block; furniture on both sides of a wall joined into one block through it (never now: that also clears
  some invisible furniture blocks poking into the next room, like the motel's); a safe in front of the doctor's bathroom
  door (0.4 m along the wall), a toilet that left no room to stand (old house 8: now on the side wall), and the
  signal box washroom's door moved off the bench outside.

## 0.23.2 (AI stop shooting at shut doors)
- **The AI no longer fire at a door you've shut** (owner: "the AI still tries to shoot through doors"). Since 0.21.19
  their bullets stopped at a shut door, but an AI pinning you down kept firing at the spot where it last saw you,
  so going through a door and shutting it got the door hammered. Now it won't start suppressing through a shut door,
  and stops (and comes after you instead, as it would with nobody to pin down) if you shut one mid-burst. A melee bash
  that was already swinging when you shut the door in its face no longer lands through it.
- Shots through walls (playtesters): checked again; AI shots and eyes stop at walls and shut doors, and online your
  game turns a late hit from behind a wall or a shut door into a miss (0.21.18-0.21.19). No change needed.

## 0.23.1 (No snagging on furniture)
- **The furniture hitboxes from 0.22.0 can't catch or trap you** (owner: "i dont want players to just keep getting
  randomly stuck everywhere when they walk"). A new walk test (`tools/prop_snag_check.gd`) walks a player-sized body
  into every one from 8 sides, then checks it can walk away. Three fixes from it:
  - every furniture box is now a plain block from the floor up: no table top, seat or rail edge hanging at knee or
    head height to catch on;
  - anything under 0.5 m tall stays walk-through, like small rubble and things on the ground;
  - furniture standing closer together than a player is wide (chairs round a table, stools by a counter) is one block
    you walk round, so there's no gap to wedge into.
  Result: nobody gets stuck anywhere (2,248 walk-ins); the only spots that need a jump are a few where you've climbed
  onto a desk and step off between its chairs. Every container, door and key door can still be reached (checked).
  Still only players: shots, eyes and the AI pass through them as before.

## 0.23.0 (Proper crouch and prone)
- **Characters have joints** (owner: crouching "just compresses" them and prone "is like you're dead"). Scavs,
  Raiders, Bon and other players are rebuilt with hips, chest, head, arms and legs that bend, keeping the old models'
  size and every outfit option (owner: "the same as before for now").
- **Real poses:** walking with bending knees; crouched they kneel on one knee, and crouch-walk low; prone players lie
  on their elbows, head up, the gun ahead in both hands, and crawl; downed players lie flat without their gun,
  dragging themselves with one arm and holding the wound; dead players fall on their back (or stay face down if they
  were lying already). Both hands are on the gun they hold. The wardrobe and inventory show your character at ease.
- **Hitboxes fit the poses exactly** (owner: "the hitboxes need to be precise"). Crouched, prone and downed, a
  player has three boxes (head, chest, hips and legs) measured off the posed model, every outfit included: the chest
  box leans with the chest, the head box nods with the head. Standing is unchanged. The head stays at its old
  height crouched (owner): 1.15 m for players, 1.03 m for a kneeling scav (the model leans just enough to put its
  head there), and kneeling scavs get the same fitted boxes. `tools/fit_hitboxes.gd` re-measures them; the smoke
  test fails if the model and the boxes drift apart.
- Each character draws as one skinned mesh (plus its gun), fewer draw calls than before.
- Models: `art_source/scripts/make_character.py` (plain Python now), poses: `scripts/body_pose.gd`, pictures:
  `tools/body_preview.gd`.

## 0.22.9 (Back lawn, church roof, carpet hitch)
- **Cover behind the town hall** (owner: too open, the AI roaming there got sniped). Bon's crew have barricaded
  the back lawn about 10 m out from the hall's back wall: three shipping containers (one stacked two high), an army
  truck and sandbag posts, with gaps to walk through. What stood there before (a ruin, a container, a tree, some
  junk) was cleared. The map only: AI behaviour is unchanged.
- **The church roof is solid** (owner: you could walk through it). Only a flat slab at the eaves collided, so from
  the bell tower you could walk about inside the pitched roof. Its slopes and gable ends now collide (out of sight).
- **No hitch when the town hall's red carpet is tripped** (owner: the game lagged for a second). Fading the runner
  switched its material to a see-through one right then, so the renderer had to build a new shader mid-raid (worst
  in browsers). The see-through copy now goes on at raid start, looking the same; tripping only fades it.
## 0.22.8 (No buzz, hear the shooter)
- **Fixed the buzzing some players heard when a raid starts** (owner: a playtester heard it on entering a raid). The
  background loops (wind, woods, room tone, creek, waterfall) started at a random point; on the web Godot repeats a
  loop only from where it was started, so one started near its very end repeated a few milliseconds over and over.
  They start at the beginning now and repeat the whole sound.
- **You hear where you're being shot from** (owner: "hear more where u got shot from and less where the shot
  lands"): a gun shooting at you (its bullet passes within 3 m of your head or hits you) gets back half the loudness
  distance took off it (up to +10 dB), so a far sniper is clearly heard from their side. The bullet's snap is
  softer and now comes from the shooter's side of your head, and other people's bullets landing around you are
  8 dB quieter. Your own shots' impacts sound as before. No sounds were replaced.

## 0.22.7 (No more ding)
- **The lock-on ding is gone** (owner: "get rid of the ding for when scavs lock on to you, we need to really
  emphasize the footsteps and their voicelines"). Instead an AI that spots you always says its "spotted" callout
  (was 70% of the time; still at most one callout per few seconds, and one that calls for help says that instead).
  Callouts are 3 dB louder and fade more slowly with distance. Muttering is unchanged, and no other sound is
  replaced. Online, the server no longer sends the "alerted" event (it only played the ding). The sound file stays
  in `audio/` in case it's wanted back.

## 0.22.6 (Every can, swinging table lamps)
- **Shots kick every can and bottle they pass** (owner: "some are shootable but not all"): a shot only knocked a
  can when it landed within half a metre of it, so a shot through a can into the ground behind it often missed it.
  Now any can within a hand's width of the shot's path jumps.
- **More of them**: the ration tins and bottles lying about in the town hall and its vault (120) and the cans and the
  bottle on the hideout's mess tables are kickable and shootable now (366 on the map in all).
- **The lamps over the mess tables swing** too (owner: "when u walk through nothing happens"), and walking right
  under any hanging lamp gives it a little nudge, as if you'd brushed it. Jumping into one still knocks it hardest.
## 0.22.5 (Hold still)
- **The wardrobe character stands still** (owner: it shouldn't be constantly spinning). Click and drag on them to
  turn them round; on phones, drag with a finger. The hint under the character says so.

## 0.22.4 (Dresser fix)
- **The dresser in one of the old houses no longer sticks out through the wall** (owner). It's the house in the old
  quarter with its door on the west side: the dresser was slid off the door so far it ended half outside the south
  wall. It now stands at the other end of the same wall, by the room's inside wall, fully indoors (hitbox with it).
  Containers moved off a door can no longer slide past the end of their wall in any building (no other one did).

## 0.22.3 (Footsteps up, online)
- **Louder online players' footsteps** too (owner: "not just AI footsteps, online players too"). Other players'
  walking and sprinting steps are 6 dB louder, fade more slowly with distance and carry 10 m farther (35 m walking,
  45 m sprinting). Crouch-walking is unchanged, so sneaking up on someone still works. Same sounds as before.

## 0.22.2 (Footsteps up)
- **Louder AI footsteps** (owner: "the AI footsteps audio needs to be increased"; playtesters had trouble finding
  enemies). Scav, raider and Bon steps are 6 dB louder up close, fade more slowly with distance (about 10 dB louder
  at 30 m) and can be heard out to 40 m instead of 30 m. Same sounds as before; sneaking AI are still silent, and
  steps behind walls are still muffled. AI behaviour is unchanged.

## 0.22.1 (Lights out)
- **The light switch is for the whole bunker** (owner: he didn't like 0.21.17's lights, and meant the whole place).
  Off, the whole hideout goes dark and stays dark wherever you walk; the fairy lights and the TV in the bunks still
  glow. On again, everything's lit as before. 0.21.17's bunks-only darkening is gone.

## 0.22.0 (World Reacts)
- **Things that look solid are solid** (owner: "give solid-looking things real hitboxes"). A new check
  (`tools/walkthrough_audit.gd`) walks every spot you can reach on Bloxov Frontlines and in the hideout and lists
  what's drawn at body height with nothing to bump into (768 spots on the map before, 468 after; most left are
  kerbs on banks, rolled-over wrecks and rubble you step over). From it: chairs, stools, benches, cots, bunks, tables,
  toilets, racks, plants, globes, voting booths, the barn's stall gates, washroom stalls, the drill rig, porch posts
  and the like now stop players, and so does the furniture knocked about in the caved-in rooms that stands
  waist-high or more. They stop players only (a new collision layer, 10): shots, eyes and the AI pass through them
  exactly as before, so fights and the AI are unchanged. Ruined walls outside collide as drawn (their broken tops
  stuck up past their box). In the hideout: the tunnel mouths' concrete frames, crates and the washroom walls. Small
  rubble under knee height, paper, timbers and rebar stay walk-over; nothing new blocks a doorway, and every
  container, door and key door can still be reached (checked).
- **Hanging lamps swing** in the hideout (the bulbs over the bays and the washroom's lamps hang a bit lower now, so
  a jump heads them). Bumping one, a shot going past or a blast nearby sets it swinging; it slows back to still. The
  light stays where it's baked.
- **Bushes part round you** when you walk through them (and round anyone else nearby), the tops most, with a rustle
  while you're moving. The hideout's curtains (the toilet cubicles, the showers) and the washing on the line sway
  and get pushed aside the same way.
- **Cans and bottles get kicked about**: the ones in the litter along the roads. Walk into one and it skitters off
  the way you were going; a shot next to it makes it jump, a grenade throws it. They roll to a stop and lie there.
- All of the moving things are looks only: they never collide, never block shots or sight, are never sent online
  and the server doesn't run them (each player sees their own). Cheap: 2 draw calls for every can on the map, 4 in
  the hideout for the lamps and curtains.

## 0.21.21 (Faster drift)
- The main screen's town drifts a bit faster (owner): 25 seconds from side to side, was 40.

## 0.21.20 (Smoother main screen)
- The main screen's town drifts smoothly (owner: "super choppy"): it moved one whole pixel at a time; it now slides
  in a shader.
- The town picture is rendered again (owner: the trees looked weird): every tree in full detail at any distance
  (the far stand-ins are gone), thinner haze so the woods aren't washed out, and the low sun off to the left so the
  trees are lit from the side. Sharper too (rendered bigger, with anti-aliasing).

## 0.21.19 (Doors stop bullets)
- **Shut doors stop bullets** (owner: "stop bullets going through doors, i don't like that mechanic right now").
  Yours, the AI's (aimed shots and suppressing fire) and other players' online all stop at a shut door now; an
  open door lets them through as before. Grenades are unchanged.

## 0.21.18 (Fair fights: Raiders' first burst, Bon's leash, shots through walls)
- **A Raider's first burst can't kill you outright, most of the time** (owner: "a raider should not be able to kill you
  instantly without being able to react"). The first burst any AI fires at you in a fight rolls once: with no armor
  it may kill you 20% of the time; armor and a helmet lower that (light vest 13%, heavy vest 6%, light vest and old
  helmet 10%; worn gear counts for less) down to 0% with heavy armor and the combat helmet. When the roll says no,
  a shot of that burst that would kill you (or put you down) misses instead; the rest land as usual. Every burst
  after the first is unchanged. Bon and his guards are the exception: their first burst can kill (owner).
- **Bon stays near his guards** (owner: he could be lured away from them). He still charges you, but once he's 15 m
  from his nearest living guard he won't chase or go after you any farther: he stands and fires from there until
  they catch up. With his guards dead he's free again.
- **Online: no more AI hits through walls** (playtesters were shot through walls). The server sees you a moment
  late, so a burst could land just after you'd stepped behind a wall on your screen. Now your game checks: if
  there's solid wall between that AI and you (chest and head, from its chest and eyes), the hit misses.
  (A check of the map found the walls the AI see and shoot along match the drawn ones; shut doors still let
  bullets through, as before.)

## 0.21.17 (Hideout and aiming fixes)
- **Iron sights aim where the crosshair was** (owner: aiming in with the Stinger moved your aim a little lower). The
  sights sat 3 mm under the middle of the screen, so the front post pointed slightly low of where the shots go, on
  every gun. They now line up exactly on the middle.
- **The bunks' lights stay off as you walk round** (owner). Before, the whole hideout dimmed only while you stood in the
  bunks, so they lit up again when you walked out. Now the bunks themselves go dark, seen from anywhere; the fairy
  lights and the TV still glow.
- **The radio, darts and light switch are used by looking at them** (owner: their hitboxes felt off). Before, you had
  to stand on an invisible spot near them; now the USE prompt shows when you look at the thing itself from up close.
- **The < HIDEOUT button** on the menu's top bar is the same size as the other buttons (owner: it was big and
  awkward). Tab still takes you back (it's on the button's tooltip).
- **Going into a raid with nothing on you asks first** (owner): NO GEAR, with GO ANYWAY, TAKE FREE KIT (when you can)
  and BACK. Also for QUEUE and START NOW online.

## 0.21.16 (Front line fixes)
- "No Man's Land" on the main screen is cream like the BLOXOV logo (owner: the light red looked pink).
- The website build failed: the server logged an engine error when a player left a raid (their first-person hands'
  jacket and gloves, since 0.21.11). The dressed hands now share one copy of each jacket and glove look.

## 0.21.15 (Front line)
- **New main screen look** (owner picked A of four options): the town of Bloxov Frontlines at dusk, smoke rising,
  drifting slowly from side to side behind the menu, with a military red PLAY button. It's a picture, not a 3D
  scene, so the main screen is lighter on phones. Red is for the main screen only: in the game yellow still means
  "active" and red means danger.

## 0.21.14 (Deploy fix)
- 0.21.11 to 0.21.13 never reached the website: the hands' outfit pictures had names the repository leaves out, so
  the online build's test failed. Renamed, and the site gets the matching hands, darts night and the main screen.

## 0.21.13 (Main screen)
- **The game opens on a main screen** (owner): BLOXOV, No Man's Land, over a slow look round the hideout, with
  PLAY, OPTIONS, PRIVACY and CREDITS (and QUIT on a computer build). PLAY goes into the hideout, which loads in the
  background while you're on the main screen.
  - OPTIONS: volume and each sound type, mouse sensitivity, graphics, damage numbers, lean toggle (the same
    settings as the raid's menu).
  - PRIVACY: what the game keeps and sends, in plain words (both app stores want this reachable in the game).
  - CREDITS: the game, the Godot Engine and the fonts' licences.
  - Space is left under PLAY for signing in later.
- Some new hideout text (darts, the record screen, the range) now uses the pixel font's even sizes, so its letters
  are crisp.

## 0.21.12 (Darts night)
- **Darts is a real mini-game now** (owner: "just click to throw, too easy... maybe play against the traders").
  - At the line, pick PRACTICE or play one of the traders.
  - Your aim drifts in a slow loop, like breathing, so you time your throw.
  - Hold the mouse (or your finger) to wind up. The power bar swings up and down: let go in the green band. Too soft
    and the dart drops low, too hard and it flies high.
  - Against a trader: three rounds of three darts each, highest total wins. Each trader throws differently (the
    Gunsmith and Supreme are sharp, the Medic less so, Ming goes for the bull) and has something to say when the game
    ends. Practice keeps your best three darts.
  - Just for fun: nothing is bet and nothing is saved.

## 0.21.11 (Matching hands)
- **Your first-person hands match your character** (owner): the sleeves are your character's jacket (green, tan,
  multicam or black) and the gloves are theirs (green, tan or black), as picked in the wardrobe. Looks only.

## 0.21.10 (Phone tabs, mouse fix)
- **Everything in the 3D hideout works on phones** (owner). Phones open on the menu, so it gets four tabs on the top
  bar: GEAR (stash and loadout), TRADERS (the traders' own screens), WARDROBE (pick and customize your operator),
  RECORD (new: your record and every trader's open jobs, with a GO TO TRADER button for handing in). The tab you're
  on is lit. Buttons are big enough to tap. On a computer you still walk to these, so the bar stays tidy.
  "Raid with free kit" is shortened to FREE KIT RAID on phones so the bar fits.
  The shooting range and the hangout toys (darts, the couch, the radio, the light switch) are for walking round,
  so they come to phones with the touch controls.
- **The mouse is no longer grabbed on the menu** (owner): on a first load the menu could show while you were still
  free to walk, so a click on the stash grabbed (and hid) the mouse. It's only grabbed while walking round the
  hideout or shooting at the range.

## 0.21.9 (Hint line fix)
- The controls hint at the bottom of the hideout's stash screen was cut off by the bottom edge of the screen, more so
  when a gun's stat bars showed (owner). It's now shown in the details area until you point at an item, so the screen
  fits again.

## 0.21.8 (Cleaner top bar)
- **The hideout menu's top bar is tidier** (owner: "too busy"). On the left is just the way back to the hideout and
  your money. On the right are the raid buttons, in order ONLINE, LOADOUTS, RAID WITH FREE KIT, then START RAID last.
  The game title is gone. Your record (raids, extracts, deaths) shows when you point at your money, and on the stats
  board in the hideout. What your stash is worth is next to the STASH heading. The version is small in the bottom
  corner.

## 0.21.7 (Hangout)
- **Things to do in the mess and bunks** (owner asked for all four, for hanging round with friends late at night).
  Just for fun: nothing here is saved or changes how you play.
  - **The radio**: walk up to it by the couch and press F to switch it on. It plays a slow, crackly little tune
    (a new sound) that you hear across the mess until you switch it off.
  - **Sit down** on the couch or any mess bench: F when you're next to it. You can still look round. F, jump or
    walking gets you up.
  - **Darts**: a dartboard on the mess wall with a throw line on the floor. Press F at the line, then click to throw.
    Three darts a round with real scoring (doubles, trebles, bull) and your best round. Darts land a little off
    where you aim. F stops.
  - **Lights off**: a switch on the wall by the bunks. The bunks go dark, but the fairy lights and the TV stay on.
- **New washroom** (owner: "just some metal box"): a tiled shower block at the end of the bunks, with two toilet
  cubicles, a trough sink with taps and mirrors, and two showers with curtains, towels and a mat.
- The TV's screen sits in the TV now (it hung half below it). Notices no longer hide behind the tunnel's ribs.

## 0.21.6 (Wardrobe)
- **The wardrobe is a character select** (owner picked operators plus customizing): walk up to it in the hideout and
  pick one of six operators (Rook, Dune, Ghost, Viper, Bishop, Hawk; placeholder names), watch them turn on a stand,
  and change any part on the right (face, headgear, eyewear, mask, jacket, vest, trousers, gloves, boots). It's worn
  and saved at once, shows on your inventory screen, and **online the others in your raid see your character**
  (before, everyone saw a random outfit on you, different on each screen). Looks only.

## 0.21.5 (Hideout fixes)
- **The quests and stats boards stand out in the hall on their own** (owner: the quests board was "shoved in the
  corner", the stats board hard to see): freestanding, under a tin awning with their own lamp, either side of the war
  table facing where you spawn. They're written with your real quests (each trader's jobs for their next level, with
  your progress) and your record (raids, extracts, deaths, earnings, stash worth, trader levels). Using the quests
  board opens the trader whose jobs you're on.
- **The mess and bunks are lived in** (owner: "so dead and awkward"): a lamp over each table with dinner and a card
  game left out, a corner with a couch, a rug and an old TV, reading lamps and kit on the bunks, fairy lights over
  them, washing hung across the tunnel, a sink and mirror outside the washroom, notices on the walls.
- No more flickering where two surfaces sat on top of each other (crate lids, drums, signs, the war table's map).
- No more gaps round the tunnel mouths: their concrete frames are wider and the rock sits flush against them.
- The seats round the war table, the mess benches and a few drums block you now (you walked through them).
- Signs can spell Q (the quests board's said "UESTS").

## 0.21.4 (Trader screens)
- **Walking up to a trader in the hideout opens their own screen** (owner): their stock as big cards with pictures
  (hover or tap one for its stats), their level and quests on the left, and a SELL list on the right of everything
  you have that they buy. Tabs switch traders; STASH & GEAR goes to the stash screen, where the trader column stays
  as it was. Ming's boxes show their odds on the card.
- The way back to walking round is now **< HIDEOUT (Tab)**, first on the menu's top bar, instead of a button in the
  bottom corner that covered the equipment. The stats line on the bar trims itself so the buttons never get pushed off.
- The hideout's prompts show the real use key (F; E is lean).

## 0.21.3 (Buy new keeps what can't be bought)
- With "Buy everything new" ticked, items the traders don't sell you (loot-only, or above your trader level) now come
  from your stash instead of being left out.

## 0.21.2 (Saved loadouts)
- **Save your loadouts** (owner): LOADOUTS in the hideout menu's top bar. Put your gear on the way you like it, name
  it and press SAVE WHAT I CARRY (up to 8 loadouts). Each saved loadout keeps where everything sits, the gun's
  attachments and its loaded rounds.
- **EQUIP builds one in one tap:** what you carry goes into your stash, then the loadout is taken from your stash
  first and only what's missing is bought from the traders (at your trader levels, with earned money). Each row shows
  what EQUIP will cost before you press it. Items the traders don't sell you (loot-only ones, or above your trader
  level) are left out and named. Not enough money or no stash room for what you carry: nothing changes.
- **"Buy everything new, even what's in my stash"** (owner's tick box idea): buys the whole loadout new and leaves
  what you own in the stash. Free kit items and found-in-raid items keep their marks when a loadout takes them from
  the stash (it takes free kit ones first and found-in-raid ones last, so quest items stay put when it can).

## 0.21.1 (Shooting range)
- **The range is open:** walk to the bench at the mouth of the range tunnel (north of the war table) and press E.
  Pick your own loadout (a copy, attachments and all) or borrow any gun the Gunsmith sells you at your level
  (locked ones show the level they need). Targets stand at 10, 25, 50 and 100 m, each in its own lane with a
  distance sign. Ammo is free and tops itself up, hits show the hit marker and the damage, HEAD if it was a
  headshot, and the distance. E (or GUNS) changes gun; Tab (or LEAVE) puts you back on your feet. Nothing at the
  range touches your stash or loadout.

## 0.21.0 (The walkable hideout)
- **The game now starts in a 3D hideout** (roadmap, owner OK'd the plan): no title screen; press play and you're
  standing at the war table. It's a rock cave the PMCs dug concrete tunnels off (owner picked the shape from
  sketches and renders: a cave hub with a command post's tunnels). The trader market is to the west (all five
  traders in a row), the armory with the stash, wardrobe and workbench is east, the mess hall, bunks and washroom
  are south, and the shooting range tunnel is north. Lit by strung bulbs and work lamps, with sandbags, green
  duffel bags, crates, a generator and canteen tables.
- **Walk up to a station and press E** (or tap the big USE button) to open the hideout menu there: a trader's
  counter opens that trader. **Tab** (or the MENU button, top right) opens the menu from anywhere, and Tab or BACK TO
  HIDEOUT closes it. The menu is today's hideout screen, unchanged (stash, loadout, traders, START RAID, online party).
  Raids end back in the hideout.
- Not there yet: the wardrobe (characters) and the workbench (crafting) are coming in later updates, and the range
  opens next. Online (back from a raid with your party) and on phones, the game opens on the menu. Phones get
  walking with the touch controls.
- Built by `art_source/scripts/make_hideout.py` (`--shape=mix`; `cave` and `post` were the other options shown).

## 0.20.25 (Fountain fit & AI fire)
- **Town square fountain collides like its model** (owner: "has a box hitbox, make it actually fit the model"): the
  6 m square block is gone. You and bullets now meet the octagonal rim, the water inside it, the pedestal and the
  bowl, so the open corners are open and you can step down into the basin (make_outdoor `draw_fountain` -> shape).
- **Scavs a little worse at range** (owner: "nerf the scav accuracy from far ... by like 10%, close is fine"): hit
  chance 30% -> 27% at 28 m and 18% -> 16% at 70 m; 60% up close unchanged. Raiders, Bon and snipers unchanged.
- **Raiders pause less between bursts** (owner: "shorten the raiders pause ... like bon"): 0.5-1.0 s -> 0.5-0.75 s.
  Shot speed and burst length unchanged.

## 0.20.24 (First-person animations)
- **Reload animations** (owner OK'd the plan: reloads plus a per-shot kick): the gun comes up and rolls toward you,
  and the left hand pulls the magazine out, drops it out of view, brings a fresh one up and slaps it in (in time with
  the mag-in sound). On the Stinger the mag comes out of the grip. Reloading from empty ends with the hand racking
  the gun (handle, slide or bolt) with a click. The Mauler's left hand fetches each shell and pushes it into the
  loading port under the gun.
- **Kick on every shot:** the gun and hands jolt back and up, roll a little, then spring back. Heaviest on the Lancer
  and Mauler, lightest on the Wasp; about half as much when aiming. Purely visual: aim, recoil and spread are
  unchanged. Gun sway and bob are as before.
- `tools/anim_view.gd` renders the reload and kick as frames for checking.

## 0.20.23 (Fix: shoot through the gaps you can see)
- **Shots go under cars** (owner: "can you shoot under the car? ... u cant shoot through the parts u can see through.
  this type of logic should be applied to like every hitbox"): a car's body box now starts where its underside is
  drawn; the gap under it only stops people, and its wheels still stop shots. Burnt cars sit lower, so their gap is
  smaller. Added late in the generator, so nothing else on the map moved.
- **About 55 more kinds of furniture** let shots through their gaps, like tables already did: chairs, benches,
  stools, bunks, desks, sinks, toilets, urinals, stands, open shelves, headstones, the globe, the rocking horse...
  (found by an audit that fires rays through every prop's box and checks them against its drawing).
- **Outdoors:** lamp posts, oil drums, crates, the kiosk, the hut, rail signals and camo nets now stop shots only
  where they're drawn (past a thin pole, round a drum's edge).

## 0.20.22 (Low and Medium no longer slower than High)
- **Low and Medium graphics ran worse than High in the browser** (owner: "all my friends are getting more lag on
  medium/low compared to high"). Their lower 3D render scale (70% / 85%) made Godot copy the depth buffer at a
  different size every frame, which browsers on Windows (ANGLE on Direct3D 11) do through the CPU, stalling the
  graphics card. In browsers the render scale now stays at 100% on every setting; Low and Medium still save on
  shadows and switch buildings to their far models sooner. The downloadable builds keep the render scale.

## 0.20.21 (Fix: army truck hitboxes)
- **The green army trucks collide like they look** (owner: "you can walk inside the hood in the green military
  trucks, gives an unfair advantage, needs to have a proper hitbox"): their old boxes stopped short of the bonnet
  (on the wrecked ones the whole bonnet and the top of the cab had nothing) and tilted the cab in ways the model
  never showed. Each truck now has three boxes from its model: the bed (up to its canvas, and the gap behind the
  cab), the cab, the bonnet. Shots still hit the drawing, so they now stop on the bonnet too and still go through
  the windows and the gap behind the cab. The scatter round the trucks is unchanged (the swap happens after it);
  one truck by the station sidings that was only a leftover cab box (the rest cleared off the rails) is gone.
- Cars and the farm tractor were checked: their boxes already fit their models.
## 0.20.20 (Red dot replaces the iron sights)
- **An optic now replaces the iron sights** (owner: you could see both): with a red dot or a scope on, the gun's iron
  sights (rear notch/aperture, front post, the Mauler's beads) are hidden, and they come back when it's taken off.
  The gun models keep their sights in their own "Irons" part (`make_gun.py`), which `GunViewModels.dress` hides.
  Third person is unchanged: held guns there don't show attachments yet, so they keep their iron sights.

## 0.20.19 (Sound update: shots pan to their side)
- **You can hear which side a shot (or step, or callout) comes from** (owner: "easy to hear you are getting shot
  but not from where ... I just meant the audio itself"): sounds in the world now pan fully left/right instead of
  halfway, so a shot from your left is clearly in your left ear. The sounds themselves are unchanged.
- The 0.20.18 thwack is taken out again (owner didn't want an extra sound).

## 0.20.18 (Sound update: hear where you're shot from)
- **Getting shot now tells you which way** (owner: "easy to hear you are getting shot but not from where"): with
  today's hurt sound, a short thwack plays from the shooter's side, close to your head, so you can tell which way
  to turn. Falls don't play it. Sound only: no new marker on screen.

## 0.20.17 (Mauler quest moved up)
- **Field Test (kill 3 scavs with a Mauler) now unlocks Gunsmith level 3 instead of level 2** (owner). Level 2 needs
  Zeroing In and Spare Parts; level 3 needs Field Test, Overwatch, Hard Targets and Big Game. Field Test already done
  on an old save stays done.

## 0.20.16 (Sound update: quieter water)
- **The creek and the waterfall are much quieter** (owner: "way too loud"): the creek 14 dB down and heard within
  22 m (was 40), the waterfall 14 dB down and heard within 45 m (was 70); both fade out sooner as you walk away.

## 0.20.15 (Hands on the gun)
- **First-person hands** (owner: "add like a hand model holding the gun"; picked look B of three): black gloves with
  knuckle pads and black sleeves. The right hand wraps the grip (trigger finger along the frame), the left holds the
  handguard or pump with the thumb over the top, and on the pistol it cups the right hand. The forearms follow the
  gun when you aim, sprint or reload. Made by `art_source/scripts/make_hands.py` (`assets/models/hands/hands.glb`),
  checked with `tools/hands_view.gd`. Reloads still move the gun as before (hand animations come later, roadmap).
- **The Mauler points straighter at the hip** (owner: it faced too far left).
## 0.20.14 (AI start inside buildings and patrol them)
- **More AI start inside buildings, and they stay and patrol there** (owner: "AI's can spawn inside buildings and
  patrol around"; picked "indoor guards", same number of AI). Every ground-floor room the AI can walk into now has a
  spawn spot (67, was 33), found by the map generator from the walls and furniture as they stand since the world
  art (`building_rooms`); about 2 in 3 of a zone's AI start at one (was 1 in 2). An AI that starts inside walks
  room to room in its building, sometimes to a loot spot in it (upstairs too), and now and then steps just outside
  round the building before going back in (`Scav.indoor_rooms`, `indoor_patrol` 0.8). In a 3-minute run on the map
  they were in or by their building 83% of the time and most visited 2 or more rooms. AI that start outside patrol
  as before; fights, hearing and numbers are unchanged.
## 0.20.13 (Natural ladders)
- **Ladders climb the way you look** (owner: "make it so that when you are going down a ladder if u are looking down
  and pressing W u go down and if u press W and look up u go up"). On a ladder, W goes up while you look ahead or up
  and down while you look more than about 25° down; S does the opposite. At the top you can turn round, look down
  and walk over the edge to get on the ladder and climb down; at the bottom, W looking down steps you off. Hanging
  near the top with no keys held no longer pushes you back onto the floor. Same controls on a touch stick.

## 0.20.12 (Free kit after a closed tab)
- **Fixed: no free kit on a fresh visit with nothing on you** (owner: "sometimes you can't start with free kit when
  you first open the website and have nothing in your inventory"). Closing the tab mid-raid loses your gear, as
  meant, but the raid was only counted at the end screen, so a free kit taken before that raid still counted as
  "already taken this raid" and the button stayed hidden. Starting a raid now frees up the next free kit. The once
  per raid rule is unchanged (taking the kit and selling or stashing it still needs a raid before the next one).

## 0.20.11 (Brighter indoors)
- **Indoors are easier to see** (owner: "the indoors look a little too dark sometimes ... anything black is like
  unseeable"). The late afternoon look's colour curve (ACES) crushed dark colours to black in the shade; it now uses
  the softer Filmic curve the classic look used, with a little more fill light (ambient 0.9 -> 1.1). Outdoors (sun,
  sky, warm colours, haze) look the same. The classic look file is untouched.
- New tool `tools/render_indoors.gd` renders views inside buildings with any look (for checking indoor lighting).

## 0.20.10 (AI hear gunshots from less far)
- **AI hear gunshots from a quarter less far** (owner: the range AI respond to gunshots was too high). Each gun's
  noise radius reaches the AI at 3/4: Hound 35 -> 26 m, Stinger 25 -> 19 m, Wasp 28 -> 21 m, Mauler 40 -> 30 m,
  Lancer 60 -> 45 m (suppressed halves that again; Raiders still hear 1.5x as far). Solo and online. Footsteps,
  knife, grenades and searching are unchanged, and which guns make AI hurry over (alarm) is unchanged.

## 0.20.9 (Sound update: lower, softer new sounds)
- **Bullets snapping past are lower and softer** (owner: "the bullets coming towards us are kinda high pitched"):
  a dull crack and a low falling whoosh instead of a bright crack and whistle, and 4 dB quieter.
- The other bright new sounds are brought down too (owner: "change a bit of those if everything is too high pitch,
  for the new stuff only"): the metal bullet ping, the grenade pin's ring, the safe's dial ticks, the key turning,
  the coins when buying, and the extract countdown beeps.
- Only 0.20 sounds changed; every sound from before the Sound update (the Wasp's shot included) is untouched.

## 0.20.8 (Sound fix: no sound on the web)
- **Fixed: the web game had no sound at all since 0.20.1** (owner: "I can't hear anything now"). The game made its
  sound buses (World, then Voices, Ambience, UI) while running; Godot 4.5's web audio puts a bus added at the end in
  the wrong place and loses Master, so every sound went nowhere. The buses are now set up in
  `default_bus_layout.tres`, loaded when the game starts, and nothing adds buses while running (smoke test checks).
- On the web the indoor echo and the muffling through walls may be lighter or missing (the browser plays the sounds
  itself and skips bus effects); everything else is the same as on desktop.

## 0.20.7 (Sound update: the mix)
- **Volume sliders per kind of sound:** MIX next to Volume in the pause menu opens a slider each for Effects (guns,
  steps, the world), Voices (the AI's callouts and chatter), Ambience and Menus. Volume stays the master slider.
  Hidden until you press MIX, so the menu stays short on phones. Saved with your other settings.
- **The AI's voices have their own bus** (no indoor echo on them), so you can turn them down without the guns.
- **A cap for busy fights** (web and phones): with 40 sounds already playing, new ones more than 25 m away are left
  out; nothing close to you is ever dropped.
- That's the Sound update's whole list built (0.20.0-0.20.7). Next: the owner's listen-through for changes.

## 0.20.6 (Sound update: UI)
- **Menus have sounds now**, soft and low like the sell sound (owner found a bright ring annoying), on their own UI
  bus (`scripts/ui_sounds.gd`):
  - A soft tick on every button, in the hideout and in the raid.
  - Equipping gear into a slot: a cloth rustle and clack (the old move sound still plays).
  - Buying from a trader: a few coins clinking onto the counter.
  - Opening one of Ming's boxes: a cardboard rip and a soft rising twinkle (the old coin sound still plays too).
  - START RAID: a radio chirp and a low drum hit.
  - The extract countdown ticks each second, higher for the last three.
  - The end of a raid: a soft rising chord when you extract, a low falling drone when you're killed or go missing.

## 0.20.5 (Sound update: ambience)
- **The raid has a background now** (quiet, under the game, for you only; `scripts/ambience.gd`):
  - **Wind** outdoors, dropping low when you go inside.
  - **Birds and insects** in the woods: louder the more trees are around you, gone in the middle of town.
  - **The creek** babbling where it's nearest to you, and **the waterfall** rushing, heard from up to 70 m.
  - **The war far off:** a distant artillery thump rolling in every 25-70 s (fits the lore: Novarra and Exion
    are still fighting out there).
  - **Room tone** indoors: a faint hum and still air.
- Everything fades smoothly as you move between them. It all goes through its own Ambience bus, which gets its own
  volume slider at the end of the update. The loops are set to repeat in code
  (`Ambience.looped`: `.import` files aren't kept in git).

## 0.20.4 (Sound update: voices)
- **New gibberish lines** (cartoony, never real words, like today's callouts; `tools/gen_voice_placeholders.py`):
  - **Muttering:** scavs, Raiders and Bon wandering about mutter to themselves now and then (every 20-50 s), quietly
    and only within 20 m. Snipers on their perches stay silent.
  - **A smug chuckle** when one of them kills a player.
  - **"Grenade!":** the nearest AI shouts a frantic warning 1.6 s before your grenade goes off. Only a sound: they
    don't run or do anything different.
  - None of these use up the callout cooldown, so they never hold back a "spotted" or "cover" callout.
- **Bon has his own voice:** every callout again, deeper, slower and rougher (`audio/voice/bon/`), instead of
  everyone's lines pitched down. Today's lines for everyone else are unchanged.

## 0.20.3 (Sound update: items and guns)
- **Each gun reloads with its own pitch:** today's mag out/in sounds, a little higher for the Stinger (pistol) and
  Wasp, a little lower for the Lancer; the Hound as before, the Mauler's shells as before.
- **Swapping guns** clacks the new one into your hands; **aiming down sights** makes a soft cloth rustle.
- **Meds and drinks:** a bandage unrolls and tears, a medkit unzips and rustles, the energy drink cracks open,
  fizzes and gets gulped. Today's heal sound still plays with them.
- **Grenades:** a scrape and ring as the pin comes out when you get one ready (the throw sound is unchanged).
- (There are no pills or food items in the game yet, so no sounds for them; they'll come with those items.)

## 0.20.2 (Sound update: movement and the world)
- **Movement:** a push-off when you jump, a landing thud that's louder the further you fall, hands and boots
  scuffling over a vault, a knock on each ladder rung, a cloth thump going prone. Today's step sounds on landing,
  vaulting and ladders still play; these go on top.
- **Doors:** wooden doors creak open and thud shut (others hear it, up to 30 m), a locked door rattles when you try
  it without the key, the key turns with a click and a clunk, and the bank vault and bunker doors grind open.
- **Searching:** rummaging when you start searching a container; a safe ticks its dial, clunks and creaks open.
- **Bullet impacts by surface:** a dull puff in dirt, a thock in wood, a ping off metal (cars, metal pieces), a sharp
  chip off concrete and stone, within 40 m. The hit markers you hear when you hit someone are unchanged.

## 0.20.1 (Sound update: hearing where things are)
- **Far-off shots roll in:** a shot more than ~45 m away now also has a dull boom with a rolling echo on top of
  today's shot sound (full from 90 m), so you hear a fight across the map and roughly where it is.
- **Muffled through walls:** a sound with a wall between you and it (shots, steps, voices) comes through dull and a
  little quieter; in plain sight it sounds as before. One ray per sound.
- **A light echo indoors:** under a roof (buildings, the bunker and vault) every sound gets a short small-room echo;
  it's off outdoors and in the hideout.
- **Bullets snap past:** someone else's shot that passes within 3 m of your head cracks and whizzes past (not from
  someone right next to you: you hear their gun).
- Today's shot, step and voice sounds are unchanged; these play on top. All game sounds now go through a `World`
  bus (scripts/hearing.gd), ready for the volume sliders at the end of the update.

## 0.20.0 (Sound update: footsteps by surface)
- **Start of the Sound update** (owner, 2026-10-24: "let's do all this"; plan in the project files, `sound/plan.md`).
  Every sound in the game stays as it is: this update only adds new ones.
- **Footsteps sound like what you walk on:** wood floors (houses, cabins, barn, motel, lofts, the railway sleepers),
  metal (cars, the silo, metal pieces), concrete and tile (roads, pavements, car parks, shops, bank, police, school,
  town hall, station, bunker and vault), water when wading the creek, and a leafy rustle on top inside a bush.
  Grass and dirt keep today's step. The same for scavs, Raiders and other players, so you can tell where they are.
- How it knows: the map now lists each colour's name and each building's footprint with its floor
  (`tools/gen_old_bloxov.py` FLOOR_SURFACE), and `BoxMap.surface_at` looks up the box under your feet (about 7
  microseconds a step). Hearing ranges and how far the AI hears you are unchanged.
- New sounds are made by `tools/make_sounds.py` like the old ones (`audio/steps/`); the old files come out identical.

## 0.19.13 (Dirt banks blend in)
- **The dirt banks round the map blend into the ground** (owner: "they look super unnatural in some places"):
  - Shape: a rounded crest instead of a flat loaf top, a steep body that flares into a gentle grassy foot sinking
    under the ground, and a wavering outline instead of a stretched box.
  - Colour: smooth shading and the same hilltop/slope tint the ground uses, so there's no lighter patch, blocky
    facets or seam where they meet the grass; bare earth only shows on the steepest part (the ground shader).
  - Crater rims get the same smooth, ground-tinted shading.
- **Cover is unchanged:** the crest is as high as before, the body is still too steep to walk up, collision follows
  the new shape (the 0.19.7 "stuck after vaulting in" fix still holds, smoke test), sightline check 528 -> 523.
- Behind the scenes: `make_building.write_glb` takes per-corner normals and colours (`Builder.poly(vnormals=, colors=)`);
  the outdoor models and collision were rebuilt from the current map (they were a step behind 0.19.11's map).
  `tools/hump_views.gd` renders eye-level views of chosen map spots.
## 0.19.12 (Gear slot text)
- **The equipment slots' text matches the item tiles** (owner: the text there wasn't good). A filled slot shows the
  item's short name small in the top-right corner (no more big "PRIMARY / Hound" over the picture), and an empty slot
  shows its name small and dim in the top-left. The ammo, armor and backpack numbers stay big at the bottom right.
  Bodies' gear slots match.

## 0.19.11 (Car windows and under tables)
- **Shots go through car windows and under tables too** (owner picked "every visible gap works"):
  - Street cars: the window band between the body and the roof only stops people; shots go through the windows and
    hit the pillars, the roof and the body. Same for the trucks, the tractor and the minibus's windows all round.
  - 100 kinds of building props (tables, desks, office pods, benches, pews, beds and cots, shelves and racks, the
    junkyard's wrecks and fence, the forklift, the pickup, the gas station canopy, the belfry...): shots and eyes hit
    their drawing, so they pass under tables and between legs, slats and shelves. `make_building.py` writes what
    to hit per building (`<name>_shots.json`, `SHOT_KINDS`); props only a bit rounder than their box (toilets, sacks,
    tyres, sofas) stay as they were.
- **Moving is unchanged:** what shots hit is cut to the boxes that stop people (0.19.8's people-only boxes), so you
  and the AI bump into exactly what you did before, and the AI's paths (navigation bake) use those boxes.
- The 0.19.8 pieces (shelters, fences...) now work the same way: their shot triangles are cut to their boxes too.
- Vaulting sees the people-only boxes, so you vault and climb onto tables, fences and the like as before.
- Cost: about 112k more collision triangles (shots only) and a bigger map scene (2.5 MB to 6.2 MB as text).
- Smoke test: the station square's bus shelter (missing pane, glass, kick plate) and the see-through pieces' counts.

## 0.19.10 (Item names)
- **Item names on tiles are small and sit in the top-right corner** (owner: the text over the items bothered him; picked
  this from four options). They use the plain font at 10 px (smaller for long names) in soft white, instead of the big
  bold pixel font across the top that covered the pictures. Counts stay big at the bottom right.

## 0.19.9 (Backpack picture)
- **The Medium Backpack's picture is now the green camo backpack you see in the game** (owner), rendered from its real
  model (`scav_backpack.glb`) instead of a green-and-orange block model.

## 0.19.8 (Shoot through the gaps)
- **Shots go through the gaps you can see** (owner: "i cannot shoot through these cracks in the bus stop, stuff like
  this needs to be fixed"). Found with a map-wide audit: rays across every collision box that a model draws, looking
  for where nothing drawn is in the way.
  - Bus shelters, farm fences, the hunting stands' rails, market stalls, benches, road signs, the clock and the tents:
    shots (and eyes) now hit their drawing, so they pass through gaps, missing panes and glass (glass never stops a
    shot, as with windows), and hit frames, posts, boards and kick plates.
  - Open railings (galleries, the barn loft, the rails round stair holes upstairs), the graveyard railings and the
    police cells' bars: shots and eyes pass, like barred windows.
  - People still can't walk through any of them: their old boxes stay as people-only blockers (BoxMap `bar_boxes`).
    Floors and ramps (the hunting stands') keep their solid boxes.
- The AI now bumps into those people-only boxes too (including barred windows), and the navigation bake counts them,
  so scavs walk round a fence instead of trying to squeeze through its gaps.
- `make_outdoor.py`: `SEE_THROUGH` kinds; `gen_old_bloxov.py`: `PEOPLE_KINDS` and `people=True` boxes.

## 0.19.7 (Stuck in the dirt fix)
- **Fixed: vaulting into a dirt bank got you stuck inside it** (owner's playtest: his friend jumped at a bank by the
  south woods and ended up inside). Map collision is a skin of triangles that stops you from both sides, and from
  inside a bank or rock that skin looked like a top to land on, so the vault planner sent you into it. Vaults and
  the step-up now ignore surfaces seen from behind (at that bank, 160 of 181 possible vaults used to end inside it;
  now none do). Banks are slopes you walk up; you can still vault and climb rocks, walls and cover as before.
- **Safeguard: stuck inside something? You're put back out.** Twice a second the player checks whether they're
  inside the map's collision (a rock, a bank, a wall), caught in its skin or walled in by it. Two checks in a row
  and you're moved to the nearest free spot (on top of it, or beside it, within 5 m). Crouching under an overhang
  that's open to one side doesn't count. (`BoxMap.stuck_inside` / `free_spot`.)
- Needs Jolt's ray face index (`physics/jolt_physics_3d/queries/enable_ray_cast_face_index` in project.godot): it
  tells which way the triangle a ray hit faces.
- Smoke test: the `old_bloxov` section vaults at that bank from every side; a new `stuck` section buries the player
  in a lump and checks they get out.

## 0.19.6 (Inventory glow)
- **New inventory and stash look** (owner: the old one looked a bit plain; picked look B, "Glow", from three options
  drawn on the real screen; the layout stays as it was). Items are dark tiles with their rarity colour rising from
  the bottom and a thin edge, instead of a tinted block with a thick bright border. Grids are flat and dark with faint
  lines and a dot at each corner. Gear slots match.
- **Bigger cells** (44 to 48 px), easier to read and to tap on a phone. The gaps between the panels are a little
  narrower so the hideout still fits the screen with the trader open.
- **Item names in the HUD's pixel font** (on tiles and gear slots) instead of the plain default font. A name too long
  for a 1-cell tile squeezes its letters, and the few still too long ("Bandage") use the small plain font, so no name
  is cut off.
- `tools/inventory_view.gd` takes a screenshot of the hideout's inventory screen with some loot in it.

## 0.19.5 (Vault ramp gap)
- **Fixed: a gap round the town hall's vault ramp.** Going down the ramp (once the ghost cloth had tripped), your eyes
  passed a 1 m band between the hall's floor and the vault's ceiling that had no walls, so you could see out under the
  whole map. The shaft is now walled all round in that band (gen `th_vault`, vault model and far mesh rebuilt).

## 0.19.4 (Item pictures)
- **Every item has a picture** (owner, like Tarkov and Arc Raiders; picked look C: a slight angle with a thin dark
  edge so it reads on every rarity colour and on a phone). Shown in the inventory, stash and container grids, the
  gear slots (and a gun's attachment slots), the trader's stock rows and the quest hand-in window. Tiles now show the
  short name along the top and the count at the bottom, over the picture; a turned item's picture turns with it.
- Guns and attachments use their real models; the other 51 items got small block models of their own
  (`tools/item_models.gd`, no real brands). `tools/render_icons.gd` renders them all to `assets/icons/items/`
  (88 px per grid cell); re-run it after adding an item. The smoke test checks every item has a picture of its size.
  `tools/icon_sheet.gd` draws a sheet of tiles for comparing looks.

## 0.19.3 (Loading screen)
- **A real loading screen** (owner picked option B, "map vista"): START RAID shows a shot of Bloxov Frontlines in
  the late afternoon look, the map's name, a random gameplay tip and ENTERING THE RAID. It replaces 0.18.10's plain
  plate. The web build can't draw while the raid loads, so it's a still picture (no moving bar). The raid then
  keeps the same screen (same tip) up for its first second while it settles and fades it out, so you no longer drop
  into the first laggy frames. (`scripts/loading_screen.gd`; picture `assets/textures/loading_battlegrounds.jpg`.)

## 0.19.2 (Graphics settings)
- **Graphics: LOW / MEDIUM / HIGH** in the pause menu (owner, for web, phones and weak laptops; three big buttons,
  easy on a touch screen). Saved with the other settings; phones start on LOW, everything else on HIGH.
  - HIGH: as before (sun shadows to 60 m, buildings switch to their far mesh 70 m out, full render scale).
  - MEDIUM: shadows to 40 m (smaller shadow map), far meshes from 56 m, 3D drawn at 85% scale.
  - LOW: no sun shadows, far meshes from 45 m, 3D drawn at 70% scale (the HUD stays sharp).
  - Measured with `tools/perf_view.gd -- graphics=0/2` (32 views): LOW averages 596 draw calls against 869 on HIGH
    (-31%), and the busiest view 1.2M triangles instead of 2.1M.
  - Looks only, never what you can see through: bushes, grass tufts and the haze are the same on every setting.

## 0.19.1 (Late afternoon)
- **Raids get the new look: late afternoon** (owner picked option C): a lower, warmer sun with longer shadows, a pale
  warm horizon, a light distance haze and less saturated colours. Looks only; the haze is thin and the AI's sight
  doesn't use it. Today's look stays saved (`assets/looks/classic.tres`) and comes back by pointing `Look.current`
  at it. Cost measured with `tools/perf_view.gd` (32 views): about 3% more draw calls on average (longer shadows
  reach a few more things), frame time the same.

## 0.19.0 (Look update starts: the current look is saved)
- **The Look update starts** (0.19: the final lighting, graphics settings, loading screen). First step, as the owner
  asked: **today's look is saved** as `assets/looks/classic.tres` (sky, ambient light, colour grading, sun, cloud
  colour), so it can always be put back. A raid now takes its lighting from a look file (`scripts/look.gd`,
  `Look.current`), so switching looks is one line. Nothing looks different yet.
- Four new lighting options to pick from (`assets/looks/options/`: overcast, late afternoon, muted midday, smoke
  haze), rendered on the real map. `tools/render_views.gd -- look=<file>` renders any look.

## 0.18.12 (half the draw calls)
- **About half the draw calls on Bloxov Frontlines** (owner: "the whole game just feels kinda laggy"), measured
  with the new `tools/perf_view.gd` (a real raid at 1280x720, four places, eight directions each): the busiest
  view went from 3,045 draw calls to 1,464, the main street from 2,736 to 1,349. Web and phones are held back by
  draw calls most. Looks only: collision, the AI and loot are unchanged.
  - Doors cast no shadow (they sit in their wall's shadow anyway; each shadow was two more draw calls).
  - Doors and loot containers with a roof over them (inside a building) stop drawing past 40 m; outside they keep
    0.18.11's 150 m and 100 m. From farther you'd only see them through a doorway or window.
  - The AI's clothes are merged into one mesh per moving part (body, each leg): a scav was about 10 meshes, now 5.
  - Sun shadows reach 60 m instead of 100 m (sharper up close, too).

## 0.18.11 (fewer draw calls far out)
- **Doors stop drawing past 150 m and loot containers past 100 m** (owner: "give my game more fps"), shadows
  included: out there they're a few pixels tall but each cost a draw call or more. Measured on Bloxov
  Frontlines (1280x720, from a fixed spawn): the busiest view went from 3,413 draw calls to 2,426 (-29%), the
  next from 2,765 to 2,085. Web and phones are limited by draw calls, so this is where they gain most.
  Looks only: collision, the AI and loot are unchanged. (`PixelModel.hide_beyond`.)

## 0.18.10 (START RAID doesn't look frozen)
- **Pressing START RAID shows a loading plate** (owner: "lag when going into raid?"): the raid scene and the map take
  a couple of seconds to load and the game can't draw a frame while they do, so the hideout sat there looking dead.
  The plate goes up and gets two frames to draw before the load starts.
- **The map is warmed in the background** while you're in the hideout, where the machine has threads, so there's
  about a second less to wait on the press. The web build is exported without threads, so there it only gets the
  plate (loading on the main thread there would hitch the hideout instead).

## 0.18.9 (Kill feed)
- **Kill feed** (owner): a short list top left of who killed whom, fading away after a few seconds (the last 5 at
  most). Your kills are brass, a kill you were on the wrong end of is red. Online every player death goes to the
  whole raid, so you see who got who; the AI's names are plain ("Scav", "Raider", "Bon") and other players' names go
  through `NameFilter` before they're shown. Top left so it doesn't sit under the quests or the extract list.

## 0.18.8 (Breakable windows)
- **Windows break** (owner): the 71 panes still glazed round the map are the map's now, not part of the building
  models, so a shot, a vault or a shove through one breaks it, with the sound of it going (a new `audio/glass.wav`).
  Shots were never stopped by glass and still aren't: one passing through takes the pane with it. Online, a break is
  sent to everyone in the raid by pane number. Pipeline: `make_building.py` leaves whole panes out of the model and
  lists them in `art_source/buildings/<name>_panes.json`; `gen_old_bloxov.py` puts them in the map (`window_panes`).
- **What a gun is before you buy it** (owner): hovering a trader's stock row, or tapping its name on a phone, puts
  that item's details in the panel below: the gun's slot, damage, rate of fire, magazine, stat bars and description.

## 0.18.7 (The waterfall end of the map)
- **The waterfall room's roof and walls are fixed** (owner: "the model is messed up"): the knoll's skin boulders were
  poking in through the room's ceiling and walls as big grey spikes. No skin or top boulder reaches into the room
  now (it's thinned, then dropped), and the room's walls are drawn as plain slabs flush with their collision, so you
  no longer stop short of a wall that looks further away.
- **More rock at that end of the map** (owner: "that end of the map needs like some more rocks or smth to make it
  look more natural"): six outcrops along the map's west edge north and south of the knoll, and three boulders out
  from its foot, so the cliff reads as part of a rocky edge instead of one lump in the grass.

## 0.18.6 (The ghost cloth trips)
- **The ghost cloth over the bunker ramp fades once someone goes through it** (owner): the first player or AI to walk
  in trips it and it's gone for the rest of the raid, so the next one in sees the ramp (and that someone's down
  there). Every game sees who walks in, so it works online without sending anything. The runner is its own material
  in the town hall model now ("runner"); `scripts/ghost_cloth.gd` sits on the model over the hole.

## 0.18.5 (Vault ceiling)
- **Bon's vault ceiling doesn't flicker** (owner's screenshot: stripes across the ceiling under the town hall): the
  vault's model draws its ceiling at the same height as the map's ceiling boxes there, and the two fought over which
  is in front. The boxes are still solid but no longer drawn.

## 0.18.4 (Searchable props, better safes)
- **Anything that looks lootable is lootable** (owner: "dont make fake loot spots"): the filing cabinets, drawers,
  nightstands, dressers, trunks, toy chests, footlockers, lockers, tool chests, coolers, freezers, ammo crates and the
  small safes the building models draw (104 of them) are containers now. Each is the size of the drawn piece, has no
  model of its own, rolls light loot (1-2 things, a nightstand 1, the small safes 1 from the safe table, lockers 1-3)
  and takes the loot of the place it's in. `tools/gen_old_bloxov.py` PROP_LOOT (box kind -> table, name, roll);
  `LootContainer` `prop` metadata.
- **Safes are worth opening** (friend's playtest: the waterfall, the vault and Bon's safes gave armor and a couple
  of rare goods): a safe holds 2-3 things (was 1-2), less armor and helmets in the safe table (large backpacks, which
  never fit, are out), and the waterfall room's safes have their own loot (gold, rings, crystals, more epic and
  legendary). Economy sim (500 runs): safe $10.9k -> $19.6k, waterfall $22.9k -> $49.2k, bank $41.5k -> $97.5k (5
  more containers), bunker $76k -> $107k; every container on the map $328k -> $678k (twice as many containers).
- Smoke test: the leaves check stands the player on open ground first (it hit the target dummy depending on where
  earlier sections left the player).

## 0.18.3 (Hitboxes match the map)
- **Rocks, earth banks, crater rims, rubble and the derailed train collide as drawn**, not as the big boxes under
  them: no more invisible walls over a rock or the leaning engine, the tank cars are round, and the hump on the road
  by the offices is the bank itself (walk up it instead of hitting a hidden wall).
- **Mortar craters:** you walk in and out over the rim (it was 8 blocks you got stuck on).
- **Tree trunks** are as thick as they're drawn (shots between close trees go through the gap).
- **Every bush is walk-through** and slows you down inside it (players and AI). Bullets go through bushes (the AI's
  too); the AI still can't see you through one.
- **Jumping:** about 1 m high (was 0.65 m), a press just before landing or just after stepping off an edge still
  jumps, ordinary jumps don't slow you when you land, and low ledges (kerbs, rubble, up to 35 cm) are stepped onto.
- **Barred windows** (gun store, bank and police ground floor, the boarded farmhouse) can't be climbed or jumped
  through; you can still shoot through them.
- **Waterfall:** the two stones in front of the cliff on the way in are gone.

## 0.18.2 (Gun model polish)
- **Owner's picks:** Hound A (wood), Stinger C (tan frame, black slide), Wasp A, Mauler A (wood pump), Lancer C (olive).
- **Real iron sights on every gun:** a rear notch with the front post sitting in it (light dots on the post, three dots on
  the Stinger), a ring aperture on the Wasp, a hooded post and a leaf sight on the Lancer (no more square block), a
  front and middle bead on the Mauler.
- **Wasp:** slimmer barrel and handguard (the fat barrel is gone).
- **Red dot remodelled:** a low housing with a clear window, so aiming shows only the red dot through clean glass.
- **Scopes remodelled:** rounder tubes, tapered objective bells, power ring, rubber eye cup, turret caps and rings.

## 0.18.1 (Gun models)
- **Real models for all five guns**, in first person and in everyone's hands: the Hound (wood and blued steel), the
  Stinger (black polymer pistol), the Wasp (classic SMG with steel struts), the Mauler (black pump with a side saddle
  of shells) and the Lancer (wood army rifle). Three looks were made for each (option sheets in the project files);
  these are the picks for now.
- **Scavs, Raiders, Bon and other players hold the gun they actually carry** (online, the gun you have out is sent with
  your movement, so others see a Stinger when you switch to it). Before, everyone held the same drawn-in rifle.
- **Attachments are real models too:** red dot, 4x and 8x scopes, suppressor, choke and foregrip; the extended mag
  stretches the gun's own magazine. Aiming lines up with each gun's own iron sights or optic.
- Models are built by `art_source/scripts/make_gun.py` (no Blender needed); same mechanics and numbers as before.

## 0.18.0 (the World art update: the whole map remodelled)
Everything built on the World art branch since 0.17.0 goes live at once. The map's layout is the same, but every
building and almost everything outside now has a real model instead of gray boxes.
- **Every building modelled, inside and out (37 of them):** gas stations, shops (laundromat, shoe store, burned-out TV
  shop, facing the street now), school, pharmacy, gun store, the rich houses on the hill, offices (Korven
  Engineering), town hall with Bon's crew living in it and its vault under the floor, bank, police station with a
  custody block, FreshWay grocery, church with its bell tower, graveyard and crypt, the Last Stop Motel, the farm
  (farmhouse, barn with hayloft, silo, machine shed), three cabins in the woods, and the bombed old quarter (train
  station, goods depot, signal box, diner, old gas station, garage, junkyard with its crane and crusher, old houses).
  Rooms are furnished, many have washrooms, windows have glass (some smashed), and loot boxes look like what they
  are in that room (medicine cabinets, lockers, filing cabinets, wardrobes...).
- **Doors:** inner doorways have doors. Press F to open or shut one; the AI opens them too, and online everyone sees
  the same door. About half the doorways have no door or a wrecked one.
- **Outside:** textured ground (three grasses, mud, scorched earth round craters), smooth asphalt roads with lines,
  car parks, street lamps, power lines, road signs, kerbs and paths to the doors; the town square with its fountain;
  real trees and swaying bushes (small bushes you walk through still hide you from the AI, big ones are solid cover);
  cars in four types, burnt wrecks, junk and ruins as real models; the railway with its bridge, boxcars and a derailed
  train; the creek with flowing water starting at a waterfall; set pieces (checkpoint, trench, campsite, hunting
  stands, the farm's fields, hay bales); a border fence with the land carrying on outside the map; extract points
  marked with a camp and a radio mast.
- **Secret room:** behind the waterfall, on the creek's east bank, there is a hidden room with safes.
- **Cover:** about 140 new pieces of cover (ruined walls, containers, earth banks) so you can't be sniped from the
  spawn hill across the whole map; hay bales are new cover too.
- **Moved:** the school sits up by the hill houses, the shops took its old spot (with a car park), the town hall is
  4 m further back. The depot has 2 more loot spots.
- **Sky and light:** clear day with blocky pixel clouds.
- **Speed:** far-off buildings and trees switch to simple versions and shadows are cheaper, so the new map runs about
  40% lighter than it did before that pass. It is still heavier than the old gray-box map, so slow PCs and phones
  may notice it.
- No changes to guns, AI, loot tables or prices.

## 0.17.13 (owner's batch: stash fixes, loading guns, leaves, spawns, quests tab)
- **Load and unload guns in the stash:** right-click (or hold) a gun in the hideout for **Load** / **Unload**, or drag
  rounds onto a gun. Loading takes rounds from your stash first, then what you carry. In a raid you still reload.
- Putting an attachment on your gun (or equipping something) no longer scrolls the stash back to the top.
- Attachments on a gun you loot from an AI (Bon's, a Raider's, a scav's) count as **found in raid**, and stay found
  when you take them off. A bought attachment put on a found gun doesn't become found.
- Ming's boxes were already never found in raid; the smoke test now checks it.
- **Tree tops block the AI:** the AI can't see you or shoot you through the leaves any more. (You and your bullets
  still pass through them, like before.)
- **Spawns:** online, a raid with only your squad always started at the same spawn point (the slots were handed out
  1, 2, 3... per squad, so with one squad only the first point was ever used). Now every spawn point gets used
  evenly. Solo raids were already even (a random pick from all 8).
- **Duo extracts:** you and your partner always get the same extracts now (they were picked from where each of you
  stood, a step apart, so one near the limit could differ).
- The dead scav's backpack: its loot hitbox now sits on the model (it was off to one side).
- **QUESTS tab** on the inventory screen in a raid: press your inventory key and switch to QUESTS to see your quests.
- Lore and roadmap: the escape vehicle, the safe haven and prestige written in as a planned later feature.

## 0.17.12 (scav body = the backpack; owner asked)
- A dead scav (or sniper) leaves its body exactly as before (name, loadout slots, loot), only shown as its backpack
  lying on the ground; no second container any more. Raiders and Bon keep the old body bag.
- Opening it swings open the backpack's own dark green flap with the grey button (the extra lid piece is gone).

## 0.17.11 (dropped backpack lies flat, lid in the backpack's own camo; owner asked)
- A dead scav's backpack now lies on its back on the ground instead of standing up.
- The lid uses the backpack's own camo texture, and the grab handle sits on the lid, so it opens with it.

## 0.17.10 (scavs drop their backpack, backpack lid opens; owner asked)
- A scav that dies drops its small backpack on the ground beside its body (on whichever side isn't against a wall).
  Its loose loot is inside the backpack now; its gun, armor and helmet stay on the body. Snipers wear one too.
- Opening a dropped backpack swings its lid open; leaving it (closing the screen or walking off) swings it shut.
  Online, everyone in the raid sees the lid move. The lid is a simple placeholder piece on the current model until
  the final backpack art.
- Smoke test: a dead scav's backpack lies on the ground with loot in it, the lid opens and shuts, and online the
  other player gets the backpack and sees its lid move.

## 0.17.9 (AI always shoot first; owner asked: a Raider ran off the moment it saw him)
- When a fight starts, the first thing every AI (scavs, Raiders, Bon) does once it sees you is stand and open fire
  for 2-3 seconds. Before, a Raider that spotted you after a quiet spell could roll a flank and run off to a hidden
  spot without shooting, and one that spotted you from beyond its range ran for cover; both looked like running away.
  Flanks, cover runs and pushes still happen, just after that opening volley. Out of range it now moves up instead.
- A teammate that's just about to open fire on you isn't sent off to flank by another AI either.
- Unchanged: badly hurt AI still go for cover first, and one sniped from beyond its range by someone it can't see
  still hides (0.15.26).
- Smoke test: a Raider set to always flank, 20 m and 50 m off, shoots before any flank or cover run.

## 0.17.8 (no more hitch when shooting; owner reported stutters before/when shooting)
- Every muzzle flash (yours and the AI's) lit up the area with a real light for a split second. The web renderer
  has to build extra shaders for everything that light touches the first time, which froze the game for up to a
  second on the first shots of a raid and whenever a gun fired near something new; while lit, everything near it
  was also drawn twice. The flashes stay, without the light: smoother on phones and slow PCs too.
- Tracers and impact puffs are now drawn once, too small to see, at raid start, so their shaders are ready before
  the first shot instead of being built mid-fight.

## 0.17.7 (mouse no longer stutters on fast turns; owner's friend reported it)
- Turning the mouse fast could stutter and stop turning until you slowed down (Chrome and Firefox). A glitch
  filter from 0.1 threw away every mouse move over 200 pixels, and a fast flick on a high-DPI mouse (raw input
  is on) easily passes that in one frame. Now only a lone jump far bigger than the move before it is ignored
  (the Chrome glitch it was made for), never two in a row, so real fast turns always go through.
- Smoke test: a fast turn is used in full, a lone glitch jump is dropped, a flick from rest loses at most one move.

## 0.17.6 (scav backpack turned around; owner asked)
- The scav backpack faced the wrong way (its back side pointed out). Turned 180 degrees so the straps sit on the scav.

## 0.17.5 (Esc closes the pause menu, $50k start, scav backpack, one tab at a time; owner asked)
- Escape in the pause menu closes it (it did nothing before, only a click got you out). In the browser it shows
  "Click to keep playing" (a browser only gives the mouse back on a click) and the game stays paused until then.
  With LEAVE RAID's question open, Escape goes back to the menu.
- New players start with $50,000 (was $15,000). Existing saves keep their own money and everything else.
- Every scav wears the small backpack (model by the owner's friend, `assets/models/characters/scav_backpack.glb`).
  Looks only: what scavs drop is unchanged.
- The free kit adds a small backpack (sells for $0, like the rest of the kit).
- Only one browser tab plays (TabLock, a Web Lock): every tab kept its own copy of the profile and saved all of it,
  so a second tab could take the same gear into another raid and keep it if the first died, or hand a copy to
  itself online. Any other tab now shows "Bloxov is already open in another tab", never saves, and starts by
  itself (reading the fresh save) once the first tab closes.
- Smoke test: scavs wear the backpack, $50k start, an old save keeps its money/stash/loadout/stats, the free kit's
  backpack, and the tab lock off the web.

## 0.17.4 (Bon keeps shooting on his breaks, flanks again; owner asked)
- Bon opens fire as soon as a break between chases starts and keeps firing through it (standing or stepping aside),
  so he's never just standing there.
- Bon flanks again (30% of lulls, as before 0.17.3). A flank that finds no hidden spot still never sends him to cover.

## 0.17.3 (Bon the juggernaut; owner asked)
- Bon never takes cover: no ducking to reload or when shot, no hiding when sniped from far away, and he doesn't play
  safe when badly hurt. He chases from 45 m (was 30), walking at you and firing, and no longer flanks.
- He doesn't chase non-stop: after 3-5 s of chasing he stops for 1.5-2.5 s, standing and firing or (half the time)
  stepping a few meters to one side while firing, then comes on again. His guards fight as before (cover included).
- Smoke test: Bon never takes cover, doesn't play safe when hurt, and pauses between chases.

## 0.17.2 (found-in-raid only for quest items, steady trader column; owner asked)
- The found-in-raid mark now only matters for items an open quest wants (e.g. bandages for First Aid). Everything
  else stacks together again, found or bought (ammo too); stacking a found stack with a bought one makes it unfound.
  The "(found in raid)" note only shows on items a quest wants.
- The trader column keeps one width for every trader (the widest one's) instead of resizing when you switch tabs;
  its scroll bar always shows.
- Smoke test: the PvP section ignores the raid's AI hitting the target (made it flaky).

## 0.17.1 (playtest fixes: LEVEL UP, quest tracker, damage after armor, ammo names; owner asked)
- Traders get a **LEVEL UP** button: once a level's quests are done (and, for the Gunsmith and Supplier, its money
  spent with them), press it to level the trader up and unlock the new stock. Until the money is spent the button
  says how much is left. The hideout says when a trader can level up. Fixed: the "spend $X more" hint showed the
  level 2 amount even at level 2. Old saves keep the levels they had.
- **Quest tracker** in the pause menu: a panel beside it lists your open quests with progress, and what this raid
  adds once you extract (e.g. "+2 when you extract").
- Online, your damage number on another player now shows what the hit really did **after their armor** (their game
  reports it back). Numbers on AI were already after armor, solo and online.
- Ammo is named after its gun: Hound Rounds, Stinger Rounds, Wasp Rounds, Mauler Shells, Lancer Rounds.

## 0.17.0 (World art update starts: neutral lighting baseline)
- New lighting for raids, the base the World art models get built against: a calmer, less saturated sky, a
  slightly warm sun with a bit more contrast, weaker blue sky light (the map no longer looks washed-out and
  mint-green), and a small overall saturation cut. No gameplay change.
- `tools/render_views.gd` renders a few fixed views of the map for comparing art and lighting changes.

## 0.16.14 (quest hand-in window; owner asked)
- HAND IN on a quest opens a window: your found-in-raid items that count on the left, the trader's box on the right.
  Tap an item to put it in the box (tap again to take it back), then HAND IN. You can hand in part of a quest
  (e.g. 1 of 2) now and the rest later; progress is kept.

## 0.16.13 (trader quests; owner asked)
- Trader levels now come from **quests** instead of spending (owner: "quests instead of buying items to unlock items").
  Each trader's tab lists the quests for their next level, with progress, rewards and a HAND IN button.
  - Gunsmith level 2: Zeroing In (kill 5 scavs), Spare Parts (hand in 2 attachments), Field Test (3 scav kills
    with a Mauler), plus $15,000 spent with him. Level 3: Overwatch (2 snipers), Hard Targets (3 Raiders), Big
    Game (Bon), plus $40,000 spent.
  - Medic level 2: First Aid (hand in 3 bandages), House Call (extract 3 times). No money needed.
  - Supplier level 2: Packing Up (extract with $10,000+ of loot), Scrap Run (hand in 2 armor vests or helmets),
    plus $5,000 spent.
  - Kills and extracts only count once you get out alive. Each quest pays $1,500-$10,000. No player-kill quests.
- **Found in raid:** loot from containers and bodies is marked "found in raid" (shown in its info). Only found items
  can be handed in, so buying the item doesn't work. Found stacks don't stack with bought ones.
- Names and quest text are placeholders until the owner renames them. Levels reached by spending before this
  update go back to level 1 until their quests are done (what you already bought stays).

## 0.16.12 (the valuables trader is Supreme; owner named it)
- The trader who buys valuables and keys (was "Fence", a placeholder) is now called Supreme.

## 0.16.11 (spectate after extracting; owner asked)
- Online, after you extract while a teammate is still in the raid, the end screen has SPECTATE <NAME> too (before,
  only after dying). Same over-the-shoulder view; when they're out, the end screen comes back.

## 0.16.10 (drag items out to drop them; owner asked)
- In a raid, dragging one of your items (or something you're wearing) out of the inventory onto empty space drops it
  on the ground, like right-click > Drop. Letting go on or between the panels does nothing. The hideout has no
  ground, so there the item just goes back.

## 0.16.9 (scavs hit players online; owner's report)
- Online, AI shots now actually hit players. Each player is a stand-in body on the server, and that body was paused,
  which (Godot default) also took it out of physics, so every scav bullet passed straight through. It stays in
  physics now. Online AI will feel a lot more dangerous: this is the intended damage, it just never landed before.

## 0.16.8 (damage numbers online; owner's report)
- Online, damage numbers (settings toggle) now show when you hit an AI or another player, like they do solo. The
  server sends the damage with the hit confirm: an AI's real damage taken, a player's before their armor.

## 0.16.7 (free kit items sell for $0; owner asked)
- Free kit items can be sold again, for $0, so you can clear them out of your inventory (before, traders refused
  them). The item info says "free kit: sells for $0".

## 0.16.6 (nothing in the free kit sells; owner asked)
- The free kit's 30 rounds and bandage are marked as free kit items too, so nothing from the kit sells. They only
  stack with other free kit items (bought or found rounds stay separate and sellable), and they keep the mark when
  moved, split, dropped, saved, or used and cancelled.

## 0.16.5 (free kit pistol sells for nothing; owner asked)
- The free kit's Stinger is marked as free kit gear: traders won't buy it (the item info says so). A Stinger you
  find or buy still sells as normal. The kit's 30 rounds and bandage still sell (about $480; with one kit per raid
  that's not worth farming).

## 0.16.4 (free kit once per raid; owner's report)
- The free kit can only be taken once per raid: after taking it you have to go on a raid (solo or online) before
  you can take another. Before, you could take it, sell it and take it again for endless money.

## 0.16.3 (free kit online; owner's report)
- Online, the free kit button reads **TAKE FREE KIT**: it puts the pistol, 30 rounds and bandage on you and you
  stay online, so you can queue with your party. Offline it's still RAID WITH FREE KIT (starts a solo raid).
  Same rule as before: only when you carry nothing at all.

## 0.16.2 (Ming's mystery boxes; owner asked)
- New trader tab **MING**: Uncle Ming keeps the outpost entertained with mystery boxes. Pay, and one random item
  from the box goes to your stash. Every box shows its odds before you buy.
  - **Gun Box** $12,000: Stinger 30%, Wasp 25%, Mauler 20%, Hound 15%, Lancer 10%.
  - **Gear Box** $10,000: light armor 30%, old helmet 25%, medium backpack 20%, large backpack 9%, heavy armor 8%,
    combat helmet 8%.
  - **Loot Box** $3,500: a common 30%, uncommon 30%, rare 25%, epic 12% or legendary 3% valuable.
  On average a box gives back a little less than it costs (a money sink), but it can skip trader levels or land
  loot-only gear.
- Earned money only: Ming never takes the future premium currency (STORE_RULES.md section 5). Casino games
  (blackjack, slots, coin flips) are left out on purpose, since they count as simulated gambling for age ratings.
- The trader tabs are smaller so five fit.

## 0.16.1 (price pass; owner OK'd raising gear prices about 5x)
- Gear costs about **5x more**: guns, attachments, ammo, meds, armor, helmets, backpacks and drinks (Hound $12,500,
  was $2,500; Lancer $22,500; bandage $500; rifle round $15). Valuables and keys keep their values, so loot stays
  exciting and a good kit costs about 2-3 normal raids (`tools/economy_sim.gd`). Gear you find sells for more too
  (still 60%).
- New profiles start with $15,000 (was $3,000). The free kit is unchanged.
- Trader levels and stash upgrades scaled with it: Gunsmith level 2 at $40,000 spent, level 3 at $120,000; Medic
  level 2 at $5,000; Supplier level 2 at $10,000; stash upgrades $50,000, $120,000, $250,000.

## 0.16.0 (Economy update starts: traders and stash upgrades; owner's plan)
- The one trader is now four, each on its own tab: **Gunsmith** (guns, ammo, attachments, grenades), **Medic**
  (bandages, medkits), **Supplier** (armor, helmets, backpacks, energy drinks, stash space) and **Fence** (buys
  valuables and keys, sells nothing). Names are placeholders until the owner picks them.
- **Trader levels:** spending money with a trader levels them up and unlocks more stock. Gunsmith: Stinger, Wasp,
  Mauler, red dot, choke at level 1; Hound, rifle rounds, foregrip, extended mag, grenade at level 2 ($15,000
  spent); Lancer, sniper rounds, scopes, suppressor at level 3 ($40,000). Medic: medkit at level 2 ($3,000).
  Supplier: medium backpack, light armor, old helmet at level 2 ($5,000). Locked items show the level they need.
- Selling: right-click still sells anything; it goes to the trader that buys that kind (gear 60%, valuables full
  value, same as before).
- **Stash upgrades:** a new stash is 8 x 20 (was 8 x 30; saved stashes keep their size). The Supplier sells
  +10 rows for $25,000, $60,000 and $120,000, up to 8 x 50. Earned money only.
- Prices are unchanged in this version; the price pass for "a good kit costs 2-3 raids" comes next.
- New dev tool: `tools/economy_sim.gd` rolls the real map's loot thousands of times and prints what raids earn
  next to what kits cost.

## 0.15.30 (map label fix)
- Full map (M): the SHOPS name in town sits above its building now. It was hidden under the "Town Road" extract
  name. Found running the game through godot-mcp on the owner's PC.

## 0.15.29 (PMC dog tag; owner asked)
- A player killed online by another player drops their dog tag, named after them ("Tavish's Dog Tag"), in its own
  Dog Tag slot at the top of their body's loot window. No tag if the AI (or anything else) killed them. The name
  stays on the tag in your stash, and it sells for $2,500.

## 0.15.28 (online raid fixes; owner's playtest)
- Online hit registration: shots at AI are checked where the AI was on your screen (like other players already
  were). Before, the server checked where the AI was right then, so shots at a moving AI (often the first few,
  while it ran for cover) missed. Shots that arrive bunched up over the internet all count now (the fire-rate
  check dropped some of a full-auto burst).
- Online you hear other players shoot (their gun's own sound, quieter with a suppressor) and see the tracer.
- AI that lose you up close and can't get to where you were now hunt for you (30 s) instead of a 5 s look round.
- RAID WITH FREE KIT (replaces the Free kit button): starts a solo raid with a pistol, 30 rounds and a bandage.
  Only shows when you carry nothing at all (nothing equipped, nothing in your pockets, backpack or secure pocket).

## 0.15.27 (Wasp mag; owner asked)
- The Wasp holds 25 rounds (was 30), 35 with an extended mag (was 45).

## 0.15.26 (AI run from snipers; owner picked it)
- An AI shot from beyond its own shooting range (about 70 m, e.g. a Lancer) that can't see the shooter runs off to
  a hidden spot farther away, then lies low for 20 s watching that way before it goes looking. If it sees you in
  range it fights as before: shooting back comes first. Closer fights are unchanged.

## 0.15.25 (AI change from 0.15.24 reverted; owner)
- Back to how AI reacted before 0.15.24 when shot by someone they can't see (the owner meant something else). The
  softer sell sound stays.

## 0.15.24 (AI shot from out of sight, softer sell sound; owner asked)
- An AI shot by someone it can't see (too far, or hidden) gets out of the line of fire into cover first, then goes
  looking for the shooter. Before, it walked straight at them in the open. It doesn't run away (owner, 0.12.32).
- The sell sound is softer and quieter: two low notes instead of the bright coin ring.

## 0.15.23 (Bigger safes, patrols start differently; owner asked)
- Safes are 4x4 (were 3x3), so a large backpack found in a safe fits instead of being rolled again.
- AI start each raid facing a random way and wait a random 0-8 s before their first patrol stop, so they don't all
  set off together the same way every raid. Fights are unchanged.

## 0.15.22 (Richer bank vault; owner asked, numbers ours)
- Bank vault safes: the Holy Grail 3% each (was 1%; the bunker stays 1%), and the golden toilet about 6% each (an
  extra 3% on top of every safe's 3%).

## 0.15.21 (Never-empty safes, swap any item; owner reported)
- A safe could come up empty: when it rolled something too big to fit (a large backpack is 4x4, a safe 3x3), the
  item was lost. Rolls that don't fit are rolled again, so no container is ever empty.
- Dropping an item onto another works the same for every item: it goes where you drop it (or elsewhere on the item
  under the pointer), and whatever it covers moves out of the way, to where your item came from or any free space.
  A grenade dropped on a medkit now swaps; before, it only worked when each fitted the other's exact spot.

## 0.15.20 (Build fix)
- 0.15.18 and 0.15.19 didn't deploy: the SORT button's "SURE?" reset timer could fire after the stash screen was
  gone, and the web build stops on that error. The timer now goes away with the button.

## 0.15.19 (Drop option, scav backpacks, rare loot; owner asked)
- Right-click an item while looting (a crate, a body) now offers "Drop" (on the ground) as well as "Put in".
- Scavs wear a small backpack 7% of the time, so their body has one to loot (the friend's backpack model comes later).
- The golden toilet is rarer: only in safes, 3% each (it used to come from any legendary roll, about 7% of safes,
  and the antiques house).
- The Holy Grail is only in the bank vault and the town hall bunker: 1% in each safe there (was 15% in a town hall
  locker and 5% in the vault).

## 0.15.18 (Playtest batch 2; owner asked)
- Keys: the bunker key only comes off Bon now (no more in town hall or police lockers). The bank vault key: 2% on
  Raiders, 2% in lockers (was 10% Raiders, 2% crates).
- AI push you when you're under 40% health, like they do while you heal or reload (online too: your game tells the
  server you're low).
- Selling an item plays a sound (the item-move click and a coin ring).
- The stash's SORT button asks first: tap once and it turns to SURE?, tap again to sort (back to SORT after 3 s).
- The stamina bar is green when high, yellow in the middle, red near the end; running out still shows the red
  recharge stripes.
- Headshot damage numbers drop the "!": the colour tells them apart.
- Removed the tree growing inside Cabin 3.
- Scrap Metal stacks to 3.
- Roadmap: the base map stays friendly (harder maps later), and the art update fills the map with debris and clutter
  so you can't see or snipe lots of scavs from spawn.

## 0.15.17 (Attachment slots on equipped guns; owner asked)
- An equipped gun's slot (Primary/Secondary) in the hideout and raid inventory shows its attachment slots along the
  bottom, each with a small picture of what's fitted (empty ones are named: SCP, BRL, GRP, MAG, SGT). Point at one
  for its info; click or tap a fitted one to take it off. Dropping an attachment on the gun lights up the slot it
  goes in. Guns in the inventory grids look the same as before.
- Checked every gun's hits (owner asked): body and head shots land for the right damage in single player and
  online; the smoke test now checks all five guns both ways.

## 0.15.16 (Playtest fixes: place loot, patrols, stash sort, drop pile; owner asked)
- Loot by place now shows: a place's own loot counts 3x, so pharmacy crates are mostly meds, the gun store mostly
  guns and ammo, the school mostly backpacks. Anything can still turn up anywhere. Keys aren't boosted.
- AI patrols spread out: an AI won't pick a patrol stop another AI (outside its own group) is already heading for,
  so they stop walking the same path in a line. Fights are unchanged.
- The stash has a SORT button: it merges part stacks and lays everything out by kind (guns, gear, ammo, meds,
  valuables last), big items first.
- Dropping items one after another puts them on one "Dropped Items" pile at your feet (online too) instead of a
  new bag each time.
- Bolts stack to 10.

## 0.15.15 (Weaker choke; owner: the Mauler hit too hard too far with it)
- The choke tightens the Mauler's pellets by 15% instead of 30%, so a choked Mauler stops landing nearly every
  pellet past about 15 m.

## 0.15.14 (New gun shots stay close to the original; owner: "I really like the sounds we have")
- The Wasp, Mauler and Lancer shots from 0.15.12 are remade as small tweaks of the original shot instead of new
  sounds: Wasp a bit shorter and lighter, Mauler a bit deeper and fuller, Lancer a bit sharper with a short echo.
  The Hound, Stinger and every other sound are unchanged.

## 0.15.13 (PLAY in the pause menu resumes on the first click; owner: it felt unresponsive)
- Clicking PLAY (or anywhere outside the menu) right after pressing Escape often did nothing: browsers refuse to
  give the mouse back for about a second after Escape let it go, and the game only asked once. Now it keeps asking
  for up to 2 seconds after your click, so one click is enough. PLAY also reacts when you press the mouse button,
  not when you let go.
## 0.15.12 (Gun stats, gun sounds, online AI guns; owner picked these)
- Gun stat bars: pointing at a gun in the inventory shows bars for damage, fire rate, range, control, handling and
  quiet. Attachments show as a green gain or a red loss on top of the bare gun.
- New sounds for the Wasp (short, snappy), Mauler (heavy boom), Lancer (sharp crack with a long echo), the
  Mauler's pump and shells going in, and the Lancer's bolt. The Hound and Stinger keep their sound, and every
  other sound is unchanged. AI with these guns use the same sounds.
- Online, the AI now hold, sound and shoot like the gun they really carry (before, every AI looked and sounded
  like a Hound, and their shooting numbers could differ from the server's).

## 0.15.11 (AI fight to suit their gun; owner asked)
- Same fight brain, only how close they like to get changes with the gun:
  - Mauler AI rush you: they chase from as far as they can hit (22 m), walk in faster and hardly ever stop for cover.
  - Wasp AI are aggressive: they chase from 40 m (was 30), walk in a bit faster and spray to pin you down more.
  - Stinger AI are careful: they only chase within 15 m and take cover more often.
  - Hound AI and the Lancer snipers fight as before.

## 0.15.10 (The pistol is now the Stinger; owner's pick)
- The Pistol is renamed the Stinger. It's the same gun with the same stats, and saved pistols keep working.

## 0.15.9 (The AK is now the Hound; owner's pick)
- The AK Rifle is renamed the Hound, a made-up name like the Wasp, Mauler and Lancer. It's the same gun with the
  same stats, and saved guns keep working.

## 0.15.8 (Trader list scrolls; owner: "its going off the screen")
- The trader's stock is now a scrolling list under the TRADER title and hint, so every gun, ammo and attachment
  can be reached. Scroll with the mouse wheel, the scroll bar, or by dragging with a finger on a phone.

## 0.15.7 (The Mauler looks like a shotgun; owner: "i cant tell what it is")
- New placeholder shape for the Mauler: a fat barrel with the shell tube under it, a big ridged orange pump, a
  short receiver with no mag, a pistol grip and a wide stock. At the hip it's turned a little so you see the pump
  side on; aimed, it lines up straight down the barrel to the bead sight.

## 0.15.6 (Gun feel: attachments show on the gun, pump and bolt action)
- Attachments show on the gun in your hands: sights and scopes on top, a suppressor or choke on the muzzle (the
  flash moves out to its end), a foregrip under the barrel, a longer extended mag. Aiming with a red dot lines
  you up through the dot. (Placeholder blocks until the art pass.)
- The Mauler pumps and the Lancer works its bolt between shots, with a click; loading shells rolls the shotgun
  over with a push per shell.

## 0.15.5 (AI loadouts; scavs drop their gun; owner's Guns plan)
- Every scav and Raider now rolls a gun when it spawns. Scavs: AK 40%, Wasp 25%, Mauler 20%, pistol 15%.
  Raiders: AK 50%, Wasp 30%, Mauler 20%. Sniper scavs carry the Lancer, Bon an AK with a 4x scope and a grip.
- The gun changes how it shoots (only the numbers; how the AI fights is unchanged):
  - **Mauler**: one hard hit at a time (you go down in about 4 instead of 7), but only within about 22 m.
  - **Wasp**: longer, faster bursts that each hurt less, and a shorter reach.
  - **Pistol**: short bursts, slower, a bit weaker.
  - **AK**: exactly as before. Overall danger stays about where it was.
- Their shots sound like their gun (Wasp higher, Mauler deeper).
- Scavs now drop their gun 15% of the time (owner), sniper scavs their Lancer too. Raiders still 30%, and a
  Raider's gun sometimes comes with an attachment. Bon's AK drops with its scope and grip.
- For now every AI still holds the AK model whatever it carries; showing the real gun comes with the art pass.

## 0.15.4 (Three new guns: Wasp, Mauler, Lancer; owner OK'd names and numbers)
- **Wasp** (SMG): full auto, 900 rounds a minute, 30-round mag, 20 damage (5 body shots). Great from the hip,
  light kick, but its damage drops past 25 m (down to 14 by 50 m). Uses its own **SMG Rounds** (owner).
- **Mauler** (pump shotgun): 8 pellets of 14 damage per shot (one blast kills up close), 6 shells, loaded one at a
  time; you can fire whatever's loaded mid-reload. Pellets do much less past 12 m. Uses **Shotgun Shells**.
- **Lancer** (bolt-action sniper): 90 damage (2 body shots, one headshot kills), 5 rounds, slow to work the bolt,
  terrible from the hip, loud. Uses **Sniper Rounds**.
- Each has its own sound (Wasp higher, Mauler and Lancer deep and loud), kick and muzzle flash size.
- Scopes now show a scope view when you aim (round view, black around it, a cross and a red center), and the
  red dot shows a red dot. The 8x Scope (Lancer only) and the Choke (Mauler only) now turn up too.
- Where to find them: gun store (all three), police station (Mauler), bunker (Lancer), lockers now and then. The
  trader sells all three, their ammo and every attachment. Ammo turns up in crates and on bodies.
- Placeholder first-person models for now (the art pass makes real ones).
- Online: the server checks every pellet; pellets that hit the same player add up into one hit.

## 0.15.3 (asks before closing the tab mid-raid; owner's friends kept hitting Ctrl+W)
- In the browser, closing or reloading the tab (Ctrl+W, the X, F5) during a raid now asks "Leave site?" first.
  Only while the raid is on: in the hideout and on the end screen the tab closes as normal. The browser writes
  the question itself (pages can't change its words), and it only shows once you've clicked in the game.

## 0.15.2 (Escape in the loot screen goes back to the game; owner's friends hit the pause menu)
- Escape while looting a body or container (or in your backpack) now always closes it and shows "Click to keep
  playing", never the pause menu. It used to grab the mouse right away, and a browser that let go again (Escape
  still held) dropped you in the pause menu. Now the mouse is only grabbed on your click. Tab still closes the
  screen and puts you straight back in.
## 0.15.1 (Attachments; owner's Guns plan)
- Guns have attachment slots: AK scope, barrel, grip, mag; pistol barrel and sight. Each attachment's stats
  add to the gun:
  - **Red Dot** (sight/scope): aim 15% faster, a little more zoom.
  - **4x Scope** (scope): zooms right in, aiming 20% slower.
  - **Suppressor** (barrel): your shots are heard half as far (by the AI too, online as well), 10% less kick.
  - **Foregrip** (grip): 20% less kick.
  - **Extended Mag** (mag): 50% more rounds (AK 45), reload 10% slower.
- Putting one on: drag it onto the gun (in a grid or your gun slot), or right-click it and pick "Attach to
  <gun>" (no dragging needed, good for phones later). Swapping puts the old one back where the new one was.
  Right-click a gun to take its attachments off. Taking an extended mag off a full gun gives you the extra rounds.
- The gun's info line lists what's on it, and a gun is worth its attachments too when you sell it.
- Found in the gun store, police station, bunker and on Raiders; the trader sells all five.
- Already in for the new guns: an 8x Scope (sniper only) and a Choke (shotgun only); they only drop once those
  guns exist.

## 0.15.0 (Guns update starts: no more RPK; owner asked)
- Raiders and Bon now hold an AK instead of the RPK that was drawn into their model (owner: "I don't want an
  rpk"). It was only ever the look: there's no RPK item, and how they shoot hasn't changed.
- Under the hood: the gun a character holds is now its own piece, swapped onto the model (`HeldGun`), so later
  each AI can show the gun it really carries and the art pass can drop real gun models in.

## 0.14.24 (LEAVE RAID in the pause menu; owner asked)
- The pause menu (Esc) has a LEAVE RAID button under PLAY. Pressing it asks first ("Leave the raid? It counts
  as dying...") with STAY and a red LEAVE, so a misclick can't end your raid. Leaving counts as dying: you keep
  only your secure pocket, it adds a death, and the end screen says LEFT THE RAID. Online you drop where you
  stand and your body can be looted, like any death. Buttons are big enough to tap.

## 0.14.23 (no black bars on wide or narrow screens; owner asked)
- The game now fills the whole window at any shape. It used to keep a fixed 16:9 picture and put black bars
  on the sides (wider screens, e.g. phones and ultrawides) or top and bottom (4:3, 16:10). Now the view just
  shows a little more to the sides (or above and below), and the HUD and menus stay pinned to the edges.
  Checked at 16:9, 21:9, 19.5:9 (phone), 16:10 and 4:3.

## 0.14.22 (vault through a window with a crate under it; owner asked)
- A crate (or anything low) in front of a window no longer blocks it: you used to climb onto the crate or not
  vault at all. If the near thing can't be vaulted over, cover up to 1.2 m behind it is tried, and vaulting over
  wins over climbing onto. Landing on a crate on the far side already worked.

## 0.14.21 (Death screen; owner asked)
- When you die or go missing, the end screen's lost list and LOST total leave out your secure pocket, since it
  comes home with you. Extracting still lists and counts everything.

## 0.14.20 (AI vaulting scrapped; owner decided)
- The AI doesn't vault any more, not even fences or windows: it walks round. The owner asked to scrap AI vaulting
  entirely if it caused the stair-ramp bug, and it did (0.14.19). The navigation map no longer links across low
  cover. Players still vault as before.

## 0.14.19 (AI fell through stair ramps; bug fix, owner reported)
- AI walking up the stairs inside buildings no longer drop through the ramp to the floor below. Since 0.14.14 the
  vault check counted the rising ramp in front as cover and "vaulted" over it, landing downstairs. A slope you can
  walk up isn't cover any more (players too: Space on a ramp no longer vaults you through it). On the real map 25 of
  28 ramps failed before; all the stair ramps work again. The smoke test checks a ramp now.

## 0.14.18 (grenade damage, right-click to cancel; owner asked)
- Grenade damage: 80 on a direct hit, falling off evenly to nothing at 7 m (was 120 within 1.5 m).
- Cancel a heal or drink with **right-click** now (was the same key again), still only after the first second.
  Once you can, a "[mouse, right button lit] TO CANCEL" plate shows under the healing bar. Phones get a cancel
  button with the touch controls.

## 0.14.17 (grenade and heal animations, cancel heal; owner asked; placeholders)
- **Grenades:** key 4 now pulls one out (the gun drops out of the way and a gloved hand brings the grenade up),
  click throws it (a quick wind-up, then it flies), and key 4 again, or switching guns, puts it away. The fuse
  still starts when it leaves your hand. You can't shoot or aim with a grenade out.
- **Healing and drinking:** same as before, but now the gun lowers and the hand shows the bandage, medkit or can
  while you use it.
- **Cancel a heal or drink:** press the same key again (H, 3 or its hotbar key). Only after the first second (no
  heal-cancel spam); you get the item back.
- All placeholder looks (owner: the real art comes later in the roadmap). New `HandItem` (`scripts/hand_item.gd`).

## 0.14.16 (drag to swap; owner asked)
- Drop an item onto another one and they swap places (in the same grid or between your inventory and a stash,
  crate or body), as long as each fits in the other's spot. Same items still stack instead.

## 0.14.15 (playtest fixes, batch 1; owner asked)
- Right-clicking in the inventory no longer zooms in with your gun.
- No shooting and throwing at once: the gun can't fire for 0.6 s after a throw, and you can't throw within 0.3 s
  of a shot.
- Medkits are 2×1 (were 2×2) and stack to 3. (Bandages already stacked to 5.)
- Dog tags only come off bodies (one per Raider, Bon's on Bon, a PMC tag on player bodies online), never from random
  loot.
- The bank vault key: a 10% chance on each Raider and a 2% chance in each crate (for now). It's no longer in
  police and office loot.
- Energy drink: fills your stamina, then sprinting costs no stamina for 10 s (was: half cost and double regen for
  30 s).

## 0.14.14 (vault anything vaultable; owner asked)
- Fences vault now: the check for a top looked 15 cm in, exactly a fence's thickness, and missed it. It looks at
  a few depths now and takes the highest.
- Raised cover counts too (a ramp's side, a counter or crate on legs): cover is looked for at four heights from
  knee to chest, not just one.
- When there's no room on the far side (cover against a wall), you climb onto it instead of the vault failing.
- Same rules for the AI (it still only vaults over, never onto). Things that are too tall, too thick or have no
  room to stand stay unvaultable, so you can't vault into walls or out of the map.

## 0.14.13 (hideout message font; owner asked)
- The hideout's message tape ("Sold ... for $...") uses the HUD's pixel font now: the old tape font spaced its
  letters unevenly ("Ra ider", "Ta g").

## 0.14.12 (the Holy Grail; owner asked)
- **Holy Grail** ($75,000, 2×2): the most valuable item in the game. It never comes from random loot: each raid
  there's a 15% chance it's in the town hall's first locker (the town hall has no vault yet) and a 5% chance it's
  in the bank vault's first safe. New `ItemDB.SPECIAL_FINDS` holds these one-off finds by container name.

## 0.14.11 (AI fight back when you show up mid-move; owner asked)
- An AI running to cover or round a flank now stops and shoots when you come at it (you've moved a few meters
  and are within 12 m and in view), or when it set off with you out of sight or out of range and you then show up
  in range. Before, it only stopped if you shot it up close, so one kept repositioning while you walked right up to it.
  Everything else about the AI is unchanged.

## 0.14.10 (full item names on tiles; owner asked)
- Item tiles show the whole name: on one line if it fits, else one word per line ("Raider / Dog / Tag" instead of a
  cut-off "Raider"), in the biggest text that fits. The name uses the whole tile unless there's a count at the bottom.
- The Gunpowder Tin is now called **Powder Tin**, so it fits a 1×1 tile.

## 0.14.9 (Items: crafting materials to sell; owner asked)
- Four more valuables, meant as crafting materials later: **Bolts** ($120; junkyard, garage, shed, railyard, barn),
  **Wires** ($180; junkyard, offices, garage, shed, the electronics house), **Gunpowder Tin** ($1000; gun store,
  bunker, police, lockers) and **Processor** (CPU, $5000; electronics house, offices).

## 0.14.8 (Items: more to sell; owner's picks)
- Seven new valuables, picked with crafting in mind for later: **Fuel Can** ($900; gas stations, the garage,
  depot, barn, junkyard), **Medical Supplies** ($800; the pharmacy, bunker), **Novarra Badge** ($2000; police,
  checkpoint, town hall), **Hard Drive** ($3500; offices, town hall, the electronics house), **Exion Medal** ($7000;
  Bon always carries one, and the bunker), **Graphics Card** ($10000; electronics house, offices, bunker) and
  **Diamond Ring** ($15000; the bank, the jewellery house). Like every valuable, they can also turn up anywhere a
  container rolls a random valuable of their rarity.
- The item list tool reads the AI's loot settings from their new place after the 0.14.6 script split.

## 0.14.7 (inventory layout; owner asked)
- The equipment slots are rearranged: primary on top, secondary under it (next to the backpack), then armor and
  helmet together. Bodies you loot show their gear the same way.

## 0.14.6 (code cleanup: AI and player scripts split up; owner asked after the health check)
- No change in how anything plays. The AI script (about 2,400 lines) is now five smaller files: settings, senses,
  movement, fight, and the per-frame brain. The player script is now three: settings, movement, and the rest.
- Checked: every number the smoke test measures (62 sections) comes out exactly the same as before the split, the
  real-map AI check passes, and the AI cost per frame is unchanged.

## 0.14.5 (Items: grenades, energy drink, dog tags, intel documents; owner's picks)
- **Frag grenades.** Key 4 throws one (it goes on key 4 by itself when you pick it up); it bounces off the world and goes off 3 s
  later: 120 damage within 1.5 m, falling to nothing at 7 m, through armor. Walls and floors between you and the
  blast stop it. It hurts everyone, you and other players included. Online the server's copy does the damage.
  AI hear the blast from 60 m, but they don't throw grenades. Found in lockers, on Raiders and in the bunker;
  the trader sells them ($600). No touch button for it yet (comes with the next touch-controls pass).
- **Energy drink.** 1.5 s to drink: fills your stamina, then for 30 s sprinting costs half and stamina comes back
  twice as fast. Found in crates, lockers and on scavs; the trader sells it ($250).
- **Dog tags** to sell: Raiders drop a Raider Dog Tag ($900), Bon drops Bon's Dog Tag ($9000), and online a dead
  player's body has a PMC Dog Tag ($2500).
- **Intel documents** to sell: Novarra Field Report ($3000; town hall, offices, lockers) and Exion Orders ($8500;
  mostly the bunker).

## 0.14.4 (performance: AI level of detail, Jolt physics; owner asked after the health check)
- **Far, calm AI cost much less.** An AI that's patrolling and farther from every player than it can see now thinks
  and moves 10 times a second instead of 60, and glides smoothly between steps, so it looks and moves the same. Any
  noise, shot, call for help or player coming near puts it straight back to full speed. Nothing about how the AI
  plays changed (the sideways check on the real map still passes).
- **Jolt physics** (Godot's faster physics engine) replaces the old one. With every AI at full speed (big fights)
  it cut the AI's cost by about 20%; the rest of the physics got slightly slower (+0.1 ms), so it's a win in fights
  and even otherwise.
- Measured on Bloxov Frontlines with 32 AI and the player at a spawn (`tests/perf_check.gd`, whole physics frame):
  **about 4.3 ms before, about 2.2 ms now**; in a fight, where every AI runs at full speed, 4.3 → 3.6 ms.
  Phones and browsers are 2-3x slower than this desktop, so it matters most there. The game server gains the same
  per raid.

## 0.14.3 (no durability for now; owner)
- Durability is out until its own update (owner): armor, helmets and keys don't wear, keys open their door every
  time and are kept, and nothing loses value. Armor and helmets protect at full strength always, on you and on the
  AI (Raiders x0.8 body / x0.75 head, Bon x0.6 / x0.55). The code for it stays, switched off.

## 0.14.2 (helmets, AI wear their gear; owner)
- **Helmets**, in a new Helmet slot next to the backpack: the **Old Helmet** (uncommon, -25% on hits to the head,
  40 durability, $1,000) and the **Combat Helmet** (rare, -45%, 80 durability, $3,000). They wear down from hits like
  armor. Body armor now covers the body only; the helmet covers the head. The trader sells the Old Helmet; both turn
  up in lockers, safes, the police station, the school (old) and the bunker (combat).
- AI land some of their hits on your head (15%): same damage as before, but those go to your helmet, not your armor.
- **AI wear real gear** (owner): Raiders wear light armor and an Old Helmet, Bon heavy armor and a Combat Helmet. It
  protects them exactly like it protects you (body and head separately), wears down from your hits, and is on their
  body when they die, as worn as you left it. (Before, Raiders took a flat x0.8 and Bon x0.75 everywhere; Raiders are
  about the same now, Bon is tougher until his gear wears down.) Raiders no longer roll extra armor in their loot.

## 0.14.1 (AI climb through windows; owner: "if it fits in seamlessly")
- The AI climb through ground-floor windows the same way they vault fences: only when it's clearly shorter than the
  door (it costs them about 3 m of walking), ducking through the gap, no shooting while they do. Only windows with
  room to land on both sides count (not one with a crate right inside).
- (A Movement follow-up, first pushed as "v0.13.11" without a version bump.) Checked against the AI's fight movement on the real map (the sideways check, several runs): no change.

## 0.14.0 (Spoils of War, the Items update: keys, loot by place, descriptions, armor wear; owner)
- **Keys.** The bunker under the town hall and the bank vault are locked now. Hold F at the door with its key
  anywhere on you (pockets, backpack or secure pocket) to unlock it; it opens for everyone in the raid until the
  raid ends. Each opening takes a use off the key (Bunker Key 3 uses, Bank Vault Key 5) and a used-up key is gone.
  Bon always carries the Bunker Key; both keys turn up now and then in the police station, the town hall (bunker
  key) and the offices (vault key), and Raiders sometimes carry the vault key. Keys go home in your stash like
  any item. The AI stay out of locked rooms.
- **Loot by place** (the map plan's table): gun store lockers are mostly guns and ammo, the pharmacy meds, the
  grocery and diner food, the school backpacks, the police station armor and pistols, the bank cash and gold, and
  each big house its own kind of valuables (jewellery, electronics, antiques). The bunker has the best loot in the
  game. Other places roll the usual mid loot. New items: Water Bottle, Ration Pack, Cash Bundle, Gold Bar.
- **Item descriptions**: pointing at an item in the inventory shows a line about it under its stats.
- **Armor wears** (owner): every hit takes armor points off (the damage it stopped when new; falls don't count),
  and worn armor stops less (Light 60 points, Heavy 120: about 20 scav hits to wear one out). Durability shows as a
  bar on the item, in its details and on the armor slot; worn armor is worth less (30% when worn out). Armor found
  in a raid is 40-100% worn; armor bought from the trader is new. Repairs come with the Economy update.
- Fix: the AI's paths could go through a wall next to a low box against it (a safe, a bench), from one side of the
  wall to the other. They no longer do (it let them into the bank vault).

## 0.13.10 (vault through windows; owner)
- Space while walking into a window vaults you through it, in or out (on upper floors that means a drop, with fall
  damage past 3.5 m). You duck through the gap (the camera too) and slide a little sideways to fit it if you're not
  dead centre.
- Fix: since 0.13.2 the AI's navigation also linked across window sills, as if they were low cover; they couldn't
  get through and would get stuck at the window. Sills are no longer linked (the AI don't use windows).

## 0.13.9 (Escape closes the inventory, AI out of the floor; owner)
- Escape closes the inventory and you're back to playing, not in the pause menu. In the browser the mouse can't be
  grabbed back on Escape (browsers only allow it on a click or another key), so a "Click to keep playing" hint
  shows until you click; Escape again, or Escape while playing, opens the pause menu as before.
- AI in the floor (owner: a friend saw one, no screenshot): every AI spawn spot on the map checks out (on a floor,
  head room). As a safety net, an AI that ends up under the ground is put back on top, like players already are.

## 0.13.8 (leaning hitboxes online; owner)
- Online, a leaning player's body hitbox now tips with their model (before, only the head moved over and the body
  box stayed upright), so a shoulder showing round a corner can be hit, the same in what you shoot at and the
  server's hit check.

## 0.13.7 (lean while prone; owner)
- Q/E lean works while prone too: your head shifts sideways to peek past cover (online, your head hitbox moves with it).

## 0.13.6 (prone; owner)
- **Prone: Z.** Lie flat: a slow crawl (1 m/s), as quiet as crouching, eyes 0.4 m off the ground, and the steadiest
  aim (spread x0.75 and recoil x0.7 on top of the crouch bonus). Z, Space or Shift gets you up (C to a crouch);
  not under anything too low. No leaning or vaulting while prone.
- Online the others see you lying down with your gun ahead, and their hits use the lying-down hitboxes (the same
  as a downed player's). The controls line on the raid screen lists Z.

## 0.13.5 (ladders, crouch speed; owner)
- **Ladders.** Walk into one facing it to climb on; W up, S down, Space lets go (you push off it). Climbing past the
  top steps you onto the floor there; stepping off the top over a ladder (or dropping past one) catches you, so you
  can climb down without a fall. No gun while climbing. Ready for the sniper towers: `scenes/ladder.tscn` (set its
  `height`; it leans on whatever is behind it). None on the map yet, and the AI don't use them.
- Crouch-walking is a little quicker: 2.2 m/s (was 1.8). Still nearly silent.

## 0.13.4 (fall damage fix)
- 0.13.3's fall damage also counted being moved (spawning, being set back on the ground): a fast fall before the
  move could hurt or kill you on arrival. Moves now reset the fall.

## 0.13.3 (fall damage; owner)
- Drops up to 3.5 m are free (jumps, vaults, a one-storey roof). Past that, 12 damage per extra meter: a two-storey
  roof (5.5 m) costs about 24, 9 m about 66, 12 m kills. Armor doesn't stop it. A hard landing dips the view more,
  and the damage arrow doesn't show (there's no direction).

## 0.13.2 (AI vaulting; owner)
- The AI vault too: fences, sandbags and low walls (the same heights as yours) when going over is shorter than
  walking round, whether chasing you, moving to cover or patrolling. Over only: they never climb onto ledges or roofs.
- They can't shoot mid-vault. The navigation map links across every low, thin piece of cover (a link every 3 m;
  going over costs about 3 m of walking, so a short way round still wins).
- Vaulting moved into one shared `Vault` script used by players and the AI.

## 0.13.1 (far-range scav accuracy; owner)
- Scavs hit more often at range: 30% at 28 m (was 20%), sliding to 18% at the edge of their range (was 10%).
  Close range is unchanged. Raiders, Bon, guards and snipers are unchanged.

## 0.13.0 (Over the Top, the Movement update: vaulting; owner)
- **Vaulting.** Press Space while walking into cover: waist-high cover you can see over (sandbags, fences, low
  walls, up to 1.25 m) is vaulted, over and down the other side, keeping your speed. Ledges and wide tops up to chest
  high (1.7 m) are climbed onto. Anything lower than 0.5 m or taller than 1.7 m is a normal jump.
- Costs the same stamina as a jump and makes a little noise. The gun is lowered while you vault (no shooting,
  healing or looting) and comes back up like after a sprint. Needs room: no vaulting into a low roof (you climb on
  crouched if only that fits), a wall, another player or an AI.
- Online it's ordinary movement, so the others see you go over. The AI don't vault yet.

## 0.12.39 (Bon's Guard; owner)
- Bon's guards are named "Bon's Guard" (their body bags), not "Raider Body".

## 0.12.38 (scavs spawning in roofs, the real cause; owner)
- Scavs spawning with their heads in the ceiling (owner, screenshots from the first 20 s of a raid): the indoor AI
  spawn spots (0.12.23) and Bon's start spots (0.12.18) were 1.2 m above the floor, meant as "dropped from just
  above it", but a 1.9 m AI's head then started inside the floor above (ceilings are 2.75 m up) and got pushed up
  through it. All 37 spots are now on the floor, and the spawner also sets every AI down on the floor under its
  spot. (0.12.35's fix was for a different, rarer case: two AI spawned in one spot.)
- Smoke test: every AI spawn spot on the real map is on a floor with head room.

## 0.12.37 (strafe to cover in the open; owner)
- Out in the open past chase range, after its first shots an AI now strafes to cover still shooting at you (owner:
  "they shoot a few times then run to cover, which is unrealistic"). Every other cover run is unchanged: facing
  where it's going, not shooting.
- Smoke test: out in the open it strafes to cover still shooting.

## 0.12.36 (shoot first, chase all the way in, Bon's trips; owner)
- Shooting comes first (owner: in the open they still ran first). A healthy AI that sees you stands and shoots
  for 2-3 s before it moves to cover; getting hit in that first second doesn't send it running.
- Chasing (owner: "chase all the way into you", "just be walking and shooting"): within 30 m it walks straight at
  you shooting, all the way up to you (rifle-butt range), and getting hit doesn't stop it. The 0.12.34
  dash-and-stop is gone. 1 time in 10 it takes cover instead. Badly hurt (about 30%, Raiders and Bon 40%) it doesn't
  chase and fights from cover, as before.
- Running to cover is done with intent: facing where it's going, not shooting on the way.
- Vision (owner: indoors it lost you the moment you broke line of sight): within 35 m it still knows where you are
  for 5 s after losing sight, heads there, and sees you again the moment you're in view (through a window, round a
  corner). Suppressing fire still goes where it last saw you.
- Bon and his guards (owner): some patrol stops are just outside the town hall, and once or twice a raid Bon takes
  the guards to another building in town (the bank half the time), then back. A fight while they're out doesn't
  send them straight home. Bon waits for a guard that falls far behind.
- AI that get caught on an edge (a ramp's side, a corner) step to the side before trying again. Bon's guards used
  to get stuck for good on the way out of the hall.
- Smoke test: chases all the way in, shoots first in the open, keeps track of you for a few seconds, Bon's trips.

## 0.12.35 (AI stuck in ceilings, teammate footsteps; owner)
- AI stuck in a ceiling (owner's screenshot): an AI could spawn right inside another (a crowded spawn spot, a
  Raider's partner, Bon's guards: the free-spot check only looked for walls) and get pushed up onto its head, with
  its own head jammed in the ceiling. Spawn spots now keep clear of other AI and players too, and an AI standing on
  anyone's head drops through them to the floor and steps aside.
- Teammates' footsteps (owner): online you now hear other players walk (about 25 m), sprint (35 m) and, barely,
  crouch-walk (6 m).
- Nobody can get stuck under the hills: big online raids (more than 8 squads) could start squadmates on a slope
  below the ground, which is solid from underneath. Spawns are lifted onto the ground, and a player who ends up
  under it is put back on top (not in the bunker, which has its own ceiling).
- Smoke test: spawn spots avoid other AI, an AI on another's head steps off (even wedged under a ceiling), other
  players' footsteps play, no squad spawn is underground, and someone under the ground is put back on top.

## 0.12.34 (smarter chasing; owner)
- Chasing is no longer a straight walk at you (owner: "strategically"). In range an AI dashes about 5-11 m at a
  time to the next spot closer to you, picking one out of your sight when there is one and curving round to one
  side, then stops and shoots for about 1-1.5 s before the next dash. It shoots on the move only when you're
  ahead of it. AI fighting you together take turns: one dashes while the others shoot from where they are.
- Smoke test: a chaser dashes and stops to shoot, and two chasers never dash at the same time.

## 0.12.33 (AI chase you in range; owner)
- AI now push you when they're close enough to really hit you (owner: "they never push when in range to actually
  shoot"; cover is for when they see you but you're too far). Within 30 m an AI mostly walks straight at you
  shooting, stops about 7 m away, and comes after you again if you back off. About 1 in 4 times (and sometimes after
  getting hit) it takes cover instead, and from cover in that range it peeks once, then comes out after you.
  Where its path bends round something it faces where it's going and holds fire, so no sideways walking.
  Farther than 30 m nothing changes: cover to cover. Badly hurt AI, snipers and AI pushing while you reload are as before.
- Smoke test: in range a scav chases you while shooting.

## 0.12.32 (fight on, heal when it's quiet; quieter AI footsteps; owner)
- No more retreating at low health (owner: "reposition and fight", heal once they lose you). Below 30% (Raiders and
  Bon 40%) an AI plays safer: no pushing, flanking or chasing you, cover whenever it can (and it stays down a bit
  longer), but it keeps fighting. It patches up only once the fight goes quiet: about 5 s without seeing anyone and
  without being shot at. Shooting it while it heals stops the heal.
- AI footsteps carry 30 m (owner + friend: you could hear every AI on the map walking, "like 30 crunching steps").
  Callouts carry 50 m, the heal sound 20 m, the rifle-butt bash 30 m. Gunshots still carry across the map.
- Smoke test: badly hurt it repositions and keeps fighting, and patches up once it's quiet.

## 0.12.31 (up-close fight priorities, town patrols, stuck spawns, hit arrow; owner)
- Up-close priorities (owner: "the scavs priorities are not right at all"): badly hurt with you close by and in
  sight, an AI only falls back to cover a few steps away (6 m); with none that close it keeps shooting back and tries
  again shortly, instead of turning its back to run 20 m or patching up in the open in front of you. Shot up close
  while running to far cover, it turns and fights. Badly hurt up close, it only ducks into cover a step away.
- In co-op an AI turns on whoever is shooting it (it used to keep fighting the closest player).
- Town scavs no longer spawn or patrol around the town hall and bank (Bon's guards are there): they start and
  patrol out toward the edges of town (owner).
- Spawns: a Raider's partner (and Bon's guards) used a fixed offset from the leader, which could put it on a shelf
  under the ceiling or inside a wall (owner saw a Raider stuck in a roof). They now go to a clear spot beside the
  leader: same floor, headroom, nothing in the way.
- The hit-direction arrow keeps pointing at whoever shot you while you turn (owner: it felt off turning fast; it
  kept the angle from the moment of the hit).
- Smoke test: hurt up close with no cover near, it fights back; town patrols keep out of the avoid areas; a blocked
  partner spawn moves to a clear spot.

## 0.12.30 (AI hearing, retreat, shoot back first, faster reactions; owner)
- AI hear you better (owner: walking right past them, they never looked). Footsteps carry farther: walking 12 m
  (was 7), sprinting 25 m (was 15); crouch-walking is nearly silent (2 m, was silent). On hearing a step an AI stops,
  snaps round to look where it came from, then walks over: walking up behind one, it spots you in about 0.4 s.
- Retreat when badly hurt (owner: "like 30%"): scavs at 30%, Raiders and Bon at 40%, drop what they're doing and run
  back to cover farther from you (up to 20 m), patch up there if they have a heal, else lie low a while. Before,
  only an AI with a heal left fell back, to the nearest cover.
- Up close (within 12 m) an AI's first instinct is to shoot back: it only ducks into cover a step or two away
  (owner: one ran round inside a building looking for cover while he shot it).
- Faster reactions (owner): spotted -> first shot 0.35 s for scavs (was 0.65), 0.27 s for Raiders (was 0.55),
  0.22 s for Bon (was 0.45). Snipers unchanged.
- Peeking out of cover from a few meters away, it walks out facing ahead and only turns to you for the last step.
- Smoke test: retreating with no heals, shooting back up close, hearing footsteps from behind.

## 0.12.29 (AI fight brain, step 1; owner)
- AI fights are rebuilt around one decision layer, like shipped shooters (owner: the AI felt "cluttered and messy").
  Each AI picks ONE plan and sticks to it until it's done or something real changes (shot in the open, lost sight
  of you, you start reloading, out of range): take cover and peek, trade shots in the open (only when there's no cover
  near), push you while you reload or heal, flank, move up from far away, pin you down, chase where it last saw you,
  or fall back and heal. Before, every behavior grabbed control on its own each frame, so plans flip-flopped.
  All AI keep every move (owner); scavs vs Raiders still differ only by their numbers.
- Flanks are short and purposeful: a spot 50-90 degrees round you, 10-20 m from you, out of your sight, at most a 30 m
  walk that doesn't pass right by you (some were 50-60 m loops round you). A flanker that runs into you up close fights.
- Friends pick their own cover spots (2 m apart) and keep a step apart in fights instead of bunching up.
- In the open it stands and shoots; its only sideways move is a quick dodge right after getting hit. Rushing in from
  far away goes straight in instead of weaving.
- Same aggression as before: in real-map group fights the AI fired about as much as 0.12.28 (45 vs 41 shots per AI
  per minute), the longest sideways run stays under 1.3 s.
- Smoke test: sticking to a plan, separate cover spots; a point-blank check no longer depends on the dice.

## 0.12.28 (AI stop running sideways; Raider, Bon and sniper accuracy; owner)
- AI stop running sideways in fights (owner: "the AI was just moving sideways again"). On the real map the longest
  sideways run went from 6.5 s to 1.3 s, and the worst AI went from 62% of a fight spent sideways to 24%. It had three causes:
  - Flanks were a sideways run across your view while shooting. Now a flank goes to a spot off to your side that you
    can't see, facing where it's going; with no such spot it takes cover instead, and if it's shot on the way it fights back.
  - Running to cover while facing (and shooting at) you. Now it faces where it's going and only shoots on the way if
    you're roughly ahead of it.
  - Strafing in the open in 0.8-2 s runs. Now it takes short side-steps (0.3-0.6 s) between longer stops to shoot.
  Peeking out of cover still steps sideways around the corner (that's the peek).
- New real-map check `tests/ai_sideways_check.gd` (slow, run by hand) plus smoke checks for flanks and strafing.
- Raiders, Bon and snipers more accurate (owner: "everyone just misses too much"; scavs unchanged). Hit chance up
  close / 28 m / edge of range: Raiders 85/50/30% (was 80/32/16%), Bon 90/60/35% (was 85/40/20%), snipers
  85/50/50% (was 75/35/35%, out to 100 m).

## 0.12.27 (better AI callouts; owner)
- AI callouts stay cartoony gibberish (owner: no real voice lines) but sound better: consonants (b, d, g, m...)
  between bouncier vowels, a snappier, slightly lo-fi sound to match the game's other effects, and each kind has
  its own shape (spotted: sharp and rising; hurt: a yelp; help: a long call; heal: a low mumble).
- 3 takes per callout so the same line doesn't repeat. Raiders and Bon still say them deeper.
- Demo of all 27: `/mnt/project-files/scavs2/0.12.27-callouts-demo.wav`.

## 0.12.26 (Raider and Bon close-range accuracy; owner)
- Raiders and Bon hit 80% and 85% up close again (owner), as before 0.12.25. Their 28 m and long-range hit chances
  stay at 0.12.25's lower numbers (Raiders 32/16%, Bon 40/20%).

## 0.12.25 (Raider and Bon accuracy; owner)
- Raiders and Bon a bit less accurate (owner: with 0.12.21's shorter pauses they hurt about 45% more; aim for about
  15%): every hit chance x0.79. Raiders 63% up close (was 80%), 32% at 28 m (was 40%), 16% at the edge of their
  range (was 20%); Bon 67/40/20% (was 85/50/25%). Scavs and snipers unchanged.

## 0.12.24 (fewer indoor spawns, more patrolling; owner)
- Half as many indoor AI spawn spots (owner: 6 in a building -> 3, 2 -> 1): 34 spots, was 65. Each building keeps
  at least one, spread through its rooms. A zone's AI still start inside about half the time.
- Patrols go to loot spots 45% of the time (was 80%; owner: they should patrol a lot, not go for loot).

## 0.12.23 (AI inside buildings; owner)
- AI spawn inside buildings too (owner: so you have to clear buildings, and can get ambushed): every zone now has
  spawn spots in the middle of its buildings' ground-floor rooms (not the grocery, full of shelves), and about
  half of a zone's AI start in one. In a test raid 15 of 31 AI started indoors (was 6, Bon and his guards).
- Patrols go through buildings more: AI head for loot spots (inside buildings) 80% of the time (was 65%).
  AI were indoors 48% of the time on patrol (was 34%).
- Town scavs 7 -> 6 (owner). 32 AI at the start.
- Spawn map: `/mnt/project-files/scavs2/0.12.23-ai-spawns.png`.

## 0.12.22 (Raiders spread out; scav accuracy; owner)
- Raiders spread out instead of crowding round Bon: the town square is scav ground now; Raiders hold the police
  station and the bank (2), the gun store and pharmacy (2) and the south-east (2, was 3).
- One more scav in the woods (3) and a new one at the two road houses between the church and the farm.
  33 AI at the start; the cap on AI alive at once goes 34 -> 36 so later arrivals still come.
- Scavs a bit less accurate (owner: with 0.12.21's shorter pauses they hurt about 50% more; aim for about 20%):
  hit chance 60% up close (was 70%) down to 20% at 28 m (was 25%), still bottoming out at 10%. Raiders, Bon and
  snipers unchanged.
- Spawn map: `/mnt/project-files/scavs2/0.12.22-ai-spawns.png`.

## 0.12.21 (shorter pauses between AI bursts; owner)
- AI pause less between bursts: scavs 0.75-1 s (was 1-1.8), Raiders 0.5-1 s (was 0.8-1.5), Bon 0.5-0.75 s
  (was 0.8-1.4). Snipers unchanged.

## 0.12.20 (Bon's patrol fixed; AI spawn check; owner)
- Bon and his guards stood still (owner, on 0.12.17): his guards crowded round him and boxed him into a corner, so
  none of them could move. Bon and his guards now walk through each other (a Raider and its partner too), and a
  guard that gets stuck on the way to its spot just follows Bon's steps for a bit. In a 90 s test Bon stood still
  10 s (his normal stops) instead of 75 s.
- Checked every AI spawn spot on the map (on walkable ground, clear of walls and props, can walk to town): two
  were overlapping something (one under the raised road by the junkyard, one under a hunting stand's ladder) and
  moved a few meters. Map: `/mnt/project-files/scavs2/0.12.20-ai-spawns.png`.

## 0.12.19 (no station firefight; owner)
- Removed 0.12.17's contested spot: scavs and Raiders no longer trade fire at the train station. The station and
  depot are scav ground again (2 scavs); its 2 Raiders moved to the town core and the south-east (3 each).
  Scavs and Raiders still keep to their own areas and never back each other up.

## 0.12.18 (Bon starts inside the town hall; owner)
- Bon and his 3 guards start each raid inside the town hall (in one of four ground-floor rooms, picked at random),
  then head out on their usual patrol of the hall, the bunker and the area round it.

## 0.12.17 (Scav and Raider rivals; owner)
- Scavs and Raiders are rivals. Each side has its own areas: Raiders hold the town core, the town hall (Bon) and the
  south-east (junkyard, old gas station, diner, garage); scavs hold the rest of town, the farm, the church, the
  woods and the old houses. Same number of AI as before.
- The train station and depot are contested: 2 scavs and 2 Raiders trade fire there all raid. Their shots at each
  other always miss, so the spot stays held; they drop it to fight you when they spot you, and go back to it after.
- Elsewhere they ignore each other, and they never back up the other side (calls for help, "man down" warnings,
  suppress-and-flank).
- Removed 0.12.16's gear pickup (owner didn't like it): AI no longer take gear off bodies.

## 0.12.16 (AI pick up gear off bodies; owner)
- Unaware AI head for a body or dropped bag within 25 m (in their area) that has gear better than theirs, yours
  included, search it, and take it: a rifle (hits 5 harder, bursts 1 longer) and/or armor (light: 20% less damage,
  heavy: 40%). They drop what they took when killed. Everything else stays in the bag. They won't take anything
  while a player is within 6 m of the bag. Online, a bag they empty disappears for everyone.
- Not visible on their model yet (the models' guns are built in; see BACKLOG "guns as separate models").

## 0.12.15 (suppress and push; owner)
- When you duck out of sight mid-fight and two or more AI are on you, one keeps firing at where you disappeared for
  5 s (pinning you in cover; it hits you only if you peek into it) and calls the push, while the nearest other one
  goes around to flank you. Raiders always do it; scavs half the time. Only one suppresses at a time.

## 0.12.14 (smarter search; owner)
- Lost you in a fight: AI hunt for you for 30 s (owner) around where they last saw you instead of turning on the
  spot: they walk to spots within 18 m, indoor ones first (you'd hide inside), look around at each, and several
  searchers split up (each checks a different spot). Afterwards they patrol again but stay wary for 30 s (quicker
  to spot you). Bon and his guards only search inside their own area.

## 0.12.13 (wounded AI; owner)
- Badly hurt AI (below 35% health) limp: 70% speed, and the body dips with every other step (shown online too).
- The moment they get that low they shout for help (nearby AI come over, still at most 4 at a time) and fall back
  to cover; wounded AI no longer push you or flank. Healing back up ends it.

## 0.12.12 (callouts, Bon guards his area, shooting range -5 m; owner)
- Callouts (owner): AI call out what they're doing: spotted you, calling for help, lost you, taking cover,
  flanking, pushing while you reload/heal, hurt, man down, healing. At most one per AI every 4 s; Raiders sound
  deeper, Bon deepest. Placeholder gibberish barks for now (`tools/gen_voice_placeholders.py`); the owner will
  record real lines (`audio/voice/<kind>.wav`, extra takes as `<kind>_2.wav`...). Heard online too.
- Bon and his guards stick to the town hall (owner: "he should just patrol an area"): they ignore gunshots and calls
  from outside their area, spot you out to 60 m (was 85), and give up a chase 40 m past the edge of their area,
  going back to patrol (not re-spotting you for 6 s unless shot). Bon's hearing is a scav's (was 1.5x).
- Shooting range 5 m shorter (owner): scavs 70 m, Raiders 75, Bon 80.

## 0.12.11 (fewer AI pile into one fight; owner)
- Owner: a friend who spawned near town had to fight 8-9 scavs and Raiders at once; they grouped up a lot.
- At most 4 AI per raid head over to a fight they heard or were called to at a time. The rest go on alert where
  they are: they look toward the trouble, spot you faster, then go back to patrolling.
- Gunshots don't carry as far (owner: "kinda insane, not everyone should show up"): scavs hear an AK 35 m away
  (was 50) and the pistol 25 m (was 35). Raiders and Bon hear 1.5x as far (was 2x and 2.5x): an AK about 52 m
  (was 100 / 125 m). A bullet passing close or a friend dropping next to them still alerts AI farther away.

## 0.12.10 (AI actually hide: cover right away, behind trees/tents, crouching; owner)
- Owner: cover didn't seem to work; a scav looting at the camp didn't hide behind the tents, trees or a hill, it just
  kept running sideways.
- In a fight in the open, AI head for cover as soon as they can (shooting on the way) instead of strafing until
  their burst ends. They look for cover every 2.5 s (was 5; Raiders and Bon 2, was 3.5) and peek out up to 5 times
  (was 3) before re-thinking.
- Cover search first looks at the far side of whatever is right around it (tree trunks, tents, cars, wall corners,
  hillsides), which the old ring of sample points often missed.
- Low cover (tents, low walls, cars): it crouches behind it while hiding (model and hitboxes shrink, also online),
  then stands up to shoot. It prefers cover it can stand behind when there's a choice.
- In a test on the real map (8 fights at 25 m) every AI fought from cover, and spent 0-3 s in your view out of cover
  (before: 3 of 8 never took cover, and some strafed or flanked in the open for 3-6 s).

## 0.12.9 (AI hit more often at range; owner)
- Owner: the 0.12.8 accuracy was far too low, especially for Bon and Raiders; scavs should bottom out at about 10%.
- Hit chance per bullet (up close / at 28 m / at the edge of their range): scavs 70% / 25% / 10% at 75 m,
  Raiders 80% / 40% / 20% at 80 m, Bon 85% / 50% / 25% at 85 m.

## 0.12.8 (AI shoot back from far, accuracy falls off with range, no more wall hugging; owner)
- Owner: far-off scavs just looked at him, then went for cover, so they were easy to kill; their reaction should be a
  lot faster, and far shots should be even less accurate, getting better as they close in. One scav hugged a building
  for 20 seconds.
- Shooting range: scavs 75 m (was 40), Raiders 80 (was 45), Bon 85 (was 50). In range they shoot first and take cover
  after their first burst; only when you're out of range do they go for cover straight away.
- Accuracy is a gradient: a scav's hit chance per bullet is 70% up close, 20% at 28 m, and drops to 5% at 75 m
  (Raiders 8%, Bon 12% at the edge of their range).
- An AI pressing into a wall (or sliding along it) for 1.5 s gives up on that spot and picks another.

## 0.12.7 (AI notice you on hills, patrol near cover, move up cover to cover; owner)
- Owner: from a hill he shot lots of scavs that never noticed him, and scavs shot at from far away went into cover,
  then just walked at him in the open.
- Scavs see 75 m (was 50; Raiders 80, Bon 85). Spotting at 50 m stays about as quick as 0.12.6.
- Gunshots carry farther: an AK is heard 50 m away (was 25), the pistol 35 m (was 18). AI that hear a shot jog over.
- A scav shot dead alerts friends within 12 m, or within 35 m that see it go down: they turn toward roughly where the
  shots came from.
- Patrol stops out in the open are now next to a wall or other cover when there is one nearby.
- Too far away to shoot back: AI move up cover to cover toward you (a spot at least 5 m closer that you can't see),
  holding a moment at each. With no cover ahead they wait out of sight; only with no cover at all do they rush in,
  weaving. They no longer peek out from cover when you're out of their range.

## 0.12.6 (AI fight from cover, varied bursts, quicker spotting; owner)
- **Fighting from cover** (owner, from a playtest: the first scav ran sideways at him with cover right next to
  it). Scavs, Raiders and Bon now get into cover and fight from there:
  - In a fight out in the open, between bursts (or as soon as they're hit), they go to a nearby spot you can't
    see, up to 12 m away (was 7). Scavs do this every 5 s at most, Raiders and Bon every 3.5 s
  - From cover they **peek out** to where they could see you, shoot for 1.5-3 s, duck back in, and do it again
    (up to 3 peeks). Getting hit while peeking sends them back in after the burst
  - If you've moved when they peek, they come looking for you. While you reload or heal they still push in
  - With no cover nearby (open fields) they fight in the open as before
- **Bursts vary** (owner: "not always 3"): each burst is a random length. Up close they're longer (3-5 rounds for
  scavs, 4-6 for Raiders, 5-7 for Bon); in the middle 2-4 for scavs; far away scavs tap 1-2 rounds
  (Raiders 1-3)
- **They spot you faster** (owner: scavs should be pretty aware and spot you fairly easily):
  - Time to notice you: 0.15 s up close (was 0.25) to 0.7 s at the edge of their sight (was 1.2)
  - Standing still no longer hides you any better; crouching helps a bit less (1.4x, was 1.6x)
  - Reaction after spotting: 0.3 s (was 0.4)
  - Snipers keep their slower spotting at long range

## 0.12.5 (farm house floor stops flickering; owner)
- Fix: the farm house, barn and shed floors still flickered (owner). They stand on the farmyard's dirt, and since
  0.11.21 both sat at exactly the same height. Now a floor or patch on top of a bigger one sits 5 cm higher (10 cm
  on a road), so no two are ever level. Checked every building, yard and road on the map: none overlap level now
- Same fix where the Old Road crosses the railway: the road goes over the rails instead of level with them, with
  no sleepers under it, and the sleepers stand 5 cm above the rail bed (was 2 cm)

## 0.12.4 (the boss is Bon; owner)
- The town hall boss is called **Bon** (owner). Its body is labelled "Bon"
- Bon always carries **heavy armor** (owner), on top of its AK and 4-6 items. It goes straight into the body's
  Armor slot

## 0.12.3 (smarter fights; owner)
- **AI fight smarter** (owner: every AI was "too dumb"; a friend's playtest: AI standing around). This covers scavs,
  Raiders and the boss:
  - **They call for help:** an AI that starts a fight brings over every unaware AI within 35 m (mostly its
    zone-mates). They jog over toward the fight, not straight to you. The ones that answer don't call again, so
    one fight doesn't pull in the whole map
  - **Cover at range:** spotting you from more than 20 m away, an AI heads for cover first (shooting on the way if
    it can) instead of trading shots in the open
  - **They push you:** while you reload or heal, an AI in a fight walks in on you, still shooting, instead of
    strafing in place, and one holding cover comes out straight away. Hiding was already pushed: they go to where
    they last saw you. (Online, reloading isn't sent to the server yet, so there it's healing only)
  - **Scavs flank too:** in a break in the fight a scav sometimes circles round to your side (30% of the time;
    Raiders 50%)
  - **They keep moving:** shorter stops on patrol (1-3 s, was 2-6 s) and shorter container searches (2-4 s, was
    3-6 s)
- Snipers stay on their perches (they don't answer calls)

## 0.12.2 (the town hall boss; owner)
- **A boss guards the town hall** (owner: high-tier loot guarded by a better-equipped boss and guards). A Raider
  **commander** and 3 Raider guards patrol the town hall and its bunker together. They're in every raid while
  we test (owner); later it'll be a chance per raid. The name comes later (owner)
- The commander: 250 health with built-in armor (takes 75% damage), so it lasts about 3 Raiders' worth of shots.
  5-round bursts of 20 damage, sharper aim (85% close, 40% far), sees you from 60 m and hears fights from farther
  off. It patches itself up to 3 times and flanks sometimes. It's a little bigger than a Raider, so you can tell
  it apart
- The guards walk in formation round the commander (each in its own spot) and fight like Raiders. If the
  commander dies they keep guarding the town hall
- Its body ("Commander Body") always has its AK and 4-6 items from the Raider loot list
- With the boss and the snipers, a raid now starts with 31 AI (owner: about 30); up to 34 alive at once
- Works online (players' games show the server's boss)

## 0.12.1 (sniper scavs; owner)
- **Sniper scavs** (owner: a long-range threat up high that you can spot and shoot back). 2 per raid, each on a
  perch picked from 5 high spots: the police roof (over the town core), the bell tower, the school roof, the train
  station roof and the hunting stand by the creek trail. A perch that already has a player in its sights at the
  start is only used if nothing else is free
- A sniper stays on its perch (it can shift a few meters but never comes down to chase you, take cover or
  check a noise). It scans the area slowly while it hasn't seen you
- It sees you from up to 120 m and fires single heavy shots (35 damage, one every 3-4 s) out to 110 m. It's
  accurate up close and less so far out (75% to 35%), and running still makes you harder to hit. It takes a
  little longer to aim than a scav (1.2 s)
- **Scope glint** (owner): a bright yellow-white flash at its head when it's aiming at you. It gets bigger with
  distance, so it still shows up from far away. A faint flicker shows when its scan sweeps past you. Nothing shows
  when it looks the other way
- **Its own shot sound** (owner): deeper and louder than a scav's, and heard from much farther, so you know a
  sniper is shooting
- Same health as a scav; its body is a "Sniper Body". Works online (players' games show the server's snipers
  with the glint)

## 0.12.0 (Hot Zone, the Scavs 2.0 update: AI zones and hot zones; owner)
- **Scavs 2.0 starts** (owner, from playtests: "too easy but too many", AI roaming in weird places). AI now live
  in **zones** on Bloxov Frontlines and patrol only their own zone, so you learn where to expect them:
  - **Hot zones** have the most AI and most of the Raiders: the town core round the town hall, bank and square
    (hottest: 2 scavs and 3 Raiders), the rest of town (4 scavs, 1 Raider) and the bottom right round the depot,
    junkyard and old gas station (3 scavs, 2 Raiders). The train station is busy too (2 scavs)
  - **Quiet areas** get small patrols: the farm (2), the church (1), the woods by the creek (1), the old houses
    south of the railway (1)
  - **3 roamers** still cross the whole map
  - Zone AI walk between the loot spots in their zone (in and out of the buildings) and other spots in it, and
    head back into their zone after a fight pulls them out
- **Fewer AI:** 25 at the start (was 30), then 5 more scavs (one every 50-70 s) and 3 more Raiders (2:30, 5:00,
  7:00) arrive in the hot zones: about 33 over a raid (was up to 80). The town hall boss and guards, and
  sniper scavs, come in the next versions (about 30 at the start then, owner)
- No zone reaches a player spawn, so nobody starts a raid next to a patrol
- Fix: two AI could spawn on the same spot and stay stuck in each other for the whole raid (one reason for AI
  "standing around doing nothing" in a playtest). They now spawn on a free spot

## 0.11.21 (building floors stop flickering; owner)
- Fix: building floors flickered against the ground under them (owner: "a really bad visual glitch"). Since the hills
  (0.11.17), floors were only 3 cm above the ground, and in 5 buildings the ground poked up through the floor
  (a spawn's level spot next to them lifted it). Now floors, yards and car parks sit 7 cm up, nothing lifts the
  ground under a building, and the ground hidden under a floor isn't drawn at all
- The generator now checks that no ground pokes through any floor or yard

## 0.11.20 (real water in the creek; owner)
- **The creek is water now, not a blue path** (owner: "the water is not water at all its just a blue path"). It
  runs in a channel dug into the bottom of its valley, about half a metre deep in the middle, with a see-through
  water surface below the banks: you can see the bed through it, and the banks hide its edges
- **Wading slows you down** (owner's pick): in the water players and AI move at 60% speed, and you can't sprint.
  It doesn't hide you and bullets go through it
- The AI walks into and across the creek as before (its paths go through the channel)

## 0.11.19 (scavs shoot over hills, not into them; owner)
- Fix: a scav that could see you over a hill crest shot into the ground in front of it (owner). Its eyes saw
  your head, but its shots left from chest height and hit the hill. Now it shoots from its eyes at whatever part
  of you it can see, and holds fire when nothing has a clear line (since 0.11.17's hills)

## 0.11.18 (the map screen says TOWN, not OLD TOWN; owner)
- The map (M) labels the town area **TOWN** instead of "OLD TOWN", so nothing in the game says "Old" any more
  (owner: the map is Bloxov Battlegrounds, not Old Bloxov). The town's own name is still to come
- The 0.11 update is now called **Scorched Earth** (owner): the cleanup plus the map turning into a war zone
- Docs: every leftover "Old Bloxov" in the changelog, docs and comments now says Bloxov Battlegrounds (file names
  keep `old_bloxov`); the layout picture is redrawn

## 0.11.17 (hills and valleys; owner)
- **The ground isn't flat any more** (owner: "there should be hills and valleys"). Bloxov Frontlines now rolls,
  about 14 m from the lowest hollow to the highest hilltop:
  - Big hills in the open: the east woods sit on the tallest one (about 11 m), and there are hills either side of
    the creek, between the old houses, in the field south of the railway and east of Station Road
  - Hollows and dips: the creek runs down a real valley, there's a hollow by the hunting stand, and the shell
    craters are now holes dug into the ground (ring of dirt round the rim, as before)
  - The north end of town sits on a gentle rise, so the hill houses look down on Main Street
  - Hills block sight and bullets: a crest hides you from whoever is on the other side, scavs included
- Everything built stays usable: every building, yard, spawn, extract and loot spot sits on its own level ground,
  roads follow the hills without tilting sideways, the railway stays level all the way across, and the trench and
  bunker are where they were. Wrecks and rubble out on the hills get a small level spot
- Slopes are gentle enough to walk up anywhere (about 23 degrees, a few short banks up to 35 by
  buildings). Scavs and Raiders still path everywhere: every loot spot, spawn and AI spawn point is reachable
- The map screen (M) shades the hills, so you can plan routes round them
- The edge wall follows the hills. Same layout, buildings, loot and spawns as before (owner: layout unchanged)

## 0.11.16 (scavs fight back; owner)
- **Scavs and Raiders react faster** (owner, from a playtest: you could see a scav first and kill it before it
  did anything). Same accuracy and damage as before; they just notice you and get their shots off sooner:
  - Getting shot (or a bullet whizzing past) while unaware startles them: they turn and start shooting back in
    about half a second (scavs 0.15 s + 0.35 s aim, Raiders 0.1 s + 0.25 s). Before, it was over a second
  - Only the first hit of a flinch holds their fire. Before, every hit pushed their next shot back, so steady
    fire kept them from ever shooting back
  - Spotting you: quicker at range (far spot time 1.8 s to 1.2 s, standing still slows it less), then 0.4 s to
    react and 0.35 s to aim (were 0.6 s and 0.45 s; Raiders 0.3 s and 0.25 s, were 0.45 s and 0.35 s)
  - They see farther (scavs 40 m to 50 m, Raiders 45 m to 55 m) and shoot back from farther (28 m to 40 m and
    45 m), at their long-range accuracy instead of walking at you without firing

## 0.11.15 (Bloxov Battlegrounds; owner)
- The first map is now called **Bloxov Battlegrounds** (owner; it was "Old Bloxov"; renamed Bloxov Frontlines in 0.25.3). The map screen (M) shows the
  new name
- Lore (owner): the two nations are **Novarra** and **Exion**; their armies, which players fight as, are
  **NOVA** and **EXION**. Bloxov sits on the border between them (`docs/LORE.md`)

## 0.11.14 (loot no longer lost on reload)
- Fix: after extracting, reloading the page (e.g. for an update) could load the save from the start of that raid,
  as if you had died in it: the raid's loot and the kit you took in were gone. The browser's storage connection can
  drop mid-session and the game kept saving into it without noticing. The save now also goes to the browser's
  localStorage straight away, and loading takes whichever copy is newer

## 0.11.13 (loot a body's loadout; owner)
- **Bodies show their loadout** (owner): scav, Raider and dead-player bodies open with Primary, Secondary, Armor
  and Backpack slots, plus their Pockets for everything else. Loot the slots like your own: drag a body's gun onto
  your Primary (yours swaps into its slot), Shift+click a body's pistol straight into your empty Secondary, or put
  gear back. A Raider's dropped AK sits in its Primary slot. Each slot takes one item of its kind
- Works online: the server sends and checks the slots with the rest of the body (old crates and dropped-item bags
  are unchanged)

## 0.11.12 (F no longer reopens the loot screen it just closed)
- Fix: pressing F to close a body's or crate's loot screen sometimes reopened it right away (the same F press
  closed the screen and then counted as a new interact). F now has to be let go before it can open a container again

## 0.11.11 (Raiders can drop their AK; owner)
- **Raiders sometimes drop their AK** (owner): a 30% chance a Raider's body bag holds an AK Rifle on top of its
  usual loot (empty mag, like any found gun). Scavs don't drop guns this way. Works online too (the server rolls
  the body). Tunable per enemy: `weapon_drop` / `weapon_drop_chance` on the scene
- Body bags grow taller when their loot wouldn't fit (an AK next to a backpack used to lose the backpack)

## 0.11.10 (twice the enemies on Bloxov Frontlines; owner)
- **Twice the enemies** (owner: testers found it way too easy): 24 scavs at the start (was 12), up to 30 alive at
  once (15), 64 scavs over the raid (32) and up to 16 Raiders (8): 6 at the start, then one about every 45 s from
  1:00 to 8:00. Twice the AI spawn spots too (48, the new 24 on open ground away from the others and 45+ m from
  player spawns), so they don't stack. Still placeholders until Scavs 2.0
- Only Bloxov Frontlines' numbers changed (the test map keeps 3)

## 0.11.9 (dead grass patches removed; Map & Spawn follow-up, owner)
- **The dead grass patches are gone** (owner: the flat grey and green patches looked bad). Flat blocks can't sell
  dead grass; it waits for real ground textures/models. The trench, dead trees and junk stay

## 0.11.8 (dead trees, dead grass, a trench; Map & Spawn follow-up, owner)
- **Fewer trees in the open, most of them dead** (owner: tone it down, and war-torn trees): about half as many
  as 0.11.7, mostly lone trees; 6 in 10 spots are dead instead: burnt bare trunks with broken branches, snapped-off
  trunks or stumps. Only the living ones show on the M map
- **Dead grass**: brown and burnt patches round the junk, along the trench and dotted over the open ground (looks only;
  removed again in 0.11.9)
- **A trench line** (owner: terrain change, trench warfare): a zig-zag trench dug 1.1 m into the field south of the
  town hall, with a ramp in at each end and sandbags along parts of its north lip. Stand up to see over the bare
  edge, crouch to hide. Junk and trees stay 6 m clear of it
- `tools/gen_old_bloxov.py`: `TRENCHES`, `trench()`, `dead_tree()`, `dead_grass()`; new colours deadgrass, deadwood, earth

## 0.11.7 (trees in the open; Map & Spawn follow-up, owner)
- **More trees in the empty areas** (owner): about 55 lone trees and little clumps of 2-3 (some with a bush)
  scattered over the open grass, clear of the junk spots, roads, buildings, spawns and extracts. They show on the
  M map as small tree patches
- Junk and trees now also stay off flat ground patches (the farm field, car parks, the sports field), so a few
  junk spots moved
- `tools/gen_old_bloxov.py`: `scatter_trees()` (fixed seed)

## 0.11.6 (war-damaged buildings; Map & Spawn follow-up, owner)
- **Buildings are shot up** (owner: houses and the town should look war torn too, especially the bottom right):
  blown-out holes in outside walls (scorched round the edges, chunks of wall hanging into them, rubble blown out
  onto the ground with a solid heap each side for cover) and caved-in roofs (rubble on the floor below, a piece of
  roof hanging down). Bottom right: OldHouse1, 3, 7 and 8, the Diner, the old gas station and the depot.
  Town: the Offices, Pharmacy and Grocery (blown walls) and the Shops (caved roof). OldHouse6 stays whole (it's spawn
  5's cover); the bank, police, town hall and gun store are untouched
- Blast holes are new ways in and out. Rubble inside rooms is looks only, so nothing blocks a doorway or loot
- `tools/gen_old_bloxov.py`: `Building(blasts=..., caved=...)`; the generator refuses a blast on a door or behind
  stairs, and a caved roof over stairs. Real models come later (owner)

## 0.11.5 (store rules: player names filtered; owner)
- **Bloxov now follows the App Store and Google Play rules** (owner: the game will go on phones too). The rules
  that matter are written down in `docs/STORE_RULES.md`, and every change from now on gets checked against them.
  An audit of the game found it already fits (blocky violence, made-up item names, no real money, ads, accounts
  or tracking, saves on your device, encrypted online play). Before a store launch it still needs a privacy policy,
  the age rating forms and phone controls (listed in the doc)
- **Player names are cleaned by the server** (the stores require a filter on anything players type that others
  see): odd characters are dropped, and a rude or hateful name (also spelled with numbers or spaces) becomes
  "Player N". `scripts/name_filter.gd`

## 0.11.4 (war-torn clutter in the empty grass; Map & Spawn follow-up, owner)
- **The empty grass isn't empty any more** (owner: the dead areas need stuff, like a war-torn place would have):
  about 80 spots of gray-box junk spread over the open ground between places: boulders, rubble piles with a bit of
  wall still standing, burnt-out cars (some on their side), a wrecked army truck or two, rows of tank traps, shell
  craters you can crouch in and knocked-over barrels, each with planks and scrap scattered round it. Most of it is
  solid cover. Kept off roads, the railway, yards, buildings, spawns, extracts and loot. Real models come later
- `tools/gen_old_bloxov.py`: `clutter()` places it (fixed seed, so the map stays the same every build)

## 0.11.3 (spawn 5 moved; Map & Spawn follow-up, owner)
- **Spawn 5 moved** (owner: it wasn't good): it was out in the open field in the middle of the map, next to the
  railway, with no cover. It's now behind an old house south of the railway, off the roads, 124 m from the
  nearest other spawn

## 0.11.2 (spawns spread evenly; Map & Spawn follow-up, owner)
- **Player spawns moved** (owner: some pairs felt close enough to see each other): one now in the top-left corner,
  and the rest re-spread evenly, 3 across the top (top-left corner, north of the church, the farm), 3 across the
  middle (west field, north of the railway, east woods edge) and 2 across the bottom (the creek, bottom right).
  The closest two are now 139 m apart (before: 108 m). Each still has 4+ extracts far enough away to open

## 0.11.1 (spawns spread out, O extract list back; Map & Spawn follow-up, owner)
- **Player spawns spread out** (owner: not all on the edge): west field, the creek (bottom left), south of the
  railway, bottom middle, the east edge, east of the train station, the farm, and between the town and the farm.
  All still away from the hot spots, each with room for a duo
- **O shows the extracts open for you** again: a list in the top right (name and distance) that slides in when you
  press O and goes away after a few seconds (or press O again). It no longer pops up on its own at the start, and
  there are still no name tags over extracts; the map (M) shows where they are
## 0.11.0 (Scorched Earth update starts: code cleanup: the AI's navigation helpers)
No gameplay changes. 0.11 is a cleanup pass before Scavs 2.0 and the Items update (owner, 0.10.0).
- The AI's navigation queries (closest walkable point, paths, random spots, safe before the map is ready) moved out
  of `scav.gd` into `ai_nav.gd`, ready for Scavs 2.0's spawn spots and roaming areas
- A scav and its online copies share one place for their shot, alert and bash effects
- Removed unused code: the character tint (unused since Raiders got their own model in 0.7.10) and a crosshair check
- Docs: roadmap, handoff and phase list brought up to date

## 0.10.3 (spawns and extracts; 0.10 is now the "Map & Spawn update", owner)
- **Extracts near where you spawned are closed for you** (owner): anything within 120 m of your spawn stays shut, and
  2 of the far ones open. You and your duo spawn together, so you get the same ones; other squads get their own.
  The map (M) shows only yours
- **6 extracts** now (was 3): Farm Road, Highway, Creek Trail, plus **Town Road** (west end of Main Street),
  **Mill Lane** (top of town) and **South Road** (bottom middle)
- **New player spawns:** 8 spots round the edges in quiet places away from the hot spots, each with room for a duo
  (west field, the creek, the south edge twice, the east edge twice, the farm, north of town)

## 0.10.2 (the map: M, owner)
- **Press M for the map**: Bloxov Frontlines from above with the names of places (bank, police, junkyard, farm...), the
  extracts open for you this raid (green flags), your teammates (green dots) and you (a yellow arrow pointing where
  you look). It stays open while you move; M again closes it
- **Extracts are no longer on your screen** (owner): the O list and the name tags over extracts are gone; the map is
  where you find them. "EXTRACTING" still shows while you stand in one
- The map's drawing comes from the map generator (buildings, roads, the creek, woods, yards, place names)

## 0.10.1 (Bloxov Frontlines: junkyard, checkpoint, church, power lines, owner)
- **Fewer buildings, more places** (owner: replace rather than add, so players spread out and meet at hot spots):
  - a **junkyard** north of the gas station (fenced maze of stacked wrecks, a crane, a crusher, the office) replaces two old houses
  - a **roadblock checkpoint** across the highway west of the gas station (barrier chicane, sandbag nests, guard booth,
    two army trucks) replaces another
  - a **church and graveyard** top right of town (bell tower with a roof lookout, pews, headstones for low cover, a crypt)
    replaces the road house nearest town
  - a **modern gas station** on the corner of Main Street and Old Road replaces the small town house
  - **power lines** along Main Street, the county road and the highway
  - in the bottom-left woods (kept quiet on purpose): a **campsite** by the creek and two climbable **hunting stands**,
    one watching the Creek Trail extract
- **3 big houses on the hill instead of 5**, so the expensive loot isn't spread thin and the hill has sightlines over town
- Main Street runs to the map edge again (the big house at its end is gone)
- 95 loot spots (new places: Campsite, Junkyard, JunkOffice, Checkpoint, Church, BellTower, Crypt, GasStationTown)

## 0.10.0 (the first real map: Bloxov Frontlines, gray box, owner)
- **Raids now happen in Bloxov Frontlines**, a 350 x 350 m town (about 2:15 to walk across on a real route) laid out with the owner:
  the **town** in the top left (winding Main Street, town square full of cover, gun store, pharmacy, grocery, bank,
  offices, police station, school, big houses on the hillside), the **farm** top right, the **train station and
  depot** in the middle, **old houses and the gas station** bottom right, **woods** with 3 cabins, a creek and a railway
- **Buildings have rooms and stairs:** most have 2 floors, and the town hall, police station, school, grocery and train
  station have **rooftops** you can walk on. **The bunker is under the town hall** (ramp down from its west room)
- **97 loot spots**, each tagged with its place (police, bank, bunker, ...) for the Items update. Placeholders for
  the **bunker key door** and the **bank vault door** (open for now; keys come in the Items update)
- **3 extracts** (Farm Road, Highway, Creek Trail; 2 open per raid) and **8 player spawns** round the edges
- **More AI for testing** (owner: harder than seems right): 12 scavs and 3 Raiders at the start, up to 15 alive,
  32 scavs and 8 Raiders over the raid. Spawn spots are placeholders until Scavs 2.0. AI paths can now cross the
  whole map (they used to stop searching after a few thousand pieces of it)
- **Roads are smooth curves** that join up cleanly, and no building stands on a road (the map builder now refuses
  to build one that does, or buildings that overlap)
- **Town and farm layout tweaks** (owner): the county road runs down the farm's west side instead of through it (Farm Road
  extract at its north end), Main Street ends at a **big house** on the west edge, the two shops on the top-left road
  are one big building, the **bank and offices** east of the square are one building (bank and vault downstairs,
  offices upstairs), and the offices west of the square are bigger
- It's a **gray box**: plain coloured blocks for walking, fighting and timing the layout. The look comes later
  (designer), and the props/models after that (artist)

## 0.9.5 (squads spawn together, spectate your teammate, owner)
- **Squads spawn together** online: you and your duo start side by side, and every other squad gets a different spawn
- **Dead with your teammate still in the raid?** The end screen has a **SPECTATE <NAME>** button: the camera follows
  them over the shoulder (SPECTATING BRAVO at the top, with BACK TO HIDEOUT under it). When they extract or die, the
  end screen comes back. Or just go back to the hideout like before
- Everyone already extracts on their own (the raid keeps going for the others); the raid timer keeps running while
  you spectate

## 0.9.3 (pick your med: tap 3 to use, hold 3 to switch, owner)
- **Hold 3 to switch meds:** each hold steps through **Auto -> Bandage -> Medkit -> Auto** (smallest heal first,
  only meds you carry); keep holding to keep stepping. The new pick is shown on tape over the slot ("MEDKIT x1")
- **Tap 3 uses the med the slot shows.** Auto works like before (and like H): the best fit for how hurt you are, marked
  with a small **A** in the slot's corner. Run out of the picked med and it goes back to Auto. **H always heals on Auto**
- **Touch screens:** tapping / holding the meds slot does the same (first piece of touch controls)

## 0.9.2 (downed and revive, owner)
- **In a squad, 0 HP knocks you down instead of killing you** (solo still dies). You drop to the ground and can only
  look around and **crawl at 1/4 speed**: no shooting, healing, looting or extracting
- **Downed bar:** a red DOWNED plate under the crosshair with a bar that drains **100 to 0 over 30 seconds**. Getting
  shot takes from it too, and **at 0 you die** (owner)
- **Revive:** walk up to a downed teammate and **hold F for 5 seconds** ("[F] REVIVE" with a green bar). They get back
  up with **30 HP**. They see a green REVIVING bar while you do it. Their name tag turns red while they're down
- If **nobody is left who could revive you** (your teammate went down too, died, extracted or left), you die
- **Scavs and Raiders ignore downed players**; other players can still finish you off
- Kills on a player who bled out still go to whoever shot them
- (first went live as 0.9.4, renumbered to 0.9.2 by the owner; there is no 0.9.4)

## 0.9.1 (meds slot shows what it'll use, owner)
- **Hotbar key 3 shows the heal it will use right now** (the best fit for how hurt you are, same as H): a
  **bandage roll** for small damage, the **medkit cross** when you're badly hurt, with how many of that one you have.
  Crossed out when you have no heals

## 0.9.0 (start of 0.9: hotbar 1-4 + V, secure pocket at the bottom, owner)
- 0.8 (HUD & inventory) is closed; 0.9 is the rest of multiplayer (raid flow), starting with two owner tweaks:
- **Hotbar is now 1, 2, 3, 4, V:** 1-2 guns, 3 meds, **4 = one free slot** (grenades later), V = knife. Keys 5 and 6
  do nothing now (one grenade slot is enough)
- **The secure pocket is at the bottom** of the inventory column, under your backpack

## 0.8.16 (damage numbers and teammate tags in the HUD style, owner)
- **Damage numbers** (the optional setting) are drawn crisp in the pixel font with a hard dark edge, pop up and float
  away; headshots and backstabs are bigger and yellow with "!" (they used to be blurry 3D text)
- **Teammate name tags** are small bright-green names with a crisp 1-pixel black edge (no plate behind them), so
  they read over sky, grass and dark rooms; still visible through walls
- **Extract tags** keep their plate, with the name in cream (like the extract list) and the green flag, so green
  text now only means a teammate

## 0.8.15 (ONLINE panel in the "Ammo Can" look, owner)
- **ONLINE panel** (hideout): a gunmetal plate, the pixel font, sunk-in text boxes (yellow edge while you type),
  gunmetal buttons, and big hazard-yellow GO ONLINE and QUEUE buttons. Works exactly as before
- The empty status line no longer leaves a gap above CLOSE

## 0.8.14 (pause menu in the "Ammo Can" look, owner)
- **Pause menu:** a gunmetal panel with BLOXOV in the big pixel font, a hazard-yellow PLAY button, sliders with a
  brass fill and a gunmetal handle, checkboxes as small sunk-in boxes with a yellow block when ticked
- The controls list breaks lines between controls (it used to split things like "F3 / debug"), in a slightly wider
  panel

## 0.8.13 (crisp pixel text everywhere, owner)
- **All text is pixel-perfect now:** the pixel font used to be drawn at sizes where its pixels landed between screen
  pixels, so some strokes were thinner than others and some letter pairs looked off. Every size now uses the Jersey
  design made for it, at exactly one screen pixel per font pixel: small text Jersey 10, titles/timer/tags Jersey
  15, the ammo count and big tags Jersey 20, the end-of-raid stamp Jersey 25 (owner's pick from 7 font options)
- The hideout's help line ("Drag to move/equip ...") fits on screen under the columns (it was pushed off the bottom)

## 0.8.12 (a nicer A, owner)
- **The pixel font's capital A is redrawn:** a square top with clipped corners (the old one had a pointed, stepped
  top that looked odd next to the other blocky capitals), spaced like every other letter. It's everywhere the font
  is: HUD, inventory, hideout, end screen, buttons. The font is now "Bloxov Jersey 10" (`assets/fonts/BloxovJersey10-Regular.ttf`, OFL, made by
  `tools/make_bloxov_font.py` from Jersey 10; see `assets/fonts/README.md`)
- **Letters no longer run together:** text shadows drop straight down instead of diagonally (the diagonal shadow
  filled the 1-pixel gaps between letters, so words looked squished)
- The hideout's message tape no longer shows as an empty strip under the top bar when there's no message

## 0.8.11 (hideout in the "Ammo Can" look, owner)
- **Top bar:** a gunmetal strip with BLOXOV in the pixel font, your money on a brass tag, the stats in the pixel font,
  gunmetal buttons and a big hazard-yellow **START RAID**
- **Messages** ("Sold ...", "Not enough money ...") are written on a strip of masking tape under the bar
- **Trader:** a gunmetal column like the inventory's, item names in their rarity color in the pixel font, gunmetal
  price buttons
- **Button labels are centered to the pixel** (and letter-spaced) on every gunmetal button: START RAID, ONLINE, the
  trader's prices, CLOSE, BACK TO HIDEOUT
- (The ONLINE panel keeps its look for now)

## 0.8.10 (end-of-raid screen in the "Ammo Can" look, owner)
- **The result is an ink stamp:** green EXTRACTED, amber MISSING IN ACTION or red KILLED IN ACTION, with a double,
  slightly worn border
- **What your loot was worth on a tag:** brass "KEPT $..." when you made it out, red "LOST $..." when you didn't
- The loot list, how you got out and what happens to your gear in the pixel font; kills, money, raids, extracts
  and deaths as stenciled chips; a gunmetal BACK TO HIDEOUT button
- The raid HUD hides behind it (it used to show through)

## 0.8.9 (extract name tags on plates, "Unarmed", owner)
- **Extract name tags** sit on a small gunmetal plate (green flag + name with the HUD's hard drop shadow) instead
  of a black outline, which looked odd
- **"Unarmed"** (bottom right, no gun) is in the HUD's pixel font, mixed case, with 1 px between letters (the
  letters were squished together)

## 0.8.8 (inventory in the "Ammo Can" look, extract tags, owner)
- **Inventory screen (light pass, same layout):** the columns are gunmetal plates like the HUD; headings, section
  names (POCKETS, SECURE POCKET...), item names in the details and counts use the HUD's pixel font; "Carrying $..."
  is brass; grids and empty equipment slots are sunk in; item tiles keep their rarity colors with a slight bevel;
  a gunmetal CLOSE button. Also shows in the hideout's stash/loadout
- **Extract name tags** over the pads are now drawn crisp in the HUD's pixel font with a green flag (they still show
  through walls, open extracts only)
- **UNARMED** uses clean stencil caps (the pixel font's "A" looked odd there)

## 0.8.7 (HUD "Ammo Can" 3/4: timer, prompts, extracts, owner)
- **Raid timer:** on a gunmetal plate with a hazard strip; the last minute turns it red and it punches every tick
- **[F] prompts:** a cream key cap with F and the action ("SEARCH CRATE") on a plate under the crosshair, with a
  brass bar while searching. Healing shows a red cross, HEALING and a green bar
- **Extract list** (still a few seconds at the start and on O): slides in from the right, a green flag, the name and
  the distance per open extract, and an O key cap
- **Extracting:** "EXTRACTING 4.5" on a green-rimmed plate that fills up; "EXTRACT CLOSED" on a red one with red
  caution stripes
- **Hit direction:** a red pixel chevron instead of a plain bar
- **Hotbar keys** are hand-drawn pixel digits (the old small font drew its "4" with an odd flag)

## 0.8.6 (HUD "Ammo Can" 2/4: hotbar, owner)
- **New hotbar:** gunmetal lids with the key stenciled small in the corner (no more tabs on top), the icon, the
  count and the rarity stripe, with more room between slots
- **The gun in your hands pops up:** lighter lid, hazard-yellow rim, caution stripes along its top edge and a
  yellow key
- **Switching guns** slaps its name on a strip of tape above its slot for a moment (it used to be plain text)
- **Empty slots** are sunk-in wells with a faint ghost of what goes there (rifle on 1, pistol on 2, grenade on 4-5)
- **No meds left:** the cross dims and gets crossed out with a red pixel line, the count turns red

## 0.8.5 (centered hotbar, owner)
- **Everything on the hotbar is centered:** key numbers in their tabs, icons in the space under the tab, counts
  across the slot (measured to the pixel; the text used to sit a bit left and low)
- The health number is centered on its brass tag, and RELOADING on its tape
- Empty hotbar slots are sunk-in wells (instead of dashed outlines), matching the new look

## 0.8.4 (HUD "Ammo Can" 1/4: health & ammo, owner)
- **New HUD look, "Ammo Can":** chunky beveled blocks of gunmetal-painted steel, built like the voxels of the world,
  with brass, hazard stripes and masking-tape labels as the scavenged details. Two new pixel fonts (Silkscreen for
  tiny stenciled labels, Pixelify Sans for writing on tape; both OFL). The rest of the HUD already uses the new
  colors; hotbar, timer and prompts get their full makeover in the next updates
- **Health:** 10 voxel cubes (green / yellow / red) and the number stamped on a brass tag. A partly lost cube
  shrinks; getting hit **knocks cubes off** (they flash, pop up and tumble away) and jolts the plate. At 30 or less
  the tag turns red and pulses. Stamina is a thin bar under the cubes (only while it isn't full), hazard-striped
  when you're exhausted
- **Ammo:** the count big on the left; the magazine as a row of brass cartridges with the reserve under it.
  Yellow when low, red when empty. Reloading refills the cartridges and shows a strip of tape saying RELOADING
- **The knife looks like a knife** (V on the hotbar, and when unarmed): steel blade, guard and a wooden handle

## 0.8.3 (HUD redesign: "Stenciled Field Kit", owner; first released as 0.7.15)
- **New HUD look:** dark gunmetal plates with notched corners and a chunky pixel font (Jersey 10) for numbers,
  matching the inventory screen
- **Health:** a red cross and 10 blocks (10 HP each, green / yellow / red). Getting hit **chips blocks off** (they
  flash, fall and fade) and shakes the plate; at 30 or less the cross and number pulse. Stamina is a thin bar under
  the blocks (hazard stripes when you're exhausted)
- **Hotbar:** slots with stamped key tabs, pixel icons (rifle, pistol, med cross, knife), counts and a rarity stripe.
  The gun in your hands rises and glows yellow, and its name shows for a moment when you switch. Empty slots are
  dashed ghosts (a faint grenade on 4 and 5); no meds left = crossed out
- **Ammo:** the magazine as a row of bullets (spent ones hollow) above a big count and the reserve; yellow when low,
  red when empty; bullets refill during a reload; "UNARMED" with a knife when you have no gun
- **Timer** on a plate (red and punching on every tick in the last minute), **extract list** and **[F] prompts** on
  plates, a pixel crosshair and a pixel hit marker (yellow on headshots)

## 0.8.2 (inventory screen polish, owner; first released as 0.7.14)
- **New layout:** gear on the left (with **your character**, the PMC model for now), everything you carry in the
  middle (pockets, secure pocket, backpack), and the container you're looting (or your stash) on the right
- **The HUD hides while the inventory is open** (only the raid timer stays: the raid doesn't pause)
- **Item names fit their tiles** (full name, smaller font when needed)
- **Item details** when you point at something: name in its rarity color, then rarity, size, stats (guns: damage,
  fire rate, magazine, loaded; heals: HP; armor: %; backpacks: size), value, and the sell price in the hideout.
  No placeholder text when you're not pointing at anything

## 0.8.1 (HUD polish, owner; first released as 0.7.13)
- **Health is a bar** with the number on it (green, yellow as it drops, red at 30 or less)
- **"Carrying $..." is gone from the raid screen** (it's still in the inventory)
- **The extract list shows for a few seconds** at the start of the raid and when you press O (then hides)
- **Hotbar (owner's layout):** 1 and 2 = your guns, **3 = Meds** (all your heals; uses the one that fits how hurt
  you are, same as H), 4 and 5 = free for later (grenades...), 6 = **Knife (V)** (6 swings it too). Heals no longer
  bind to keys one by one. Smaller slots; empty ones are faint
- The bottom of the screen is much less crowded
- **ONLINE panel:** just your name, Go online and Close (no server address box; it always uses the game's server)

## 0.8.0 (hideout fixes, owner; first released as 0.7.12)
- Hideout messages ("Sold Antique Vase for ...") show in full under the top bar and fade out (they were cut off)
- The ONLINE button shows where you are with the panel closed: "ONLINE ●" (online), "IN QUEUE (1/2)",
  "RAID IN 21s"
- Teammates' name tags are smaller

## 0.7.11 (no gun when unarmed)
- Other players' models only show a gun while they're holding one (the character models have a rifle built in;
  separate gun models are planned, see BACKLOG)

## 0.7.10 (Raider models, owner)
- **Raiders have their own look** instead of a red-tinted PMC: dark gear with a red armband, heavy armor with
  shoulder plates and a groin flap, skull masks, gas masks, balaclavas, visored heavy helmets, hoods or red bandanas,
  and an RPK with a drum mag. Easy to tell apart from scavs (ragtag) and players (PMC gear) at a glance
- Random outfits like scavs (2,880 combinations), and the same outfit for everyone online
- The PMC model is now only used for players
- Test fix: the spawn test now accepts the first Raider arriving as a duo (the new model's random outfits changed
  the test's random rolls so a duo came up)

## 0.7.9 (multiplayer: shared loot)
- **Loot is shared online.** Crates, lockers and safes have the same contents for everyone (rolled by the
  server): take something and it's gone for the others
- **One player at a time** can have a container open; anyone else trying gets "Someone else is looting that"
  (you each still search it yourself)
- **Scav and Raider bodies** leave body bags everyone sees and can loot
- **Dead players drop a body** ("Name's Body") with everything they carried (not the secure pocket): PvP loot
- **Dropped items** become a bag everyone sees; emptied bags disappear for everyone
- Solo raids work exactly as before

## 0.7.8 (multiplayer: everyone sees the same AI)
- **Scavs and Raiders are back in online raids, and everyone sees the same ones.** They run on the server (each
  raid has its own), with the same behavior as solo: patrols, spotting, hearing, cover, healing, Raider duos, spawn
  budget. Everyone sees the same scavs in the same places, wearing the same outfits
- They **see, hear, shoot and rifle-butt every player** in the raid (footsteps, gunshots, near misses); their hits
  go through your armor as usual
- **Your shots and knife hit them on the server** (hit markers, sounds and kills like solo; backstabs still kill)
- The **knife works on other players too** now (45 damage, backstab kills)
- Scavs pop into voxels for everyone when they die. Their **body bags (loot) come in the next update** (shared
  loot)
- Fix: a scav whose target left (died/extracted/disconnected) between sight checks could crash its AI (only
  possible with more than one player)

## 0.7.7 (multiplayer: shooting each other)
- **You can shoot other players online** (friendly fire is on: teammates too). Hit markers, hit/headshot sounds and
  the kill sound work like against scavs; kills count on the end screen
- **The server decides every hit:** each online raid has its own copy of the map on the server, so walls stop
  bullets, and damage comes from the gun's stats (AK 28, x2 to the head; pistol 17, x2.5), never from the shooter
- **Lag compensation:** a shot is checked against where the target was *on your screen* when you fired, so a shot
  that looked like a hit counts
- Your armor protects you from other players like it does from scavs
- The server ignores shots that couldn't be real (impossible fire rate, fired from somewhere you aren't, not a gun)
- At most 40 players online at once, so a flood of fake connections can't swamp the server
- README shows the current version (it still said 0.5.7)

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
