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
- Passing `-f` turns off Compose's own file lookup: both the base names (`compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml`) and the automatic override (`compose.override.yaml`, `compose.override.yml`, `docker-compose.override.yaml`, `docker-compose.override.yml`).
- `stack_run` runs `bash -c` with the user's whole environment, so unrelated `*_PORT` variables (from direnv, Kubernetes, the shell) are present too. Orca's own ports are the `^[A-Z0-9_]+_PORT=` lines of `$ORCA_WORKTREE/.env.local`, which `worktree up` writes whenever `ports` is configured and which `stack_ports` reads.
- `docker run -v <name>:/from` silently creates a missing named volume, so a misspelt seed volume copies nothing and exits 0.
- `project` is optional in `.orca/config.json`; `orca-lc config project` prints nothing when it is unset.
- `docker compose version --short` prints e.g. `2.24.4`, `v2.24.4`, `2.24.4-desktop.1` or `5.6.0`. Compose splits `COMPOSE_FILE` on `COMPOSE_PATH_SEPARATOR`, whose default is `:` (`;` on Windows).

## Settings

Both scripts open with a header of settings, each read from the environment with a default (`: "${ORCA_PORT_MAP:=...}"`). The adopter edits the header in their copy or sets values as prefixes in the `stackUp` command.

| Setting | Meaning | Default in the example |
|---|---|---|
| `ORCA_PORT_MAP` | Space-separated `VAR=service:containerPort` entries | `WEB_PORT=web:80 API_PORT=api:8080` (matches the sample compose file) |
| `COMPOSE_FILE` | Base compose file(s), split on `${COMPOSE_PATH_SEPARATOR:-:}` as Compose does (set `COMPOSE_PATH_SEPARATOR=';'` on Windows when the paths are absolute) | unset: Compose's own lookup in `$ORCA_WORKTREE`, base file plus its automatic override file |
| `SEED_VOLUME` | Named volume holding seed data | unset: no seeding |
| `SEED_TARGET` | Volume key in the compose file the seed fills | unset |

## stack-up.sh

In order, `set -euo pipefail`, every failure message on stderr and naming the setting to fix:

1. **Version**: `docker compose version --short`, with a leading `v` and any `-suffix` stripped, split on `.` into three integers and compared field by field in bash arithmetic (no `sort -V`, which macOS lacks). It must be ≥ 2.24.4, else fail: `docker compose <ver> is older than 2.24.4, which ports: !override needs; upgrade Docker Compose`. `5.6.0` and `2.24.4-desktop.1` pass; `2.24.3` and `2.9.0` fail.
2. **Project name**: `$(orca-lc config project)`, lowercased, every character outside `[a-z0-9_-]` replaced by `-`, leading `-` and `_` stripped (Compose names must start with a letter or digit; nothing left fails), then `-$ORCA_TICKET`. The ticket is used as given; the script never changes its case. When `project` is unset (empty output), fail: `set project in .orca/config.json; it names the compose project`.
3. **Compose files**: when `COMPOSE_FILE` is set, its entries split on `${COMPOSE_PATH_SEPARATOR:-:}`, in order. Otherwise, as Compose does: the first existing of `compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml` in `$ORCA_WORKTREE` (none found: fail), then the first existing of `compose.override.yaml`, `compose.override.yml`, `docker-compose.override.yaml`, `docker-compose.override.yml`, when there is one. The generated override always comes last.
4. **Port map check**: the required names are the `^[A-Z0-9_]+_PORT=` lines of `$ORCA_WORKTREE/.env.local` (none when it is absent), not every `*_PORT` in the environment. Each needs an `ORCA_PORT_MAP` entry, and every entry's variable must be set. Either gap fails and names the variable. Other `*_PORT` variables in the environment are ignored.
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
6. **Seed** (only when `SEED_VOLUME` is set; `SEED_TARGET` unset then fails): the ticket volume is `<project-name>_<SEED_TARGET>`, the name Compose gives a named volume. When `docker volume inspect` finds it, skip. Otherwise:
   - `docker volume inspect "$SEED_VOLUME"` must succeed, else fail naming `SEED_VOLUME`. This check runs before anything is created, because `docker run -v` would silently create an empty seed volume.
   - `docker volume create` the ticket volume with the labels Compose sets (`com.docker.compose.project=<project-name>`, `com.docker.compose.volume=<SEED_TARGET>`), so `up` adopts it without a warning and `down -v` removes it.
   - `docker run --rm -v "$SEED_VOLUME":/from:ro -v <ticket volume>:/to alpine:3.20 cp -a /from/. /to/`. If it fails, `docker volume rm` the ticket volume and then fail. A retry then seeds again instead of skipping a half-copied volume.
   - An existing ticket volume is never overwritten.
7. **Up**: `docker compose -p <project-name> -f <file>... -f <override> up -d --wait`, the files from step 3 in order.
8. Print one line: `stack <project-name> up; override <path>`.

## stack-down.sh

- Project name built the same way (step 2), including the failure when `project` is unset.
- `docker compose -p <project-name> down -v --remove-orphans`. No compose file or override is needed, and no version check is run.
- The two scripts are standalone copies; neither sources the other, so an adopter can copy either one alone. The project-name code is duplicated (three lines).

## Sample compose file

`examples/stack/compose.yaml`: services `web` (busybox `httpd -f -p 80`, published `80:80`) and `api` (busybox `httpd -f -p 8080`, published `8080:8080`), plus one named volume `data` mounted in `api`, so the seed path has a target. The base host ports are deliberately fixed: the run shows that the override replaces them.

