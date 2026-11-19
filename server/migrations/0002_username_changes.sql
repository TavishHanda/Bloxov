-- 0.36.25: players can change their PvP username, once every RENAME_DAYS (server/src/api.js). When it last changed.
alter table accounts add column username_changed_at timestamptz;
