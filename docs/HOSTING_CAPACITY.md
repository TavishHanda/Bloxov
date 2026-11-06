# Hosting capacity and cheaper alternatives

**Status:** planning note, measured 2026-11-06. No code changed, nothing migrated.
**Read with:** `docs/DEV_HANDOFF.md` §5 (current hosting), `docs/STASH_UPDATE_PLAN.md` §5 (the API and database this
will eventually host).

This note exists because the Stash update adds a database and an API to the same dyno, so the hosting bill and the
server's real capacity both matter. It records what the server actually uses, what the current caps mean, and what
the same money buys elsewhere.

---

## 1. What the server actually uses

Each online raid loads its own full copy of the map (`RaidWorld`, `scripts/raid_world.gd`) with navigation, the
spawner and AI. That is the cost driver, not the player count: a player in the hideout is nearly free, a raid is not.

Measured by loading real `RaidWorld` scenes headless and sampling process memory (`Performance.MEMORY_STATIC` and
the OS working set), empty vs. a 120-second raid with six player proxies and spawned scavs:

| Raid worlds | Empty map (RSS) | Live raid (RSS) |
| --- | --- | --- |
| 0 (extrapolated) | ~308 MB | — |
| 1 | 383 MB | 384 MB |
| 4 | 609 MB | 614 MB |
| 8 | 911 MB | 922 MB |

Scavs and player proxies add only ~1–2 MB per raid. The map copy is almost all of it. The ~308 MB base is the
engine plus the map assets the first raid loads (static memory with no world is only ~61 MB); every raid after the
first costs ~77 MB on top.

**Rule of thumb:** `RSS ≈ 307 MB + 77 MB × active raids`.

**Where one raid's memory goes** (measured 2026-11-06 on Linux, Godot static memory, 1 vs 3 raid worlds; ~67 MB a
raid before 0.30.6):

| Part | Per raid | Notes |
| --- | --- | --- |
| Map collision triangle list (`BoxMap.collision_faces`) | ~10 MB | **Shared since 0.30.6** |
| Other map collision (2,200 box shapes for props, bars, bushes, windows) + level nodes | ~16 MB | |
| AI navigation map (NavigationServer, from the shared baked mesh) | ~17 MB | |
| AI bodies (spawned scavs/raiders with their models) | ~12 MB | |
| Doors, loot | ~7 MB | |

**Done in 0.30.9: the server runs a stripped pack.** Godot's "Dedicated Server" export (preset "Server",
*Strip Visuals*: meshes become `PlaceholderMesh` with their bounds, textures and materials placeholders); the
Dockerfile exports it and runs `godot --headless --main-pack bloxov_server.pck -- --server`. Measured on Linux
(RSS, six players and two minutes of AI per raid):

| Raids | Project folder (before) | Stripped pack |
| --- | --- | --- |
| 0 (idle server) | 202 MB | 167 MB |
| 1 | 399 MB | 236 MB |
| 3 | 549 MB | 376 MB |
| 4 | — | ~440 MB |
| 6 | 767 MB | 572 MB |

New rule of thumb on the stripped pack: `RSS ≈ 170 MB + 67 MB × active raids`, so 512 MB fits 4 raids. CI runs
`tools/server_pack_check.gd` (four busy raids inside the pack) before every deploy. Server code must not need a real
mesh, texture or material: `get_aabb()` works, `surface_get_arrays()` and friends find no surfaces.

That puts these ceilings on the current build:

| RAM | Raids that fit |
| --- | --- |
| 512 MB | **2** (461 MB; a 3rd is ~538 MB and over) |
| 1 GB | ~9 |
| 2.5 GB | ~29 |
| 4 GB | ~49 |
| 8 GB | ~100 (RAM-wise; CPU becomes the limit first) |

**Caveats:** measured on Windows headless with Godot 4.7.2. Linux (Heroku, a VPS) will differ somewhat, so treat
these as order-of-magnitude, not exact. The engine baseline (~307 MB) is included. Beyond RAM, the Godot server's
main loop is single-threaded, so one process only uses one core well; big boxes need several processes, not one
bigger one.

---

## 2. What the current caps mean

The caps are constants, not measurements:

| What | Constant | Value |
| --- | --- | --- |
| Players online at once | `MAX_ONLINE` (`scripts/net.gd`) | 40 |
| Raid lobbies at once | `MAX_RAIDS` (`scripts/matchmaker.gd`) | 4 (2 in 0.30.5-0.30.8) |
| Players per raid | `MAX_PLAYERS` (`scripts/matchmaker.gd`) | 6 |
| Party size | `MAX_PARTY` (`scripts/matchmaker.gd`) | 2 |

So the ceiling is 4 lobbies × 6 = 24 raiding, 40 online total.

**The real ceiling on a 512 MB Basic dyno is ~2 raids (~12 raiding, ~20 online).** Four simultaneous raids would
exceed the dyno's memory and Heroku would log `R14` (memory quota exceeded) then `R15` (dyno killed). If that has
never happened, it is because four raids have never overlapped in testing, not because it fits.

**Done:** 0.30.5 set `MAX_RAIDS = 2`; 0.30.9 moved the server to the stripped pack (below) and set it back to 4
(~440 MB measured). Raise it only after moving to a box with more RAM.

---

## 3. Heroku pricing vs. the alternatives

