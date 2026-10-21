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
    # Handoffs and discoveries are read by every session: scan what is about to land there. Labels never carry the
    # file name, so no output line can echo a denylisted one. Any scan exit but 1 lets the write through.
    if [ "$(jq -r '.leakCheck // empty' "$root/.orca/config.json")" = true ]; then
      sh=$(orca-lc config sharedDir 2>/dev/null); sh=${sh:-$root/.orca}
      dd=$(orca-lc config discoveriesDir 2>/dev/null); dd=${dd:-discoveries}
      dir=$(readlink -f "$(dirname "$f")" 2>/dev/null); kind=""
      for k in "handoff:$sh/handoffs" "discovery:$sh/$dd"; do
        base=$(readlink -f "${k#*:}" 2>/dev/null) || continue
        [ -n "$dir" ] && [ -n "$base" ] && [[ "$dir/" == "$base/"* ]] && { kind=${k%%:*}; break; }
      done
      if [ -n "$kind" ]; then
        hits=""
        scan() { local o; o=$(orca-lc leak-check --stdin "$1" 2>&1); [ $? = 1 ] && hits+=$(grep -v '^leak-check:' <<<"$o")$'\n'; }
        scan "$kind file name" <<<"$(basename "$f")"
        if [ "$tool" = MultiEdit ]; then
          n=$(jq '.tool_input.edits | length' <<<"$in")
          for ((i = 0; i < n; i++)); do scan "$kind body" < <(jq -r --argjson i "$i" '.tool_input.edits[$i].new_string // ""' <<<"$in"); done
        else
          scan "$kind body" < <(jq -r '.tool_input.content // .tool_input.new_string // ""' <<<"$in")
        fi
        [ -n "$hits" ] && block "$kind write blocked: denylisted term. Location, then the denylist line that matched:
${hits%$'\n'}
"
      fi
    fi
    ;;
esac
exit 0
