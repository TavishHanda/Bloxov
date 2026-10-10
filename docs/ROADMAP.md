# Roadmap

The plan from here, as milestones. Each one has a goal and a clear "done when".
Every milestone ends with someone other than the owner playing the build.
(Replaces the phase table in `GAME_DESIGN.md` §11; phases 0–2 there are done.)

**Where we are (2026-10-10):** 0.10.x, the **Map & Spawn update**: Old Bloxov is in as a gray box
(`docs/MAP_PLAN.md`), with player spawns in progress (0.10.3). M1-M3 are done (multiplayer co-op + PvP is live).
Art is paused: cover props (cars, square props) are built; buildings wait until the layout is proven in play.

### Up next, in order
1. **Finish 0.10 (Map & Spawn):** ship 0.10.3 (player spawns), then a playtest on the big map. Still untested live:
   extracting one at a time, the downed timer running out, squads spawning together, the 0.10.1 places
   (hunting stands, bell tower, junkyard, bunker, vault), AI on the big map. Layout fixes from that playtest close 0.10.
2. **Code cleanup (0.11):** a pass over the code before the next big systems (owner, 0.10.0). No gameplay changes.
3. **Scavs 2.0:** AI spawn spots per area, scavs roaming their area, Raiders at hot spots, the close-range
   "walks into you" bug, spawn budget retuned for the real raid.
4. **Items update:** keys (bunker, bank vault), loot by place (`MAP_PLAN.md` table), item descriptions.
5. **Then (M4, vertical slice):** building models fitted to the proven layout, guns as separate models
   (`GunSocket`), real sounds, loading screen. After that M5 content (characters with perks, more traders,
   more maps) and the M6 public release.
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
per-player extract, spectate; paused at 0.9.5) · **0.10 Map & Spawn** (Old Bloxov) · next: 0.11 cleanup,
then Scavs 2.0 and Items as their own phases.

## Rules while we go
- **Co-op-friendly code, even before M3.** Don't add new "there is exactly one player" assumptions.
  Existing ones to fix in the spike: scavs target the first node in the `player` group; HUD, loot screen and
  Raid are each bound to one player; extracting ends the raid for everyone.
- **One area at a time.** Owner-driven reviews of each mechanic (movement done in 0.3.1–0.3.2).
- Notes and parked ideas live in `docs/BACKLOG.md`.
