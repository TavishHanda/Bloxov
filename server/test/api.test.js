'use strict';
// Stash API tests against a real Postgres (CI starts one; locally set TEST_DATABASE_URL). Each run starts from an
// empty schema. Run: TEST_DATABASE_URL=postgres://postgres@127.0.0.1:5433/bloxov_test npm test

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const { StashApi, checkPassword } = require('../src/api');
const { makeServer, migrate, makePool } = require('../src/index');

const URL = process.env.TEST_DATABASE_URL;
const PROFILE = { version: 1, money: 50000, stash_size: [8, 20], stash: [{ id: 'ak', count: 1, x: 0, y: 0 }], loadout: {} };

test('stash api', { skip: !URL && 'TEST_DATABASE_URL not set' }, async (t) => {
  const pool = makePool(URL);
  await pool.query('drop schema public cascade; create schema public');
  await migrate(pool);
  await migrate(pool); // (a second boot changes nothing)
  let clock = new Date();
  const api = new StashApi(pool, { now: () => clock });
  const fails = async (promise, code) => {
    await assert.rejects(promise, (err) => err.code === code, `expected ${code}`);
  };

  await t.test('sign up makes an account, a profile, a session and a recovery code', async () => {
    const made = await api.signup({ username: 'Tavish', password: 'correct horse', display_name: 'Tav', profile: PROFILE });
    assert.equal(made.username, 'Tavish');
    assert.equal(made.profile.money, 50000);
    assert.equal(made.revision, 1);
    assert.match(made.recovery_code, /^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    assert.ok(made.token.length >= 40);
    const row = (await pool.query('select password_hash, recovery_hash from accounts')).rows[0];
    assert.ok(!row.password_hash.includes('correct horse') && checkPassword('correct horse', row.password_hash));
    assert.ok(!row.recovery_hash.includes(made.recovery_code));
    const sessions = (await pool.query('select token_hash from sessions')).rows;
    assert.ok(sessions.every((s) => s.token_hash !== made.token), 'tokens are stored hashed');
  });

  await t.test('sign up refuses bad names, weak passwords and taken names (any case)', async () => {
    await fails(api.signup({ username: 'ab', password: 'correct horse', profile: PROFILE }), 'bad_username');
    await fails(api.signup({ username: 'bad name!', password: 'correct horse', profile: PROFILE }), 'bad_username');
    await fails(api.signup({ username: 'Someone', password: 'short', profile: PROFILE }), 'weak_password');
    await fails(api.signup({ username: 'Someone', password: 'password123', profile: PROFILE }), 'common_password');
    await fails(api.signup({ username: 'TAVISH', password: 'correct horse', profile: PROFILE }), 'username_taken');
  });

  await t.test('sign in, wrong passwords, lockout', async () => {
    const ok = await api.login({ username: 'tavish', password: 'correct horse' });
    assert.equal(ok.username, 'Tavish');
    await fails(api.login({ username: 'tavish', password: 'wrong one!!' }), 'bad_login');
    await fails(api.login({ username: 'nobody', password: 'wrong one!!' }), 'bad_login');
    for (let i = 0; i < 9; i++) await fails(api.login({ username: 'tavish', password: 'wrong one!!' }), 'bad_login');
    await fails(api.login({ username: 'tavish', password: 'correct horse' }), 'locked');
    await pool.query('update accounts set locked_until = now() - interval \'1 minute\'');
    assert.equal((await api.login({ username: 'tavish', password: 'correct horse' })).username, 'Tavish');
  });

  await t.test('one session: a new sign-in ends the old one; remember-me resumes', async () => {
    const first = await api.login({ username: 'tavish', password: 'correct horse' });
    const resumed = await api.resume({ token: first.token });
    assert.equal(resumed.account_id, first.account_id);
    const second = await api.login({ username: 'tavish', password: 'correct horse' });
    await fails(api.resume({ token: first.token }), 'bad_session');
    assert.equal((await api.resume({ token: second.token })).username, 'Tavish');
    await api.logout({ account_id: second.account_id });
    await fails(api.resume({ token: second.token }), 'bad_session');
  });

  await t.test('saves need the current revision; raids and results are stored', async () => {
    const me = await api.login({ username: 'tavish', password: 'correct horse' });
    const next = { ...me.profile, money: 40000 };
    const saved = await api.save({ account_id: me.account_id, revision: me.revision, profile: next });
    assert.equal(saved.revision, me.revision + 1);
    await fails(api.save({ account_id: me.account_id, revision: me.revision, profile: PROFILE }), 'conflict');
    await api.save({ account_id: me.account_id, revision: saved.revision, profile: next,
      raid: { state: 'in_raid', id: 'boot1-3', snapshot: { equipment: {} } } });
    let back = await api.login({ username: 'tavish', password: 'correct horse' });
    assert.deepEqual(back.raid, { state: 'in_raid', id: 'boot1-3', snapshot: { equipment: {} } });
    assert.equal(back.profile.money, 40000);
    await api.save({ account_id: me.account_id, revision: back.revision, profile: next, raid: { state: 'idle' },
      result: { raid_id: 'boot1-3', result: 'extracted', loot_value: 1234 }, look: { body: 2 }, display_name: 'Tav2' });
    back = await api.login({ username: 'tavish', password: 'correct horse' });
    assert.equal(back.raid.state, 'idle');
    assert.deepEqual(back.look, { body: 2 });
    assert.equal(back.display_name, 'Tav2');
    const results = (await pool.query('select result, loot_value from raid_results')).rows;
    assert.deepEqual(results, [{ result: 'extracted', loot_value: 1234 }]);
  });

  await t.test('the recovery code resets the password once', async () => {
    const made = await api.signup({ username: 'forgetful', password: 'first password', profile: PROFILE });
    await fails(api.recover({ username: 'forgetful', recovery_code: 'AAAA-BBBB-CCCC', new_password: 'second password' }), 'bad_recovery');
    const fixed = await api.recover({ username: 'forgetful', recovery_code: made.recovery_code.toLowerCase(), new_password: 'second password' });
    assert.notEqual(fixed.recovery_code, made.recovery_code);
    await fails(api.resume({ token: made.token }), 'bad_session');
    await fails(api.login({ username: 'forgetful', password: 'first password' }), 'bad_login');
    assert.equal((await api.login({ username: 'forgetful', password: 'second password' })).username, 'forgetful');
    await fails(api.recover({ username: 'forgetful', recovery_code: made.recovery_code, new_password: 'third password' }), 'bad_recovery');
  });

  await t.test('bans step up 24 hours, 7 days, for good', async () => {
    const made = await api.signup({ username: 'cheater', password: 'cheater pass', profile: PROFILE });
    const first = await api.ban({ account_id: made.account_id, reason: 'speed' });
    assert.ok(Math.abs(new Date(first.until) - clock - 24 * 3600000) < 5000);
    await fails(api.login({ username: 'cheater', password: 'cheater pass' }), 'banned');
    await fails(api.resume({ token: made.token }), 'bad_session');
    const second = await api.ban({ account_id: made.account_id });
    assert.ok(Math.abs(new Date(second.until) - clock - 7 * 24 * 3600000) < 5000);
    assert.equal((await api.ban({ account_id: made.account_id })).permanent, true);
    await api.unban({ account_id: made.account_id });
    assert.equal((await api.find({ username: 'CHEATER' })).account_id, made.account_id);
    await api.login({ username: 'cheater', password: 'cheater pass' });
    await fails(api.find({ username: 'nobody_here' }), 'no_account');
  });

  await t.test('the data export has the account and profile, never the secrets', async () => {
    const made = await api.signup({ username: 'exporter', password: 'export pass 1', profile: { money: 7 } });
    const out = await api.exportData({ account_id: made.account_id });
    assert.equal(out.format, 'bloxov-pvp-data');
    assert.equal(out.account.username, 'exporter');
    assert.equal(out.profile.data.money, 7);
    const text = JSON.stringify(out);
    for (const secret of ['password_hash', 'recovery_hash', 'token_hash', made.token, made.recovery_code]) {
      assert.equal(text.includes(secret), false, secret);
    }
  });

  await t.test('delete: 30-day grace, cancelled by signing in, then gone', async () => {
    const made = await api.signup({ username: 'leaving', password: 'leaving pass', profile: PROFILE });
    const gone = await api.remove({ account_id: made.account_id });
    assert.ok(new Date(gone.delete_on) > clock);
    await fails(api.resume({ token: made.token }), 'bad_session');
    await fails(api.login({ username: 'leaving', password: 'leaving pass' }), 'deleted');
    const back = await api.login({ username: 'leaving', password: 'leaving pass', cancel_delete: true });
    assert.equal(back.username, 'leaving');
    await api.remove({ account_id: made.account_id });
    await pool.query('update accounts set deleted_at = now() - interval \'31 days\' where username = \'leaving\'');
    await pool.query('update accounts set last_seen_at = now() - interval \'13 months\' where username = \'forgetful\'');
    const swept = await api.sweep();
    assert.deepEqual(swept, { deleted: 1, marked: 1 });
    assert.equal((await pool.query('select 1 from profiles where account_id = $1', [made.account_id])).rowCount, 0);
  });

  await t.test('the HTTP side checks the service token and maps errors', async () => {
    const server = makeServer(api, 'service-secret');
    await new Promise((done) => server.listen(0, '127.0.0.1', done));
    const port = server.address().port;
    const call = (url, body, token) => new Promise((done, fail) => {
      const req = http.request({ host: '127.0.0.1', port, path: url, method: 'POST',
        headers: { 'content-type': 'application/json', 'x-service-token': token } }, (res) => {
        let text = '';
        res.on('data', (c) => { text += c; });
        res.on('end', () => done([res.statusCode, JSON.parse(text)]));
      });
      req.on('error', fail);
      req.end(JSON.stringify(body));
    });
    assert.deepEqual(await call('/v1/login', { username: 'tavish', password: 'x' }, 'wrong'), [401, { error: 'service_token' }]);
    assert.deepEqual(await call('/v1/login', { username: 'tavish', password: 'wrong one!!' }, 'service-secret'), [401, { error: 'bad_login' }]);
    const [status, body] = await call('/v1/login', { username: 'tavish', password: 'correct horse' }, 'service-secret');
    assert.equal(status, 200);
    assert.equal(body.username, 'Tavish');
    server.close();
  });

  await pool.end();
});
