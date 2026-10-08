# 🎮 Bloxov — Design Doc (v2)

> **Genre:** blocky voxel extraction shooter
> **One line:** Loot weird stuff, get attached to it, try to make it out alive.

---

## 1. The Pitch

A short-session extraction shooter with a goofy pixel/voxel look. You drop into a small map with a loadout, grab whatever you can, and decide when to run for an exit. Make it out and you keep everything. Die and you lose what you brought and what you found.

**North star:** *Loot something valuable. Get attached to it. Risk it. Survive. Extract. Go again.*

**The feeling we want:**
"One quick raid." → 30 minutes later: "I just lost all my good gear." → "Okay. One more."

**Success test for the MVP:** a stranger plays it, finds something valuable, gets nervous about losing it, extracts (or doesn't), and **queues another raid without being asked.** Nothing else counts.

---

## 2. Decisions to Lock Before Writing Code

These change everything downstream. Pick once and stop debating.

| Decision | Recommendation | Why |
|---|---|---|
| **Camera** | **First-person 3D**, blocky voxel look | The most exciting option, and excitement is what gets a solo project finished. First-person also skips full-body player animation: just arms and a gun. |
| **Engine** | **Godot 4, GDScript** | Free, light, exports to web/iOS/Android/PC. GDScript (not C#) because C# can't export to web in Godot 4. Uses the Compatibility renderer so it runs in browsers. |
| **Art** | Voxel/low-poly **asset packs** first (Kenney, Synty, MagicaVoxel) | 3D art is the biggest time sink. Placeholder cubes are fine until Phase 5. |
| **Inventory** | Fixed **slots**, items take 1–4 slots | Tetris grids are fiddly on touch screens. Slots still force the key "what do I drop?" choice. |
| **Ammo** | **One ammo type** to start | Ammo is still a resource you manage, without the spreadsheet. Split it later only if playtests show it would help. |
| **PvP** | **No.** PvE only for a long time | Solo and co-op against AI. PvP needs servers, anti-cheat and matchmaking, which is a separate game's worth of work. |

> **3D scope rule:** 3D costs more than 2D in art, animation and performance. To pay for it, keep the map small, use asset packs, and keep the enemy count per raid low (~10–20).

---

## 3. The Core Loop

```
Stash → Pick loadout → Drop in → Loot / fight / sneak → Decide → Extract → Sell / store → Repeat
                                              │
                                              └─ Die → lose raid gear → back to stash
```

Each raid is **5–12 minutes** with a **hard timer.** When the timer runs out, you're killed and count as missing in action. The timer creates pressure, so the player doesn't have to invent it.

### What makes a raid interesting: three decisions

The whole game is about these. Every feature should feed at least one of them.

1. **Go deeper or leave?** The good loot is far from spawn, in dangerous places.
2. **Fight or avoid?** Gunfire is **loud** and pulls nearby enemies. Shooting is always a cost.
3. **What do I carry?** Your bag is full. Drop the medkit to fit the laptop?

---

## 4. Death Penalty (the part most extraction games get wrong)

Death has to hurt, but it can't trap a player at zero. Make it hurt without being punishing:

- **You lose:** everything you brought in and everything you found.
- **You keep:** your stash, your money, and anything in your **secure pocket** (1 small slot that's never lost).
- **Free loadout:** you can always start a raid with a free junk kit (bad pistol, a few bullets, no armor). A broke player can always earn their way back, which also makes high-risk "nothing to lose" runs possible.
- **Insurance (later, maybe):** pay to sometimes get your gun back.

Without the free kit, one bad streak means quitting. With it, a bad streak becomes a comeback story.

---

## 5. MVP Content: the first playable

Deliberately small. Resist adding to this list.

**Map — 1 small map ("Abandoned Town")**
- 4–6 spawn points, 3 extraction points (only 2 open each raid, chosen at random)
- ~6 buildings with loot spots, scaled by danger:
  - Outskirts: houses, gas station, common loot, few enemies
  - Middle: grocery, police station, mixed
  - Center: **bunker**, best loot, guarded, opening the door makes noise

**Weapons — 4 to start (the sniper can wait)**
| Weapon | Identity |
|---|---|
| Pistol | Weak, but accurate and always available (free kit) |
| SMG | Sprays fast, chews through ammo |
| Shotgun | Deletes things up close, useless at range |
| Rifle | Balanced, the "good gun" you're scared to lose |

**Items**
- Ammo (one type)
- Bandage (small, slow heal) and medkit (big heal, takes 2 slots)
- Armor: light / heavy
- Backpacks: small / medium / large (more slots)
- Valuables: ~10 items across 5 rarities, e.g. watch, laptop, crystal, military chip, antique vase, and the **Golden Toilet** (legendary, 4 slots, worth absurd money, totally useless)

**Enemies — 3 types**
- **Rusher:** melee, fast, comes at you
- **Shooter:** ranged, keeps distance, uses cover
- **Brute:** slow, tanky, guards the bunker, drops good loot

**Systems:** movement, shooting, reload, health, noise, inventory, looting, extraction, death, stash, sell, buy.

---

## 6. Loot & Value

- **Rarity tiers:** Common → Uncommon → Rare → Epic → Legendary, each with a clear color and pickup sound. Legendary pickups should feel like a slot machine paying out.
- **Value per slot is the real stat.** A gold watch (1 slot, $2k) vs. a laptop (2 slots, $3k) is a real decision. The Golden Toilet ($50k, 4 slots) makes you dump half your bag.
- **Show the number.** The HUD shows "Bag value: $12,400" at all times. Watching it climb is what makes you scared to die.
- **Containers:** crates, lockers, safes. Opening takes a moment, which leaves you vulnerable.

---

## 7. Stash & Economy (keep it boring and simple)

- **Stash:** a fixed number of slots, upgradable with money.
- **Money comes from** selling extracted items.
- **Money goes to** guns, ammo, meds, armor, backpacks, stash upgrades.
- **One trader, one shop screen.** Buy and sell. That's it.
- No crafting, quests or trading for now.

**Progression = access, not power.** Unlocks give *options* (new guns, bigger bags, later new maps), not +10% damage. A new player with a rifle should be able to kill a veteran's character.

---

## 8. Combat Feel

Fast, readable, punchy. Juice matters more than realism:

- Screen shake, muzzle flash, hit flashes, damage numbers (toggleable)
- Distinct sound per gun; a sharp, unmistakable "you got hit" sound and red screen edge
- Short knockback on hits; enemies visibly react
- Recoil as a gameplay mechanic (spread grows while firing), not realistic camera kick
- Each gun recognizable by sound with your eyes closed

## 9. AI (simple state machine)

```
Idle/Patrol → (sees or hears player) → Alert/Investigate → Attack → Search → Return
```

- **Hearing matters:** gunshots, sprinting and opening the bunker all make noise with a radius. This one system gives "fight or avoid" its meaning.
- **Personalities come later:** Coward (flees when hurt), Guard (never leaves post), **Loot Goblin** (grabs loot and runs for an exit; kill it to get the stuff).

---

## 10. Controls

**PC:** WASD move · mouse look · LMB shoot · RMB aim · R reload · E interact · Tab inventory · Shift sprint

**Mobile (designed from day 1, built in Phase 6):**
- Left side: virtual joystick to move
- Right side: drag anywhere to look
- **Light aim assist** (slight slowdown/stick on enemies), plus an optional auto-fire setting like Pixel Gun / CoD Mobile
- Buttons: fire, reload, interact (context-sensitive), heal, sprint
- Inventory works with taps, no drag precision required

Keep the button count small enough that it fits on a phone. That limit is a feature: it stops the game from growing too many inputs.

---

## 11. Roadmap

> **Superseded by [`ROADMAP.md`](ROADMAP.md)** (milestones M1–M6, including an early multiplayer spike). Phases 0–2 below are done; kept for history.

Each phase ends with **a build someone else plays.** The web export runs from week 1, not "Phase 7."

| Phase | Build | Done when… |
|---|---|---|
| **0. Setup** | Godot project, auto-deployed web build (GitHub Pages) | A friend can open a link and walk around a gray box |
| **1. Move + shoot** | Player, camera, one gun, a target dummy, one dumb enemy | Shooting an enemy feels good |
| **2. The loop** | Loot containers, slot inventory, extraction zones, raid timer, death | One full raid works start to finish, even ugly |
| **3. Stakes** | Stash, money, sell/buy, free kit, secure pocket | Players care whether they extract |
| **4. Threat** | 3 enemy types, noise, bunker + guard | Players hesitate before going to the bunker |
| **5. Polish + test** | Juice, sound, 4 guns, 10 valuables, randomized loot/extracts | Strangers queue a second raid unprompted |
| **6. Mobile** | Touch controls, UI scaling, perf pass | Fun on a mid-range phone |
| **7. Co-op** | 2–4 players, revive, shared raid | Only after 5 is true |

**Saving:** local save file in `user://` (on web this is backed by browser storage). No backend, accounts or servers until co-op.

---

## 12. Later: only if the core is fun

Roughly in priority order:

1. More valuables and weird weapons (nail gun, potato cannon, freeze gun, golden gun)
2. Dynamic events: supply drop, power outage (dark areas = better loot), boss spawn, extract shutdown
3. Second map
4. Solo challenges ("extract with 3 legendaries," "kill the boss without healing")
5. Co-op (see note below)
6. Cosmetics

**Honest note on co-op:** adding multiplayer to a finished single-player game is famously painful. You don't need to build networking early, but **keep game state (health, inventory, loot) separate from visuals and input** from day one. Then, if co-op happens, it's a retrofit instead of a rewrite.

**Backend (Node/TS, Postgres, auth):** only needed for co-op or cross-device saves. Ignore it entirely until then.

---

## 13. Not Building (until further notice)

PvP · big maps · multiple maps · vehicles · attachments · crafting · quests · skill trees · hunger/thirst · multiple ammo types · clans · trading · battle pass · ranked · voice chat · weather · accounts

---

## 14. The Rules

1. **Does it make the core loop more fun?** If not, it doesn't go in.
2. **Depth comes from decisions, not menus.**
3. **Playtest every phase with someone who isn't you.** Watch silently. Where they get confused or bored is the to-do list.
4. **If unsure, prototype it in a day.** If it isn't fun in a day, it probably won't be in a month.
5. **Make the core loop fun before building anything else.**
