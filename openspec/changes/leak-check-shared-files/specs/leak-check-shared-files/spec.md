## ADDED Requirements

### Requirement: File mode
`orca-lc leak-check --file <path>…` SHALL scan every line of each file against the denylists of the `leak-check` capability. It SHALL print `<path>:<line>  (<denylist file>:<line>)` for each hit, never the matched text, and exit 1 on hits. It SHALL exit 0 when the files are clean or when no denylist exists, and 2 when a path does not exist.

#### Scenario: Hit in a handoff file
- **WHEN** `leak-check --file` runs on a handoff whose line 12 contains a denylisted term
- **THEN** it prints `<path>:12  (<denylist file>:<line>)`, exits 1, and the output does not contain the term

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
