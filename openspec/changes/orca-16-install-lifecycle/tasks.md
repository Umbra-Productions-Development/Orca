# Tasks: install lifecycle

Work top to bottom. Check a box only once its test passes, or for a task with no test, once its diff is committed. Commit after each group.

## 0. Base

- [ ] 0.1 Get the test harness from PR #49 (design.md, Test harness).
  - If #49 is on main, rebase `orca-16/work` on main.
  - Otherwise, rebase onto `fix/test-harness`, and note the stack in the PR body.
- [ ] 0.2 If PR #46 is merged, rebase on it. Then remove its `pairs`/`--force` check as part of task 2.3, keeping its behaviour (design.md, Relationship with #42).
- [ ] 0.3 Confirm `bash tests/run.sh` passes on the base before any change.

## 1. Tests first (test-lock on)

Run `orca-lc test-lock on`, and say why in the commit body ("new test file for #16"). Write `tests/install.test.sh` using the helpers from `tests/lib.sh`. Every test runs in its own sandbox and cleans up with `trap`.

- [ ] 1.1 Sandbox helper `sandbox [mode]` (design.md, Test isolation):
  - `d=$(mktemp -d)`, `HOME=$d/home`, `unset XDG_STATE_HOME`, `PATH=$d/bin` only.
  - Wrapper scripts (not symlinks) for the external commands listed in install.sh's header comment, plus real `jq`.
  - `exit 0` stubs for `claude git gh herdr`.
  - Recorder stubs for `npm brew go pipx uv curl` that append to `$d/calls`.
  - `mode=copy` replaces the `ln` wrapper with one that runs `cp -R`.
  - Copies the checkout's install.sh, bin/, hooks/, skills/ and agents/ into `$d/src`, so tests never write to the real checkout.
- [ ] 1.2 Helper `snapshot <dir>`: a sorted listing of every path under `$HOME`, with type, link target and sha256 of content. Two snapshots compare with `assert_eq`.
- [ ] 1.3 Guard: each test asserts that `$HOME` starts with `$d/`, and that no run exits 127.
- [ ] 1.4 **AC: twice is a no-op.** Run in link mode and in copy mode:
  - install with `--no-optional`, snapshot
  - install again, snapshot
  - snapshots are equal (manifest and settings.json included), and the second run exits 0
- [ ] 1.5 **AC: settings byte-identical, other hooks kept.** Run in both modes:
  - Seed `settings.json` with non-default formatting and a foreign SessionStart hook plus another PreToolUse hook. Save its bytes.
  - Install, then assert all of the following:
    - all four Orca hooks are present
    - the foreign hooks are still present
  - Uninstall, then `cmp` the file against the saved bytes.
- [ ] 1.6 settings.json absent before install: after install then uninstall, it is absent again.
- [ ] 1.7 settings.json edited between install and uninstall (add a key):
  - uninstall removes only Orca's four commands
  - the added key and the foreign hooks remain
  - the output says the file was rewritten
- [ ] 1.8 **AC: missing required tool.** For each of `claude git jq gh herdr`, remove its stub or wrapper, then:
  - exit status is 1
  - stderr names the tool
  - the `$HOME` snapshot is unchanged from before the run
- [ ] 1.9 Two missing tools are both named in one run.
- [ ] 1.10 **AC: optional installs nothing.** Run each of these with every recommended tool missing and launchers stubbed:
  - `--no-optional`
  - stdin `n` for every prompt
  - stdin `</dev/null`
  
  For all three, `$d/calls` does not exist, and none of the recommended tools' install targets exist.
- [ ] 1.11 `--yes` runs exactly the commands in the platform table, and only when their launcher stub is present. With the launcher absent, the install link is printed and nothing is called.
- [ ] 1.12 **AC: existing file at a link target.** Run in both modes with a regular file at `~/.claude/agents/orca-verifier.md`, then at `~/.local/bin/orca-lc`, then a directory at `~/.claude/skills/orca`. For each:
  - exit status is 1
  - stderr names the path
  - the file is unchanged (`cmp`)
  - no other target was created (snapshot)
- [ ] 1.13 Same setup with `--force`: the original is at `<target>.orca-bak-*` byte for byte, and the target is now Orca's.
- [ ] 1.14 Legacy adoption:
  - Pre-create the old layout without a manifest: symlinks in link mode, identical copies in copy mode.
  - Install: nothing on disk changes except that the manifest appears.
  - Uninstall removes the adopted targets.
