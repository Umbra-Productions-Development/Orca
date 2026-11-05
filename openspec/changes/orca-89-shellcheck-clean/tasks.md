## 1. Tests first

- [x] 1.1 `orca-lc test-lock on`; add the two new cases in design.md "Tests" to `tests/handoff.test.sh`, and extend S-4 and S-7 in `tests/worktree.test.sh` as described there.
- [x] 1.2 Run `bash tests/run.sh` on the unchanged `bin/orca-lc`; all pass. Commit with the reason for the test edit in the body; `orca-lc test-lock off`.

## 2. bin/orca-lc

- [x] 2.1 SC2155 at `:193`: `local hdr; hdr="[orca from $(me_tag)]"`.
- [x] 2.2 SC2018/2019 at `:41`, `:295`, `:303`, `:329`, `:370`, `:520`: `[:upper:]`/`[:lower:]` classes.
- [x] 2.3 `:244` and `:359`: build the ports line with `stack_ports "$t" | paste -sd' ' -` into a local, no `echo $(…)`.
- [x] 2.4 `:310`: `export ORCA_TICKET=… ORCA_WORKTREE=…`.
- [x] 2.5 `:361`: `if`/`then`/`else`, `die` message unchanged.
- [x] 2.6 `:536`: `case "$r" in propose|apply|review)`.
- [x] 2.7 `:546`: `set -- <dir>/*.md` with a `[ -e "$1" ]` guard in place of `ls | sort`; last three; nothing when none.
- [x] 2.8 `:113`: `# shellcheck source=/dev/null` above `load_env`, with its reason.
- [x] 2.9 `:246`: split `f=$(ls -t …)` onto its own line inside the `read)` branch; `# shellcheck disable=SC2012` with its reason directly above that line, not above `read)`.

## 3. Verify

- [x] 3.1 `shellcheck bin/orca-lc` prints nothing and exits 0.
- [ ] 3.2 `orca-lc gate` passes.
- [ ] 3.3 PR body lists the findings beyond SC2155 as found during #89, and the ones left in `hooks/pretool.sh`, `.githooks/pre-push` and `tests/` as handed to #15.
