# Stash update (0.31): plan

Status: **plan only, not built.** Written 2026-11-04 for the owner, after the Sound 2.0 work closed. This file is the
reference for the biggest update Bloxov has had: **PvE and PvP game modes, the current stash becoming the solo stash,
and a new online stash kept in the Heroku database.**

Read first: `CLAUDE.md` (rules), `docs/DEV_HANDOFF.md` §3 code map and §5 hosting, `docs/CLAUDE_HANDOFF.md` (how the
owner works), `docs/STORE_RULES.md` §3-4 (privacy and accounts), `docs/MULTIPLAYER_PLAN.md` (how online got here).

Nothing here is a decision the owner has made unless it says so. Items marked **Owner decision** are already settled;
items marked **Proposed** are my recommendation; items in §15 marked still open need an answer before building.

**Decisions recorded 2026-11-04** (the owner answered the first round):
- **PvE is offline solo now; online co-op PvE is a later option.** Add the `mode` field now so it can come later.
- **PvP keeps the AI** (PvPvE, as today).
- **PvP starts with its own separate starter kit**, not the solo one. The contents are proposed in §4.6 and need a
  final yes on the numbers.
- **Economy is per-stash; look and tutorial are account-wide.** Money, stash, loadout, stats, traders, quests, levels
  and presets are separate; the character look and the tutorial are shared.
- **Explained, waiting on a yes:** credentials can be **linked** (device + Steam later), but only **one active session
  at a time**. The transfer code moves a device credential; Steam linking is the browser ↔ Steam path. §8.6 explains
  what this means for a browser player moving to Steam.

---

## 1. The owner's brief, in their words

> "At its core I want a PvE and PvP game mode. The current stash everyone has that has been playtesting will be the
> single-player stash, and the new stash should be the Heroku database we connect for the PvP online stash. But that's
> kind of the extent I know of what I want."

That is enough to start. It means:

- **PvE** is the game as it plays today: solo, offline, against the AI, with the stash you already have.
- **PvP** is online: other players and the AI, with a **different** stash that lives on the server.
- The **current stash is not deleted, moved or reset.** It becomes the PvE stash. Existing playtesters keep everything.
- The **online stash is new.** It starts fresh with its own PvP starter kit (§4.6), and it is stored in Heroku
  Postgres, not in the browser.
- The update is big enough that it needs a plan before code: accounts, a database, a companion API, server-owned
  money/items, migration, anti-cheat and store-privacy work all land together.

The rest of this file fills in the decisions the brief leaves open.

---

## 2. What exists today (the honest starting point)

Bloxov is one Godot project with two run modes: the normal game (title → hideout → raid) and the same project started
with `--server` for online. There is **one profile, one stash, no accounts and no database.**

| Thing | Today | Where |
| --- | --- | --- |
| Profile | one JSON at `user://profile.json`; on web also `localStorage["bloxov_profile"]` | `scripts/profile.gd` |
| Stash | a `GridInventory`, 8 x 20 to 8 x 50 (upgrades bought) | `scripts/profile.gd` (`STASH_SIZE`, `STASH_ROWS`) |
| Loadout | a serialized dictionary; `raid_begun()` marks it dead before the raid starts | `scripts/profile.gd:313` |
| Money and stats | in the profile (`START_MONEY = 65000`) | `scripts/profile.gd` |
| Traders and quests | in the profile (`trader_spent`, `trader_levels`, `quests_done`, `quest_progress`) | `scripts/profile.gd`, `traders.gd`, `quests.gd` |
| Look | in the profile (`Profile.look`) | `scripts/operators.gd` |
| Tutorial | in the profile (`Profile.tutorial`) | `scripts/tutorial.gd` |
| Solo raid | `START RAID`, offline vs AI, the profile is the stash | `scripts/hideout.gd:704`, `scripts/raid.gd` |
| Online raid | `ONLINE`, PvPvE, server checks shots/moves/health/extracts | `scripts/net.gd`, `scripts/matchmaker.gd`, `scripts/net_raid.gd` |
| Server identity | peer id + a typed name; no account, no token, no resume | `scripts/net.gd:258` (`_hello`) |
| Server storage | in memory only; nothing survives a restart | `scripts/net.gd`, `scripts/matchmaker.gd` |
| Database | none | `Dockerfile`, `heroku.yml` |
| Save backup | whole profile + settings as one file; restore replaces everything | `scripts/save_backup.gd:56` |
| Anti-cheat | rate limits, movement/health/extract checks, strikes, kicks; **no bans** | `scripts/net_guard.gd:15` |
| Hosting | Heroku app `bloxov-server`, one Basic dyno, ephemeral disk | `.github/workflows/web.yml`, `heroku.yml` |

### The four facts that shape the whole plan

1. **`Profile` is static and global.** Every hideout and raid script reads `Profile.money`, `Profile.stash`,
   `Profile.loadout` directly. Adding a second profile is a real refactor, not a flag.
2. **`Profile.VERSION` is 1, and an unknown version is backed up to `user://profile.bad.json` and reset.** Any change
   to the save format needs a migration branch *before* the version number changes, or playtesters lose everything.
3. **The server already trusts the client for the stash and the kit.** `_kit` takes the client's list of carried
   items "still on trust: the stash lives in their browser until the Stash update" (`scripts/net.gd:698`). The client
   also writes its own raid result and rewards (`scripts/raid.gd:190-198`). Moving the stash to the server means
   closing both holes.
4. **Heroku's disk is ephemeral.** The dyno restarts daily and on every deploy. A file on the dyno is not storage;
   the database has to be Heroku Postgres.

---

## 3. The shape of the update at a glance

### 3.1 Modes

| | PvE (solo) | PvP (online) |
| --- | --- | --- |
| Who | you vs the AI | you, other players, and the AI |
| Network | none; works offline | WebSocket to the game server |
| Stash | the current stash, on the device | a new stash, in Heroku Postgres |
| Account | none | a silent device account (Steam link later) |
| Money / loadout / stats | on the device | server-owned |
| Traders / quests / presets | on the device (decided: per-stash) | server-owned (decided: per-stash) |
| Look / tutorial | account-wide (decided) | account-wide (decided) |
| Starter kit | today's starter kit | its own PvP kit (§4.6) |
| Can you cheat the stash? | it is your device, so yes — that is fine | no: the server is the only writer |

**Decided reading of the brief:** PvE = today's offline solo raid; PvP = today's online PvPvE raid. Online co-op PvE
is a later option (§4.3).

### 3.2 What stays local, what moves

- **Stays local:** settings (`user://settings.cfg`), keybinds, the solo profile, the solo stash, the solo raid.
- **Moves to the server:** the online profile (stash, loadout, money, stats, traders, quests, presets), the online
  raid's kit and result, the account row.
- **Shared:** the game build, the item database, the map, the AI, the matchmaker. The online and solo raids use the
  same scene; only the profile source and the mode differ.

### 3.3 The one-sentence architecture

**The client never writes the online stash.** It sends *intents* (buy, sell, move, equip, start raid, I extracted) to
the game server; the game server validates them against a profile it owns and persists through a small companion API
into Heroku Postgres; the client's copy of the online profile is a view that the server refreshes.

That is the whole update. Everything below is detail.

---

## 4. Game modes

### 4.1 PvE (solo)

- It is **today's `START RAID`**: offline, AI only, the local profile.
- No account, no network, no server. It must keep working with the internet off, on a plane, on a locked-down school
  laptop. That is a store rule (`STORE_RULES.md` §4: no forced account for solo).
