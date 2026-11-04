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
- **PvP starts with its own separate starter kit**, not the solo one. The contents are in §4.6; the only open number is
  how many of the three Hound sets also get armor, helmet and a medium backpack.
- **Economy is per-stash; look and tutorial are account-wide.** Money, stash, loadout, stats, traders, quests, levels
  and presets are separate; the character look and the tutorial are shared.
- **Online needs a real account; PvE needs none.** PvE stays local and accountless forever. PvP requires signing in.
- **Credentials can be linked, and only one session is active at a time.** The base credential is a username and
  password; email is **optional**; Steam links later. §8 explains the model and why the device secret became a
  remember-me token instead of an identity.

**Decisions recorded 2026-11-04 (second round):**
- **Reconnect window: yes, 2 minutes.** Disconnecting does not instantly kill the player; the body stays in the raid
  for 2 minutes and the same account can resume. After that it resolves as death.
- **Server crash: restore the pre-raid loadout.** If the restore ever proves unreliable, fall back to resolving it as
  `left` (gear lost) rather than leaving the profile stuck.
- **Account deletion: 30-day grace.** Sessions are revoked immediately, the stash is inaccessible during the grace,
  and the player can cancel by signing in. Hard delete after 30 days.
- **Bans: yes.** 24 hours, then 7 days, then permanent.
- **Names: display name is changeable and non-unique.** The username stays the immutable login handle.
- **No playtester grant.** The current stash becomes the solo stash; PvP starts fresh for everyone.
- **Online export: yes.** Read-only JSON download, no import.
- **Hosting cost: approved.**
- **Release shape: incremental 0.31.x.** Phase 1 can ship early; Phase 2 is 0.31.0.
- **Starter kit: the A list plus 5 bandages and 2 medkits, with one ready kit** (one set of light armor, an old helmet
  and a medium backpack). §4.6 has the contents and the pricing.

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
| Account | none, ever | a real account (username + password; Steam link later) |
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

### 4.6 The PvP starter kit (decided)

**Decided 2026-11-04: PvP starts with its own kit, not the solo one.** The point is that PvP starts poorer and tenser
than PvE, so the first good extract matters. The solo kit stays exactly as it is (Hound AK, medium backpack, 60 rifle
rounds, a bandage).

**Decided 2026-11-04 — the A list plus meds:**

| Item | Count | Why |
| --- | --- | --- |
| Hound (`ak`), loaded | 3 | one ready, two spare, so losing a gun does not end the session |
| Stinger (`pistol`), loaded | 5 | sidearm plus spares |
| Red Dot (`red_dot`) | 3 | one per Hound |
| Foregrip (`foregrip`) | 3 | one per Hound |
| Extended Mag (`ext_mag`) | 3 | one per Hound |
| Suppressor (`suppressor`) | 1 | a nice find to use or keep |
| Hound Rounds (`rifle_ammo`) | 360 | three magazines per Hound |
| Stinger Rounds (`pistol_ammo`) | 250 | five magazines |
| Bandage | 5 | |
| Medkit | 2 | |
| Energy Drink | 3 | |
| Small Backpack (`backpack_small`) | 1 | |
| Light Armor (`armor_light`) | see below | |
| Old Helmet (`helmet_basic`) | see below | |
| Medium Backpack (`backpack_medium`) | see below | |
| Money | **$50,000** | the buffer that lets a bad raid be rebuilt |

**Ready kits: decided one.** Each Hound set can also get light armor, an old helmet and a medium backpack. The
alternatives were priced with the game's own `Traders.buy_price` (1.56× value) and rejected:

| Ready kits | Gear cost | With $50k | Cells used | Quick raids of value |
| --- | --- | --- | --- | --- |
| **1 (decided)** | $154,128 | $204,128 | 90 | 6.8 |
| 2 (rejected) | $180,648 | $230,648 | 112 | 7.6 |
| 3 (rejected) | $207,168 | $257,168 | 134 | 8.5 |

