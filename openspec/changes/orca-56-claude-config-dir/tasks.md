## 1. install.sh

- [x] 1.1 Resolve `cfg=${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, through `cygpath -u` when `cygpath` exists; print `config dir: $cfg` as the first output line.
- [x] 1.2 Point the hooks, skills and agents link pairs and `S` at `$cfg`; `mkdir -p "$cfg"` before creating `settings.json`. Leave `$HOME/.local/bin/orca-lc` as is.
- [x] 1.3 Rewrite `ensure()` per design.md "Hook registration": match by `hooks[/\\]orca[/\\]<script>\.sh` in the event, rewrite only the first match's `command`, remove later matches and emptied groups, append when none match.
- [x] 1.4 Register the four hooks with command `bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/orca/<script>.sh"`.
- [x] 1.5 Update the header comment (install.sh:2) to name the config dir instead of `~/.claude`.

## 2. Docs

- [x] 2.1 README Install paragraph: install targets `$CLAUDE_CONFIG_DIR` when set, else `~/.claude`; the hook commands follow the variable at run time; on Windows with Git outside `C:\Program Files\Git`, set `CLAUDE_CODE_GIT_BASH_PATH` so Claude Code runs hooks through Git Bash.

## 3. Tests

- [x] 3.1 Add `tests/install-config-dir.sh` with the cases in design.md "Tests".
- [x] 3.2 `tests/install-keep.sh`: `unset CLAUDE_CONFIG_DIR` after the `HOME` export (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [x] 3.3 Run both test scripts and the gate (`orca-lc gate`); all pass.
