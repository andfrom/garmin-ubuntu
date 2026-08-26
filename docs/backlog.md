# Backlog

Open items, roughly by value. Nothing here is a commitment; move an item into an ADR or a
commit when it is actually decided or done. Done items get deleted, not ticked.

## Upstream

- **File the two drafted Theia bug reports.** Reports are drafted (not committed) for
  (a) `TaskServerImpl.fireTaskExitedEvent` never firing
  `onDidEndTaskProcess` for `CustomTask`, and (b) `theia-ide`'s static server preferring
  stale pre-built `.gz` assets. Filing them is what makes the Theia patch and the `.gz`
  regeneration step droppable (README "Patches applied" table). Once filed, link the
  issue numbers in that table and the Dockerfile comments.

## Automation

- **Detect new Theia and Monkey C extension releases; bump automatically unless
  something breaks.** Today both pins are hand-edited (`theia/Dockerfile`: `FROM
  ...theia-ide:1.60.100` and `ARG MONKEYC_EXT_VERSION=1.1.3`) and nothing notices when
  upstream moves. The SDK Manager has the opposite problem: its download URL is
  unversioned (`connectiq-sdk-manager-linux.zip`), so it floats silently on every
  `--no-cache` build.

  *Sources to watch:*
  - Theia: tags of `ghcr.io/eclipse-theia/theia-ide/theia-ide` (or releases of
    `eclipse-theia/theia-ide` on GitHub).
  - Monkey C: the VS Marketplace gallery — the same `garmin.gallery.vsassets.io` host the
    Dockerfile already downloads from, queried for the latest version, or the
    `extensionquery` API.
  - SDK Manager: no version endpoint; hash the downloaded zip and compare to a pinned
    checksum (which requires pinning it first — see Hardening).

  *Gate — what "nothing is broken" must mean, in order of cost:*
  1. Build succeeds with every patch needle matching. The Theia patch `throw`s on a
     needle count ≠ 1 and the `taskType` `sed` is guarded by `grep` counts, so a
     shape change in either upstream fails the build instead of passing silently.
  2. `test/smoke-test.sh` passes (`ldd` clean, HTTP up, extension activation log line).
  3. The debug path works end-to-end. `test/debug-path.sh` does this, but it needs a real
     SDK, a developer key, and a display, so it is a local check, not a CI gate. Until an
     automatable form exists, a bump that a human has not run `debug-path.sh` against can
     only be *proposed*, not merged.

  *Mechanism, two viable shapes:*
  - **Renovate**-style: `FROM` tags are handled natively; `MONKEYC_EXT_VERSION` needs a
    custom regex manager with a custom datasource; the marketplace has no standard
    datasource, so this may need a small JSON shim. Produces PRs; CI on the PR runs the
    gate.
  - **Own scheduled job** (GitHub Actions cron, or a local systemd timer if the repo is
    not on GitHub — there is no `.github/` yet): a script queries the sources, edits the
    pins, runs the gate, and opens a PR or commits to a branch. More code, no
    datasource gymnastics, and the gate can include the X11-dependent parts on a
    self-hosted runner.

  *Policy:* auto-merge only for bumps that pass gate 3; anything failing gate 1 or 2 is
  a PR with the failing output attached, since a needle miss means an upstream change
  that needs a human to re-derive the patch. Theia and the extension should bump
  independently — a needle break on one must not block the other.

  *Prerequisite still open:* an automatable (CI-runnable) form of the debug-path check;
  `test/debug-path.sh` exists but needs a real SDK, key, and display.

## Hardening

- **Debug adapter `setExceptionBreakpoints` internal error — root cause known, decide if
  worth fixing.** Every debug session start logs an lsp4j
  `SEVERE: Internal error: java.lang.reflect.InvocationTargetException` whose root cause
  (confirmed 2026-08-26 by decompiling the adapter) is
  `UnsupportedOperationException` thrown by lsp4j's **default** implementation of
  `IDebugProtocolServer.setExceptionBreakpoints`: Garmin's `DebugServer.jar` does not
  implement that DAP request, and Theia calls it during session init. The session runs
  fine regardless (verified: build → simulator → adapter → RUNNING all succeed). Options:
  ignore it (harmless log noise); or have the extension advertise
  `supportsExceptionOptions: false` / no exception breakpoint filters so Theia stops
  sending the request. Low priority; document in README Troubleshooting so it isn't
  re-chased as a failure.

## Portability

- **Remote/ARM64 editing container.** The Theia image builds for `linux/arm64` (CI
  verifies this), and the compiler is a JVM app, so running the editing/build container
  on a remote arm64 host works. Build it on that host rather than pushing the image
  through a registry (README, "License"). The simulator and SDK Manager are x86_64-only
  and stay local (goals.md, non-goals). Open: document the remote-host workflow.
- **Wayland-native display path.** Not planned (goals.md), but worth re-checking if
  XWayland is ever dropped from a default Ubuntu session.
