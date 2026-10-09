# Multiplayer update (0.7.x, roadmap M3)

Goal: real players in the same raid, as squads (co-op) and against each other (PvP), with the AI.
Same process as guns and scavs: one step at a time, the owner (and friends) play it, we tune, then the next step.
This is the roadmap's "multiplayer spike", but built so the parts that work are kept (see "Approach").

## How it would work (recommended)
- **Browsers can't host.** A web game can't open a server or accept connections; it can only connect out.
  So every raid runs on a **dedicated server**: the same Godot project, started headless with `--server`,
  on a small rented machine. Players connect to it from the web link over a secure WebSocket (`wss://`).
- **The server owns the game.** It runs the AI, the loot, health and hits. Players send their inputs
  ("I moved here, I shot in this direction") and the server decides what happened. This is what makes PvP
  fair: a player can't edit their own health, ammo or the loot in a crate.
- **Godot's built-in multiplayer** (`WebSocketMultiplayerPeer`, RPCs, `MultiplayerSpawner`,
  `MultiplayerSynchronizer`): no extra libraries, works in the web export.
- **Solo stays offline.** A solo raid runs the server inside your own game (no network), so there is one code
  path and solo can't drift out of date. Solo keeps working at every step; the smoke test keeps checking it.
- **The stash stays in the browser for now** (`user://profile.json`), so the loadout you bring is trusted.
  Fine with friends; before strangers play PvP, the stash moves onto the server with accounts (later, M5/M6).

## What has to change in today's code (~5,300 lines)
- **Player**: split "this is me" (camera, input, HUD) from "a player in the raid" (body, health, gun).
  Other players are the same scene without camera/input, moved by the server.
- **Shooting**: the gun asks the server to fire; the server traces the shot and applies damage.
  Your own gun still shows the shot instantly (muzzle flash, recoil, sound) so it doesn't feel laggy.
- **Scavs/Raiders**: run only on the server; players get their position, facing, state and shots.
  They already pick targets from every player (scav step 8), mostly.
- **Loot**: containers and bodies live on the server; taking/moving an item is a request it approves.
- **Raid**: extracting or dying ends the raid **for you**, not everyone. `raid.gd`, the HUD and the end
  screen are bound to one player today (see ROADMAP rules).

## Steps (each one playable/testable before the next)
- [ ] **1. Connect (0.7.0).** Server mode (`--server`), a "Join" box in the hideout (server address + room
      code), players spawn in the same raid. Tested locally: the smoke test starts a server and two clients
      in one process. No visible gameplay change for solo.
- [ ] **2. See each other (0.7.1).** Other players move, turn, crouch, lean, aim, with smoothing so they don't
      jitter. The PMC model is the player model (owner: kept for real players).
- [ ] **3. Shoot each other and scavs (0.7.2).** Server-side hits and damage; hit feedback and kill sound
      as now. Friendly fire per the owner's answer below.
- [ ] **4. AI on the server (0.7.3).** Scavs/Raiders run on the server and react to every player.
- [ ] **5. Loot and bodies (0.7.4).** Shared containers (one person takes an item, it's gone for everyone),
      player bodies you can loot (PvP).
- [ ] **6. Raid flow (0.7.5).** Per-player extract and death, squads spawn together, raid ends when everyone is
      out. What a dead squadmate sees (spectate their squad or go back to the hideout).
- [ ] **7. Online test (0.7.6).** Server deployed to a host, friends play over the internet.
      Measure lag and bandwidth. **Decision point:** keep going (lag compensation for PvP hits,
      matchmaking, accounts) or adjust the approach.
- Later (after the test): lag compensation (the server checks hits against where the target *was* on your
  screen), matchmaking/server list, accounts and a server-side stash, anti-cheat basics.

## Owner decisions (questions)
1. **Hosting (needs you).** A server costs about $5/month (Hetzner, Fly.io, Railway). You'd make the account;
   I set up everything else. Not needed until step 7: steps 1-6 are tested here.
2. **Raid size.** Squad size (suggested up to 3) and players per raid (suggested 6 to start).
3. **Friendly fire** on or off? (Suggested: on, like Tarkov; teammates show a name tag so you can tell.)
4. **Death in a squad:** straight death (as now), or downed and revivable by a teammate for a few seconds?
5. **Joining:** room code you share with friends (suggested for now), or quick match into any raid?
6. **Stash trust:** OK to keep the stash in the browser until accounts exist (cheatable, but only by people
   you give the link to)?
