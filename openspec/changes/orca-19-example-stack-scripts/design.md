# Design: example stack scripts for per-ticket compose stacks

## Context

Established facts:

- `stack_run` (bin/orca-lc, `stack_run()`) runs `stackUp`, `migrateCommand` and `stackDown` from the worktree with `bash -c`. It exports only `ORCA_TICKET`, `ORCA_WORKTREE`, and the `*_PORT` lines of the worktree's `.env.local` (from `ports_for` the first time; hand edits there win).
- After #64 (PR #125), `ORCA_TICKET` is the lowercase canonical ticket id (`abc-1`), whatever case the user typed.
- `worktree up --stack` runs `migrateCommand` right after `stackUp` returns.
- `stack_check` accepts `VAR=value` prefixes before the command in `stackUp`, so `SEED_VOLUME=x ./scripts/stack-up.sh` passes its check.
- `orca.example.json` already sets `stackUp: ./scripts/stack-up.sh` and `stackDown: ./scripts/stack-down.sh`.
- In a compose override file, a service's `ports` list is merged with the base file's list, not swapped in, so the base host port would still be published and clash between tickets. `ports: !override` replaces the list. It needs Docker Compose ≥ 2.24.4.
- Compose project names must be lowercase alphanumerics, `-` and `_`, starting with a letter or digit.
- Passing `-f` turns off Compose's own file lookup (`compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml`).

## Settings

Both scripts open with a header of settings, each read from the environment with a default (`: "${ORCA_PORT_MAP:=...}"`). The adopter edits the header in their copy or sets values as prefixes in the `stackUp` command.

| Setting | Meaning | Default in the example |
|---|---|---|
| `ORCA_PORT_MAP` | Space-separated `VAR=service:containerPort` entries | `WEB_PORT=web:80 API_PORT=api:8080` (matches the sample compose file) |
| `COMPOSE_FILE` | Base compose file(s), `:`-separated, as Compose reads it | unset: first of Compose's four names found in `$ORCA_WORKTREE` |
| `SEED_VOLUME` | Named volume holding seed data | unset: no seeding |
| `SEED_TARGET` | Volume key in the compose file the seed fills | unset |

## stack-up.sh

In order, `set -euo pipefail`, every failure message on stderr and naming the setting to fix:

1. **Version**: `docker compose version --short` (leading `v` stripped) must be ≥ 2.24.4, else fail: `docker compose <ver> is older than 2.24.4, which ports: !override needs; upgrade Docker Compose`.
2. **Project name**: `$(orca-lc config project)`, lowercased, every character outside `[a-z0-9_-]` replaced by `-`, then `-$ORCA_TICKET`. The ticket is used as given; the script never changes its case.
3. **Base file**: each entry of `COMPOSE_FILE` when set; otherwise the first existing of `compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml` in `$ORCA_WORKTREE`. None found: fail.
4. **Port map check**: every exported `*_PORT` variable (`compgen -v | grep '_PORT$'`) needs an `ORCA_PORT_MAP` entry, and every entry's variable must be set. Either gap fails and names the variable.
5. **Override file**: written to `$(git -C "$ORCA_WORKTREE" rev-parse --git-path orca-compose.override.yaml)`, made absolute. Entries are grouped by service, one `ports: !override` per service, in map order:

   ```yaml
   services:
     web:
       ports: !override
         - "3010:80"
     api:
       ports: !override
         - "3011:8080"
   ```

   Regenerated on every run.
6. **Seed** (only when `SEED_VOLUME` is set; `SEED_TARGET` unset then fails): the ticket volume is `<project-name>_<SEED_TARGET>`, the name Compose gives a named volume. When `docker volume inspect` finds it, skip. Otherwise `docker volume create` it with the labels Compose sets (`com.docker.compose.project=<project-name>`, `com.docker.compose.volume=<SEED_TARGET>`), so `up` adopts it without a warning and `down -v` removes it. Then run `docker run --rm -v "$SEED_VOLUME":/from:ro -v <ticket volume>:/to alpine:3.20 cp -a /from/. /to/`. An existing ticket volume is never overwritten.
7. **Up**: `docker compose -p <project-name> -f <base>... -f <override> up -d --wait`.
8. Print one line: `stack <project-name> up; override <path>`.

## stack-down.sh

- Project name built the same way (step 2).
- `docker compose -p <project-name> down -v --remove-orphans`. No compose file or override is needed, and no version check is run.
- The two scripts are standalone copies; neither sources the other, so an adopter can copy either one alone. The project-name code is duplicated (three lines).

## Sample compose file

`examples/stack/compose.yaml`: services `web` (busybox `httpd -f -p 80`, published `80:80`) and `api` (busybox `httpd -f -p 8080`, published `8080:8080`), plus one named volume `data` mounted in `api`, so the seed path has a target. The base host ports are deliberately fixed: the run shows that the override replaces them.

## Tests

`tests/stack-example.test.sh`, run by `tests/run.sh`, no Docker needed:

