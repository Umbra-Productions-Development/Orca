## Why

install.sh still ends with `per project: copy orca.example.json to <repo>/.orca/config.json` (`install.sh`, last line). Since #10, `orca-lc init` writes that file, proposing values from the repository, and the README Quickstart and `docs/daily-use.md` "Setup, once per project" already say to run it. A copied example carries sample values (`myproj`, `ABC-[0-9]+`, `npx vitest run`) that are wrong until each one is replaced by hand (issue #128, found while proposing ORCA-10; orca-10's design.md lists it as a follow-up).

## What Changes

- install.sh's closing line becomes `per project: run orca-lc init in the repository`.
- `tests/install.test.sh` case 5.7 (`t_fail_installer`), which today checks only that the last line contains `per project:`, asserts the last line contains `orca-lc init` and does not contain `orca.example.json`.

## Impact

- Code: `install.sh` (one line). Tests: `tests/install.test.sh` (one assert, needs the test lock).
- Checked and unchanged: `README.md` (Quickstart and Configuration already name `orca-lc init`; `orca.example.json` stays the key reference), `docs/daily-use.md` (Setup already runs `orca-lc init`), `skills/`, `agents/`, `orca-lc help`, `examples/stack/README.md` (its `orca.example.json` mention is about `stackUp`/`stackDown` values, not setup). Archived/merged change docs (`orca-16-install-lifecycle` task 2.8, `orca-10-init`) are history and stay as written.
- No command, flag or config key changes; no spec delta (`openspec/specs` does not exist yet, #62).
