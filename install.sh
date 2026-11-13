#!/usr/bin/env bash
# Install, update or uninstall Orca for this user. Links orca-lc into ~/.local/bin and the hooks, skills and agents into
# the Claude config dir ($CLAUDE_CONFIG_DIR, else ~/.claude), or copies them where symlinks are unavailable, registers
# the hooks in its settings.json, and records what it created in ${XDG_STATE_HOME:-~/.local/state}/orca/install.manifest,
# so a rerun changes nothing and --uninstall removes exactly that. A target is replaced only when Orca installed it
# (missing, a dangling link, a link into an Orca checkout, or a copy of something Orca shipped); anything else is kept
# and reported, even with --force. --force only moves an install from another Orca checkout to this one.
#
# External commands: awk basename cat chmod cmp cp cut dirname find git jq ln mkdir mktemp mv readlink rm rmdir sort tr
# uname, sha256sum (else shasum, macOS), cygpath when present (Git Bash), the required tools claude gh herdr (presence,
# and `claude plugin list`), and an accepted recommended tool's own launcher (npm brew go pipx uv claude).
# Test-only: ORCA_INSTALL_PROMPT_STDIN=1 reads prompt answers from stdin even when it is not a terminal, so tests can
# drive the prompts. It is not a user setting.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: ./install.sh [--yes | --no-optional] [--grilling-fallback] [--force]
       ./install.sh --uninstall
       ./install.sh --help

Installs Orca from this checkout, or updates it after a git pull. A rerun changes nothing.
  --yes                install every missing recommended tool that has a command for this platform, without asking
  --no-optional        skip the recommended tools; only list the ones present
  --grilling-fallback  also offer the mattpocock-skills plugin, a fallback for Orca's grilling skill
  --force              move an install made from another Orca checkout to this one
  --uninstall          remove what install created and keep everything else; exit 1 when something is left
  --help               show this text
EOF
}
usage_error() { echo "install.sh: $1" >&2; usage >&2; exit 2; }
yes=0 noopt=0 gfb=0 uninst=0 force=0 nflags=0
for a in "$@"; do
  case $a in
    --yes) yes=1;; --no-optional) noopt=1;; --grilling-fallback) gfb=1;; --uninstall) uninst=1;; --force) force=1;;
    --help|-h) usage; exit 0;;
    *) usage_error "unknown flag: $a";;
  esac
  nflags=$((nflags + 1))
done
if [ $yes = 1 ] && [ $noopt = 1 ]; then usage_error "--yes and --no-optional exclude each other"; fi
if [ $gfb = 1 ] && [ $noopt = 1 ]; then usage_error "--grilling-fallback and --no-optional exclude each other"; fi
if [ $uninst = 1 ] && [ $nflags -gt 1 ]; then usage_error "--uninstall takes no other flag"; fi

TAB=$'\t'
here=$(cd "$(dirname "$0")" && pwd)
here_p=$(cd "$here" && pwd -P)
cur=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
if command -v cygpath >/dev/null; then cur=$(cygpath -u "$cur"); fi
state=${XDG_STATE_HOME:-$HOME/.local/state}/orca
M=$state/install.manifest
ORIG=$state/settings.json.orig

# The manifest: one tab-separated record per line (kind, fields). rec <kind> [<first field>] prints the first match;
# recf <kind> <n> [<first field>] prints its field n (the kind is field 0).
MREC=()
if [ -f "$M" ]; then while IFS= read -r l || [ -n "$l" ]; do [ -n "$l" ] && MREC+=("$l"); done < "$M"; fi
rec() { local l
  for l in ${MREC[@]+"${MREC[@]}"}; do
    case "$l$TAB" in "$1$TAB"*) ;; *) continue;; esac
    if [ $# -ge 2 ]; then case "$l$TAB" in "$1$TAB$2$TAB"*) ;; *) continue;; esac; fi
    printf '%s\n' "$l"; return 0
  done; return 1; }
recf() { local l a; l=$(rec "$1" ${3+"$3"}) || return 1; IFS=$TAB read -r -a a <<< "$l"; printf '%s\n' "${a[$2]:-}"; }
m_checkout=$(recf checkout 1 || true)
m_config=$(recf config 1 || true)