- The stash, money, traders, quests and stats are the current `user://profile.json`. **Nothing in it changes format.**
- The only player-facing change is naming: the hideout says **PvE (SOLO)** so it is obvious which stash you are in.
- The free kit, the no-gear warning, the end screen and the backup file all keep working exactly as they do.

### 4.2 PvP (online)

- It is **today's `ONLINE`**: queue/party, the server, other players, the AI.
- The online stash is server-owned. You cannot edit it in `localStorage` or a save file.
- The kit you take in is issued by the server from your online loadout. The client does not tell the server what it
  carries; the server tells the client.
- Extraction, death and MIA write back on the server. The client's end screen shows the server's result.
- The server already checks shots, movement, health, extracts and loot locks. The Stash update adds the stash, the
  kit and the rewards to that list.

### 4.3 Online co-op PvE (later; decided)

**Decided 2026-11-04: PvE is offline solo now; online co-op PvE is a later option.** The plan keeps the door open:

- It is a **third queue mode** (`mode = PVE`), not a new stash. It uses the **online** stash, because it is online and
  the server has to own it.
- The matchmaker gets a `mode` field on parties and raids so PvE and PvP queues never mix.
- It is a small addition **if** the `mode` field is added now (it is cheap) and **large** if it is bolted on later.
- **Decided:** add the `mode` field in Phase 2 even though only PvP uses it. Do not build the co-op queue until the
  owner asks.

### 4.4 Switching modes

- The switch lives in the **hideout**, at the top: `PvE (SOLO) | PvP (ONLINE)`, with the active stash's money and a
  one-line explanation.
- Switching to PvE: disconnect from the server (leave the party; you cannot switch mid-raid), load the solo profile.
- Switching to PvP: connect (or show the GO ONLINE panel), load the online profile from the server.
- **Mid-raid there is no switch.** The pause menu's LEAVE RAID returns to the hideout in the same mode.
- A solo raid must never be startable while the online profile is active, and vice versa. Add a `Profile.mode` guard
  and a test for it.

### 4.5 Naming and onboarding

- Use the owner's words: **PvE** and **PvP**, with **SOLO** and **ONLINE** as the short labels on the switch.
- First time a player opens PvP, show a one-time panel:
  > "PvP is online and uses a separate stash saved on the server. Your current stash is now your PvE stash. PvP starts
  > fresh with a starter kit."
- This is the single most important message in the update. Playtesters must not think their stash was wiped.

### 4.6 The PvP starter kit (decided: separate; contents proposed)

**Decided 2026-11-04: PvP starts with its own kit, not the solo one.** The point is that PvP starts poorer and tenser
than PvE, so the first good extract matters. The solo kit stays exactly as it is (Hound AK, medium backpack, 60 rifle
rounds, a bandage).

**Proposed PvP kit** — the same "free kit" the hideout already gives a player with nothing (so the items and numbers
already exist), plus a small wallet:

| Item | Count | Why |
| --- | --- | --- |
| Stinger pistol (`pistol`), loaded | 1 (12 rounds in it) | a real gun, but a weak one |
| Stinger rounds (`pistol_ammo`) | 30 | enough for a fight, not a war |
| Bandage | 1 | one mistake is survivable |
| Small backpack (`backpack_small`) | 1 | somewhere to put the first haul |
| Money | **$20,000** (proposed) | buys a Hound (AK) or armor and meds, not both |

- The pistol, rounds, bandage and small backpack are exactly `hideout.gd`'s free kit (`take_free_kit`), so there is no
  new item or art work.
- **$20,000** is the number to argue about. The Hound's base value is $12,500 and traders mark it up, so $20,000 buys
  a rifle and a little ammo, or a pistol kit with armor and meds. $10,000 makes the first raid a real gamble; $35,000
  is close to the solo start and defeats the point. **My pick: $20,000, tune after the first PvP playtest.**
- The PvP free kit (when a player has nothing at all) should follow the same rule as solo: one per raid, only when
  empty, and it cannot be sold for profit (the `free` flag already exists on `ItemStack`).
- If the owner wants the PvP kit to be a *scav* fantasy instead, the alternative is a knife or a shotgun; say so and
  I will price it. The pistol version is the least new work and the easiest to reason about.

---

## 5. Architecture

### 5.1 The pieces

```
Browser / desktop client (Godot)
   |  WSS: game traffic; the device secret is sent once in _hello
   v
Game server (Godot --server, Heroku dyno, the "web" process)
   |  HTTP over 127.0.0.1 with a service token
   v
Stash API (small companion service, same dyno)
   |  TLS, DATABASE_URL
   v
Heroku Postgres
```

- **Client:** unchanged transport (`WebSocketMultiplayerPeer`, `wss://`). It gains an account secret, a mode, and a
  read-only view of the online profile.
- **Game server:** the existing `scripts/net.gd` process. It gains an in-memory online profile per connected account,
  the economy RPCs, and the raid start/end persistence calls.
- **Stash API:** a small service in `server/` (Node.js + `pg` is the recommendation; Python/FastAPI is the
  alternative). It owns the SQL, the transactions, the account rows and the service token. It does **not** know item
  rules; the game server validates those, because `ItemDB` lives in GDScript.
- **Postgres:** Heroku Postgres, reached only by the API through `DATABASE_URL`. TLS required.

### 5.2 Why a companion API (and not SQL from Godot)

Godot has no Postgres driver. The options were:

1. **Companion API in the same dyno (recommended).** One Docker image runs the Godot server and the API; the API
   listens on `127.0.0.1` only. No second dyno, no public surface, the API can restart with the game server. The
   Dockerfile gains the API runtime (Node or Python) and an entrypoint script that starts both and forwards SIGTERM.
2. **Companion API as a second Heroku app.** Cleaner separation, but an extra dyno (~$7/month) and an extra public
   endpoint to secure. Use this if the sidecar proves flaky.
3. **A hosted Postgres REST layer (PostgREST, Supabase, etc.).** Adds a third-party processor to the privacy story and
   a dependency the owner did not ask for. Not recommended.
4. **The Postgres wire protocol in GDScript.** Technically possible, practically a bad idea. No.

**Proposed:** option 1. The plan assumes it; switching to option 2 changes the URL and the deploy, not the schema.

### 5.3 Authentication flow

1. **First launch:** the client generates a random 32-byte **device secret**, stores it in `user://account.json`
   (mirrored to `localStorage["bloxov_account"]` on web), and shows no UI. This is the "silent device account".
2. **First online login:** the client sends `account_id = ""` and the secret in `_hello` (over WSS). The game server
   calls `POST /v1/login` on the API. No account with that secret hash exists, so the API creates one and a fresh
   online profile, and returns `account_id`, the profile, and a session token.
3. **Later logins:** the client sends `account_id` + the same secret. The API verifies the hash and returns the
   profile. The game server holds the profile in memory for the session.
4. **Every economy/raid call** goes from the game server to the API with the **service token** and the `account_id`
   from the session. The client never talks to the API and never sees the service token.
5. **Transfer:** a one-time code (see §8) lets a new device claim the account. The old device's secret is rotated, so
   it stops working.
6. **Delete:** the client asks the game server, which calls `DELETE /v1/account/:id`; the API deletes the account and
   profile; the client clears its local account file and returns to PvE.

