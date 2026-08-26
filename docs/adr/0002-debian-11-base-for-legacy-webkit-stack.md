# 0002 — Debian 11 (bullseye) base images for the legacy WebKit2GTK stack

**Status:** Accepted (backfilled 2026-08-25 from the 2026-08-02 initial commit)
**Date:** 2026-08-02

## Context

`sdkmanager` and the SDK's `simulator` are precompiled x86_64 GTK apps linked against
`libwebkit2gtk-4.0.so.37` and `libsoup-2.4.so.1` (confirmed via `ldd` against a real
install, and cross-checked against the Arch AUR `connectiq-sdk-manager` package, which
has to `patchelf` the binary precisely because Arch no longer ships those libraries).
Current Ubuntu releases dropped them too, which is what naive
`apt-get install libwebkit2gtk-4.0-dev` Dockerfiles trip over.

The official `theia-ide` image (`ghcr.io/eclipse-theia/theia-ide/theia-ide:1.60.100`)
is itself Debian 11-based, and Debian 11 still carries the old stack natively.

## Decision

Base both images on Debian 11: the Theia image directly on the official `theia-ide`
image, the SDK Manager image on `debian:11-slim`. Install the runtime libraries as plain
packages (`libwebkit2gtk-4.0-37 libsoup2.4-1 libgtk-3-0 libsm6 libusb-1.0-0`) — no
`patchelf`, no vendored `.so` files.

## Alternatives considered

- **Ubuntu 22.04/24.04 base + `patchelf` to newer WebKit** — the Arch approach; fragile,
  and it binds the images to library ABIs Garmin never tested against.
- **Vendoring the old `.so` files into a modern base** — works until a transitive
  dependency (GLib, GTK) moves; also a licensing/redistribution smell.
- **Nix or a static build** — Garmin's binaries are closed; nothing to rebuild.

## Consequences

- Zero library surgery; `apt-get install` of the listed packages is the whole fix.
- Both images are pinned to a distribution that is past its regular support window;
  security updates come only via the `theia-ide` upstream image and Debian LTS. Accepted:
  these containers face `localhost` and the X socket, not the network.
- Both images must stay on the *same* base so the shared SDK data (installed by one,
  executed by the other) sees an identical library ABI.
- Host portability follows for free: nothing here depends on the host's package
  versions (goals.md goal 2, principles.md P1).
