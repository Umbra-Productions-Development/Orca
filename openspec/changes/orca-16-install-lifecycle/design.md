# Design: install lifecycle

## Shape of install.sh

The script runs in three phases. Nothing is written before phase 3.

1. **Parse flags.** The flags are `--yes`, `--no-optional`, `--uninstall`, `--force` and `--help`.
   - `--yes` and `--no-optional` together is a usage error: exit 2.
   - `--uninstall` with any flag other than `--force` is also a usage error: exit 2.
   - An unknown flag exits 2, and the usage text goes to stderr.
2. **Preflight (read-only).**
   - Check the required tools.
   - Detect link mode or copy mode.
   - Classify every target, and plan the settings.json change.
   - If any required tool is missing, or any target is a conflict and `--force` is not set: print every problem, print `nothing changed`, exit 1.
3. **Apply.**
   - Create or refresh the targets and write the manifest.
   - Write settings.json only if its content changes.
   - Then the recommended-tool offers run, last, so a declined or failed optional install never leaves Orca half-installed.

Exit codes:
- 0: success, including a second run that changes nothing.
- 1: missing required tool, a conflict, or an uninstall that left something in place.
- 2: usage error.

Every message that reports a problem goes to stderr and names the path or tool it is about.

## Required tools

The required tools are `claude git jq gh herdr`. Each is checked with `command -v`. Every missing one is listed on its own line:

```
install.sh: missing required tool: herdr (https://...)
```

Then the script exits 1 and changes nothing.
- The URL for each tool comes from a table in the script.
- jq is checked before anything uses it.

## Recommended tools

There is one table row per tool. Each row has:
- the tool's name
- a presence check: `command -v` for binaries, a directory test for the `grilling` skill
- the install link
- optional per-platform install commands

The platform comes from `uname -s`:
- `Linux`
- `Darwin`
- `MINGW*`/`MSYS*`, treated as `windows-gitbash`

Rules:
- Present tools are skipped silently. A one-line summary at the end lists them.
- Missing tool with a command for this platform, and the command's own launcher present (e.g. `npm`, `brew`, `go`): prompt `Install <tool> with '<cmd>'? [y/N] `.
- Missing tool with no command, or with a missing launcher: print `<tool>: not installed; see <link>`.
- Answers are read from stdin. Only `y` or `yes` (any case) accepts. Anything else declines, and so does EOF. Nothing is installed by default.
- Non-interactive behaviour: piped input, CI, or `</dev/null` each mean every offer is declined.
- `--yes` accepts every offer that has a command, without reading stdin.
- `--no-optional` skips the whole section except the summary line.
- A failed install command is reported with its exit code and does not change the script's exit code. Orca itself is already installed at that point.

The apply session fills in the commands only from each tool's own install docs, and leaves a row link-only when unsure. A wrong command is worse than a printed link.

## Link mode and copy mode

The mode is probed once:
- In a `mktemp -d` directory, `ln -s` a file, then test `[ -L ]`.
- A link means link mode. A copy means copy mode, which is Git Bash without Developer Mode, where MSYS `ln -s` silently copies.
- Nothing sets `MSYS=winsymlinks:*`. The script takes whatever the platform does.

In copy mode the script copies with `cp -R` itself. It does not rely on `ln` copying. It prints once:

```
copy mode: symlinks unavailable; re-run ./install.sh after every pull
```

## Ownership manifest

Path: `${XDG_STATE_HOME:-$HOME/.local/state}/orca/install.manifest`.
- It is outside `~/.claude`, so it never shows up as a skill, hook or agent.
- It is written atomically (temp file + `mv`) at the end of phase 3.

The format is one record per line, with tab-separated fields:

| kind | fields | meaning |
|---|---|---|
| `checkout` | path | the checkout that installed (`$here`) |
| `mode` | `link` or `copy` | the mode used |
| `link` | target, source | Orca made this symlink |
| `copy` | target, source, hash | Orca made this copy; hash is its content when written |
| `dir` | path | Orca created this directory (e.g. `~/.claude/skills` on a fresh HOME) |
| `settings-created` | path | settings.json did not exist before install |
| `settings-orig` | path of saved bytes | the pre-install settings.json, saved once at the first install that changes it |
| `settings-post` | hash | hash of settings.json right after Orca last wrote it |
| `hook` | event, command | a hook entry Orca added (not one already present) |

Hash:
- `sha256sum`, or `shasum -a 256` on macOS, over a stable listing.
- For a file: the hash of its bytes.
- For a directory: the hash of `find . -type f | LC_ALL=C sort` with each file's own hash. File modes are not included, because Git Bash reports them unreliably.

