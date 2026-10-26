# orca-lc worktree up/down (git path; lib.sh sets HERDR_ENV=0)
cfg='{"project":"p","gate":"true","ports":["web","db"]}'
# The path as git prints it: Git Bash's mktemp gives /tmp/..., git gives C:/.... Identity where cygpath is absent.
native() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else echo "$1"; fi; }

# Ports: a trailing number gives its slot; an id without one hashes to a fixed slot (cksum of the uppercased id)
r=$(new_repo "$cfg"); d=$(dirname "$r")
out=$(cd "$r" && orca-lc worktree up abc-7 2>&1)
assert_contains "$out" "ports WEB_PORT=3070 DB_PORT=3071"
h=$(( $(printf INFRA | cksum | cut -d' ' -f1) % 100 * 10 + 3000 ))
out=$(cd "$r" && orca-lc worktree up infra 2>&1)
assert_contains "$(cat "$d/INFRA/.env.local")" "WEB_PORT=$h"
assert_contains "$(cat "$d/INFRA/.env.local")" "DB_PORT=$((h+1))"
assert_contains "$out" "ports WEB_PORT=$h DB_PORT=$((h+1))"
assert_eq "$(cd "$r" && orca-lc worktree up InFrA 2>&1 | grep -o 'ports.*')" "ports WEB_PORT=$h DB_PORT=$((h+1))" "hashed ports not deterministic across case"

# .env.local is excluded, idempotently
assert_eq "$(git -C "$d/INFRA" status --porcelain)" "" ".env.local shows in git status"
assert_eq "$(grep -cx .env.local "$(git -C "$d/INFRA" rev-parse --path-format=absolute --git-path info/exclude)")" 1

# --stack refuses up front when stackUp is unset or its command missing / not executable
r=$(new_repo "$cfg"); d=$(dirname "$r")
out=$(cd "$r" && orca-lc worktree up S-1 --stack 2>&1); assert_status $? 1
assert_contains "$out" "needs stackUp"; [ ! -e "$d/S-1" ] || fail "worktree created despite missing stackUp"
r=$(new_repo '{"project":"p","gate":"true","stackUp":"./scripts/up.sh"}'); d=$(dirname "$r")
out=$(cd "$r" && orca-lc worktree up S-2 --stack 2>&1); assert_status $? 1
assert_contains "$out" "'./scripts/up.sh' is missing or not executable"; [ ! -e "$d/S-2" ] || fail "worktree created despite missing stack script"
git -C "$r" show-ref -q --verify refs/heads/s-2/work && fail "branch created despite missing stack script"
mkdir -p "$r/scripts"; printf '#!/bin/sh\necho "up $ORCA_TICKET"\n' > "$r/scripts/up.sh"
out=$(cd "$r" && orca-lc worktree up S-3 --stack 2>&1); assert_status $? 1 "non-executable stack script accepted"
chmod +x "$r/scripts/up.sh"; git -C "$r" add scripts; git -C "$r" commit -qm stack; git -C "$r" push -q origin main
out=$(cd "$r" && orca-lc worktree up S-4 --stack 2>&1); assert_status $? 0
assert_contains "$out" "up S-4"; assert_contains "$out" "stack up"
r=$(new_repo '{"project":"p","gate":"true","stackUp":"FOO=1 nosuchcmd-orca"}')
out=$(cd "$r" && orca-lc worktree up S-6 --stack 2>&1); assert_status $? 1; assert_contains "$out" "'nosuchcmd-orca' is missing"

# --stack whose command fails after creation: says what exists, how to retry or tear down, exits non-zero
r=$(new_repo '{"project":"p","gate":"true","stackUp":"false"}'); d=$(dirname "$r")
out=$(cd "$r" && orca-lc worktree up S-7 --stack 2>&1); assert_status $? 1
assert_contains "$out" "worktree $(native "$d")/S-7 on s-7/work"
assert_contains "$out" "orca-lc worktree up S-7 --stack"
assert_contains "$out" "orca-lc worktree down S-7 --force"
[ -d "$d/S-7" ] || fail "worktree missing after stackUp failure"

