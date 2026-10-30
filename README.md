# Bloxov: No Man's Land

**A blocky first-person extraction shooter. Loot weird stuff, get attached to it, try to make it out alive.**

[![Build and deploy](https://github.com/TavishHanda/Bloxov/actions/workflows/web.yml/badge.svg)](https://github.com/TavishHanda/Bloxov/actions/workflows/web.yml)
![Version](https://img.shields.io/badge/version-0.14.21-informational)
![Godot](https://img.shields.io/badge/Godot-4.5-478cbf?logo=godotengine&logoColor=white)
![Platform](https://img.shields.io/badge/platform-web-success)

### ▶ [Play it in your browser](https://tavishhanda.github.io/Bloxov/)

Gear up in your hideout, drop into a war-torn border town with a loadout, grab whatever you can and decide when to
run for an exit. Make it out and you keep everything. Die and you lose it all, except what fits in your secure
pocket. Play solo, or squad up online with friends in raids shared with other players.

> Bloxov is in active development. Everything here is playable today on the live build; art is still mostly
> gray-box while the gameplay is proven out. Every change is listed in [`CHANGELOG.md`](CHANGELOG.md).

---

## Contents
- [The world](#the-world)
- [Features](#features)
- [Controls](#controls)
- [Roadmap](#roadmap)
- [Development](#development)
- [Project layout](#project-layout)

---

## The world

Two superpowers, **Novarra** and **Exion**, are locked in a global war. Years ago a Novarran strike on the Exion
Brotherhood's secret super-soldier program went wrong and laid huge regions to waste. Now most of the world is
abandoned, and the regions still worth something are picked over by contractors.

You are one of them: a **REVENANT** contractor, hired by whoever pays to pull resources out of the dead zones. Your
first stop is **Bloxov**, a border region far from ground zero, still grounded and normal, and its first map,
**Bloxov Frontlines**. The full lore lives in [`docs/LORE.md`](docs/LORE.md).

---

## Features

### The raid loop
- **Hideout:** your stash, loadout and trader. Sell what you bring home, buy better gear, and pick what to risk.
  Broke and unarmed? Take the free kit (pistol, ammo and a bandage).
- **10-minute raids** with a clock. Get to an open extract before time runs out.
- **Extract or lose it:** extract and you keep everything; die and you lose your gear, except the 2×2 secure pocket.
  The death screen shows what you lost.
- Progress (stash, money, loadout, settings) is saved in your browser.

### Combat
- Aim down sights, real view recoil, spread and flinch, tuned time-to-kill.
- Pistol (semi-auto) and AK rifle (full-auto) with two ammo types, reloads that pull from your inventory, and a knife
  (backstabs kill).
- **Armor and helmets** cut body and head damage; headshots hurt.
- **Frag grenades** (pull, throw, take cover), bandages and medkits with heal animations you can cancel, and energy
  drinks for free sprinting.
- Damage direction arrows, optional damage numbers, and hit feedback.

### Movement
- Sprint with stamina, crouch (quiet), **prone**, lean left and right.
- **Vaulting:** vault over fences, sandbags and walls, and climb onto ledges.
- Ladders, fall damage, and wading through the creek.

### Enemies
- **Scavs** patrol their zones, hear footsteps and shots, spot you at range, call out to each other, take cover,
  flank, chase, push and suppress, and heal when it's quiet.
- **Raiders:** tougher, better-armed and sharper shots.
- **Snipers** in high spots, with a scope glint that gives them away.
- **Bon**, the boss of Bloxov Frontlines, holds the town hall and its bunker with his guards. He wears heavy armor
  and carries the Bunker Key, an Exion Medal and his own dog tag.
- Everything an AI wears and carries can be looted off its body.

### Items and loot
- A grid ("Tetris") inventory with rotation, stacking, drag-to-swap, backpacks and equipment slots.
- 49 items from bolts to the Holy Grail, across six rarities, each with a description
  (full list: [`docs/ITEMS.md`](docs/ITEMS.md)).
- **Loot by place:** pharmacies have meds, the police station has armor and pistols, the bank and big houses have
  valuables, and the bunker has the best of the best.
- **Keys and locked rooms:** the Bank Vault Key and the Bunker Key open the map's two vaults.
- Crates, lockers, safes (loud to open), loot bags and bodies, plus dog tags from Raiders, Bon and other players.

### The map: Bloxov Frontlines
- A 350 × 350 m war-torn town on rolling hills: Main Street and the town square, the town hall and bunker, the bank,
  a church and bell tower, the train station and depot on a railway, a farm, a junkyard, gas stations, woods cabins,
  hunting stands and a creek.
- Trenches, craters, wrecked cars and battle damage for cover.
- 8 player spawns round the edges; extracts near your spawn are closed, so you have to cross the map.
- A full-screen map (**M**) that shows the hills.

### Online
- **Party up** with a friend's code and queue into raids with **2-6 players**: co-op with your squad, PvP with
  everyone else.
- Server-checked shots with lag compensation, server-run AI, and shared loot (one looter per container at a time).
- **Downed, not dead:** teammates can revive you, you extract one at a time, and you can spectate your squad after
  you're out.

---

## Controls

| Key | Action |
|---|---|
| Mouse | Look |
| Left click | Shoot / throw |
| Right click (hold) | Aim down sights (cancels a throw or heal) |
| W A S D | Move |
| Shift | Sprint (uses stamina) |
| Space | Jump / vault / climb |
| C | Crouch |
| Z | Prone |
| Q / E | Lean left / right (hold, or tap-to-toggle in the menu) |
| R | Reload (rotates an item while dragging it) |
| 1 / 2 | Primary / secondary weapon |
| 3 | Meds (uses the best fit) |
| 4 | Bindable slot (e.g. grenades) |
| H | Heal |
| V | Knife |
| F | Search, loot, open doors |
| Tab | Inventory |
| M | Map |
| O | Show open extracts |
| Esc | Menu: volume, mouse sensitivity, damage numbers, lean mode |
| F3 | Debug overlay |

Touch controls are planned for the mobile release.

---

## Roadmap

The game ships in updates. The middle version number is the update, the last number is each change in it.

| Version | Update | |
|---|---|---|
| 0.5 | Guns | ✅ |
| 0.6 | Scavs | ✅ |
| 0.7 | Multiplayer | ✅ |
| 0.8 | HUD & Inventory | ✅ |
| 0.9 | Raid Flow (downed, revive, spectate) | ✅ |
| 0.10 | Map & Spawn | ✅ |
| 0.11 | Scorched Earth | ✅ |
| 0.12 | Hot Zone (Scavs 2.0) | ✅ |
| 0.13 | Over the Top (Movement) | ✅ |
| **0.14** | **Spoils of War (Items)** | 🔨 now |
| next | Guns, Sound, Economy, then art and the vertical slice | |

**Release plan:** a free **open web beta** when the game feels done, then **Steam Early Access** (free, with
crossplay and shared progress with the web), then **mobile**. Details: [`docs/ROADMAP.md`](docs/ROADMAP.md).

---

## Development

Built with **Godot 4.5** in **GDScript**, using the Compatibility renderer so it runs in browsers.

### Run it locally
1. Download **Godot 4.5** (standard, *not* .NET) from https://godotengine.org/download
2. In Godot: **Import** → pick this folder's `project.godot`
3. Press **F5**

### Tests
CI runs a headless gameplay test that plays through the game in named sections (shooting, recoil, the knife,
the AI, movement, vaulting, loot, the inventory, healing, extracting, dying, the hideout, online play with a
server and two clients, and more). From the repo root:

```
godot --headless --import
godot --headless --fixed-fps 60 -s tests/smoke_test.gd
```

It must print `SMOKE TEST: PASSED` with no `SCRIPT ERROR`. To run only some sections (plus what they depend on):
`godot --headless --fixed-fps 60 -s tests/smoke_test.gd -- section=knife,heal`. Your saved profile is backed up and
restored by the test.

### Deploys
Every push to `main` runs the tests, builds the web version and publishes it to
[GitHub Pages](https://tavishhanda.github.io/Bloxov/), and deploys the game server to Heroku.
Run a server yourself with `godot --headless -- --server [--port=9080]`.

### Versions
`MAJOR.UPDATE.CHANGE`. The current version is `config/version` in `project.godot`; it's shown in the menu and the
top-right corner. Every change is in [`CHANGELOG.md`](CHANGELOG.md).

### Making changes
- **Items:** edit `ITEMS` and `LOOT_TABLES` in `scripts/item_db.gd`, then run `python3 tools/gen_item_list.py` to
  update `docs/ITEMS.md`.
- **The map:** generated by `tools/gen_old_bloxov.py`. Edit the script and re-run it; never edit the scene by hand.
- **Tuning:** most numbers (damage, fire rate, recoil, AI senses…) are `@export` vars you can change in the Inspector.
- **Sounds:** placeholders generated by `python3 tools/make_sounds.py` until the Sound update.

<details>
<summary>Coming from Unity</summary>

| Unity | Godot |
|---|---|
| GameObject + Components | **Node** (each node does one thing; build a tree of them) |
| Prefab | **Scene** (`.tscn`). Any scene can be instanced inside another |
| `MonoBehaviour` | Script attached to a node (`extends CharacterBody3D`) |
| `Start()` / `Update()` / `FixedUpdate()` | `_ready()` / `_process(delta)` / `_physics_process(delta)` |
| `[SerializeField]` | `@export` |
| `GetComponent<T>()` | `$ChildName` or `get_node("Path")` |
| `CharacterController` | `CharacterBody3D` + `move_and_slide()` |
| ProBuilder | **CSG nodes** (`CSGBox3D`, etc.) for gray-boxing |
| UnityEvents / C# events | **Signals** |
| Input Manager | Project Settings → **Input Map** |

</details>

---

## Project layout

```
scenes/      .tscn scenes (hideout = main scene, raid, player, AI, containers, doors, ladder)
scenes/maps/ generated maps (Bloxov Frontlines)
scripts/     GDScript (player, guns, AI, inventory, profile, hideout, HUD, networking...)
assets/      models (.glb)
art_source/  Blender sources (ignored by Godot)
materials/   shared materials
audio/       sound effects
tests/       headless gameplay tests and checks
tools/       generators (map, item list, sounds)
docs/        design and planning docs
```

| Doc | What's in it |
|---|---|
| [`GAME_DESIGN.md`](docs/GAME_DESIGN.md) | The game design |
| [`LORE.md`](docs/LORE.md) | The world and story |
| [`ROADMAP.md`](docs/ROADMAP.md) / [`BACKLOG.md`](docs/BACKLOG.md) | What's next / parked ideas |
| [`ITEMS.md`](docs/ITEMS.md) | Every item and loot table (generated) |
| [`MAP_PLAN.md`](docs/MAP_PLAN.md) | Bloxov Frontlines |
| [`SCAVS_PLAN.md`](docs/SCAVS_PLAN.md) | The AI |
| [`MULTIPLAYER_PLAN.md`](docs/MULTIPLAYER_PLAN.md) | Online play and the server |
| [`INVENTORY_DESIGN.md`](docs/INVENTORY_DESIGN.md), [`STASH_TRADER_PLAN.md`](docs/STASH_TRADER_PLAN.md), [`GUNS_PLAN.md`](docs/GUNS_PLAN.md) | Feature plans |
| [`ART_SPEC.md`](docs/ART_SPEC.md) | Art pipeline and sizes |
| [`STORE_RULES.md`](docs/STORE_RULES.md) | App Store and Google Play rules every change follows |
| [`DEV_HANDOFF.md`](docs/DEV_HANDOFF.md) / [`DESIGN_HANDOFF.md`](docs/DESIGN_HANDOFF.md) | Catch-up for new dev and design sessions |