**Why the secret is sent only once:** after `_hello`, the connection itself is the session. Re-sending the secret on
every RPC would put it in more logs and packets for no gain. The server binds the peer id to the account id for the
life of the connection.

**What the server stores:** a **hash** of the secret (Argon2id or bcrypt), never the secret itself. The client stores
the secret; if it is lost, the account is lost unless a transfer code was made. That is the cost of no email/login,
and the UI must say so.

### 5.4 Session and concurrency

- One **active session per account** (proposed; §8.6). A second login is refused with "This account is
  playing in another tab or on another device." A transfer code is the way to move.
- The API stores a `revision` on the profile. Every write includes the revision the server based it on; a mismatch is
  rejected. This stops two tabs or a stale cache from duplicating items.
- The game server keeps the profile in memory and **flushes on every meaningful change**: raid start, raid end,
  purchases, sales, stash moves (debounced by ~1 s), trader/quest changes, mode changes. A crash loses at most the
  debounce window, never a completed raid.
- **Heroku restarts:** the dyno restarts daily. Connected players are disconnected; in-flight raids are lost; the
  database is intact. Orphaned `in_raid` profiles are resolved on next login (§7.6).

### 5.5 The client's copy of the online profile

- It is a **cache and a view**, not a source of truth.
- On login and after every server write, the server sends a `profile_sync` RPC with the full profile (small: <50 KB)
  or a delta. Full sync is simpler and fine at this scale; use it first.
- The hideout UI reads the cache. Economy actions send intents and wait for the sync; the UI can be optimistic but must
  roll back on rejection.
- On disconnect, the cache stays visible but **read-only**, with a "Reconnecting…" banner. Do not silently fall back
  to solo: a player could think they are spending online money when they are spending solo money.
- The cache is written to `user://online_profile.json` only to make the next login fast; the server ignores it. It is
  cleared on logout and delete.

---

## 6. Database schema (Heroku Postgres)

All tables live in one schema. The API owns them; the game server never sends SQL. Use `jsonb` for item grids so the
item model stays in `ItemDB` and does not need a table per item. Money is `bigint`; timestamps are `timestamptz`.

### 6.1 Tables

```sql
-- One row per account. Credentials (device secret, Steam) live in `credentials` below.
create table accounts (
  id              uuid primary key default gen_random_uuid(),
  name            text not null default '',      -- filtered by NameFilter before it is stored
  look            jsonb not null default '{}',   -- account-wide (decided)
  tutorial        jsonb not null default '{}',   -- account-wide (decided)
  transfer_hash   text,                          -- one active transfer code
  transfer_expires timestamptz,
  banned_until    timestamptz,
  ban_reason      text,
  ban_count       int not null default 0,
  created_at      timestamptz not null default now(),
  last_seen_at    timestamptz not null default now(),
  deleted_at      timestamptz
);
create index accounts_transfer on accounts (transfer_hash) where transfer_hash is not null;

-- How a player proves it is them: a device secret now, a Steam ID later. One account, several credentials.
create table credentials (
  id          bigserial primary key,
  account_id  uuid not null references accounts(id) on delete cascade,
  kind        text not null,                     -- 'device' | 'steam'
  secret_hash text,                              -- device only (Argon2id/bcrypt)
  external_id text,                              -- Steam ID, later
  created_at  timestamptz not null default now(),
  revoked_at  timestamptz
);
create index credentials_secret on credentials (secret_hash) where secret_hash is not null;
create index credentials_external on credentials (external_id) where external_id is not null;

-- The online profile: one row per account. Everything the solo profile keeps, minus settings.
create table profiles (
  account_id      uuid primary key references accounts(id) on delete cascade,
  revision        bigint not null default 1,
  money           bigint not null default 20000,  -- PvP starting money (§4.6); the game server sends the real fresh profile
  stash_size      int[] not null default '{8,20}',
  stash           jsonb not null default '[]',
  loadout         jsonb not null default '{}',
  stats           jsonb not null default '{"raids":0,"extracts":0,"deaths":0,"earned":0}',
  trader_spent    jsonb not null default '{}',
  trader_levels   jsonb not null default '{}',
  quests_done     jsonb not null default '[]',
  quest_progress  jsonb not null default '{}',
  presets         jsonb not null default '[]',
  free_kit_raid   int not null default -1,
  raid_state      text not null default 'idle',  -- idle | in_raid
  raid_id         text,                          -- the server's raid id
  raid_started_at timestamptz,
  raid_snapshot   jsonb,                         -- the loadout before the raid (for crash restore)
  updated_at      timestamptz not null default now()
);
create index profiles_updated on profiles (updated_at);

-- Optional but useful: one line per raid result, for stats and support.
create table raid_results (
  id              bigserial primary key,
  account_id      uuid not null references accounts(id) on delete cascade,
  raid_id         text not null,
  result          text not null,                 -- extracted | killed | mia | left | crash
  loot_value      int not null default 0,
  created_at      timestamptz not null default now()
);
create index raid_results_account on raid_results (account_id, created_at desc);

-- The schema version, so a deploy knows what to migrate.
create table meta (key text primary key, value text not null);
```

**Notes**

- `stash` and `loadout` use the exact JSON that `Profile._write_grid` / `capture_inventory` already produce. That
  keeps one item format across solo, online and backups. The API stores it; the game server validates it.
- The API's profile response joins `accounts.name`, `accounts.look` and `accounts.tutorial` into the profile object the
  game server sees, so the client keeps one profile shape.
- The column defaults (money, stash size, stats) are a safety net only. On account creation the game server sends a
  fresh profile built from the PvP starter kit and money (§4.6), so the starting numbers stay in one place (GDScript)
  and cannot drift from the schema.
- `look` and `tutorial` on `accounts` are the decided account-wide fields. If the owner changes their mind, move
  them to `profiles`; the schema is otherwise unchanged.
- `raid_snapshot` is only the loadout, not the stash. The stash does not change during a raid (loot is carried, then
  written back at the end), so the loadout is enough to restore a crash.
- **No item table.** A stash is at most a few hundred stacks (<50 KB); `jsonb` is simpler and fast enough. If the game
  ever needs cross-player item queries (trading, an auction house), revisit it.
- **No password column.** There is no password. The device secret is the credential.

### 6.2 Migrations

- SQL files in `server/migrations/NNNN_name.sql`, applied in order by a small runner at API boot (or by a one-off
  `npm run migrate`/`python -m migrate` in CI before the deploy).
- `meta.schema_version` records the last applied number. A migration is additive whenever possible; the API and game
  server deploy together, but a rolling restart can overlap, so the API must tolerate the previous game server's calls
  for a few seconds.
- **Never destructive without a backup.** Take a Heroku Postgres backup before a destructive migration and record it
  in the release notes.

### 6.3 Retention and deletion

- **Account delete (in-game):** delete the `profiles` row, the `raid_results` rows and the `accounts` row in one
  transaction. The solo profile is untouched. Show a confirmation that says what is deleted and what stays.
- **Backups:** Heroku Postgres keeps its own backups for a few days. Say so in the privacy policy; do not promise
  "instant, everywhere".
- **Inactive accounts:** proposed cleanup after 12 months with no `last_seen_at`, after a warning email is impossible
  (there is no email). Alternative: never delete. **Owner decision.** For now, do not auto-delete; revisit before
  launch.
- **Logs:** the server logs names, kicks and account ids. Keep the existing short retention and say so in the privacy
  policy.

