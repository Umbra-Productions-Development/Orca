# Design: orca-lc init

## Context

Established facts:

- `cfgfile` reads `$(root)/.orca/config.json` (bin/orca-lc:36). `worktree up` links each worktree's `.orca` to `sharedDir`, falling back to `<main checkout>/.orca` (bin/orca-lc, `cmd_worktree up`). So the main checkout's file is the one every worktree reads.
- A `.orca/` ignore pattern matches directories only. The worktree's `.orca` is a symlink, so it shows as untracked (`?? .orca` in this repo's worktrees, whose `.gitignore` has `.orca/`). On the main checkout, `.orca` is a real directory, and `git check-ignore .orca` reports it ignored under `.orca/`.
- `test-affected` runs `testCommand` with the affected test files appended (bin/orca-lc, `cmd_test_affected`). A whole-suite command (`make test`, `cargo test`, `go test ./...`) breaks there.
- `ticket()` falls back to `[A-Z]+-[0-9]+` when `ticketPattern` is empty (bin/orca-lc:39).
- `testGlob` guards the test lock and `sourceGlob` steers searches to the code graph (hooks/pretool.sh); both are off when empty.
- Install may copy `orca-lc` instead of linking it (Git Bash without Developer Mode), so the installed `orca-lc` cannot count on `orca.example.json` sitting next to it.
- #116 (install.sh prompts) sets the prompt conventions: prompts only when `[ -t 0 ]`, no `CI` variable, EOF or a non-terminal declines, only `y`/`yes` accepts, and a test-only stdin override.
- `tests/help.test.sh` reads the dispatcher's command list, so it covers `init --help` with no edit.

## Command

`orca-lc init [--yes]`. `-h`/`--help` prints the USAGE line (existing dispatcher rule). Any other argument is a usage error (exit 2). Outside a git repository: `die "not in a repo"`.

USAGE line: `init [--yes]                     set up .orca/config.json (prompts; --yes accepts every proposal)`.

Target: `$(main_root)/.orca/config.json`, whichever worktree `init` runs from. `mkdir -p` the `.orca` dir only when writing.

## Defaults

One jq object in `orca-lc` (`init_defaults`) holds every key of `orca.example.json`, in the example's order, with these values:

| Key | Default |
|---|---|
| `project` | basename of `main_root` (always detected) |
| `sharedDir` | `<main_root>/.orca`, absolute; never prompted |
| `baseBranch` | `main` |
| `gate`, `testCommand`, `tracker`, `envCommand`, `stackUp`, `stackDown`, `migrateCommand` | `""` |
| `testGlob` | Languages, below |
| `sourceGlob` | Languages, below |
| `ticketPattern` | `[A-Z]+-[0-9]+` |
| `roles`, `portScheme`, `prShareLimit`, `stackTool`, `discoveriesDir`, `handoffArchiveDays` | the example's values |
| `reviewPasses` | `["security-review"]` |
| `envFiles` | `[".env"]` |
| `applyChecks`, `reviewChecks`, `linkPaths`, `ports` | `[]` |

None of the example's sample values (`myproj`, `ABC-[0-9]+`, npm/vitest commands, `./scripts/stack-*.sh`, `["web","db"]`, the `.tsx` reviewCheck) is ever proposed.

## Detection

Detection runs only for keys the existing config lacks (Rerun). It reads the main checkout and runs nothing from the project.

