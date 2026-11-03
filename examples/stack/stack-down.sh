#!/usr/bin/env bash
# Stops this ticket's docker compose stack and removes its volumes. Run by `orca-lc worktree down`
# as `stackDown`, with ORCA_TICKET and ORCA_WORKTREE exported. See examples/stack/README.md.
set -euo pipefail

die() { echo "stack-down: $*" >&2; exit 1; }
: "${ORCA_TICKET:?ORCA_TICKET is unset; run this through orca-lc worktree down}"
cd "${ORCA_WORKTREE:-.}"

project=$(orca-lc config project)
[ -n "$project" ] || die "set project in .orca/config.json; it names the compose project"
project=$(printf '%s' "$project" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')

docker compose -p "$project-$ORCA_TICKET" down -v --remove-orphans
