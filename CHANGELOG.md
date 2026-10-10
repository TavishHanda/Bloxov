# Changelog

Versions are `0.PHASE.CHANGE`: a new roadmap phase bumps the middle number, every change after that bumps the last.

<!-- Phases: 0.7 = multiplayer (0.7.0-0.7.11), 0.8 = HUD and inventory (0.8.0 onward). The first four 0.8
updates went out as 0.7.12-0.7.15 and were renumbered afterwards (owner). -->

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
## 0.11.0 (code cleanup starts: the AI's navigation helpers)
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
- **Press M for the map**: Old Bloxov from above with the names of places (bank, police, junkyard, farm...), the
  extracts open for you this raid (green flags), your teammates (green dots) and you (a yellow arrow pointing where
  you look). It stays open while you move; M again closes it
- **Extracts are no longer on your screen** (owner): the O list and the name tags over extracts are gone; the map is
  where you find them. "EXTRACTING" still shows while you stand in one
- The map's drawing comes from the map generator (buildings, roads, the creek, woods, yards, place names)

## 0.10.1 (Old Bloxov: junkyard, checkpoint, church, power lines, owner)
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

## 0.10.0 (the first real map: Old Bloxov, gray box, owner)
- **Raids now happen in Old Bloxov**, a 350 x 350 m town (about 2:15 to walk across on a real route) laid out with the owner:
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
