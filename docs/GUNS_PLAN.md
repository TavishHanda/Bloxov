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
- [x] **3. Hit feedback (0.5.4), kept subtle on purpose (owner).** Scavs flinch when hit (hold fire 0.35 s,
      aim worse for 0.8 s, visible jolt), mirroring the player's flinch. No kill marker (you see the body drop);
      kill sound stays. Damage numbers off by default, toggle in the Esc menu.
- [x] **4. Time to kill (0.5.3): "lethal-leaning middle", owner's pick.** Everyone has 100 HP.
      AK 28 dmg (scav: 4 body / 2 head), headshots x2; pistol 17 (6 body / 3 head at x2.5, 0.5.6: weak sidearm that rewards precision). 0.5.5: owner said the AK killed too fast. Scav hits 15 (you die in 7;
      9 with light armor, 12 heavy), PMC hits 18 (6) and wears armor (takes 80%: 5 AK body shots).
      Scavs aim worse so danger = getting caught in the open. Checked in the smoke test.
- **Parked (later, with more guns):** reload variations (tactical vs. empty, round in the chamber) and more
      gun identity (pistol is already quicker to aim with better hip fire). They barely change fights yet.
- [x] **7. Knife / melee (0.5.6, owner idea).** 45 damage from the front, backstab kills in one hit. Everyone always has a knife (can't be lost or sold).
      Quick melee on a key (V) with any gun out, for point-blank fights and saving ammo.
      No separate "unarmed" mode for now: holstering has no gameplay reason yet.
- [ ] **8. Code cleanup (no gameplay changes).** Once the gun code stops changing: a code review pass for real bugs,
      then a simplify pass (gun.gd, player.gd, and loot_ui.gd, which grew a lot during the inventory work).
      Tests must pass unchanged before and after, so nothing the owner likes gets broken.

## Mobile notes
Every new action is an input action (`aim`, `shoot`, ...), so touch buttons can trigger them later.
Aim will need a toggle mode for touch (hold is awkward on a phone): plan a "hold / toggle" setting.
