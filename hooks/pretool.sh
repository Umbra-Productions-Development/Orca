#!/usr/bin/env bash
# PreToolUse. Active only where <repo>/.orca/config.json exists. Exit 2 blocks; stderr reaches the session.
# Bash: push gate, merge block, commit-report, rebase and code-graph advice, then tool advice (Bash that
# reads, searches or writes files the Read/Grep/Glob/Write/Edit tools cover; once per session per kind).
set -uo pipefail
in=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$in"); cd "${cwd:-.}" 2>/dev/null || exit 0
cwd=$PWD
tool=$(jq -r '.tool_name' <<<"$in")
tail_msg="If this block was unexpected, record it: /discover"
block() { echo "orca-lc: $1. $tail_msg" >&2; exit 2; }
advise() { jq -n --arg m "$1" '{systemMessage:$m, hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$m}}'; exit 0; }
# Top of the repo holding $1 when it carries .orca/config.json, else nothing.
orca_root() { local r; r=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) && [ -f "$r/.orca/config.json" ] && echo "$r"; }
absdir() { case "$2" in /*) echo "$2";; "~") echo "$HOME";; "~/"*) echo "$HOME/${2#"~/"}";; *) echo "$1/$2";; esac; }

US=$'\x1f' RS=$'\x1e' GS=$'\x1d' PFX='^([A-Za-z_][A-Za-z0-9_]*=.*|env|command|exec|time|nohup)$'
# tokenize <command>: the command's segments, into the caller's S_W (words, quotes removed, US-joined),
# S_P (1 when fed by an unquoted |, not ||), S_R (redirects "op GS target", RS-joined, removed from the
# words), S_H (1 when it carries a heredoc) and S_HEAD (index of its pipeline's head). Callers declare
# them local. ; & | ( ) and newlines end a segment. Redirects come from unquoted characters only, with an
# optional fd digit; >&N, N>&M and <&N are fd duplications with target &N. Heredoc bodies are skipped.
tokenize() {
  local s=$1 n=${#1} i c tok="" has=0 q="" rop="" w=() r=() hd=0 np=0 hds=() ad=0
  for ((i=0; i<n; i++)); do c=${s:i:1}
    if [ "$q" = "'" ]; then [ "$c" = "'" ] && q="" || tok+=$c
    elif [ "$q" = '"' ]; then
      if [ "$c" = '"' ]; then q=""; elif [ "$c" = '\' ] && [[ "${s:i+1:1}" == [\"\\\$\`] ]]; then tok+=${s:i+1:1}; i=$((i+1)); else tok+=$c; fi
    else case "$c" in
      "'"|'"') q=$c; has=1;;
      '\') tok+=${s:i+1:1}; i=$((i+1)); has=1;;
      ' '|$'\t') _tw;;
      '>'|'<') if [ "$ad" -gt 0 ]; then tok+=$c; else _tr; fi;;   # inside (( )) they are arithmetic
      '&') if [ "${s:i+1:1}" = '>' ]; then _tr; else _tw; _ts; np=0; fi;;
      '|') _tw; _ts; if [ "${s:i+1:1}" = '|' ]; then i=$((i+1)); np=0; else np=1; [ "${s:i+1:1}" = '&' ] && i=$((i+1)); fi;;
      '(') [ "${s:i+1:1}" = '(' ] && { ad=$((ad+1)); i=$((i+1)); }; _tw; _ts; np=0;;
      ')') [ "$ad" -gt 0 ] && [ "${s:i+1:1}" = ')' ] && { ad=$((ad-1)); i=$((i+1)); }; _tw; _ts; np=0;;
      ';') _tw; _ts; np=0;;
      $'\n') _tw; _ts; np=0; [ ${#hds[@]} -gt 0 ] && _tb;;
      *) tok+=$c;;
    esac; fi
  done
  _tw; _ts
}
# tokenize's helpers, on its locals: end a word (a redirect target when an operator waits), end a segment,
# read a redirect operator at $i, skip heredoc bodies after the line at $i.
_tw() {
  if [ "$has$tok" != 0 ]; then
    if [ -n "$rop" ]; then r+=("$rop$GS$tok")
      # a heredoc delimiter is a word or quoted; `1<<3` is a shift, not a heredoc
      case "$rop" in '<<'|'<<-') { [ "$has" = 1 ] || [[ "$tok" =~ ^[A-Za-z_] ]]; } && { hds+=("$rop$GS$tok"); hd=1; };; esac; rop=""
    else w+=("$tok"); fi
  fi; tok=""; has=0
}
_ts() {
  rop=""
  if [ ${#w[@]} -gt 0 ]; then local k=${#S_W[@]} IFS=$US
    S_W+=("${w[*]}"); IFS=$RS; S_R+=("${r[*]}"); S_P+=("$np"); S_H+=("$hd")
    if [ "$np" = 1 ] && [ "$k" -gt 0 ]; then S_HEAD+=("${S_HEAD[k-1]}"); else S_HEAD+=("$k"); fi
  fi; w=(); r=(); hd=0
}
_tr() {
  local op t="" fd=""
  # a lone fd digit before the operator belongs to it; fds other than 0 and 1 stay on the op (2> is no file write)
  if [ "$has" = 0 ] && [[ "$tok" =~ ^[0-9]$ ]]; then [[ "$tok" == [01] ]] || fd=$tok; tok=""; else _tw; fi
  case "${s:i:3}" in
    '<<<'|'<<-'|'&>>') op=${s:i:3}; i=$((i+2));;
    *) case "${s:i:2}" in
      '<<'|'>>'|'>|'|'&>') op=${s:i:2}; i=$((i+1));;
      '>&'|'<&') i=$((i+2)); while [[ "${s:i:1}" == [0-9-] ]]; do t+=${s:i:1}; i=$((i+1)); done; i=$((i-1))
        r+=(">&$GS&$t"); rop=""; return;;
      *) op=$c;;
    esac;;
  esac
  rop=$fd$op
}
_tb() {
  local x op d rest ln
  for x in "${hds[@]}"; do op=${x%%"$GS"*}; d=${x#*"$GS"}
    while [ "$i" -lt "$n" ]; do rest=${s:i+1}; ln=${rest%%$'\n'*}; i=$((i+1+${#ln}))
      [ "$op" = '<<-' ] && ln=${ln#"${ln%%[!$'\t']*}"}
      [ "$ln" = "$d" ] && break
    done
  done; hds=()
}
# _split <joined>: the caller's seg, split on US.
_split() { local x=$1; seg=(); while [[ "$x" == *"$US"* ]]; do seg+=("${x%%"$US"*}"); x=${x#*"$US"}; done; seg+=("$x"); }

# git_targets <verb> [dir]: over the caller's segment list, the directory each `git [global opts] <verb>`
# acts on, one per line. `cd <dir>` carries into later segments (relative to the one before, from the
# payload cwd); -C stacks on it; --git-dir names the repo, whose worktree is printed (--work-tree, else a
# linked worktree's, else the .git's parent). `bash|sh -c "<cmd>"` is read as a command too.
git_targets() {
  local verb=$1 dir=${2:-$cwd} k seg=()
  for ((k=0; k<${#S_W[@]}; k++)); do _split "${S_W[k]}"; git_seg; done
}
# One segment of git_targets: reads and moves the caller's $dir, prints a target when it is git <verb>.
git_seg() {
  local j=0 a d gd="" wt=""
  while [ $j -lt ${#seg[@]} ] && [[ "${seg[j]}" =~ $PFX ]]; do j=$((j+1)); done
  case "${seg[j]:-}" in
    cd) a=${seg[j+1]:-"~"}; [ "$a" = - ] || dir=$(absdir "$dir" "$a"); return;;
    bash|sh) if [ "${seg[j+1]:-}" = -c ]; then local S_W=() S_P=() S_R=() S_H=() S_HEAD=(); tokenize "${seg[j+2]:-}"; git_targets "$verb" "$dir"; fi; return;;
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

# Value-taking options per command, so a value is never read as a file operand.
VO_head=" -n -c --lines --bytes "
VO_grep=" -A -B -C -m -e -f -d -D --after-context --before-context --context --max-count --regexp --file --directories --devices --include --exclude --exclude-dir --label "
VO_rg=" -A -B -C -m -e -f -g -t -T -j -M --glob --type --type-not --max-count --regexp --file --threads --max-columns "
VO_ag=" -A -B -C -m -G --file-search-regex --ignore --max-count "
VO_sed=" -e -f -l --expression --file --line-length "
# _cw <k>: segment k's command word, prefixes skipped.
_cw() { local seg=() j=0; _split "${S_W[$1]}"; while [ $j -lt ${#seg[@]} ] && [[ "${seg[j]}" =~ $PFX ]]; do j=$((j+1)); done; echo "${seg[j]:-}"; }
# tool_scan: "<kind> <cmd>" for the first segment of the caller's list that reads (read), searches
# (search), writes a new file (write) or changes one (edit) with a command a dedicated tool covers.
tool_scan() { local k o; for ((k=0; k<${#S_W[@]}; k++)); do o=$(tool_seg "$k"); [ -n "$o" ] && { echo "$o"; return; }; done; }
tool_seg() {
  local k=$1 seg=() j=0 c vo="" fl=" " ops=() a x ch m e=0 p op t h
  _split "${S_W[k]}"
  while [ $j -lt ${#seg[@]} ] && [[ "${seg[j]}" =~ $PFX ]]; do j=$((j+1)); done
  c=${seg[j]:-}
  case "$c" in
    bash|sh) if [ "${seg[j+1]:-}" = -c ]; then local S_W=() S_P=() S_R=() S_H=() S_HEAD=(); tokenize "${seg[j+2]:-}"; tool_scan; fi; return;;
    find) for x in "${seg[@]}"; do case "$x" in -exec|-execdir|-ok|-okdir|-delete) return;; esac; done; echo "search find"; return;;
    head|tail) vo=$VO_head;; grep|egrep|fgrep) vo=$VO_grep;; rg) vo=$VO_rg;; ag) vo=$VO_ag;; sed) vo=$VO_sed;;
    cat|less|more|bat|tee|echo|printf) ;;
    *) return;;
  esac
  for ((j=j+1; j<${#seg[@]}; j++)); do a=${seg[j]}
    if [ $e = 1 ] || [ "$a" = - ] || [[ "$a" != -* ]]; then ops+=("$a")
    elif [ "$a" = -- ]; then e=1
    elif [[ "$a" == --* ]]; then fl+="${a%%=*} "; [[ "$a" != *=* && "$vo" == *" $a "* ]] && j=$((j+1))
    else for ((m=1; m<${#a}; m++)); do ch=-${a:m:1}; fl+="$ch "
        if [[ "$vo" == *" $ch "* ]]; then [ $m -eq $((${#a}-1)) ] && j=$((j+1)); break; fi
      done
    fi
  done
  case "$c" in cat|echo|printf)
    x=${S_R[k]}; seg=(); while [ -n "$x" ]; do seg+=("${x%%"$RS"*}"); [[ "$x" == *"$RS"* ]] && x=${x#*"$RS"} || x=""; done
    for x in "${seg[@]}"; do op=${x%%"$GS"*}; t=${x#*"$GS"}
      { [ "$t" = /dev/null ] || [[ "$t" == '&'* ]]; } && continue
      case "$op" in '>'|'>|'|'&>') echo "write $c"; return;; '>>'|'&>>') echo "edit $c"; return;; esac
    done;;
  esac
  case "$c" in
    cat|head|tail|less|more|bat) [ ${#ops[@]} -gt 0 ] && echo "read $c";;
    sed) p=1; [[ "$fl" =~ \ (-e|-f|--expression|--file)\  ]] && p=0
      if [[ "$fl" =~ \ (-i|--in-place)\  ]]; then [ ${#ops[@]} -gt $p ] && echo "edit sed"
      elif [[ "$fl" =~ \ (-n|--quiet|--silent)\  ]]; then [ ${#ops[@]} -gt $p ] && echo "read sed"; fi;;
    grep|egrep|fgrep|rg|ag) [ "$c" = rg ] && [[ "$fl" == *" --files "* ]] && { echo "glob rg"; return; }
      p=1; [[ "$fl" =~ \ (-e|-f|--regexp|--file)\  ]] && p=0
      if [ ${#ops[@]} -gt $p ]; then echo "search $c"
      elif [ "${S_P[k]}" != 1 ]; then
        case "$c" in rg|ag) echo "search $c";; *) [[ "$fl" =~ \ (-r|-R|--recursive|--dereference-recursive)\  ]] && echo "search $c";; esac
      fi;;
    tee) [ ${#ops[@]} -gt 0 ] || return; h=${S_HEAD[k]}
      if [ "${S_H[h]}" = 1 ] || [[ "$(_cw "$h")" =~ ^(cat|echo|printf)$ ]]; then
        if [[ "$fl" =~ \ (-a|--append)\  ]]; then echo "edit tee"; else echo "write tee"; fi
      fi;;
  esac
}

# push and commit are judged in the repo they act on, not the session's cwd: a push into an Orca repo is
# gated from wherever it is typed, and one into a repo without .orca/config.json is left alone even from
# an Orca cwd. Everything else stays active only where the cwd's repo carries the config.
root=$(orca_root .)
case "$tool" in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
    S_W=() S_P=() S_R=() S_H=() S_HEAD=(); tokenize "$cmd"   # one segment list for every consumer below
    while IFS= read -r t; do
      [ -n "$(orca_root "$t")" ] || continue
      (cd "$t" && orca-lc gate-fresh) || block "git push blocked: gate marker missing or stale for $t. Run 'orca-lc gate' there and push only after it passes"
    done < <(git_targets push)
    [ -n "$root" ] && grep -qE '(^|[;&|]\s*)git\s+merge([^-[:alnum:]_]|$)' <<<"$cmd" && block "git merge blocked: PRs merge on GitHub (gh pr merge). A local merge closes the PR without review"
    t=$(git_targets commit | head -1)
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
    # Bash reading, searching or writing files the dedicated tools cover: once per session per kind.
    [ "$(jq -r '.toolAdvice' "$root/.orca/config.json")" = false ] && exit 0
    ta=$(tool_scan); [ -n "$ta" ] || exit 0
    ta_kind=${ta%% *} ta_cmd=${ta#* }; ta_mk=$ta_kind; case "$ta_kind" in edit) ta_mk=write;; glob) ta_mk=search;; esac
    sid=$(jq -r '.session_id // ""' <<<"$in")
    if [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]]; then
      ta_dir="$(git rev-parse --git-dir)/orca-tool-advice"
      [ -e "$ta_dir/$sid-$ta_mk" ] && exit 0
      mkdir -p "$ta_dir" && : > "$ta_dir/$sid-$ta_mk"
    fi
    ta_off="Set toolAdvice: false in .orca/config.json to silence this."
    case "$ta_kind" in
      read) advise "Bash \`$ta_cmd\` reads a file: the Read tool covers it (line-numbered, no output cap). $ta_off";;
      search) advise "Bash \`$ta_cmd\` searches files: the Grep tool (Glob for find) covers it. $ta_off";;
      glob) advise "Bash \`$ta_cmd\` lists files: the Glob tool covers it. $ta_off";;
      write) advise "Bash \`$ta_cmd\` writes a file: the Write tool covers it. $ta_off";;
      edit) advise "Bash \`$ta_cmd\` changes a file: the Edit tool covers it. $ta_off";;
    esac
    ;;
  Edit|Write|MultiEdit)
    [ -n "$root" ] || exit 0
    f=$(jq -r '.tool_input.file_path // ""' <<<"$in")
    glob=$(jq -r '.testGlob // empty' "$root/.orca/config.json")
    if [ -n "$glob" ] && grep -qE "$glob" <<<"$f" && [ ! -f "$(git rev-parse --git-dir)/orca-allow-test-edits" ]; then
      block "test file edit blocked ($f). Fixing code must not weaken its checks. If the test itself is wrong or a scenario is missing, run 'orca-lc test-lock on' and say why in the commit body"
    fi
    ;;
esac
exit 0
