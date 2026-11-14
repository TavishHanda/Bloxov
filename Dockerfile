# The online game server (multiplayer, docs/MULTIPLAYER_PLAN.md), built and deployed by .github/workflows/web.yml
# (Heroku via heroku.yml) after the tests pass.
# Since 0.30.9 it runs a stripped "dedicated server" pack (export preset "Server"): every model, texture and material is
# a placeholder (meshes keep their bounds), so the server starts at ~170 MB instead of ~200 and each raid costs far less
# (docs/HOSTING_CAPACITY.md). Nothing about the game changes: the server never drew anything.

# Stage 1: import the project and export the server pack (no export templates needed for a .pck).
FROM debian:bookworm-slim AS build

ARG GODOT_VERSION=4.7.2
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
	&& curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	&& unzip -q /tmp/godot.zip -d /tmp \
	&& mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
	&& rm /tmp/godot.zip

COPY . /game
WORKDIR /game
RUN godot --headless --import \
	&& mkdir -p /out \
	&& godot --headless --export-pack "Server" /out/bloxov_server.pck \
	&& test -s /out/bloxov_server.pck

# Stage 2: the Stash API (server/: PvP accounts and the online stash, Stash update 0.31) and its packages.
FROM node:22-bookworm-slim AS api
WORKDIR /api
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund
COPY server/src ./src
COPY server/migrations ./migrations
COPY server/start.sh ./start.sh

# Stage 3: Godot and the pack, plus Node and the Stash API (started only when there's a database: server/start.sh).
FROM debian:bookworm-slim
RUN apt-get update \
	&& apt-get install -y --no-install-recommends libfontconfig1 libstdc++6 \
	&& rm -rf /var/lib/apt/lists/*
COPY --from=build /usr/local/bin/godot /usr/local/bin/godot
COPY --from=build /out/bloxov_server.pck /game/bloxov_server.pck
COPY --from=api /usr/local/bin/node /usr/local/bin/node
COPY --from=api /api /game/server
WORKDIR /game

EXPOSE 9080
CMD ["sh", "/game/server/start.sh", "--port=9080"]
