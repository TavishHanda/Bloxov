# The online game server (multiplayer, docs/MULTIPLAYER_PLAN.md), built and deployed by .github/workflows/web.yml
# (Heroku via heroku.yml; Fly.io via fly.toml) after the tests pass.
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

# Stage 2: just Godot and the pack.
FROM debian:bookworm-slim
RUN apt-get update \
	&& apt-get install -y --no-install-recommends libfontconfig1 \
	&& rm -rf /var/lib/apt/lists/*
COPY --from=build /usr/local/bin/godot /usr/local/bin/godot
COPY --from=build /out/bloxov_server.pck /game/bloxov_server.pck
WORKDIR /game

EXPOSE 9080
CMD ["godot", "--headless", "--main-pack", "/game/bloxov_server.pck", "--", "--server", "--port=9080"]
