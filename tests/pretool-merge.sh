#!/usr/bin/env bash
# pretool.sh merge block: real merges are refused, read-only merge-* subcommands pass. Run: tests/pretool-merge.sh
set -uo pipefail
hook="$(cd "$(dirname "$0")/.." && pwd)/hooks/pretool.sh"
repo=$(mktemp -d); trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q && mkdir "$repo/.orca" && echo '{}' >"$repo/.orca/config.json"

fail=0
check() { # check <expected exit> <command>
  jq -n --arg c "$2" --arg d "$repo" '{cwd:$d, tool_name:"Bash", tool_input:{command:$c}}' | bash "$hook" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$1" ]; then echo "ok   $1  $2"; else echo "FAIL want $1 got $got  $2"; fail=1; fi
}

check 0 'git merge-base --is-ancestor a b'
check 0 'git merge-base HEAD main'
check 0 'git merge-tree a b'
check 0 'git log --oneline && git merge-base HEAD origin/main'
check 2 'git merge feature'
check 2 'git merge --ff-only x'
check 2 'git merge'
check 2 'git fetch && git merge origin/main'
check 2 'git status; git  merge feature'
check 2 'git merge;echo hi'
check 2 'git merge&&echo hi'
check 2 'git merge|cat'
exit $fail
