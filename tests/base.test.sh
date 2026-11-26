# evidence and test-affected measure against the fetched origin/<baseBranch>, not a stale local one (#69)
# fixture: local main stays at the seed; origin/main gains upstream.txt; t-1/work, cut from origin/main, adds mine.txt.
# A diff against local main shows upstream.txt; one against origin/main does not.
stale_repo() {
  local r c; r=$(new_repo "${1:-}"); c=$(mktemp -d)/clone
  git clone -q "$(dirname "$r")/remote.git" "$c"
  echo up > "$c/upstream.txt"; git -C "$c" add -A; git -C "$c" commit -qm upstream; git -C "$c" push -q origin main
  git -C "$r" fetch -q origin; git -C "$r" checkout -q -b t-1/work origin/main
  echo mine > "$r/mine.txt"; git -C "$r" add -A; git -C "$r" commit -qm mine
  echo "$r"
}
# evidence <repo> [base] -> the evidence file's contents (orca-lc prints its path relative to the repo)
evidence() { (cd "$1" && shift && f=$(orca-lc evidence "$@") && cat "$f") || echo "evidence failed"; }

# Stubs that show what they were given: detect_changes echoes its arguments, codegraph affected its stdin.
printf '#!/bin/sh\necho "$@"\n' > "$TMPDIR/bin/codebase-memory-mcp"
printf '#!/bin/sh\n[ "$1" = affected ] && cat\nexit 0\n' > "$TMPDIR/bin/codegraph"

# 1. evidence, stale local main: measured against origin/main, fetched
r=$(stale_repo); om=$(git -C "$r" rev-parse origin/main)
out=$(evidence "$r")
assert_contains "$out" "Base: origin/main (fetched)" "stale main: Base line"
assert_contains "$out" "Merge base: $om" "stale main: merge base is origin/main"
assert_contains "$out" "--base-branch $om" "stale main: detect_changes gets the merge-base sha"
assert_contains "$out" "mine.txt" "stale main: own change listed"
assert_not_contains "$out" "upstream.txt" "stale main: base-branch commit leaked into the evidence"

# 2. evidence, no origin: local main, labelled
r=$(stale_repo); git -C "$r" remote remove origin; lm=$(git -C "$r" rev-parse main)
out=$(evidence "$r")
assert_contains "$out" "Base: main (local; fetch failed)" "no origin: Base line"
assert_contains "$out" "Merge base: $lm" "no origin: merge base is local main"
assert_contains "$out" "upstream.txt" "no origin: local main is behind, upstream.txt shows"

# 3. evidence, explicit base: used as given, stale or not
r=$(stale_repo)
out=$(evidence "$r" main)
assert_contains "$out" "Base: main (given)" "explicit base: Base line"
assert_contains "$out" "upstream.txt" "explicit base: the given main is honoured"

# 4. test-affected, stale local main
r=$(stale_repo '{"project":"proj","gate":"true","testCommand":"echo"}')
out=$(cd "$r" && orca-lc test-affected 2>&1)
assert_contains "$out" "mine.txt" "test-affected: own change"
assert_not_contains "$out" "upstream.txt" "test-affected: base-branch commit leaked"

# 5. evidence, fetch failed: an earlier origin/main still beats the stale local main
r=$(stale_repo); git -C "$r" remote set-url origin "$(dirname "$r")/missing.git"
out=$(evidence "$r")
assert_contains "$out" "Base: origin/main (fetch failed)" "fetch failed: Base line"
assert_not_contains "$out" "upstream.txt" "fetch failed: fell back to the stale local main"

# 6. evidence, no merge base: dies naming the base, the last evidence file stays as it was
r=$(stale_repo); f="$(git -C "$r" rev-parse --absolute-git-dir)/orca-evidence.md"
evidence "$r" >/dev/null; before=$(cat "$f")
git -C "$r" branch orphan "$(git -C "$r" commit-tree "$(git -C "$r" mktree </dev/null)" -m orphan)"
out=$(cd "$r" && orca-lc evidence orphan 2>&1); assert_status $? 1 "no merge base: evidence succeeded"
assert_contains "$out" "orphan" "no merge base: message names the base"
assert_eq "$(cat "$f")" "$before" "no merge base: evidence file changed"

# worktree up <repo> <ticket> -> its output; worktrees land next to the repo
wt_up() { (cd "$1" && orca-lc worktree up "$2" 2>&1); }

