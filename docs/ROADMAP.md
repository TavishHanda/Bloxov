# Roadmap

The plan from here, as milestones. Each one has a goal and a clear "done when".
Every milestone ends with someone other than the owner playing the build.
(Replaces the phase table in `GAME_DESIGN.md` §11; phases 0–2 there are done.)

**Where we are:** 0.5.7. M1's build is complete: hideout, stash, trader, persistent loadout, death rules.
Friends have played it and liked it. Now honing core mechanics one at a time (movement done, looting OK for now):
the **guns update** is done through the knife (0.5.x, see `docs/GUNS_PLAN.md`); a code cleanup is in progress.
Next phase: **scavs** (0.6).

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
**0.8 HUD & inventory** (owner's designer session; started as 0.7.12-0.7.15, renumbered to 0.8.0-0.8.3) ·
next: the rest of multiplayer (raid flow: downed/revive, per-player extract) once 0.8 closes.

## Rules while we go
- **Co-op-friendly code, even before M3.** Don't add new "there is exactly one player" assumptions.
  Existing ones to fix in the spike: scavs target the first node in the `player` group; HUD, loot screen and
  Raid are each bound to one player; extracting ends the raid for everyone.
- **One area at a time.** Owner-driven reviews of each mechanic (movement done in 0.3.1–0.3.2).
- Notes and parked ideas live in `docs/BACKLOG.md`.
