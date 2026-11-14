#!/usr/bin/env bash
# Does the running game server need a deploy? Usage: tools/server_deploy_check.sh <deployed_sha> <head_sha> <event>
# Prints one word on stdout, the reason on stderr:
#   now    deploy right away: manual run, net version changed, server infra changed, or can't tell
#   later  game files changed (scripts/, scenes/, ...) but the net version is the same: wait for the nightly run
#   none   nothing the server runs changed
# The net version is read with `git show <sha>:project.godot`; a commit without the line counts as 0.
# Rules and the CI wiring: docs/context/ONLINE.md ("The net version"), .github/workflows/web.yml, server_nightly.yml.
deployed="${1:-}"; head="${2:-HEAD}"; event="${3:-}"

say() { echo "$1"; echo "server_deploy_check: $1 ($2)" >&2; exit 0; }

net_version() {
  local v
  v=$(git show "$1:project.godot" 2>/dev/null | sed -n 's/^config\/net_version="\{0,1\}\([0-9][0-9]*\)"\{0,1\}[[:space:]]*$/\1/p' | head -n1)
  echo "${v:-0}"
}

[ "$event" = "workflow_dispatch" ] && say now "manual run"
[ -z "$deployed" ] && say now "deployed commit unknown"
git rev-parse --verify --quiet "$deployed^{commit}" >/dev/null || say now "deployed commit $deployed not found here"
git rev-parse --verify --quiet "$head^{commit}" >/dev/null || say now "head commit $head not found"

old=$(net_version "$deployed"); new=$(net_version "$head")
[ "$old" != "$new" ] && say now "net version $old -> $new"

files=$(git diff --name-only "$deployed" "$head") || say now "could not diff $deployed..$head"
if echo "$files" | grep -qE '^(server/|Dockerfile$|heroku\.yml$|export_presets\.cfg$)'; then
  say now "server infra changed"
fi
if echo "$files" | grep -qE '^(scripts/|scenes/|assets/|materials/|audio/|project\.godot$|default_bus_layout\.tres$)'; then
  say later "game files changed, same net version $new; the nightly run deploys them"
fi
say none "nothing the server runs changed"
