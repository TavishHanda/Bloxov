#!/bin/sh
# The game server's start (Dockerfile CMD, heroku.yml). With a database (Heroku Postgres sets DATABASE_URL) the Stash
# API (PvP accounts and the online stash) runs beside it on 127.0.0.1, restarted if it ever stops; the game server
# finds it through STASH_API_URL / STASH_API_TOKEN. Without one, the game server runs alone (online play as before).
if [ -n "$DATABASE_URL" ]; then
	STASH_API_PORT="${STASH_API_PORT:-9091}"
	# A fresh secret each boot unless the host sets one: only these two processes ever need it.
	STASH_API_TOKEN="${STASH_API_TOKEN:-$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')}"
	STASH_API_URL="http://127.0.0.1:${STASH_API_PORT}"
	export STASH_API_PORT STASH_API_TOKEN STASH_API_URL
	(
		while true; do
			node --max-old-space-size=64 /game/server/src/index.js
			echo "stash-api: stopped, starting again in 5 s"
			sleep 5
		done
	) &
fi
exec godot --headless --main-pack /game/bloxov_server.pck -- --server "$@"