# norm <dir>: the form two spellings of a config dir are compared in; never stored or printed.
norm() { local p=$1
  while [ ${#p} -gt 1 ] && [ "${p%/}" != "$p" ]; do p=${p%/}; done
  if [ -d "$p" ]; then (cd "$p" && pwd -P); else printf '%s\n' "$p"; fi; }

# <cfg>, the spelling this run works with: the recorded one whenever a config record exists (install stops below when
# the current spelling names another dir), else the current one. Only the first line prints the current spelling.
if [ -n "$m_config" ]; then cfg=$m_config; else cfg=$cur; fi
if [ $uninst = 1 ]; then echo "config dir: $cfg"; else echo "config dir: $cur"; fi

problems=()
stop_if_problems() {
  [ ${#problems[@]} -gt 0 ] || return 0
  printf 'install.sh: %s\n' "${problems[@]}" >&2; echo "install.sh: nothing changed" >&2; exit 1; }

# Required tools. #27 may move herdr to the recommended table; this list is the one place it is named.
REQUIRED="claude git jq gh herdr"
tool_url() {
  case $1 in
    claude) echo https://docs.claude.com/en/docs/claude-code/setup;; git) echo https://git-scm.com/downloads;;
    jq) echo https://jqlang.org/download/;; gh) echo https://cli.github.com;; herdr) echo https://herdr.dev/tui;;
  esac; }
need=$REQUIRED; [ $uninst = 0 ] || need="git jq"
for t in $need; do command -v "$t" >/dev/null || problems+=("missing required tool: $t ($(tool_url "$t"))"); done
stop_if_problems

if command -v sha256sum >/dev/null; then hcmd=(sha256sum); else hcmd=(shasum -a 256); fi
hstream() { local o; o=$("${hcmd[@]}"); printf '%s\n' "${o%% *}"; }
# hpath <path>: a file's hash, or for a directory the hash of its sorted file list with each file's hash. Modes are left
# out: Git Bash reports them unreliably, and ownership is about content.
hpath() {
  if [ -d "$1" ] && [ ! -L "$1" ]; then
    (cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s  %s\n' "$(hstream < "$f")" "$f"; done) | hstream
  else hstream < "$1"; fi; }

probe=$(mktemp -d); : > "$probe/f"; ln -s "$probe/f" "$probe/l" 2>/dev/null || true
if [ -L "$probe/l" ]; then mode="link"; else mode="copy"; fi
rm -rf "$probe"

# shipped <copy> <source>: the copy is byte-equal to the source, or to a version of that same repo-relative path this
# repository has committed. Copies are what ln -s makes in Git Bash on Windows without Developer Mode.
shipped() { cmp -s "$1" "$2" && return 0; local h; h=$(git -C "$here" hash-object --no-filters "$1" 2>/dev/null) || return 1
  git -C "$here" log --all --format= --raw --no-abbrev -- "${2#"$here"/}" 2>/dev/null | awk -v h="$h" '$4 == h { f = 1 } END { exit !f }'; }
# copied <source> <target>: the target is a copy of Orca's: a regular file that is shipped, or a directory whose every
# entry, checked recursively, is.
copied() { local f
  if [ -L "$2" ]; then return 1; fi
  if [ -f "$2" ]; then shipped "$2" "$1"; return; fi
  [ -d "$2" ] || return 1
  for f in "$2"/* "$2"/.[!.]* "$2"/..?*; do [ -e "$f" ] || [ -L "$f" ] || continue
    copied "$1/${f#"$2"/}" "$f" || return 1; done; }
# link_root <link> <rel>: the Orca checkout (a directory holding bin/orca-lc) the link points into at <rel>, if any.
link_root() { local l root; l=$(readlink "$1"); root=${l%/"$2"}
  [ "$root" != "$l" ] && [ -f "$root/bin/orca-lc" ] && printf '%s\n' "$root"; }

# in_here <path>: the path, its parents resolved, lies inside this checkout (a config subdir linked into it), so it is the
# checkout's own file and never Orca's to remove.
in_here() { local p; p=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || return 1
  case $p/ in "$here_p"/*) return 0;; esac; return 1; }
# pairs_for <cfg>: P holds source, target, source, target, ...
pairs_for() { local s
  P=("$here/bin/orca-lc" "$HOME/.local/bin/orca-lc" "$here/hooks" "$1/hooks/orca")
  for s in "$here"/skills/*/; do [ -d "$s" ] && P+=("${s%/}" "$1/skills/$(basename "$s")"); done
  for s in "$here"/agents/*.md; do [ -f "$s" ] && P+=("$s" "$1/agents/$(basename "$s")"); done; }

# classify <source> <target>: sets cls to absent, current, stale, other, kept or edited (design.md, Classifying a
# target), and croot to the checkout an "other" target belongs to.
classify() { local s=$1 t=$2 rel=${1#"$here"/} h rh=
  croot=
  if [ ! -e "$t" ]; then cls=absent; return; fi
  if [ -L "$t" ]; then
    if croot=$(link_root "$t" "$rel"); then
      if [ "$croot" = "$here" ]; then cls=current; else cls=other; fi
    else cls=kept; croot=; fi
  elif in_here "$t"; then cls=kept
  else
    h=$(hpath "$t"); rh=$(recf copy 3 "$t" || true)
    if [ $mode = copy ] && [ "$h" = "$(hpath "$s")" ]; then cls=current
    elif [ -n "$rh" ] && [ "$h" = "$rh" ]; then cls=stale
    elif copied "$s" "$t"; then cls=stale
    elif [ -n "$rh" ] || rec edited "$t" >/dev/null; then cls=edited
    else cls=kept; fi
  fi
  if { [ $cls = current ] || [ $cls = stale ]; } && [ -n "$m_checkout" ] && [ "$m_checkout" != "$here" ]; then
    cls=other; croot=${croot:-$m_checkout}
  fi
  return 0; }

# settings.json. orca(s) is #86's matcher and the one definition of Orca's hook: the merge, the pristine check and
# uninstall all call it.
JQ_ORCA='def orca(s): (.command? // "") | type == "string" and test("hooks[/\\\\]orca[/\\\\]" + s + "\\.sh([^A-Za-z0-9_.-]|$)");'
# ensure: a hook is Orca's when its command names hooks/orca/<script>.sh (either separator), followed by the end or a
# character that cannot continue a file name, so a stop.sh.bak is not Orca's. The first one in the event gets Orca's
# command and keeps its other fields; later ones go, and so does a group they leave empty. None: append one.
JQ_ENSURE='
  def ensure(ev; m; s): ("bash \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/orca/" + s + ".sh\"") as $cmd
    | .hooks[ev] = ((.hooks[ev] // []) | reduce .[] as $g ({seen: false, out: []};
        if ($g | type) != "object" or ($g.hooks | type) != "array" or ($g.hooks | length) == 0 then .out += [$g]
        else (reduce $g.hooks[] as $h ({seen: .seen, hs: []};
                if ($h | orca(s)) then (if .seen then . else .seen = true | .hs += [$h | .command = $cmd] end)
                else .hs += [$h] end)) as $r
          | .seen = $r.seen | if ($r.hs | length) == 0 then . else .out += [$g | .hooks = $r.hs] end end)
      | if .seen then .out else .out + [{matcher: m, hooks: [{type: "command", command: $cmd, timeout: 15}]}] end);
  ensure("PreToolUse"; "Bash|Edit|Write|MultiEdit"; "pretool")
  | ensure("SessionStart"; "startup|resume|clear|compact"; "session-start")
  | ensure("PostToolUse"; "Read"; "post-read")
  | ensure("Stop"; "*"; "stop")'
# scan: whether .hooks exists, then per event and script whether a hook of Orca's is there and whether the event array is.
JQ_SCAN='
  def scan(ev; s): [ev, s,
      ([(.hooks[ev] // [])[]? | objects | .hooks? | arrays | .[] | select(orca(s))] | if length > 0 then 1 else 0 end),
      (if (.hooks[ev] | type) == "null" then 0 else 1 end)] | map(tostring) | join("\t");
  (if (.hooks | type) == "null" then "key\t0" else "key\t1" end),
  scan("PreToolUse"; "pretool"), scan("SessionStart"; "session-start"), scan("PostToolUse"; "post-read"), scan("Stop"; "stop")'
# strip: remove every hook of Orca's and the groups that leaves empty; drop an emptied event array only when Orca created
# it ($newev), and .hooks only when Orca created it ($hk).
JQ_STRIP='
  def strip(ev; s): if (.hooks[ev] | type) == "array" then .hooks[ev] |= map(
        if type == "object" and (.hooks | type) == "array" and (.hooks | length) > 0
        then (.hooks |= map(select(orca(s) | not))) | select(.hooks | length > 0) else . end) else . end;
  (if (.hooks | type) == "object" then strip("PreToolUse"; "pretool") | strip("SessionStart"; "session-start")
     | strip("PostToolUse"; "post-read") | strip("Stop"; "stop") else . end)
  | reduce $newev[] as $e (.; if (.hooks | type) == "object" and (.hooks[$e] | type) == "array" and (.hooks[$e] | length) == 0
      then del(.hooks[$e]) else . end)
  | if $hk and (.hooks | type) == "object" and (.hooks | length) == 0 then del(.hooks) else . end'

# resolve <link>: the file a settings.json link points to, through every hop; readlink -f where it works, else a
# readlink loop (older macOS).
resolve() { local p=$1 l r n=0
  if r=$(readlink -f "$p" 2>/dev/null) && [ -n "$r" ]; then printf '%s\n' "$r"; return; fi
  while [ -L "$p" ] && [ $n -lt 40 ]; do
    l=$(readlink "$p"); case $l in /*) p=$l;; *) p=$(dirname "$p")/$l;; esac; n=$((n + 1)); done
  printf '%s\n' "$p"; }
# swrite <file>: write its content to $R atomically, keeping $R's mode (a new file gets 0666 under the umask). A
# read-only $R is replaced like any other: the temp file is made writable for the write only. A failed write removes it.
swrite() { local tmp m ro=0
  tmp=$(mktemp "$R.XXXXXX")
  if { if [ -e "$R" ]; then cp -p "$R" "$tmp"; else m=$(umask); chmod "$(printf '%o' $(( 0666 & ~(8#$m) )))" "$tmp"; fi; } \
     && { [ -w "$tmp" ] || { ro=1; chmod u+w "$tmp"; }; } && cat "$1" > "$tmp" && { [ $ro = 0 ] || chmod u-w "$tmp"; } \
     && mv "$tmp" "$R"; then return 0; fi
  rm -f "$tmp"; return 1; }
# jq's text output is read with \r stripped: a native jq.exe under Git Bash ends its lines with CRLF.
# settings_in: R (the file to write), sexists, SDOCS (its JSON document count; empty when it does not parse) and SIN
# (the content to read). An absent file and one with 0 documents are read as {} (design.md, settings.json).
settings_in() {
  R=$S; if [ -L "$S" ]; then R=$(resolve "$S"); fi
  SIN=$R SDOCS=1
  if [ -e "$R" ]; then sexists=1; SDOCS=$(jq -s length "$R" 2>/dev/null | tr -d '\r' || true); else sexists=0; fi
  if [ $sexists = 0 ] || [ "$SDOCS" = 0 ]; then SIN=$work/empty.json; echo '{}' > "$SIN"; fi; }
# settings_check: the preflight's steps (design.md, settings.json): it parses, holds one document (or none), and
# Orca's filters accept its shape. $1 is the filter run on it; its output goes to $2.
settings_check() {
  if ! jq empty "$R" 2>"$work/jq.err"; then problems+=("$S is not valid JSON: $(cat "$work/jq.err")")
  elif [ "${SDOCS:-1}" -gt 1 ]; then problems+=("$S holds $SDOCS JSON documents; Claude reads one")
  elif ! jq "$JQ_ORCA $1" "$SIN" > "$2" 2>"$work/jq.err" \
       || ! jq -r "$JQ_ORCA $JQ_SCAN" "$SIN" > "$work/scan" 2>>"$work/jq.err"; then
    problems+=("$S is valid JSON but not a Claude settings object: $(cat "$work/jq.err")")
  fi; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# Directories Orca creates are recorded, so uninstall can remove them when empty. mkparents <dir> [private] creates
# <dir> and its missing parents (under umask 077 when private).
NEWDIRS=()
mkparents() { local d=$1 miss=() i
  while [ ! -d "$d" ]; do miss=("$d" ${miss[@]+"${miss[@]}"}); d=$(dirname "$d"); done
  [ ${#miss[@]} -gt 0 ] || return 0
  if [ "${2:-}" = private ]; then (umask 077; mkdir -p "$1"); else mkdir -p "$1"; fi
  for i in "${miss[@]}"; do NEWDIRS+=("$i"); done; }
in_list() { local x=$1 y; shift; for y in "$@"; do [ "$x" = "$y" ] && return 0; done; return 1; }

# ---------------------------------------------------------------------------------------------------------------------
if [ $uninst = 1 ]; then
  LEFT=()
  left() { LEFT+=("$1"); echo "left: $1 ($2)"; }
  # settings.json is parsed before anything is removed, as install's preflight does (design.md, Uninstall).
  S=$cfg/settings.json
  if [ -e "$S" ]; then
    settings_in; settings_check "$JQ_SCAN" /dev/null
    stop_if_problems
  fi
  if [ ${#MREC[@]} -gt 0 ]; then
    for l in "${MREC[@]}"; do
      IFS=$TAB read -r -a f <<< "$l"
      case ${f[0]} in link|copy|edited) ;; *) continue;; esac
      t=${f[1]} s=${f[2]}; rel=${s#"$m_checkout"/}
      if [ ! -e "$t" ] && [ ! -L "$t" ]; then continue; fi
      case ${f[0]} in
        link) if [ -L "$t" ] && link_root "$t" "$rel" >/dev/null; then rm "$t"; echo "removed $t"
              else left "$t" "not created by Orca"; fi;;
        copy|edited)
          if [ -L "$t" ] || in_here "$t"; then left "$t" "not created by Orca"
          elif { [ "${f[0]}" = copy ] && [ "$(hpath "$t")" = "${f[3]:-}" ]; } || copied "$here/$rel" "$t"; then
            rm -rf "$t"; echo "removed $t"
          else left "$t" "edited since install"; fi;;
      esac
    done
  else
    pairs_for "$cfg"
    for ((i = 0; i < ${#P[@]}; i += 2)); do
      t=${P[i+1]}; classify "${P[i]}" "$t"
      case $cls in current|stale) if [ -L "$t" ]; then rm "$t"; else rm -rf "$t"; fi; echo "removed $t";; esac
    done
  fi

  # s_jq: a settings.json the dir rule below does not count as foreign (Orca's part of it is gone, or it is a dangling
  # link that holds none of Orca's hooks).
  s_jq=
  if [ -L "$S" ] && [ ! -e "$S" ]; then s_jq=$S; echo "install.sh: $S is a dangling symlink; left it as it is" >&2
  elif [ -e "$S" ]; then
    settings_in
    r_post=$(recf settings-post 1 || true) r_orig=$(recf settings-orig 1 || true) r_created=$(recf settings-created 1 || true)
    # Untouched since Orca last wrote it: restore the saved bytes, or delete the file Orca created. A settings.json that
    # is now a symlink is never deleted, nor its target: it takes the jq path below.
    untouched=0
    if [ -n "$r_post" ] && [ "$(hstream < "$R")" = "$r_post" ] \
       && { [ -n "$r_created" ] || { [ -n "$r_orig" ] && [ -f "$r_orig" ]; }; }; then untouched=1; fi
    if [ $untouched = 1 ] && ! { [ -L "$S" ] && [ -n "$r_created" ]; }; then
      if [ -n "$r_created" ]; then rm "$S"; echo "removed $S"
      else swrite "$r_orig"; echo "restored $S"; fi
    else
      s_jq=$S
      newev=$(for l in ${MREC[@]+"${MREC[@]}"}; do IFS=$TAB read -r -a f <<< "$l"
        if [ "${f[0]}" = hook ] && [ "${f[3]:-0}" = 1 ]; then printf '%s\n' "${f[1]}"; fi; done | jq -R . | jq -s -c .)
      if rec hooks-key >/dev/null; then hk=true; else hk=false; fi
      jq --argjson newev "$newev" --argjson hk "$hk" "$JQ_ORCA $JQ_STRIP" "$SIN" > "$work/strip.json"
      if [ "$(jq -S . "$SIN")" != "$(jq -S . "$work/strip.json")" ]; then
        swrite "$work/strip.json"
        if [ $untouched = 1 ]; then echo "settings.json is a symlink; removed Orca's hooks only, kept the link and its target"
        else echo "settings.json was edited after install; removed Orca's hooks only (formatting may differ)"; fi
      fi
    fi
  fi

  rm -f "$M" "$ORIG"; rmdir "$state" 2>/dev/null || true
  # A recorded dir is listed only when it directly holds something no left: line or kept recorded dir names. The s_jq
  # settings.json is not left, so it does not list its dir either.
  KEPTD=()
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] && [ ! -L "$d" ] || continue
    rmdir "$d" 2>/dev/null && continue
    foreign=0
    for e in "$d"/* "$d"/.[!.]* "$d"/..?*; do [ -e "$e" ] || [ -L "$e" ] || continue
      [ "$e" = "$s_jq" ] || in_list "$e" ${LEFT[@]+"${LEFT[@]}"} || in_list "$e" ${KEPTD[@]+"${KEPTD[@]}"} || { foreign=1; break; }; done
    KEPTD+=("$d")
    [ $foreign = 0 ] || left "$d" "not empty: holds files Orca did not create"
  done < <(for l in ${MREC[@]+"${MREC[@]}"}; do case $l in "dir$TAB"*) printf '%s\n' "${l#dir"$TAB"}";; esac; done \
             | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-)
  [ ${#LEFT[@]} = 0 ] || exit 1
  exit 0
fi

# --- install: preflight (read-only) ----------------------------------------------------------------------------------
# legacy_in <dir>: <dir> holds an Orca install (a target the classifier calls Orca's, or a hook of Orca's).
legacy_in() { local i
  pairs_for "$1"
  for ((i = 2; i < ${#P[@]}; i += 2)); do
    classify "${P[i]}" "${P[i+1]}"; case $cls in current|stale|other) return 0;; esac; done
  [ -f "$1/settings.json" ] && jq -e "$JQ_ORCA [.. | objects | select(has(\"command\")) | select(orca(\"pretool\") or orca(\"session-start\") or orca(\"post-read\") or orca(\"stop\"))] | length > 0" "$1/settings.json" >/dev/null 2>&1; }
if [ -n "$m_config" ]; then
  if [ "$(norm "$m_config")" != "$(norm "$cur")" ]; then
    problems+=("installed into $m_config, not $cur; run ./install.sh --uninstall with CLAUDE_CONFIG_DIR=$m_config first")
  fi
elif [ ${#MREC[@]} = 0 ] && [ "$(norm "$cur")" != "$(norm "$HOME/.claude")" ] && legacy_in "$HOME/.claude"; then
  problems+=("$HOME/.claude holds an Orca install with no manifest; run ./install.sh --uninstall with CLAUDE_CONFIG_DIR unset first")
fi
stop_if_problems

pairs_for "$cfg"
CLS=() ROOTS=()
for ((i = 0; i < ${#P[@]}; i += 2)); do classify "${P[i]}" "${P[i+1]}"; CLS+=("$cls"); ROOTS+=("$croot"); done
if [ $force = 0 ]; then
  for ((i = 0; i < ${#CLS[@]}; i++)); do
    [ "${CLS[i]}" = other ] && problems+=("${P[2*i+1]} belongs to the Orca checkout at ${ROOTS[i]}, not this one")
  done
  [ ${#problems[@]} = 0 ] || problems+=("run ./install.sh --force to switch the install to $here")
fi
# A parent that exists but is not a directory (a dangling link, a file) would stop mkdir midway through the apply.
BADP=() PT=("$state/x" "$cfg/settings.json")
for ((i = 1; i < ${#P[@]}; i += 2)); do PT+=("${P[i]}"); done
for p in "${PT[@]}"; do
  q=$(dirname "$p")
  while [ ! -d "$q" ]; do
    if [ -e "$q" ] || [ -L "$q" ]; then
      in_list "$q" ${BADP[@]+"${BADP[@]}"} || { BADP+=("$q"); problems+=("$q exists and is not a directory"); }; break
    fi
    q=$(dirname "$q")
  done
done
# Records of targets no longer shipped (a skill removed upstream): removed when still Orca's, else kept.
# A record that names a target in another spelling (HOME with a trailing slash, say) is that target, not an orphan.
npath() { printf '%s/%s\n' "$(norm "$(dirname "$1")")" "$(basename "$1")"; }
ORPH=() PN=()
for l in ${MREC[@]+"${MREC[@]}"}; do
  IFS=$TAB read -r -a f <<< "$l"
  case ${f[0]} in link|copy|edited) ;; *) continue;; esac
  in_list "${f[1]}" "${P[@]}" && continue
  if [ ${#PN[@]} = 0 ]; then for ((i = 1; i < ${#P[@]}; i += 2)); do PN+=("$(npath "${P[i]}")"); done; fi
  in_list "$(npath "${f[1]}")" "${PN[@]}" || ORPH+=("$l")
done

S=$cfg/settings.json
if [ -L "$S" ] && [ ! -e "$S" ]; then problems+=("$S: settings.json is a dangling symlink"); fi
stop_if_problems
settings_in
if [ $sexists = 1 ]; then settings_check "$JQ_ENSURE" "$work/merged.json"
else jq "$JQ_ORCA $JQ_ENSURE" "$SIN" > "$work/merged.json"; jq -r "$JQ_ORCA $JQ_SCAN" "$SIN" > "$work/scan"; fi
stop_if_problems

# --- install: apply --------------------------------------------------------------------------------------------------
chmod +x "$here"/bin/orca-lc "$here"/hooks/*.sh
[ $mode = link ] || echo "copy mode: symlinks unavailable; re-run ./install.sh after every pull"
NT=() KEPT=() grilling_kept=0
place() { mkparents "$(dirname "$2")"
  if [ $mode = link ]; then ln -s "$1" "$2"; NT+=("link$TAB$2$TAB$1"); echo "linked $2"
  else cp -R "$1" "$2"; NT+=("copy$TAB$2$TAB$1$TAB$(hpath "$2")"); echo "copied $2"; fi; }
drop() { if [ -L "$1" ]; then rm "$1"; else rm -rf "$1"; fi; }
for ((i = 0; i < ${#CLS[@]}; i++)); do
  s=${P[2*i]} t=${P[2*i+1]}
  case ${CLS[i]} in
    absent) if [ -L "$t" ]; then rm "$t"; fi; place "$s" "$t";;
    current) if [ -L "$t" ]; then NT+=("link$TAB$t$TAB$s"); else NT+=("copy$TAB$t$TAB$s$TAB$(hpath "$t")"); fi;;
    stale|other) drop "$t"; place "$s" "$t";;
    kept) KEPT+=("kept $t, which Orca did not install; Orca's is not linked there (move it aside and rerun to use Orca's)");;
    edited) KEPT+=("kept $t, edited since install; Orca's is not copied there (move it aside and rerun to use Orca's)")
            NT+=("edited$TAB$t$TAB$s");;
  esac
  case ${CLS[i]} in kept|edited) [ "$t" = "$cfg/skills/grilling" ] && grilling_kept=1;; esac
done
for l in ${ORPH[@]+"${ORPH[@]}"}; do
  IFS=$TAB read -r -a f <<< "$l"; t=${f[1]}; rel=${f[2]#"${m_checkout:-$here}"/}
  if [ ! -e "$t" ] && [ ! -L "$t" ]; then continue; fi
  if { [ -L "$t" ] && link_root "$t" "$rel" >/dev/null; } \
     || { [ ! -L "$t" ] && ! in_here "$t" && { [ "$(hpath "$t")" = "${f[3]:-}" ] || copied "$here/$rel" "$t"; }; }; then
    drop "$t"; echo "removed $t, no longer shipped"
  else KEPT+=("kept $t, which Orca no longer ships and did not install as it is now"); fi
done
for k in ${KEPT[@]+"${KEPT[@]}"}; do echo "install.sh: $k" >&2; done

# settings.json (design.md, settings.json).
r_created=$(recf settings-created 1 || true) r_orig=$(recf settings-orig 1 || true) r_post=$(recf settings-post 1 || true)
HOOKS=()
for l in ${MREC[@]+"${MREC[@]}"}; do case $l in "hook$TAB"*) HOOKS+=("$l");; esac; done
if rec hooks-key >/dev/null; then r_hk=1; else r_hk=0; fi
had_orca=0 had_key=1
while IFS=$TAB read -r ev sc matched existed; do
  if [ "$ev" = key ]; then had_key=$sc; continue; fi
  [ "$matched" = 0 ] || { had_orca=1; continue; }
  rec hook "$ev" >/dev/null || HOOKS+=("hook$TAB$ev$TAB$sc$TAB$((1 - existed))")
done < <(tr -d '\r' < "$work/scan")
if [ $sexists = 1 ] && [ "$(jq -S . "$SIN")" = "$(jq -S . "$work/merged.json")" ]; then :
else
  if [ -n "$r_post" ] && { [ $sexists = 0 ] || [ "$(hstream < "$R")" != "$r_post" ]; }; then
    r_orig="" r_created=""; rm -f "$ORIG"
    echo "settings.json was edited since the last install; uninstall will remove Orca's hooks only"
  fi
  if [ $sexists = 0 ]; then r_created=$S
  elif [ -z "$r_post" ] && [ $had_orca = 0 ]; then
    mkparents "$state" private; rm -f "$ORIG"; (umask 077; cp "$R" "$ORIG"); r_orig=$ORIG
  fi
  [ "$had_key" = 1 ] || r_hk=1
  mkparents "$(dirname "$R")"
  swrite "$work/merged.json"
  r_post=$(hstream < "$R")
fi
echo "hooks registered in $S"

# The manifest, rewritten only when its content changes.
mkparents "$state" private
NREC=("checkout$TAB$here" "config$TAB$cfg" "mode$TAB$mode" ${NT[@]+"${NT[@]}"})
OLDD=()
for l in ${MREC[@]+"${MREC[@]}"}; do case $l in "dir$TAB"*) OLDD+=("${l#dir"$TAB"}"); NREC+=("$l");; esac; done
for d in ${NEWDIRS[@]+"${NEWDIRS[@]}"}; do in_list "$d" ${OLDD[@]+"${OLDD[@]}"} || { OLDD+=("$d"); NREC+=("dir$TAB$d"); }; done
[ -z "$r_created" ] || NREC+=("settings-created$TAB$r_created")
[ -z "$r_orig" ] || NREC+=("settings-orig$TAB$r_orig")
[ -z "$r_post" ] || NREC+=("settings-post$TAB$r_post")
NREC+=(${HOOKS[@]+"${HOOKS[@]}"})
[ $r_hk = 0 ] || NREC+=("hooks-key")
new=$(printf '%s\n' "${NREC[@]}"); old=
[ -f "$M" ] && old=$(cat "$M")
if [ "$new" != "$old" ]; then (umask 077; t=$(mktemp "$state/.install.manifest.XXXXXX"); printf '%s\n' "$new" > "$t"; mv "$t" "$M"); fi

# --- recommended tools, last: Orca is installed whatever happens here ------------------------------------------------
# One tab-separated row per tool: name, enables, presence check (cmd:<binary> or plugin:<id> in `claude plugin list`),
# link, then the Linux, Darwin and windows-gitbash install commands (- for none). Package-manager commands only; a tool
# whose only installer is a downloaded script stays link-only. Each command's source is in the comment above its row.
table() {
  cat <<'EOF'
# BEGIN recommended-tools
# codegraph: `npm i -g @colbymchenry/codegraph`, https://github.com/colbymchenry/codegraph (README, "Use npm instead").
codegraph	affected tests for orca-lc test-affected and evidence	cmd:codegraph	https://github.com/colbymchenry/codegraph	npm i -g @colbymchenry/codegraph	npm i -g @colbymchenry/codegraph	npm i -g @colbymchenry/codegraph
# codebase-memory-mcp: `npm install -g codebase-memory-mcp@latest`, https://github.com/DeusData/codebase-memory-mcp (README, npm).
codebase-memory-mcp	blast radius for orca-lc evidence	cmd:codebase-memory-mcp	https://github.com/DeusData/codebase-memory-mcp	npm install -g codebase-memory-mcp@latest	npm install -g codebase-memory-mcp@latest	npm install -g codebase-memory-mcp@latest
# direnv: https://direnv.net/docs/installation.html gives only package links and a curl | bash installer: link-only.
direnv	a per-repository GitHub account	cmd:direnv	https://direnv.net/docs/installation.html	-	-	-
# openspec: `npm install -g @fission-ai/openspec@latest`, https://github.com/Fission-AI/OpenSpec (README, npm; package
# @fission-ai/openspec, Node 22.12 or later). Its curl | sh and PowerShell irm | iex installers are scripts, so excluded;
# npm on every platform, like the rows above.
openspec	openspec CLI for the propose role's change proposals	cmd:openspec	https://github.com/Fission-AI/OpenSpec	npm install -g @fission-ai/openspec@latest	npm install -g @fission-ai/openspec@latest	npm install -g @fission-ai/openspec@latest
# mattpocock-skills: source https://github.com/mattpocock/skills, skills/productivity/grilling (MIT). Command from
# `claude plugin install --help` (plugin@marketplace) and the claude-plugins-official marketplace entry; `claude plugin
# list` prints an installed plugin as its plugin@marketplace id. The plugin's .claude-plugin/plugin.json lists its whole
# skill set (grilling, tdd, code-review, domain-modeling and some 35 more), so enables says so.
mattpocock-skills	grilling fallback; installs the whole mattpocock-skills set (about 40 skills)	plugin:mattpocock-skills@claude-plugins-official	https://github.com/mattpocock/skills	claude plugin install mattpocock-skills@claude-plugins-official	claude plugin install mattpocock-skills@claude-plugins-official	claude plugin install mattpocock-skills@claude-plugins-official
# END recommended-tools
EOF
}
case $(uname -s) in Linux) col=4;; Darwin) col=5;; MINGW*|MSYS*) col=6;; *) col=0;; esac
present_tool() {
  case $1 in
    cmd:*) command -v "${1#cmd:}" >/dev/null;;
    plugin:*) local out; out=$(claude plugin list 2>/dev/null) || return 1; case $out in *"${1#plugin:}"*) return 0;; esac; return 1;;
    *) return 1;;
  esac; }
offer() { local ans=
  [ $yes = 0 ] || return 0
  [ -t 0 ] || [ "${ORCA_INSTALL_PROMPT_STDIN:-}" = 1 ] || return 1
  printf "%s: %s. Install with '%s'? [y/N] " "$1" "$2" "$3"
  IFS= read -r ans || ans=
  [ -t 0 ] || echo
  case $(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]') in y|yes) return 0;; esac; return 1; }
ROWS=(); while IFS= read -r l; do case $l in ''|'#'*) continue;; esac; ROWS+=("$l"); done < <(table)
present=
for l in "${ROWS[@]}"; do
  IFS=$TAB read -r -a f <<< "$l"; name=${f[0]} en=${f[1]} link=${f[3]}; cmd=-
  [ $col = 0 ] || cmd=${f[col]:--}
  if present_tool "${f[2]}"; then present="$present $name"; continue; fi
  [ $noopt = 0 ] || continue
  if [ "$name" = mattpocock-skills ] && [ $gfb = 0 ] && [ $grilling_kept = 0 ] && [ -d "$here/skills/grilling" ]; then
    echo "grilling: using Orca's skill; fallback not installed (./install.sh --grilling-fallback to offer it)"; continue
  fi
  if [ "$cmd" != - ] && command -v "${cmd%% *}" >/dev/null && offer "$name" "$en" "$cmd"; then
    read -r -a w <<< "$cmd"
    if "${w[@]}"; then echo "$name: installed"; else st=$?; echo "install.sh: $name: '$cmd' failed with exit $st" >&2; fi
  else echo "$name: not installed ($en); see $link"; fi
done
echo "recommended tools present:${present:- none}"
echo "per project: copy orca.example.json to <repo>/.orca/config.json"
