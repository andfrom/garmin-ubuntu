# Project Goals

**Status:** v1 — 2026-08-25 (backfilled from the state of the repo at that date; the
goals themselves were set 2026-08-02 when the repo was created)

## Purpose

Make Garmin Connect IQ development on Linux *boringly reproducible*: clone, run one
script, open a browser, and have an IDE that can build, run in the simulator, and debug
Monkey C apps — on any Ubuntu 24.04+ machine, without touching the host's package
versions.

The problem it solves is real and specific: Garmin ships `sdkmanager` and `simulator` as
precompiled x86_64 GTK/WebKit2GTK binaries linked against a library stack
(`libwebkit2gtk-4.0`, `libsoup2.4`) that current Ubuntu releases no longer carry. A native
install therefore rots with every host upgrade. Containers pinned to a base that still
ships that stack sidestep the problem permanently.

## Goals

1. **Works from a clean machine.** `git clone` → `./setup.sh` → `docker compose up -d
   theia` is the whole install. No manual library surgery, no `patchelf`, no host
   packages beyond Docker and an X server.
2. **Survives host upgrades.** Nothing depends on the host's package versions; Ubuntu
   26.x should work unmodified. (See [principles.md](principles.md) P1.)
3. **Full inner loop, not just editing.** Build, run in the simulator, and debug from the
   IDE must all work end-to-end — that is what distinguishes this from "Theia in a
   container".
4. **Data outlives images.** SDKs, device profiles, workspaces, and IDE settings live on
   the host under one directory (`~/garmin-dev/` by default) and survive rebuilds.
5. **Reuse an existing native install.** Pointing `CONNECTIQ_DATA_DIR` at an existing
   `~/.Garmin/ConnectIQ` must just work, so adoption is incremental.
6. **Every workaround is accounted for.** Each patch to upstream code has a stated
   reason, a stated drop condition, and an upstream status — so the image trends toward
   vanilla over time rather than accreting cruft.
7. **Helpful documentation (reflecting real troubleshooting and encountered issues).**
   Every troubleshooting entry is a failure that actually happened here and was
   diagnosed, not a hypothetical — and each gives the symptom, the command that exposes
   the cause, and the fix, so a reader can confirm the diagnosis applies to them.
   Reproducing the failure on demand is not the bar; being able to check the cause is.

## Non-goals

- **A general-purpose Theia distribution.** Only what Monkey C development needs.
- **Running the simulator or SDK Manager on ARM64.** Garmin ships no arm64 binaries;
  QEMU user-mode emulation for interactive GTK apps is not a supported path. The
  *editing/build* container is a candidate for remote/ARM64 hosts; the GUI parts are
  not.
- **Replacing or wrapping Garmin's tooling.** The SDK Manager, compiler, and simulator
  are used as shipped. Patches target Theia/extension integration gaps only, never
  Garmin's own binaries.
- **Non-Docker packaging** (snap, flatpak, native .deb). The whole point is isolation
  from the host's library versions.
- **Wayland-native rendering.** X11/XWayland socket sharing is the supported display
  path; it is stable and available on every current Ubuntu desktop session.

## Who it's for

Primarily the maintainer's own Connect IQ projects; secondarily anyone on Linux who
has hit the `libwebkit2gtk-4.0.so.37: cannot open shared object file` wall and wants a
setup that stays fixed.
