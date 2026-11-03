## 0. Base

- [x] 0.1 Work on top of `orca-64/work` (PR #125): `ORCA_TICKET` must already be lowercase in `stack_run`.

## 1. Examples

- [x] 1.1 Add `examples/stack/compose.yaml` per design.md "Sample compose file".
- [x] 1.2 Add `examples/stack/stack-up.sh` (executable), settings header and steps 1–8 per design.md "stack-up.sh".
- [x] 1.3 Add `examples/stack/stack-down.sh` (executable) per design.md "stack-down.sh".
- [x] 1.4 Both scripts pass `bash -n` and `shellcheck -S warning`, and use no GNU-only `sed`/`grep` flags (Git Bash and macOS portable).
- [x] 1.5 Add `examples/stack/README.md` covering:
  - copying both scripts into `scripts/`, keeping `orca.example.json`'s `stackUp`/`stackDown`;
  - the settings table, including `COMPOSE_PATH_SEPARATOR` on Windows;
  - Compose's automatic override file being kept when `COMPOSE_FILE` is unset;
  - the Compose ≥ 2.24.4 requirement;
  - the project name (`project` required) and volume naming;
  - that `stackDown` removes volumes;
  - the `${WEB_PORT:-80}:80` interpolation alternative for adopters who own their compose file.

## 2. Docs

- [x] 2.1 `README.md`, `stackUp` / `stackDown` row: append "Docker Compose examples in `examples/stack/`".
- [x] 2.2 `docs/daily-use.md`, the config paragraph that names `ports`, `stackUp` and `stackDown`: add that `examples/stack/` has compose scripts to copy.

## 3. Tests

- [x] 3.1 Add `tests/stack-example.test.sh` with the cases in design.md "Tests" (`orca-lc test-lock on` to create it, reason in the commit body, `test-lock off`).
- [x] 3.2 `tests/run.sh` and `orca-lc gate` pass.

## 4. Acceptance

- [x] 4.1 Run design.md "Manual verification" on native Linux with real Docker, and put the output in the PR body.
