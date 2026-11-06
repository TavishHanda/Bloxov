'use strict';
// The owner's account tool, run on the server's own machine (it needs DATABASE_URL):
//
//   heroku run -a bloxov-server node /game/server/src/admin.js ban <username> [reason...]
//   heroku run -a bloxov-server node /game/server/src/admin.js unban <username>
//   heroku run -a bloxov-server node /game/server/src/admin.js export <username>
//
// ban: 24 hours the first time, then 7 days, then for good (owner, 2026-11-04). It ends their remembered sessions
// and stops them signing in; someone online right now plays on until they next sign in. unban lifts it (the count
// stays). export prints what "download my PvP data" gives, for a privacy request sent by email.

const { StashApi } = require('./api');
const { makePool } = require('./index');

async function main() {
  const [command, username, ...rest] = process.argv.slice(2);
  if (!['ban', 'unban', 'export'].includes(command) || !username) {
    console.log('usage: node admin.js ban|unban|export <username> [reason]');
    process.exit(2);
  }
  if (!process.env.DATABASE_URL) {
    console.error('DATABASE_URL is not set (run it with heroku run on the server app)');
    process.exit(1);
  }
  const pool = makePool(process.env.DATABASE_URL);
  const api = new StashApi(pool);
  try {
    const { account_id } = await api.find({ username });
    if (command === 'ban') {
      const reason = rest.join(' ') || 'cheating';
      const out = await api.ban({ account_id, reason });
      console.log(`${username} banned ${out.permanent ? 'for good' : `until ${out.until}`} (${reason})`);
    } else if (command === 'unban') {
      await api.unban({ account_id });
      console.log(`${username} unbanned`);
    } else {
      console.log(JSON.stringify(await api.exportData({ account_id }), null, 2));
    }
  } catch (err) {
    console.error(err.code === 'no_account' ? `no account called ${username}` : `failed: ${err.message}`);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
}

main();