- **project**: basename of `main_root`.
- **baseBranch**: `git symbolic-ref --short refs/remotes/origin/HEAD`, minus `origin/`; else `main`.
- **ticketPattern**: local and remote-tracking branch names (`git for-each-ref refs/heads refs/remotes`, `origin/` stripped, `HEAD` skipped). Take the leading or `/`-separated token matching `[A-Za-z]+-?[0-9]+`, and count each distinct branch once per prefix (letters, uppercased). The most common prefix found on at least 2 branches gives `<PREFIX>-[0-9]+`; a tie goes to the alphabetically first. Otherwise, the default.
- **tracker**, first that applies:
  1. `origin` is a GitHub URL (`github.com[:/]<o>/<r>(.git)?`) and `gh api repos/<o>/<r> -q .has_issues` (through `ghx`) prints `true` → `GitHub Issues on <o>/<r>`, followed by `; ticket <P>-N is issue #N (gh issue view N)` when the settled `ticketPattern` is exactly `<P>-[0-9]+` with `<P>` a literal prefix, not the default. A gh failure (offline, logged out) skips this step silently.
  2. An MCP server whose name matches `jira|atlassian|linear` (case-insensitive), in `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json` (top-level `mcpServers`, and `projects["<main_root>"].mcpServers`) or `<main_root>/.mcp.json` (`mcpServers`) → `Jira via MCP server <name>` or `Linear via MCP server <name>`. With several, the first by name. Plugin-provided servers are not read.
  3. Else `""`.
  `ticketPattern` is prompted before `tracker`, so the tracker text uses the answered pattern.
- **testCommand**: only runners that take test file paths, first that applies:
  1. `package.json` lists `vitest` in dependencies or devDependencies → `npx vitest run`; else `jest` → `npx jest`.
  2. `pytest.ini`, `conftest.py`, a `[tool.pytest` table in `pyproject.toml`, or `pytest` in `requirements*.txt` → `pytest`.
  3. `tests/run.sh` exists → `bash tests/run.sh`.
  4. Else `""`.
- **gate**: whole-suite commands, first that applies:
  1. `Makefile` with a `test:` target → `make test`.
  2. Otherwise, join what is present with ` && `: the `package.json` scripts `lint`, `typecheck` and `test`, in that order, run with the package manager its lockfile names (`pnpm-lock.yaml` → `pnpm run <s>`, `yarn.lock` → `yarn <s>`, else `npm run <s>`, with `npm test` for `test`); `cargo test` when `Cargo.toml` exists; `go test ./...` when `go.mod` exists.
  3. Nothing from 1–2 → the detected `testCommand` (it runs the whole suite with no files).
  4. Else `""`.
  `testCommand` is prompted before `gate`, so step 3 uses the answered value.
- **stackUp/stackDown**: `scripts/stack-up.sh` / `scripts/stack-down.sh` when the file exists; else `""`.
- **ports**: no detection; `[]`.

### Languages (testGlob, sourceGlob)

Not prompted, written on the first run only (Rerun). Each language found contributes its pair; the pairs of every language found are joined with `|` in this table's order. Separators are matched as `[/\\]` so Windows paths match too.

| Marker | testGlob | sourceGlob |
|---|---|---|
| `tsconfig.json` | `\.test\.tsx?$` | `src/\|\.tsx?\b` |
| `package.json` without `tsconfig.json` | `\.(test\|spec)\.[cm]?jsx?$` | `\.[cm]?jsx?\b` |
| `pyproject.toml`, `setup.py` or `requirements*.txt` | `(^\|[/\\])test_[^/\\]*\.py$\|_test\.py$` | `\.py\b` |
| `go.mod` | `_test\.go$` | `\.go\b` |
| `Cargo.toml` | `(^\|[/\\])tests[/\\].*\.rs$` | `\.rs\b` |
| none of these | `(^\|[/\\])(tests?\|__tests__\|spec)[/\\]\|[._-](test\|spec)\.[^/\\]*$\|(^\|[/\\])test_[^/\\]*$` | `""` |

The TypeScript row is the example's own values.

## Prompts

Order: `project`, `baseBranch`, `ticketPattern`, `tracker`, `testCommand`, `gate`, `stackUp`, `stackDown`, `ports`.