---

## 7. Server-authoritative economy

This is the part that makes the online stash worth having. It is also the part that touches the most code.

### 7.1 The four levels of authority

Build in this order. Each level is useful on its own, and each one closes a specific cheat.

| Level | What the server owns | What it stops | Cost |
| --- | --- | --- | --- |
| **L1: storage** | The online profile is read from and written to Postgres at raid start/end. | Editing `localStorage` while offline; losing the stash when the browser clears storage. | Accounts + API + DB. |
| **L2: kit** | The server issues the loadout and builds `_carried` itself; it ignores a client-sent kit. | Fabricating a raid kit (the current `_kit` trust hole). | Medium: `_raid_start` carries the kit; `_kit` is retired or validated. |
| **L3: hideout economy** | Every buy/sell/move/equip/upgrade/quest/level/preset is an intent the server applies. | Duplicating items, printing money, buying past trader levels, handing in quests twice. | Large: every hideout mutation becomes an RPC. |
| **L4: in-raid items** | The server tracks every item change in the raid (loot, drops, ammo, heals, keys, attachments, durability) and computes the extracted inventory. | Bringing out items you never had; editing durability/attachments at extract. | Medium-large: the client must report item-state changes, or the server must reconstruct them. |

**Proposed target:** L1 + L2 in 0.31.0; L3 in 0.31.x; L4 in 0.31.x/0.32 as the anti-cheat finish. Shipping L1+L2
already gives the owner a real online stash and closes the worst hole (fabricated gear). L3 is what most players
think of as "server-owned", and it is the big one.

### 7.2 The operations the server must accept (L3)

Each is a typed RPC with a payload the server validates against its own copy of the profile. The client sends
*what it wants*, never *the result*.

| Operation | Server checks | Server does |
| --- | --- | --- |
| `buy(trader, item, count)` | trader level and stock, price from `ItemDB`/`Traders`, money, stash space | removes money, adds the item to the stash, adds to `trader_spent`, may unlock a level |
| `sell(trader, item_ref, count)` | the item exists at that spot in the stash/loadout, the trader buys it | removes the item, adds money |
| `move(from_grid, from_pos, to_grid, to_pos, rotated)` | both grids exist, the item is at `from`, it fits at `to`, no overlap | moves it |
| `split(item_ref, count)` / `merge(a, b)` | counts and space | splits/merges |
| `equip(item_ref, slot)` / `unequip(slot)` | slot rules, backpack size, item kind | equips/unequips |
| `upgrade_stash()` | money, current level, max level | takes money, grows the grid |
| `level_up(trader)` | `Profile.can_level_up` equivalent: quests + money | levels the trader |
| `hand_in_quest(quest, item_refs)` | quest exists, not done, the items are real and required | consumes items, marks progress/done, pays |
| `save_preset(name, kit)` / `delete_preset` / `apply_preset` | preset count, items and money for a "buy all" | stores/applies |
| `set_look(part, option)` | the part and option are real (`Operators`) | sets the account look |
| `set_name(name)` | `NameFilter` | sets the account name |
| `take_free_kit()` | the free-kit rule (nothing carried, not taken this raid) | gives the kit, sets `free_kit_raid` |
| `start_raid(mode, party)` | mode is PvP, the profile is idle, the loadout is valid | marks `in_raid`, snapshots, applies `death_loadout`, returns the kit |
| `end_raid(result, final_inventory, loot_value)` | the result, the carried set, the inventory | computes and persists the new stash/loadout/money/stats |

**Validation rules that apply to all of them:**

- Item ids must exist in `ItemDB`; counts must be positive and within stack limits; grids must fit and not overlap.
- Money never goes negative; prices come from the server's `ItemDB`/`Traders`, never from the client.
- The item must be where the client says it is, in the server's profile.
- The `revision` must match; a stale write is rejected with a fresh profile.
- Rate limits are per **account**, not just per peer (a scripted client can reconnect).
- An operation while `raid_state = 'in_raid'` is rejected (the hideout is not available in a raid).

### 7.3 The raid start handshake

1. The player queues or presses START NOW. The matchmaker picks the raid.
2. Before `_raid_start`, the game server calls `POST /v1/raid/start` for each player with their `account_id`,
   `raid_id` and the party.
3. The API, in one transaction: checks `raid_state = 'idle'`, stores `raid_snapshot = loadout`, sets
   `loadout = death_loadout(loadout)` (gear at risk), sets `raid_state = 'in_raid'`, `raid_id`,
   `raid_started_at = now()`, bumps `revision`, returns the kit (the loadout as it was, plus the secure pocket).
4. The server sends the kit to the client in `_raid_start` (a new `kit` field) and builds `_carried` from it. The
   client applies it. **The client no longer sends `_kit`.** If it does (old client), the server ignores it.
5. If the API call fails, that player is not put in the raid; they get a notice and stay in the hideout. The party
   and queue handle the missing member (the existing "wait until everyone is back" logic).

### 7.4 The raid end handshake

1. The server knows the result: `extracted` (verified by `_extract_ok`), `killed` (state/health), `mia` (clock), or
   `left` (the pause menu / disconnect).
2. It calls `POST /v1/raid/end` with the result, the server's `_carried` (after container moves, drops, shots,
   grenades, heals), the client's final inventory (for item state), and the loot value.
3. The API validates, computes the new profile and persists it in one transaction: stash, loadout, money, stats,
   `free_kit_raid`, `raid_state = 'idle'`, `revision++`.
4. The server sends `profile_sync` to the client. The end screen shows the server's numbers.
5. If the call fails, the server retries with backoff and keeps the result in memory. The player sees "Saving…" and
   cannot start another raid until it saves. If the server dies first, the orphan rule (§7.6) applies.

### 7.5 What the server can already reconstruct (L4)

The server already tracks a lot in `_carried` (`scripts/net.gd:158`):

- The kit it issued (L2).
- Container moves: `_container_update` diffs the before/after and adjusts `_carried` (`NetGuard.move_items`).
- Drops and bodies: `_drop_items` takes entries off `_carried`.
- Shots and grenades: `NetGuard.use_item` takes ammo/grenades off.
- Heals: `_healed` takes the item off.
- Keys: `_open_door` checks the key in `_carried` (but does not consume it today; the client does).

So the server can compute **which item ids and counts** came out. It cannot yet compute **durability, attachments,
loaded rounds, labels, or found parts**, because those change on the client (repair, attach, fire, loot a found
attachment). L4 has two options:

- **Option A (recommended, cheaper):** the client sends its final inventory at extract; the server checks it against
  `_carried` (every item accounted for, counts not increased except for items the server saw looted, ids real) and
  uses the client's item state for the fields it cannot track. A mismatch is logged, the server's counts win, and a
  repeat is a strike.
- **Option B (stronger, more work):** report every item-state change (attach, detach, repair, load, split) as its own
  RPC, and have the server hold the full item state. This is the clean end state but it touches `gun.gd`,
  `inventory.gd`, `grid_inventory.gd`, `loot_container.gd` and `item_stack.gd`.

Start with A; move to B only if cheating shows up in playtests.

### 7.6 Disconnects, crashes and orphans

- **Player disconnects mid-raid:** the raid result is `left`/`killed`; gear is lost, as today. The client is told
  before it can leave ("Leaving loses your gear").
