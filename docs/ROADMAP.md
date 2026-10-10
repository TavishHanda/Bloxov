# Roadmap

The plan from here, as milestones. Each one has a goal and a clear "done when".
Every milestone ends with someone other than the owner playing the build.
(Replaces the phase table in `GAME_DESIGN.md` §11; phases 0–2 there are done.)

**Where we are (2026-10-10):** 0.10.x, the **Map & Spawn update**: Bloxov Battlegrounds (first called Old Bloxov) is in as a gray box
(`docs/MAP_PLAN.md`), with player spawns and per-squad extracts (0.10.3). The code cleanup (0.11.0) is done; map follow-ups shipped as 0.11.x.
Next: Scavs 2.0. M1-M3 are done (multiplayer co-op + PvP is live).
Art is paused: cover props (cars, square props) are built; buildings wait until the layout is proven in play.

### Up next, in order
1. **Playtest the big map** (0.10 Map & Spawn, done through 0.10.3). Still untested live:
   extracting one at a time, the downed timer running out, squads spawning together, the 0.10.1 places
   (hunting stands, bell tower, junkyard, bunker, vault), AI on the big map. Layout fixes from it ship as 0.11.x.
2. ~~**Code cleanup (0.11):**~~ done in 0.11.0.
3. **Scavs 2.0 (0.12, in progress):** 0.12.0 AI zones + hot zones + fewer AI (done), 0.12.1 sniper scavs on high perches
   (scope glint + their own shot sound, done), 0.12.2 the town hall boss + 3 guards (every raid while testing, a
   chance later; done), 0.12.3 smarter fights (calling for help, cover at range, pushing while you reload/heal,
   scavs flank too, shorter idle pauses; done). Then: owner playtest and tuning, the close-range "walks into you" bug.
4. **Movement update (owner, 2026-10-10; small):** mainly **vaulting**: vault or mantle over low cover (fences,
   sandbags, the trench, walls) and climb onto ledges. Candidates for the owner to pick from: ladders, fall damage
   (both parked in `BACKLOG.md`), prone, crouch-walk speed tuning. (Leaning and stamina already exist.) Right after
   Scavs 2.0, so the AI's paths can use the same vaultable cover.
5. **Items update:** keys (bunker, bank vault), loot by place (`MAP_PLAN.md` table), item descriptions.
6. **Guns update (owner, 2026-10-10):** gun categories (e.g. pistols, SMGs, rifles, shotguns, marksman), a real set
   of guns in each, attachments (sights, muzzles, grips, mags, stocks), and gun models: each gun its own model on the
   characters' `GunSocket` (see `BACKLOG.md`), owner in Blender. After the Items update, since guns, attachments and
   their loot spots build on it. Made-up gun names and looks only (`STORE_RULES.md`: no real brands or models).
7. **Sound update (owner, 2026-10-10):** a full sound pass replacing the generated placeholders
   (`tools/make_sounds.py`): a sound per gun (shot, reload, empty click, distant shot), footsteps by surface
   (grass, wood, metal, concrete), directional and distance audio you can play PvP by (where shots and steps come
   from, muffled through walls), scav and Raider voice lines, map ambience, UI sounds, and a final mix. Right after
   the Guns update, since gun sounds need the gun set.
8. **Economy update (owner, 2026-10-10):** after the Items and Guns updates, when there's a full set of things to
   price: trader buy/sell prices, what's worth looting and where, money in vs. money out (sinks), and how traders and
   their stock fit in (more traders are on the wishlist). Earned money only (`STORE_RULES.md`: no real-money trading).
9. **Then (M4, vertical slice):** building models fitted to the proven layout, loading screen, and a **lighting overhaul** (owner, 2026-10-10: today's look is too
   saturated; tune it once, against the real models and ground textures, within what the web build supports).
   After that M5 content (characters with perks, more traders,
   more maps) and the M6 public release.
- **Stash update (planned, before the store/Steam release; owner 2026-10-10: wait until closer to shipping, solo and
  online share one stash while we playtest):** solo and online get **separate stashes** (each with its own money,
  loadout and stats), picked with a SOLO / ONLINE switch in the hideout. Solo stays on the device and works
  offline with no account. The **online stash moves onto the server** so it can't be edited to cheat: the server
  owns the stash, loadout and money, checks what you take in and saves what you bring out. Needs: a player
  identity (owner chose a **device account**: made silently on the device, no email or login, a transfer code
  moves it to another device; Steam login can be linked later), a database (Heroku's disk is wiped on restart), and the store rules on accounts
  (`STORE_RULES.md` §4: delete account in-game, Sign in with Apple if other logins are offered, no forced
  account for solo). The current save becomes the solo stash.
Parked 0.9 leftovers (teammate-down alert, squad line on the end screen, rejoin after disconnect) can slot in
between updates. Lore is the owner's.

| # | Milestone | Goal | Done when |
|---|---|---|---|
| **M1** | **Complete loop** (0.4) | Inventory redesign, persistent stash, simple trader (sell loot, buy gear), pick a loadout before a raid | The owner plays 5 raids in a row because they *want* to |
| **M2** | **First playtest round** | 3–5 friends play the web link while the owner watches without explaining | A ranked list of the top problems |
| **M3** | **Multiplayer spike** | Throwaway prototype: 2 players in one raid, moving, shooting scavs, seeing each other, and able to shoot each other (owner wants **co-op and PvP**) | We know: how browsers connect (hosted server vs. WebRTC + signaling), who runs the game state (host vs. server), and roughly how much work each system takes to sync. **Decide:** how to build co-op + PvP (PvP needs a server that owns the game state, against cheating) and when |
| **M4** | **Vertical slice** | One small part of the game at near-final quality: Blender art pipeline, real sounds, polished gun feel and scav, clean UI | It looks and feels like the real game; good enough to show people |
| **M5** | **Production** | More content: map areas, guns, enemy types, events (plus real co-op if M3 said go) | Content matches the MVP list in the design doc |
| **M6** | **Release** | Public web release (itch.io), then iterate; mobile after | Strangers play it and come back |

## Version phases (middle number)
0.5 guns · 0.6 scavs · 0.7 multiplayer (0.7.0-0.7.11: connect, matchmaking, PvP, shared AI and loot) ·
0.8 HUD & inventory (owner's designer session; started as 0.7.12-0.7.15) · 0.9 raid flow (downed/revive,
per-player extract, spectate; paused at 0.9.5) · **0.10 Map & Spawn** (Bloxov Battlegrounds) · **0.11 Scorched Earth** (cleanup, war-torn map, hills) ·
then Scavs 2.0 and Items as their own phases (the Stash update waits until closer to release).

## Rules while we go
- **Co-op-friendly code, even before M3.** Don't add new "there is exactly one player" assumptions.
  Existing ones to fix in the spike: scavs target the first node in the `player` group; HUD, loot screen and
  Raid are each bound to one player; extracting ends the raid for everyone.
- **One area at a time.** Owner-driven reviews of each mechanic (movement done in 0.3.1–0.3.2).
- Notes and parked ideas live in `docs/BACKLOG.md`.