For comparison, the economy sim's "really good" kit is $125,112, and a quick raid brings home about $30,200. Three
ready kits is roughly twice the best kit the sim models, uses 134 of the 160 starting stash cells before any loot, and
makes armor disposable. **One ready kit** keeps the three Hounds and five Stingers as the "lose two, still fight"
buffer, and the $50k rebuys armor and meds.

- **Every starter item carries the `free` flag** (`ItemStack.FREE`), so it cannot be sold to a trader. Otherwise a
  fresh account is a ~$75k payday. The $50k cash is the only spendable money.
- **The one-time starter kit is separate from the repeatable free kit.** The free kit stays as today (Stinger, 30
  rounds, bandage, small backpack), still one per raid, only when empty, and still unsellable.
- **Trader side effect:** $50k spent at Ponta reaches level 3 (the threshold is $40k), unlocking the Lancer, 4x/8x
  scopes and suppressor. If that feels too fast, lower the cash to ~$30k; the gear is the part that matters.
- **Stash space:** the online stash starts at 8x20 (160 cells). One ready kit leaves about 102 free cells after
  equipping, which fits a quick raid's haul (~$30k). Three ready kits leave 58, which is tight on the first raid.

---

## 5. Architecture

### 5.1 The pieces

```
Browser / desktop client (Godot)
   |  WSS: game traffic; the session token is sent once in _hello
   v
Game server (Godot --server, Heroku dyno, the "web" process)
   |  HTTP over 127.0.0.1 with a service token
   v
Stash API (small companion service, same dyno)
   |  TLS, DATABASE_URL
   v
Heroku Postgres
```

- **Client:** unchanged transport (`WebSocketMultiplayerPeer`, `wss://`). It gains a login screen, a remember-me
  session token, a mode, and a read-only view of the online profile.
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

Two separate things: the **account** (username + password) and the **session** (a remember-me token). Keeping them
apart is what lets the browser stay convenient without the account being hostage to `localStorage`.

1. **Sign up (first time online):** the login screen asks for a username and a password (email is optional and is not
   asked for in 0.31.0). The client sends them over WSS; the game server calls `POST /v1/accounts` on the API. The API
   hashes the password (Argon2id), creates the account and a fresh online profile, and returns `account_id`, a one-time
   **recovery code** (shown once, never again), the profile, and a session token.
2. **Sign in:** username + password → `POST /v1/login` → the password is verified against the hash → the API returns
   the profile and a new session token.
3. **Remember me:** the client stores the session token in `user://session.json` (mirrored to
   `localStorage["bloxov_session"]` on web) and sends it instead of the password on later launches. This is the old
   "device secret", now demoted: it is a session you can revoke, not the account itself.
4. **Every economy/raid call** goes from the game server to the API with the **service token** and the `account_id`
   from the session. The client never talks to the API and never sees the service token.
5. **Recovery:** the one-time recovery code, or the optional verified email, lets the player set a new password. A reset
   revokes every session, including the one on the device that asked.
6. **Delete:** the client asks the game server, which calls `DELETE /v1/account/:id`; the API deletes the account and
   profile; the client clears its session file and returns to PvE.

**Why the token is sent only once:** after `_hello`, the connection itself is the session. Re-sending the token on
every RPC would put it in more logs and packets for no gain. The server binds the peer id to the account id for the
life of the connection.

**What the server stores:** an **Argon2id hash** of the password and a **SHA-256 hash** of each session token. Never
the plaintext of either. A session token is 32 random bytes, so a fast hash is enough; a password is low-entropy, so it
needs a slow one. The plaintext password exists only in the login form's memory and is never logged.

**What this fixes:** clearing the browser no longer destroys the account. The stash is on the server, and the player
can sign in again with a username and password from any device. The remember-me token only decides whether they have
to type the password.

### 5.4 Session and concurrency

