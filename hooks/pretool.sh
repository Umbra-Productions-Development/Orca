#!/usr/bin/env bash
# PreToolUse. Active only where <repo>/.orca/config.json exists. Exit 2 blocks; stderr reaches the session.
set -uo pipefail
in=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$in"); cd "${cwd:-.}" 2>/dev/null || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/.orca/config.json" ] || exit 0
tool=$(jq -r '.tool_name' <<<"$in")
tail_msg="If this block was unexpected, record it: /discover"
block() { echo "orca-lc: $1. $tail_msg" >&2; exit 2; }
advise() { jq -n --arg m "$1" '{systemMessage:$m, hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$m}}'; exit 0; }

case "$tool" in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
    if grep -qE '(^|[;&|]\s*)git\s+push\b' <<<"$cmd"; then
      orca-lc gate-fresh || block "git push blocked: gate marker missing or stale for this tree. Run 'orca-lc gate' and push only after it passes"
    fi
    grep -qE '(^|[;&|]\s*)git\s+merge([^-[:alnum:]_]|$)' <<<"$cmd" && block "git merge blocked: PRs merge on GitHub (gh pr merge). A local merge closes the PR without review"
    if grep -qE '(^|[;&|]\s*)git\s+commit\b' <<<"$cmd"; then
      me=$(orca-lc name 2>/dev/null); r=$(jq -r '.role // ""' <<<"$me")
      case "$r" in ""|session|orchestrator) ;; *) advise "Once this commit lands, report it: orca-lc notify $(jq -r .ticket <<<"$me") --role orchestrator \"<sha> <subject>\"";; esac
    fi
    # A sleep whose answer is already on its way: the runtime wakes the session when the turn ends. Every other sleep passes.
    if [ "$(jq -r '.tool_input.run_in_background // false' <<<"$in")" != true ] && grep -qE '(^|[^[:alnum:]_-])sleep\s+[0-9]' <<<"$cmd"; then
      wake="End the turn instead: its completion wakes this session, inside a subagent too"
      grep -qE '/tasks/[^[:space:]]+\.output' <<<"$cmd" && block "sleep before reading a background task's output. $wake"
      tp=$(jq -r '.transcript_path // empty' <<<"$in")
      if [ -f "$tp" ]; then
        for f in $(grep -oE "[^[:space:];|&<>\"'=]+\.(log|out|txt)\b" <<<"$cmd" | sort -u); do
          grep -F -- "$f" "$tp" | jq -e --arg f "$f" 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .input.run_in_background==true and ((.input.command // "") | contains($f)))' >/dev/null 2>&1 \
            && block "sleep before reading $f, which a background command of this session writes. $wake"
        done
      fi
      grep -qE '(herdr\s+agent\s+(get|list|read)|orca-lc\s+(peers|inbox))\b' <<<"$cmd" && block "sleep before checking a peer. Its 'orca-lc notify' wakes this session once the turn ends; to block until it changes state, use 'herdr agent wait <peer> --until idle --timeout <ms>'"
      grep -qE 'gh\s+(pr\s+(view|checks)|run\s+(view|list))\b' <<<"$cmd" && block "sleep around a CI poll. Run 'gh pr checks <n> --watch' with run_in_background: true and end the turn; its completion wakes this session"
    fi
    grep -qE '(^|[;&|]\s*)git\s+rebase\b' <<<"$cmd" && advise "After the rebase, run the gate's type check even when git reports no conflict: two edits to different lines of one logic rebase clean and still break the build."
    # discovery-shaped commands over source: the graph answers cheaper. Off until sourceGlob is set.
    src=$(jq -r '.sourceGlob // empty' "$root/.orca/config.json")
    if [ -n "$src" ] && grep -qE '^\s*(rg|grep|egrep|ag)\b' <<<"$cmd" && grep -qE "$src" <<<"$cmd"; then
      pat=$(grep -oE "(rg|grep|egrep|ag)\b[^'\"]*['\"]([^'\"]+)['\"]" <<<"$cmd" | sed -E "s/.*['\"]([^'\"]+)['\"]$/\1/" | head -1)
      if [ -n "$pat" ] && grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' <<<"$pat"; then
        advise "Graph answers this in one call: codegraph_explore \"$pat\" returns its source, callers and blast radius. Use Bash grep only if the graph has no such symbol."
      else
        advise "Searching source by phrase: codebase-memory search_graph (semantic mode) finds it by meaning; codegraph_explore by symbol. Use Bash grep only if neither knows it."
      fi
    fi
    if [ -n "$src" ] && grep -qE '^\s*(cat|sed\s+-n|head|tail)\b' <<<"$cmd" && grep -qE "$src" <<<"$cmd"; then
      advise "Reading a source file: codegraph_explore <file or symbol> gives line-numbered source plus who calls it; Read gives the file. Bash cat sends the whole file as command output."
    fi
    ;;
  Edit|Write|MultiEdit)
    f=$(jq -r '.tool_input.file_path // ""' <<<"$in")
    glob=$(jq -r '.testGlob // empty' "$root/.orca/config.json")
    if [ -n "$glob" ] && grep -qE "$glob" <<<"$f" && [ ! -f "$(git rev-parse --git-dir)/orca-allow-test-edits" ]; then
      block "test file edit blocked ($f). Fixing code must not weaken its checks. If the test itself is wrong or a scenario is missing, run 'orca-lc test-lock on' and say why in the commit body"
    fi
    ;;
esac
exit 0
