## ADDED Requirements

### Requirement: Stack commands receive the lowercase ticket

`orca-lc worktree up <ticket> --stack` and `orca-lc worktree down <ticket>` SHALL run `stackUp`, `migrateCommand` and `stackDown` with `ORCA_TICKET` set to the ticket in lowercase, whatever case it was typed in. The worktree directory keeps its uppercase name.

#### Scenario: Ticket typed in lowercase

- **WHEN** `orca-lc worktree up abc-1 --stack` runs
- **THEN** `stackUp` and `migrateCommand` see `ORCA_TICKET=abc-1`

#### Scenario: Ticket typed in uppercase

- **WHEN** `orca-lc worktree up ABC-1 --stack` runs
- **THEN** `stackUp` and `migrateCommand` see `ORCA_TICKET=abc-1`

#### Scenario: Down reaches the stack up created

- **WHEN** `orca-lc worktree up abc-1 --stack` ran and `orca-lc worktree down ABC-1 --force` runs
- **THEN** `stackDown` sees `ORCA_TICKET=abc-1`
