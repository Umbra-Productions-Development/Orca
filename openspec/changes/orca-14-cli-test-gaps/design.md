# Design: close the CLI test gaps left after #49

## Context

Established facts (main at ac0c846):

- `tests/run.sh` runs every `tests/*.test.sh` in its own shell, in an empty temp dir, with `tests/lib.sh` sourced: `HERDR_ENV=0`, a throwaway `HOME`, stubbed `codegraph` and `codebase-memory-mcp`, `new_repo [config]`, `hook_json`, and the `assert_*` helpers. 8/8 files pass.
- Already covered: `config`, `worktree up/down` (with and without `--stack`, default-scheme ports, `.env.local`, `.orca` link), `handoff write/read/consume`, `--help`, the push gate in `hooks/pretool.sh` (fresh and stale marker), the merge block, and the commit notify hint.
- `gate-fresh` (bin/orca-lc:111) compares `$(git rev-parse --git-dir)/orca-gate-ok` with `tree_sig` (bin/orca-lc:75): HEAD plus a hash of `git diff HEAD` and the untracked files.
- `role owner` (bin/orca-lc:508) writes `<shared>/owners/<lowercased ticket>` on `--set`, prints the role, and exits 1 with "no owner recorded" when the file is absent. Without herdr it prints the role alone.
- `notify` (bin/orca-lc:189) without herdr takes the first `ticketPattern` match in the target, queues via `inbox send`, prints `no live session for <ticket>, queued: <path>`, and exits 1 with "nothing queued" when the target holds no ticket.
- `inbox read` (bin/orca-lc:215) prints each message under `--- inbox: <file>` and moves it to `archive/`; a second read prints nothing.
- `test-lock` (bin/orca-lc:291) toggles `<git-dir>/orca-allow-test-edits`. `hooks/pretool.sh:102` blocks (exit 2) an Edit/Write/MultiEdit whose `file_path` matches `testGlob` while that file is absent.
- `discover` (bin/orca-lc:261) writes `<shared>/discoveries/<slug>.md` with `rule`, `enforced-by` (default `none`), `since`; refuses an existing slug and an `enforced-by` outside `hook|skill|memory|reference|none` (exit 2). `archive` refuses while `enforced-by: none`, otherwise adds `archived:` and moves the file to `archive/`. `triage` lists `none` and untagged files only.
- `ports_for` (bin/orca-lc:303) gives `base + (n % slots) * step + i` per name in `.ports`, defaults 3000/100/10. Only the defaults are tested today (tests/worktree.test.sh:6-15).
- Open PRs #106 and #107 edit `tests/gate.test.sh` and `tests/worktree.test.sh`.

## Tests

Each file follows the existing style: a header comment naming the behaviour, `new_repo` per scenario, asserts on output, exit status and files.

### gate-fresh.test.sh
- After `orca-lc gate` (config gate `true`): `gate-fresh` exits 0.
- Edit a tracked file: exits 1. Run the gate again: 0.
- Add an untracked, non-ignored file: exits 1.
- Commit after a fresh gate: exits 1.
- No marker at all (fresh repo): exits 1.

### role.test.sh
- `role owner ABC-3 --set propose` prints `propose`; `role owner abc-3` prints `propose`; the file is `.orca/owners/abc-3`.
- `--set apply` replaces it.
- `role owner abc-4` with no file: exit 1, "no owner recorded".
- `--set` with no role: exit 2.

### inbox.test.sh
- `notify ABC-5 --role orchestrator "hi"` exits 0, prints `no live session for abc-5, queued:` and a path under `.orca/inbox/abc-5/`; the file holds `hi` and a `from:` line.
- `notify "see ABC-5 now" "x"` takes the ticket from the target text.
- `notify somebody "x"`: exit 1, "nothing queued", no inbox file.
- `inbox read abc-5` prints each message under `--- inbox:`, moves them to `archive/`; a second read prints nothing.
- `inbox read` for a ticket with no inbox prints nothing and exits 0.

### test-lock.test.sh
- Fresh repo: `test-lock status` prints `locked`; `on` then `status` prints `unlocked`; `off` then `locked`.
- With `"testGlob":"[/\\\\]tests[/\\\\]"`: an Edit payload for `<repo>/tests/x.test.sh` exits 2 with "test file edit blocked" while locked, 0 after `test-lock on`, 2 again after `off`. A Write payload behaves the same.
- A non-test path (`<repo>/src/a.sh`) exits 0 while locked.
- No `testGlob` in config: a test path exits 0.

### discover.test.sh
- `discover some-rule "a rule"` prints the file path; the file has `rule: a rule`, `enforced-by: none`, `since:`.
- Same slug again: exit 1. `enforced-by` outside the list: exit 2.
- `triage` lists `none      some-rule.md  a rule`; an untagged file shows as `untagged`; a file with `enforced-by: hook` is not listed.
- `discover archive some-rule` while `none`: exit 1. After `discover set some-rule hook`: archive prints `.../archive/some-rule.md`, the file has `archived:`, the live file is gone, and `triage` no longer lists it.
- `discover set missing hook`: exit 1.

### ports.test.sh
- Config `"ports":["web","db"],"portScheme":{"base":4000,"slots":50,"step":5}`: `worktree up abc-7` prints `ports WEB_PORT=4035 DB_PORT=4036`, and `.env.local` holds both lines.
- Slot wrap: `abc-57` gives the same ports as `abc-7` (57 % 50 = 7).
- A partial scheme (`{"base":5000}` only) keeps the default `slots` and `step`: `abc-7` gives `WEB_PORT=5070`.

## Decisions

- Scope is the gap between the issue's list and main: `gate-fresh` staleness, `role owner`, `notify` inbox fallback, `inbox read`, `test-lock` with the pretool edit block, `discover`/`triage`, custom `portScheme`; #61, #85, #87, #112, #89 and #15 stay separate — user (recommended, accepted).
- New files only, one per command group; `tests/gate.test.sh` and `tests/worktree.test.sh` are not edited, to avoid conflicts with #106 and #107 — user (recommended, accepted).
- A pre-existing bug a new test exposes goes to the orchestrator as a new issue, and that test is left out until the fix lands; apply does not fix it here — user (recommended, accepted).
- Apply proves "breaking any covered behaviour makes at least one test fail" by breaking each newly covered behaviour once by hand, seeing a test go red, reverting, and listing each break in the PR body — user (recommended, accepted).
- This change closes #14, with #49 as its first slice; one Linux run satisfies both the Linux and WSL2 boxes — user (recommended, accepted).

## Risks

- `tests/` matches this repo's `testGlob`, so apply creates the files under `orca-lc test-lock on` and says why in the commit body.
- Asserting on exact output text ties tests to wording; assert on the stable fragments listed above, not whole lines, except where the line is the contract (`triage`, ports).
