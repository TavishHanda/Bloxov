#!/usr/bin/env bash
# Should the nightly job touch the game server now? Usage: tools/nightly_guard.sh <event>
# Prints `run` or `skip` on stdout, the reason on stderr. Used by .github/workflows/server_nightly.yml.
#   manual run (workflow_dispatch)  -> always `run`
#   scheduled run                   -> `skip` unless (1) the UTC hour is 8..12 (quiet window, 1-6 am Mountain
#                                      Standard Time) and (2) no web dyno started in the last 6 hours
# GitHub starts scheduled runs hours late; a late run must not restart the server in the daytime.
# Env: HEROKU_API_KEY and APP for the real dyno lookup (the key is never printed).
# Test overrides: NIGHTLY_NOW_HOUR (UTC hour), NIGHTLY_NOW_EPOCH (seconds), NIGHTLY_DYNOS_JSON (replaces the curl call).
event="${1:-}"

say() { echo "$1"; echo "nightly_guard: $1 ($2)" >&2; exit 0; }

[ "$event" = "schedule" ] || say run "not a scheduled run ($event), always acts"

hour="${NIGHTLY_NOW_HOUR:-$(date -u +%H)}"
hour=$((10#$hour)) 2>/dev/null || say run "could not read the hour '$hour'"
if [ "$hour" -lt 8 ] || [ "$hour" -gt 12 ]; then
  echo "::notice::Nightly run started late (UTC hour $hour, window is 08:00-12:59 UTC); skipped so players' raids are not interrupted." >&2
  say skip "UTC hour $hour is outside 08-12"
fi

if [ -n "${NIGHTLY_DYNOS_JSON+x}" ]; then
  json="$NIGHTLY_DYNOS_JSON"
else
  key=$(printf '%s' "${HEROKU_API_KEY:-}" | tr -d '[:space:]')
  json=$(curl -fsS --max-time 30 -H "Authorization: Bearer $key" -H "Accept: application/vnd.heroku+json; version=3" -H "Content-Type: application/json" "https://api.heroku.com/apps/${APP:-bloxov-server}/dynos" 2>/dev/null) || json=""
fi

# Seconds since the newest web dyno started (created_at / updated_at), or nothing if unknown.
age=$(printf '%s' "$json" | NOW="${NIGHTLY_NOW_EPOCH:-}" python3 -c '
import sys, os, json, time
from datetime import datetime, timezone
try:
    now = float(os.environ.get("NOW") or time.time())
    best = None
    for d in json.load(sys.stdin):
        if d.get("type") != "web":
            continue
        for k in ("created_at", "updated_at"):
            v = d.get(k)
            if v:
                t = datetime.fromisoformat(v.replace("Z", "+00:00"))
                if t.tzinfo is None:
                    t = t.replace(tzinfo=timezone.utc)
                t = t.timestamp()
                best = t if best is None else max(best, t)
    if best is not None:
        print(int(now - best))
except Exception:
    pass
' 2>/dev/null) || age=""

if [ -z "$age" ]; then
  echo "nightly_guard: could not tell when the web dyno last started; treating as not restarted" >&2
elif [ "$age" -lt 21600 ]; then
  echo "::notice::Already restarted tonight (web dyno started $((age / 60)) minutes ago); skipped." >&2
  say skip "web dyno started $((age / 60)) min ago, under 6 h"
fi
say run "in the quiet window, no recent restart"
