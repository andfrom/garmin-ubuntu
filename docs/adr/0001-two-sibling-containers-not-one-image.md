# 0001 — Two sibling containers, not one combined image

**Status:** Accepted (backfilled 2026-08-25 from the 2026-08-02 initial commit)
**Date:** 2026-08-02

## Context

The environment needs three things that all want a display or a foreground: the Theia
IDE (a web server, but it also spawns the SDK's native GTK `simulator`), and the Connect
IQ SDK Manager (a standalone GTK/WebKit2GTK app). Earlier prototypes put the IDE and the
SDK Manager into one image and broke on exactly that: two GUI processes fighting over one
container's foreground, and no clean way to start/stop one without the other.

The SDK Manager is only needed occasionally — to install or update SDK versions and
device profiles — while the IDE runs persistently.

## Decision

Build two separate images, `theia/` and `sdk-manager/`, wired by one
`docker-compose.yml`. The SDK Manager service is profile-gated (`profiles:
["sdk-manager"]`) so a plain `docker compose up` starts only the IDE; the SDK Manager is
run on demand and stopped again.

They cooperate through a single host directory (`$CONNECTIQ_DATA_DIR`) bind-mounted into
both at `$HOME/.Garmin/ConnectIQ` — the path Garmin's tooling hardcodes.

## Alternatives considered

- **One image running both** — the approach that failed before; no supervisor story for
  two GUI foregrounds, and every SDK Manager restart would restart the IDE.
- **SDK Manager installed natively on the host, Theia in Docker** — reintroduces the
  host-library-rot problem the project exists to eliminate (see 0002).
- **Theia's own extension marketplace flow to fetch SDKs** — the Monkey C extension
  does not install SDKs; only the SDK Manager does.

## Consequences

- Each GUI binary owns its container's foreground; start/stop independently.
- Both images must agree on `$HOME` and uid so shared data is valid in both (led
  directly to 0004).
- `docker compose build` silently skips profile-gated services — `--profile
  sdk-manager` must always be passed when building; `test/smoke-test.sh` does so.
- Both images carry a near-identical GTK/WebKit dependency block; drift between them
  would break the shared SDK. Kept in sync by hand for now.
