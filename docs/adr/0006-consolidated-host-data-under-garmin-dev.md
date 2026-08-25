# 0006 — All host-side data under one directory, `~/garmin-dev/`

**Status:** Accepted (backfilled 2026-08-25 from commit `bf46eec`, 2026-08-02)
**Date:** 2026-08-02

## Context

The environment persists three kinds of data on the host: the shared ConnectIQ data
(SDKs, device profiles, `current-sdk.cfg`), Monkey C project workspaces, and Theia's own
config (recent workspaces, settings). An earlier iteration of the repo scattered these
across several unrelated paths (a standalone prototype directory, `~/.Garmin`, ad-hoc
workspace dirs), which got confusing fast and made "what do I back up?" a research task.

Users who already have a native SDK Manager install have data at `~/.Garmin/ConnectIQ`
and should be able to reuse it.

## Decision

`.env.example` defaults every host path to a subdirectory of one consolidated root,
`__HOME__/garmin-dev/` (`ConnectIQ/`, `workspaces/`, `theia-ide/`); `setup.sh`
substitutes the real `$HOME`, writes `.env`, and creates the directories. Each path stays
individually overridable in `.env` so an existing `~/.Garmin/ConnectIQ` can be pointed at
directly.

## Alternatives considered

- **Default `CONNECTIQ_DATA_DIR` to `~/.Garmin/ConnectIQ`** (Garmin's own convention) —
  convenient for existing native installs, but a Docker-written `current-sdk.cfg` there
  would silently break a native install sharing the same directory (0004). Opt-in
  instead.
- **Docker named volumes** — invisible to the host, awkward to back up, and workspaces
  need to be editable by host tools.
- **Everything under the repo checkout** — mixes data with code; a `git clean` would eat
  SDKs.

## Consequences

- One directory to back up, move, or wipe; one place to look.
- Paths in `.env.example` are placeholders (`__HOME__`), so the committed file carries no
  machine identity — a pre-commit rule for this repo.
- `docker-compose.yml` fails fast with a pointed message (`:?run ./setup.sh ...`) if
  `.env` is missing, rather than mounting empty defaults.
