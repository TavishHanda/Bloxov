# Player history (0.30.7)

The online server posts how many players are on to a Google Sheet every 5 minutes: online, in the hideout, in raids,
raids running, and the version. Numbers only (no names, no IP addresses), so nothing changes for the privacy page.
It's free (Google Sheets + Apps Script). Without the `STATS_URL` setting on Heroku nothing is sent.

Solo play never reaches the server, so only online players count. Every push to main restarts the server, which can
leave a short gap. For website visits (solo and online), use Cloudflare Web analytics.

## Setup (owner, once)
1. Make a new Google Sheet (sheets.new), name it e.g. "Bloxov players".
2. **Extensions > Apps Script**. Delete what's there, paste `tools/player_history.gs`, click **Save**.
3. **Deploy > New deployment**. Gear icon > **Web app**. Execute as: **Me**. Who has access: **Anyone**. **Deploy**,
   allow access (Google warns the app isn't verified: Advanced > Go to project). Copy the **Web app URL**.
4. Heroku dashboard > **bloxov-server** > **Settings** > **Reveal Config Vars**. Add key `STATS_URL`, value = that URL,
   **Add**. Heroku restarts the server; the first row shows up within 5 minutes.
5. Chart: select columns A and B > **Insert > Chart** (line chart).

Keep the URL private: anyone with it could add rows. To change the script later use **Deploy > Manage deployments >
edit > New version** so the URL stays the same.
