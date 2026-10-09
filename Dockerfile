# The online game server (multiplayer, docs/MULTIPLAYER_PLAN.md): this same project, run headless with --server.
# Built and deployed to Fly.io by .github/workflows/web.yml after the tests pass.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.5.1
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
	&& curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	&& unzip -q /tmp/godot.zip -d /tmp \
	&& mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
	&& rm /tmp/godot.zip \
	&& apt-get purge -y curl unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

COPY . /game
WORKDIR /game
# Import once at build time so the server starts in about a second.
RUN godot --headless --import

EXPOSE 9080
CMD ["godot", "--headless", "--", "--server", "--port=9080"]