- A stub `docker` in `$TMPDIR/bin` logs its arguments to a file. It answers `compose version --short` with a version taken from an env var (default `2.29.0`), and `volume inspect` with exit 0 or 1 from an env var.
- A repo from `new_repo '{"project":"My.Proj","gate":"true"}'` with `compose.yaml` copied from the examples. The scripts are run directly with `ORCA_TICKET=abc-1 ORCA_WORKTREE=<repo> WEB_PORT=3010 API_PORT=3011`.
- Cases:
  - Up: the log has `compose -p my-proj-abc-1 -f <repo>/compose.yaml -f <override> up -d --wait`. The override file sits under the repo's git dir and holds `"3010:80"` under `web` and `"3011:8080"` under `api`, each with `ports: !override`. `git status --porcelain` is empty.
  - Version `2.24.3`: exit non-zero, message names 2.24.4, no `up` in the log.
  - An extra `DB_PORT=3012` with no map entry: fails naming `DB_PORT`. A map entry whose variable is unset: fails naming it.
  - No compose file and no `COMPOSE_FILE`: fails.
  - `SEED_VOLUME=seed SEED_TARGET=data` with the volume missing: the log has `volume create` with both labels for `my-proj-abc-1_data`, then `run --rm ... alpine:3.20 cp -a`. With the volume present: neither appears.
  - Down: the log has `compose -p my-proj-abc-1 down -v --remove-orphans`.

The scripts stay separate from the test's scope: `tests/` gains one file, and `examples/` is read from `$ORCA_SRC`.

## Manual verification (acceptance)

On native Linux with real Docker (this counts for the WSL2 box too): in a scratch repo carrying `examples/stack/` copied into `scripts/` and `compose.yaml` at the root, with `ports: ["web","api"]` and the example `stackUp`/`stackDown`. `orca-lc worktree up ABC-1 --stack` and `orca-lc worktree up ABC-2 --stack` both come up. `curl` reaches each ticket's `WEB_PORT` and `API_PORT`, and `docker compose ls` shows `<project>-abc-1` and `<project>-abc-2`. Then `orca-lc worktree down ABC-1 --force` leaves no `<project>-abc-1` containers or volumes, and ABC-2 is still running. Record the output in the PR.

## Decisions

- `ORCA_TICKET` is the lowercase canonical id from #64 (PR #125). The scripts never lowercase it. ORCA-19's PR is stacked on `orca-64/work` and retargeted to `main` after #125 merges. Apply builds on `orca-64/work`. — user
- Ports reach Compose through a generated override file with `ports: !override`, so the adopter's compose file stays untouched. The README names `${WEB_PORT}` interpolation as the simpler alternative. — user (recommended, accepted)
- The compose project name is `orca-lc config project`, lowercased and cleaned, followed by `-<ORCA_TICKET>`. — user (recommended, accepted)
- The seed volume is optional, used when `SEED_VOLUME` and `SEED_TARGET` are set. It is copied once into `<project>_<SEED_TARGET>` and never overwrites an existing volume. — user (recommended, accepted)
- stack-down runs `down -v --remove-orphans`: the ticket's volumes go with it. — user (recommended, accepted)
- The change ships a sample `examples/stack/compose.yaml` and a stub-docker test, `tests/stack-example.test.sh`. One manual real-Docker run on Linux satisfies the Linux and WSL2 boxes. — user (recommended, accepted)
- The scripts are referenced from `examples/stack/README.md`, the `README.md` `stackUp`/`stackDown` row and `docs/daily-use.md`. `orca.example.json` is unchanged, and the getting-started docs are left to #20. — user (recommended, accepted)
- Port mapping comes from an explicit `ORCA_PORT_MAP` of `VAR=service:containerPort`. An unmapped `*_PORT`, or a mapped variable that is unset, fails by name. — user (recommended, accepted)
- Settings are environment variables with defaults in the script header, and can be set as prefixes in the `stackUp` command. No new Orca config key. — user (recommended, accepted)
- The base compose file is `COMPOSE_FILE` when set, else Compose's own lookup order. The script fails when none is found. — user (recommended, accepted)
- The override file is written to `git rev-parse --git-path orca-compose.override.yaml`. — user (recommended, accepted)
- stack-up runs `up -d --wait`, so `migrateCommand` meets running services. — user (recommended, accepted)
- stack-up fails clearly below Compose 2.24.4. — user (recommended, accepted)
- The seed copy uses `alpine:3.20`. — user (recommended, accepted)

## Risks

- `--wait` fails when a service has a healthcheck that never passes. Then `worktree up` reports `stackUp failed` with its retry and tear-down lines. That is the correct outcome, not a script bug.
- Labelling the seeded volume relies on Compose's label names (`com.docker.compose.project`, `com.docker.compose.volume`). If Compose changes them, `up` would warn that the volume was not created by Compose, and use it anyway.
- A project that worked around the uppercase `ORCA_TICKET` before #64 has stacks under another name. They need a one-time `docker compose -p <old> down` (#64's migration note). These examples start fresh.