- Prompt text: `<key> [<proposed>]: `, with `[]` when the proposal is empty. `ports` shows and reads names separated by spaces or commas.
- Input, trimmed: empty accepts the proposal; `-` sets `""` (`[]` for `ports`); anything else replaces it.
- EOF at a key prompt accepts the proposal.
- Prompts are read only when stdin is a terminal (`[ -t 0 ]`). **Test-only:** `ORCA_INIT_PROMPT_STDIN=1` reads answers from stdin even when it is not a terminal. It is named in a comment by `cmd_init` as test-only, and not in help, README or daily-use.md.
- With no terminal, no override and no `--yes`: no prompt is printed, every key takes its proposal, the confirmation is declined, and init exits 1 with `orca-lc: not a terminal; nothing written (orca-lc init --yes accepts every proposal)` on stderr.

## Output and confirmation

- The new config is the existing one (or `{}`) with the prompted keys set, then the missing keys from Defaults appended in the example's order. It is formatted with `jq --indent 2 .` and ends in a newline.
- `.gitignore` (in `main_root`) needs a change unless it holds a line that is exactly `.orca` or `/.orca`, whitespace trimmed. A `.orca/` line does not count; the new `.orca` line goes after it, and the existing line stays. The file is created when missing, and a missing final newline is added before appending. This replaces a `git check-ignore` test: on the main checkout, check-ignore reports the real `.orca` directory ignored under `.orca/`, which still misses the worktree symlinks (Context).
- Nothing changes (the config bytes are equal and `.gitignore` needs nothing): print `no changes`, exit 0, ask nothing, write nothing.
- Otherwise print the new config on stdout, plus `.gitignore: add .orca` when that applies, then ask `Write <path>? [y/N] `. Only `y` or `yes` (any case) writes; anything else, or EOF, prints `nothing written` and exits 1. `--yes` skips the question and writes.
- Writes: the config through a temp file in the same dir, then `mv`; `.gitignore` appended. Exit 0 with `wrote <path>`.
- An existing config that is not valid JSON: `die` naming the file, before any prompt; nothing written.

## Rerun

- A key present in the existing config is proposed with its current value, even when empty; detection runs only for missing keys. That keeps a rerun deterministic when the environment changes (gh offline, new branches), so accepting everything twice leaves the file byte-identical.
- Keys not prompted, unknown keys, and the existing key order are kept. Keys missing from an older config are appended with their defaults (`testGlob`/`sourceGlob` from Languages).

## Tests

`tests/init.test.sh`, on `new_repo` (its `.orca/config.json` removed where a test needs a fresh repo). Answers come through `ORCA_INIT_PROMPT_STDIN=1` with a here-string; every other run reads `/dev/null`. `HOME` is the harness's temp dir, so no real `~/.claude.json` is read.

1. Fresh repo, `--yes`: exit 0; the file passes `jq empty`; its keys equal `orca.example.json`'s keys in the same order; `sharedDir` = `<repo>/.orca`; `project` = repo dir name; `.gitignore` has `.orca`; no sample value from the example appears.
2. Interactive, Enter at every prompt and `y` → bytes equal to a `--yes` run on the same repo (config removed and `.gitignore` restored between the two).
3. Two `--yes` runs: the second prints `no changes`, and the file and `.gitignore` are byte-identical.
4. `-` at `ticketPattern`, with detection proposing a value → `""`. Typed input replaces the proposal.
5. stdin `/dev/null`, no `--yes`, no override: exit 1, no config file, `.gitignore` untouched, no prompt text on stdout.
6. `n` at the confirmation: exit 1, nothing written.
7. ticketPattern: branches `abc-1/x` and `abc-2/y` → `ABC-[0-9]+`; one such branch → `[A-Z]+-[0-9]+`.
8. JS/TS repo: `package.json` with `vitest` and scripts `lint`, `test`, plus `tsconfig.json` → `testCommand` `npx vitest run`, `gate` `npm run lint && npm test`, and the TypeScript globs. With `pnpm-lock.yaml` → `pnpm run lint && pnpm run test`.
9. `tests/run.sh` only → `testCommand` and `gate` both `bash tests/run.sh`; no-language `testGlob`, `sourceGlob` `""`.
10. `Makefile` with `test:` → `gate` `make test`.
11. Tracker: origin `git@github.com:o/r.git`, the gh stub answering `has_issues: true`, branches giving `ORCA-[0-9]+` → `GitHub Issues on o/r; ticket ORCA-N is issue #N (gh issue view N)`. The stub failing → `""`. A `.mcp.json` with a server `linear` → `Linear via MCP server linear`.
12. Run from a worktree made by `worktree up` → writes the main checkout's `.orca/config.json`.
13. Rerun keeps an unknown key, a hand-edited unprompted value and the key order. An older config missing `testGlob` gets it appended.
14. `.gitignore` holding `.orca/` → `.orca` added below it; holding `/.orca` → unchanged.
15. `origin/HEAD` set to `develop` → `baseBranch` `develop`.
16. An invalid JSON config → non-zero exit, file unchanged.
17. Unknown argument → exit 2.