# 7. worktree up, origin's refspec leaves main out: the explicit refspec still updates origin/main
r=$(stale_repo); d=$(dirname "$r")
git -C "$r" update-ref refs/remotes/origin/main main
git -C "$r" config remote.origin.fetch '+refs/heads/t-*:refs/remotes/origin/t-*'
out=$(wt_up "$r" T-2); assert_status $? 0 "refspec without main: worktree up failed: $out"
assert_contains "$out" "base origin/main (fetched)" "refspec without main: base line"
[ -f "$d/T-2/upstream.txt" ] || fail "refspec without main: worktree not cut from the fetched origin/main"

# 8. worktree up, fetch failed: cut from the earlier origin/main, not the older local main
r=$(stale_repo); d=$(dirname "$r"); git -C "$r" remote set-url origin "$d/missing.git"
out=$(wt_up "$r" T-2); assert_status $? 0 "fetch failed: worktree up failed: $out"
assert_contains "$out" "base origin/main (fetch failed)" "fetch failed: base line"
[ -f "$d/T-2/upstream.txt" ] || fail "fetch failed: worktree cut from the stale local main"

# 9. worktree up, no base: dies naming the base branch before creating anything
r=$(stale_repo); d=$(dirname "$r"); git -C "$r" remote remove origin; git -C "$r" branch -qD main
out=$(wt_up "$r" T-2); assert_status $? 1 "no base: worktree up succeeded"
assert_contains "$out" "no base: neither origin/main nor main exists" "no base: orca-lc did not die naming the base"
[ ! -e "$d/T-2" ] || fail "no base: T-2 created"

# remote_ticket_repo -> a stale_repo whose origin has t-3/work (holding ticket.txt) and whose fetch refspec
# maps only main, so worktree add cannot set the upstream itself; sets r and d
remote_ticket_repo() {
  local c; r=$(stale_repo); d=$(dirname "$r"); c=$(mktemp -d)/clone
  git clone -q "$d/remote.git" "$c"; git -C "$c" checkout -q -b t-3/work
  echo t > "$c/ticket.txt"; git -C "$c" add -A; git -C "$c" commit -qm ticket; git -C "$c" push -q origin t-3/work
  git -C "$r" config remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'
}

# 10. worktree up, remote ticket branch outside origin's refspec: reused, upstream set by config
remote_ticket_repo
out=$(wt_up "$r" T-3); assert_status $? 0 "remote ticket branch: worktree up failed: $out"
[ -f "$d/T-3/ticket.txt" ] || fail "remote ticket branch: not reused"
assert_eq "$(git -C "$r" config branch.t-3/work.remote)" origin "remote ticket branch: upstream remote"
assert_eq "$(git -C "$r" config branch.t-3/work.merge)" refs/heads/t-3/work "remote ticket branch: upstream merge"
assert_not_contains "$out" "base " "remote ticket branch: base line printed for a reused branch"
assert_not_contains "$out" "WARNING: upstream not set" "remote ticket branch: warned with the upstream set"

# 11. worktree up, existing local ticket branch and no base: reused, no base needed
r=$(stale_repo); d=$(dirname "$r"); git -C "$r" remote remove origin; git -C "$r" branch -qD main; git -C "$r" branch t-4/work
out=$(wt_up "$r" T-4); assert_status $? 0 "local ticket branch, no base: worktree up failed: $out"
assert_contains "$out" "on t-4/work" "local ticket branch, no base: not reused"

