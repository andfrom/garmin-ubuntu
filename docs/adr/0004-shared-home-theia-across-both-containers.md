# 0004 — Both containers use the literal home `/home/theia`, with no colliding passwd entry

**Status:** Accepted (backfilled 2026-08-25 from commits `cf855af` and `bf46eec`,
2026-08-02)
**Date:** 2026-08-02

## Context

Two separate defects surfaced once the containers were split (0001):

1. The SDK Manager writes an **absolute** path into `current-sdk.cfg` and
   `sdkmanager-config.ini` (`current-sdk=/home/<user>/.Garmin/ConnectIQ/Sdks/...`). With
   the SDK Manager running as `garmin` with home `/home/garmin` and Theia running as
   `theia` with home `/home/theia`, everything the SDK Manager installed was invisible to
   the IDE: "Unable to determine the current SDK".
2. The Theia base image ships a pre-existing `node` user at uid 1000. Remapping `theia`
   to the host uid (also typically 1000) leaves two passwd entries at one uid, and
   Java's `user.home` — which the extension's `LanguageServer.jar` uses to locate
   `~/.Garmin/ConnectIQ` — resolves via `getpwuid()`, not `$HOME`. It kept returning
   `/home/node` regardless of `ENV HOME`.

Relocating Theia's own home directory was tried and broke the container outright: the
base image's launcher hardcodes `/home/theia/applications/browser/lib/backend/main.js`.

## Decision

`/home/theia` is the fixed home in **both** images. The SDK Manager image creates its
user with `-d /home/theia` and sets `ENV HOME=/home/theia`; the Theia image additionally
runs `usermod -d /home/theia node` so every passwd entry at the shared uid resolves to the
same home. The shared data directory is mounted at `/home/theia/.Garmin/ConnectIQ` in
both.

## Alternatives considered

- **Rewrite the absolute paths in `current-sdk.cfg` on container start** — a moving
  target; the SDK Manager rewrites them on every change, and it hides the real cause.
- **Delete the `node` user** — the base image's own tooling may depend on it; pointing
  its home is the minimal change.
- **Give Theia a different home than `/home/theia`** — tried, fails hard (see Context).
- **Run both containers as uid 1000 and ignore the host uid** — breaks bind-mount file
  ownership for any host user that is not uid 1000 (principles.md P3).

## Consequences

- Any container that reads or writes the shared ConnectIQ directory must use exactly
  this home. This is now a stated invariant (principles.md P4) with a `java
  -XshowSettings` test.
- Reusing an existing native `~/.Garmin/ConnectIQ` still works, but its
  `current-sdk.cfg` will point at the *host* home and must be re-selected once from
  the SDK Manager (documented in README Troubleshooting).
- The unusual `-d /home/theia` for a user named `garmin` needs a comment wherever it
  appears; it looks like a mistake otherwise.