`tests/stub/gh` (test-locked edit; the reason goes in the commit body): `api repos/<o>/<r>` prints `$GH_STUB/repo.json` filtered by `-q`, and exits 1 when that file is missing.

## Decisions

- Defaults live in `orca-lc` as one jq object; a test keeps its key set equal to `orca.example.json`'s — user (recommended, accepted).
- With nothing detected, keys fall back to generic working values (`ticketPattern` `[A-Z]+-[0-9]+`, a language-neutral `testGlob`), with `testGlob`/`sourceGlob` derived from the languages detected; the example's sample values are never proposed — user (option c, chosen after the sample values were listed key by key).
- The first run writes every key; a rerun keeps unprompted and unknown keys and their order, appending new keys in the example's order — user (recommended, accepted).
- `sharedDir` is not prompted: it is the main checkout's `.orca`, absolute; `init` always writes `<main checkout>/.orca/config.json` — user (recommended, accepted).
- `.gitignore` gets `.orca`, not `.orca/`, so worktree symlinks are ignored too — user (recommended, accepted). Testing the existing ignore with a line match instead of `git check-ignore`, because check-ignore reports the main checkout's real directory as ignored under `.orca/` — propose, from the Context fact, within the user's intent.
- With no terminal and no `--yes`, nothing is written and init exits 1; `[ -t 0 ]` is the whole rule; `ORCA_INIT_PROMPT_STDIN=1` is test-only, as in #116 — user (recommended, accepted).
- Confirmation is `[y/N]`, only `y`/`yes` writes; a rerun with no change prints `no changes` and asks nothing — user (recommended, accepted).
- `testCommand` proposes only runners that take file paths; whole-suite commands go to `gate` — user (recommended, accepted).
- Tracker detection: GitHub origin with issues enabled, then a `jira|atlassian|linear` MCP server, then empty; `--yes` detects the same way — user (recommended, accepted).
- `ticketPattern` is inferred from the most common prefix on at least 2 branches — user (recommended, accepted).
- Docs in this change: `orca-lc help`, README, daily-use.md; install.sh's closing line waits for #116 — user (recommended, accepted).
- A rerun proposes current values even when empty and detects only missing keys, so reruns are deterministic — propose, from #10's "re-running proposes the current values" and its byte-identical criterion.
- EOF at a key prompt accepts the proposal; EOF at the confirmation declines — propose, consistent with the user's `[y/N]` decision.

## Follow-ups (sent to the orchestrator)

- Orca's own `.gitignore` has `.orca/`, so every worktree shows `?? .orca`; change it to `.orca` and the README Quickstart line to match (that README line is replaced by this change anyway).
- install.sh's closing `per project: copy orca.example.json to <repo>/.orca/config.json` becomes `per project: orca-lc init` once #116 merges.
- #124 (v0.3): once `trackerConventions` exists, `init` may prompt for it.

## Risks

- Detection reads the network once (`gh api`) when origin is on GitHub. It is skipped silently on failure, so an offline `--yes` writes an empty `tracker`, and a later rerun keeps it empty (Rerun). The user types the value or edits the file.
- Language globs are heuristics; a monorepo with several languages gets the union. They are printed before the confirmation, and a rerun never overwrites a hand-edited value.
