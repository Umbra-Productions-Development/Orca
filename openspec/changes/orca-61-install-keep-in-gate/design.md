## Conversion

`tests/run.sh` runs each file as `bash -c '. lib.sh; cd "$TMPDIR"; . <file>; [ "$fails" = 0 ] && : > <marker>'`. So in the converted file:

- `src` is `$ORCA_SRC`. `$(dirname "$0")` no longer works: when sourced under `bash -c … _`, `$0` is `_`.
- `tmp` is `$TMPDIR`, and the file has no `mktemp -d` and no EXIT trap of its own; `run.sh` removes `$TMPDIR` after the file. The names the script creates under it (`probe-src`, `probe`, `elsewhere`, `other-orca`, `repo`, `home2`) do not clash with `lib.sh`'s `home` and `bin`.
- `HOME` starts as `lib.sh`'s `$TMPDIR/home`; the nested-skill section still switches to `$TMPDIR/home2`.
- `unset CLAUDE_CONFIG_DIR XDG_STATE_HOME` stays at the top of the file, as `tests/init.test.sh` does for the config dir, so `install.sh` never writes to a real config dir or, since #116, its manifest to a real state dir from the environment. `run` and `run2` keep #116's `</dev/null`, so `install.sh` never prompts for dependencies.
- `ok` becomes `ok() { [ "$1" = 0 ] || fail "$2"; }` (the `tests/leak-check.test.sh` pattern); the `fail=0` variable and the final `exit $fail` go. Call sites stay as they are, which keeps the diff to the header and the helpers.
- The "skip link cases" line becomes `echo "  SKIP: ln -s copies here (no native symlinks); link cases skipped"`, matching `tests/worktree.test.sh`.
- The header comment's `Run: tests/install-keep.sh` becomes `Run: tests/run.sh tests/install-keep.test.sh`.
- `set -uo pipefail` goes: no other `tests/*.test.sh` sets shell options, and the file is sourced into `run.sh`'s shell after `lib.sh`.
- The shebang goes and the mode becomes 100644, like every other `tests/*.test.sh`: the file is sourced, never executed.
- A guard at the top stops the file unless `lib.sh` has sandboxed it: it exits 1 unless `ORCA_TEST_TMP` is set and `HOME` is `$ORCA_TEST_TMP/home`. Run directly, `src` would be empty and `HOME`/`$sk` the real `~/.claude`, so the `rm`/`ln` steps would delete and relink the real skills and agents; a stray `ORCA_TEST_TMP` export alone does not pass it.

What stays: `install.sh` runs only from `$ORCA_SRC` or from the scratch clone in `$TMPDIR/repo`, always with a temp `HOME`, so it never relinks the real install. The stale fixture `git show 6468a79:skills/orca/SKILL.md` and `install.sh`'s own `shipped()` (`git log --all`) need the checkout's full history. That holds for the gate, which runs in a local checkout; a shallow clone would fail the "stale copy refreshed" check.

## Verification

Native Linux only. Before conversion, the script passed 20/20 there in about 1.7s, with the link cases running. After conversion: `tests/run.sh tests/install-keep.test.sh` passes; flipping one expectation (for example, the `cmp` in "fresh install puts Orca's grilling in place" against a wrong file) makes `run.sh` report the file as failed; then `orca-lc gate` passes.

## Decisions

- Rename to `tests/install-keep.test.sh` and convert to `lib.sh` helpers; `tests/run.sh` is not edited — user (recommended, accepted).
- `unset CLAUDE_CONFIG_DIR` stays in the test file, not `lib.sh` — user (recommended, accepted).
- The converted file keeps #116's `unset XDG_STATE_HOME` and `</dev/null` on `run`/`run2` after the rebase onto `main` — PR #152 review, should fix at `tests/install-keep.test.sh:8`.
- Output is only `FAIL:` lines like the rest of the suite, plus one `SKIP:` line where `ln -s` copies — user (recommended, accepted).
- No spec delta — user (recommended, accepted).
- `set -uo pipefail` dropped in the conversion — proposal review, suggestion 1.
- The file refuses to run outside `tests/run.sh` (no shebang, mode 644, guard at the top) — code review, should-fix 1; the guard checks `HOME` is `lib.sh`'s sandbox, not only that `ORCA_TEST_TMP` is set — code review, security-review suggestion (orchestrator took it).
- #61 and #85 are separate changes in separate PRs, using the same approach; they share no file, `tests/run.sh` included — user.

## Overlap with #85

#85 brings `tests/install-config-dir.sh` into the gate the same way. Both tickets were expected to edit `tests/run.sh`; under the decision above, neither does. They share no file, so the PRs merge in either order.
