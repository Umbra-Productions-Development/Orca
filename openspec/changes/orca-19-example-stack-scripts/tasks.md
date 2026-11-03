## 0. Base

- [ ] 0.1 Work on top of `orca-64/work` (PR #125): `ORCA_TICKET` must already be lowercase in `stack_run`.

## 1. Examples

- [ ] 1.1 Add `examples/stack/compose.yaml` per design.md "Sample compose file".
- [ ] 1.2 Add `examples/stack/stack-up.sh` (executable), settings header and steps 1–8 per design.md "stack-up.sh".
- [ ] 1.3 Add `examples/stack/stack-down.sh` (executable) per design.md "stack-down.sh".
- [ ] 1.4 Both scripts pass `bash -n` and `shellcheck -S warning`, and use no GNU-only `sed`/`grep` flags (Git Bash and macOS portable).
- [ ] 1.5 Add `examples/stack/README.md`: copy both scripts into `scripts/` and keep `orca.example.json`'s `stackUp`/`stackDown`; the settings table; the Compose ≥ 2.24.4 requirement; the project and volume naming; that `stackDown` removes volumes; the `${WEB_PORT:-80}:80` interpolation alternative for adopters who own their compose file.

## 2. Docs

- [ ] 2.1 `README.md`, `stackUp` / `stackDown` row: append "Docker Compose examples in `examples/stack/`".
- [ ] 2.2 `docs/daily-use.md`, the config paragraph that names `ports`, `stackUp` and `stackDown`: add that `examples/stack/` has compose scripts to copy.

## 3. Tests

- [ ] 3.1 Add `tests/stack-example.test.sh` with the cases in design.md "Tests" (`orca-lc test-lock on` to create it, reason in the commit body, `test-lock off`).
- [ ] 3.2 `tests/run.sh` and `orca-lc gate` pass.

## 4. Acceptance

- [ ] 4.1 Run design.md "Manual verification" on native Linux with real Docker (covers Linux and WSL2), and put the output in the PR body.
