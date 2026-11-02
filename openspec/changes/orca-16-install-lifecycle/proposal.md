# install.sh: dependency checks, prompted installs, update and uninstall

Ticket: GitHub issue #16. Related: #42 (PR #46, relink guard), PR #49 (test harness), #28 (PR #57, the install keep rule and Orca's own `grilling` skill), #56 (PR #86, the Claude config dir and the hook matcher). All four PRs are on main.

## Why

`install.sh` today (after #57 and #86):

- lists missing tools loosely and never installs them; a missing required tool is a printed line, not a failure;
- has no uninstall and no documented update path beyond "run it again";
- keeps what Orca did not install (#57), but records nothing about what it did install: no record of the directories it created or the hook entries it added, so nothing can be undone exactly;
- on Git Bash without Developer Mode, `ln -s` copies instead of linking, and the readlink-based idempotence check in `link()` never matches a copy, so every run deletes and recopies every Orca copy;
- creates `<config dir>/settings.json` (the config dir is `$CLAUDE_CONFIG_DIR`, else `~/.claude`, #86) and rewrites it through `jq` on every run, so its bytes can change even when nothing was added.

## What changes

- **Two dependency tiers.**
  - Required, never installed by the script: Claude Code (`claude`), `git`, `jq`, `gh`, `herdr`. Any missing one makes install exit non-zero, name each missing tool with where to get it, and change nothing. `herdr` is required here as a one-line list entry; whether it stays required is decided in #27.
  - Recommended, offered one by one: `codegraph`, `codebase-memory-mcp`, `direnv`, `openspec`. Each offer says what the tool enables. A tool is offered for install only where a package-manager command exists for the detected platform; otherwise its install link is printed. Prompts are read only from a terminal: piped or closed stdin declines every offer. No install command ever runs without a `y` answer or `--yes`.
  - **Grilling fallback.** Orca ships its own `grilling` skill (#57), and that is the default. The mattpocock/skills plugin is a fallback only: it is offered when Orca's skill is not in place (its install target was kept for someone else's), or when the user asks with `--grilling-fallback`, for example because Orca's skill behaves strangely. Orca's own link never makes the fallback read as present.
- **Flags.** `--yes` (accept every offer that has a command), `--no-optional` (offer nothing, install nothing optional), `--grilling-fallback` (offer the mattpocock grilling plugin even when Orca's skill is in place), `--uninstall`, `--force` (switch an install that belongs to another Orca checkout, kept from #42), `--help`. Unknown flags exit 2.
- **Config dir, as #86 left it.** Every Claude target, settings.json included, sits under the config dir install prints first (`config dir: <dir>`). The manifest keeps the spelling of the first install, and a later run under another spelling of the same dir reuses it, so it changes nothing. #86's hook commands and its hook matcher are kept as they are; the matcher is the one definition of "Orca's hook" for install, the pristine check and uninstall, so installs made before #86 clean up too.
- **Ownership manifest.** Install records the config dir and every link, copy, directory, settings.json creation and hook entry it creates in `~/.local/state/orca/install.manifest`. An install under a different config dir than the recorded one stops and changes nothing; uninstall works on the recorded one. Uninstall reads it. The same rules work in link mode (Linux, macOS, Git Bash with Developer Mode) and copy mode (Git Bash without it).
- **Never remove what Orca did not create: #57's keep rule, unchanged.** A target Orca did not install is kept and reported, and install still exits 0, even with `--force`. Orca's own copies are recognised as #57 does, through the install checkout's git history (`shipped()`), plus the manifest's record of each copy's hash. A copy of Orca's that the user edited is kept the same way. `--force` only moves an install that belongs to another Orca checkout.
- **settings.json written only on change.** Install writes the file only when the merged content differs, atomically and keeping its mode, and saves the original bytes once, only from a file Orca has not yet touched (mode 0600, like the rest of the state dir). A symlinked settings.json is written through, keeping the link. Uninstall never deletes a link or its target. Uninstall restores the original bytes exactly when nobody edited the file since install. When the user edited it between installs, the saved original is dropped and uninstall removes Orca's hooks only. Other hooks are always kept.
- **Uninstall.** `./install.sh --uninstall` removes what the manifest says Orca created and is still unchanged, removes Orca's hook entries, restores or deletes settings.json, and lists every path it left in place with the reason, exiting 1 if there is any. A directory Orca created that still holds the user's files is kept and counts as left. It never uninstalls dependencies.
- **Update.** `git pull` in the install checkout, then `./install.sh` again. In copy mode this refreshes copies Orca still owns.
- **Tests.** `tests/install.test.sh` proves each acceptance criterion under a temporary HOME and a PATH that contains only the tools each test names, with stubs for everything external. Tests never touch the real HOME or install anything.
  `tests/install-keep.sh` (#57) and `tests/install-config-dir.sh` (#86) keep passing unchanged in what they assert.
- **Docs.** README.md and docs/daily-use.md cover install, update, uninstall, the flags, both platforms' modes, the manifest, and the grilling fallback.

## Out of scope

- Package-manager distribution of Orca itself (per the issue).
- Uninstalling dependencies.
- Native Windows outside Git Bash (#37).
- A per-project setup step (`orca-lc init`, #10).

## Acceptance (from #16)

- [ ] Running install twice is a no-op: second run changes no file and no byte.
- [ ] Install then uninstall leaves the config dir's `settings.json` byte-identical, with other hooks kept.
- [ ] A missing required tool exits non-zero and names the tool.
- [ ] `--no-optional`, and declining every prompt, install nothing.
- [ ] An existing file at a link target is reported, not removed (kept, exit 0, per #57).
- [ ] Verified on Linux (manual, by the user, including `bash tests/run.sh`, which proves link mode).
- [ ] Verified on WSL2 (manual, by the user, including `bash tests/run.sh`).

## Impact

- `install.sh` grows from about 45 lines to about 200 to 250 lines. It is one change in one PR.
- New: `tests/install.test.sh`, on the harness (`tests/run.sh`, `tests/lib.sh`) PR #49 put on main. The PR targets `main` (design.md, Test harness).
- `tests/install-keep.sh` and `tests/install-config-dir.sh` get a stdin and state-dir guard only (design.md, Test harness); their assertions stay.
- Docs: README.md, docs/daily-use.md.
- Existing installs migrate on their first run under the new script (design.md, Migration).
