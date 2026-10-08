# Guns update (0.5.x)

Goal: shooting feels good and every gun has its own identity. Same process as movement:
one change at a time, the owner plays it, we tune, then move to the next step.
Stats live in `scripts/item_db.gd` (weapon entries), so tuning is mostly editing numbers there.

## Steps
- [x] **1. Aim down sights (0.5.0).** Hold right mouse. Gun moves to the center of the screen, camera zooms,
      shots get much tighter, you move slower and can't sprint. Hip fire gets looser, so aiming matters.
      Per-gun: `ads_time`, `ads_fov`, `spread` (aimed), `hip_spread` (extra when not aimed).
- [x] **1b. Accuracy targets (0.5.1)**, from the owner. Measured on a scav's chest (0.5 m) at 20 m,
      shots land evenly inside the spread circle (checked by the smoke test):
      hip standing ~75%, hip crouched ~90%, hip walking ~20%; aimed standing/crouched 100%, aimed walking ~90%.
      Spraying adds bloom (much less while aimed). **Getting shot flinches** your aim and loosens your next shots.
- [x] **2. Recoil you can control (0.5.1, tune by playing).** A learnable pattern (mostly up, a little sideways drift) that you pull
      down against, instead of random kick. Recoil should stay where it lands while you hold fire and
      settle back when you stop.
- [ ] **3. Hit feedback.** Scavs flinch when hit, clear hit/kill/headshot markers and sounds,
      blood/impact readability.
- [ ] **4. Time to kill (decision with the owner).** How many hits a scav takes and how many you take.
      Sets the tone of the game (fast and deadly vs. arcade). Then tune damage/health to match.
- [ ] **5. Reloads.** Tactical vs. empty reload (empty is slower), maybe a round kept in the chamber.
- [ ] **6. Gun identity.** Pistol plays differently from the AK (fast to aim, good hip fire, weak at range).
      Only after this: more guns.
- [ ] **7. Knife / melee (owner idea).** Everyone always has a knife (can't be lost or sold).
      Quick melee on a key (V) with any gun out, for point-blank fights and saving ammo.
      No separate "unarmed" mode for now: holstering has no gameplay reason yet.
- [ ] **8. Code cleanup (no gameplay changes).** Once the gun code stops changing: a code review pass for real bugs,
      then a simplify pass (gun.gd, player.gd, and loot_ui.gd, which grew a lot during the inventory work).
      Tests must pass unchanged before and after, so nothing the owner likes gets broken.

## Mobile notes
Every new action is an input action (`aim`, `shoot`, ...), so touch buttons can trigger them later.
Aim will need a toggle mode for touch (hold is awkward on a phone): plan a "hold / toggle" setting.
