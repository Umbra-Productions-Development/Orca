# Per-ticket docker compose stacks

`stack-up.sh` and `stack-down.sh` give each ticket its own compose stack: its own project name, its own published ports, and optionally its own copy of a seed volume. `compose.yaml` is a two-service sample (`web`, `api`) they run against as given.

## Use them

1. Copy both scripts into your project's `scripts/`:

   ```sh
   mkdir -p scripts && cp examples/stack/stack-up.sh examples/stack/stack-down.sh scripts/
   ```

2. Keep `stackUp` and `stackDown` as `orca.example.json` has them, and list your ports:

   ```json
   "project": "myapp",
   "ports": ["web", "api"],
   "stackUp": "./scripts/stack-up.sh",
   "stackDown": "./scripts/stack-down.sh"
   ```

3. Set `ORCA_PORT_MAP` in the header of your copy of `stack-up.sh` to match your compose services.

Requirements: docker with **Compose 2.24.4 or newer** (the override uses `ports: !override`), git, and `orca-lc` on PATH. `stack-up.sh` fails with a clear message on an older Compose.

## Settings

Each setting is read from the environment, with a default in the script header. Edit the header in your copy, or set a value as a prefix in `stackUp`, e.g. `"stackUp": "SEED_VOLUME=myapp-seed SEED_TARGET=db ./scripts/stack-up.sh"`.

| Setting | Meaning | Default |
|---|---|---|
| `ORCA_PORT_MAP` | Space-separated `VAR=service:containerPort` entries. Every `*_PORT` line in the worktree's `.env.local` needs one; a missing entry, or an entry whose variable is unset, fails by name. Other `*_PORT` variables in your environment are ignored. | `WEB_PORT=web:80 API_PORT=api:8080` |
| `COMPOSE_FILE` | Base compose file(s), split on `COMPOSE_PATH_SEPARATOR` (default `:`) as Compose does. On Windows with absolute paths, also set `COMPOSE_PATH_SEPARATOR=';'`. | unset: Compose's own lookup |
| `SEED_VOLUME` | Named volume holding seed data. | unset: no seeding |
| `SEED_TARGET` | The volume key in your compose file the seed fills. Required with `SEED_VOLUME`. | unset |

With `COMPOSE_FILE` unset, the script looks up files as Compose does: the first of `compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml` in the worktree, then the automatic override file (`compose.override.yaml` and its three other names) when there is one. Passing `-f` would otherwise switch that override off, so the script keeps it. With `COMPOSE_FILE` set, only its files are used.

## What it names

- Compose project: `project` from `.orca/config.json`, lowercased, characters outside `a-z0-9_-` replaced by `-`, leading `-` and `_` dropped (Compose names start with a letter or digit), then `-<ticket>`: `myapp-abc-12`. `project` is required; both scripts fail without it.
- Volumes: Compose names a named volume `<project-name>_<key>`, so the ticket's `data` volume is `myapp-abc-12_data`.
- Ports: a generated override file under the worktree's git dir (`git rev-parse --git-path orca-compose.override.yaml`) replaces each mapped service's `ports` with the ticket's. Your compose file stays untouched and nothing appears in `git status`.

## Seeding

With `SEED_VOLUME` and `SEED_TARGET` set, the first `stack-up.sh` for a ticket copies `SEED_VOLUME` into `<project-name>_<SEED_TARGET>` (with `alpine:3.20`) before `up`. A ticket volume that already exists is never overwritten. A missing `SEED_VOLUME` fails before anything is created, and a failed copy removes the half-filled volume so the next run seeds again.

## Tearing down

`stack-down.sh` runs `docker compose -p <project-name> down -v --remove-orphans`: **the ticket's volumes are removed with it**, seeded data included.

## A simpler alternative

If you own your compose file and don't mind editing it, skip the override: write the ports as interpolations, `"${WEB_PORT:-80}:80"`. `stackUp` already exports the ticket's ports, so `docker compose -p "myapp-$ORCA_TICKET" up -d --wait` is enough.
