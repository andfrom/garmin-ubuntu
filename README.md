# garmin-ubuntu

A working, Dockerized Garmin Connect IQ dev environment: Eclipse Theia (with the Monkey C
extension baked in) plus the Connect IQ SDK Manager, as two sibling containers instead of one
combined image. Built to run on Ubuntu 24.04, and should keep working on later Ubuntu
releases (26.x, ...) unmodified - see [Why Ubuntu version portability just works](#why-ubuntu-version-portability-just-works)
below.

## Quick start

```
git clone <this repo> ~/repos/garmin-ubuntu
cd ~/repos/garmin-ubuntu
./setup.sh
docker compose up -d theia
```

Open `http://localhost:3000`. `setup.sh` generates a `.env` from `.env.example` (using your
`$HOME` and uid/gid), creates the directories it points at if they don't exist, grants
containers X server access (`xhost +si:localuser:$(whoami)`), and builds both images.

If you already have SDKs/devices installed from a native (non-Docker) SDK Manager, edit
`.env` to point `CONNECTIQ_DATA_DIR` at that existing directory (typically
`~/.Garmin/ConnectIQ`) instead of a fresh empty one.

## Layout

- **`theia/`** - Eclipse Theia IDE with the Garmin Monkey C VSCode extension baked in.
  Persistent web server on `:3000`. Also runs the SDK's native `simulator` binary when you
  hit "Run" on a Monkey C project - that's a GTK app, not a web thing, so this container
  needs X11 access too even though it has no GUI of its own.
- **`sdk-manager/`** - the Connect IQ SDK Manager GUI, on its own. Only needed to
  install/update SDK versions and device profiles. Not started by `docker compose up` by
  default (it's profile-gated) - run it on demand, then stop it again.

Both containers bind-mount the same host directory (`$CONNECTIQ_DATA_DIR` in `.env`) to
`$HOME/.Garmin/ConnectIQ` inside the container. That's how they see the same installed
SDKs/devices without needing to run in the same container - trying to run both the IDE and
the SDK Manager in one image is what broke earlier attempts (two GUI processes fighting over
one container's foreground).

## Why this actually works

Both `sdkmanager` and the SDK's `simulator` binary are native GTK/WebKit2GTK apps linked
against the *old* `libwebkit2gtk-4.0` / `libsoup2.4` stack (confirmed via `ldd` against a real
install, and cross-checked against the Arch AUR package for `connectiq-sdk-manager`, which has
to `patchelf` the binary to newer libs precisely *because* Arch no longer ships the old ones).
Current Ubuntu releases dropped those old packages too - that's exactly what naive
`apt-get install libwebkit2gtk-4.0-dev libsoup2.4-1` Dockerfiles trip over.

Debian 11 (bullseye) - which is what the official `theia-ide` image is already built on -
still carries the old stack natively. Both images here are Debian 11-based, so no patchelf or
library surgery is needed: `apt-get install libwebkit2gtk-4.0-37 libsoup2.4-1 libgtk-3-0` is
enough, plus `libsm6` and `libusb-1.0-0` (both binaries need these too - easy to miss since the
error only appears once you actually try to launch the GUI, not at `apt-get install` time).

## Why Ubuntu version portability just works

All of the library-version wrangling above happens *inside* the containers, pinned to Debian
11, completely independent of whatever the host is running. The host only needs two things
that are stable across Ubuntu versions: Docker Engine, and an X server for the containers to
render GUI windows into (X11 directly, or XWayland if the host is on Wayland - true on 24.04's
GNOME session and expected to stay true going forward). There's nothing here that depends on
the host's own package versions, so this should keep working unmodified on Ubuntu 26.x and
beyond without touching the Dockerfiles.

## Usage

Start the IDE (persistent):

```
docker compose up -d theia
```

Your workspaces (`$WORKSPACES_DIR`) and Theia config (`$THEIA_CONFIG_DIR`) are bind-mounted
in, so recent-workspace history and settings persist across rebuilds.

Install/update the SDK or device profiles (on demand):

```
docker compose --profile sdk-manager up sdk-manager
# ... use the GUI window that appears on your desktop ...
docker compose stop sdk-manager && docker compose rm -f sdk-manager
```

Rebuild after Dockerfile changes:

```
docker compose build
```

## Verified end-to-end

- SDK Manager GUI renders correctly via X11/XWayland (reaches the "Welcome to Connect IQ"
  login screen).
- Theia web UI reachable on `:3000`, Monkey C extension activates automatically
  (`Debug configuration provider has been registered: monkeyc` in the container logs).
- From inside the **Theia** container: started the SDK's `simulator` binary and pushed a
  compiled `.prg` to it with `monkeydo <file>.prg <device_id>` - rendered as a simulated
  watch on the desktop. This is the same mechanism the Monkey C extension's "Run"/"Debug"
  command uses.
- Both containers run concurrently without conflict.

## Remote / TuringPi

The **Theia image is multi-arch** (`ghcr.io/eclipse-theia/theia-ide/theia-ide:1.60.100`
publishes both `amd64` and `arm64` manifests), and the SDK's actual compiler toolchain
(`monkeyc`, `monkeydo`, `era`, `mdd` - all bash wrappers around `monkeybrains.jar`, a JVM app)
is architecture-independent. So editing, building, and linting Monkey C projects headless
would work fine on an ARM64 cluster node.

**But** `sdkmanager` and `simulator` are precompiled **x86_64-only** native ELF binaries -
there is no arm64 build of either from Garmin. They cannot run on ARM64 nodes without QEMU
user-mode emulation, which is impractical for interactive GTK apps. Keep `sdk-manager` and
any interactive simulator/debug sessions running locally on an amd64 machine; only the Theia
*editing/build* container is a candidate for moving to a remote/ARM64 host (e.g.
`docker buildx build --platform linux/arm64 -t <registry>/garmin-theia ./theia`, push, run
remotely, and access it over the network or a mesh VPN at `http://<host>:3000`).

## Files

| File | Purpose |
|---|---|
| `theia/Dockerfile` | Theia + Monkey C extension image |
| `sdk-manager/Dockerfile` | SDK Manager GUI image |
| `docker-compose.yml` | Wires both up, reads paths/uid/gid from `.env` |
| `.env.example` | Template for `.env` (committed) |
| `.env` | Your actual machine-specific paths (gitignored) |
| `setup.sh` | One-shot bootstrap for a fresh machine |
