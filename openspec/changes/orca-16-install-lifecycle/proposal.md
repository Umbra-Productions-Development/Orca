# install.sh: dependency checks, prompted installs, update and uninstall

Ticket: GitHub issue #16. Related: #42 (PR #46, relink guard), PR #49 (test harness).

## Why

`install.sh` today:

- lists missing tools loosely and never installs them; a missing required tool is a printed line, not a failure;
- has no uninstall and no documented update path beyond "run it again";
- runs `rm -rf` on whatever sits at a link target, so a file or directory Orca did not create is deleted without a word;
- on Git Bash without Developer Mode, `ln -s` copies instead of linking, so nothing records which files Orca owns and the readlink-based idempotence check never matches (every run recopies);
- creates `~/.claude/settings.json` and rewrites it through `jq` on every run, so its bytes can change even when nothing was added.

## What changes

- **Two dependency tiers.**
  - Required, never installed by the script: Claude Code (`claude`), `git`, `jq`, `gh`, `herdr`. Any missing one makes install exit non-zero, name each missing tool with where to get it, and change nothing. `herdr` is required here as a one-line list entry; whether it stays required is decided in #27.
  - Recommended, offered one by one: `codegraph`, `codebase-memory-mcp`, `direnv`, `openspec`, the `grilling` skill (from mattpocock/skills, offered as a Claude Code plugin install). Each offer says what the tool enables. A tool is offered for install only where a package-manager command exists for the detected platform; otherwise its install link is printed. Prompts are read only from a terminal: piped or closed stdin declines every offer. No install command ever runs without a `y` answer or `--yes`.
- **Flags.** `--yes` (accept every offer that has a command), `--no-optional` (offer nothing, install nothing optional), `--uninstall`, `--force` (switch an install that belongs to another checkout, kept from #42), `--help`. Unknown flags exit 2.
- **Ownership manifest.** Install records every link, copy, directory, settings.json creation and hook entry it creates in `~/.local/state/orca/install.manifest`. Uninstall and "never overwrite what we did not create" both read it. The same rules work in link mode (Linux, macOS, Git Bash with Developer Mode) and copy mode (Git Bash without it).
- **Never remove what Orca did not create.** An existing target that is not Orca's is reported and install stops before changing anything. `--force` moves such a target aside to `<target>.orca-bak-<UTC timestamp>`; it never deletes it. Targets the manifest records as Orca's from another checkout, and still unchanged, are replaced in place, not backed up.
- **settings.json written only on change.** Install writes the file only when the merged content differs, atomically and keeping its mode, and saves the original bytes once, only from a file Orca has not yet touched (mode 0600, like the rest of the state dir). A symlinked settings.json is written through, keeping the link. Uninstall restores them exactly when nobody edited the file since install. When the user edited it between installs, the saved original is dropped and uninstall removes Orca's hooks only. Other hooks are always kept.
- **Uninstall.** `./install.sh --uninstall` removes what the manifest says Orca created and is still unchanged, removes Orca's hook entries, restores or deletes settings.json, and lists every path it left in place with the reason, exiting 1 if there is any. A directory Orca created that still holds the user's files is kept and counts as left. It never uninstalls dependencies.
- **Update.** `git pull` in the install checkout, then `./install.sh` again. In copy mode this refreshes copies Orca still owns.
- **Tests.** `tests/install.test.sh` proves each acceptance criterion under a temporary HOME and a PATH that contains only the tools each test names, with stubs for everything external. Tests never touch the real HOME or install anything.
- **Docs.** README.md and docs/daily-use.md cover install, update, uninstall, the flags, both platforms' modes, and the manifest.

## Out of scope

- Package-manager distribution of Orca itself (per the issue).
- Uninstalling dependencies.
- Native Windows outside Git Bash (#37).
- A per-project setup step (`orca-lc init`, #10).

## Acceptance (from #16)

- [ ] Running install twice is a no-op: second run changes no file and no byte.
- [ ] Install then uninstall leaves `~/.claude/settings.json` byte-identical, with other hooks kept.
- [ ] A missing required tool exits non-zero and names the tool.
- [ ] `--no-optional`, and declining every prompt, install nothing.
- [ ] An existing file at a link target is reported, not removed.
- [ ] Verified on Linux (manual, by the user, including `bash tests/run.sh`, which proves link mode).
- [ ] Verified on WSL2 (manual, by the user, including `bash tests/run.sh`).

## Impact

- `install.sh` grows from about 25 lines to about 150 to 200 lines. It is one change in one PR.
- New: `tests/install.test.sh`. The harness (`tests/run.sh`, `tests/lib.sh`) comes from PR #49, which this PR builds on: on main when both have merged, otherwise stacked on `fix/test-harness` once #46 has merged (design.md, Test harness).
- Docs: README.md, docs/daily-use.md.
- Existing installs migrate on their first run under the new script (design.md, Migration).
