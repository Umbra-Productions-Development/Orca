#!/usr/bin/env bash
# Stop: one line of what is left undone, as {systemMessage} on stdout: shown to the user, never to Claude.
# Never blocks and never continues the turn.
set -uo pipefail
in=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$in"); cd "${cwd:-.}" 2>/dev/null || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/.orca/config.json" ] || exit 0
[ "$(jq -r '.stop_hook_active // false' <<<"$in")" = true ] && exit 0
left=()
orca-lc gate-fresh || left+=("gate stale")
[ -n "$(git status --porcelain 2>/dev/null)" ] && left+=("uncommitted changes")
[ "$(orca-lc test-lock status 2>/dev/null)" = unlocked ] && left+=("test-lock still on")
[ ${#left[@]} -gt 0 ] && jq -n --arg m "orca-lc: before calling this done: ${left[*]}." '{systemMessage: $m}'
exit 0