# 12. worktree up, upstream config fails on a reused remote ticket branch: still reused, warns with the push command
remote_ticket_repo; w=$(mktemp -d); real=$(command -v git)
# A git that fails `git config branch.<b>.remote|merge <value>` writes; reads and every other call run the real git.
cat > "$w/git" <<WRAP
#!/bin/sh
i=0
for a; do i=\$((i+1)); case "\$a" in branch.*.remote|branch.*.merge) [ "\$i" -lt \$# ] && exit 1;; esac; done
exec "$real" "\$@"
WRAP
chmod +x "$w/git"
out=$(PATH="$w:$PATH" wt_up "$r" T-3); assert_status $? 0 "upstream not set: worktree up failed: $out"
[ -f "$d/T-3/ticket.txt" ] || fail "upstream not set: not reused"
assert_contains "$out" "WARNING: upstream not set; git push -u origin t-3/work" "upstream not set: no warning"
assert_not_contains "$out" "base " "upstream not set: base line printed for a reused branch"

# 13. evidence, ssh origin: the fetch runs the user's ssh command with BatchMode=yes, so ssh never prompts on the tty
r=$(stale_repo); git -C "$r" remote set-url origin sshhost:/remote.git; s=$(mktemp -d)
printf '#!/bin/sh\necho "$*" >> %s/log\nexit 1\n' "$s" > "$s/ssh"; chmod +x "$s/ssh"
out=$(unset GIT_SSH GIT_SSH_VARIANT; GIT_SSH_COMMAND="$s/ssh -i k" evidence "$r")
assert_contains "$out" "Base: origin/main (fetch failed)" "ssh origin: Base line"
assert_contains "$(cat "$s/log")" "-i k -o BatchMode=yes" "ssh origin: GIT_SSH_COMMAND not kept or BatchMode missing"
: > "$s/log"; git -C "$r" config core.sshCommand "$s/ssh -p 2"
(unset GIT_SSH_COMMAND GIT_SSH GIT_SSH_VARIANT; evidence "$r" >/dev/null)
assert_contains "$(cat "$s/log")" "-p 2 -o BatchMode=yes" "ssh origin: core.sshCommand not kept or BatchMode missing"
# a GIT_SSH program alone is left as is: it may not take ssh's -o
: > "$s/log"; git -C "$r" config --unset core.sshCommand
(unset GIT_SSH_COMMAND GIT_SSH_VARIANT; GIT_SSH="$s/ssh" evidence "$r" >/dev/null)
assert_not_contains "$(cat "$s/log")" "BatchMode" "ssh origin: BatchMode added to a GIT_SSH program"
[ -s "$s/log" ] || fail "ssh origin: GIT_SSH program not run"
# plink and the simple variant take no -o: by program name, by ssh.variant, by GIT_SSH_VARIANT
: > "$s/log"; cp "$s/ssh" "$s/PLink.exe"
(unset GIT_SSH GIT_SSH_VARIANT; GIT_SSH_COMMAND="\"$s/PLink.exe\" -batch" evidence "$r" >/dev/null)
git -C "$r" config core.sshCommand "$s/ssh"; git -C "$r" config ssh.variant plink
(unset GIT_SSH GIT_SSH_COMMAND GIT_SSH_VARIANT; evidence "$r" >/dev/null)
git -C "$r" config --unset ssh.variant
(unset GIT_SSH GIT_SSH_COMMAND; GIT_SSH_VARIANT=simple evidence "$r" >/dev/null)
assert_eq "$(grep -c . "$s/log")" 3 "ssh variants: not every fetch ran the ssh program"
assert_not_contains "$(cat "$s/log")" "BatchMode" "ssh variants: BatchMode given to plink or simple"
# as in git, a set but empty GIT_SSH_VARIANT means ssh over ssh.variant, and plink.exe as a setting is ssh
: > "$s/log"; git -C "$r" config ssh.variant plink
(unset GIT_SSH; GIT_SSH_VARIANT='' GIT_SSH_COMMAND="$s/ssh -e" evidence "$r" >/dev/null)
(unset GIT_SSH; GIT_SSH_VARIANT=plink.exe GIT_SSH_COMMAND="$s/ssh -x" evidence "$r" >/dev/null)
assert_contains "$(cat "$s/log")" "-e -o BatchMode=yes" "ssh variants: empty GIT_SSH_VARIANT not read as ssh"
assert_contains "$(cat "$s/log")" "-x -o BatchMode=yes" "ssh variants: plink.exe setting not read as ssh"

# 14. evidence and test-affected, no base branch anywhere: HEAD~1, labelled no base
r=$(stale_repo '{"project":"proj","gate":"true","testCommand":"echo"}'); git -C "$r" remote remove origin; git -C "$r" branch -qD main
h1=$(git -C "$r" rev-parse HEAD~1)
out=$(evidence "$r")
assert_contains "$out" "Base: HEAD~1 (no base)" "no base: Base line"
assert_contains "$out" "Merge base: $h1" "no base: merge base is HEAD~1"
assert_contains "$out" "mine.txt" "no base: own change listed"
out=$(cd "$r" && orca-lc test-affected 2>&1)
assert_contains "$out" "mine.txt" "no base: test-affected own change"
assert_not_contains "$out" "upstream.txt" "no base: test-affected reached past HEAD~1"