- **Reconnect window (later, optional):** keep the body and the profile `in_raid` for ~2 minutes; if the same account
  reconnects, resume. This is a real UX win but needs a resume path in `net_raid.gd` and the matchmaker. **Proposed:
  not in 0.31.0.**
- **Server crash / Heroku restart:** on boot, the game server has a new boot id. Any profile with `raid_state =
  'in_raid'` and a `raid_id` from a previous boot is an orphan.
  - **Proposed policy:** restore `raid_snapshot` (the pre-raid loadout) and mark the result `crash`. The player did
    nothing wrong, and the alternative (losing gear to a Heroku restart) is the kind of thing that makes people quit.
  - The stash is unchanged during a raid, so only the loadout needs restoring. Loot from the crashed raid is lost,
    which is fine.
  - A player who disconnects and never reconnects is **not** a crash: the server saw them leave, so it resolved as
    death. The orphan rule is only for profiles the server could not resolve.
- **API down:** the game server refuses new online logins ("Online is unavailable right now; PvE still works") and
  retries writes. It does not let players in with an unverified profile.
- **Postgres down:** same as API down. The API returns 503; the game server shows the same message.

### 7.7 Anti-cheat and bans

- The existing `NetGuard` checks stay. With accounts, the server can also:
  - Ban by `account_id` (`accounts.banned_until`, `ban_reason`, `ban_count`), checked at login.
  - Escalate: 3 strikes in a raid = kick (today); repeated kicks = 24 h, then 7 days, then permanent (proposed).
  - Log every catch with the account id, not just the peer id.
- **The honest limitation:** a device account is free and silent, so a banned player can make a new one. Without an
  email or Steam login, bans are a speed bump, not a wall. Say this to the owner. Mitigations:
  - Rate-limit account creation per hashed IP (privacy-sensitive; ask).
  - Link Steam later (the roadmap already says "Steam login can be linked later"); a Steam-linked account is much
    harder to replace.
  - Keep the server authoritative so a new account does not inherit cheated gear.
- **What the server still trusts (until L4):** item durability/attachments at extract, and the client's own health
  application (it reports damage taken). The existing god-mode check covers the worst case.

---

## 8. Device accounts

### 8.1 Creation

- On first launch, generate a 32-byte random secret with `Crypto.new().generate_random_bytes(32)`.
- Store it in `user://account.json` as `{"account_id": "", "secret": "<base64>", "created_at": ...}`.
- On web, also mirror it to `localStorage["bloxov_account"]` (the same reason the profile is mirrored: `user://` on
  web can lag or lose its storage connection).
- The account is created on the server the first time the player goes online, not at launch. A player who only plays
  PvE never creates one.
- **Never** put the secret in a log, a crash report, a screenshot or the save backup. The backup is solo-only.

### 8.2 Transfer code (moving a device credential)

- In the account panel: **TRANSFER TO ANOTHER DEVICE** → shows a one-time code, e.g. `K7QP-3M9X` (10 chars from
  `Matchmaker.CODE_LETTERS`-style alphabet, ~50 bits). Expires in **15 minutes**.
- On the new device: **I HAVE A CODE** → enter it. The API verifies the hash, rotates the account's `secret_hash` to
  the new device's secret, clears the code, and returns the profile.
- The old device's next call fails ("This account was moved to another device"). Its local cache is cleared.
- One active code per account; making a new one invalidates the old.
- **Proposed:** a transfer **moves** the device credential (one active device at a time). It does not block linking a
  Steam credential to the same account later; see §8.6.
- **Why one active device:** two devices playing on one stash at the same time is the easiest way to duplicate items
  (both buy the same gun before either save lands). The revision check would catch some of it, but not all. One active
  session is the simple, safe rule; a second login offers **TAKE OVER HERE**, which signs the other one out.

### 8.3 Deletion

- **DELETE ONLINE ACCOUNT** in the account panel, behind a typed confirmation (`DELETE`) and a clear list of what
  goes: the online stash, money, loadout, stats, traders, quests, presets, the account, the transfer code.