- One **active session per account** (owner decision 2026-11-04). A second sign-in is refused with "This account is
  playing in another tab or on another device." The sign-in screen offers **TAKE OVER HERE**, which revokes the other
  session.
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
-- One row per account. The password is the base credential; email is optional.
create table accounts (
  id               uuid primary key default gen_random_uuid(),
  username         text not null,                -- unique, case-insensitive
  display_name     text not null default '',     -- filtered by NameFilter before it is stored
  password_hash    text not null,                -- Argon2id
  email            text,                         -- optional; null until the player adds one
  email_verified   boolean not null default false,
  recovery_hash    text,                         -- one-time recovery code (SHA-256)
  recovery_used_at timestamptz,
  look             jsonb not null default '{}',  -- account-wide (decided)
  tutorial         jsonb not null default '{}',  -- account-wide (decided)
  failed_logins    int not null default 0,
  locked_until     timestamptz,
  banned_until     timestamptz,
  ban_reason       text,
  ban_count        int not null default 0,
  created_at       timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),
  deleted_at       timestamptz
);
create unique index accounts_username on accounts (lower(username));
create unique index accounts_email on accounts (lower(email)) where email is not null;

-- Linked external identities. Steam now; Discord/Google later use the same shape.
create table credentials (
  id          bigserial primary key,
  account_id  uuid not null references accounts(id) on delete cascade,
  kind        text not null,                     -- 'steam' (later 'discord' | 'google')
  external_id text not null,                     -- the provider's stable id
  created_at  timestamptz not null default now(),
  revoked_at  timestamptz
);
create unique index credentials_external on credentials (kind, external_id) where revoked_at is null;
create index credentials_account on credentials (account_id);

-- Remember-me sessions. Tokens are 32 random bytes, so a fast hash is enough.
create table sessions (
  id           uuid primary key default gen_random_uuid(),
  account_id   uuid not null references accounts(id) on delete cascade,
  token_hash   text not null,                    -- SHA-256 of the token
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at   timestamptz not null,
  revoked_at   timestamptz
);
create unique index sessions_token on sessions (token_hash);
create index sessions_account on sessions (account_id);

