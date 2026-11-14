## Why

`install.sh` hard-codes `$HOME/.claude` for the hook, skill and agent links, for the settings file it edits, and for the four hook commands it registers. Claude Code reads its config from `$CLAUDE_CONFIG_DIR` when that is set, so on such a machine Orca installs into a directory Claude Code never reads, and the registered hooks point at a missing path. Separately, `ensure()` matches an existing hook by exact command text, so a hand-edited command or one carried over from another machine gets a second entry on rerun and every hook fires twice (issue #56, confirmed on Linux with the variable unset).

## What Changes

- `install.sh` resolves one config dir, `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` (through `cygpath -u` when `cygpath` exists), and uses it for the links under `hooks/orca`, `skills/`, `agents/` and for `settings.json`. `~/.local/bin/orca-lc` is unchanged.
- The registered hook commands become `bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/orca/<script>.sh"`, expanded at run time.
- `ensure()` recognises an Orca hook in an event by its script path (`hooks/orca/<script>.sh`, either separator), rewrites only its `command`, and collapses duplicates to one entry.
- Install prints `config dir: <path>` before anything else.
- README Install section: `CLAUDE_CONFIG_DIR` is honoured; on Windows with Git outside `C:\Program Files\Git`, set `CLAUDE_CODE_GIT_BASH_PATH`.
- New test `tests/install-config-dir.sh`; `tests/install-keep.sh` unsets `CLAUDE_CONFIG_DIR`.

## Impact

- Code: `install.sh`. Docs: `README.md`. Tests: `tests/install-config-dir.sh` (new), `tests/install-keep.sh`.
- Existing installs with the variable unset: a rerun rewrites the four command strings and nothing else; links and settings location are unchanged.
- Installs with the variable set: links and registration move to the config dir; anything already under `$HOME/.claude` is left alone, not removed.
- Out of scope: `orca-lc` and the hooks themselves (neither reads `~/.claude`), wiring tests into `tests/run.sh`.
