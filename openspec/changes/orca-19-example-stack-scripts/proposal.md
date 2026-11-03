## Why

`stackUp` and `stackDown` run whatever the project names, but Orca ships no working example, so every adopter writes per-ticket stack scripts from zero (issue #19). The common case is docker compose. The hard parts are naming the compose project per ticket, publishing the ticket's `*_PORT` values without editing the adopter's compose file, and seeding data once per ticket. Each adopter gets them wrong in its own way.

## What Changes

- New `examples/stack/stack-up.sh`: names the compose project `<project>-<ORCA_TICKET>`, writes a generated override file that replaces each mapped service's `ports` with the ticket's ports (`ports: !override`), optionally copies a seed volume into the ticket's volume once, and runs `docker compose up -d --wait`.
- New `examples/stack/stack-down.sh`: `docker compose -p <project>-<ORCA_TICKET> down -v --remove-orphans`.
- New `examples/stack/compose.yaml`: a two-service sample (`web`, `api`, busybox httpd) the scripts run against as given.
- New `examples/stack/README.md`: how to copy the scripts into `scripts/`, every setting (`ORCA_PORT_MAP`, `COMPOSE_FILE`, `SEED_VOLUME`, `SEED_TARGET`), the Compose ≥ 2.24.4 requirement, and the simpler `${WEB_PORT}` interpolation alternative.
- `README.md` (`stackUp` / `stackDown` row) and `docs/daily-use.md` (config paragraph) point at `examples/stack/`.
- New `tests/stack-example.test.sh`: runs both scripts against a stub `docker` and checks the commands and the override file.
- No change to `bin/orca-lc`, to `orca.example.json` (its `./scripts/stack-up.sh` / `./scripts/stack-down.sh` already match where adopters copy the scripts), and no new config key.

## Dependency

The scripts rely on `ORCA_TICKET` being the lowercase canonical ticket id, which #64 delivers in PR #125 (https://github.com/Umbra-Productions-Development/Orca/pull/125). ORCA-19's PR is stacked on #125 with base `orca-64/work` and retargeted to `main` once #125 merges. Apply builds on `orca-64/work` and does not wait for the merge.

## Impact

- New files only, under `examples/stack/` and `tests/`. Docs: `README.md`, `docs/daily-use.md`.
- Adopters: nothing changes until they copy the scripts. The scripts need docker with Compose ≥ 2.24.4, git, and `orca-lc` on PATH.
- #20 (getting started) will link these examples. That work stays in #20.
- Out of scope: stacks that are not compose (per the ticket), and adding `examples/stack/*.sh` to this repo's gate shellcheck list, which lives in the untracked `.orca/config.json` (sent to the orchestrator as a follow-up).