- [ ] 1.15 Another checkout (#42):
  - Install from `$d/src`, then from a second copy `$d/src2`.
  - The second run exits 1, names the other checkout, and changes nothing.
  - With `--force`, the install switches to `$d/src2`.
- [ ] 1.16 Copy-mode update:
  - Install, edit a skill file in `$d/src`, install again: the copy is refreshed.
  - Then edit the installed copy and install again: it is reported as edited, left as is, and the run exits 1.
- [ ] 1.17 Uninstall:
  - Afterwards `$HOME` matches the pre-install snapshot, with no manifest, no state dir and no directories Orca created.
  - A file the user added inside `~/.claude/skills` survives, and that directory stays.
- [ ] 1.18 Uninstall leaves an edited copy in place, names it, and exits 1.
- [ ] 1.19 Flags:
  - an unknown flag exits 2 and prints usage on stderr
  - `--yes --no-optional` exits 2
  - `--help` exits 0
- [ ] 1.20 Run `orca-lc test-lock off`. The new tests fail against the current install.sh; that is expected. Commit.

## 2. install.sh

Follow design.md section by section. Keep `set -euo pipefail` and the header comment listing every external command.

- [ ] 2.1 Flag parsing and usage (design.md, Shape). Makes 1.19 pass.
- [ ] 2.2 Required-tool preflight with the URL table. Makes 1.8 and 1.9 pass.
- [ ] 2.3 Mode probe, hash helper (`sha256sum`, or `shasum -a 256`), manifest read and atomic write, and the target classifier from the table in design.md. Remove `rm -rf`. The preflight reports every conflict before any write. Makes 1.12, 1.14 and 1.15 pass.
- [ ] 2.4 Apply phase: link or copy, `dir` records, `--force` backups. Write the manifest only when its content changes. Makes 1.4, 1.13 and 1.16 pass.
- [ ] 2.5 settings.json:
  - write only on change
  - save `settings.json.orig` once
  - record `settings-created`, `settings-post` and `hook`
  
  Makes 1.5 and 1.6 pass on the install side.
- [ ] 2.6 `--uninstall`: targets, directories, settings restore or jq removal, manifest cleanup, the left-in-place report and exit code. Makes 1.5, 1.6, 1.7, 1.17 and 1.18 pass.
- [ ] 2.7 Recommended-tool table and prompts:
  - Fill in the install commands from each tool's own docs. Put the source URL in a comment next to each command, and leave a row link-only when it can't be verified.
  - Prompt reading, `--yes` and `--no-optional`.
  
  Makes 1.10 and 1.11 pass.
- [ ] 2.8 Keep the closing line about `orca.example.json`. Print the copy-mode notice once.
- [ ] 2.9 `bash tests/run.sh` passes, in both modes, on this machine (Git Bash). Commit.

## 3. Docs

- [ ] 3.1 README.md, "Install" section:
  - required vs recommended tools
  - the flags
  - link mode vs copy mode and what each means for updates
  - where the manifest lives
  - "never removes what it did not create" and `--force` backups
  - Replace the "It is idempotent; run it again after pulling" sentence, and the #46 sentence if present.
  - Update any flags or commands table the README has (applyChecks).
- [ ] 3.2 README.md: an "Update" paragraph (`git pull`, then `./install.sh`) and an "Uninstall" paragraph (`./install.sh --uninstall`, what it keeps, exit 1 when it leaves something).
- [ ] 3.3 docs/daily-use.md: update the Orca-stable row and the take-a-new-release lines with pull + rerun, the copy-mode note and the uninstall command. Replace the #46 line if present.
- [ ] 3.4 If #46 was not merged, carry its notes in `skills/orca/SKILL.md` and `agents/orca-verifier.md`, reworded for this change.
- [ ] 3.5 Check that the docs say nothing install.sh does not do. Run `./install.sh --help` and compare. Commit.

## 4. Gate

- [ ] 4.1 Run `applyChecks` from `.orca/config.json`. Fix what they raise, or say in the commit body why it stays.
- [ ] 4.2 Run `orca-lc gate` and make it pass. shellcheck and gitleaks are skipped on this machine; say so in the report.
- [ ] 4.3 Run `orca-lc evidence`, dispatch `orca-verifier`, and report to the orchestrator.
- [ ] 4.4 Leave the Linux and WSL2 acceptance boxes in proposal.md for the orchestrator. Name them in the report as not yet verified.
