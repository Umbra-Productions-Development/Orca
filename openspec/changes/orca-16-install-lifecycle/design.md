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
- `enables`: one line saying what the tool gives Orca, e.g. `code graph for affected tests`. Every message about the tool shows it.
- a presence check: `command -v` for binaries; for the `grilling` skill, `[ -d "$HOME/.claude/skills/grilling" ]` or the plugin being listed by `claude plugin list`
- the install link
- optional per-platform install commands

The table sits in install.sh as one block between the marker lines `# BEGIN recommended-tools` and `# END recommended-tools`, one tab-separated row per line: name, enables, presence check, link, then the Linux, Darwin and windows-gitbash commands (`-` for none). Tests read this block to know which commands to expect, and replace it in their sandbox copy of install.sh to drive the prompt path with a fixed fixture (Test isolation). No environment variable overrides the table.

Install commands are package-manager commands only (`npm`, `brew`, `go install`, `pipx`, `uv tool`, and `claude plugin install`). A tool whose only installer is a downloaded script (`curl ... | sh`) stays link-only, because the script would run code the table cannot show.

**`grilling`.** Source: the `grilling` skill in https://github.com/mattpocock/skills, at `skills/productivity/grilling` (MIT). It ships as the Claude Code plugin `mattpocock-skills@claude-plugins-official`, so its row has the command `claude plugin install mattpocock-skills@claude-plugins-official` on every platform, with that repository as its link. `claude plugin install` counts as a package-manager command: it installs a named package from a named marketplace, and runs no downloaded script. Its launcher is `claude`, a required tool, so the offer is always made when the skill is missing. Apply verifies the command and the plugin name upstream at task 2.7. If it cannot verify them, the row stays link-only with the repository link. Either way the row stays in the table. The plugin is named after the repository, not the skill, so it may install more than `grilling`. Apply also confirms at 2.7 which skills it installs; if it is more than `grilling`, the row's `enables` text says so, because a `y` or `--yes` must never add skills the offer did not name.

The platform comes from `uname -s`:
- `Linux`
- `Darwin`
- `MINGW*`/`MSYS*`, treated as `windows-gitbash`

