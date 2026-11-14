# Design: install.sh honours CLAUDE_CONFIG_DIR

## Context

Established facts:

- Only `install.sh` refers to `~/.claude`: the link pairs (install.sh:29-31), the settings file (install.sh:48) and the four commands (install.sh:52-55). Nothing in `bin/orca-lc` or `hooks/` does.
- `ensure()` (install.sh:51) appends a new entry unless some hook in the event has the exact command text.
- `tests/install-keep.sh` isolates by pointing `HOME` at a temp dir; it does not unset `CLAUDE_CONFIG_DIR`, so once install honours it the test would write into a real config dir.
- Claude Code without Git Bash falls back to a runner that substitutes variables itself; `$HOME` and `${VAR:-default}` do not expand as in bash there. `CLAUDE_CODE_GIT_BASH_PATH` points it at Git Bash.

## Config dir

- `cfg=${CLAUDE_CONFIG_DIR:-$HOME/.claude}`; when `command -v cygpath` succeeds, `cfg=$(cygpath -u "$cfg")`, so a Windows value such as `D:\.claude` becomes the form Git Bash's `ln -s` and `readlink` use.
- First output line: `config dir: $cfg`.
- Link pairs: `$here/hooks` → `$cfg/hooks/orca`, each skill → `$cfg/skills/<name>`, each agent → `$cfg/agents/<name>.md`. `$HOME/.local/bin/orca-lc` stays.
- Settings: `S="$cfg/settings.json"`; create `$cfg` first (`mkdir -p`) so `echo '{}' > "$S"` works on a fresh config dir.
- The keep rule (`ours`, `copied`, `shipped`) and the "another checkout" refusal run unchanged over the new paths.
- Nothing is created under `$HOME/.claude` when the variable is set.

## Hook registration

- Command text for each script: `bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/orca/<script>.sh"`, literal in settings.json, expanded when the hook runs.
- `ensure(event; matcher; script)`, per event:
  - A hook is Orca's when its `command` matches `hooks[/\\]orca[/\\]<script>\.sh`.
  - No match: append `{matcher, hooks: [{type: "command", command, timeout: 15}]}` as today.
  - One or more matches: the first match (in array order, groups then hooks) gets `command` set to Orca's text; its `matcher`, `timeout` and other fields are kept. Every later match is removed, and a group whose `hooks` becomes empty is removed.
  - Hooks that are not Orca's, in the same group or elsewhere, are untouched.
- A rerun over settings that already carry Orca's text changes nothing.

## Tests

`tests/install-config-dir.sh`, standalone like `tests/install-keep.sh`, `HOME` and `CLAUDE_CONFIG_DIR` both under a temp dir:

- Variable unset: links and `settings.json` land under `$HOME/.claude`; output starts with `config dir: $HOME/.claude`; the four commands carry the new text.
- Variable set: links and `settings.json` land in the config dir; `$HOME/.claude` does not exist afterwards.
- Rerun over settings holding the old `bash "$HOME/.claude/hooks/orca/<script>.sh"` commands, a hand-edited one, a Windows-separator one, and an existing duplicate pair: exactly one entry per Orca hook per event; a custom `timeout` on a matched entry survives; a non-Orca hook in the same group survives.
- Keep rule in the config dir: a third-party skill at `$CLAUDE_CONFIG_DIR/skills/grilling` is kept and reported.

`tests/install-keep.sh`: add `unset CLAUDE_CONFIG_DIR` next to the `HOME` export (test edit; unlock tests, give the reason in the commit body).

## Decisions

- Hook command text uses `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, expanded at run time, not a path baked in at install — user.
- `ensure()` identifies an Orca hook by `hooks/orca/<script>.sh` within the event, accepting `/` or `\` — user (recommended, accepted).
- A matched hook has only its `command` rewritten; `matcher` and `timeout` are kept — user (recommended, accepted).
- Existing duplicates collapse to the first match; emptied groups are dropped — user (recommended, accepted).
- A Windows-style `CLAUDE_CONFIG_DIR` is converted with `cygpath -u` when `cygpath` exists, else used as given — user (recommended, accepted).
- Install prints `config dir: <path>` as its first line — user (recommended, accepted).
- New standalone `tests/install-config-dir.sh`, and `tests/install-keep.sh` unsets `CLAUDE_CONFIG_DIR`; wiring into `tests/run.sh` is a follow-up behind #49/#61 — user (recommended, accepted).
- `~/.local/bin/orca-lc` stays put; one change, one PR — user (recommended, accepted).

## Risks

- A user with `CLAUDE_CONFIG_DIR` set and an older install under `$HOME/.claude` keeps that stale copy; install does not clean it up. Acceptable: it is never read by Claude Code, and removing it is outside the keep rule's spirit.
- The run-time expression does not expand under Claude Code's non-bash fallback runner; the README note on `CLAUDE_CODE_GIT_BASH_PATH` is the mitigation.
