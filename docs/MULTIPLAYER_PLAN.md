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
Versions: each update is the next 0.7.x in order (hosting moved up to 0.7.1, so later numbers shift by one).
- [x] **Hosting (0.7.1, owner: set up now so every step can be played online).** `Dockerfile` + `fly.toml`;
      CI's `server` job deploys to Fly.io (app `bloxov-server`, one machine, sleeps when empty) after the tests
      pass, once the `FLY_API_TOKEN` repo secret exists. Clients default to `wss://bloxov-server.fly.dev`.
- [x] **1. Connect (0.7.0).** Server mode (`--server`, `scripts/net.gd` = the `Net` autoload, used as
      `Network.main`), a "JOIN ONLINE" box in the hideout (server address + room code), players land in the same
      raid and see each other (`RemotePlayer`, moved by `NetRaid`). The server checks version, code and player
      count, runs the raid clock and seeds the open extracts. One room per server process for now. Online raids
      have no AI and per-player loot until steps 4-5. Tested: the `net` smoke test section runs a real WebSocket
      server and two clients in one process (separate multiplayer branches); also checked with three separate
      processes (server + two games joining through the hideout).
- [x] **2. See each other (0.7.1).** Other players move, turn, crouch, lean, aim, with smoothing so they don't
      jitter. The PMC model is the player model (owner: kept for real players).
- [x] **Matchmaking (0.7.3, owner; moved before shooting because server-side hits need the server to load
      raid worlds, the same piece as running several raids).** `scripts/matchmaker.gd` (pure logic, tested
      directly): party codes (duos max, party kept between raids), one queue for solos and duos, countdown 30 s
      once 2 are waiting, raids of 2-6 (full = start now, parties never split), no late joining, "Start now" for
      one party (testing), up to 4 raids per server. Teammates get a name tag. START RAID stays the solo raid
      against the AI (owner: keep solo in the final game too; later it can run on the server so its loot counts).
- [x] **3. Shoot each other (0.7.7).** `RaidWorld` (one map copy per raid on the server, its own physics world),
      `Hitbox` (shared box math), position history + rewind to the shooter's view time (max 0.5 s). Victims
      apply hits to their own health (armor), so health isn't server-owned yet (fine with friends; moves to the
      server with accounts). Scavs come with step 4.
- [ ] ~~3. Shoot each other and scavs (0.7.2).** Server-side hits and damage; hit feedback and kill sound
      as now. Friendly fire per the owner's answer below.
- [x] **4. AI on the server (0.7.8).** `RaidWorld` keeps Navigation + EnemySpawner; every player has a proxy body
      (`player.tscn` with `proxy = true`, moved by their states, makes footstep noise) the AI targets; what scavs do
      to proxies is forwarded (`_hit`, `_bashed`). Clients show puppets (`Scav.puppet`, `net_push`, seeded outfits)
      and events (fired/alerted/bash/died). Groups are per raid via `RaidScope`. Server knife checks too.
- [ ] ~~4. AI on the server (0.7.3).** Scavs/Raiders run on the server and react to every player.
- [x] **5. Loot and bodies (0.7.9).** Contents live on the server (`RaidWorld.container`, ids = node names, bags
      `BagN`); one player at a time holds a container open (lock), their changes are sent as the whole grid
      (`GridInventory.to_data`), released on close/walk-away/leave. Bags from scav deaths, dropped items
      (`_drop_items`) and dead players' bodies are announced to the raid. Items are checked against ItemDB.
- [ ] ~~5. Loot and bodies (0.7.4).** Shared containers (one person takes an item, it's gone for everyone),
      player bodies you can loot (PvP).
- [ ] **6. Raid flow (0.7.5).** Per-player extract and death, squads spawn together, raid ends when everyone is
      out. What a dead squadmate sees (spectate their squad or go back to the hideout).
- [ ] **7. Online test (0.7.6).** Server deployed to a host, friends play over the internet.
      Measure lag and bandwidth. **Decision point:** keep going (lag compensation for PvP hits,
      matchmaking, accounts) or adjust the approach.
- **Public queue (owner wants it, before going public).** Press "Queue" alone or with your duo; a small
  matchmaker groups waiting players into raids of up to 6 and starts a fresh raid server for each match (Fly
  Machines, one process per raid), then sends everyone its address + a match code. Today's pieces carry over:
  the room code becomes the match code, the server's join checks stay. Room codes stay for playing with friends.
- Later (after the test): lag compensation (the server checks hits against where the target *was* on your
  screen), matchmaking/server list, accounts and a server-side stash, anti-cheat basics.

## Owner decisions (answered)
1. **Hosting:** OK, ~$5/month; owner makes the account at step 7.
2. **Raid size:** squads of **up to 2 (duos)**, **up to 6 players** per raid.
3. **Friendly fire: ON.** Teammates get a name tag.
4. **Squad death: downed.** A downed player can be revived by their teammate for a few seconds (numbers proposed
   to the owner at step 6), otherwise they die.
5. **Joining: room code** for now.
6. **Stash in the browser for now: OK.** Later (before strangers play PvP): accounts + the stash in a database the
   game server reads and writes (players never write it directly). Suggested: Supabase (free tier, gives logins
   like Google/Discord and a database), or SQLite on the game server itself. Decide at that point.