### Classifying a target

For each source and target pair, the target is in exactly one class:

| class | test | install does | uninstall does |
|---|---|---|---|
| absent | nothing at target | create (link or copy), record | n/a |
| ours, current | link: in manifest, `readlink` = source. copy: in manifest, hash = recorded hash = hash of source | nothing | remove |
| ours, stale copy | copy in manifest, hash = recorded hash, source changed (after a pull) | recopy, update the hash | remove |
| ours, edited | copy in manifest, hash ≠ recorded hash | **conflict**: report "edited since install" | leave, report |
| another checkout | link into a different Orca checkout, or a manifest whose `checkout` ≠ `$here` | **conflict** (the #42 behaviour) | remove only if the manifest records it |
| legacy, adoptable | not in the manifest. A symlink whose `readlink` = source, or a file/dir byte-identical to source | record it as ours (no write) | remove |
| foreign | anything else | **conflict**: report "exists, not created by Orca" | not touched |

`--force` resolves the conflicts of an install:
- It moves the target to `<target>.orca-bak-<UTC yyyymmddThhmmssZ>` and installs, then prints each backup path.
- It never deletes a file Orca did not create.
- On uninstall, `--force` also removes "ours, edited" targets, again by moving them to a backup.

The table covers every case in the issue:
- `rm -rf` is gone.
- An existing file at a link target is "foreign": it is reported, and nothing is removed.
- A second run finds every target "ours, current" and writes nothing.
- The manifest is rewritten only if its content changed, so a second run is byte-for-byte a no-op, manifest included.

### Directories

- `mkdir -p` happens per target. Each directory that did not exist is recorded as `dir`.
- Uninstall removes a recorded `dir` only if it is empty, deepest first.
- `~/.claude` itself is recorded too if Orca created it.

## settings.json

Orca's four hook entries are unchanged from today:
- the same events
- the same matchers
- the same commands (`bash "$HOME/.claude/hooks/orca/<x>.sh"`, with a literal `$HOME`)
- timeout 15

**Install:**
1. If the file is absent, plan to create it and record `settings-created`.
2. Compute the merged JSON with the existing `ensure()` jq program, adding only entries whose command is not already present. Record each added entry as `hook`.
3. Compare the result with the current content: `jq -S .` on both sides for the decision.
   - If they are equal, do not write. The bytes stay as they were, whatever their formatting.
4. If they differ:
   - Before the first write, copy the current bytes to `<state dir>/settings.json.orig` and record `settings-orig`, unless a record already exists from an earlier install.
   - Write the jq output and record `settings-post` as the hash of the new bytes.

**Uninstall:**
1. If the hash of settings.json equals `settings-post`, nobody touched it since Orca last wrote it.
   - Restore `settings.json.orig` byte for byte.
   - If the record is `settings-created`, delete the file instead.
2. Otherwise, remove Orca's entries with jq:
   - Remove every hook whose command is one of Orca's four commands. These commands are Orca's by construction, so legacy installs without `hook` records clean up too.
   - Drop a matcher group that ends up with no hooks.
   - Drop an event array that ends up empty, but only if a `hook` record shows Orca created it.
   - Drop `.hooks` if it ends up empty and Orca created it.
   - Print `settings.json was edited after install; removed Orca's hooks only (formatting may differ)`.
   - Every other hook, including another tool's SessionStart hook on the same event, is kept.

The byte-identical acceptance test is the first path. The second path keeps other hooks, but it only promises "same JSON", not "same bytes".

## Uninstall

`./install.sh --uninstall`:
- Reads the manifest. With no manifest, it falls back to classifying the known targets of this checkout, removing only "legacy, adoptable" ones, plus the settings.json hook removal.
- Removes:
  - "ours" targets: the link with `rm`, the copy with `rm -r`, only after re-checking its hash
  - empty recorded directories
  - Orca's hooks, as above
  - then the manifest, the saved settings bytes, and the state dir if it is empty
- Leaves the checkout, the dependencies and per-project `.orca/` untouched.
- Lists every path it left in place and why. Exits 1 if it left anything, 0 otherwise.

## Update

`git pull` in the install checkout, then `./install.sh`:
- Link mode: nothing to do unless skills, agents or hooks were added or removed. New ones are linked. A manifest entry whose source no longer exists in the checkout is removed if it is still ours, and reported otherwise.
- Copy mode: stale copies are refreshed (the "ours, stale copy" row) and edited copies are reported.

There is no `--update` flag. The docs give the two commands.

## Migration from today's installs

- **Symlink installs.** Every target is a symlink to `$here/...`, so it is "legacy, adoptable". The first run records it and changes nothing on disk.
- **Copy installs** (Git Bash, e.g. a machine installed before this change). Copies identical to the current source are adopted. Copies that differ (made from an older checkout, then pulled) are "foreign" and stop the install. The message names `--force`, which backs them up and recopies.
  - This is deliberate: the script cannot tell an old Orca copy from a user's file at the same path.
- **settings.json.** The hooks are already present, so install does not write and there is no `settings-orig`. A later uninstall takes the jq path. That is acceptable for existing installs; the byte-identical promise holds from a fresh install.

## Relationship with #42 / PR #46

PR #46 adds `--force` and refuses to relink when a managed symlink points outside `$here`. This change keeps both behaviours. The "another checkout" row is that check, and `--force` keeps its meaning. It extends them to copy mode and to non-symlink targets, and replaces the deletion with a backup.

Decision: **#46 merges first.** This change builds on it:
- Apply replaces #46's `pairs` check with the classifier.
- This change's doc tasks rewrite the README and daily-use lines that #46 added.
- The SKILL.md and verifier lines from #46 stay.

## Test harness

Decision: **build on PR #49 (`fix/test-harness`, commit 6c37aba)**. Do not add a second harness.
- Its `tests/run.sh` and `tests/lib.sh` are what the gate already expects (`testCommand: bash tests/run.sh`).
- Its helpers (`fail`, `assert_eq`, `assert_contains`, `assert_not_contains`, `assert_status`) are all these tests need.
- Two harnesses would conflict on the same paths. `feat/7-stacked-prs` is stacked on the same commit, so it adds nothing for install.

Decision: **stack on #49.** Its base must include #46, so the order is:
1. #46 merges to main.
2. `fix/test-harness` is rebased on that main. The orchestrator owns this, because apply never edits #49's branch.
3. Apply rebases `orca-16/work` onto `fix/test-harness`. The PR targets `fix/test-harness`, and after #49 merges it is retargeted to main.

The proposal commit only touches `openspec/`, so the rebase is trivial. If `fix/test-harness` does not contain #46 when apply starts, apply asks the orchestrator before writing code.

Install-specific helpers live in `tests/install.test.sh` itself, not in `lib.sh`, so this change does not edit #49's files. `lib.sh` prepends `$ORCA_SRC/bin` to PATH. The install tests replace PATH entirely (below), so that does not matter.

Test files are edit-locked. Apply runs `orca-lc test-lock on` before writing `tests/install.test.sh`, says why in the commit body, then runs `orca-lc test-lock off`.

## Test isolation

Each test builds a sandbox with `d=$(mktemp -d)`:
- `HOME=$d/home` and `XDG_STATE_HOME` unset, so the manifest lands under the fake HOME.
- `$d/bin` is the **entire** PATH. It holds:
  - **Wrappers for the utilities install.sh uses**, resolved from the real PATH before it is replaced: `#!/bin/sh` + `exec /real/path "$@"`. These are scripts, not symlinks, so they work in copy mode too.
    - install.sh keeps a comment naming every external command it calls.
    - The helper's list matches that comment. A test asserting no exit 127 catches drift.
  - **Real `jq`**, wrapped the same way.
  - **Stubs for the required tools** (`claude git gh herdr`): `exit 0` scripts. A test drops one to prove the failure.
  - **Recorder stubs for installer launchers** (`npm`, `brew`, …): they append `$0 $*` to `$d/calls` and exit 0. "Installs nothing" is asserted as "`$d/calls` does not exist". A real install can never run, because nothing real is on PATH.
- To test copy mode on any OS, the sandbox's `ln` wrapper copies instead of linking (`cp -R`), the way Git Bash does. The mode probe then picks copy mode. The same test file therefore covers both modes on Linux, macOS and Git Bash.
- The real HOME is never read or written. As a guard, every test asserts that its target paths start with `$d/`.

## Settled decisions

- #46 merges first; this change builds on it.
- This PR stacks on #49.
- Uninstall exits 1 when it leaves anything in place. It lists every such path with its reason, one per line, e.g. `left: <path> (edited since install)`.
- When there is no terminal, or stdin hits EOF, every prompt is declined. `--force` backs a target up and never deletes it.
- Apply verifies each recommended tool's install command against that tool's own docs. A row that cannot be verified stays link-only.
- The user does the Linux and WSL2 checks by hand.

## Open question

`herdr` stays required, as the issue says, but whether it should is unsettled because of #27 (native Claude Code mode without herdr). The required list is a single variable in install.sh, so #27 can move `herdr` to the recommended table with a one-line change and no other design change. Recommendation: keep it required here and decide in #27.
