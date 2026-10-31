# Moving the game to bloxov.com

Owner rule: **nobody loses progress.** Online progress is on the server, so it's safe. Singleplayer saves (the
profile and settings) live in each player's browser, and a browser keeps them per site: what was saved on
`tavishhanda.github.io` can't be read from `bloxov.com`.

## How saves come along (built in 0.25.5)

- Once the custom domain is set, GitHub sends `tavishhanda.github.io/Bloxov/` straight to `bloxov.com`
  (the old page never loads, so it can't hand anything over itself).
- On bloxov.com, `web/move_in.js` (loaded before the game) checks for a save. A browser with none is sent **once**
  to the move page on the old site, `https://tavishhanda.github.io/bloxov-move/`.
- The move page (`web/move/index.html`, hosted from its own small repo `TavishHanda/bloxov-move`, since every path
  under `/Bloxov/` will redirect) is on the old site, so it can read the old save. It goes straight back to
  `bloxov.com/#move=<save>` and the game picks it up. Only ever to bloxov.com; a browser that already has a save
  on bloxov.com is never touched.
- Players with no old save just make one quick hop on their first visit.
- Backup: OPTIONS > SAVE TO FILE / LOAD FROM FILE. The move page also offers the old save as a file at
  `https://tavishhanda.github.io/bloxov-move/?download` (for anyone whose save didn't come over, e.g. a different
  browser). Keep the `bloxov-move` repo up for good: it's the only way to reach old saves.
- Limits: the save follows in the **same browser** only. Safari already deletes a site's storage after about 7
  days without a visit (that's true today too).

Tested in Chromium with the real web export (old site, move page and bloxov.com faked locally): profile and
settings came over, including settings from before 0.25.5 that were only in IndexedDB; second visits stay put.

## Steps for the owner

### 1. Make the move page (free, can be done any time before step 4)
1. On GitHub: **New repository**. Name: `bloxov-move`. **Public**. Create it.
2. Click **uploading an existing file** and upload `index.html` (from this repo's `web/move/` folder, or the copy in
   the project files `domain/index.html`). Commit.
3. In the new repo: **Settings > Pages**. Source: **Deploy from a branch**, branch **main**, folder **/ (root)**. Save.
4. After a minute, open `https://tavishhanda.github.io/bloxov-move/?download`. It should say "BLOXOV HAS MOVED"
   and offer your save. (Without `?download` it jumps to bloxov.com, which won't work until step 4. Harmless.)

### 2. Buy bloxov.com
Any registrar works (Cloudflare Registrar, Porkbun and Namecheap sell .com at about $10-11 a year). Turn off any
"parking page" or "forwarding" the registrar sets up.

### 3. DNS records (at the registrar)
First, prove the domain is yours to GitHub (stops anyone else using it on Pages): GitHub **profile picture >
Settings > Pages > Add a domain**, type `bloxov.com`. GitHub shows a **TXT** record; add it at the registrar,
then press **Verify**.

Then add these records at the registrar (delete any other A/AAAA/CNAME records on `@` and `www` first):

| Type  | Name / Host | Value                  |
|-------|-------------|------------------------|
| A     | @           | 185.199.108.153        |
| A     | @           | 185.199.109.153        |
| A     | @           | 185.199.110.153        |
| A     | @           | 185.199.111.153        |
| AAAA  | @           | 2606:50c0:8000::153    |
| AAAA  | @           | 2606:50c0:8001::153    |
| AAAA  | @           | 2606:50c0:8002::153    |
| AAAA  | @           | 2606:50c0:8003::153    |
| CNAME | www         | tavishhanda.github.io  |

(On Cloudflare: set each record to "DNS only", grey cloud, not proxied.)

### 4. Switch the game over (only after step 1 works)
1. `TavishHanda/Bloxov` > **Settings > Pages > Custom domain**: type `bloxov.com`, **Save**.
2. Wait for the green "DNS check successful" (minutes, sometimes a few hours).
3. Tick **Enforce HTTPS** once GitHub allows it (the certificate can take up to an hour or so).
4. Check: open the old link `https://tavishhanda.github.io/Bloxov/` in the browser you play in. It should end up on
   `https://bloxov.com/` with your stash and settings.

Nothing else in the game needs changing: the server address is separate (Heroku) and doesn't check the site.
The link-preview tags (`og:url`, `og:image`, `twitter:image` in the Web preset's head include, `export_presets.cfg`)
point at `https://bloxov.com/` (0.25.8).

## Status
Done 2026-10-31: bloxov.com bought (Cloudflare, DNS only), verified on GitHub, custom domain set on the Bloxov repo,
HTTPS on, move page live at https://tavishhanda.github.io/bloxov-move/. Checked with a real browser against the
live sites: a save on the old site followed the old link to https://bloxov.com/.
