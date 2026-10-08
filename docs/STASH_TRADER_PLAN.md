# Stash & Trader (0.4.0 = M1 done)

Inventory redesign step 3. Goal: loot carries between raids, so there's a reason to go again.
Prototype quality: it needs to work, not be pretty. Status: **all steps done, shipped in 0.4.0.** Next: play it (M1 "done when"), then M2 playtest.

## How it plays
1. The game opens in the **Hideout**: stash (left), your loadout (equipment, pockets, secure pocket, backpack), trader (right).
2. Drag gear between stash and loadout, buy what you need, then **START RAID**.
3. **Extract:** you come back with everything you carried (it stays on you; move it to the stash in the hideout).
4. **Die / MIA:** your loadout is gone, **except the secure pocket**.
5. Sell loot to the trader for money, buy gear, go again.
6. Broke and unarmed? **Free kit** (pistol, 30 rounds, bandage), only when you own no weapon and can't afford one
   (cheaper to reason about than a once-per-death flag, and it can't be farmed for real money).

## Numbers (first guesses)
| Thing | Value |
|---|---|
| New profile | $3,000, loadout = AK (loaded) + medium backpack + 60 rifle rounds + bandage |
| Stash | 8 × 30 grid (scrolls), grows if it ever overflows |
| Sell price | valuables 100% of value, everything else 60% |
| Buy price | 120% of value |
| Trader stock | AK, pistol, rifle rounds ×60, pistol rounds ×50, bandage, medkit, light armor, small & medium backpack |
| Loot-only | heavy armor, large backpack, all valuables |

## Saving
- Everything lives in `user://profile.json` (browser storage on web): money, stash, loadout, stats.
- Saved when you start a raid, when a raid ends, and after hideout changes (buy/sell/move).
- When a raid starts, the saved loadout is already the "died" version (secure pocket only); extracting overwrites it.
  So closing the tab mid-raid counts as dying.

## Build steps
- [x] 1. **Plan** (this file)
- [x] 2. **Inventory screen works without a player**: takes any `Inventory`, the "other side" can be the stash,
      right-click Sell, extra trader column. In-raid behavior unchanged
- [x] 3. **Profile** (`scripts/profile.gd`): money, stash, loadout, stats; save/load JSON; serialize grids,
      equipment (incl. loaded rounds), hotbar
- [x] 4. **Raid uses the profile**: player starts with the saved loadout; extract keeps it, death keeps only the
      secure pocket; stats; end screen goes back to the hideout
- [x] 5. **Hideout scene** (new main scene): stash + loadout screen, money/stats, START RAID, free kit
- [x] 6. **Trader**: buy list, sell via right-click, prices
- [x] 7. **Tests**: profile round-trip, death/extract rules, buy/sell, free kit, hideout UI builds
- [x] 8. Changelog, item list, roadmap (M1 done), version 0.4.0