# Branches: an existing local branch is reused, a remote one tracked; the real branch is printed
r=$(new_repo "$cfg"); d=$(dirname "$r")
git -C "$r" branch b-1/work; git -C "$r" commit -q --allow-empty -m ahead; git -C "$r" branch -f b-1/work HEAD; git -C "$r" reset -q --hard HEAD~1
out=$(cd "$r" && orca-lc worktree up B-1 2>&1); assert_status $? 0
assert_contains "$out" "on b-1/work"; assert_eq "$(git -C "$d/B-1" log -1 --format=%s)" ahead
git -C "$r" checkout -q -b feat/remote; git -C "$r" commit -q --allow-empty -m remote; git -C "$r" push -q origin feat/remote
git -C "$r" checkout -q main; git -C "$r" branch -qD feat/remote; git -C "$r" update-ref -d refs/remotes/origin/feat/remote
out=$(cd "$r" && orca-lc worktree up B-2 feat/remote 2>&1); assert_status $? 0
assert_contains "$out" "on feat/remote"; assert_eq "$(git -C "$d/B-2" log -1 --format=%s)" remote
assert_eq "$(git -C "$d/B-2" rev-parse --abbrev-ref '@{upstream}')" origin/feat/remote
out=$(cd "$r" && orca-lc worktree up B-3 2>&1); assert_contains "$out" "on b-3/work"
assert_eq "$(git -C "$d/B-3" branch --show-current)" b-3/work

# From a linked worktree: new worktrees sit next to the main checkout and link to its files; down finds them
r=$(new_repo '{"project":"p","gate":"true","linkPaths":[".secret"]}'); d=$(dirname "$r")
echo s > "$r/.secret"; mkdir -p "$d/nest"; git -C "$r" worktree add -q -b lnk "$d/nest/L"
out=$(cd "$d/nest/L" && orca-lc worktree up L-1 2>&1); assert_status $? 0
[ -d "$d/L-1" ] || fail "worktree not next to the main checkout: $out"; [ ! -e "$d/nest/L-1" ] || fail "worktree next to the linked one"
# Git Bash without native symlinks makes ln -s copy: nothing to readlink there, so the link assert is skipped.
if ln -s "$r/.secret" "$d/probe" 2>/dev/null && [ -L "$d/probe" ]; then
  assert_eq "$(native "$(readlink "$d/L-1/.secret")")" "$(native "$r/.secret")"
else echo "  SKIP: ln -s copies here (no native symlinks); linkPaths link assert skipped"; fi
out=$(cd "$d/nest/L" && orca-lc worktree down L-1 --force 2>&1); assert_status $? 0
[ ! -e "$d/L-1" ] || fail "down left $d/L-1: $out"

# claude.disabledMcpServers: up merges the list into the new worktree's entry in $HOME/.claude.json
# (other keys kept); an empty or missing list writes nothing; down drops it, and the entry once empty.
cj="$HOME/.claude.json"
r=$(new_repo '{"project":"p","gate":"true","claude":{"disabledMcpServers":["playwright","x"]}}'); d=$(dirname "$r")
jq -n --arg k "$(native "$d")/M-1" '{theme:"dark", projects:{"/other":{a:1}, ($k):{disabledMcpServers:["x","mine"], allowedTools:["Bash"]}}}' > "$cj"
out=$(cd "$r" && orca-lc worktree up M-1 2>&1); assert_status $? 0; assert_contains "$out" "mcp off: playwright x"
k="$(native "$d")/M-1"
assert_eq "$(jq -c --arg k "$k" '.projects[$k].disabledMcpServers' "$cj")" '["mine","playwright","x"]'
assert_eq "$(jq -c --arg k "$k" '[.theme, .projects["/other"].a, .projects[$k].allowedTools[0]]' "$cj")" '["dark",1,"Bash"]' "other keys lost"
out=$(cd "$r" && orca-lc worktree up M-2 2>&1)
assert_eq "$(jq -c --arg k "$(native "$d")/M-2" '.projects[$k]' "$cj")" '{"disabledMcpServers":["playwright","x"]}'
(cd "$r" && orca-lc worktree down M-1 --force >/dev/null 2>&1)
assert_eq "$(jq -c --arg k "$k" '.projects[$k]' "$cj")" '{"allowedTools":["Bash"]}' "down: entry not cleared"
(cd "$r" && orca-lc worktree down M-2 --force >/dev/null 2>&1)
assert_eq "$(jq --arg k "$(native "$d")/M-2" '.projects | has($k)' "$cj")" false "down: empty entry kept"
assert_eq "$(jq -c '[.theme, .projects["/other"].a]' "$cj")" '["dark",1]'
rm -f "$cj"
for c in '{"project":"p","gate":"true"}' '{"project":"p","gate":"true","claude":{"disabledMcpServers":[]}}'; do
  r=$(new_repo "$c"); out=$(cd "$r" && orca-lc worktree up M-3 2>&1); assert_status $? 0
  [ ! -e "$cj" ] || fail "wrote $cj with config $c"; assert_not_contains "$out" "mcp off"
done
