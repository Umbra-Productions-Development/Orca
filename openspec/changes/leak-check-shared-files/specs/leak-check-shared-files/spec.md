## ADDED Requirements

### Requirement: File mode
`orca-lc leak-check --file <path>…` SHALL scan each path, as one line, and every line of each file against the denylists of the `leak-check` capability. It SHALL print `file:<line>  (<list> denylist:<line>)` for a hit in the contents and `file path:1  (<list> denylist:<line>)` for a hit in the path, where `<list>` is `global` or `project`, never the path, the list's path or the matched text, and exit 1 on hits. It SHALL exit 0 when the files are clean or when no denylist exists. It SHALL exit 2 with `leak-check: no such file` when a path does not exist, and with `leak-check: unreadable file` when it cannot be read, in both cases without printing the path. A newline in a path SHALL be scanned as a space, within the one `file path:1` line. In `--file`, `--stdin`, `--pre-push` and range modes, a scan that fails after the lists were read SHALL print `orca-lc: leak-check: scan failed`, never awk's error, and exit 2. `--stdin <label>` SHALL use the same output and exit codes. When a denylist file exists but cannot be read, both modes SHALL print `orca-lc: leak-check: global denylist unreadable` or `orca-lc: leak-check: project denylist unreadable`, never the list's path, and exit 2.

#### Scenario: Hit in a handoff file
- **WHEN** `leak-check --file` runs on a handoff whose line 12 contains a denylisted term
- **THEN** it prints `file:12  (project denylist:<line>)`, exits 1, and the output contains neither the path nor the term

#### Scenario: Denylisted path with clean contents
- **WHEN** `leak-check --file` runs on a clean file whose path contains a denylisted term
- **THEN** it prints `file path:1  (project denylist:<line>)`, exits 1, and the output does not contain the term

#### Scenario: Missing path
- **WHEN** `leak-check --file` is given a path that does not exist
- **THEN** it prints `leak-check: no such file`, exits 2, and the output does not contain the path

#### Scenario: Unreadable path
- **WHEN** `leak-check --file` is given a file it cannot read
- **THEN** it prints `leak-check: unreadable file`, exits 2, and the output does not contain the path

#### Scenario: Unreadable denylist in file and stdin mode
- **WHEN** `leak-check --file` or `leak-check --stdin <label>` runs and a denylist file exists but cannot be read
- **THEN** it prints `orca-lc: leak-check: global denylist unreadable` or `orca-lc: leak-check: project denylist unreadable`, with no path and no awk error, and exits 2

#### Scenario: Scan fails in leak-check
- **WHEN** the scan fails after the lists were read, in `--file`, `--stdin`, `--pre-push` or range mode
- **THEN** the command prints `orca-lc: leak-check: scan failed`, exits 2, and the output does not contain awk's error or the list's path

#### Scenario: Path holding `=` or a newline
- **WHEN** `leak-check --file` is given a path containing `=` or a newline
- **THEN** its contents are scanned, and the path is reported, if at all, only as `file path:1`

### Requirement: Shared files are refused before they are written
When `leakCheck` is `true` and a denylist exists, `discover`, `role start` and `inbox send` SHALL scan the content they are about to write; `role start` SHALL also scan its ticket and role, as `role start ticket` and `role start role`, before its herdr and tty checks. On a hit they SHALL write nothing, print the location as `<command> <field>` with the denylist line, and exit 1. When a denylist file exists but cannot be read, or the scan fails, they and `notify`'s inbox fallback SHALL write nothing, print `orca-lc: leak-check: global denylist unreadable` or `orca-lc: leak-check: project denylist unreadable`, or `orca-lc: leak-check: scan failed, text not checked`, then `orca-lc: refused, nothing written`, never the list's path or an awk error, and exit 2. When `leakCheck` is absent or false, they SHALL behave as before this change, except for the messages that the requirement "Messages never echo unscanned arguments" changes.

#### Scenario: Discovery with a denylisted rule
- **WHEN** `orca-lc discover some-slug "<rule containing a denylisted term>"` runs with `leakCheck` true
- **THEN** no discovery file is created, and stderr carries the `leak-check: denylisted terms found.` header, `discover rule` with the denylist line, and `orca-lc: refused, nothing written`

#### Scenario: Role start with a denylisted handoff body
- **WHEN** `orca-lc role start <ticket> apply` receives a body containing a denylisted term with `leakCheck` true
- **THEN** no herdr tab or agent is created, no handoff is written, and the command exits 1

#### Scenario: Role start with a denylisted role or ticket
- **WHEN** `orca-lc role start <ticket> <role>` runs with `leakCheck` true and the role or the ticket contains a denylisted term
- **THEN** it names `role start role` or `role start ticket` with the denylist line, does not echo the argument, makes no herdr call, writes no handoff, and exits 1

#### Scenario: Notify falls back to the inbox
- **WHEN** `orca-lc notify <ticket> "<text containing a denylisted term>"` finds no live session and `leakCheck` is true
- **THEN** nothing is queued and the command exits 1

