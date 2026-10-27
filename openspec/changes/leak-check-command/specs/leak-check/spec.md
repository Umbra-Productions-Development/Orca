## ADDED Requirements

### Requirement: Leak check scans commits against local denylists
`orca-lc leak-check` SHALL read `${XDG_CONFIG_HOME:-$HOME/.config}/orca/denylist`, then `<toplevel>/.orca/denylist`, with `.gitignore`-like syntax: one pattern per line, `#` comments, `*` wildcard, `!` re-allows, the last matching line wins, case is ignored, and only whole words match. It SHALL scan the branch name and, for each commit, the author and committer names and emails, the message, the paths of changed files, and the added lines.

#### Scenario: Term in an added line
- **WHEN** a commit in the range adds a line that contains a denylisted term
- **THEN** the command exits 1 and prints `commit <sha> <path>  (project denylist:<line>)` to stderr, or `(global denylist:<line>)` when the global list matched, never the list's path

#### Scenario: Term in an added line under a denylisted path
- **WHEN** the added line's file path matches any deny pattern, even one a later `!` line re-allows
- **THEN** the location is printed as `commit <sha> added line`, without the path

#### Scenario: Term in the branch name
- **WHEN** the branch name contains a denylisted term
- **THEN** the location is printed as `branch name`, without the branch

#### Scenario: Re-allowed term
- **WHEN** a term matches a deny line and then a later `!` line
- **THEN** it is not reported

#### Scenario: Clean range
- **WHEN** nothing in the range matches
- **THEN** the command exits 0 and prints nothing

### Requirement: Output never contains the term
Every line the command prints SHALL name a location and the denylist that matched, as `global denylist:<line>` or `project denylist:<line>`, never by the list's path. No line SHALL contain the matched text.

#### Scenario: Hit in a commit message
- **WHEN** a commit message contains a denylisted term
- **THEN** the output contains `commit <sha> message` and the denylist location, and does not contain the term

#### Scenario: Header per mode
- **WHEN** hits are found
- **THEN** `--pre-push` prints the header `pre-push: denylisted terms found, push refused.` and every other mode prints `leak-check: denylisted terms found.`

### Requirement: Range mode
With a range argument, the command SHALL scan the commits that `git log <range>` lists. With no argument, it SHALL scan every commit reachable from HEAD that no remote-tracking ref has (`HEAD --not --remotes`). In both cases it SHALL also scan the current branch name. With no denylist file it SHALL print `leak-check: no denylist, skipped` and exit 0. When `git log` fails on the range, it SHALL print `orca-lc: leak-check: bad range: a commit in it is not in this clone (a typo, or run git fetch first)` as its only line, without the range, and exit 2. When a denylist file exists but cannot be read, range mode and `--pre-push` SHALL print `orca-lc: leak-check: global denylist unreadable` or `orca-lc: leak-check: project denylist unreadable` to stderr, never the list's path, and exit 2.

#### Scenario: Default range
- **WHEN** `orca-lc leak-check` runs on a branch with two commits that no remote has
- **THEN** exactly those two commits and the branch name are scanned

#### Scenario: Commit on the base branch
- **WHEN** `orca-lc leak-check` runs on `main` with one unpushed commit carrying a denylisted term
- **THEN** the hit is reported and the command exits 1

#### Scenario: No denylist
- **WHEN** neither denylist file exists
- **THEN** the command prints `leak-check: no denylist, skipped` and exits 0

#### Scenario: Bad range
- **WHEN** `orca-lc leak-check <range>` names a revision that does not exist and a denylist exists
- **THEN** the command prints only the bad-range line (`orca-lc: leak-check: bad range: …`), with no command list, the output does not contain the range, and it exits 2

#### Scenario: Unreadable denylist
- **WHEN** a denylist file exists but cannot be read, in range mode or with `--pre-push`
- **THEN** the command prints only `orca-lc: leak-check: global denylist unreadable` or `orca-lc: leak-check: project denylist unreadable` to stderr, with no path and no awk error, and exits 2

### Requirement: Pre-push mode
With `--pre-push`, the command SHALL read git's pre-push stdin and, for each ref that is not a deletion, scan the remote branch name and the commits being pushed: `<remote sha>..<local sha>`, or `<local sha> --not --remotes` for a new branch. With no denylist file it SHALL exit 0 silently. When `git log` fails for a ref, it SHALL print `orca-lc: leak-check: bad range: a commit in it is not in this clone (a typo, or run git fetch first)` and exit 2, so the push is refused. It SHALL NOT require `.orca/config.json` or `jq`.

#### Scenario: Repository hook unchanged in behaviour
- **WHEN** this repository's `.githooks/pre-push` is enabled and a push carries a denylisted term
- **THEN** the push is refused with the same header and location lines as before this change, except that a branch hit prints `branch name`; a hit under a path matching any deny pattern, re-allowed or not, prints `commit <sha> added line`; a C-quoted path is read unquoted, with `\"` and `\\` as `"` and `\` and every other escape as a space; and the denylist is named `global denylist` or `project denylist` instead of its path

#### Scenario: Remote sha not in the local repo
- **WHEN** a push names a remote sha that the local repo does not have, and a denylist exists
- **THEN** `--pre-push` prints `leak-check: bad range`, exits 2, and the push is refused

#### Scenario: New branch
- **WHEN** a new branch is pushed whose commits are partly on a remote already
- **THEN** only the commits not on any remote are scanned

### Requirement: Opt-in gate step
When `.orca/config.json` sets `leakCheck` to `true`, `orca-lc gate` SHALL run the range-mode leak check after the gate command passes. A hit SHALL fail the gate and leave no marker. When `leakCheck` is absent or false, the gate SHALL NOT run it.

#### Scenario: Hit blocks the push
- **WHEN** `leakCheck` is true and an unpushed commit reachable from HEAD carries a denylisted term
- **THEN** `orca-lc gate` writes no marker and the pretool hook refuses `git push`

#### Scenario: Gate reports the failure
- **WHEN** `leakCheck` is true and the leak check finds a hit
- **THEN** `ORCA_GATE_FAIL` is the last line of the gate's output and the gate returns 1

#### Scenario: Unborn HEAD
- **WHEN** `leakCheck` is true, a denylist exists, and HEAD has no commit yet
- **THEN** the leak step exits 2 with `leak-check: bad range`, and the gate prints `ORCA_GATE_FAIL` and writes no marker

#### Scenario: Key absent
- **WHEN** `leakCheck` is not set
- **THEN** the gate runs only the gate command, as before this change
