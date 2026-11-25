#!/usr/bin/env bash
# PreToolUse. Active only where <repo>/.orca/config.json exists: the repo a push, commit or edited file acts on,
# else the session cwd's. Exit 2 blocks; stderr reaches the session.
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
# Absolute, symlink-free form of a path whose tail may not exist yet, walked left to right as mkdir -p would: each
# existing directory is resolved through cd -P, so a symlink after a missing dir and ".." is still followed; a missing
# one is kept as written, and ".." drops the last component. readlink -f fails past one missing part; BSD has no -m.
# The result goes to $ap, not stdout: $(...) would strip a trailing newline from the last name.
# Reads ".." physically, after any link before it: use it to compare directories, as the leak scan does. For
# the path an edit names use textpath first, as the test lock does, so no ".." is left for abspath to read.
# A non-empty $2 (Windows) also takes a drive (C:/) or UNC (//host) root as absolute.
abspath() { local p="$1" c d; ap=""
  case "$p" in /*) d=/;; *) d=$(pwd -P);; esac
  if [ -n "${2:-}" ]; then case "$p" in
    # The drive root itself goes through cd -P too, so a file right under it reads /c/x.sh as in Git Bash.
    [A-Za-z]:/*) d=${p:0:2}; p=${p:3}
      [ -d "$d/" ] && { d=$(CDPATH='' cd -P -- "$d/" 2>/dev/null && pwd -P) || return 1; };;
    //?*) p=${p#//}; d=//${p%%/*}; case "$p" in */*) p=${p#*/};; *) p="";; esac;;
  esac; fi
  while [ -n "$p" ]; do
    c=${p%%/*}; if [ "$c" = "$p" ]; then p=""; else p=${p#*/}; fi
    case "$c" in ""|.) ;; ..) d=${d%/*}; d=${d:-/};; *) d="${d%/}/$c";; esac
    # The trailing x keeps a name ending in a newline whole; $(...) would strip it. cd's error would echo the path.
    [ -d "$d" ] && { d=$(CDPATH='' cd -P -- "$d" 2>/dev/null && pwd -P && echo x) || return 1; d=${d%$'\n'x}; }
  done
  ap=$d
}
# Top of the repo holding $1 when it carries .orca/config.json, else nothing.
orca_root() { local r; r=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) && [ -f "$r/.orca/config.json" ] && echo "$r"; }
# textpath <path with / separators>: . and .. collapsed as text (like Node's path.resolve), links not
# followed. Keeps a leading /, // (UNC) or drive (C:/); .. above the root stays at the root.
# Reads ".." as text, the way Claude Code resolves a file_path before it follows any link: use it for the
# path an edit names, then abspath for its physical form. For comparing directories use abspath alone.
textpath() {
  local s=$1 pre="" c out=() parts=() IFS=/
  case "$s" in //*) pre=//;; /*) pre=/;; [A-Za-z]:/*) pre=${s:0:3};; esac
  read -rd '' -a parts < <(printf %s "${s#"$pre"}") || true
  for c in "${parts[@]}"; do
    case "$c" in ""|.) ;; ..) [ ${#out[@]} -gt 0 ] && unset 'out[${#out[@]}-1]';; *) out+=("$c");; esac
  done
  echo "$pre${out[*]}"
}
absdir() { case "$2" in /*) echo "$2";; "~") echo "$HOME";; "~/"*) echo "$HOME/${2#"~/"}";; *) echo "$1/$2";; esac; }

US=$'\x1f' RS=$'\x1e' GS=$'\x1d' PFX='^([A-Za-z_][A-Za-z0-9_]*=.*|env|command|exec|time|nohup)$'
# tokenize <command>: the command's segments, into the caller's S_W (words, quotes removed, US-joined),
# S_P (1 when fed by an unquoted |, not ||), S_R (redirects "op GS target", RS-joined, removed from the
# words), S_H (1 when it carries a heredoc) and S_HEAD (index of its pipeline's head). Callers declare
# them local; it appends to them. ; & | ( ) and newlines end a segment. Redirects come from unquoted
# characters only, with an optional fd digit; >&N, N>&M and <&N are fd duplications with target &N.
# Heredoc bodies are skipped. An unquoted # starting a word right after a blank, newline, ; & or | (or at
# the start) comments out the rest of its line. $'..' and $".." drop the $, as bash does ($'..' follows \'
# and \\); dqs, dqn and dqh track $( ), ${ } and backticks inside ".." (_tdq); an unquoted $(( )) is one
# word (_tarith). It feeds the tool advice and, beside main_targets, the push and commit checks. A
# misread here can hide only what main_targets still reads, except where main's own quote reading drifts
# from bash; for those, S_AMB (the caller's) is set to 1 on a heredoc with no exact terminator or a quote
# the parse may have misread (_tdq, _tdqh, _tdqb): one left open, another escape in $'..', or, inside a $( ),
# ${ } or backtick of "..", a " or ', \, a # not after a word character, case, a ) or } that does not match
# the innermost open (, { or backtick, a heredoc WORD that is not plain text, or a heredoc body there with no
# terminator. A plain '..' there (_tdqsq) sets it only when a ; & | or newline is also in the open
# substitutions. new_targets then adds raw_targets.
tokenize() {
  # LC_ALL=C first, alone: ${s:i:1} is O(1) per byte instead of O(i) per character, and n counts bytes
  local LC_ALL=C; local s=$1 n=${#1} i c tok="" has=0 q="" rop="" w=() r=() hd=0 np=0 hds=() dqs='' dqn=0 dqh=() dqx=0 dqp=0 tas=0 raw=${TK_RAW:-}
  for ((i=0; i<n; i++)); do c=${s:i:1}
    if [ "$q" = "'" ]; then [ "$c" = "'" ] && q="" || tok+=$c
    elif [ "$q" = A ]; then   # $'..': \' and \\ followed, any other escape is not modelled
      if [ "$c" = "'" ]; then q=""
      elif [ "$c" = '\' ]; then
        [[ "${s:i+1:1}" == [\'\\] ]] || { S_AMB=1; tok+=$c; }
        tok+=${s:i+1:1}; i=$((i+1))
      else tok+=$c; fi
    elif [ "$q" = '"' ]; then case "$c" in '"'|'\'|'$'|'('|'{'|')'|'}'|'`'|"'"|'#'|'<'|$'\n'|c|';'|'&'|'|') _tdq;; *) tok+=$c;; esac
    else case "$c" in
      "'"|'"') if [ -n "$raw" ]; then tok+=$c; continue; fi; q=$c; has=1; dqs=''; dqn=0; dqh=(); dqx=0; dqp=0
        if [ "${tok: -1}" = '$' ] && _tansi; then tok=${tok%?}; [ "$c" = "'" ] && q=A; fi;;
      '\') tok+=${s:i+1:1}; i=$((i+1)); has=1;;
      ' '|$'\t') _tw;;
      '>'|'<') _tr;;
      '#') if [ "$has$tok" != 0 ] || [ -n "$raw" ] || { [ "$i" -gt 0 ] && [[ "${s:i-1:1}" != [' '$'\t'$'\n'';&|'] ]]; }; then tok+=$c
        else while [ $((i+1)) -lt "$n" ] && [ "${s:i+1:1}" != $'\n' ]; do i=$((i+1)); done; fi;;
      '&') if [ "${s:i+1:1}" = '>' ]; then _tr; else _tw; _ts; np=0; fi;;
      '|') _tw; _ts; if [ "${s:i+1:1}" = '|' ]; then i=$((i+1)); np=0; else np=1; [ "${s:i+1:1}" = '&' ] && i=$((i+1)); fi;;
      ';'|'('|')') _tw; _ts; np=0;;
      '$') tok+=$c; [ "${s:i+1:2}" = '((' ] && _tarith;;
      $'\n') _tw; _ts; np=0; [ ${#hds[@]} -gt 0 ] && { if [ -z "$raw" ]; then _tb; else hds=(); fi; };;
      *) tok+=$c;;
    esac; fi
  done
  _tw; _ts
  [ -n "$q" ] && S_AMB=1
  return 0
}
# tokenize's helpers, on its locals: end a word (a redirect target when an operator waits), end a segment,
# read a redirect operator at $i, skip heredoc bodies after the line at $i.
_tw() {
  if [ "$has$tok" != 0 ]; then
    if [ -n "$rop" ]; then r+=("$rop$GS$tok")
      case "$rop" in '<<'|'<<-') hds+=("$rop$GS$tok"); hd=1;; esac; rop=""
    else w+=("$tok"); fi
  fi; tok=""; has=0
}
# _tdq: one character $c inside "..". A $( ), ${ } or backtick opened in these quotes (dqs the stack of open
# (, { and backticks, dqn once any opened) is a shell of its own that this does not parse, except for
# heredocs (_tdqh, _tdqb: the body kept raw in the word, as bash reads it) and plain '..' (_tdqsq). What
# in one could end it, or the outer string, where bash would not, sets S_AMB (the list is at tokenize).
_tdq() {
  local z=${#dqs}
  if [ "$c" = '"' ]; then [ "$z" -gt 0 ] && S_AMB=1; q=""
  elif [ "$c" = '\' ]; then [ "$z" -gt 0 ] && S_AMB=1
    if [[ "${s:i+1:1}" == [\"\\\$\`] ]]; then tok+=${s:i+1:1}; i=$((i+1)); else tok+=$c; fi
  else tok+=$c
    case "$c" in
      '$') [[ "${s:i+1:1}" == [\({] ]] && { dqs+=${s:i+1:1}; dqn=1; tok+=${s:i+1:1}; i=$((i+1)); };;
      '('|'{') [ -n "$dqs" ] && dqs+=$c;;
      ')'|'}') if [ -n "$dqs" ]; then case "${dqs: -1}$c" in '()'|'{}') ;; *) S_AMB=1;; esac; _tdqpop
        elif [ "$dqn" = 1 ]; then S_AMB=1; fi;;
      '`') if [ "${dqs: -1}" = '`' ]; then _tdqpop; else dqs+=$c; fi; dqn=1;;
      ';'|'&'|'|') [ "$z" -gt 0 ] && _tdqsep;;
      "'") if _tdqsq; then [ "$dqp" = 0 ] || S_AMB=1; elif [ "$z" -gt 0 ]; then S_AMB=1; fi;;
      '#') [ "$z" -gt 0 ] && [[ "${s:i-1:1}" != [A-Za-z0-9_\$\{/.:=,+@%^~-] ]] && S_AMB=1;;
      c) [ "$z" -gt 0 ] && [ "${s:i:4}" = case ] && [[ "${s:i-1:1}" == [' '$'\t'$'\n'';&|(`'] ]] \
           && [[ "${s:i+4:1}" == [' '$'\t'$'\n'] ]] && S_AMB=1;;
      '<') [ "$z" -gt 0 ] && [ "${s:i+1:1}" = '<' ] && _tdqh;;
      $'\n') if [ ${#dqh[@]} -gt 0 ]; then _tdqb; elif [ "$z" -gt 0 ]; then _tdqsep; fi;;
    esac
  fi
  return 0
}
# _tdqsq: at a ' (not $') inside "..", with a ( innermost (of $( ), $(( )) or a subshell) and no backtick
# open, read to the next ' as bash does there, when that text holds none of " ` \ ( ) { } $ or a newline:
# skipping such text changes nothing this reader tracks, even in $(( )), where bash does not quote. False
# when it does not apply; the caller sets S_AMB either way.
_tdqsq() {
  [ "${dqs: -1}" = '(' ] && [[ "$dqs" != *'`'* ]] && [ "${s:i-1:1}" != '$' ] || return 1
  local t=${s:i+1}; t=${t%%"'"*}
  [ $((i+1+${#t})) -lt "$n" ] && [[ "$t" != *[\"\`\\\(\)\{\}\$$'\n']* ]] || return 1
  tok+=$t"'"; i=$((i+1+${#t})); dqx=1
}
# dqx: a '..' was read by _tdqsq in the open substitutions; dqp: a ; & | or newline is in them. Both at
# once, in either order, set S_AMB: the separator may start a command this reader does not parse, which
# the raw reading finds. A command first in the substitution, or in one nested in it, is not read, here or
# by main_targets. Both reset when the last open substitution closes (_tdqpop).
_tdqsep() { dqp=1; [ "$dqx" = 0 ] || S_AMB=1; }
_tdqpop() { dqs=${dqs%?}; [ -n "$dqs" ] || { dqx=0; dqp=0; }; }
# _tdqh: the << at $i inside a substitution of "..": queue its WORD (<<- marked by a leading 1). <<< is a
# here-string. A WORD that is not plain [A-Za-z0-9_] text, whole or in one pair of quotes, sets S_AMB.
_tdqh() {
  local j=$((i+2)) t=0 w e
  if [ "${s:j:1}" = '<' ]; then tok+='<<'; i=$((i+2)); return; fi
  [ "${s:j:1}" = - ] && { t=1; j=$((j+1)); }
  while [[ "${s:j:1}" == [' '$'\t'] ]]; do j=$((j+1)); done
  e=${s:j:1}
  if [[ "$e" == [\'\"] ]]; then w=${s:j+1}; w=${w%%"$e"*}; j=$((j+${#w}+2)); [ "${s:j-1:1}" = "$e" ] || w=""
  else w=${s:j}; w=${w%%[!A-Za-z0-9_]*}; j=$((j+${#w})); fi
  if [ -z "$w" ] || [[ "$w" == *[!A-Za-z0-9_]* ]] || { [ "$j" -lt "$n" ] && [[ "${s:j:1}" != [' '$'\t'$'\n'')|;&'] ]]; }; then
    S_AMB=1; return; fi
  tok+=${s:i+1:j-i-1}; i=$((j-1)); dqh+=("$t$w")
}
# _tdqb: at the newline at $i, keep each queued heredoc body raw in the word, through its terminator line;
# a body with no terminator runs to the end and sets S_AMB.
_tdqb() {
  local h l
  for h in "${dqh[@]}"; do
    while :; do
      [ $((i+1)) -lt "$n" ] || { S_AMB=1; dqh=(); return; }
      l=${s:i+1}; l=${l%%$'\n'*}; tok+=$'\n'$l; i=$((i+1+${#l}))
      [ "${h:0:1}" = 1 ] && while [ "${l:0:1}" = $'\t' ]; do l=${l:1}; done
      [ "$l" = "${h:1}" ] && break
    done
  done; dqh=()
}
# _tarith: at the $ of an unquoted $(( at $i, take the expansion to its matching )) into the word, so a <<
# in it is a shift, not a heredoc; one holding a quote, \, backtick or newline, or left open, is left to the
# main loop. A failed scan records where it stopped (tas) and no $(( before that is scanned again, so the
# scans stay linear in the command. A valid $(( )) nested in a failed one is then read character by
# character too: its << can read later lines as a heredoc body, hiding them from this reading, not from
# main_targets.
_tarith() {
  local j=$((i+3)) d=2
  [ "$j" -ge "$tas" ] || return 0
  while [ "$j" -lt "$n" ] && [ "$d" -gt 0 ]; do
    case "${s:j:1}" in '(') d=$((d+1));; ')') d=$((d-1));; [\'\"\`\\]|$'\n') tas=$j; return 0;; esac; j=$((j+1))
  done
  [ "$d" = 0 ] || { tas=$j; return 0; }; tok+=${s:i+1:j-i-1}; i=$((j-1))
}
# _tansi: true when the quote at $i follows a $ that bash reads as $'..' or $"..": an odd run of unescaped $
# (an even run is $$ pairs, the PID). An odd run of \ before the $ run escapes its first $.
_tansi() {
  local k=$((i-1)) d=0 b=0
  while [ "$k" -ge 0 ] && [ "${s:k:1}" = '$' ]; do d=$((d+1)); k=$((k-1)); done
  while [ "$k" -ge 0 ] && [ "${s:k:1}" = '\' ]; do b=$((b+1)); k=$((k-1)); done
  [ $(( (d - b % 2) % 2 )) = 1 ]
}
_ts() {
  rop=""
  if [ ${#w[@]} -gt 0 ]; then local k=${#S_W[@]} IFS=$US
    S_W+=("${w[*]}"); IFS=$RS; S_R+=("${r[*]}"); S_P+=("$np"); S_H+=("$hd")
    if [ "$np" = 1 ] && [ "$k" -gt 0 ]; then S_HEAD+=("${S_HEAD[k-1]}"); else S_HEAD+=("$k"); fi
  fi; w=(); r=(); hd=0
}
_tr() {
  local op fd=""
  # a lone fd digit before the operator belongs to it; fds other than 0 and 1 stay on the op (2> is no file write)
  if [ "$has" = 0 ] && [[ "$tok" =~ ^[0-9]$ ]]; then [[ "$tok" == [01] ]] || fd=$tok; tok=""; else _tw; fi
  case "${s:i:3}" in
    '<<<'|'<<-'|'&>>') op=${s:i:3}; i=$((i+2));;
    *) case "${s:i:2}" in
      '<<'|'>>'|'>|'|'&>') op=${s:i:2}; i=$((i+1));;
      # >&N, <&N, >&-, >&$fd (a space after the & allowed) duplicate an fd; >&word writes stdout and stderr to word, as &> does
      '>&'|'<&') _tdup && return; op='&>'; i=$((i+1));;
      *) op=$c;;
    esac;;
  esac
  rop=$fd$op
}
# _tdup: at >& or <&, read an fd word after optional blanks: digits, -, or a $name (bare or in ""). <& always duplicates;
# >& duplicates only when that word stands alone, otherwise it is >&word (return 1).
_tdup() {
  local j=$((i+2)) t="" dq=0
  while [[ "${s:j:1}" == [' '$'\t'] ]]; do j=$((j+1)); done
  [ "${s:j:2}" = '"$' ] && { dq=1; j=$((j+1)); }
  if [ "${s:j:1}" = '$' ]; then t='$'; j=$((j+1)); while [[ "${s:j:1}" == [A-Za-z0-9_{}] ]]; do t+=${s:j:1}; j=$((j+1)); done
    if [ "$dq" = 1 ]; then [ "${s:j:1}" = '"' ] || return 1; j=$((j+1)); fi
  else while [[ "${s:j:1}" == [0-9-] ]]; do t+=${s:j:1}; j=$((j+1)); done; fi
  if [ "${s:i:1}" = '>' ]; then
    case "$t" in ''|'$') return 1;; esac
    case "${s:j:1}" in ''|' '|$'\t'|$'\n'|';'|'|'|'&'|'<'|'>'|')') ;; *) return 1;; esac
  fi
  r+=(">&$GS&$t"); rop=""; i=$((j-1))
}
# _tb: skip each queued heredoc body through the line equal to its word (leading tabs dropped for <<-); a
# body with no such line runs to the end and sets S_AMB.
_tb() {
  local x op d rest ln
  for x in "${hds[@]}"; do op=${x%%"$GS"*}; d=${x#*"$GS"}
    while [ "$i" -lt "$n" ]; do rest=${s:i+1}; ln=${rest%%$'\n'*}; i=$((i+1+${#ln}))
      [ "$op" = '<<-' ] && ln=${ln#"${ln%%[!$'\t']*}"}
      [ "$ln" = "$d" ] && continue 2
    done
    S_AMB=1   # no exact terminator: the body ran to the end of the command
  done; hds=()
}
# _split <joined>: the caller's seg, split on US.
_split() { local x=$1; seg=(); while [[ "$x" == *"$US"* ]]; do seg+=("${x%%"$US"*}"); x=${x#*"$US"}; done; seg+=("$x"); }
_treset() { S_W=() S_P=() S_R=() S_H=() S_HEAD=(); }
# raw_targets <verbs> <command> [dir]: git_targets over <command> read again with TK_RAW=1: ' and " plain
# characters, # never a comment, no heredoc body skipped.
raw_targets() { local S_W S_P S_R S_H S_HEAD S_AMB=0 TK_RAW=1; _treset; tokenize "$2"; git_targets "$1" "${3:-$cwd}"; }
# new_targets <verbs> <command> [dir]: git_targets over the caller's tokenized <command>, plus raw_targets
# when that parse set S_AMB (not again inside a raw reading).
new_targets() {
  git_targets "$1" "${3:-$cwd}"; [ "$S_AMB" = 0 ] || [ -n "${TK_RAW:-}" ] || raw_targets "$1" "$2" "${3:-$cwd}"
}

# git_targets <verbs> [dir]: over the caller's segment list, "<verb> <dir>" for each `git [global opts] <verb>`
# with <verb> in the space-separated <verbs>, <dir> the directory it acts on. `cd <dir>` carries into later
# segments (relative to the one before, from the payload cwd); -C stacks on it; --git-dir names the repo,
# whose worktree is printed (--work-tree, else a linked worktree's, else the .git's parent). `bash|sh -c
# "<cmd>"` is read as a command too.
git_targets() {
  local verbs=$1 dir=${2:-$cwd} k seg=()
  for ((k=0; k<${#S_W[@]}; k++)); do _split "${S_W[k]}"; git_seg; done
}
# One segment of git_targets: reads and moves the caller's $dir, prints "<verb> <dir>" for git <verb>.
git_seg() {
  local j=0 a d gd="" wt="" v
  while [ $j -lt ${#seg[@]} ] && [[ "${seg[j]}" =~ $PFX ]]; do j=$((j+1)); done
  case "${seg[j]:-}" in
    cd) a=${seg[j+1]:-"~"}; [ "$a" = - ] || dir=$(absdir "$dir" "$a"); return;;
    bash|sh) [ "${seg[j+1]:-}" = -c ] || return
      local S_W S_P S_R S_H S_HEAD S_AMB=0; _treset; tokenize "${seg[j+2]:-}"; new_targets "$verbs" "${seg[j+2]:-}" "$dir"
      return;;
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
  v=${seg[j]:-}; [ -n "$v" ] && [[ " $verbs " == *" $v "* ]] || return 0
  gd=${gd%/}
  if [ -n "$wt" ]; then echo "$v $wt"
  elif [ -n "$gd" ] && [ -f "$gd/gitdir" ]; then echo "$v $(dirname "$(cat "$gd/gitdir")")"
  elif [ -n "$gd" ]; then echo "$v ${gd%/.git}"
  else echo "$v $d"; fi
}

# main_targets <verb> <command> [dir]: origin/main's reading (38a39ea git_targets/git_seg), kept verbatim but
# for the names and LC_ALL=C. Push and commit detection take the union of its targets and git_targets', so the
# new reading can only add to what main gates. It reads heredoc bodies and # as commands, as main did.
# It prints the directory each `git [global opts] <verb>` in the command acts on,
# one per line. Words split with shell quoting; ; & | ( ) and newlines end a segment. `cd <dir>` carries
# into later segments (relative to the one before, from the payload cwd); -C stacks on it; --git-dir names
# the repo, whose worktree is printed (--work-tree, else a linked worktree's, else the .git's parent).
# `bash|sh -c "<cmd>"` is read as a command too.
main_targets() {
  local LC_ALL=C; local verb=$1 s=$2 dir=${3:-$cwd} w=() tok="" has=0 q="" c i n=${#2} sep=$'\x1f'
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
  for x in "${w[@]}"; do if [ "$x" = "$sep" ]; then [ ${#seg[@]} -gt 0 ] && main_seg; seg=(); else seg+=("$x"); fi; done
}
# main_union <verbs> <command>: "<verb> <dir>" from main_targets for each verb. main_targets builds words
# from contiguous characters, dropping only ' " and \ (at every bash -c level too), so it is skipped for a
# verb the command does not hold once those are removed.
main_union() {
  local v; for v in $1; do [[ ${2//[\'\"\\]/} != *"$v"* ]] || main_targets "$v" "$2" | sed "s/^/$v /"; done
}
# gate_push <targets>: block on the first "push <dir>" line whose Orca repo has no fresh gate marker.
gate_push() {
  local t
  while IFS= read -r t; do
    [ -n "$(orca_root "$t")" ] || continue
    (cd "$t" && orca-lc gate-fresh) || block "git push blocked: gate marker missing or stale for $t. Run 'orca-lc gate' there and push only after it passes"
  done < <(sed -n 's/^push //p' <<<"$1")
}
# One segment of main_targets: reads and moves the caller's $dir, prints a target when it is git <verb>.
main_seg() {
  local j=0 a d gd="" wt=""
  while [ $j -lt ${#seg[@]} ] && [[ "${seg[j]}" =~ ^([A-Za-z_][A-Za-z0-9_]*=.*|env|command|exec|time|nohup)$ ]]; do j=$((j+1)); done
  case "${seg[j]:-}" in
    cd) a=${seg[j+1]:-"~"}; [ "$a" = - ] || dir=$(absdir "$dir" "$a"); return;;
    bash|sh) [ "${seg[j+1]:-}" = -c ] && main_targets "$verb" "${seg[j+2]:-}" "$dir"; return;;
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
  local k=$1 seg=() j=0 c vo="" fl=" " ops=() a x ch m e=0 p op t h in=0 rd=()
  _split "${S_W[k]}"
  while [ $j -lt ${#seg[@]} ] && [[ "${seg[j]}" =~ $PFX ]]; do j=$((j+1)); done
  c=${seg[j]:-}
  case "$c" in
    bash|sh) if [ "${seg[j+1]:-}" = -c ]; then local S_W S_P S_R S_H S_HEAD; _treset; tokenize "${seg[j+2]:-}"; tool_scan; fi; return;;
    find) for x in "${seg[@]}"; do case "$x" in -exec|-execdir|-ok|-okdir|-delete) return;; esac; done; echo "search find"; return;;
    head|tail) vo=$VO_head;; grep|egrep|fgrep) vo=$VO_grep;; rg) vo=$VO_rg;; ag) vo=$VO_ag;; sed) vo=$VO_sed;;
    cat|less|more|bat|tee|echo|printf) ;;
    *) return;;
  esac
  for ((j=j+1; j<${#seg[@]}; j++)); do a=${seg[j]}
    if [ "$a" = - ] && [ $e = 0 ]; then in=1   # - is stdin, not a file operand
    elif [ $e = 1 ] || [[ "$a" != -* ]]; then ops+=("$a")
    elif [ "$a" = -- ]; then e=1
    elif [[ "$a" == --* ]]; then fl+="${a%%=*} "; [[ "$a" != *=* && "$vo" == *" $a "* ]] && j=$((j+1))
    else for ((m=1; m<${#a}; m++)); do ch=-${a:m:1}; fl+="$ch "
        if [[ "$vo" == *" $ch "* ]]; then [ $m -eq $((${#a}-1)) ] && j=$((j+1)); break; fi
      done
    fi
  done
  # Stdin: piped in, a - operand, or a <, <<, <<- or <<< redirect on the segment.
  x=${S_R[k]}; while [ -n "$x" ]; do rd+=("${x%%"$RS"*}"); [[ "$x" == *"$RS"* ]] && x=${x#*"$RS"} || x=""; done
  [ "${S_P[k]}" = 1 ] && in=1
  for x in "${rd[@]}"; do case "${x%%"$GS"*}" in '<'|'<<'|'<<-'|'<<<') in=1;; esac; done
  case "$c" in cat|echo|printf)
    for x in "${rd[@]}"; do op=${x%%"$GS"*}; t=${x#*"$GS"}
      case "$t" in /dev/null|/dev/stdout|/dev/stderr|/dev/tty|'&'*) continue;; esac
      case "$op" in '>'|'>|'|'&>') echo "write $c"; return;; '>>'|'&>>') echo "edit $c"; return;; esac
    done;;
  esac
  case "$c" in
    cat|head|tail|less|more|bat) [ ${#ops[@]} -gt 0 ] || return
      # following a growing file is something Read cannot do
      [ "$c" = tail ] && [[ "$fl" =~ \ (-f|-F|--follow)\  ]] && return
      [ "$c" = less ] && [[ " ${ops[*]} " == *" +F "* ]] && return
      echo "read $c";;
    sed) p=1; [[ "$fl" =~ \ (-e|-f|--expression|--file)\  ]] && p=0
      if [[ "$fl" =~ \ (-i|--in-place)\  ]]; then [ ${#ops[@]} -gt $p ] && echo "edit sed"
      elif [[ "$fl" =~ \ (-n|--quiet|--silent)\  ]]; then [ ${#ops[@]} -gt $p ] && echo "read sed"; fi;;
    grep|egrep|fgrep|rg|ag) [ "$c" = rg ] && [[ "$fl" == *" --files "* ]] && { echo "glob rg"; return; }
      p=1; [[ "$fl" =~ \ (-e|-f|--regexp|--file)\  ]] && p=0
      if [ ${#ops[@]} -gt $p ]; then echo "search $c"
      elif [ "$in" != 1 ]; then
        case "$c" in rg|ag) echo "search $c";; *) [[ "$fl" =~ \ (-r|-R|--recursive|--dereference-recursive)\  ]] && echo "search $c";; esac
      fi;;
    tee) [ ${#ops[@]} -gt 0 ] || return; h=${S_HEAD[k]}
      if [ "${S_H[h]}" = 1 ] || [[ "$(_cw "$h")" =~ ^(cat|echo|printf)$ ]]; then
        if [[ "$fl" =~ \ (-a|--append)\  ]]; then echo "edit tee"; else echo "write tee"; fi
      fi;;
  esac
}

# push, commit and file edits are judged in the repo they act on, not the session's cwd: a push into an
# Orca repo is gated from wherever it is typed, and one into a repo without .orca/config.json is left alone
# even from an Orca cwd. An Edit/Write is judged by the repo and worktree holding the file: its testGlob,
# its test lock. Everything else stays active only where the cwd's repo carries the config.
root=$(orca_root .)
case "$tool" in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
    # push and commit take the union with origin/main's reading, so nothing is gated less than on main.
    # main's push reading and the merge check run and block first, as on main, so what main blocks is blocked
    # as soon as on main; then one parse for every other consumer
    tm=$(main_union push "$cmd"); gate_push "$tm"
    [ -n "$root" ] && grep -qE '(^|[;&|]\s*)git\s+merge([^-[:alnum:]_]|$)' <<<"$cmd" && block "git merge blocked: PRs merge on GitHub (gh pr merge). A local merge closes the PR without review"
    _treset; S_AMB=0; tokenize "$cmd"
    tg=$({ new_targets "push commit" "$cmd"; main_union commit "$cmd"; } | awk '!x[$0]++')
    gate_push "$(grep -vxF -f <(printf '%s\n' "$tm") <<<"$tg")"
    t=$(sed -n 's/^commit //p' <<<"$tg" | head -1)
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
    [ "$(jq '.toolAdvice == false' "$root/.orca/config.json")" = true ] && exit 0   # only a JSON false, not "false"
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
    f=$(jq -r '.tool_input.file_path // ""' <<<"$in")
    # ~ and ~/ expand to $HOME, as Claude Code does, for the test lock and the leak scan alike. With HOME unset or
    # empty ~ stays as written: set -u would abort the hook, and exit 1 lets the edit through unchecked.
    if [ -n "${HOME:-}" ]; then case "$f" in "~") f=$HOME;; "~/"*) f=$HOME/${f#"~/"};; esac; fi
    # The test-edit lock ends with return, never exit: the leak scan below must run for every edit.
    test_lock() { local win p t n anc m froot glob
      [ -n "$f" ] || return 0
      # Absolute when it starts with /, or on Windows (Git Bash, MSYS, Cygwin) with a drive (C:\ or C:/) or \\
      # (UNC); anything else is relative to the payload cwd.
      # On Windows \ reads as /; elsewhere it is an ordinary filename character and stays in its segment.
      # Then . and .. collapse as text, as Claude Code does before it follows any link.
      win=""; case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) win=1;; esac
      case "$f" in
        /*) p=$f;;
        [A-Za-z]:[\\/]*|'\\'*) if [ -n "$win" ]; then p=$f; else p=$cwd/$f; fi;;
        *) p=$cwd/$f;;
      esac
      [ -n "$win" ] && p=${p//\\//}
      p=$(textpath "$p")
      # testGlob always matches the physical path m. A symlinked file is judged as its target: readlink -f
      # gives it already physical, for that repo, that lock, that path. Otherwise each existing dir goes
      # through cd -P, so a symlinked dir shows as its target, and the missing tail stays as written; p if a
      # dir can't be entered.
      if [ -L "$p" ] && t=$(readlink -f "$p" 2>/dev/null) && [ -n "$t" ]; then m=$t
      elif abspath "$p" "$win"; then m=$ap; else m=$p; fi
      # Nearest existing ancestor of the file's directory, for its repo and lock: a new file in a new dir
      # resolves through the first one that exists. Ends at a fixpoint (/, a missing drive root): no repo.
      anc=${m%/*}
      while :; do
        case "$anc" in ""|[A-Za-z]:) anc=$anc/;; esac
        [ -d "$anc" ] && break
        n=${anc%/*}; case "$n" in ""|[A-Za-z]:) n=$n/;; esac
        [ "$n" != "$anc" ] || return 0
        anc=$n
      done
      froot=$(orca_root "$anc")
      [ -n "$froot" ] || return 0
      glob=$(jq -r '.testGlob // empty' "$froot/.orca/config.json")
      if [ -n "$glob" ] && grep -qE "$glob" <<<"$m" && [ ! -f "$(git -C "$anc" rev-parse --absolute-git-dir)/orca-allow-test-edits" ]; then
        block "test file edit blocked. Fixing code must not weaken its checks. If the test itself is wrong or a scenario is missing, run 'orca-lc test-lock on' in the worktree that holds the file and say why in the commit body"
      fi
    }
    test_lock
    # Handoffs and discoveries are read by every session: scan what is about to land there. Labels never carry the
    # file name, so no output line can echo a denylisted one. Exit 1 blocks with the hits; any exit but 0 and 1 (an
    # unreadable denylist, an orca-lc without leak-check) blocks too, since the write was not checked.
    if [ -n "$root" ] && [ "$(jq -r '.leakCheck // empty' "$root/.orca/config.json")" = true ]; then
      sh=$(orca-lc config sharedDir 2>/dev/null); sh=${sh:-$root/.orca}
      dd=$(orca-lc config discoveriesDir 2>/dev/null); dd=${dd:-discoveries}
      case "$f" in */*) dir=${f%/*}; dir=${dir:-/};; *) dir=.;; esac # not dirname: $(...) strips a trailing newline
      abspath "$dir" && dir=$ap || dir=""; kind=""
      for k in "handoff:$sh/handoffs" "discovery:$sh/$dd"; do
        abspath "${k#*:}" || continue; base=$ap
        [ -n "$dir" ] && [ -n "$base" ] && [[ "$dir/" == "$base/"* ]] && { kind=${k%%:*}; break; }
      done
      if [ -n "$kind" ]; then
        hits=""
        scan() { local o s r=""; o=$(orca-lc leak-check --stdin "$1" 2>&1); s=$?
          case $s in
            0) ;;
            1) hits+=$(grep -v '^leak-check:' <<<"$o")$'\n';;
            # Only the fixed unreadable-list line is echoed; any other output may carry a path.
            *) r=$(grep -m1 -oE '^orca-lc: leak-check: (global|project) denylist unreadable$' <<<"$o") && r=" (${r#orca-lc: })"
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
