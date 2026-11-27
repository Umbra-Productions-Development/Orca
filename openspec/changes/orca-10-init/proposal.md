## Why

Every project starts by copying `orca.example.json` to `.orca/config.json` and editing it by hand (README Quickstart, docs/daily-use.md). The example's values are samples for a fictional TypeScript/npm project (`myproj`, `ABC-[0-9]+`, `npx vitest run`, `./scripts/stack-up.sh`), so a copied config is wrong until every one is replaced. `tracker` must be set by hand, and sessions ask the user for it whenever it is empty, in every project. The README's `.orca/` ignore line also misses the `.orca` symlink that `worktree up` puts in each worktree, so every worktree shows `?? .orca` (issue #10). #79 (setup prompt) needs a command that writes the config.

## What Changes

- New `orca-lc init [--yes]`, run anywhere in a repository. It writes `<main checkout>/.orca/config.json` and adds `.orca` to `.gitignore`.
- It prompts one key at a time for `project`, `baseBranch`, `ticketPattern`, `tracker`, `testCommand`, `gate`, `stackUp`, `stackDown` and `ports`. Each prompt shows a proposed value: Enter accepts it, typed input replaces it, and `-` leaves the key empty.
- Proposed values are detected from the repository: the repo name, `origin/HEAD`, branch names, the GitHub remote or the MCP servers in the Claude config, the test runners and build files. When detection finds nothing, a key falls back to a neutral or generic value, never to the example's sample.
- Keys that are not prompted are written on the first run. `testGlob` and `sourceGlob` are derived from the languages detected; the rest take the defaults built into `orca-lc`. A rerun keeps them as they are.
- It prints the resulting config and the `.gitignore` change, and writes only after a `[y/N]` confirmation. A rerun that changes nothing prints `no changes` and writes nothing.
- `--yes`: no prompts and no confirmation; every proposed value is accepted. With no terminal and no `--yes`, it writes nothing and exits 1.
- A rerun proposes the current values, so it doubles as the edit flow.
- Docs: `orca-lc help`, README (Quickstart and Configuration) and docs/daily-use.md describe `init` instead of copying the example.
- Tests: new `tests/init.test.sh`; `tests/stub/gh` answers `gh api repos/<o>/<r>`.

## Impact

- Code: `bin/orca-lc` (new `cmd_init` and its detection helpers, a defaults object, the dispatcher and USAGE). Docs: `README.md`, `docs/daily-use.md`. Tests: `tests/init.test.sh` (new), `tests/stub/gh` (test-locked edit).
- Existing configs: untouched until `init` is run. A rerun keeps every key and value it does not prompt for, and unknown keys too.
- `orca.example.json` stays the documented reference. A test keeps its key set equal to the defaults built into `orca-lc`.
- Out of scope: creating tickets or configuring the tracker itself (#10); install.sh's closing `per project: copy orca.example.json…` line, which #116 rewrites (follow-up); `trackerConventions` (#124, v0.3), which `init` could prompt for once it exists (follow-up); getting-started.md, owned by #20 and stacked on this change.
