#!/usr/bin/env bash
# PreToolUse. Active only where <repo>/.orca/config.json exists. Exit 2 blocks; stderr reaches the session.
set -uo pipefail
in=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$in"); cd "${cwd:-.}" 2>/dev/null || exit 0
cwd=$PWD
tool=$(jq -r '.tool_name' <<<"$in")
tail_msg="If this block was unexpected, record it: /discover"
block() { echo "orca-lc: $1. $tail_msg" >&2; exit 2; }
advise() { jq -n --arg m "$1" '{systemMessage:$m, hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$m}}'; exit 0; }
# Absolute, symlink-free form of a path whose tail may not exist yet: the existing head through cd -P, the missing
# tail lexically, where ".." drops the component before it. readlink -f needs all but the last part, BSD has no -m.
abspath() { local d="$1" rest="" b up=0
  while [ ! -d "$d" ]; do
    b=$(basename "$d"); d=$(dirname "$d")
    case "$b" in .) ;; ..) up=$((up + 1));; *) if [ $up -gt 0 ]; then up=$((up - 1)); else rest="/$b$rest"; fi;; esac
  done
  d=$(cd -P "$d" 2>/dev/null && pwd -P) || return 1
  while [ $up -gt 0 ]; do d=$(dirname "$d"); up=$((up - 1)); done
  d="${d%/}$rest"; echo "${d:-/}"
}
# Top of the repo holding $1 when it carries .orca/config.json, else nothing.
orca_root() { local r; r=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) && [ -f "$r/.orca/config.json" ] && echo "$r"; }
absdir() { case "$2" in /*) echo "$2";; "~") echo "$HOME";; "~/"*) echo "$HOME/${2#"~/"}";; *) echo "$1/$2";; esac; }

# git_targets <verb> <command> [dir]: the directory each `git [global opts] <verb>` in the command acts on,
# one per line. Words split with shell quoting; ; & | ( ) and newlines end a segment. `cd <dir>` carries
# into later segments (relative to the one before, from the payload cwd); -C stacks on it; --git-dir names
# the repo, whose worktree is printed (--work-tree, else a linked worktree's, else the .git's parent).
# `bash|sh -c "<cmd>"` is read as a command too.
git_targets() {
  local verb=$1 s=$2 dir=${3:-$cwd} w=() tok="" has=0 q="" c i n=${#2} sep=$'\x1f'
  for ((i=0; i<n; i++)); do c=${s:i:1}
    if [ "$q" = "'" ]; then [ "$c" = "'" ] && q="" || tok+=$c
    elif [ "$q" = '"' ]; then
      if [ "$c" = '"' ]; then q=""; elif [ "$c" = '\' ] && [[ "${s:i+1:1}" == [\"\\\$\`] ]]; then tok+=${s:i+1:1}; i=$((i+1)); else tok+=$c; fi
    else case "$c" in
      "'"|'"') q=$c; has=1;;
      '\') tok+=${s:i+1:1}; i=$((i+1)); has=1;;
      ' '|$'\t') [ "$has$tok" != 0 ] && w+=("$tok"); tok=""; has=0;;
      ';'|'&'|'|'|'('|')'|$'\n') [ "$has$tok" != 0 ] && w+=("$tok"); w+=("$sep"); tok=""; has=0;;
      *) tok+=$c;;
    esac; fi
  done
  [ "$has$tok" != 0 ] && w+=("$tok"); w+=("$sep")
  local seg=() x
  for x in "${w[@]}"; do if [ "$x" = "$sep" ]; then [ ${#seg[@]} -gt 0 ] && git_seg; seg=(); else seg+=("$x"); fi; done
}
# One segment of git_targets: reads and moves the caller's $dir, prints a target when it is git <verb>.
git_seg() {
  local j=0 a d gd="" wt=""
  while [ $j -lt ${#seg[@]} ] && [[ "${seg[j]}" =~ ^([A-Za-z_][A-Za-z0-9_]*=.*|env|command|exec|time|nohup)$ ]]; do j=$((j+1)); done
  case "${seg[j]:-}" in
    cd) a=${seg[j+1]:-"~"}; [ "$a" = - ] || dir=$(absdir "$dir" "$a"); return;;
    bash|sh) [ "${seg[j+1]:-}" = -c ] && git_targets "$verb" "${seg[j+2]:-}" "$dir"; return;;
    git) ;; *) return;;
  esac
  d=$dir; j=$((j+1))
  while [ $j -lt ${#seg[@]} ]; do a=${seg[j]}
    case "$a" in
      -C) d=$(absdir "$d" "${seg[j+1]:-.}"); j=$((j+2));;
      --git-dir) gd=$(absdir "$d" "${seg[j+1]:-}"); j=$((j+2));;
      --git-dir=*) gd=$(absdir "$d" "${a#*=}"); j=$((j+1));;
      --work-tree) wt=$(absdir "$d" "${seg[j+1]:-}"); j=$((j+2));;
      --work-tree=*) wt=$(absdir "$d" "${a#*=}"); j=$((j+1));;
      -c|--namespace|--config-env|--super-prefix) j=$((j+2));;
      -*) j=$((j+1));;
      *) break;;
    esac
  done
  [ "${seg[j]:-}" = "$verb" ] || return 0
  gd=${gd%/}
  if [ -n "$wt" ]; then echo "$wt"
  elif [ -n "$gd" ] && [ -f "$gd/gitdir" ]; then dirname "$(cat "$gd/gitdir")"
  elif [ -n "$gd" ]; then echo "${gd%/.git}"
  else echo "$d"; fi
}

# push and commit are judged in the repo they act on, not the session's cwd: a push into an Orca repo is
# gated from wherever it is typed, and one into a repo without .orca/config.json is left alone even from
# an Orca cwd. Everything else stays active only where the cwd's repo carries the config.
root=$(orca_root .)
case "$tool" in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
    while IFS= read -r t; do
      [ -n "$(orca_root "$t")" ] || continue
      (cd "$t" && orca-lc gate-fresh) || block "git push blocked: gate marker missing or stale for $t. Run 'orca-lc gate' there and push only after it passes"
    done < <(git_targets push "$cmd")
    [ -n "$root" ] && grep -qE '(^|[;&|]\s*)git\s+merge([^-[:alnum:]_]|$)' <<<"$cmd" && block "git merge blocked: PRs merge on GitHub (gh pr merge). A local merge closes the PR without review"
    t=$(git_targets commit "$cmd" | head -1)
    if [ -n "$t" ] && [ -n "$(orca_root "$t")" ]; then
      # Ticket from the committed tree (its path and branch), not the identity: that falls back to the project name.
      r=$(orca-lc name 2>/dev/null | jq -r '.role // ""'); tk=$(cd "$t" && orca-lc ticket 2>/dev/null)
      case "$r" in ""|session|orchestrator) ;; *) [ -n "$tk" ] && advise "Once this commit lands, report it: orca-lc notify $tk --role orchestrator \"<sha> <subject>\"";; esac
    fi
    [ -n "$root" ] || exit 0
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
    [ -n "$root" ] || exit 0
    f=$(jq -r '.tool_input.file_path // ""' <<<"$in")
    glob=$(jq -r '.testGlob // empty' "$root/.orca/config.json")
    if [ -n "$glob" ] && grep -qE "$glob" <<<"$f" && [ ! -f "$(git rev-parse --git-dir)/orca-allow-test-edits" ]; then
      block "test file edit blocked. Fixing code must not weaken its checks. If the test itself is wrong or a scenario is missing, run 'orca-lc test-lock on' and say why in the commit body"
    fi
    # Handoffs and discoveries are read by every session: scan what is about to land there. Labels never carry the
    # file name, so no output line can echo a denylisted one. Exit 1 blocks with the hits; any exit but 0 and 1 (an
    # unreadable denylist, an orca-lc without leak-check) blocks too, since the write was not checked.
    if [ "$(jq -r '.leakCheck // empty' "$root/.orca/config.json")" = true ]; then
      sh=$(orca-lc config sharedDir 2>/dev/null); sh=${sh:-$root/.orca}
      dd=$(orca-lc config discoveriesDir 2>/dev/null); dd=${dd:-discoveries}
      dir=$(abspath "$(dirname "$f")"); kind=""
      for k in "handoff:$sh/handoffs" "discovery:$sh/$dd"; do
        base=$(abspath "${k#*:}") || continue
        [ -n "$dir" ] && [ -n "$base" ] && [[ "$dir/" == "$base/"* ]] && { kind=${k%%:*}; break; }
      done
      if [ -n "$kind" ]; then
        hits=""
        scan() { local o s r=""; o=$(orca-lc leak-check --stdin "$1" 2>&1); s=$?
          case $s in
            0) ;;
            1) hits+=$(grep -v '^leak-check:' <<<"$o")$'\n';;
            # Only the fixed unreadable-list line is echoed; any other output may carry a path.
            *) grep -qE '^orca-lc: leak-check: (global|project) denylist unreadable$' <<<"$o" && r=" (${o#orca-lc: })"
               block "$kind write blocked: leak scan failed (exit $s), write not checked$r";;
          esac; }
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
