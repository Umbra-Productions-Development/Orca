# Tasks: install lifecycle

Work top to bottom. Check a box only once its test passes, or for a task with no test, once its diff is committed. Commit after each group.

`<cfg>` is the config dir in the spelling the run works with (design.md, Config dir: the recorded spelling whenever a `config` record exists): `$HOME/.claude` in the sandbox, or `$d/cfg` in the tests that set `CLAUDE_CONFIG_DIR`. "Orca's hook" is a hook #86's `orca(s)` matcher accepts (design.md, settings.json), never an exact command string.

## 0. Base

- [x] 0.1 `git fetch origin`, then check the one row in design.md, Test harness:
  - `git merge-base --is-ancestor` succeeds against `origin/main` for `b387a59` (#46), `d863e74` (#57) and `233f913` (#86), and `tests/run.sh` and `tests/install-config-dir.sh` exist on `origin/main`: base `origin/main`, PR targets `main`.
  - Anything else: notify the orchestrator and stop.
- [x] 0.2 Confirm `orca-16/work` contains `origin/main` as 0.1 fetched it. If it does not, notify the orchestrator and stop: rebasing is the orchestrator's or propose's call, not apply's. #57's `pairs`/`todo`/`kept` loop and `link()` are replaced in task 2.3, keeping #46's, #57's and #86's behaviour (design.md, Relationship with #42; Config dir).
- [x] 0.3 Confirm `bash tests/run.sh`, `bash tests/install-keep.sh` and `bash tests/install-config-dir.sh` pass on the base before any change.

## 1. Tests first (test-lock on)

Run `orca-lc test-lock on`, and say why in the commit body ("new test file for #16"). Write `tests/install.test.sh` using the helpers from `tests/lib.sh`. Every test runs in its own sandbox and cleans up with `trap`.

- [x] 1.1 Sandbox helper `sandbox [mode]` (design.md, Test isolation):
  - `d=$(mktemp -d)` (under `lib.sh`'s `TMPDIR`), `HOME=$d/home`, `unset XDG_STATE_HOME CLAUDE_CONFIG_DIR`, `PATH=$d/bin` only.
  - Wrapper scripts (not symlinks) for the external commands listed in install.sh's header comment, plus real `jq`.
  - A wrapper for real `git` (install.sh reads history through `shipped`).
  - `exit 0` stubs for `gh herdr`. The `claude` stub exits 0, appends `claude plugin install ...` calls to `$d/calls`, and for `claude plugin list` prints `$ORCA_TEST_PLUGINS` (default empty) and exits `${ORCA_TEST_PLUGIN_LIST_STATUS:-0}`.
  - Recorder stubs for `npm brew go pipx uv curl` that append to `$d/calls`.
  - A `uname` stub that prints `$ORCA_TEST_UNAME`, default `Linux`. Tests never read the host platform.
  - `mode=copy` replaces the `ln` wrapper with one that runs `cp -R`.
  - `mode=link` first probes real symlink support (`ln -s` in a `mktemp -d`, then `[ -L ]`). Without it, the case prints `SKIP link mode: no symlinks`, returns without asserting, and is not counted as passed. Below, "both modes" means copy mode always and link mode when available.
  - `git clone -q` the checkout into `$d/src`, then copy the working tree's install.sh, bin/, hooks/, skills/ and agents/ over it, so tests run the code under test, `shipped` sees real history, and tests never write to the real checkout.
  - Every install run reads stdin from `/dev/null` unless the test drives prompts.
- [x] 1.1b Table helpers (design.md, Test isolation):
  - `table_rows`: reads the block between `# BEGIN recommended-tools` and `# END recommended-tools` in `$d/src/install.sh` and prints, per row, the name, the enables text and the command for the platform `ORCA_TEST_UNAME` pins (`-` for none). It calls `fail` when either marker is missing, when the END marker comes before the BEGIN marker, or when the block holds no rows, so a test that reads the table can never pass on an empty one.
  - `use_fixture_table`: replaces that block in `$d/src/install.sh` with three rows: `fix-a` and `fix-b` with an `npm` command on every platform, `fix-c` link-only, each with a presence check that fails in the sandbox. The fixture always has two command rows, so no test needs a fewer-than-two SKIP.
- [x] 1.2 Helper `snapshot <dir>`: a sorted listing of every path under `<dir>` (tests snapshot `$HOME`, and `$d/cfg` too when they set `CLAUDE_CONFIG_DIR`), with type, link target and sha256 of content, plus each file's mode when the link-mode probe succeeded (design.md, Test isolation). Two snapshots compare with `assert_eq`.
- [x] 1.3 Guard: each test asserts that `$HOME`, and `$CLAUDE_CONFIG_DIR` when set, start with `$d/`, and that no run exits 127.
- [x] 1.4 **AC: twice is a no-op.** Run in both modes:
  - install with `--no-optional`, snapshot
  - install again, snapshot
  - snapshots are equal (manifest and settings.json included), and the second run exits 0
- [x] 1.5 **AC: settings byte-identical, other hooks kept.** Run in both modes:
  - Seed `settings.json` with non-default formatting and a foreign SessionStart hook plus another PreToolUse hook. Save its bytes.
  - Install, then assert all of the following:
    - all four Orca hooks are present
    - the foreign hooks are still present
  - Uninstall, then `cmp` the file against the saved bytes.
- [x] 1.5b **Config dir round** (design.md, Config dir). Both modes, `CLAUDE_CONFIG_DIR=$d/cfg`:
  - Seed `$d/cfg/settings.json` with a foreign hook, save its bytes, snapshot `$HOME` and `$d/cfg`.
  - Install: the first output line is `config dir: $d/cfg`; the hooks, skills, agents and settings.json are under `$d/cfg`; `$HOME/.claude` does not exist; `orca-lc` is at `$HOME/.local/bin/orca-lc`; the manifest has a `config` record naming `$d/cfg`; settings.json holds #86's four commands.
  - Install again: both snapshots equal the ones after the first install.
  - Uninstall: `cmp` settings.json against the saved bytes, and both snapshots equal the pre-install ones.
- [x] 1.5c **Another config dir.** Both modes. Install with `CLAUDE_CONFIG_DIR=$d/cfg`, snapshot `$HOME` and `$d/cfg`, then:
  - install with `CLAUDE_CONFIG_DIR` unset: exit 1, stderr names `$d/cfg` and `$HOME/.claude` and says `nothing changed`, both snapshots unchanged, `$HOME/.claude` does not exist
  - the same with `--force`: the same results
  - save the manifest's bytes; install with `CLAUDE_CONFIG_DIR="$d/cfg/"`, then with `CLAUDE_CONFIG_DIR="$d/cfg/../cfg"`: each exits 0, its first output line is `config dir: ` followed by that run's own spelling, `cmp` the manifest against the saved bytes, no output line after the first names a path with `$d/cfg//` or `$d/cfg/../`, and both snapshots are unchanged (the same dir, normalised; targets and records reuse the recorded spelling; design.md, Config dir)
  - uninstall with `CLAUDE_CONFIG_DIR` unset: the first output line is `config dir: $d/cfg`, the run exits 0, and both snapshots equal the pre-install ones
- [x] 1.5d **Legacy install, new config dir** (design.md, Config dir; Migration). Both modes. Pre-create the old layout in `$HOME/.claude` with no manifest, as in 1.14, with Orca's hooks in its settings.json. Snapshot `$HOME`, then:
  - install with `CLAUDE_CONFIG_DIR=$d/cfg`: exit 1, stderr names `$HOME/.claude` and says to run `--uninstall` with `CLAUDE_CONFIG_DIR` unset, and says `nothing changed`; the snapshot is unchanged and `$d/cfg` does not exist
  - uninstall with `CLAUDE_CONFIG_DIR` unset: no Orca target and no hook of Orca's is left in `$HOME/.claude`
  - install with `CLAUDE_CONFIG_DIR=$d/cfg`: exit 0
  - with no Orca install in `$HOME/.claude` (a fresh `$HOME`), install with `CLAUDE_CONFIG_DIR=$d/cfg` exits 0 at once
- [x] 1.6 settings.json absent before install: after install then uninstall, it is absent again.
- [x] 1.7 settings.json edited between install and uninstall (add a key):
  - uninstall removes only Orca's hooks: no hook the matcher accepts is left
  - the added key and the foreign hooks remain
  - the output says the file was rewritten
- [x] 1.7b settings.json edited between two installs (design.md, settings.json, install step 4). Both modes:
  - Seed settings.json with a foreign hook. Install.
  - Add a key, and delete one of Orca's four hooks. Install again: it re-adds that hook and prints that uninstall will remove Orca's hooks only. The manifest has no `settings-orig` record, and `settings.json.orig` is gone.
  - Simulate a pull that grows Orca's hook set, the path N1 broke: remove all four of Orca's hooks from settings.json, then, in the sandbox manifest only, set the `settings-post` record to the new file's hash. The file now matches `settings-post` (no drop fires) and holds no hook of Orca's, so only the "a `settings-post` record exists" half of the pristine check stops the save. Install a third time: it re-adds all four hooks, prints no "was edited" line, the manifest still has no `settings-orig` record, and `settings.json.orig` does not exist.
  - Uninstall: the added key and the foreign hook remain, and no hook of Orca's is left.
  - The other half of the pristine check (Orca's hooks present, no `settings-post` record) is 1.7c and 1.7d.
- [x] 1.7c Legacy variant (design.md, Migration, settings.json). Both modes:
  - Seed settings.json with a foreign hook and all four of Orca's hooks, and no manifest (the old layout, as in 1.14). Delete one of Orca's hooks.
  - Install: the hook is re-added, and the manifest has no `settings-orig` record.
  - Uninstall: the foreign hook remains, and no hook of Orca's is left.
- [x] 1.7d Pre-#86 variant (design.md, Migration, settings.json; review R6). Both modes, no manifest:
  - Seed settings.json with a foreign hook and Orca's hooks as installs before #86 wrote them: `bash "$HOME/.claude/hooks/orca/<x>.sh"` for `pretool`, `session-start` and `stop`, a Windows-path command (`bash "C:\Users\x\.claude\hooks\orca\post-read.sh"`) for `post-read`, and a duplicate `stop` entry in a second group. Add `stop.sh.disabled` as a foreign hook.
  - Install: exit 0; each event holds exactly one hook of Orca's, carrying #86's command; the manifest has no `settings-orig` record, and `settings.json.orig` does not exist.
  - Uninstall: no hook of Orca's is left, the foreign hook and `stop.sh.disabled` remain, and no hook points at a script uninstall removed.
- [x] 1.8 **AC: missing required tool.** For each of `claude git jq gh herdr`, remove its stub or wrapper, then:
  - exit status is 1
  - stderr names the tool
  - the `$HOME` snapshot is unchanged from before the run
- [x] 1.9 Two missing tools are both named in one run.
- [x] 1.10 **AC: optional installs nothing.** Run each of these with every recommended tool missing and launchers stubbed:
  - `--no-optional`
  - `ORCA_INSTALL_PROMPT_STDIN=1` with stdin `n` for every prompt: each prompt is printed, and each declined tool prints its `not installed (<enables>)` line (the `mattpocock-skills` row prints its `using Orca's skill` line instead and is not prompted)
  - stdin `</dev/null`, without the override: no prompt is printed
  - stdin piped from `yes y`, without the override: no prompt is printed (a non-terminal stdin declines even `y`)
  
  For all four, `$d/calls` does not exist, and none of the recommended tools' install targets exist.
- [x] 1.10b **Mixed answers.** `use_fixture_table`, `ORCA_TEST_UNAME=Linux`, `ORCA_INSTALL_PROMPT_STDIN=1`, `npm` stub present. Answer `y` to the `fix-a` prompt and `n` to the `fix-b` prompt:
  - `$d/calls` holds exactly one line, `fix-a`'s command
  - stdout holds both prompts, each with its tool's `enables` text
  - `fix-b` prints its `not installed (<enables>); see <link>` line, and `fix-c` (link-only) prints its link with its `enables` text and no prompt
  - the exit status is 0
- [x] 1.11 `--yes`, for each of `ORCA_TEST_UNAME=Linux`, `Darwin` and `MINGW64_NT-10.0`:
  - Real table: with every launcher stub present, `$d/calls` holds exactly the commands `table_rows` lists for that platform, in table order, except the `mattpocock-skills` row (Orca's grilling is in place, so it is not offered; 1.11b), and nothing for a `-` row. `curl` never appears in `$d/calls`.
  - `use_fixture_table`, `npm` stub removed: nothing is called, and each of `fix-a`, `fix-b` and `fix-c` prints its link with its `enables` text.
- [x] 1.11b **Grilling fallback** (design.md, Grilling fallback). Real table, `ORCA_TEST_UNAME=Linux`, both modes. When 2.7 left the row link-only, the cases that expect a `claude plugin install` line expect its link line instead.
  - Default install with `--yes`: Orca's grilling is in place at `<cfg>/skills/grilling`; `$d/calls` has no `claude plugin install` line; stdout has `grilling: using Orca's skill; fallback not installed (./install.sh --grilling-fallback to offer it)`; the present summary does not name `mattpocock-skills`.
  - `--yes --grilling-fallback`: `$d/calls` has the row's `claude plugin install` line.
  - `--grilling-fallback` with `ORCA_INSTALL_PROMPT_STDIN=1` and stdin `n` for every prompt: the row's prompt is printed with its `enables` text, and nothing is called.
  - A third-party `<cfg>/skills/grilling` directory before install, then `--yes`: the directory is kept (#57's `kept` line), and `$d/calls` has the row's `claude plugin install` line.
  - `ORCA_TEST_PLUGINS` set to a `claude plugin list` output naming the plugin (in the form 2.7 confirms), `--yes --grilling-fallback`: nothing is called for the row, and the present summary names `mattpocock-skills`.
  - The same with `ORCA_TEST_PLUGIN_LIST_STATUS=1`: the plugin reads as absent, so `$d/calls` has the row's `claude plugin install` line, and stdout has no line about `claude plugin list`.
- [x] 1.12 **AC: existing file at a link target** (design.md, Classifying a target; #57's keep rule). Run in both modes with a regular file at `<cfg>/agents/orca-verifier.md`, then at `~/.local/bin/orca-lc`, then a directory holding a file Orca never shipped at `<cfg>/skills/orca`. For each:
  - exit status is 0
  - stderr has #57's line, `install.sh: kept <target>, which Orca did not install; ...`
  - the file is unchanged (`cmp`)
  - every other target is installed, and the manifest has no `link` or `copy` record for the kept one
- [x] 1.13 Same setup with `--force`: the same four results, and no `.orca-bak-*` path exists anywhere under `$HOME`.
- [x] 1.14 Legacy adoption, both modes:
  - Pre-create the old layout without a manifest: symlinks in link mode, identical copies in copy mode.
  - Install: nothing on disk changes except that the manifest appears.
  - Uninstall removes the adopted targets.
  - Stale copy, copy mode: pre-create `<cfg>/skills/orca/SKILL.md` from an older commit of that path (`git -C $d/src show <commit>:skills/orca/SKILL.md`, a commit where it differs from the working tree), no manifest. Install: the copy now equals the source, the run exits 0 and prints no `kept` line.
- [x] 1.15 Another checkout (#42), both modes:
  - Seed settings.json with a foreign hook, save its bytes, and snapshot `$HOME`.
  - Install from `$d/src`, then from a second copy `$d/src2`.
  - The second run exits 1, names the other checkout, and changes nothing.
  - With `--force`, the install switches to `$d/src2`: the targets the first manifest recorded now point at (or are copies from) `$d/src2`, and no `.orca-bak-*` path exists.
  - After the switch, the manifest still has its `config` record. An install from `$d/src2` with `CLAUDE_CONFIG_DIR=$d/cfg`, with and without `--force`, exits 1 and changes nothing.
  - Uninstall from `$d/src2`: `cmp` settings.json against the saved bytes, and `$HOME` matches the pre-install snapshot.
  - Records carried by the switch (review R7). Start with settings.json absent (`settings-created`, `hooks-key`), install from `$d/src` in copy mode, and edit a file in the installed `<cfg>/skills/orca`, then install again (an `edited` record). Then `--force` from `$d/src2`: the manifest has the `config`, `hooks-key` and `settings-created` records, and an `edited` record for `<cfg>/skills/orca` with its source under `$d/src2`; stderr has the `edited since install` line for it. Edit settings.json (add a key) so uninstall takes the jq path, then uninstall from `$d/src2`: settings.json has no `hooks` key, and stdout has `left: <cfg>/skills/orca (edited since install)`.
  - Link mode only: a #42-style link into `$d/src` with no manifest, then `--force` from `$d/src2`: the link now points into `$d/src2`, no `.orca-bak-*` path exists, and `$d/src` is untouched.
  - Link mode only, no `--force`: replace `<cfg>/skills/grilling` with a link to a directory outside any Orca checkout (no `bin/orca-lc` above it). Install exits 0, the link is unchanged, stderr has #57's `kept` line for it, and nothing refuses (design.md, Classifying a target).
- [x] 1.16 Copy-mode update:
  - Install, edit a skill file in `$d/src`, install again: the copy is refreshed.
  - Then edit the installed copy and install again: stderr has `install.sh: kept <target>, edited since install; ...`, the copy is left as is, the manifest has an `edited` record and no `copy` record for it, and the run exits 0.
  - Install a third time: the same `edited since install` line (not #57's `which Orca did not install` line), the same `edited` record, exit 0.
  - Uninstall: stdout has `left: <target> (edited since install)`, and the target's parent directory is not listed.
  - Move the copy aside and install: Orca's copy is back, recorded `copy`, and no `edited` record is left.
- [x] 1.17a Clean uninstall, both modes, starting from an empty `$HOME`:
  - the run exits 0 and prints no `left:` line
  - `$HOME` matches the pre-install snapshot, with no manifest, no state dir and no directories Orca created
- [x] 1.17b Uninstall with a user file, both modes: after install, add a file inside `<cfg>/skills` (a directory Orca created and recorded):
  - the file survives byte for byte, and `<cfg>/skills` stays
  - stdout has exactly one `left:` line, `left: <cfg>/skills (not empty: holds files Orca did not create)`
  - the run exits 1
- [x] 1.18 Copy mode (design.md, Directories; Ownership manifest, Hash). After install, edit two files inside the installed copy `<cfg>/skills/orca` (one target, one `copy` record), and add one foreign file inside `<cfg>/agents`. Uninstall:
  - stdout has exactly two `left:` lines: `left: <cfg>/skills/orca (edited since install)`, and `left: <cfg>/agents (not empty: holds files Orca did not create)`, since `<cfg>/agents` directly holds the foreign file, which no other `left:` line names
  - `<cfg>/skills/orca` stays whole, both edited files byte for byte
  - `<cfg>/skills` stays on disk but is not listed: it holds only a path another `left:` line already names
  - the run exits 1
- [x] 1.19 Flags:
  - an unknown flag exits 2 and prints usage on stderr
  - `--yes --no-optional` exits 2
  - `--grilling-fallback --no-optional` exits 2
  - `--uninstall --force` exits 2
  - `--help` exits 0
- [x] 1.20 **macOS hash path.** Remove the `sha256sum` wrapper and add a `shasum` wrapper that accepts `-a 256` (it may exec the real `sha256sum` and fail on any other `-a`). Install, snapshot, install again, snapshot: the snapshots are equal, and the second run exits 0.
- [x] 1.21 State permissions, when the link-mode probe succeeded (modes are reliable): the state dir is `0700`, and the manifest and `settings.json.orig` are `0600`. A settings.json seeded with mode `0600` is still `0600` after install and after uninstall.
- [x] 1.22 Symlinked settings.json, link mode only (design.md, settings.json). Put the real file at `$d/dotfiles/settings.json` with a foreign hook, save its bytes, and make `<cfg>/settings.json` a symlink to it:
  - install: `<cfg>/settings.json` is still a symlink with the same target, and `$d/dotfiles/settings.json` holds the foreign hook and Orca's four
  - uninstall: the link is still there with the same target, and `cmp` the target against the saved bytes
  - dangling variant: point the link at a missing path; install exits 1, stderr says `settings.json is a dangling symlink`, and the `$HOME` snapshot is unchanged
  - no-`-f` variant (older macOS): add a `readlink` wrapper that exits 1 when any argument is `-f` and otherwise execs the real `readlink`. Use a two-hop chain, `<cfg>/settings.json` → `$d/hop1` → `dotfiles/settings.json` (relative, so the loop must resolve it from `$d`). Install and uninstall as above: both links are unchanged, the target holds Orca's four hooks after install, and `cmp` the target against the saved bytes after uninstall.
  - created-then-linked variant: start with no settings.json, install, then move the file to `$d/dotfiles/settings.json` and link `<cfg>/settings.json` to it, content unchanged (its hash still equals `settings-post`). Uninstall:
    - the run exits 0
    - stdout has `settings.json is a symlink; removed Orca's hooks only, kept the link and its target` and not the `was edited after install` line
    - the link is still there with the same target, and the target still exists
    - the target holds no hook of Orca's
    - a following install exits 0 (no dangling-link conflict)
- [x] 1.23 Run `orca-lc test-lock off`. The new tests fail against the current install.sh; that is expected. Commit.

## 2. install.sh

Follow design.md section by section. Keep `set -euo pipefail` and the header comment listing every external command.

- [x] 2.1 Flag parsing and usage (design.md, Shape), `--grilling-fallback` included. Makes 1.19 pass.
- [x] 2.2 Required-tool preflight with the URL table. Makes 1.8 and 1.9 pass.
- [x] 2.3 Mode probe, hash helper (`sha256sum` when on PATH, else `shasum -a 256`), manifest read and atomic write under `umask 077`, and the target classifier from the table in design.md (Classifying a target). Keep #57's `shipped`, `copied` and the link test in `ours`; replace the `pairs`/`todo`/`kept` loop and `link()`, so nothing runs `rm -rf` on a target the classifier did not class as Orca's. The preflight stops on another checkout without `--force` and on a dangling settings.json symlink, reporting each before any write; kept targets never stop it. Follow design.md, Config dir's spelling rule: record `config` as the current spelling prints, never rewrite it, normalise only when comparing, and when a record exists and compares equal build every target, record path, settings.json path and message from the recorded spelling (only the first line keeps the current spelling); stop on another config dir than the recorded one, `--force` or not, and on a legacy install in `$HOME/.claude` when `<cfg>` is another dir (design.md, Config dir). Keep #86's `cfg` and `cygpath -u` lines and the `config dir:` first line. Makes 1.12, 1.14, 1.15 (the refusal part), the install part of 1.5c, 1.5d, 1.20 and the dangling part of 1.22 pass.
- [x] 2.4 Apply phase: link or copy, `dir` records, the two `kept` lines (design.md, Classifying a target), dropping a kept target's record, and the `--force` switch from another checkout (replace Orca's targets in place; carry over and rewrite records exactly as design.md, Classifying a target, lists them). No backups. Write the manifest only when its content changes. The `edited` record and its removal (design.md, Classifying a target). Makes 1.4, 1.5b (install side), 1.13, 1.15 and 1.16 pass.
- [x] 2.5 settings.json, at `<cfg>/settings.json` (the recorded spelling when a record exists):
  - #86's `orca(s)` matcher and `ensure()` stay as they are; the matcher is one jq function that the merge, the pristine check and uninstall all call (design.md, settings.json)
  - write only on change, atomically, keeping the file's mode; when settings.json is a symlink, write the resolved target (`readlink -f`, or a `readlink` + `cd` loop where `-f` is missing) and never replace the link
  - save `settings.json.orig` once, under `umask 077`, and only from a pristine file: no `settings-post` record and no hook of Orca's present
  - drop `settings-orig` and `settings-created` when the file was edited since the last `settings-post`; keep the `settings-post` record
  - record `settings-created`, `settings-post`, `hook` (appended entries only, with `new-event`) and `hooks-key`
  
  Makes 1.5, 1.5b, 1.6, 1.7b, 1.7c, 1.7d, 1.21 and 1.22 pass on the install side.
- [x] 2.6 `--uninstall`, on the recorded config dir in its recorded spelling, which is also its `config dir:` first line (design.md, Config dir): targets, `edited` records listed as left, directories (a kept recorded dir is listed as left only when it directly holds something no other `left:` line names), settings restore or jq removal through the matcher (both through a symlink to its target; under `settings-created`, a settings.json that is now a symlink takes the jq path and is never deleted), manifest cleanup, the left-in-place report and exit code. Makes 1.5, 1.5b, 1.5c, 1.5d, 1.6, 1.7, 1.7b, 1.7c, 1.7d, 1.16, 1.17a, 1.17b, 1.18, 1.21 and 1.22 pass.
- [x] 2.7 Recommended-tool table and prompts:
  - Keep the table as one tab-separated row per line between `# BEGIN recommended-tools` and `# END recommended-tools` (design.md, Recommended tools), since tests read and replace that block.
  - Each row gets its `enables` line. Fill in the install commands from each tool's own docs, package-manager commands only. Put the source URL in a comment next to each command, and leave a row link-only when it can't be verified or its only installer is a downloaded script.
  - `mattpocock-skills` (design.md, Grilling fallback): source https://github.com/mattpocock/skills, `skills/productivity/grilling` (MIT). Verify upstream that `claude plugin install mattpocock-skills@claude-plugins-official` installs it, then use that command on every platform, with `claude` as the launcher. If it cannot be verified, leave the row link-only. Never drop the row. Also confirm, from the plugin's marketplace entry or manifest, which skills it installs. If it installs more than `grilling`, the row's `enables` text says so (e.g. `grilling fallback; installs the whole mattpocock-skills set`), so the prompt names everything a `y` adds. Put the source of that list in the comment next to the command.
  - The row's presence check is `claude plugin list` naming `mattpocock-skills`, never the `<cfg>/skills/grilling` directory. Verify upstream, with the install command, that `claude plugin list` exists and how its output names an installed plugin; match that form, and put its source in the comment. A non-zero exit or output that does not name the plugin reads as absent, with nothing extra printed. If the list subcommand or its form cannot be verified, leave the row link-only. Set the test stub's `$ORCA_TEST_PLUGINS` in 1.11b to that form. Gate its offer as design.md says: offered only when the grilling target was kept, the checkout ships no `skills/grilling`, or `--grilling-fallback` is set; otherwise print the `using Orca's skill` line.
  - Prompt reading only when `[ -t 0 ]` or `ORCA_INSTALL_PROMPT_STDIN=1`; name the variable as test-only in the header comment. `--yes` and `--no-optional`.
  
  Makes 1.10, 1.10b, 1.11 and 1.11b pass.
- [x] 2.8 Keep the closing line about `orca.example.json`. Print the copy-mode notice once.
- [x] 2.9 Under `orca-lc test-lock on`, make the one edit design.md, Test harness names to `tests/install-keep.sh` and to `tests/install-config-dir.sh` (stdin from `/dev/null` on every install run, `unset XDG_STATE_HOME`), say why in the commit body, then `orca-lc test-lock off`. No assertion changes.
- [x] 2.10 `bash tests/run.sh`, `bash tests/install-keep.sh` and `bash tests/install-config-dir.sh` pass on this machine. Say in the report which modes ran: link mode is proven only where symlinks work, and on Git Bash without Developer Mode the link-mode cases print `SKIP`. Commit.

## 3. Docs

- [x] 3.1 README.md, "Install" section:
  - required vs recommended tools
  - the flags
  - link mode vs copy mode and what each means for updates
  - where the manifest lives
  - "never removes what it did not create": keep the meaning of #57's keep-rule sentence (kept and reported, exit 0, even with `--force`), and say that `--force` only moves an install from another Orca checkout
  - the grilling fallback: Orca's skill is the default; `./install.sh --grilling-fallback` offers the mattpocock plugin, for when Orca's skill behaves strangely
  - Keep #86's lines as they are: the config dir (`$CLAUDE_CONFIG_DIR`, else `~/.claude`, printed first), the hook commands that follow the variable, and `CLAUDE_CODE_GIT_BASH_PATH`. Add that one install lives in one config dir, and that moving it is uninstall, then install; an install made before this change is in `~/.claude`, so before setting `CLAUDE_CONFIG_DIR` the user runs `./install.sh --uninstall` with it unset.
  - Replace the "It is idempotent; run it again after pulling" sentence, keeping #86's "one entry per Orca hook" fact, and the #46 sentence.
  - Update any flags or commands table the README has (applyChecks).
- [x] 3.2 README.md: an "Update" paragraph (`git pull`, then `./install.sh`) and an "Uninstall" paragraph (`./install.sh --uninstall`, what it keeps, exit 1 when it leaves something).
- [x] 3.3 docs/daily-use.md: update the Orca-stable row and the take-a-new-release lines with pull + rerun, the copy-mode note and the uninstall command. Replace the #46 line.
- [x] 3.4 Check that #46's lines in `skills/orca/SKILL.md` and `agents/orca-verifier.md` still match the new behaviour; reword only what no longer does.
- [x] 3.5 Check that the docs say nothing install.sh does not do. Run `./install.sh --help` and compare. Commit.

## 4. Gate

- [x] 4.1 Run `applyChecks` from `.orca/config.json`. Fix what they raise, or say in the commit body why it stays.
- [x] 4.2 Run `orca-lc gate` and make it pass. Say in the report which of its checks were skipped on this machine (shellcheck, gitleaks) and why.
- [x] 4.3 Run `orca-lc evidence`, dispatch `orca-verifier`, and report to the orchestrator.
- [x] 4.4 Leave the Linux acceptance box in proposal.md unchecked; the user verifies them by hand, including `bash tests/run.sh` there, which is where link mode is proven. Name them in the report as not yet verified.

## 5. Behaviour apply built beyond the sections (user decision, 2026-11-02)

install.sh already does all of this (design.md, Decisions: Keep what apply built beyond the sections). These tasks add its tests; install.sh changes only if one of them fails, and a failure that means the design is wrong goes to the orchestrator.

- [ ] 5.1 `orca-lc test-lock on`.
- [ ] 5.2 **Targets Orca no longer ships** (design.md, Targets Orca no longer ships). Both modes. Install, then `rm -r` one shipped skill's directory from `$d/src`'s working tree (no commit, so its files stay in the clone's history for `shipped`; in link mode its target becomes a dangling link):
  - rerun install: exit 0, stdout has `removed <cfg>/skills/<skill>, no longer shipped`, the target is gone, and the manifest has no record naming it
  - kept variant: before the rerun, replace the target with a directory holding a file Orca never shipped; the rerun exits 0, stderr has `install.sh: kept <cfg>/skills/<skill>, which Orca no longer ships and did not install as it is now`, the target is unchanged, and the manifest has no record naming it; a following uninstall neither removes it nor prints a `left:` line for it
  - copy mode, edited variant: edit a file inside the copy before the rerun; same results as the kept variant
  - gone variant: delete the target before the rerun; exit 0, no line names it, and the manifest has no record naming it
- [ ] 5.3 `-h` exits 0 and prints exactly what `--help` prints, on stdout.
- [ ] 5.4 **Uninstall tools** (design.md, Required tools). After an install, remove the `claude`, `gh` and `herdr` stubs: `--uninstall` exits 0 and removes Orca's targets. Then reinstall, remove the `jq` wrapper, and run `--uninstall`: exit 1, stderr names `missing required tool: jq`, and the `$HOME` snapshot is unchanged. Same for `git`.
- [ ] 5.5 **Invalid settings.json** (design.md, settings.json). Both modes. Write `{` to `<cfg>/settings.json`, snapshot `$HOME`, install: exit 1, stderr has `install.sh: <cfg>/settings.json is not valid JSON:` and `install.sh: nothing changed`, and the snapshot is unchanged. Repeat after a clean install (a manifest exists): same results.
- [ ] 5.6 **Uninstall with a dangling settings.json** (design.md, Uninstall). Link mode only, like 1.22. Install, then replace `<cfg>/settings.json` with a symlink to a missing path, and uninstall: exit 0, stderr has `install.sh: <cfg>/settings.json is a dangling symlink; left it as it is`, no `left:` line names it, the link is still there with the same target, Orca's other targets are gone, and the manifest is gone.
- [ ] 5.7 **A failing installer** (design.md, Recommended tools). `use_fixture_table`, `ORCA_TEST_UNAME=Linux`, an `npm` stub that records its call and exits 3, `--yes`: stderr has `install.sh: fix-a: 'npm i -g fix-a' failed with exit 3` and the same line for `fix-b`, `$d/calls` holds both commands in table order, stdout still ends with the `recommended tools present:` and `per project:` lines, the manifest exists, and the exit status is 0.
- [ ] 5.8 **An unknown platform** (design.md, Recommended tools). Real table, `ORCA_TEST_UNAME=FreeBSD`, every launcher stub present, `--yes`: `$d/calls` does not exist, each row of the real table, by the names `table_rows` lists (except `mattpocock-skills`, which prints its `using Orca's skill` line) prints its `not installed (<enables>); see <link>` line, and the exit status is 0.
- [ ] 5.9 `orca-lc test-lock off`. Run `bash tests/run.sh`; commit the tests.
- [ ] 5.10 Run `orca-lc gate` and report. Not tested: `cygpath -u` (Git Bash only; design.md, Test isolation).
