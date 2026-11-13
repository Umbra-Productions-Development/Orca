## ADDED Requirements

### Requirement: The suite covers every command group named in issue #14
`tests/run.sh` SHALL run a test file for each of: `config`, `worktree up/down`, `gate-fresh`, `handoff`, `role owner`, `notify` inbox fallback, `inbox read`, `test-lock`, `discover`/`triage`, `ports_for` with default and custom `portScheme`, and the pretool push, merge and test-edit blocks. The `gate` command itself (exit status, marker, timeout) is covered by `tests/gate.test.sh` from PR #106, not by this change. It SHALL need only bash, git and jq, and no running herdr.

#### Scenario: Clean machine
- **WHEN** `bash tests/run.sh` runs on a machine with bash, git and jq and `HERDR_ENV` unset
- **THEN** every test file passes and the runner exits 0

### Requirement: The gate marker goes stale when the tree changes
`orca-lc gate-fresh` SHALL exit 0 only while the tree matches the one the last passing gate saw.

#### Scenario: Edit after the gate
- **WHEN** the gate passes and a tracked file is then edited, an untracked file added, or a commit made
- **THEN** `orca-lc gate-fresh` exits 1

### Requirement: The ticket owner is recorded and read back
`orca-lc role owner <ticket> --set <role>` SHALL record the owner under the lowercased ticket, and `orca-lc role owner <ticket>` SHALL print it in any ticket case.

#### Scenario: No owner
- **WHEN** no owner is recorded for the ticket
- **THEN** `orca-lc role owner` exits 1 saying no owner is recorded

### Requirement: notify falls back to the inbox
Without a live session, `orca-lc notify` SHALL queue the message to the inbox of the ticket found in the target, and `orca-lc inbox read` SHALL print queued messages once and archive them.

#### Scenario: Target is not a ticket
- **WHEN** the target holds no ticket id and no session is live
- **THEN** notify exits 1 and queues nothing

### Requirement: Test edits are blocked while locked
`hooks/pretool.sh` SHALL exit 2 on an Edit, Write or MultiEdit of a path matching `testGlob` while `orca-lc test-lock` is off, and exit 0 once it is on.

#### Scenario: Unlocked
- **WHEN** `orca-lc test-lock on` has run in the worktree
- **THEN** an Edit of a test file passes the hook

### Requirement: Discoveries are created, tagged, triaged and archived
`orca-lc triage` SHALL list discoveries enforced by nothing or untagged, and `orca-lc discover archive` SHALL refuse one still enforced by nothing.

#### Scenario: Archive after tagging
- **WHEN** a discovery is set to `hook` and archived
- **THEN** it moves to `archive/` with an `archived:` line and leaves the triage list

### Requirement: Ports follow a custom portScheme
`orca-lc worktree up` SHALL derive ports from `.portScheme.base`, `.slots` and `.step` when set, defaulting each missing key.

#### Scenario: Custom scheme
- **WHEN** `portScheme` is `{"base":4000,"slots":50,"step":5}` and ports are `web`, `db`
- **THEN** ticket `abc-7` gets `WEB_PORT=4035` and `DB_PORT=4036`