#### Scenario: Unreadable denylist in a caller
- **WHEN** `discover`, `role start`, `inbox send` or `notify` falling back to the inbox runs with `leakCheck` true and a denylist file that exists but cannot be read
- **THEN** nothing is written or queued, no herdr tab or agent is created, stderr carries `orca-lc: leak-check: global denylist unreadable` or `orca-lc: leak-check: project denylist unreadable` and `orca-lc: refused, nothing written`, no path, and the command exits 2

#### Scenario: Scan fails in a caller
- **WHEN** `discover`, `role start` or `inbox send` runs with `leakCheck` true and the scan fails after the lists were read
- **THEN** nothing is written or queued, no herdr call is made, stderr carries `orca-lc: leak-check: scan failed, text not checked` and `orca-lc: refused, nothing written` with no awk error and no path, and the command exits 2

#### Scenario: Key absent
- **WHEN** `leakCheck` is not set and a discovery rule contains a denylisted term
- **THEN** the discovery is written as before this change

### Requirement: Handoff and discovery writes are scanned before they happen
When `leakCheck` is `true`, the PreToolUse hook SHALL scan the content of every Write, Edit and MultiEdit whose target resolves into the shared `handoffs/` directory or the shared discoveries directory (`discoveriesDir`, default `discoveries`). It SHALL also scan the target's file name. On a hit in either it SHALL block the call with exit 2 and name the location and denylist line, never the term. A location SHALL be `<kind> file name:1` or `<kind> body:<line>`, never the file name itself, with `<kind>` `handoff` or `discovery`. The line number SHALL count within the written text (`content` or `new_string`), not within the file. The target's parent SHALL be resolved the way `mkdir -p` walks it: existing directories through `cd -P`, missing ones as written, `..` dropping one. A directory whose name only starts with that of a shared directory (`handoffs-old`) SHALL NOT match. Writes elsewhere, and all writes when `leakCheck` is absent or false, SHALL pass as before.

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

#### Scenario: Target under missing directories
- **WHEN** a Write with a denylisted term targets `<shared>/handoffs/<t>/new/sub/x.md` where `new/sub` does not exist, or `<shared>/handoffs/<t>/x.md` before `handoffs/` exists
- **THEN** the Write is blocked

#### Scenario: Symlink after a missing directory or `..`
- **WHEN** the target path is `<worktree>/miss/../.orca/handoffs/<t>/x.md`, where `miss` does not exist and `.orca` is a link to the shared directory
- **THEN** the Write is scanned and blocked on a hit

#### Scenario: Parent name ending in a newline
- **WHEN** the target's parent, or a directory above it, is a link into `handoffs/` whose name ends in a newline
- **THEN** the Write is scanned and blocked on a hit

#### Scenario: Write outside the shared directories
- **WHEN** a Write with a denylisted term targets a file outside the shared `handoffs/` and discoveries directories
- **THEN** the hook does not scan it

### Requirement: A write the hook could not check is blocked
When `leakCheck` is `true` and the target resolves into a shared directory, the PreToolUse hook SHALL block the call on any `leak-check` exit other than 0 and 1 with `<kind> write blocked: leak scan failed (exit N), write not checked`. When the cause is an unreadable denylist, it SHALL append ` (leak-check: <global|project> denylist unreadable)`. It SHALL NOT echo any other output of the scan.

#### Scenario: Unreadable denylist blocks a handoff write
- **WHEN** a session writes a clean handoff body, or edits a discovery with a clean `new_string`, with `leakCheck` true and a denylist file that exists but cannot be read
- **THEN** the call is blocked and stderr names `handoff write blocked: leak scan failed (exit 2), write not checked (leak-check: <global|project> denylist unreadable)` (or `discovery write blocked: …`), with no path

#### Scenario: Installed orca-lc without leak-check
- **WHEN** the `orca-lc` on `PATH` answers `leak-check --stdin` with an error and exit 2 or 3, and a session writes a clean handoff with `leakCheck` true
- **THEN** the Write is blocked with `handoff write blocked: leak scan failed (exit N), write not checked`, and the stub's output is not echoed

### Requirement: Messages never echo unscanned arguments
`discover set` and `discover archive` on an unknown slug, and `notify` with no live session and no ticket in its target, SHALL fail without printing the slug or target. `notify`'s queued line SHALL NOT name the ticket, and `inbox send` SHALL print only the queued file's name. `role start` without a piped body SHALL fail naming its arguments only as `role start <ticket> <role>`. The PreToolUse test-lock block SHALL NOT print the target's path. These hold whether or not `leakCheck` is set.

#### Scenario: Unknown discovery slug
- **WHEN** `orca-lc discover set <slug containing a denylisted term> hook` names no existing discovery
- **THEN** the command fails and the output does not contain the slug

#### Scenario: Notify to a ticket with no live session
- **WHEN** `orca-lc notify <ticket containing a denylisted term> "clean"` queues to the inbox
- **THEN** the command prints `no live session for the ticket, queued: <file name>` and the output does not contain the ticket

#### Scenario: Inbox send
- **WHEN** `orca-lc inbox send <ticket> "clean"` queues a message
- **THEN** it prints only `<epoch>-<id>.md`, not the path or the ticket
