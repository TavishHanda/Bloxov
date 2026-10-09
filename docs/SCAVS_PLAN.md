# Scavs update (0.6.x)

Goal: scavs (and PMCs) are good fight partners for the guns we just tuned. They notice you believably, don't
know things they shouldn't, use the map instead of standing in the open, and react to getting hurt.
Same process as guns: one step at a time, the owner plays it, we tune, then the next step.
Not in scope: spawns (with the map), new enemy types (content), bosses.

## How scavs work today (0.5.9)
- States: wander, alert (turns to you), engage (strafe + burst fire, or walk straight at you if no shot), give up.
- **Sight:** 40 m, 120° cone while unaware (0.5.7), any direction once alerted. **Hearing** (shots, footsteps,
  knife, searching) alerts them instantly.
- **Problems:** once alerted they always know exactly where you are, even through walls; they walk straight at
  you (into walls, into *you*: the owner's bug); no cover; they never retreat or call others for help.
- The map has no navigation data (39 boxes), so scavs can't path around buildings.

## Steps
Versions: every scav update is the next 0.6.x (tuning updates included), in order.
- [x] **1. Senses (0.6.0).** Separate "alerted" from "knows where you are".
      Seeing you = knows your position. Hearing you = knows *roughly* where the sound came from: it walks over
      to investigate the spot instead of locking on. Lose sight of you = goes to where it last saw you, searches
      for a bit, then goes back to wandering. No more tracking you through walls.
- [x] **1b. Spotting + near misses (0.6.1, owner feedback).** Scavs notice you gradually (about 0.25 s up close,
      ~1.8 s at 40 m; slower if you crouch or stand still, faster if you sprint). Lose them for a moment and they
      must re-spot you (faster). A bullet passing within 2.5 m alerts a scav even out of earshot. Idle scavs
      wander calmly (small, slow turns) so you can sneak up behind them.
- [x] **2. Close range (0.6.2). Fixes the owner's bug.** Shots are traced from the scav's chest, not the barrel tip. Scavs keep a minimum distance (about 3 m): too close and
      they back off while shooting instead of walking into you. Point-blank shots are accurate.
- [x] **2b. Melee bash (0.6.3, owner idea).** Within 1.6 m a scav winds up (0.3 s, leans back) and rifle-butts you:
      20 damage, a hard shove, aim jolt, can't aim down sights for 0.6 s; 1.5 s cooldown. PMCs: 25 dmg, faster.
- [x] **2c. Spawn budget (0.6.4, owner idea).** Per raid: 12 scavs (3 at the start, then one every 40-60 s) and
      3 PMCs (minutes 3, 5, 8). Max 5 alive; spawns away from and out of sight of players; dead ones stay dead.
      Owner will retune once the maps exist. **0.6.5 (owner): 20 scavs (one every 25-35 s) + 5 PMCs
      (minutes 2, 3.5, 5, 6.5, 8).**
- [x] **3. Getting around (0.6.6).** `scripts/nav_baker.gd` (the `Navigation` node in `main.tscn`) builds the
      walkable area at raid start from the boxes in the `nav_source` group (Level + Loot), from their sizes (no GPU
      read-back). Paths keep 0.75 m from walls (the scav's box body snagged on corners at 0.5). Scavs follow paths
      for investigating, chasing to the last-seen spot, closing in, and wandering (to reachable spots, still calm).
      Strafing/backing off checks for walls and flips side. Unreachable goals: the path ends at the closest
      reachable point and that counts as arriving. Async navigation iterations are off in `project.godot` (they
      never finished under `--fixed-fps` tests; the map is small). Not done: avoidance between scavs (later, if
      they bunch up). Test: `pathing` section (around the grocery to its door).
- [x] **3b. Patrols (0.6.7, owner feedback: idle scavs too slow, stuck near their spawn at the map edge).**
      Unaware scavs walk (~2 m/s) to destinations across the map (65% a loot spot, else any reachable point),
      pause 2-6 s, then pick the next. Patrol destinations will follow wherever the real maps put loot.
- [x] **3c. Player-like scavs (0.6.8, owner idea).** At a loot spot a scav leans in and searches the container for
      3-6 s, distracted (60% slower to notice you), but takes nothing (owner: AI keeps only what it spawned with).
      About 1 in 3 patrol legs is a jog (~3 m/s). AI PMCs don't extract (owner: real PMCs will, with multiplayer).
- [ ] **4. Cover.** In a fight, a scav looks for a nearby spot that blocks your line of sight, moves
      there, and peeks out to shoot. No more standing in the open trading shots.
- [ ] **5. Getting hurt.** Badly hurt scavs fall back to cover and (maybe) patch up for a few seconds.
- [ ] **6. Teamwork.** A scav that spots you alerts scavs near it (they come to investigate).
      Maybe: one holds you in place while another moves to flank.
- [ ] **7. PMCs vs scavs.** Give PMCs their own identity: faster reactions, better aim, more likely to
      push and flank. Scavs stay sloppier.
- [ ] **8. Co-op prep (throughout).** Every step picks targets from all players (closest/last seen/last
      attacker), never "the first player", so the AI doesn't need a rewrite for co-op.

## Owner decisions (answered)
- Difficulty: a lone scav is a **speed bump**; groups are dangerous.
- Hearing: **short range** (shooting shouldn't pull the whole map to you). Gunshots heard at AK 25 m, pistol 18 m.
- Scavs and PMCs **don't fight each other**.
- Hurt scavs **can heal**.
- View cone while unaware: **180°** (0.6.0).

## Original questions
1. **Difficulty target.** Should a lone scav be a speed bump (you usually win 1v1 if you're careful) or a real
   threat? Suggested: speed bump alone, dangerous in groups or when they catch you in the open.
2. **Investigating.** When a scav hears a shot far away, should it come investigate (raids get busier the more
   you shoot, which supports "fight or avoid") or only react to noise nearby?
3. **Scavs vs PMCs.** Should scavs and PMCs fight each other (Tarkov-style: gunfire you didn't cause, a chance to
   third-party)? Or are they all on the same side?
4. **Healing.** Should hurt scavs heal (fights last longer, you can push a wounded one), or just retreat?

## Mobile / co-op notes
AI runs on whoever hosts the raid later, so keep it free of player-input or camera assumptions (it already is).
