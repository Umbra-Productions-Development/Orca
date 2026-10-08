# Shared helpers for tests/*.test.sh. Sourced by tests/run.sh; needs only bash, git and jq.
ORCA_SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$ORCA_SRC/bin:$PATH" HERDR_ENV=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset ORCA_ROLE HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_TAB_ID CLAUDE_SESSION_ID

fails=0
fail() { echo "  FAIL: $*"; fails=$((fails+1)); }
assert_eq() { [ "$1" = "$2" ] || fail "${3:-expected '$2', got '$1'}"; }
assert_contains() { grep -qF -- "$2" <<<"$1" || fail "${3:-'$2' not in: $1}"; }
assert_not_contains() { if grep -qF -- "$2" <<<"$1"; then fail "${3:-'$2' unexpectedly in: $1}"; fi; }
assert_status() { [ "$1" = "$2" ] || fail "${3:-exit $1, expected $2}"; }

# new_repo [config-json] -> path of a fresh repo on main with one commit, a bare origin and
# .orca/config.json. The repo sits alone in a temp dir, so worktrees orca-lc makes next to it
# (in its parent) stay inside that dir.
new_repo() {
  local d cfg='{"project":"proj","gate":"true"}'; d=$(mktemp -d); [ -n "${1:-}" ] && cfg="$1"
  git init -q --bare -b main "$d/remote.git"
  git init -q -b main "$d/repo"
  mkdir -p "$d/repo/.orca"; echo "$cfg" > "$d/repo/.orca/config.json"
  echo seed > "$d/repo/README"; git -C "$d/repo" add -A; git -C "$d/repo" commit -qm seed
  git -C "$d/repo" remote add origin "$d/remote.git"; git -C "$d/repo" push -q origin main
  echo "$d/repo"
}

# hook_json <tool> <cwd> <command> -> a PreToolUse payload for a Bash call
hook_json() { jq -n --arg t "$1" --arg c "$2" --arg x "$3" '{tool_name:$t, cwd:$c, tool_input:{command:$x}}'; }
