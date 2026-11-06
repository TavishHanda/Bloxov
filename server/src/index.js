'use strict';
// The Stash API's HTTP side: listens on 127.0.0.1 only (the game server in the same container is its one caller),
// checks the service token, runs the migrations at start, and does the daily sweep.
//
// Settings (environment): DATABASE_URL (Heroku Postgres sets it), STASH_API_TOKEN (shared with the game server;
// server/start.sh makes a random one per boot when unset), STASH_API_PORT (default 9091).

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { Pool } = require('pg');
const { StashApi, ApiError } = require('./api');

const ROUTES = {
  '/v1/signup': 'signup',
  '/v1/login': 'login',
  '/v1/resume': 'resume',
  '/v1/logout': 'logout',
  '/v1/recover': 'recover',
  '/v1/save': 'save',
  '/v1/delete': 'remove',
  '/v1/ban': 'ban',
};
const MAX_BODY = 300000;

function makePool(url) {
  // Heroku Postgres needs TLS, with a certificate Node can't check (Heroku's own advice); local test databases don't.
  const local = /@(localhost|127\.0\.0\.1)[:/]/.test(url) || url.startsWith('postgres:///');
  return new Pool({ connectionString: url, max: 5, ssl: local ? false : { rejectUnauthorized: false } });
}

async function migrate(pool) {
  await pool.query('create table if not exists meta (key text primary key, value text not null)');
  const row = await pool.query("select value from meta where key = 'schema_version'");
  const current = row.rowCount ? Number(row.rows[0].value) : 0;
  const dir = path.join(__dirname, '..', 'migrations');
  const files = fs.readdirSync(dir).filter((f) => /^\d{4}_.*\.sql$/.test(f)).sort();
  for (const file of files) {
    const number = Number(file.slice(0, 4));
    if (number <= current) continue;
    const client = await pool.connect();
    try {
      await client.query('begin');
      await client.query(fs.readFileSync(path.join(dir, file), 'utf8'));
      await client.query(`insert into meta (key, value) values ('schema_version', $1)
        on conflict (key) do update set value = excluded.value`, [String(number)]);
      await client.query('commit');
      console.log(`stash-api: migrated to ${file}`);
    } catch (err) {
      await client.query('rollback').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }
}

function sameToken(given, want) {
  const a = Buffer.from(String(given || ''));
  const b = Buffer.from(want);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function makeServer(api, token) {
  return http.createServer((req, res) => {
    const send = (status, body) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(body));
    };
    if (req.method === 'GET' && req.url === '/health') return send(200, { ok: true });
    const action = ROUTES[req.url];
    if (req.method !== 'POST' || !action) return send(404, { error: 'not_found' });
    if (!sameToken(req.headers['x-service-token'], token)) return send(401, { error: 'service_token' });
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) req.destroy();
      else chunks.push(chunk);
    });
    req.on('end', async () => {
      let body;
      try {
        body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
      } catch {
        return send(400, { error: 'bad_json' });
      }
      try {
        send(200, await api[action](body));
      } catch (err) {
        if (err instanceof ApiError) return send(err.status, { error: err.code, ...err.extra });
        // Never log a request body: it can hold a password.
        console.error(`stash-api: ${action} failed: ${err.message}`);
        send(503, { error: 'unavailable' });
      }
    });
  });
}

async function main() {
  const url = process.env.DATABASE_URL;
  const token = process.env.STASH_API_TOKEN;
  if (!url || !token) {
    console.error('stash-api: DATABASE_URL and STASH_API_TOKEN are needed');
    process.exit(1);
  }
  const pool = makePool(url);
  await migrate(pool);
  const api = new StashApi(pool);
  const port = Number(process.env.STASH_API_PORT || 9091);
  makeServer(api, token).listen(port, '127.0.0.1', () => console.log(`stash-api: listening on 127.0.0.1:${port}`));
  const sweep = () => api.sweep().then((r) => {
    if (r.deleted || r.marked) console.log(`stash-api: sweep deleted ${r.deleted}, marked ${r.marked} inactive`);
  }).catch((err) => console.error(`stash-api: sweep failed: ${err.message}`));
  setTimeout(sweep, 60000);
  setInterval(sweep, 24 * 3600 * 1000);
  process.on('SIGTERM', () => pool.end().finally(() => process.exit(0)));
}

if (require.main === module) {
  main().catch((err) => {
    console.error(`stash-api: could not start: ${err.message}`);
    process.exit(1);
  });
}

module.exports = { makeServer, migrate, makePool };
