# Inventory Design (M1)

Tarkov / Arc Raiders / Marathon style: **equipment slots + grid ("Tetris") inventory**.
Status: **approved** (placeholder version; will need an overhaul before full release). Step 1 shipped in 0.3.6, step 2 (equipment + hotbar) in 0.3.7, step 3 (stash & trader) in 0.4.0 (see `STASH_TRADER_PLAN.md`).

## Decisions (owner)
- Grid inventory with **rotation** (R while dragging).
- **Stacking** for consumables and ammo.
- **No magazines.** Loose rounds sit in the grid as stacks; reloading pulls rounds from your inventory.
- **H** still heals (best-fitting heal item from anywhere on you).
- **Secure pocket**: a small grid you never lose on death.
- Placeholders everywhere for now: item icons are auto-generated colored blocks (size of the item, name, rarity border).

## Equipment slots
| Slot | Holds | Notes |
|---|---|---|
| Primary | Rifle / shotgun / sniper | Key **1** |
| Secondary | Pistol | Key **2**. New basic pistol added for this |
| Armor | Light / heavy armor | Reduces damage taken (light 20%, heavy 40%). No durability yet |
| Backpack | None / small / medium / large | Decides your backpack grid size |
| Secure pocket | Always there | Survives death |

## Grids
| Grid | Size (w × h cells) |
|---|---|
| Pockets (always) | 4 × 1 |
| Secure pocket | 2 × 2 |
| Backpack: small / medium / large | 4 × 3 / 5 × 4 / 6 × 5 |
| Crate / locker / safe | 4 × 3 / 4 × 4 / 3 × 3 |
| Body / dropped-item bag | 4 × 4 (4 × 3, widened/heightened to fit its biggest item, plus one spare row) |
| Stash (between raids) | 8 × 30 (scrolls) |

- A backpack's contents belong to it. v1: a backpack can only be moved/unequipped when empty
  (dropping it on the ground in a raid drops it as a lootable bag with its contents).

## Items (size w × h, stack)
| Item | Size | Stack |
|---|---|---|
| Rifle rounds | 1 × 1 | 120 |
| Pistol rounds | 1 × 1 | 50 |
| Bandage | 1 × 1 | 5 |
| Medkit | 2 × 2 | 1 |
| Rifle | 4 × 2 | 1 |
| Pistol | 2 × 1 | 1 |
| Light / heavy armor | 3 × 3 | 1 |
| Backpacks | 3 × 3 to 4 × 4 | 1 |
| Small valuables (watch, phone, chip, crystal, beans, tape) | 1 × 1 | 1 |
| Laptop / battery / scrap | 2 × 1 / 2 × 2 / 2 × 1 | 1 |
| Antique vase | 2 × 2 | 1 |
| Golden toilet | 2 × 3 | 1 |

Two ammo types (rifle, pistol). Each gun keeps the rounds loaded in it; reloading fills it from matching
stacks anywhere on you (pockets, backpack, secure pocket).

## Controls
- **Tab** opens your inventory (equipment + pockets + backpack + secure pocket). **E** on a container opens it next to yours.
- **Drag & drop** to move; **R** while dragging rotates; drop on a stack of the same item to merge.
- **Shift + click** quick-moves an item between the container and your inventory.
- **Right-click** menu: Use, Split stack, Drop.
- Mobile later: tap to pick up, tap to place.

## Death and extraction
- **Die:** lose all equipment and everything in pockets and backpack. Secure pocket survives.
- **Extract:** everything comes back to the stash (from step 3 on).
- **Free kit** only when you're broke (can't afford a pistol) and own no weapon: pistol (loaded) + 30 pistol rounds + a bandage.

## Build steps
1. **Grid core (0.3.6):** grid inventory with drag & drop, rotation, stacking; containers become grids;
   ammo as grid items and reload from inventory; placeholder icons. Weight stays on hold.
2. **Equipment (0.3.7):** primary/secondary slots + pistol + weapon switching (1/2), armor, backpacks, secure pocket,
   plus a **hotbar** (1/2 weapons, 3–6 quick items; heals auto-bind).
3. **Stash & trader (0.4.0 = M1 done):** persistent stash grid (saved in the browser), sell/buy, loadout before a raid, free kit.
