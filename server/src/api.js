'use strict';
// Bloxov's Stash API (Stash update, 0.31; docs/STASH_UPDATE_PLAN.md sections 5-8).
//
// Only the Godot game server talks to it, over 127.0.0.1 with a service token: players never reach it. It knows
// nothing about items: the game server checks those (ItemDB lives in GDScript) and this stores the online profile in
// the game's own saved shape. What it does own: accounts, password hashes, remember-me sessions, recovery codes,
// lockouts, bans, deletion, and the revision that stops two writers overwriting each other.
//
// Passwords: scrypt (Node's built-in, memory-hard; no native packages to build on the server image). The plan said
// Argon2id; scrypt is the other hash OWASP recommends, and switching later only needs a prefix check on login.

const crypto = require('node:crypto');

const SCRYPT = { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };
const SESSION_DAYS = 30;
const LOCK_AFTER = 10;
const LOCK_MINUTES = 15;
const DELETE_GRACE_DAYS = 30;
const INACTIVE_MONTHS = 12;
const BAN_STEPS_HOURS = [24, 24 * 7]; // then permanent (owner, 2026-11-04)
const USERNAME_RE = /^[A-Za-z0-9_.-]{3,20}$/;
const COMMON_PASSWORDS = new Set([
  'password', 'password1', 'password12', 'password123', '1234567890', '0123456789', '12345678910', 'qwertyuiop',
  'iloveyou12', 'qwerty1234', '1q2w3e4r5t', 'abcdefghij', 'aaaaaaaaaa', '1111111111', 'letmein123', 'welcome123',
  'football12', 'baseball12', 'princess12', 'sunshine12', 'passw0rd12', 'bloxovbloxov', 'bloxov1234',
]);

class ApiError extends Error {
  constructor(code, status = 400, extra = {}) {
    super(code);
    this.code = code;
    this.status = status;
    this.extra = extra;
  }
}

function sha256(text) {
  return crypto.createHash('sha256').update(text).digest('hex');
}

function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const key = crypto.scryptSync(password, salt, 64, SCRYPT);
  return `scrypt$${SCRYPT.N}$${SCRYPT.r}$${SCRYPT.p}$${salt.toString('base64')}$${key.toString('base64')}`;
}

function checkPassword(password, stored) {
  const parts = String(stored).split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const [, N, r, p, salt, key] = parts;
  const want = Buffer.from(key, 'base64');
  const got = crypto.scryptSync(password, Buffer.from(salt, 'base64'), want.length,
    { N: Number(N), r: Number(r), p: Number(p), maxmem: SCRYPT.maxmem });
  return crypto.timingSafeEqual(want, got);
}

// A hash to compare against when the username doesn't exist, so a wrong name takes as long as a wrong password.
const DUMMY_HASH = hashPassword(crypto.randomBytes(12).toString('hex'));

// 12 characters like K7QP-3M9X-2RTW, no 0/O/1/I to misread.
function newRecoveryCode() {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.randomBytes(12);
  let out = '';
  for (let i = 0; i < 12; i++) {
    if (i && i % 4 === 0) out += '-';
    out += letters[bytes[i] % letters.length];
  }
  return out;
}