- The solo profile is not touched. Say so.
- The API deletes in one transaction. The client clears `account.json` and the online cache and returns to PvE.
- **Store rule:** deletion must be available **inside the game** (Apple 5.1.1(v), Google's account deletion policy).
  A web deletion link is also required by Google; add a page under `web/` in the launch phase.
- **Proposed:** immediate hard delete, with a warning that Heroku's database backups may keep a copy for a few days.
  A 30-day grace period is friendlier but conflicts with "delete" in the store rules unless it is clearly a
  deactivation. Ask the owner.

### 8.4 Recovery

- No email, no password, no security questions. **Lose the device and the transfer code and the online account is
  gone.** The UI must say this before the player invests time.
- The solo stash is still on the device (or in the player's own backup file), so the loss is limited to online
  progress.
- **Steam linking is the recovery path** (§8.6): once a Steam credential is attached, signing in on any Steam machine
  recovers the account without a code.
- Apple/Google sign-in would trigger Apple 4.8 (Sign in with Apple) and more privacy work; do not add it unless the
  owner wants it.

### 8.5 Names

- The name is stored on the account, filtered by `NameFilter`, changeable in the account panel.
- **Proposed:** names are not unique. Two players can be "Tavish". The kill feed already shows names; if confusion
  matters, add a short discriminator (e.g. `Tavish#4821`) later.
- The name is sent to other players in the raid, as today. It is not shown on a public leaderboard (there isn't one).

### 8.6 Steam and cross-platform accounts (the owner's question)

The owner asked: "a Steam player has their account on Steam, but if the browser player wants to migrate account to
Steam that should be possible." It is, and the plan separates two things that are easy to mix up:

**1. Credentials (how you prove it is you).** An account can have more than one credential:

| Credential | Where it comes from | Good for |
| --- | --- | --- |
| Device secret | generated on first launch, stored on the device | the default, no login |
| Transfer code | one-time code from the account panel | moving a device credential |
| Steam ID | Steamworks, once the Steam build exists | cross-platform login and recovery |

- **Browser → Steam:** in the account panel, **LINK STEAM** → the Steam overlay/login returns the Steam ID → the API
  adds it to the same `accounts` row. The online stash does not move; it is the same account, now reachable from
  Steam. The player can then revoke the browser's device credential if they want.
- **Steam → browser:** on Steam, **TRANSFER TO A BROWSER** makes a code; enter it in the browser and the browser gets a
  device credential linked to the same account. (A web Steam OpenID login is the alternative; the code is simpler and
  works before any web login exists.)
- **Steam → Steam:** Steam already identifies the player; no code needed.
- **A pure Steam player** (never opened the browser) has a device secret too, generated on first launch; it is just
  unused. The Steam ID is the credential they actually use. That matches "a Steam player has their account on Steam".
- **Linking is one-way to add, revocable:** a credential can be added and later revoked from the account panel, as
  long as at least one credential remains.

**2. Active session (who is playing right now).** Linking credentials does **not** mean two devices can play at once.
The proposed rule is **one active session per account.** A second login offers **TAKE OVER HERE**, which signs the
other one out. This is what stops item duplication.

**What this means for the build:**

- The `accounts` table no longer holds a single `secret_hash`; credentials are their own table, `credentials`
  (§6.1): one row per credential, `kind` (`device`/`steam`), `secret_hash` for a device secret, `external_id` for a
  Steam ID. An account can have several, and each can be revoked.
- Steam linking is **not in 0.31.0.** It needs the Steam build and Steamworks, which do not exist yet. The plan
  reserves the table and the account-panel button so it can be added without a migration of the stash.
- The transfer code remains the only cross-device path until Steam exists.

---

## 9. Migration

### 9.1 The solo profile does not change

- **`Profile.VERSION` stays 1 for the solo profile.** The current `user://profile.json` keeps its exact shape. No
  migration branch is needed, and no playtester loses anything.
- The online profile is a **new** thing with its own storage. It starts with the PvP kit and money in §4.6.
- The first time a player opens PvP, they get the one-time explainer from §4.5. Their solo stash is untouched.

This is the single most important safety decision in the plan: **do not touch the solo save format in the same update
that adds accounts.** Two migrations at once is how data gets lost.

### 9.2 What about the playtesters who already played online?

Their online raids have been writing to their **local** profile (the shared stash). After the update:

- That local profile is their **solo** profile, with everything they earned, including online earnings.
- Their **online** profile starts fresh. That is the owner's stated intent ("current stash becomes the single-player
  stash"), but it should be said out loud in the release notes.
- **Do not** copy the local profile into the online profile. It would be editable before the first sync, and it would
  defeat the point of a separate online economy. If the owner wants a one-time grant for playtesters, that is a
  deliberate, server-side gift, not a copy. **Ask.**

### 9.3 `Profile` refactor

The static `Profile` is used everywhere. The pragmatic path:

1. Add `Profile.mode` (`SOLO` / `ONLINE`) and `Profile.online_profile` (a dictionary in the same shape as the saved
   profile).
2. Add `Profile.use_solo()` / `Profile.use_online(data)` that swap the static fields (`money`, `stash`, `loadout`,
   `stats`, `trader_*`, `quests_*`, `presets`, `look`, `tutorial`) to the chosen source.
3. Keep `Profile.save_profile()` writing **only** the solo profile. In online mode it is a no-op (the server saves).
4. Add `ProfileStore`-style helpers for the operations in §7.2. The hideout calls those instead of mutating
   `Profile.money` directly. This is the L3 work; in L1/L2 the hideout can keep mutating the in-memory online copy and
   the server validates at raid start.
5. Guard every direct `Profile.save_profile()` call with the mode. Search for it; there are several.

**Risk:** the static fields are read in many places. Add a smoke-test section that switches modes and checks that the
solo and online stashes are independent, that a solo save never writes online data, and that an online sync never
touches `user://profile.json`.

### 9.4 SaveBackup

`SaveBackup.apply()` currently replaces the whole profile, including the stash (`scripts/save_backup.gd:56`). With two
stashes:

- **A backup is solo-only.** `pack()` writes the solo profile + settings; `apply()` restores the solo profile + settings
  and never the online profile.
- The online profile can be **exported** (read-only JSON, for transparency) but **not imported** by the player. An
  import would be an obvious cheat vector; a support tool can do it server-side if ever needed.
- Add a line to the backup UI: "This file is your PvE stash. PvP is saved on the server."
- Test: restoring a backup while in PvP does not change the online stash, and does not leave the UI showing stale
  online data.

### 9.5 Rollback

- If the update has to be rolled back, the solo profile is untouched, so PvE is safe.
- The online profile lives in Postgres; a rollback of the game server leaves the rows in place. The previous server
  ignores them. No data is lost.
- The client's `account.json` is harmless if the feature is off.
- The feature flag (`PvP online enabled`) lets the owner turn it off without a deploy if something goes wrong. Keep it
  in a server env var and in `GameSettings` for the client (hidden in release builds).

---

## 10. UI and UX

### 10.1 The hideout

- **Top bar:** `PvE (SOLO) | PvP (ONLINE)` segmented switch, the active stash's money, and a short line:
  "PvE: on this device, works offline. PvP: online, saved on the server."
- **PvE:** exactly today's hideout. Stash, loadout, traders, quests, START RAID.
- **PvP, not connected:** the switch shows the GO ONLINE panel (name, GO ONLINE). The stash area is disabled with a
  "Connect to see your PvP stash" message.
- **PvP, connected:** the same hideout layout, reading the online profile. The ONLINE button shows the party/queue
  state as today.
- **PvP, reconnecting:** the last profile stays visible, read-only, with a banner and a RETRY button. Economy actions
  are disabled. Do not fall back to solo.
- **Account panel** (from the ONLINE panel): account id (short), name, transfer code, delete account, export online
  data (later), link Steam (later).

### 10.2 The raid

- **PvE:** unchanged.
- **PvP:** the server-issued kit is applied at raid start. The player sees the same loadout they chose; the server is
  the one that decided it. If the kit differs (e.g. the server rejected an item), show a one-line notice.
- **End screen:** the server's result. If the client and server disagree, the server wins; show a small "saved on the
  server" note only when there was a correction (rare).
- **Saving:** if the end-of-raid save is slow, show "Saving your stash…" and disable the return button until it
  finishes. Never let the player start another raid before the save lands.

### 10.3 Errors and edge cases

- **Version mismatch:** today's message ("The server is on vX and you have vY") stays.
- **Banned:** "You are banned until <date>: <reason>." No retry loop.
- **Account moved:** "This account was moved to another device." Offer the transfer-code flow.
- **Server full:** today's message stays.
- **API/DB down:** "PvP is unavailable right now. PvE still works." A RETRY button.
- **Two tabs:** "This account is playing in another tab." Offer "Take over here" (kicks the other tab) or cancel.
  **Proposed:** take-over with a warning, because a crashed tab would otherwise lock the account.
- **Deleted account:** clear the cache, return to PvE, show "Your PvP account was deleted. Your PvE stash is safe."

### 10.4 Privacy page

`scripts/title_screen.gd:20-34` currently says "No accounts" and "Nothing is kept after the raid". Both become false.
The launch phase must update it to say:

- What the online account is (a device id, a name, a look, progress).
- What is stored (the online stash, money, stats, traders, quests, last seen).
- Where (Heroku Postgres, hosted by Heroku).
- How long (until deletion; backups for a few days).
- How to delete (in-game, plus a web link).
- That PvE works without an account.
- That the solo profile stays on the device.

This is a docs/text change, but it is a **release blocker** for the stores.

---

## 11. Phases

Each phase is independently shippable and testable. The version numbers are a proposal; the owner may prefer one big
release. **Do not bump `project.godot` for docs-only steps.**

### Phase 0 — decisions and scaffolding (docs, no version bump)

- This plan; the owner's answers to §15.
- Add `docs/STASH_UPDATE_PLAN.md` to the roadmap and handoff docs.
- Decide the API language, the sidecar vs second app, the Postgres plan and the release shape.
- **Exit:** the owner has answered the open questions; the plan is linked everywhere.

### Phase 1 — the mode split, no server (0.31.0 or a dev-only step)

- `Profile.mode` and the SOLO/ONLINE switch in the hideout, with ONLINE hidden behind a flag.
- `DeviceAccount` (generate/store the secret; no server call yet).
- The `Profile` mode guards and the SaveBackup solo-only change.
- Tests: mode switching, solo save isolation, backup isolation.
- **Exit:** PvE is unchanged; the switch exists but PvP is not reachable in release builds.
- **Note:** this phase alone is a safe, small release if the owner wants to see the UI early.

### Phase 2 — accounts, database, online stash at raid boundaries (0.31.0)

- The `server/` API, the Postgres schema, migrations, the sidecar entrypoint, the Dockerfile change, CI.
- Device account creation/login, transfer code, delete.
- The online profile starts fresh with the PvP kit (§4.6); the server loads it and sends it to the client.
- The server issues the kit at raid start and persists the raid-begun state; it persists the result at extract,
  death, MIA and leave.
- The client applies the server's kit and shows the server's result.
- The one-time explainer; the account panel; the privacy text draft.
- **Exit:** a player can play PvP with a server-owned stash that survives a dyno restart; a fabricated kit is
  rejected; the solo stash is untouched.
- **This is the minimum viable Stash update.** If the owner wants one release, this is it.

### Phase 3 — server-owned hideout economy (0.31.x)

- The operations in §7.2, the revision checks, the optimistic UI and rollback.
- The hideout stops mutating `Profile.money` directly; every change is an intent.
- Rate limits per account.
- Tests: buy/sell/move/equip/upgrade/quest/level/preset, stale revision, insufficient money, full stash.
- **Exit:** a modified client cannot print money or duplicate items in the hideout.

### Phase 4 — in-raid item authority and bans (0.31.x/0.32)

- L4 option A (validate the final inventory against `_carried`) or B (report every item-state change).
- Bans by account with escalation.
- The orphan/crash policy and the "Saving…" flow.
- Optional: the reconnect window.
- Tests: fabricated extract inventory, item duplication, banned login, crash restore, disconnect = death.
- **Exit:** the online economy is closed-loop; the owner can ban an account.

### Phase 5 — launch polish (0.32/1.0)

- The account panel finished; export online data; the web deletion page.
- The privacy policy, the Apple privacy label, the Google Data safety form, the store listing text.
- Load test (40 online, 4 raids), a Postgres backup/restore drill, the kill switch.
- The release notes and the one-time message for playtesters.
- Optional: online co-op PvE, Steam linking, hideout customizing (which the roadmap already says saves with the
  online stash).

### What ships when

| Phase | Player sees | Server work | Risk |
| --- | --- | --- | --- |
| 1 | the mode switch | none | low |
| 2 | PvP with a real online stash | API + DB + kit + result | high (new infrastructure) |
| 3 | the hideout is server-backed | economy RPCs | high (touches every screen) |
| 4 | fair PvP, bans | item authority | medium |
| 5 | launch | privacy/store | low code, high paperwork |

---

## 12. Testing

### 12.1 Godot smoke test sections to add

The smoke test (`tests/smoke_test.gd`) already covers profile, hideout, net, PvP, online AI, online loot and
anti-cheat. Add:

- `accounts`: the secret is generated once, stored, reloaded, never logged; a second launch reuses it.
- `mode_switch`: SOLO and ONLINE show independent stashes; a solo save does not write online data; an online sync does
  not touch `user://profile.json`; a solo raid cannot start in online mode and vice versa.
- `online_profile`: first login creates a fresh profile; the solo profile is untouched; the server's profile replaces
  the cache.
- `online_kit`: the server issues the kit; a client-sent kit is ignored; a fabricated item is rejected.
- `online_raid`: extract persists the carried items; death keeps only the secure pocket; MIA and leave behave like
  death; a disconnect loses gear.
- `online_economy` (Phase 3): buy/sell/move/equip/upgrade/quest/level/preset round-trips; stale revision rejected;
  insufficient money rejected; full stash rejected.
- `online_transfer`: a code moves the account; the old secret stops working; an expired code is rejected.
- `online_delete`: the account and profile are gone; the solo profile is intact.
- `online_ban`: a banned account is refused at login with the reason.
- `online_crash`: an orphaned `in_raid` profile is restored to its snapshot.
- `save_backup`: a backup is solo-only; restoring it in PvP does not change the online stash.
- `privacy`: the privacy text mentions the online account, the server storage and deletion.

### 12.2 A fake API for the Godot tests

The smoke test must not need a live Postgres. Add a `StashAPI` interface with two implementations:

- `HttpStashAPI` (the real one, used by the game server).
- `FakeStashAPI` (in-memory, used by the smoke test and the in-process net tests).

The game server takes the API as a dependency (a settable property), so the tests can inject the fake. This is also
how the existing in-process `net`/`pvp` tests keep working without a database.

### 12.3 API tests

- A small test suite next to the API (`server/test/`), run in CI with a Postgres service container.
- Cover: migrations, account create/login, secret hashing, transfer, delete, revision conflicts, raid start/end
  transactions, ban checks, rate limits.
- Run it on every push that touches `server/`.

### 12.4 End-to-end

- One CI job: Postgres + API + Godot `--server` + a scripted client. It creates an account, starts a raid, extracts,
  dies, transfers, deletes, and checks the DB. This is the test that catches the bugs the in-process tests cannot.
- The existing `net`/`pvp`/`online_ai`/`online_loot` sections run with the fake API.
- The real-process test from `DEV_HANDOFF.md` §4.6 (a `--server` process + two clients) still applies; add an account
  login step.

### 12.5 Manual checks before release

- A fresh browser profile: PvE works with the network off; PvP creates an account; the explainer appears once.
- A playtester's existing save: the stash is intact in PvE; PvP starts fresh.
- A dyno restart mid-hideout: reconnect works; the stash is the same.
- A dyno restart mid-raid: the crash policy restores the pre-raid loadout.
- Two tabs: the second is refused or takes over, and items are not duplicated.
- Transfer: the new device has the stash; the old device is signed out.
- Delete: the online data is gone; PvE is intact.
- A banned account: refused with the reason.

### 12.6 Performance

- Budget: a profile read <100 ms p95; a write <200 ms p95; a raid start/end <300 ms. The raid start already loads the
  map for seconds, so this is noise.
- 40 online players, 4 raids: at most 40 profiles in memory, a few writes per second. Postgres Mini is plenty; the
  risk is connection count, so pool 5-10.
- Measure the hideout's economy round-trip; if it is noticeable, batch and debounce, and keep the UI optimistic.

---

## 13. Risks and mitigations

| Risk | Why it hurts | Mitigation |
| --- | --- | --- |
| **Data loss on migration** | Playtesters lose the stash they earned | Do not change the solo format; the solo profile is the source of truth for PvE; back it up before the first online launch; test with a real old save |
| **Scope** | L3 touches every hideout screen | Phases; ship L1+L2 first; keep L3 behind the same flag |
| **Cheating** | A device account is disposable; L4 is not in 0.31.0 | Server authority at every level; rate limits; bans; Steam linking later; be honest with the owner |
| **Latency** | Every hideout action round-trips | Optimistic UI, debounce, full-profile sync at this scale |
| **Heroku limits** | One dyno, ephemeral disk, daily restart, Postgres connections | Sidecar, pool, no local disk, orphan policy, backup drill |
| **Two sessions** | Duplication across tabs/devices | One active session, revision checks, take-over flow |
| **SaveBackup** | A restore could wipe the online stash | Solo-only backups; online export is read-only; test it |
| **Store/privacy** | Accounts change what is collected | Update the privacy page, the Apple label, the Google form, deletion, the web link; do it before launch |
| **PvE feels worthless** | Players may resent a separate online stash | Say it clearly; maybe a one-time playtester grant (owner decision); keep PvE fully playable |
| **Name confusion** | Duplicate names in the kill feed | Discriminator later; `NameFilter` now |
| **Account loss** | No email/password | Warn before investment; transfer code; Steam linking later |
| **Server crash** | Gear lost through no fault of the player | Restore the pre-raid snapshot; mark the result `crash` |

---

## 14. Store, privacy and legal checklist

From `docs/STORE_RULES.md` §3-4, all of this must be true before the online stash ships to a store:

- [ ] The privacy policy is a public URL **and** reachable in the game; it says what is collected, why, how long,
      who it is shared with (Heroku), and how to delete it.
- [ ] The Apple privacy "nutrition label" and the Google Data safety form match the policy exactly.
- [ ] **Delete account in-game**, plus a web deletion link for Google.
- [ ] No forced account for PvE; offline solo works with no account.
- [ ] If Steam/Google/Apple login is added later, Sign in with Apple is offered on iOS (Apple 4.8), and the SDK is
      disclosed.
- [ ] All traffic is `wss://`/`https://`; Postgres uses TLS; the device secret is hashed at rest.
- [ ] The name and any player-visible text go through `NameFilter`.
- [ ] No real-money purchases are added by this update (the store/currency work is separate).
- [ ] The account deletion text says what is deleted and what stays (the solo stash stays).
- [ ] A working demo account (or no login needed) is available for App Review.

**Not legal advice.** The owner should have the policy reviewed before launch.

---

## 15. Decisions and open questions

### Answered 2026-11-04

1. **PvE scope:** offline solo now; online co-op PvE is a later option. Add the `mode` field now so it can come later.
2. **PvP content:** keep the AI (PvPvE, as today).
3. **PvP starter kit:** a **separate** kit, not the solo one. The contents are proposed in §4.6; the $20,000 needs a
   final yes.
4. **Per-stash vs account-wide:** money, stash, loadout, stats, traders, quests, levels and presets are **per-stash**;
   look and tutorial are **account-wide**.
5. **Devices and Steam:** the question was what a transfer code means next to a Steam account. The answer is in §8.6:
   credentials can be **linked** (device secret, transfer code, Steam ID later), but only **one active session at a
   time**. The transfer code moves a device credential; Steam linking is the browser ↔ Steam path. **This needs a yes
   before Phase 2.**

### Still open (answer before Phase 2)

1. **PvP kit numbers:** confirm the pistol + 30 rounds + bandage + small backpack + **$20,000**, or give different
   numbers. *My pick: keep it and tune after the first PvP playtest.*
2. **Disconnect mid-raid:** lose the gear (today's behavior), or allow a short reconnect window?
   *My pick: lose it in 0.31.0 with a clear warning; add a ~2-minute reconnect window later if playtests show it
   matters.*
3. **Server crash mid-raid:** restore the pre-raid loadout, or lose it like a death?
   *My pick: restore it. A Heroku restart is not the player's fault, and losing gear to it is the kind of thing that
   makes people quit.*
4. **Account deletion:** immediate hard delete, or a 30-day grace period?
   *My pick: immediate, with a typed confirmation and a note that database backups may keep a copy for a few days.
   A grace period reads like "deactivation" to the stores.*
5. **Bans:** do you want them now, and what escalation?
   *My pick: 24 hours, then 7 days, then permanent, stored on the account. Be aware a banned player can make a new
   device account until Steam linking exists.*
6. **Names:** unique names, or duplicates allowed?
   *My pick: duplicates for now; add a short discriminator later if the kill feed gets confusing.*
7. **Existing playtesters:** confirm the current stash becomes the solo stash and PvP starts fresh. Do you want a
   one-time thank-you grant for playtesters (server-side, not a copy of the solo stash)?
   *My pick: no copy; a small one-time PvP grant is a nice gesture if you want one.*
8. **Online export:** should players be able to download their online stash as a file (read-only)?
   *My pick: yes, for transparency; no import (it is a cheat vector).*
9. **Hosting cost:** are you OK with Heroku Postgres (roughly $5-9/month on top of the dyno)? The sidecar avoids a
   second dyno.
   *My pick: sidecar + the smallest Postgres plan that has room for backups; confirm the student credit covers it.*
10. **Release shape:** one big 0.31.0, or incremental 0.31.x releases behind a flag?
    *My pick: incremental. Phase 1 (the switch) can ship early; Phase 2 (the real online stash) is 0.31.0; the rest
    follows.*
11. **Two tabs:** refuse the second session, or let it take over?
    *My pick: take over, with a warning, so a crashed tab does not lock the account. This is the one-active-session
    rule in §8.2.*
12. **Steam linking timing:** 0.31.0, or after the Steam build exists?
    *My pick: after the Steam build. The table and the account-panel button are reserved now so it does not need a
    stash migration later.*

---

## 16. File-by-file impact map (for the build)

This is what the update will touch. It is here so a future session can estimate the work without re-reading everything.

| File | Change |
| --- | --- |
| `scripts/profile.gd` | `mode`, online profile swap, mode guards on `save_profile`, the operation helpers; keep `VERSION = 1` for solo |
| `scripts/save_backup.gd` | solo-only `pack`/`apply`; a note in the UI; tests |
| `scripts/hideout.gd` | the SOLO/ONLINE switch, the account panel, the online profile view, the one-time explainer, the economy intents |
| `scripts/title_screen.gd` | the privacy text |
| `scripts/net.gd` | `_hello` with the account secret, `profile_sync`, the economy RPCs, the server-issued kit, the raid start/end API calls, ban checks |
| `scripts/matchmaker.gd` | a `mode` field on players/parties/raids (PvP only for now) |
| `scripts/net_raid.gd` | apply the server kit, report item state (L4), the extract handshake |
| `scripts/raid.gd` | stop writing the online result locally; show the server's result; the "Saving…" flow |
| `scripts/net_guard.gd` | account-level rate limits and strikes; ban hooks |
| `scripts/game_settings.gd` | the mode preference and the feature flag (hidden in release) |
| `scripts/title_screen.gd` / `web/` | the privacy page and the web deletion page |
| `tests/smoke_test.gd` | the sections in §12.1 |
| `server/` (new) | the API, migrations, tests, the entrypoint |
| `Dockerfile`, `heroku.yml` | the API runtime, the entrypoint, the sidecar |
| `.github/workflows/web.yml` | the API tests, the Postgres service, the end-to-end job |
| `docs/` | this plan, `ROADMAP.md`, `DEV_HANDOFF.md`, `CLAUDE_HANDOFF.md`, `STORE_RULES.md` status, `CHANGELOG.md` |

---

## 17. What this plan does not do

- It does not build anything. No code, no schema, no deploy.
- It does not decide the open questions in §15.
- It does not add real-money purchases, skins, gems or a battle pass.
- It does not add a public leaderboard, trading, an auction house or cross-player item transfers.
- It does not add Steam/Apple/Google login; it leaves the door open.
- It does not change PvE gameplay. PvE is today's solo raid with a new name.
- It does not promise that device accounts stop determined cheaters; they raise the cost and close the easy holes.

---

## 18. Related docs

- `docs/ROADMAP.md` — the Stash update entry (the owner's brief and the store constraints).
- `docs/MULTIPLAYER_PLAN.md` — how online play, the server and the matchmaker got here.
- `docs/DEV_HANDOFF.md` — the code map, hosting and gotchas.
- `docs/CLAUDE_HANDOFF.md` — how the owner works and why things were built this way.
- `docs/STORE_RULES.md` §3-4 — privacy, data and accounts.
- `docs/SOUND_2_PLAN.md` — the previous plan, as a model for the level of detail.
- `docs/STASH_TRADER_PLAN.md` — the original stash/trader design (0.4.0).