Prices checked 2026-11-06, USD unless noted. They change; recheck before buying.

### Heroku

| Plan | RAM | Price |
| --- | --- | --- |
| Basic (always on) | 512 MB | $7/mo |
| Standard-2X | 1 GB | $50/mo |
| Performance-M | 2.5 GB | $250/mo |
| Postgres Essential-0 | 1 GB, 20 connections | $5/mo |
| Postgres Essential-1 | 10 GB, 20 connections | $9/mo |

Basic + Essential-0 = **$12/mo** (about 25 months on a $300 balance, or 24 months if the credit is the
$13/month-for-24-months student kind). Standard-2X + Essential-1 = **$59/mo** for 1 GB.

### VPS / containers

| Provider / plan | RAM | vCPU | Price | Notes |
| --- | --- | --- | --- | --- |
| Contabo Cloud VPS 4 | 8 GB | 4 | ~$5.30–6.60 | Best RAM per dollar; 24-month term is cheapest; slower support |
| Hetzner CX23 | 4 GB | 2 | ~$7.10 (€5.99) | Reliable, hourly billing; **CX line is EU-only** |
| Hetzner CX33 | 8 GB | 4 | ~$10.60 (€8.99) | Same caveat |
| Hostinger KVM 2 | 8 GB | 2 | ~$7 on a 2-year term | Renews higher (~$15) |
| RackNerd 8 GB | 8 GB | 7 | ~$10 on a 1-year term | US |
| DigitalOcean / Linode / Vultr 4 GB | 4 GB | 2 | ~$24 | Simplest docs; many regions |
| Oracle Cloud Always Free | 24 GB (ARM) | 4 | $0 | Can be reclaimed; ARM build needed; capacity is hit or miss |

The point: **$50 on Heroku buys 1 GB; ~$6 on Contabo buys 8 GB.** Heroku's Standard tier is poor value for a
single always-on container.

---

## 4. Recommendation

1. **Stay on Heroku for now.** It works, costs $12, and the credit covers it. Do not migrate just to save $6.
2. **Migrate when the Stash update lands**, because that is when Postgres and the companion API appear anyway. One
   move instead of two.
3. **Pick by region and term, not specs.** Any of the options above holds 40 players easily. Put the server near
   the players. Contabo is cheapest; Hetzner is the best balance; DigitalOcean/Vultr have the widest region list.
4. **Run everything on one box:** Caddy (auto-TLS, `wss://`), the Godot server container (the existing
   `Dockerfile` already works on Fly.io), the Stash API, and Postgres. That removes the $5 database and the network
   hop to it. Add a nightly `pg_dump` to cheap object storage.
5. **Do not scale by buying a bigger Heroku dyno.** Above one process the answer is several server processes on one
   VPS (each owning a few raids) plus a small router, not a $250 dyno.

### Migration sketch (when the time comes)

```
Caddy (443, auto-TLS)
  ├── Godot server container   (--server, wss)
  ├── Stash API container      (127.0.0.1 only)
  └── Postgres container       (volume + nightly pg_dump)
```

- CI: build the image, push to GHCR, deploy over SSH (or Watchtower), keep the version match between web and server.
- Backups: `pg_dump` on a cron to object storage; test a restore once.
- Kill switch: stop the compose stack, same as turning the dyno off.

---

## 5. How to re-measure

The numbers above came from a temporary headless probe. To reproduce, run a script like this with
`godot --headless --script <probe> -- <raids> [empty|live]`, where `live` also adds six proxies per world and ticks
the spawner for 120 s:

```gdscript
extends SceneTree

var _n := 4
var _worlds: Array = []
var _base := 0
var _frame := 0
var _mode := "empty"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_n = int(args[0])
	if args.size() > 1:
		_mode = args[1]
	_base = Performance.get_monitor(Performance.MEMORY_STATIC)
	for i in _n:
		var w := RaidWorld.new()
		root.add_child(w)
		_worlds.append(w)

func _setup_live() -> void:
	for w: RaidWorld in _worlds:
		if w.raid == null:
			continue
		for p in 6:
			w.update_proxy(p + 1, [Vector3(randf() * 20.0, 0.0, randf() * 20.0), 0.0, 0.0, 0.0, 0])
		var spawner: Node = w.raid.get_node_or_null("EnemySpawner")
		if spawner != null:
			for t in 120:
				spawner.tick(1.0)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2 and _mode == "live":
		_setup_live()
	if _frame < 30:
		return false
	var after := Performance.get_monitor(Performance.MEMORY_STATIC)
	print("worlds=%d mode=%s static_delta_mb=%.1f static_total_mb=%.1f" % [
		_n, _mode, (after - _base) / 1048576.0, after / 1048576.0])
	return true
```

Sample the process working set from the OS while it runs (that is the number a dyno limit enforces), and compare
1 / 4 / 8 worlds. The slope is the per-raid cost.

---

## 6. Sources

- Heroku pricing page (dynos, Postgres Essential): checked 2026-11-06.
- Hetzner cloud pricing (CX23/CX33, after the 2026 increases): checked 2026-11-06.
- Contabo pricing (Cloud VPS 4): checked 2026-11-06.
- Hostinger, RackNerd, DigitalOcean, Linode, Vultr, Oracle Always Free: checked 2026-11-06.
- Capacity numbers: measured locally, see §1 and §5.