function cleanCode(code) {
  return String(code || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

function checkNewPassword(password) {
  if (typeof password !== 'string' || password.length < 10) throw new ApiError('weak_password');
  if (password.length > 128) throw new ApiError('weak_password');
  if (COMMON_PASSWORDS.has(password.toLowerCase())) throw new ApiError('common_password');
}

function checkProfile(profile) {
  if (!profile || typeof profile !== 'object' || Array.isArray(profile)) throw new ApiError('bad_profile');
  if (JSON.stringify(profile).length > 200000) throw new ApiError('bad_profile');
}

class StashApi {
  constructor(pool, { now = () => new Date() } = {}) {
    this.pool = pool;
    this.now = now;
  }

  async _tx(work) {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      const result = await work(client);
      await client.query('commit');
      return result;
    } catch (err) {
      await client.query('rollback').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }

  async _newSession(db, accountId) {
    // One session per account (owner, 2026-11-04): signing in anywhere ends the others.
    await db.query('update sessions set revoked_at = now() where account_id = $1 and revoked_at is null', [accountId]);
    const token = crypto.randomBytes(32).toString('base64url');
    await db.query(
      `insert into sessions (account_id, token_hash, expires_at) values ($1, $2, now() + interval '${SESSION_DAYS} days')`,
      [accountId, sha256(token)]);
    return token;
  }

  async _signedIn(db, account, token, extra = {}) {
    const profile = await db.query('select * from profiles where account_id = $1', [account.id]);
    await db.query('update accounts set last_seen_at = now() where id = $1', [account.id]);
    const row = profile.rows[0];
    return {
      account_id: account.id,
      username: account.username,
      display_name: account.display_name,
      look: account.look,
      tutorial: account.tutorial,
      token,
      profile: row.data,
      revision: Number(row.revision),
      raid: { state: row.raid_state, id: row.raid_id, snapshot: row.raid_snapshot },
      ...extra,
    };
  }

  _gate(account) {
    if (account.banned_until && new Date(account.banned_until) > this.now()) {
      throw new ApiError('banned', 403, { until: account.banned_until, reason: account.ban_reason || '' });
    }
  }

  async signup({ username, password, display_name = '', profile }) {
    if (typeof username !== 'string' || !USERNAME_RE.test(username)) throw new ApiError('bad_username');
    checkNewPassword(password);
    checkProfile(profile);
    const code = newRecoveryCode();
    const hash = hashPassword(password);
    return this._tx(async (db) => {
      const taken = await db.query('select 1 from accounts where lower(username) = lower($1)', [username]);
      if (taken.rowCount) throw new ApiError('username_taken', 409);
      const made = await db.query(
        `insert into accounts (username, display_name, password_hash, recovery_hash) values ($1, $2, $3, $4) returning *`,
        [username, String(display_name).slice(0, 16), hash, sha256(cleanCode(code))]);
      const account = made.rows[0];
      await db.query('insert into profiles (account_id, data) values ($1, $2)', [account.id, profile]);
      const token = await this._newSession(db, account.id);
      return this._signedIn(db, account, token, { recovery_code: code });
    });
  }

  async login({ username, password, cancel_delete = false }) {
    if (typeof username !== 'string' || typeof password !== 'string') throw new ApiError('bad_login', 401);
    return this._tx(async (db) => {
      const found = await db.query('select * from accounts where lower(username) = lower($1) for update', [username]);
      const account = found.rows[0];
      if (!account) {
        checkPassword(password, DUMMY_HASH);
        throw new ApiError('bad_login', 401);
      }
      if (account.locked_until && new Date(account.locked_until) > this.now()) {
        throw new ApiError('locked', 429, { until: account.locked_until });
      }
      if (!checkPassword(password, account.password_hash)) {
        const fails = account.failed_logins + 1;
        if (fails >= LOCK_AFTER) {
          await db.query(`update accounts set failed_logins = 0, locked_until = now() + interval '${LOCK_MINUTES} minutes' where id = $1`, [account.id]);
        } else {
          await db.query('update accounts set failed_logins = $2 where id = $1', [account.id, fails]);
        }
        // (the failed count must stick even though the call fails)
        await db.query('commit');
        await db.query('begin');
        throw new ApiError('bad_login', 401);
      }
      await db.query('update accounts set failed_logins = 0, locked_until = null where id = $1', [account.id]);
      if (account.deleted_at) {
        if (!cancel_delete) {
          throw new ApiError('deleted', 403, { delete_on: new Date(new Date(account.deleted_at).getTime() + DELETE_GRACE_DAYS * 86400000).toISOString() });
        }
        await db.query('update accounts set deleted_at = null where id = $1', [account.id]);
      }
      this._gate(account);
      const token = await this._newSession(db, account.id);
      return this._signedIn(db, account, token);
    });
  }

  // Remember me: the token from an earlier sign-in. The 30 days start again each time it's used.
  async resume({ token }) {
    if (typeof token !== 'string' || token.length < 20) throw new ApiError('bad_session', 401);
    return this._tx(async (db) => {
      const found = await db.query(
        `select a.*, s.id as session_id from sessions s join accounts a on a.id = s.account_id
         where s.token_hash = $1 and s.revoked_at is null and s.expires_at > now() and a.deleted_at is null`, [sha256(token)]);
      const account = found.rows[0];
      if (!account) throw new ApiError('bad_session', 401);
      this._gate(account);
      await db.query(`update sessions set last_seen_at = now(), expires_at = now() + interval '${SESSION_DAYS} days' where id = $1`, [account.session_id]);
      return this._signedIn(db, account, token);
    });
  }

  async logout({ account_id }) {
    await this.pool.query('update sessions set revoked_at = now() where account_id = $1 and revoked_at is null', [account_id]);
    return { ok: true };
  }

  // A forgotten password: the one-time recovery code sets a new one, ends every session and gives a new code.
  async recover({ username, recovery_code, new_password }) {
    checkNewPassword(new_password);
    return this._tx(async (db) => {
      const found = await db.query('select * from accounts where lower(username) = lower($1) and deleted_at is null for update', [String(username)]);
      const account = found.rows[0];
      const given = sha256(cleanCode(recovery_code));
      if (!account || !account.recovery_hash
          || !crypto.timingSafeEqual(Buffer.from(given), Buffer.from(account.recovery_hash))) {
        throw new ApiError('bad_recovery', 401);
      }
      this._gate(account);
      const code = newRecoveryCode();
      await db.query('update accounts set password_hash = $2, recovery_hash = $3, failed_logins = 0, locked_until = null where id = $1',
        [account.id, hashPassword(new_password), sha256(cleanCode(code))]);
      const token = await this._newSession(db, account.id);
      return this._signedIn(db, account, token, { recovery_code: code });
    });
  }

  // Saves the online profile. `revision` must be the one it was based on (a stale write is refused with the stored
  // one). `raid` sets the raid state ({state, id, snapshot}); `result` adds a raid result line.
  async save({ account_id, revision, profile, raid = null, result = null, look = null, tutorial = null, display_name = null }) {
    checkProfile(profile);
    return this._tx(async (db) => {
      const found = await db.query('select revision from profiles where account_id = $1 for update', [account_id]);
      if (!found.rowCount) throw new ApiError('no_account', 404);
      const stored = Number(found.rows[0].revision);
      if (stored !== Number(revision)) throw new ApiError('conflict', 409, { revision: stored });
      const sets = ['data = $2', 'revision = revision + 1', 'updated_at = now()'];
      const values = [account_id, profile];
      if (raid) {
        values.push(raid.state === 'in_raid' ? 'in_raid' : 'idle', raid.id || null, raid.snapshot || null);
        sets.push(`raid_state = $${values.length - 2}`, `raid_id = $${values.length - 1}`, `raid_snapshot = $${values.length}`,
          raid.state === 'in_raid' ? 'raid_started_at = now()' : 'raid_started_at = null');
      }
      const saved = await db.query(`update profiles set ${sets.join(', ')} where account_id = $1 returning revision`, values);
      if (result) {
        await db.query('insert into raid_results (account_id, raid_id, result, loot_value) values ($1, $2, $3, $4)',
          [account_id, String(result.raid_id || ''), String(result.result || ''), Math.max(0, Math.trunc(Number(result.loot_value) || 0))]);
      }
      if (look || tutorial || display_name !== null) {
        await db.query(`update accounts set look = coalesce($2, look), tutorial = coalesce($3, tutorial),
          display_name = coalesce($4, display_name), last_seen_at = now() where id = $1`,
          [account_id, look, tutorial, display_name === null ? null : String(display_name).slice(0, 16)]);
      }
      return { revision: Number(saved.rows[0].revision) };
    });
  }

  // DELETE ONLINE ACCOUNT: sessions end now; the stash is gone after the 30-day grace (signing in can cancel it).
  async remove({ account_id }) {
    return this._tx(async (db) => {
      const done = await db.query('update accounts set deleted_at = now() where id = $1 and deleted_at is null returning deleted_at', [account_id]);
      await db.query('update sessions set revoked_at = now() where account_id = $1 and revoked_at is null', [account_id]);
      await db.query('update credentials set revoked_at = now() where account_id = $1 and revoked_at is null', [account_id]);
      const at = done.rowCount ? new Date(done.rows[0].deleted_at) : this.now();
      return { delete_on: new Date(at.getTime() + DELETE_GRACE_DAYS * 86400000).toISOString() };
    });
  }

  // Bans step up: 24 hours, 7 days, then for good (owner, 2026-11-04).
  async ban({ account_id, reason = '' }) {
    return this._tx(async (db) => {
      const found = await db.query('select ban_count from accounts where id = $1 for update', [account_id]);
      if (!found.rowCount) throw new ApiError('no_account', 404);
      const count = found.rows[0].ban_count;
      const hours = count < BAN_STEPS_HOURS.length ? BAN_STEPS_HOURS[count] : null;
      const until = hours === null ? new Date('9999-12-31T00:00:00Z') : new Date(this.now().getTime() + hours * 3600000);
      await db.query('update accounts set banned_until = $2, ban_reason = $3, ban_count = ban_count + 1 where id = $1',
        [account_id, until.toISOString(), String(reason).slice(0, 200)]);
      await db.query('update sessions set revoked_at = now() where account_id = $1 and revoked_at is null', [account_id]);
      return { until: until.toISOString(), permanent: hours === null };
    });
  }

  // The owner's ban tool (server/src/admin.js): lift a ban (the count stays, so the next one is longer).
  async unban({ account_id }) {
    const done = await this.pool.query('update accounts set banned_until = null where id = $1', [account_id]);
    if (!done.rowCount) throw new ApiError('no_account', 404);
    return { ok: true };
  }

  // An account's id by its username (the owner's tools).
  async find({ username }) {
    const found = await this.pool.query('select id from accounts where lower(username) = lower($1)', [String(username || '')]);
    if (!found.rowCount) throw new ApiError('no_account', 404);
    return { account_id: found.rows[0].id };
  }

  // "Download my PvP data" (plan section 9, privacy): everything kept about the account, read-only. Never the
  // password or recovery hashes, session tokens or ban notes beyond the dates.
  async exportData({ account_id }) {
    const account = await this.pool.query(`select username, display_name, email, created_at, last_seen_at, deleted_at,
      banned_until, ban_count from accounts where id = $1`, [account_id]);
    if (!account.rowCount) throw new ApiError('no_account', 404);
    const profile = await this.pool.query('select data, revision, raid_state, updated_at from profiles where account_id = $1', [account_id]);
    const raids = await this.pool.query(`select raid_id, result, loot_value, created_at from raid_results
      where account_id = $1 order by created_at desc limit 500`, [account_id]);
    const sessions = await this.pool.query(`select created_at, last_seen_at, expires_at from sessions
      where account_id = $1 and revoked_at is null`, [account_id]);
    return {
      format: 'bloxov-pvp-data',
      exported_at: this.now().toISOString(),
      account: account.rows[0],
      profile: profile.rowCount ? profile.rows[0] : null,
      raid_results: raids.rows,
      signed_in_sessions: sessions.rows,
    };
  }

  // The daily clean-up: accounts past their 30-day grace go for good; accounts unused for 12 months start the grace.
  async sweep() {
    const gone = await this.pool.query(`delete from accounts where deleted_at < now() - interval '${DELETE_GRACE_DAYS} days'`);
    const idle = await this.pool.query(`update accounts set deleted_at = now()
      where deleted_at is null and last_seen_at < now() - interval '${INACTIVE_MONTHS} months'`);
    await this.pool.query(`delete from sessions where expires_at < now() - interval '1 day' or revoked_at < now() - interval '1 day'`);
    return { deleted: gone.rowCount, marked: idle.rowCount };
  }
}

module.exports = { StashApi, ApiError, hashPassword, checkPassword, newRecoveryCode, USERNAME_RE };