## Tests

`tests/stack-example.test.sh`, run by `tests/run.sh`, no Docker needed:

- A stub `docker` in `$TMPDIR/bin` logs its arguments to a file. It answers `compose version --short` with a version taken from an env var (default `2.29.0`). It answers `volume inspect <name>` with exit 0 only for the names listed in an env var. It fails `run` when an env var asks it to.
- A repo from `new_repo '{"project":"My.Proj","gate":"true"}'` with `compose.yaml` copied from the examples, and a `.env.local` holding `WEB_PORT=3010` and `API_PORT=3011`. The scripts are run directly with `ORCA_TICKET=abc-1 ORCA_WORKTREE=<repo>`, and those ports exported. Each case unsets `COMPOSE_FILE` and `COMPOSE_PATH_SEPARATOR` unless the case sets them itself.
- Cases:
  - Up: the log has `compose -p my-proj-abc-1 -f <repo>/compose.yaml -f <override> up -d --wait`. The override file sits under the repo's git dir and holds `"3010:80"` under `web` and `"3011:8080"` under `api`, each with `ports: !override`. `git status --porcelain` is empty.
  - Up with an unrelated `FOO_PORT=1` exported and not in `.env.local`: succeeds.
  - Up with a `compose.override.yaml` in the repo: the log has `-f <repo>/compose.yaml -f <repo>/compose.override.yaml -f <override>`, in that order.
  - `COMPOSE_FILE=a.yaml:b.yaml` (both present): both passed with `-f`, in order. The automatic override is not added.
  - Versions: `5.6.0` and `2.24.4-desktop.1` pass. `2.24.3` and `2.9.0` exit non-zero, with a message naming 2.24.4 and no `up` in the log.
  - An extra `DB_PORT=3012` line in `.env.local` with no map entry: fails naming `DB_PORT`. A map entry whose variable is unset: fails naming it.
  - No compose file and no `COMPOSE_FILE`: fails.
  - `project` unset in the config: up and down both fail naming `project`, and nothing reaches the log.
  - `SEED_VOLUME=seed SEED_TARGET=data`, with `seed` present and the ticket volume missing: the log has `volume create` with both labels for `my-proj-abc-1_data`, then `run --rm ... alpine:3.20 cp -a`. With the ticket volume present: neither appears.
  - `SEED_VOLUME=seed` with `seed` missing: fails naming `SEED_VOLUME`; no `volume create` and no `run` in the log.
  - Seed copy fails (stub `run` exits 1): the script exits non-zero and the log has `volume rm my-proj-abc-1_data` after the `run`.
  - Down: the log has `compose -p my-proj-abc-1 down -v --remove-orphans`.

The scripts stay separate from the test's scope: `tests/` gains one file, and `examples/` is read from `$ORCA_SRC`.

## Manual verification (acceptance)

On native Linux with real Docker (Linux only; WSL2 is no longer verified): in a scratch repo carrying `examples/stack/` copied into `scripts/` and `compose.yaml` at the root, with `ports: ["web","api"]` and the example `stackUp`/`stackDown`. `orca-lc worktree up ABC-1 --stack` and `orca-lc worktree up ABC-2 --stack` both come up. `curl` reaches each ticket's `WEB_PORT` and `API_PORT`, and `docker compose ls` shows `<project>-abc-1` and `<project>-abc-2`. Then `orca-lc worktree down ABC-1 --force` leaves no `<project>-abc-1` containers or volumes, and ABC-2 is still running. Record the output in the PR.

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
- The ports the map must cover are the `*_PORT` lines of `$ORCA_WORKTREE/.env.local`, not every `*_PORT` in the environment. This narrows the "unmapped port fails" decision to Orca's own ports. — propose, per proposal review should-fix 1
- Without `COMPOSE_FILE`, Compose's lookup includes its automatic override file (`compose.override.yaml` and the other three names), added after the base file. This completes the "Compose's own lookup order" decision. — propose, per proposal review should-fix 2
- A missing `SEED_VOLUME` fails before anything is created, and a failed copy removes the ticket volume, so a retry seeds again. This keeps the "seed once, never overwrite" decision. — propose, per proposal review should-fix 3
- The version is compared as three integers in bash, after stripping a leading `v` and any `-suffix`, with no `sort -V`. — propose, per proposal review suggestion 1
- When `project` is unset, both scripts fail and name it. They do not fall back to a directory name, since a fallback would bring back the `<basename>` option the user turned down for the project name. — propose, per proposal review suggestion 2
- `COMPOSE_FILE` is split on `${COMPOSE_PATH_SEPARATOR:-:}`, as Compose splits it. — propose, per proposal review suggestion 3
- The change carries `.openspec.yaml` with `skip_specs: true`: it adds examples and docs, and Orca's own behaviour does not change. — propose, per proposal review suggestion 4

## Risks

- `--wait` fails when a service has a healthcheck that never passes. Then `worktree up` reports `stackUp failed` with its retry and tear-down lines. That is the correct outcome, not a script bug.
- Labelling the seeded volume relies on Compose's label names (`com.docker.compose.project`, `com.docker.compose.volume`). If Compose changes them, `up` would warn that the volume was not created by Compose, and use it anyway.
- A project that worked around the uppercase `ORCA_TICKET` before #64 has stacks under another name. They need a one-time `docker compose -p <old> down` (#64's migration note). These examples start fresh.
