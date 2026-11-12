## ADDED Requirements

### Requirement: Advice for shell file operations

In a repository carrying `.orca/config.json`, the PreToolUse hook SHALL advise, and never block, when a Bash command segment reads, searches or writes a file that Read, Grep, Glob, Edit or Write covers. The advice SHALL be one line naming the command, the tool and `toolAdvice: false`.

#### Scenario: Reading a file
- **WHEN** the command is `cat notes.txt`
- **THEN** the hook exits 0 with additionalContext naming the Read tool

#### Scenario: Recursive search
- **WHEN** the command is `grep -r pattern dir`
- **THEN** the hook exits 0 with additionalContext naming the Grep tool

#### Scenario: Heredoc write
- **WHEN** the command is `cat > file <<EOF` followed by a body and `EOF`
- **THEN** the hook exits 0 with additionalContext naming the Write tool

#### Scenario: Pipeline over command output
- **WHEN** the command is `git log | grep fix` or `make | head -5`
- **THEN** the hook exits 0 with no output

#### Scenario: Command output redirected to a file
- **WHEN** the command is `make > build.log`
- **THEN** the hook exits 0 with no output

#### Scenario: Never a block
- **WHEN** any Bash command is evaluated by the tool advice
- **THEN** the hook does not exit 2 because of it

### Requirement: Off switch

The advice SHALL be on unless `.orca/config.json` sets `toolAdvice` to `false`.

#### Scenario: Turned off
- **WHEN** `toolAdvice` is `false` and the command is `cat notes.txt`
- **THEN** the hook exits 0 with no output

### Requirement: Once per session per kind

The hook SHALL advise at most once per session for each kind (read, search, write), keyed by the payload's `session_id`; without a `session_id` it SHALL advise on every matching call.

#### Scenario: Repeat read in one session
- **WHEN** a session already advised about a read runs `head other.txt`
- **THEN** the hook exits 0 with no output

#### Scenario: Other kind in the same session
- **WHEN** that session then runs `grep -r x .`
- **THEN** the hook advises about Grep

### Requirement: Code-graph advice first

When the code-graph advice applies to a call, the hook SHALL give only that message.

#### Scenario: Source file read
- **WHEN** `sourceGlob` matches the path in `cat src/app.ts`
- **THEN** the hook gives the code-graph advice and not the tool advice
