# Map plan: Old Bloxov (first real map)

Agreed with the owner on 2026-10-09 (layout draft 5). Lore is the owner's; don't invent it.
Picture: [`maps/old_bloxov_layout.png`](maps/old_bloxov_layout.png) (drawn by `maps/old_bloxov_layout.py`; edit
the script and re-run it to change the picture). Coordinates in the script are meters, origin top-left, north up.

## Basics
- **Size:** 350 x 350 m. About 2:15 to walk across on a real route (walk speed 3.4 m/s).
- **Raids:** 10 minutes, up to 6 players (duos or solos). Daytime. Some rooftops; detailed buildings with lots of rooms.
- **Extracts:** farm road (north), highway (south-east), creek trail (south-west). 2 of 3 open each raid.
- **Player spawns:** 8, around the edges.

## Areas
- **Town (top left):** winding Main Street with side lanes (not a grid). Town square with lots of cover
  (fountain, planters, market stalls, parked cars, statue). Big houses on the hillside (north-west).
- **Farm (top right):** barn, silo, farmhouse, shed, fields. A few houses along the road between town and farm.
- **Middle:** railway running west to east (bridge over the creek), train station just south of the town,
  depot (engine shed) on side tracks, boxcars as cover.
- **Bottom right:** old houses, few and spread out; gas station, diner and garage on the highway.
- **Woods:** bottom left (with the creek) and east side (between the farm and the old houses).
  Woods cabins: 2 in the bottom-left woods, 1 in the east woods.

## Loot by place (owner)
| Place | Loot |
|---|---|
| Town hall | mid upstairs; the bunker under it has the best of the best |
| Big houses, bank | expensive (different kinds in each) |
| Police station | armor, pistols |
| Gun store | guns, gun parts (when added) |
| Pharmacy | meds |
| Grocery, diner | food |
| School | backpacks, gear |
| Shops, offices, houses, station | mid |

## Roles
This project builds the layout (walls, cover, spawns, extracts, nav, scav spawns) as a gray box first. The designer
session does the look; the Artist session makes props and models per `ART_SPEC.md`.

## Still to decide (owner: "there will be a lot of changes")
Spawns, extracts, loot spots and player spawns on the layout picture are **placeholders**.
- **AI spawn spots (owner: super important):** designated spots for every AI on this map, per area. Today
  `enemy_spawner.gd` picks any child marker out of sight of players (20 scavs + 5 Raiders per raid, max 5 alive),
  tuned for the 80 m test map.
- Spawning in general, extracts, loot placement, when players spawn. Questions for the owner are in the project thread.

## Owner answers (2026-10-09)
- **Scavs:** don't wander the whole map (no random scav between hotspots: players learn where AI is). Each scav
  roams its own area like a scavenger, "searching" spots (not real looting), and carries random low-tier loot to
  simulate what it scavenged.
- **Raiders:** mostly at the high-value places (town hall/bunker, bank, police, gun store); a few elsewhere.
  Tough AI is most likely where the best loot is.
- **AI count:** a set number at raid start, then more trickle in. Make it harder than seems right for testing.
- **Players:** duos spawn together; everyone spawns at raid start (no late spawns).
- **Extracts:** preset spots; extracts close to where you spawned are closed for you. Special extracts: later. (Built in
  0.10.3: 6 extracts, closed within 120 m of your spawn, 2 of the rest open; 8 player spawns round the edges.)
  No train extract.
- **Keys:** probably yes for the bunker and bank vault (see the thread). Locked doors only at special places.

## Phases (owner, 2026-10-09)
- **0.10 the map:** Old Bloxov as a walkable gray box (layout, buildings with rooms, cover, extracts, player spawns,
  loot spots), then iterations with the owner.
- **Scavs 2.0 (own update):** designated AI spawn spots per area, scavs roaming their area, Raiders at hotspots,
  low-tier "scavenged" loot on scavs, new AI numbers.
- **Items update (own update):** keys (bunker, bank vault), loot by place (the table above). The 0.10 gray box
  gets placeholders for them now (owner): marked key-door spots at the bunker entrance and the bank vault (open
  until the Items update makes them lock), and loot spots tagged with their place.

## How it's built (0.10.0)
- `tools/gen_old_bloxov.py` writes `scenes/maps/old_bloxov.tscn`. **The script is the source of truth:** edit it
  and re-run `python3 tools/gen_old_bloxov.py`; never hand-edit the scene. Coordinates in the script are the
  picture's map meters (x east, y south, origin top-left); Godot x = mx - 175, z = my - 175.
- Walls, floors, ramps and cover are plain boxes in one `BoxMap` node (`scripts/box_map.gd`): one mesh, one
  collision shape, and the nav baker reads its faces. Loot containers, extracts, spawns and the `KeyDoors`
  markers are normal nodes (each container has `metadata/place`).
- The raid scene (`main.tscn`) keeps its small test map; `RaidMap` (`scripts/raid_map.gd`, main.tscn's root script)
  swaps the map in when the scene is made (players and the server alike). `RaidMap.scene_path = ""` keeps the test
  map (the smoke test does). The map scene's `spawner` metadata sets the AI numbers.
- Buildings: `Building(...)` = storeys of 3 m, rooms in a grid with doorways between all neighbours, windows,
  ramps as stairs (2.2 m wide, 34 degrees, landing at the top) and optional walkable roofs. Doorways are 2+ m and
  ramps 2.2 m because the AI's paths keep 0.75 m from walls; the `old_bloxov` test section checks that every loot
  container can be walked to, so a change that blocks a room fails the test.
