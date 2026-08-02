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
docker compose --profile sdk-manager build
```

(`--profile sdk-manager` is required here even though that service isn't started by
default - see [Troubleshooting](#troubleshooting) if you forget it.)

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

## Troubleshooting

Every entry below is a real failure hit and diagnosed while building this repo, not a
hypothetical.

### GUI window never appears (SDK Manager, or the simulator launched from Theia)

Cause is almost always the X server refusing the container's connection. Check:

```
xhost +si:localuser:$(whoami)      # containers won't be authorized to connect without this
echo $DISPLAY                      # compare against DISPLAY in .env - they must match
```

If both look right and it's still silent, check the container's own stderr - a GTK app
that can't reach the display fails immediately and loudly:

```
docker compose logs sdk-manager
# or, for a one-off container:
docker logs <container>
```

Look for `cannot open display` or `Unable to initialize GTK+, DISPLAY not set`. On a
Wayland session (GNOME on 24.04 and later), `DISPLAY` should point at the XWayland
display (commonly `:0` or `:1` - run `ls /tmp/.X11-unix/` on the host to see what's
actually there).

### `error while loading shared libraries: libXxx.so.N: cannot open shared object file`

A missing runtime library - the same class of bug that broke this project for months
before (`libwebkit2gtk-4.0.so.37`, `libsoup-2.4.so.1`, `libSM.so.6`,
`libusb-1.0.so.0` have all been hit here). `apt-get install` exiting 0 does **not** mean
the binary can actually run - it only means the packages you listed were installable, not
that you listed the right ones. Diagnose directly against the binary itself:

```
docker run --rm --entrypoint bash garmin-sdk-manager:latest -c \
  "ldd /opt/sdk-manager/bin/sdkmanager | grep -i 'not found'"
```

Same idea for the SDK's `simulator` binary (not baked into the theia image - it comes
from the bind-mounted SDK data dir at runtime), substituting the real path:

```
docker run --rm --entrypoint bash -v "$CONNECTIQ_DATA_DIR:/sdk:ro" garmin-theia:latest -c \
  "ldd /sdk/Sdks/*/bin/simulator | grep -i 'not found'"
```

Whatever's listed as `not found`, add the corresponding Debian package to the relevant
Dockerfile and rebuild with `--no-cache` (see below - a plain rebuild can mask this).
`test/smoke-test.sh` runs both of these checks automatically.

### `Unable to connect to simulator` from `monkeydo`

The simulator is a separate long-running process, not something `monkeydo` starts for
you - per its own `--help` text: "The simulator must be running for this command to
succeed." Start it first, then push the app:

```
"$SDK/bin/simulator" &   # leave running
monkeydo bin/YourApp.prg fr265
```

This is also what the Monkey C extension's "Run"/"Debug" command does under the hood, so
if debugging from the Theia UI silently does nothing, check whether a `simulator` process
is actually running inside the container.

### Bind-mounted files owned by the wrong user / permission denied on write

UID/GID mismatch between the container's user and the host user that owns the
bind-mounted directories. Check `HOST_UID`/`HOST_GID` in `.env` match your actual user:

```
id -u; id -g
```

If they don't, fix `.env` and rebuild - the theia image remaps its `theia` user's
UID/GID at *build* time (`usermod`), so a stale image built with the wrong values won't
self-correct just by changing `.env` and restarting the container.

### "Unable to determine the current SDK" / "MonkeyC Language Server ... crashed 5 times"

The extension's bundled `LanguageServer.jar` (and the debugger it powers) can't find the
SDK, even though `current-sdk.cfg` under `$CONNECTIQ_DATA_DIR` looks correct. Two
possible causes, both hit here:

1. **A stale absolute path.** `current-sdk.cfg` and `sdkmanager-config.ini`'s
   `current-sdk=` line both store an *absolute* path back to the SDK directory - if
   either was written by a different environment (a native install, or a container with
   a different `$HOME`), it'll point somewhere the current container can't see. Check
   both:
   ```
   cat "$CONNECTIQ_DATA_DIR/current-sdk.cfg"
   grep ^current-sdk= "$CONNECTIQ_DATA_DIR/sdkmanager-config.ini"
   ```
   Both should point at `/home/theia/.Garmin/ConnectIQ/Sdks/<version>/` (that's the
   *container-internal* path, not a host path) with the version directory actually
   present. Fix by hand-editing them, or by opening `sdk-manager` and re-selecting the
   current SDK there.
2. **A `getpwuid()` uid collision.** The theia image's base ships a pre-existing `node`
   user already sitting at uid 1000; remapping `theia` to the host's uid (also usually
   1000) makes both accounts resolve via `getpwuid()`, and Java's `user.home` - which
   `LanguageServer.jar` uses to find `~/.Garmin/ConnectIQ` - follows `getpwuid()`, not
   the `$HOME` env var. If `node`'s passwd entry doesn't also point at `/home/theia`,
   the language server keeps resolving to `/home/node` regardless of what `.env` or
   `ENV HOME` say. Check from inside the image:
   ```
   docker run --rm --entrypoint bash garmin-theia:latest -c \
     "java -XshowSettings:properties -version 2>&1 | grep user.home"
   ```
   Should print `/home/theia`. If it doesn't, `theia/Dockerfile`'s `usermod -d
   /home/theia node` step is missing or not taking effect - rebuild with `--no-cache`.

   Do **not** try to fix this by relocating theia's own home directory to something
   else - that was tried here and broke the container outright (`Cannot find module
   '/home/theia/applications/browser/lib/backend/main.js'`), because the base image's
   own launcher hardcodes that absolute path. `/home/theia` is fixed; only `node` needs
   to be pointed at it.

After fixing either, `docker compose restart theia` and retry - no rebuild needed for
cause 1, since the config files are bind-mounted and read live.

### `docker compose build` doesn't seem to change the sdk-manager image at all

Two independent gotchas, both found while building the smoke test:

1. **`profiles:` gates `build`, not just `up`.** A profile-gated service (`sdk-manager`
   here) is silently skipped by a plain `docker compose build`, with no warning - it just
   keeps whatever image already has that tag. Always pass `--profile sdk-manager`
   explicitly when building it: `docker compose --profile sdk-manager build`.
2. **Cached layers can mask a fix (or a regression).** A cached `RUN apt-get install ...`
   layer was observed to be reused even after editing the package list, silently keeping
   an old, broken result. If a rebuild doesn't seem to have taken effect, confirm with
   `--no-cache`:
   ```
   docker compose --profile sdk-manager build --no-cache
   ```

`test/smoke-test.sh` always builds with both of these accounted for, precisely because
they produced false "it's fine" results here.

### Port 3000 already in use

Something else on the host (or another container) is bound to it - a Grafana snap
instance did exactly this during earlier development. Find and stop it, or change the
host-side port in `docker-compose.yml`'s `ports:` mapping (`"3001:3000"`, etc.) and open
that port instead.

### Newly installed SDK/device doesn't show up in Theia

The Monkey C extension reads the SDK config (`current-sdk.cfg`, `Devices/`) when it
activates, not continuously. After installing or updating something via `sdk-manager`,
restart the `theia` container so it picks up the change:

```
docker compose restart theia
```

## Files

| File | Purpose |
|---|---|
| `theia/Dockerfile` | Theia + Monkey C extension image |
| `sdk-manager/Dockerfile` | SDK Manager GUI image |
| `docker-compose.yml` | Wires both up, reads paths/uid/gid from `.env` |
| `.env.example` | Template for `.env` (committed) |
| `.env` | Your actual machine-specific paths (gitignored) |
| `setup.sh` | One-shot bootstrap for a fresh machine |
