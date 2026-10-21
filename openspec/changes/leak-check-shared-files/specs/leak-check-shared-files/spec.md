## ADDED Requirements

### Requirement: File mode
`orca-lc leak-check --file <path>…` SHALL scan each path, as one line, and every line of each file against the denylists of the `leak-check` capability. It SHALL print `file:<line>  (<denylist file>:<line>)` for a hit in the contents and `file path:1  (<denylist file>:<line>)` for a hit in the path, never the path or the matched text, and exit 1 on hits. It SHALL exit 0 when the files are clean or when no denylist exists, and 2 when a path does not exist.

#### Scenario: Hit in a handoff file
- **WHEN** `leak-check --file` runs on a handoff whose line 12 contains a denylisted term
- **THEN** it prints `file:12  (<denylist file>:<line>)`, exits 1, and the output contains neither the path nor the term

#### Scenario: Denylisted path with clean contents
- **WHEN** `leak-check --file` runs on a clean file whose path contains a denylisted term
- **THEN** it prints `file path:1  (<denylist file>:<line>)`, exits 1, and the output does not contain the term

#### Scenario: Missing path
- **WHEN** `leak-check --file` is given a path that does not exist
- **THEN** it exits 2

### Requirement: Shared files are refused before they are written
When `leakCheck` is `true` and a denylist exists, `discover`, `role start` and `inbox send` SHALL scan the content they are about to write. On a hit they SHALL write nothing, print the location as `<command> <field>` with the denylist line, and exit 1. When `leakCheck` is absent or false, they SHALL behave as before this change.

#### Scenario: Discovery with a denylisted rule
- **WHEN** `orca-lc discover some-slug "<rule containing a denylisted term>"` runs with `leakCheck` true
- **THEN** no discovery file is created and stderr names `discover rule` and the denylist line

#### Scenario: Role start with a denylisted handoff body
- **WHEN** `orca-lc role start <ticket> apply` receives a body containing a denylisted term with `leakCheck` true
- **THEN** no herdr tab or agent is created, no handoff is written, and the command exits 1

#### Scenario: Notify falls back to the inbox
- **WHEN** `orca-lc notify <ticket> "<text containing a denylisted term>"` finds no live session and `leakCheck` is true
- **THEN** nothing is queued and the command exits 1

#### Scenario: Key absent
- **WHEN** `leakCheck` is not set and a discovery rule contains a denylisted term
- **THEN** the discovery is written as before this change

### Requirement: Handoff and discovery writes are scanned before they happen
When `leakCheck` is `true`, the PreToolUse hook SHALL scan the content of every Write, Edit and MultiEdit whose target resolves into the shared `handoffs/` directory or the shared discoveries directory (`discoveriesDir`, default `discoveries`). It SHALL also scan the target's file name. On a hit in either it SHALL block the call with exit 2 and name the location and denylist line, never the term. A location SHALL be `<kind> file name:1` or `<kind> body:<line>`, never the file name itself, with `<kind>` `handoff` or `discovery`. The line number SHALL count within the written text (`content` or `new_string`), not within the file. A directory whose name only starts with that of a shared directory (`handoffs-old`) SHALL NOT match. Writes elsewhere, and all writes when `leakCheck` is absent or false, SHALL pass as before.

#### Scenario: Handoff body with a denylisted term
- **WHEN** a session writes a handoff body containing a denylisted term with `leakCheck` true
- **THEN** the Write is blocked, nothing reaches the file, and stderr names `handoff body:<line>`, where `<line>` counts within the written text, and the denylist line

#### Scenario: Discovery body edited with a denylisted term
- **WHEN** a session edits a discovery file under the shared discoveries directory and the `new_string` contains a denylisted term with `leakCheck` true
- **THEN** the Edit is blocked and stderr names `discovery body:<line>`, where `<line>` counts within `new_string`

#### Scenario: Denylisted file name with a clean body
- **WHEN** a session writes `<shared>/discoveries/<name containing a denylisted term>.md` with a clean body and `leakCheck` true
- **THEN** the Write is blocked, stderr names `discovery file name:1` and the denylist line, and stderr does not contain the term

#### Scenario: Sibling directory
- **WHEN** a Write with a denylisted term targets `<shared>/handoffs-old/x.md`
- **THEN** the hook does not scan it

#### Scenario: Handoff reached through a worktree's linked .orca
- **WHEN** the target path goes through a worktree's `.orca` link into the shared `handoffs/` directory
- **THEN** it is scanned the same way

#### Scenario: Write outside the shared directories
- **WHEN** a Write with a denylisted term targets a file outside the shared `handoffs/` and discoveries directories
- **THEN** the hook does not scan it