-- The online profile: one row per account. Everything the solo profile keeps, minus settings.
create table profiles (
  account_id      uuid primary key references accounts(id) on delete cascade,
  revision        bigint not null default 1,
  money           bigint not null default 50000,  -- PvP starting money (§4.6); the game server sends the real fresh profile
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
- The API's profile response joins `accounts.display_name`, `accounts.look` and `accounts.tutorial` into the profile
  object the game server sees, so the client keeps one profile shape.
- The column defaults (money, stash size, stats) are a safety net only. On account creation the game server sends a
  fresh profile built from the PvP starter kit and money (§4.6), so the starting numbers stay in one place (GDScript)
  and cannot drift from the schema.
- `look` and `tutorial` on `accounts` are the decided account-wide fields. If the owner changes their mind, move
  them to `profiles`; the schema is otherwise unchanged.
- `raid_snapshot` is only the loadout, not the stash. The stash does not change during a raid (loot is carried, then
  written back at the end), so the loadout is enough to restore a crash.
- **No item table.** A stash is at most a few hundred stacks (<50 KB); `jsonb` is simpler and fast enough. If the game
  ever needs cross-player item queries (trading, an auction house), revisit it.
- **Passwords are hashed, never stored.** Argon2id with a per-row salt (the `argon2` library handles the salt). Login
  is rate-limited per account and per IP hash; `failed_logins` and `locked_until` implement a lockout. A password is
  never logged, never sent to the game server in plaintext beyond the login call, and never included in an export.
- **Email is optional.** `email` is null until the player adds one; `email_verified` gates whether it can be used for
  reset. An account with no email still works and still has a recovery code.

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
- **Inactive accounts:** proposed cleanup after 12 months with no `last_seen_at`. If the account has a verified email,
  send one warning first; if not, there is no way to warn. Alternative: never delete. **Owner decision.** For now, do
  not auto-delete; revisit before launch.
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
| `set_name(name)` | `NameFilter` | sets the display name |
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

- **Player disconnects mid-raid:** the server keeps the body for the 2-minute reconnect window (§7.6), then resolves
  the result as `left`/`killed`; gear is lost. The client is told before it can leave ("Leaving loses your gear").
- **Reconnect window (decided 2026-11-04: yes, 2 minutes):** keep the body and the profile `in_raid` for **2
  minutes**; if the same account reconnects, resume. This needs a resume path in `net_raid.gd` and the matchmaker.
  The body stays lootable while the player is away, so reconnecting is a risk, not a free save. If the window
  expires, the server resolves it as death.
- **Server crash / Heroku restart:** on boot, the game server has a new boot id. Any profile with `raid_state =
  'in_raid'` and a `raid_id` from a previous boot is an orphan.
  - **Decided 2026-11-04: restore `raid_snapshot`** (the pre-raid loadout) and mark the result `crash`. The player
    did nothing wrong, and the alternative (losing gear to a Heroku restart) is the kind of thing that makes people
    quit.
  - **Fallback:** if restoring ever proves unreliable, resolve the orphan as `left` (gear lost) instead of leaving
    the profile stuck in `in_raid`. Never leave an account unable to start a raid.
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
- **The honest limitation:** sign-up is free and needs no email, so a banned player can make a new account. Bans are a
  speed bump, not a wall. Say this to the owner. Mitigations:
  - Rate-limit account creation per hashed IP (privacy-sensitive; ask).
  - Link Steam later (the roadmap already says "Steam login can be linked later"); a Steam-linked account is much
    harder to replace.
  - Keep the server authoritative so a new account does not inherit cheated gear.
- **What the server still trusts (until L4):** item durability/attachments at extract, and the client's own health
  application (it reports damage taken). The existing god-mode check covers the worst case.

---

## 8. Accounts

### 8.1 Two rules

- **PvE never has an account.** The solo profile is a file on the device. Nothing about it touches the API, and no
  login screen ever appears for a player who only plays PvE. This keeps the store rule (`STORE_RULES.md` §4: do not
  force an account for offline solo) and the "works on a plane" promise.
- **PvP always has an account.** It is created on first sign-up, and it is what the online stash hangs from. No silent
  accounts, no invisible device identity.

The account is created on the server the first time the player signs up, not at launch.

### 8.2 Sign-up

The sign-up screen asks for three things:

| Field | Rule |
| --- | --- |
| **Username** | 3–20 characters, `NameFilter`, unique case-insensitively, **immutable**. This is the login handle and is never shown to other players. |
| **Password** | At least 10 characters, checked against a short common-password list, no forced symbol rules. Stored as an Argon2id hash. |
| **Recovery code** | Generated by the server, shown **once**, 12 characters like `K7QP-3M9X-2RT`. Hashed with SHA-256. The player ticks "I saved it" before the screen closes. |

- **Email is optional, and 0.31.0 does not ask for it.** The `email` column exists so an "add email" flow can land
  later without a migration, but collecting an address before there is a mail sender would be PII with no use. When
  email delivery ships, sign-up and the account panel gain an optional field, and it is only usable for reset once
  verified. This honours the owner's "optional, not required" answer.
- After sign-up the API creates the account, a fresh online profile with the PvP kit (§4.6), and the first session.
- The username is the handle; `display_name` is the name other players see (§8.7). Splitting them means a player can
  change how they appear without changing how they log in, and it removes the rename problem entirely.

### 8.3 Sign-in and sessions

- Sign-in is username + password. The API verifies the Argon2id hash and returns the profile plus a **session token**.
- **Remember me** is on by default, with a "this is a shared device" checkbox that turns it off.
- The token is 32 random bytes. It is stored in `user://session.json` and mirrored to
  `localStorage["bloxov_session"]` on web. It expires after 30 days of no use (sliding), and it is revoked by a
  password change, "sign out everywhere", or account deletion.
- **This is the old device secret, demoted.** It is a session, not an identity. Clearing the browser loses the token,
  not the account: the player signs in again with the username and password.
- **One active session per account** (owner decision 2026-11-04). A second sign-in is refused with "This account is
  playing in another tab or on another device", and the screen offers **TAKE OVER HERE**, which revokes the other
  session. Take-over is the default because a crashed tab must not lock an account.
- **Lockout:** 10 failed attempts locks the account for 15 minutes (`failed_logins`, `locked_until`). Login is also
  rate-limited per hashed IP. The error is always "wrong username or password", never "no such user".

### 8.4 Password reset and recovery

- **With the recovery code:** enter username + code → set a new password. The code is burned, every session is
  revoked, and a new code is issued and shown once.
- **With a verified email (later):** the same flow with a one-time link instead of the code.
- **With neither:** the online account is gone. There is no support override, no security questions and no manual
  reset. The sign-up screen says this in one sentence, and the account panel repeats it.
- The solo stash is untouched by any of this. Losing the online account costs online progress only.
- The recovery code is not a "transfer code": it does not move a device, it resets a password. Moving devices is just
  signing in.

### 8.5 Why this beats the device secret

| Situation | Silent device secret (old proposal) | Real account (this plan) |
| --- | --- | --- |
| Clear browser data | Account gone | Sign in again, stash intact |
| New laptop or phone | Account gone unless a transfer code was made | Sign in |
| Private/incognito window | New empty account | Sign in (or use remember-me) |
| Safari evicts storage after ~7 days idle | Account gone | Sign in again |
| Forgot the credential | Account gone | Recovery code resets it |
| Two tabs | Ambiguous | One session, take-over |
| Cheater banned | Makes a new device account in seconds | Makes a new account, but the barrier is higher and Steam linking raises it further |

The cost is a login screen for PvP, a password to remember, and password hashing on the server. That is the trade the
owner asked for: PvE stays accountless, PvP gets a real account.

### 8.6 Deletion

- **DELETE ONLINE ACCOUNT** in the account panel, behind a typed confirmation (`DELETE`) and a clear list of what
  goes: the online stash, money, loadout, stats, traders, quests, presets, the account, its sessions and any linked
  credentials.
- The solo profile is not touched. Say so on the same screen.
- The API marks the account deleted in one transaction; the hard delete runs after the grace period.
- **Store rule:** deletion must be available **inside the game** (Apple 5.1.1(v), Google's account deletion policy).
  A web deletion link is also required by Google; add a page under `web/` in the launch phase.
- **Decided 2026-11-04: a 30-day grace period.** Deleting sets `deleted_at`, revokes every session and every linked
  credential immediately, and makes the stash inaccessible. Signing in during the grace shows one screen only:
  "This account is scheduled for deletion on <date>." with **CANCEL DELETION**; the stash is not shown. A daily job
  hard-deletes `profiles`, `raid_results`, `sessions`, `credentials` and the `accounts` row after 30 days, in one
  transaction. The store text must say 30 days, how to cancel, and that Heroku's backups may keep a copy for a few
  days after that. The solo profile is never part of it.

### 8.7 Names

- **`username`** is the login handle: unique, immutable, filtered, never shown to other players.
- **`display_name`** is what the raid shows: filtered, changeable, **not** unique. Two players can be "Tavish".
- If duplicate display names get confusing in the kill feed, add a short discriminator later (`Tavish#4821`) without
  touching the login handle.
- The display name is sent to other players in the raid, as today. It is not shown on a public leaderboard (there
  isn't one).

### 8.8 Linked credentials: Steam now-in-schema, Discord/Google later

An account can have more than one way in. The password is the base; everything else is a link.

| Credential | Status | Good for |
| --- | --- | --- |
| Username + password | 0.31.0 | every player, every platform |
| Recovery code | 0.31.0 | password reset without email |
| Email (optional) | later | self-serve reset, inactive-account warning |
| Steam ID | schema now, ships with the Steam build | Steam players, cross-platform login |
| Discord / Google | later, only if asked | convenience; not needed for launch |

**Why own login first:** it is the only door that works for a browser player with no Steam and no social account, and
it is the only one that does not add a third-party processor to the privacy policy.

**Steam specifics:** Steam uses **OpenID 2.0**, not OAuth. The flow validates the asserted SteamID with Steam's server,
then inserts a `credentials` row (`kind = 'steam'`, `external_id` = the 64-bit SteamID). No password is stored for
Steam.

- **Browser → Steam:** sign in with username + password, then **LINK STEAM**. Same account, same stash.
- **Steam → browser:** sign in with the password, or reset it with the recovery code. There is no "transfer" step.
- **A pure Steam player:** signs in with Steam, then sets a username and password once, so the account is not hostage
  to Steam.
- Steam is a **link, not a replacement**. Revoking it leaves the password working.

**Discord / Google:** same table, new `kind`. Not now, because each one needs a provider app, redirect URIs,
privacy-policy text and a 13+ age floor, and none recovers an account better than the recovery code already does. On
iOS, adding any third-party social login also triggers Apple 4.8 (Sign in with Apple), which is real cost for a small
game. The schema is additive, so this is a later decision, not a migration.

**One active session still applies.** Linking a credential does not let two devices play at once; it lets one account
be reached from more places. A second sign-in takes over.

**What this means for the build:**

- `accounts` holds the username, password hash, optional email and recovery hash; `credentials` holds linked
  providers; `sessions` holds remember-me tokens.
- 0.31.0 ships password + recovery code only. The Steam button is hidden until the Steam build exists.
- There is no transfer code anywhere in the design.

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
- **Decided 2026-11-04: yes.** The online profile can be **exported** as a read-only JSON file (stash, money, loadout,
  stats, traders, quests, presets) but **not imported** by the player. An import would be an obvious cheat vector; a
  support tool can do it server-side if ever needed. The export is the "download my data" path for privacy requests.
- Add a line to the backup UI: "This file is your PvE stash. PvP is saved on the server."
- Test: restoring a backup while in PvP does not change the online stash, and does not leave the UI showing stale
  online data.

### 9.5 Rollback

- If the update has to be rolled back, the solo profile is untouched, so PvE is safe.
- The online profile lives in Postgres; a rollback of the game server leaves the rows in place. The previous server
  ignores them. No data is lost.
- The client's `session.json` is harmless if the feature is off.
- The feature flag (`PvP online enabled`) lets the owner turn it off without a deploy if something goes wrong. Keep it
  in a server env var and in `GameSettings` for the client (hidden in release builds).

---

## 10. UI and UX

### 10.1 The hideout

- **Top bar:** `PvE (SOLO) | PvP (ONLINE)` segmented switch, the active stash's money, and a short line:
  "PvE: on this device, works offline. PvP: online, saved on the server."
- **PvE:** exactly today's hideout. Stash, loadout, traders, quests, START RAID.
- **PvP, not connected:** the switch shows the sign-in panel (username, password, SIGN IN / CREATE ACCOUNT). The stash
  area is disabled with a "Sign in to see your PvP stash" message.
- **PvP, connected:** the same hideout layout, reading the online profile. The ONLINE button shows the party/queue
  state as today.
- **PvP, reconnecting:** the last profile stays visible, read-only, with a banner and a RETRY button. Economy actions
  are disabled. Do not fall back to solo.
- **Account panel** (from the ONLINE panel): username, display name, **sign out**, **sign out everywhere**, **new
  recovery code**, delete account, export online data, link Steam (later).

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
- **Signed in elsewhere:** "This account signed in on another device." Offer **TAKE OVER HERE** or cancel.
- **Wrong password / locked:** "Wrong username or password." After 10 tries, "Too many attempts. Try again in 15
  minutes." Never reveal whether the username exists.
- **Server full:** today's message stays.
- **API/DB down:** "PvP is unavailable right now. PvE still works." A RETRY button.
- **Deleted account:** clear the cache, return to PvE, show "Your PvP account was deleted. Your PvE stash is safe."

### 10.4 Privacy page

`scripts/title_screen.gd:20-34` currently says "No accounts" and "Nothing is kept after the raid". Both become false.
The launch phase must update it to say:

- What the online account is (a username, a display name, a password hash, a look, progress; an email only if the
  player chooses to add one later).
- What is stored (the online stash, money, stats, traders, quests, last seen, session records).
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
- The sign-in screen shell and the session-token storage (no server call yet).
- The `Profile` mode guards and the SaveBackup solo-only change.
- Tests: mode switching, solo save isolation, backup isolation.
- **Exit:** PvE is unchanged; the switch exists but PvP is not reachable in release builds.
- **Note:** this phase alone is a safe, small release if the owner wants to see the UI early.

### Phase 2 — accounts, database, online stash at raid boundaries (0.31.0)

- The `server/` API, the Postgres schema, migrations, the sidecar entrypoint, the Dockerfile change, CI.
- Sign-up, sign-in, remember-me sessions, recovery code, sign out everywhere, delete.
- Password hashing, login rate limits and lockout.
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
- The 2-minute reconnect window (decided).
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

- `accounts`: sign-up creates an account and a recovery code; the password is never stored or logged in plaintext; a
  second launch reuses the session token; sign-out clears it.
- `account_login`: wrong password is refused without revealing the username; 10 failures lock the account; the lock
  expires; a valid login returns the profile.
- `account_session`: a second sign-in is refused; take-over revokes the first; an expired or revoked token is refused.
- `account_recovery`: the recovery code resets the password, revokes every session and issues a new code; a used or
  wrong code is refused.
- `mode_switch`: SOLO and ONLINE show independent stashes; a solo save does not write online data; an online sync does
  not touch `user://profile.json`; a solo raid cannot start in online mode and vice versa.
- `online_profile`: first login creates a fresh profile; the solo profile is untouched; the server's profile replaces
  the cache.
- `online_kit`: the server issues the kit; a client-sent kit is ignored; a fabricated item is rejected.
- `online_raid`: extract persists the carried items; death keeps only the secure pocket; MIA and leave behave like
  death; a disconnect loses gear.
- `online_economy` (Phase 3): buy/sell/move/equip/upgrade/quest/level/preset round-trips; stale revision rejected;
  insufficient money rejected; full stash rejected.
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
- Cover: migrations, sign-up/login, password hashing, session tokens, recovery, lockout, delete, revision conflicts,
  raid start/end transactions, ban checks, rate limits.
- Run it on every push that touches `server/`.

### 12.4 End-to-end

- One CI job: Postgres + API + Godot `--server` + a scripted client. It signs up, signs in, starts a raid, extracts,
  dies, takes over a session, resets a password and deletes the account, and checks the DB. This is the test that
  catches the bugs the in-process tests cannot.
- The existing `net`/`pvp`/`online_ai`/`online_loot` sections run with the fake API.
- The real-process test from `DEV_HANDOFF.md` §4.6 (a `--server` process + two clients) still applies; add an account
  login step.

### 12.5 Manual checks before release

- A fresh browser profile: PvE works with the network off; PvP creates an account; the explainer appears once.
- A playtester's existing save: the stash is intact in PvE; PvP starts fresh.
- A dyno restart mid-hideout: reconnect works; the stash is the same.
- A dyno restart mid-raid: the crash policy restores the pre-raid loadout.
- Two tabs: the second is refused or takes over, and items are not duplicated.
- Transfer: sign in on a second browser and the stash is there; taking over signs the first one out.
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
| **Cheating** | Accounts are free to create; L4 is not in 0.31.0 | Server authority at every level; rate limits; bans; Steam linking later; be honest with the owner |
| **Latency** | Every hideout action round-trips | Optimistic UI, debounce, full-profile sync at this scale |
| **Heroku limits** | One dyno, ephemeral disk, daily restart, Postgres connections | Sidecar, pool, no local disk, orphan policy, backup drill |
| **Two sessions** | Duplication across tabs/devices | One active session, revision checks, take-over flow |
| **SaveBackup** | A restore could wipe the online stash | Solo-only backups; online export is read-only; test it |
| **Store/privacy** | Accounts change what is collected | Update the privacy page, the Apple label, the Google form, deletion, the web link; do it before launch |
| **PvE feels worthless** | Players may resent a separate online stash | Say it clearly; no playtester grant (decided); keep PvE fully playable |
| **Name confusion** | Duplicate names in the kill feed | Discriminator later; `NameFilter` now |
| **Account loss** | A forgotten password with no recovery code and no email | Say so at sign-up; recovery code; optional email later; Steam linking later |
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
- [ ] All traffic is `wss://`/`https://`; Postgres uses TLS; passwords are hashed with Argon2id; session and
      recovery tokens are hashed at rest.
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
3. **PvP starter kit:** a **separate** kit, not the solo one. Contents in §4.6: the A list plus 5 bandages, 2 medkits
   and **one ready kit** (one light armor, one old helmet, one medium backpack).
4. **Per-stash vs account-wide:** money, stash, loadout, stats, traders, quests, levels and presets are **per-stash**;
   look and tutorial are **account-wide**.
5. **Online accounts:** PvE stays **completely accountless**. PvP requires a **real account** — no silent device
   account.
6. **Credentials:** username + password is the base. **Email is optional** and is not collected in 0.31.0 (it arrives
   with the mail sender). A one-time recovery code handles reset. **Steam links later**; Discord/Google are later
   additions to the same table, not launch scope.
7. **Sessions:** **one active session per account.** A second sign-in offers TAKE OVER HERE.
8. **The device secret is gone.** It became a remember-me session token: revocable, expiring, and never the identity.
   The transfer code is gone with it; moving devices is just signing in.
9. **Reconnect window:** yes, **2 minutes**. The body stays lootable; expiry resolves as death.
10. **Server crash:** **restore the pre-raid loadout** and mark it `crash`. If the restore proves unreliable, resolve
    it as `left` (gear lost) instead of leaving the account stuck.
11. **Account deletion:** **30-day grace**, cancellable by signing in; sessions and stash access are cut immediately;
    hard delete after 30 days.
12. **Bans:** **yes.** 24 hours, then 7 days, then permanent.
13. **Names:** `username` is the immutable login handle; `display_name` is changeable and **not unique**.
14. **Playtesters:** **no grant.** The current stash becomes the solo stash; PvP starts fresh for everyone.
15. **Online export:** **yes**, read-only JSON; **no import**.
16. **Hosting cost:** **approved** (Heroku Postgres on top of the dyno).
17. **Release shape:** **incremental 0.31.x.** Phase 1 can ship early; Phase 2 is 0.31.0.

### Still open

1. **Inactive account cleanup:** never delete, or delete after 12 months with no `last_seen_at` (with a warning when
   there is a verified email)?
   *My pick: never auto-delete for now; revisit before launch.*

---

## 16. File-by-file impact map (for the build)

This is what the update will touch. It is here so a future session can estimate the work without re-reading everything.

| File | Change |
| --- | --- |
| `scripts/profile.gd` | `mode`, online profile swap, mode guards on `save_profile`, the operation helpers; keep `VERSION = 1` for solo |
| `scripts/save_backup.gd` | solo-only `pack`/`apply`; a note in the UI; tests |
| `scripts/hideout.gd` | the SOLO/ONLINE switch, the account panel, the online profile view, the one-time explainer, the economy intents |
| `scripts/title_screen.gd` | the privacy text |
| `scripts/net.gd` | `_hello` with the session token, `profile_sync`, the economy RPCs, the server-issued kit, the raid start/end API calls, ban checks |
| `scripts/account_ui.gd` (new) | sign-up, sign-in, recovery code, take-over, sign out everywhere, delete |
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
- It does not add Steam/Apple/Google login **in 0.31.0**; Steam is reserved in the schema and ships with the Steam
  build, and Discord/Google are later additions.
- It does not change PvE gameplay. PvE is today's solo raid with a new name.
- It does not promise that accounts stop determined cheaters; they raise the cost and close the easy holes.

---

## 18. Related docs

- `docs/ROADMAP.md` — the Stash update entry (the owner's brief and the store constraints).
- `docs/MULTIPLAYER_PLAN.md` — how online play, the server and the matchmaker got here.
- `docs/DEV_HANDOFF.md` — the code map, hosting and gotchas.
- `docs/CLAUDE_HANDOFF.md` — how the owner works and why things were built this way.
- `docs/STORE_RULES.md` §3-4 — privacy, data and accounts.
- `docs/SOUND_2_PLAN.md` — the previous plan, as a model for the level of detail.
- `docs/STASH_TRADER_PLAN.md` — the original stash/trader design (0.4.0).
