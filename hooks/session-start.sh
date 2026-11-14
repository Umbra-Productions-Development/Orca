#!/usr/bin/env bash
# SessionStart: set this session's identity once, then print context. Plain stdout becomes Claude's session context.
# A fork (source "fork") writes the identity only when the pane has none: a background /fork copy may share the
# pane id, and must not overwrite the foreground session's identity.
set -uo pipefail
in=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$in"); cd "${cwd:-.}" 2>/dev/null || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/.orca/config.json" ] || exit 0
export CLAUDE_SESSION_ID; CLAUDE_SESSION_ID=$(jq -r '.session_id // empty' <<<"$in")
if [ "$(jq -r '.source // empty' <<<"$in")" != fork ] || [ -z "$(orca-lc name 2>/dev/null | jq -r '.id // empty')" ]; then
  orca-lc name --set >/dev/null 2>&1
fi
orca-lc context 2>/dev/null
orca-lc tidy >/dev/null 2>&1
echo "orca-lc rules: load skill 'orca' before starting work in this repo."
exit 0
