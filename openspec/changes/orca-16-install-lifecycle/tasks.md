# Tasks: install lifecycle

Work top to bottom. Check a box only once its test passes, or for a task with no test, once its diff is committed. Commit after each group.

## 0. Base

- [ ] 0.1 `git fetch origin`, then pick the base from the table in design.md, Test harness:
  - #46 and #49 both merged (`tests/run.sh` exists on `origin/main`, and `git merge-base --is-ancestor <#46 merge commit> origin/main` succeeds): base `origin/main`, PR targets `main`.
  - #46 merged, #49 open, and `git merge-base --is-ancestor <#46 merge commit> origin/fix/test-harness` succeeds: base `origin/fix/test-harness`, PR targets `fix/test-harness`.
  - Anything else: notify the orchestrator and stop. Do not rebase #49 yourself.
- [ ] 0.2 Rebase `orca-16/work` onto the base 0.1 picked. #46's `pairs`/`--force` check is replaced in task 2.3, keeping its behaviour (design.md, Relationship with #42).
- [ ] 0.3 Confirm `bash tests/run.sh` passes on the base before any change.

## 1. Tests first (test-lock on)

Run `orca-lc test-lock on`, and say why in the commit body ("new test file for #16"). Write `tests/install.test.sh` using the helpers from `tests/lib.sh`. Every test runs in its own sandbox and cleans up with `trap`.

- [ ] 1.1 Sandbox helper `sandbox [mode]` (design.md, Test isolation):
  - `d=$(mktemp -d)`, `HOME=$d/home`, `unset XDG_STATE_HOME`, `PATH=$d/bin` only.
  - Wrapper scripts (not symlinks) for the external commands listed in install.sh's header comment, plus real `jq`.
  - `exit 0` stubs for `git gh herdr`. The `claude` stub exits 0, appends `claude plugin install ...` calls to `$d/calls`, and prints nothing for `claude plugin list`.
  - Recorder stubs for `npm brew go pipx uv curl` that append to `$d/calls`.
  - A `uname` stub that prints `$ORCA_TEST_UNAME`, default `Linux`. Tests never read the host platform.
  - `mode=copy` replaces the `ln` wrapper with one that runs `cp -R`.
  - `mode=link` first probes real symlink support (`ln -s` in a `mktemp -d`, then `[ -L ]`). Without it, the case prints `SKIP link mode: no symlinks`, returns without asserting, and is not counted as passed. Below, "both modes" means copy mode always and link mode when available.
  - Copies the checkout's install.sh, bin/, hooks/, skills/ and agents/ into `$d/src`, so tests never write to the real checkout.
- [ ] 1.1b Table helpers (design.md, Test isolation):
  - `table_rows`: reads the block between `# BEGIN recommended-tools` and `# END recommended-tools` in `$d/src/install.sh` and prints, per row, the name, the enables text and the command for the platform `ORCA_TEST_UNAME` pins (`-` for none). It calls `fail` when either marker is missing, when the END marker comes before the BEGIN marker, or when the block holds no rows, so a test that reads the table can never pass on an empty one.
  - `use_fixture_table`: replaces that block in `$d/src/install.sh` with three rows: `fix-a` and `fix-b` with an `npm` command on every platform, `fix-c` link-only, each with a presence check that fails in the sandbox. The fixture always has two command rows, so no test needs a fewer-than-two SKIP.