Rules:
- Present tools are skipped silently. A one-line summary at the end lists them.
- Missing tool with a command for this platform, and the command's own launcher present (e.g. `npm`, `brew`, `go`): prompt `<tool>: <enables>. Install with '<cmd>'? [y/N] `.
- Missing tool with no command, with a missing launcher, or whose offer is declined: print `<tool>: not installed (<enables>); see <link>`.
- Prompts are read only when stdin is a terminal (`[ -t 0 ]`). When it is not (piped input, `</dev/null`, any CI runner), no prompt is printed and every offer is declined. No environment variable such as `CI` is consulted; the terminal test is the whole rule.
- On a terminal, only `y` or `yes` (any case) accepts. Anything else declines, and so does EOF. Nothing is installed by default.
- **Test-only override:** `ORCA_INSTALL_PROMPT_STDIN=1` makes the script read answers from stdin even when it is not a terminal, with the same accept rule. It exists so tests can drive the prompt path. It is named in install.sh's header comment as test-only, and is not in `--help`, the README or daily-use.md.
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
- It is written atomically (temp file in the same directory + `mv`) at the end of phase 3.
- The state dir, the manifest and `settings.json.orig` are created under `umask 077` (in a subshell, so the rest of the install keeps the user's umask). settings.json can hold secrets such as API keys in `env`, so its saved copy is readable only by the user: the dir is `0700`, the files `0600`.

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
- `sha256sum` when it is on PATH, otherwise `shasum -a 256` (macOS ships only the latter). One helper picks once; both give the same hex digest, so a manifest written with one verifies with the other.
- For a file: the hash of its bytes.
- For a directory: the hash of `find . -type f | LC_ALL=C sort` with each file's own hash. File modes are not included, because Git Bash reports them unreliably. Ownership is about content; a mode change alone never makes a target "edited".

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

`--force` against **another checkout** (the existing manifest's `checkout` ≠ `$here`) switches the install:
- A target the old manifest records as `link`, or as `copy` whose hash still matches its record, is Orca's. It is replaced in place (removed, then linked or copied from `$here`), not backed up.
- A target the old manifest records as a `copy` that was edited, and any target the old manifest does not record (a #42-style link into another checkout with no manifest, or a foreign file), is moved to a backup as above. A backed-up symlink is the link itself; nothing it points to is touched.
- The new manifest is built from the old one: `settings-created`, `settings-orig`, `settings-post`, `hook` and `dir` records carry over unchanged (the saved `settings.json.orig` stays where it is), while `checkout`, `mode`, `link` and `copy` records are rewritten for `$here`. A later uninstall from `$here` therefore restores settings.json and removes directories exactly as if `$here` had installed first.

The table covers every case in the issue:
- `rm -rf` is gone.
- An existing file at a link target is "foreign": it is reported, and nothing is removed.
- A second run finds every target "ours, current" and writes nothing.
- The manifest is rewritten only if its content changed, so a second run is byte-for-byte a no-op, manifest included.

### Directories

- `mkdir -p` happens per target. Each directory that did not exist is recorded as `dir`.
- Uninstall removes a recorded `dir` only if it is empty, deepest first.
- `~/.claude` itself is recorded too if Orca created it.
- A recorded `dir` kept because it still holds files Orca did not create counts as **left**: it gets its own `left: <dir> (not empty: holds files Orca did not create)` line and makes uninstall exit 1, like any other path left in place (Uninstall, below).
- A recorded `dir` is listed only when it directly holds something that is not itself a `left:` path or a kept recorded directory. A directory kept only because it contains paths already listed (an edited copy, a foreign file where Orca's target was expected, or a deeper kept directory) is not listed: the paths inside it already explain why it stays, and listing it too would name one reason twice. Uninstall still exits 1 because of those inner lines.

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
   - **Save the original only from a pristine file.** The file is pristine when no `settings-post` record exists and it holds none of Orca's four commands. Only then copy its bytes to `<state dir>/settings.json.orig` and record `settings-orig`. A file that is not pristine already carries Orca's work (an earlier install of this script, a legacy install, or an install whose original was dropped below), so its bytes are not the user's original: no `settings-orig` is recorded and uninstall takes the jq path. An absent file is pristine; its record is `settings-created` (step 1).
   - **If a `settings-post` record exists and the current file's hash differs from it**, the user edited the file since Orca last wrote it (for example, added a key and deleted one of Orca's hooks). Restoring the saved original on uninstall would then lose that edit. So before writing, drop the `settings-orig` record and delete `settings.json.orig`, and drop `settings-created` too. Uninstall then takes the jq path, which keeps the user's edit. Install prints `settings.json was edited since the last install; uninstall will remove Orca's hooks only`. The `settings-post` record stays, so no later install treats the file as pristine and saves Orca's own hooks as the original.
   - Write the jq output and record `settings-post` as the hash of the new bytes.
   - The write is atomic and keeps the file's mode: `tmp=$(mktemp "$S.XXXXXX")`, `cp -p "$S" "$tmp"` (copies the mode), write the jq output into `$tmp` (truncating keeps the mode), then `mv "$tmp" "$S"`. A new settings.json gets `0666` masked by the user's umask, as `echo > file` would. The temp file sits next to the file it replaces, so `mv` is a rename on the same filesystem.
   - **A symlinked settings.json is written through, never replaced.** Users who keep `~/.claude` settings in a dotfiles repo link the file there, and `mv` over the link would turn it into a regular file and cut it off from the repo. So before any read or write, `S` is resolved to the file the link points to, following every hop: `readlink -f` where it works (GNU, Git Bash, macOS 12.3 and later), else a small loop of `readlink` + `cd`, so older macOS works too. The temp file, `cp -p`, `mv` and the hash all use the resolved path; the link itself is never touched. A link whose target does not exist is a conflict: install reports `settings.json is a dangling symlink` and stops in preflight, changing nothing. Chosen over report-and-leave because a dotfiles link is a normal setup, and refusing it would leave those users without hooks. Both resolution branches are tested: 1.22 runs once with `readlink -f` and once with a `readlink` that rejects `-f`, through a two-hop chain so the loop runs more than once.

**Uninstall:**
1. If the hash of settings.json equals `settings-post` and a `settings-orig` or `settings-created` record exists, nobody touched it since Orca last wrote it.
   - Restore `settings.json.orig` byte for byte, with the same atomic, mode-keeping write as install, through a symlink as install does.
   - If the record is `settings-created`, delete the file instead. If settings.json is a symlink now, take path 2 instead: Orca never deletes a link's target, nor the link itself. A user who moved Orca's file into a dotfiles repo and linked it back chose to keep it there. Deleting the target would remove a file in the user's repo and leave a dangling link that stops the next install; removing the link would break their dotfiles setup. Path 2 removes only Orca's hooks and keeps both, and prints the symlink line below.
2. Otherwise, remove Orca's entries with jq:
   - Remove every hook whose command is one of Orca's four commands. These commands are Orca's by construction, so legacy installs without `hook` records clean up too.
   - Drop a matcher group that ends up with no hooks.
   - Drop an event array that ends up empty, but only if a `hook` record shows Orca created it.
   - Drop `.hooks` if it ends up empty and Orca created it.
   - Write with the same atomic, mode-keeping, link-following write as install.
   - Print `settings.json was edited after install; removed Orca's hooks only (formatting may differ)`. When path 2 was taken only because settings.json is now a symlink (step 1's hash and record checks held), print `settings.json is a symlink; removed Orca's hooks only, kept the link and its target` instead: the file was moved, not edited.
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
- Lists every path it left in place and why, one `left: <path> (<reason>)` line each. The reasons are `edited since install`, `not created by Orca` (a foreign file where the manifest expected Orca's) and `not empty: holds files Orca did not create` (a kept recorded directory that directly holds something no other `left:` line names, Directories above). Exits 1 if it left anything, 0 otherwise. A settings.json that took the jq path is not "left": Orca's part of it was removed.

## Update

`git pull` in the install checkout, then `./install.sh`:
- Link mode: nothing to do unless skills, agents or hooks were added or removed. New ones are linked. A manifest entry whose source no longer exists in the checkout is removed if it is still ours, and reported otherwise.
- Copy mode: stale copies are refreshed (the "ours, stale copy" row) and edited copies are reported.

There is no `--update` flag. The docs give the two commands.

## Migration from today's installs

- **Symlink installs.** Every target is a symlink to `$here/...`, so it is "legacy, adoptable". The first run records it and changes nothing on disk.
- **Copy installs** (Git Bash, e.g. a machine installed before this change). Copies identical to the current source are adopted. Copies that differ (made from an older checkout, then pulled) are "foreign" and stop the install. The message names `--force`, which backs them up and recopies.
  - This is deliberate: the script cannot tell an old Orca copy from a user's file at the same path.
- **settings.json.** The hooks are already present, so install does not write and there is no `settings-orig`. A later uninstall takes the jq path. That is acceptable for existing installs; the byte-identical promise holds from a fresh install. If the user deleted one of the four hooks before the first run under the new script, install writes, but the file still holds Orca's other commands, so it is not pristine: no `settings-orig` is saved, and uninstall still takes the jq path and removes all four.

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

Decision: **stack on #49.** Its base must include #46. When apply starts, after `git fetch origin`, exactly one of these holds, and each names one base:

| state at apply start | base | PR targets |
|---|---|---|
| #46 and #49 both merged: `git merge-base --is-ancestor <#46 merge commit> origin/main` succeeds, `origin/fix/test-harness` is gone or an ancestor of `origin/main`, and `tests/run.sh` exists on `origin/main` | `origin/main` | `main` |
| #46 merged, #49 open, and `origin/fix/test-harness` contains #46's merge commit | `origin/fix/test-harness` | `fix/test-harness`, retargeted to `main` after #49 merges |
| anything else (#46 not merged, or `fix/test-harness` lacks it) | none | apply notifies the orchestrator and stops |

Rebasing `fix/test-harness` onto main is the orchestrator's job, because apply never edits #49's branch. The proposal commit only touches `openspec/`, so the rebase is trivial.

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
  - **Stubs for the required tools** (`claude git gh herdr`): `exit 0` scripts. A test drops one to prove the failure. The `claude` stub also records `claude plugin install ...` calls to `$d/calls`, like the launchers below, and prints nothing for `claude plugin list`, so the `grilling` row reads as missing.
  - **A `uname` stub** that prints `$ORCA_TEST_UNAME`, default `Linux`. The platform is pinned per test, never taken from the host, so the same test picks the same table column on Linux, macOS and Git Bash.
  - **Recorder stubs for installer launchers** (`npm brew go pipx uv curl`): they append `$(basename $0) $*` to `$d/calls` and exit 0. "Installs nothing" is asserted as "`$d/calls` does not exist". `curl` is stubbed so a call to it would show up, though no row uses it (Recommended tools). A real install can never run, because nothing real is on PATH.
- **Copy mode** is tested on every OS: the sandbox's `ln` wrapper copies instead of linking (`cp -R`), the way Git Bash does, and the mode probe then picks copy mode.
- **Link mode** needs real symlinks, and the `ln` wrapper only execs the real `ln`, which on Git Bash without Developer Mode silently copies. So the sandbox probes once (real `ln -s` in a `mktemp -d`, then `[ -L ]`). Without symlinks, every link-mode case prints `SKIP link mode: no symlinks` and is not counted as passed; the copy-mode cases still run. Link mode is therefore proven only where symlinks work: Linux, macOS, or Git Bash with Developer Mode. On this machine (Git Bash, no Developer Mode) only copy mode is proven, and the user's manual Linux/WSL2 check runs `bash tests/run.sh` there to prove link mode.
- **The recommended-tools table is read, not hard-coded.** Tests run a sandbox copy of the checkout (`$d/src`). A helper reads the block between `# BEGIN recommended-tools` and `# END recommended-tools` in install.sh to list each row's name, enables text and command for the pinned platform, so the expected messages follow whatever apply puts in the table at 2.7. The helper fails the test when either marker is missing, the markers are out of order, or the block has no rows, so a test cannot pass on an empty table. The prompt-path tests (1.10b and the per-row part of 1.11) instead replace that block in `$d/src/install.sh` with a fixture of three rows, `fix-a` and `fix-b` with an `npm` command on every platform and `fix-c` link-only, all with presence checks that fail in the sandbox. The fixture always gives two command rows, so "fewer than two command rows on this platform" cannot happen and needs no SKIP. The real install.sh is never edited by a test.
- The real HOME is never read or written. As a guard, every test asserts that its target paths start with `$d/`.
- The `snapshot` helper records type, link target and content hash for every path. Where the platform reports modes reliably (the link-mode probe succeeded, i.e. not Git Bash without Developer Mode), it also records each file's mode, so the tests prove that install keeps settings.json's mode. This does not conflict with leaving modes out of the manifest hash: the hash decides ownership, and Git Bash's unreliable modes must not make a copy look edited; the snapshot only checks that nothing changed, and drops modes exactly where they are unreliable.

## Settled decisions

- #46 merges first; this change builds on it. The base is one of the three rows in Test harness.
- This PR stacks on #49.
- Uninstall exits 1 when it leaves anything in place, including a recorded directory kept because it holds the user's files. It lists every such path with its reason, one per line, e.g. `left: <path> (edited since install)`.
- When stdin is not a terminal, or hits EOF, every prompt is declined. Only the test-only `ORCA_INSTALL_PROMPT_STDIN=1` reads answers from a non-terminal stdin. `--force` backs a target up and never deletes it, except Orca's own recorded targets when switching from another checkout.
- Apply verifies each recommended tool's install command against that tool's own docs. Only package-manager commands are used; a row that cannot be verified, or whose installer is a downloaded script, stays link-only.
- The user does the Linux and WSL2 checks by hand, including `bash tests/run.sh` there for link mode.
- **`herdr` stays required here.** #27 (native Claude Code mode without herdr) makes the final call. The required list is a single variable in install.sh, so #27 can move `herdr` to the recommended table with a one-line change and no other design change.

## Review findings and how they are resolved

Against 400bee9.

- **F1** (orig restored over a later user edit): settings.json, install step 4 drops `settings-orig` when the file was edited since Orca last wrote it. Task 1.7b.
- **F2** (link mode unprovable on Git Bash): Test isolation, link-mode probe and `SKIP`. Tasks 1.1, 2.9, 4.4.
- **F3** (`--force` across checkouts): Target classification, "`--force` against another checkout". Task 1.15.
- **F4** (non-tty rule untestable): Recommended tools, `[ -t 0 ]` only, no `CI`, test-only `ORCA_INSTALL_PROMPT_STDIN=1`. Tasks 1.10, 1.10b.
- **F5** (offers say nothing of what a tool enables): `enables` field in every message; `grilling` presence path; its source was settled in the re-review below. Tasks 1.10b, 1.11.
- **F6** (kept directories and exit codes): Directories and Uninstall, a kept recorded directory counts as left. Tasks 1.17a, 1.17b.
- **F7** (open base and herdr): Test harness table, one base per state; herdr in Settled decisions. Tasks 0.1, 0.2.
- **S1–S4** are all taken; none conflicts with the design. S1: Manifest, `umask 077`; task 1.21. S2: settings.json, atomic mode-keeping write; task 1.21; it only looks at odds with "modes are not hashed", and Test isolation explains why both hold. S3: Recommended tools, package-manager commands only. S4: Manifest, hash helper; task 1.20.

Re-review, against d7da38f.

- **N1** (after the F1 drop, the next writing install saved Orca's own hooks as the original, and a legacy install did the same): settings.json, install step 4 saves `settings-orig` only from a pristine file (no `settings-post` record, none of Orca's four commands present); the `settings-post` record survives the F1 drop. Migration, settings.json covers the legacy case. Tasks 1.7b (third writing install, then uninstall), 1.7c (legacy variant), 2.5.
- **N2** (1.10b and 1.11 depended on the table at 2.7 and the host `uname`): Test isolation, `uname` stub pinned by `ORCA_TEST_UNAME`, the table read from its marker block, and a three-row fixture swapped into the sandbox copy for the prompt path; the fixture always has two command rows, so there is no fewer-than-two case. Recommended tools, table block. Tasks 1.1, 1.10b, 1.11, 2.7.
- **N3** (a dir kept only because it holds other `left:` paths was listed): Directories, a recorded dir is listed only when it directly holds something no other `left:` line names; Uninstall reasons match. Task 1.18, in copy mode.
- **N4** (row 1 lacked the #46 check): Test harness table, row 1 adds `git merge-base --is-ancestor <#46 merge commit> origin/main`. Task 0.1.
- **N5** (`mv` replaced a symlinked settings.json): settings.json, write-through to the resolved target, dangling link stops preflight; chosen over report-and-leave, reason given there. Tasks 1.22, 2.5.
- **N6** (numbering skipped 1.20): tasks renumbered, 1.21 to 1.20 and 1.22 to 1.21, references updated; the new symlink test takes 1.22, and test-lock off stays last at 1.23.
- **Grilling source:** Recommended tools, `grilling`. Source is mattpocock/skills, `skills/productivity/grilling` (MIT), installed with `claude plugin install mattpocock-skills@claude-plugins-official`, which counts as a package-manager command. Apply verifies it at 2.7; if it cannot, the row stays link-only. The row is never dropped. Tasks 2.7, 1.11.

None of N3 to N6 conflicts with the design; all four are taken.

Third review, against 9febef4.

- **S5** (1.7b's third install hit the F1 drop, not the N1 path): 1.7b's third step now removes Orca's hooks and resets `settings-post` in the sandbox manifest to match, so the hash equals `settings-post`, no orig record exists, and install writes because Orca's hook set grew; it asserts no `settings-orig` record and no `settings.json.orig`. 1.7c stays the guard for the "Orca's commands present" half. Task 1.7b.
- **S6** (`table_rows` could pass on an empty table): Test isolation, the helper fails on a missing or misordered marker or an empty block. Task 1.1b.
- **S7** (the `readlink` + `cd` fallback never ran): settings.json, write-through; 1.22 adds a variant with a `readlink` that rejects `-f` and a two-hop chain. Tasks 1.22, 2.5.
- **S8** (uninstall under `settings-created` deleted the target behind a symlink): Uninstall step 1, a settings.json that is now a symlink takes path 2; Orca deletes neither the link nor its target. Tasks 1.22, 2.6.
- **S9** (the offer did not say what the plugin installs): Recommended tools, `grilling`; apply confirms the plugin's skill list at 2.7 and the `enables` text names it when it is more than `grilling`. Task 2.7.

S5 to S9 are all taken; none conflicts with the design.

Delta check, against 6829070.

- **S10** ("them" lost its antecedent in the proposal): proposal, settings.json bullet now says "restores the original bytes".
- **S11** (path 2 said "edited" for a file that was only moved behind a symlink): Uninstall path 2 prints `settings.json is a symlink; removed Orca's hooks only, kept the link and its target` in that case. Task 1.22, created-then-linked variant.
