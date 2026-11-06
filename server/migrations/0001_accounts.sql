-- Stash update (0.31): PvP accounts and the online stash. docs/STASH_UPDATE_PLAN.md section 6.
-- The game server owns the item rules; this database only stores what it is told, in the saved-profile shape.

create table accounts (
  id               uuid primary key default gen_random_uuid(),
  username         text not null,
  display_name     text not null default '',
  password_hash    text not null,
  email            text,
  email_verified   boolean not null default false,
  recovery_hash    text,
  look             jsonb not null default '{}',
  tutorial         jsonb not null default '{}',
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

create table credentials (
  id          bigserial primary key,
  account_id  uuid not null references accounts(id) on delete cascade,
  kind        text not null,
  external_id text not null,
  created_at  timestamptz not null default now(),
  revoked_at  timestamptz
);
create unique index credentials_external on credentials (kind, external_id) where revoked_at is null;
create index credentials_account on credentials (account_id);

create table sessions (
  id           uuid primary key default gen_random_uuid(),
  account_id   uuid not null references accounts(id) on delete cascade,
  token_hash   text not null,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at   timestamptz not null,
  revoked_at   timestamptz
);
create unique index sessions_token on sessions (token_hash);
create index sessions_account on sessions (account_id);

-- The online profile in the game's saved shape (Profile.save_text without look/tutorial), plus the raid state.
create table profiles (
  account_id      uuid primary key references accounts(id) on delete cascade,
  revision        bigint not null default 1,
  data            jsonb not null,
  raid_state      text not null default 'idle',
  raid_id         text,
  raid_started_at timestamptz,
  raid_snapshot   jsonb,
  updated_at      timestamptz not null default now()
);

create table raid_results (
  id          bigserial primary key,
  account_id  uuid not null references accounts(id) on delete cascade,
  raid_id     text not null,
  result      text not null,
  loot_value  int not null default 0,
  created_at  timestamptz not null default now()
);
create index raid_results_account on raid_results (account_id, created_at desc);