- [ ] 1.2 Helper `snapshot <dir>`: a sorted listing of every path under `$HOME`, with type, link target and sha256 of content, plus each file's mode when the link-mode probe succeeded (design.md, Test isolation). Two snapshots compare with `assert_eq`.
- [ ] 1.3 Guard: each test asserts that `$HOME` starts with `$d/`, and that no run exits 127.
- [ ] 1.4 **AC: twice is a no-op.** Run in both modes:
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
- [ ] 1.7b settings.json edited between two installs (design.md, settings.json, install step 4). Both modes:
  - Seed settings.json with a foreign hook. Install.
  - Add a key, and delete one of Orca's four hooks. Install again: it re-adds that hook and prints that uninstall will remove Orca's hooks only. The manifest has no `settings-orig` record, and `settings.json.orig` is gone.
  - Simulate a pull that grows Orca's hook set, the path N1 broke: remove all four of Orca's hooks from settings.json, then, in the sandbox manifest only, set the `settings-post` record to the new file's hash. The file now matches `settings-post` (no drop fires) and holds none of Orca's commands, so only the "a `settings-post` record exists" half of the pristine check stops the save. Install a third time: it re-adds all four hooks, prints no "was edited" line, the manifest still has no `settings-orig` record, and `settings.json.orig` does not exist.
  - Uninstall: the added key and the foreign hook remain, and none of Orca's four commands is left.
  - The other half of the pristine check (Orca's commands present, no `settings-post` record) is 1.7c.
- [ ] 1.7c Legacy variant (design.md, Migration, settings.json). Both modes:
  - Seed settings.json with a foreign hook and all four of Orca's hooks, and no manifest (the old layout, as in 1.14). Delete one of Orca's hooks.
  - Install: the hook is re-added, and the manifest has no `settings-orig` record.
  - Uninstall: the foreign hook remains, and none of Orca's four commands is left.
- [ ] 1.8 **AC: missing required tool.** For each of `claude git jq gh herdr`, remove its stub or wrapper, then:
  - exit status is 1
  - stderr names the tool
  - the `$HOME` snapshot is unchanged from before the run
- [ ] 1.9 Two missing tools are both named in one run.
- [ ] 1.10 **AC: optional installs nothing.** Run each of these with every recommended tool missing and launchers stubbed:
  - `--no-optional`
  - `ORCA_INSTALL_PROMPT_STDIN=1` with stdin `n` for every prompt: each prompt is printed, and each declined tool prints its `not installed (<enables>)` line
  - stdin `</dev/null`, without the override: no prompt is printed
  - stdin piped from `yes y`, without the override: no prompt is printed (a non-terminal stdin declines even `y`)
  
  For all four, `$d/calls` does not exist, and none of the recommended tools' install targets exist.
- [ ] 1.10b **Mixed answers.** `use_fixture_table`, `ORCA_TEST_UNAME=Linux`, `ORCA_INSTALL_PROMPT_STDIN=1`, `npm` stub present. Answer `y` to the `fix-a` prompt and `n` to the `fix-b` prompt:
  - `$d/calls` holds exactly one line, `fix-a`'s command
  - stdout holds both prompts, each with its tool's `enables` text
  - `fix-b` prints its `not installed (<enables>); see <link>` line, and `fix-c` (link-only) prints its link with its `enables` text and no prompt
  - the exit status is 0
- [ ] 1.11 `--yes`, for each of `ORCA_TEST_UNAME=Linux`, `Darwin` and `MINGW64_NT-10.0`:
  - Real table: with every launcher stub present, `$d/calls` holds exactly the commands `table_rows` lists for that platform, in table order (`grilling` among them as a `claude plugin install` line when 2.7 verified it), and nothing for a `-` row. `curl` never appears in `$d/calls`.
  - `use_fixture_table`, `npm` stub removed: nothing is called, and each of `fix-a`, `fix-b` and `fix-c` prints its link with its `enables` text.
- [ ] 1.12 **AC: existing file at a link target.** Run in both modes with a regular file at `~/.claude/agents/orca-verifier.md`, then at `~/.local/bin/orca-lc`, then a directory at `~/.claude/skills/orca`. For each:
  - exit status is 1
  - stderr names the path
  - the file is unchanged (`cmp`)
  - no other target was created (snapshot)
- [ ] 1.13 Same setup with `--force`: the original is at `<target>.orca-bak-*` byte for byte, and the target is now Orca's.
- [ ] 1.14 Legacy adoption, both modes:
  - Pre-create the old layout without a manifest: symlinks in link mode, identical copies in copy mode.
  - Install: nothing on disk changes except that the manifest appears.
  - Uninstall removes the adopted targets.
- [ ] 1.15 Another checkout (#42), both modes:
  - Seed settings.json with a foreign hook, save its bytes, and snapshot `$HOME`.
  - Install from `$d/src`, then from a second copy `$d/src2`.
  - The second run exits 1, names the other checkout, and changes nothing.
  - With `--force`, the install switches to `$d/src2`: the targets the first manifest recorded now point at (or are copies from) `$d/src2`, and no `.orca-bak-*` path exists for them.
  - Uninstall from `$d/src2`: `cmp` settings.json against the saved bytes, and `$HOME` matches the pre-install snapshot.
  - Link mode only: a #42-style link into `$d/src` with no manifest, then `--force` from `$d/src2`: the link is moved to `.orca-bak-*`, and `$d/src` is untouched.
- [ ] 1.16 Copy-mode update:
  - Install, edit a skill file in `$d/src`, install again: the copy is refreshed.
  - Then edit the installed copy and install again: it is reported as edited, left as is, and the run exits 1.
- [ ] 1.17a Clean uninstall, both modes, starting from an empty `$HOME`:
  - the run exits 0 and prints no `left:` line
  - `$HOME` matches the pre-install snapshot, with no manifest, no state dir and no directories Orca created
- [ ] 1.17b Uninstall with a user file, both modes: after install, add a file inside `~/.claude/skills` (a directory Orca created and recorded):
  - the file survives byte for byte, and `~/.claude/skills` stays
  - stdout has exactly one `left:` line, `left: <HOME>/.claude/skills (not empty: holds files Orca did not create)`
  - the run exits 1
- [ ] 1.18 Copy mode (design.md, Directories). After install, edit two installed copies inside `~/.claude/skills/orca`, and add one foreign file inside `~/.claude/agents`:
  - each edited copy and the foreign file is listed on its own `left: <path> (<reason>)` line
  - `~/.claude/agents` is listed, since it directly holds the foreign file, which no other `left:` line names
  - `~/.claude/skills/orca` and `~/.claude/skills` stay on disk but are not listed: they hold only paths other `left:` lines already name
  - nothing else is listed
  - the run exits 1
- [ ] 1.19 Flags:
  - an unknown flag exits 2 and prints usage on stderr
  - `--yes --no-optional` exits 2
  - `--help` exits 0
- [ ] 1.20 **macOS hash path.** Remove the `sha256sum` wrapper and add a `shasum` wrapper that accepts `-a 256` (it may exec the real `sha256sum` and fail on any other `-a`). Install, snapshot, install again, snapshot: the snapshots are equal, and the second run exits 0.
- [ ] 1.21 State permissions, when the link-mode probe succeeded (modes are reliable): the state dir is `0700`, and the manifest and `settings.json.orig` are `0600`. A settings.json seeded with mode `0600` is still `0600` after install and after uninstall.
- [ ] 1.22 Symlinked settings.json, link mode only (design.md, settings.json). Put the real file at `$d/dotfiles/settings.json` with a foreign hook, save its bytes, and make `~/.claude/settings.json` a symlink to it:
  - install: `~/.claude/settings.json` is still a symlink with the same target, and `$d/dotfiles/settings.json` holds the foreign hook and Orca's four
  - uninstall: the link is still there with the same target, and `cmp` the target against the saved bytes
  - dangling variant: point the link at a missing path; install exits 1, stderr says `settings.json is a dangling symlink`, and the `$HOME` snapshot is unchanged
  - no-`-f` variant (older macOS): add a `readlink` wrapper that exits 1 when any argument is `-f` and otherwise execs the real `readlink`. Use a two-hop chain, `~/.claude/settings.json` → `$d/hop1` → `dotfiles/settings.json` (relative, so the loop must resolve it from `$d`). Install and uninstall as above: both links are unchanged, the target holds Orca's four hooks after install, and `cmp` the target against the saved bytes after uninstall.
  - created-then-linked variant: start with no settings.json, install, then move the file to `$d/dotfiles/settings.json` and link `~/.claude/settings.json` to it, content unchanged (its hash still equals `settings-post`). Uninstall:
    - the run exits 0
    - stdout has `settings.json is a symlink; removed Orca's hooks only, kept the link and its target` and not the `was edited after install` line
    - the link is still there with the same target, and the target still exists
    - the target holds none of Orca's four commands
    - a following install exits 0 (no dangling-link conflict)
- [ ] 1.23 Run `orca-lc test-lock off`. The new tests fail against the current install.sh; that is expected. Commit.

## 2. install.sh

Follow design.md section by section. Keep `set -euo pipefail` and the header comment listing every external command.

- [ ] 2.1 Flag parsing and usage (design.md, Shape). Makes 1.19 pass.
- [ ] 2.2 Required-tool preflight with the URL table. Makes 1.8 and 1.9 pass.
- [ ] 2.3 Mode probe, hash helper (`sha256sum` when on PATH, else `shasum -a 256`), manifest read and atomic write under `umask 077`, and the target classifier from the table in design.md. Remove `rm -rf`. The preflight reports every conflict before any write, a dangling settings.json symlink among them. Makes 1.12, 1.14, 1.15 (the conflict part), 1.20 and the dangling part of 1.22 pass.
- [ ] 2.4 Apply phase: link or copy, `dir` records, `--force` backups, and the `--force` switch from another checkout (replace recorded targets, carry settings, hook and dir records over). Write the manifest only when its content changes. Makes 1.4, 1.13, 1.15 and 1.16 pass.
- [ ] 2.5 settings.json:
  - write only on change, atomically, keeping the file's mode; when settings.json is a symlink, write the resolved target (`readlink -f`, or a `readlink` + `cd` loop where `-f` is missing) and never replace the link
  - save `settings.json.orig` once, under `umask 077`, and only from a pristine file: no `settings-post` record and none of Orca's four commands present
  - drop `settings-orig` and `settings-created` when the file was edited since the last `settings-post`; keep the `settings-post` record
  - record `settings-created`, `settings-post` and `hook`
  
  Makes 1.5, 1.6, 1.7b, 1.7c, 1.21 and 1.22 pass on the install side.
- [ ] 2.6 `--uninstall`: targets, directories (a kept recorded dir is listed as left only when it directly holds something no other `left:` line names), settings restore or jq removal (both through a symlink to its target; under `settings-created`, a settings.json that is now a symlink takes the jq path and is never deleted), manifest cleanup, the left-in-place report and exit code. Makes 1.5, 1.6, 1.7, 1.7b, 1.7c, 1.17a, 1.17b, 1.18, 1.21 and 1.22 pass.
- [ ] 2.7 Recommended-tool table and prompts:
  - Keep the table as one tab-separated row per line between `# BEGIN recommended-tools` and `# END recommended-tools` (design.md, Recommended tools), since tests read and replace that block.
  - Each row gets its `enables` line. Fill in the install commands from each tool's own docs, package-manager commands only. Put the source URL in a comment next to each command, and leave a row link-only when it can't be verified or its only installer is a downloaded script.
  - `grilling`: source https://github.com/mattpocock/skills, `skills/productivity/grilling` (MIT). Verify upstream that `claude plugin install mattpocock-skills@claude-plugins-official` installs it, then use that command on every platform, with `claude` as the launcher. If it cannot be verified, leave the row link-only. Never drop the row. Also confirm, from the plugin's marketplace entry or manifest, which skills it installs. If it installs more than `grilling`, the row's `enables` text says so (e.g. `grilling skill; installs the whole mattpocock-skills set`), so the prompt names everything a `y` adds. Put the source of that list in the comment next to the command.
  - Prompt reading only when `[ -t 0 ]` or `ORCA_INSTALL_PROMPT_STDIN=1`; name the variable as test-only in the header comment. `--yes` and `--no-optional`.
  
  Makes 1.10, 1.10b and 1.11 pass.
- [ ] 2.8 Keep the closing line about `orca.example.json`. Print the copy-mode notice once.
- [ ] 2.9 `bash tests/run.sh` passes on this machine (Git Bash). Here only copy mode is proven; the link-mode cases print `SKIP` unless Developer Mode is on. Say which in the report. Commit.

## 3. Docs

- [ ] 3.1 README.md, "Install" section:
  - required vs recommended tools
  - the flags
  - link mode vs copy mode and what each means for updates
  - where the manifest lives
  - "never removes what it did not create" and `--force` backups
  - Replace the "It is idempotent; run it again after pulling" sentence and the #46 sentence.
  - Update any flags or commands table the README has (applyChecks).
- [ ] 3.2 README.md: an "Update" paragraph (`git pull`, then `./install.sh`) and an "Uninstall" paragraph (`./install.sh --uninstall`, what it keeps, exit 1 when it leaves something).
- [ ] 3.3 docs/daily-use.md: update the Orca-stable row and the take-a-new-release lines with pull + rerun, the copy-mode note and the uninstall command. Replace the #46 line.
- [ ] 3.4 Check that #46's lines in `skills/orca/SKILL.md` and `agents/orca-verifier.md` still match the new behaviour; reword only what no longer does.
- [ ] 3.5 Check that the docs say nothing install.sh does not do. Run `./install.sh --help` and compare. Commit.

## 4. Gate

- [ ] 4.1 Run `applyChecks` from `.orca/config.json`. Fix what they raise, or say in the commit body why it stays.
- [ ] 4.2 Run `orca-lc gate` and make it pass. shellcheck and gitleaks are skipped on this machine; say so in the report.
- [ ] 4.3 Run `orca-lc evidence`, dispatch `orca-verifier`, and report to the orchestrator.
- [ ] 4.4 Leave the Linux and WSL2 acceptance boxes in proposal.md unchecked; the user verifies them by hand, including `bash tests/run.sh` there, which is where link mode is proven. Name them in the report as not yet verified.
