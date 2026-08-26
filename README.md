![Project Logo](assets/logo.png)

# garmin-ubuntu

A working, Dockerized Garmin Connect IQ dev environment: Eclipse Theia plus the Connect IQ
SDK Manager, as two sibling containers instead of one combined image. The Theia image
fetches Garmin's official Monkey C extension from the Visual Studio Marketplace at build
time - this repository doesn't ship or redistribute it (see
[The Monkey C extension, and where it comes from](#the-monkey-c-extension-and-where-it-comes-from)). Built to run on Ubuntu 24.04, and should keep working on later Ubuntu
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

- **`theia/`** - Eclipse Theia IDE; the build fetches the Garmin Monkey C VS Code
  extension from the Marketplace and unpacks it into the image (nothing extension-related
  is committed to this repo).
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

## The Monkey C extension, and where it comes from

The official Garmin Monkey C extension is fetched from the **Microsoft Visual Studio
Marketplace** at image-build time (pinned by `MONKEYC_EXT_VERSION` in `theia/Dockerfile`),
because that is currently the only place Garmin publishes it. Two things are worth knowing
before you build:

- **The Marketplace Terms of Use scope extensions to Microsoft's own products** (Visual
  Studio, VS Code, GitHub Codespaces, Azure DevOps). Eclipse Theia is not on that list.
  Building this image downloads the extension and runs it in Theia, which is your choice as
  the person building it; this repository does not redistribute the extension or host it
  anywhere - each build fetches it fresh from Garmin's Marketplace listing.
- **The clean fix is Open VSX**, the vendor-neutral registry that Theia, VSCodium, Gitpod
  and similar editors install from. The extension is not there yet; there is an open
  request asking Garmin to publish it. If that happens, this image will install it from
  Open VSX and the note above becomes moot.

Building the image also means accepting Garmin's Connect IQ SDK License Agreement (bundled
with the extension), which permits installing one copy on a machine you control for your own
development - see [License](#license). If you would rather not fetch from the Marketplace at
all, you can edit `theia/Dockerfile` to `COPY` a `.vsix` you already have instead of
fetching one.

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
- The **Theia** container can start the SDK's `simulator` binary and push a compiled
  `.prg` to it with `monkeydo <file>.prg <device_id>`, rendering a simulated watch on the
  desktop - the same mechanism the Monkey C extension's "Run"/"Debug" command uses.
  (`test/debug-path.sh` exercises this end to end via the IDE.)
- Both containers run concurrently without conflict.

## Remote / ARM64 hosts

The **Theia image is multi-arch** (`ghcr.io/eclipse-theia/theia-ide/theia-ide:1.60.100`
publishes both `amd64` and `arm64` manifests), and the SDK's actual compiler toolchain
(`monkeyc`, `monkeydo`, `era`, `mdd` - all bash wrappers around `monkeybrains.jar`, a JVM app)
is architecture-independent. So editing, building, and linting Monkey C projects headless
would work fine on a remote ARM64 host.

**But** `sdkmanager` and `simulator` are precompiled **x86_64-only** native ELF binaries -
there is no arm64 build of either from Garmin. They cannot run on ARM64 hosts without QEMU
user-mode emulation, which is impractical for interactive GTK apps. Keep `sdk-manager` and
any interactive simulator/debug sessions running locally on an amd64 machine; only the Theia
*editing/build* container is a candidate for running on a remote host.

If you do that, **build the image on the remote host itself** (clone this repo there and
run `docker compose build theia`) rather than building locally and pushing the image
through a registry: the built image contains the Monkey C extension, which Garmin's SDK
License Agreement does not permit hosting on a server or redistributing (see
[License](#license)). Then access it over the network or a mesh VPN at `http://<host>:3000`.

## Patches applied, and what's needed to drop them

This is not a vanilla `theia-ide` image - `theia/Dockerfile` patches a few things to
work around real Theia/extension incompatibilities. None of them exist by choice; each
is a workaround for a specific, identified gap. This table is the single place to check
whether a patch can be dropped yet.

| Patch | Where | Why it exists | Upstream status |
|---|---|---|---|
| `taskType` compatibility (`sed`) | `extension.js` | Theia rewrites a task's `definition.type` to the underlying execution type and moves the extension's own custom type to `definition.taskType` instead; the extension's build-completion check only ever looks at `.type`. | **Permanent** - confirmed intentional Theia behavior, not a bug: [eclipse-theia/theia#8822](https://github.com/eclipse-theia/theia/issues/8822), closed as-is. Nothing to wait for. |
| Synthesize `$onDidEndTaskProcess` for CustomExecution tasks | `hosted-plugin.js` (`patch-debug-task-tracking.js`) | Theia's `TaskServerImpl.fireTaskExitedEvent` only ever fires `onDidEndTaskProcess` for tasks `instanceof ProcessTask`, never for `CustomTask` (what the Monkey C build task actually is) - unlike real VS Code Desktop, where this fires correctly. | A bug report is drafted but not yet filed upstream. **If fixed upstream, this patch can be dropped entirely.** |
| `.gz` regeneration after patching `hosted-plugin.js` | Dockerfile step | The base image ships every browser-served file with a pre-built `.gz` twin that its static server prefers over the plain file for any client advertising gzip support (every real browser) - so patching the plain file alone has zero effect on real users. | A documentation request is drafted but not yet filed upstream. Only needed as long as any frontend file under `lib/frontend/` is patched - **if the `$onDidEndTaskProcess` patch above is ever dropped, this step becomes unnecessary too**, since it's the only frontend file this repo currently patches. |

Neither report is filed upstream yet. If either is filed, link the issue number in this
table and in the corresponding Dockerfile comment.

## Troubleshooting

Every entry below is a real, diagnosed failure, not a hypothetical.

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

### Build fails with `java.awt.AWTError: Can't connect to X11 window server`, or "Task: Building For Device" ends in a Java stack trace

Same cause as the entry above, different symptom: the SDK's resource compiler
(`monkeybrains.jar`) initializes Java AWT while rasterizing resources, and AWT connects
to the X server named by `DISPLAY`. If the X server refuses the container (the
`xhost +si:localuser:$(whoami)` grant is per X session and silently lapses when you log
out or reboot), the build dies with `Authorization required, but no authorization
protocol specified` followed by the `AWTError`. Inside the IDE that surfaces as a build
task ending in a long `org.apache.batik` / `ConnectIQBufferedImage.rasterize` stack trace
and "Run App" going nowhere. Confirm from inside the container:

```
docker exec garmin-theia bash -c 'SDK=$(cat ~/.Garmin/ConnectIQ/current-sdk.cfg); cd ~/workspaces/<project> && "$SDK/bin/monkeyc" -d fr265 -f monkey.jungle -o /tmp/t.prg -y ~/.Garmin/ConnectIQ/Keys/developer_key'
```

Fix: re-run `xhost +si:localuser:$(whoami)` on the host (no container restart needed).
The build itself does not need a display - the same command succeeds with
`JAVA_TOOL_OPTIONS=-Djava.awt.headless=true` - so making builds independent of the X
grant is a candidate hardening (`docs/backlog.md`); the simulator still needs X either
way.

### `error while loading shared libraries: libXxx.so.N: cannot open shared object file`

A missing runtime library - the same class of bug behind the shared-library failures
above (`libwebkit2gtk-4.0.so.37`, `libsoup-2.4.so.1`, `libSM.so.6`, `libusb-1.0.so.0`
are all in this class). `apt-get install` exiting 0 does **not** mean
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

Two independent gotchas:

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

`test/smoke-test.sh` always builds with both of these accounted for, since either can
otherwise produce a false "it's fine" result.

### Port 3000 already in use

Something else on the host (or another container) is bound to it - for example another
local service already using port 3000. Find and stop it, or change the
host-side port in `docker-compose.yml`'s `ports:` mapping (`"3001:3000"`, etc.) and open
that port instead.

### Newly installed SDK/device doesn't show up in Theia

The Monkey C extension reads the SDK config (`current-sdk.cfg`, `Devices/`) when it
activates, not continuously. After installing or updating something via `sdk-manager`,
restart the `theia` container so it picks up the change:

```
docker compose restart theia
```

### Debug session logs `SEVERE: Internal error ... setExceptionBreakpoints`, but works

Starting a debug session prints a Java stack trace in `docker logs garmin-theia`:
`org.eclipse.lsp4j.jsonrpc.RemoteEndpoint fallbackResponseError / SEVERE: Internal error:
java.lang.reflect.InvocationTargetException`, rooted in an
`UnsupportedOperationException` from `IDebugProtocolServer.setExceptionBreakpoints`. This
is **harmless** - the build runs, the simulator launches, and the session reaches RUNNING.
Cause: Garmin's debug adapter (`DebugServer.jar`) doesn't implement the DAP
`setExceptionBreakpoints` request, so lsp4j's default method throws; Theia sends the
request during session init regardless and logs the rejection. Nothing to fix in this
repo; noted so the stack trace isn't mistaken for a failure.

### "Run App" / Start Debugging hangs forever, no error anywhere

Fixed - `theia/patch-debug-task-tracking.js` synthesizes the `onDidEndTaskProcess` event
Theia never fires for the extension's `CustomExecution` build task, which the extension
awaits before launching the debug adapter. If "Run App" builds successfully (the terminal
shows `BUILD SUCCESSFUL`) but nothing else happens, and you have modified `theia/`, first
confirm the patch is actually in the running image (`test/task-events.sh`).

The full investigation - three OS processes, the stage-by-stage chain, and the dead ends
ruled out - is in
[`docs/investigations/run-app-hang.md`](docs/investigations/run-app-hang.md).

### Editing a frontend `.js` file has no effect in the browser, no matter what you try

The `theia-ide` base image ships a pre-built `.gz` twin of every browser-served file and
its server prefers the `.gz` for any client that accepts gzip (every browser). Patching a
plain `.js` under `lib/frontend/` therefore has **no effect** until you regenerate its
twin (`gzip -kf <file>`) - and plain `curl`, which doesn't request gzip, misleadingly
shows the patch working. This repo's Dockerfile regenerates the twin after patching, and
`test/smoke-test.sh` checks the gzip-served bytes.

Full mechanism and how it was found:
[`docs/investigations/stale-gz-assets.md`](docs/investigations/stale-gz-assets.md).

## Documentation

User-facing *how* lives in this README. The *why* — project goals and non-goals, design
principles, and Architecture Decision Records for every non-trivial choice (two
containers, Debian 11 base, shared `/home/theia`, the Theia patches, the `~/garmin-dev/`
layout) — lives in [`docs/`](docs/README.md). The longer resolved-bug write-ups behind
two of the Troubleshooting entries are in
[`docs/investigations/`](docs/investigations/).

## Files

| File | Purpose |
|---|---|
| `theia/Dockerfile` | Theia + Monkey C extension image |
| `sdk-manager/Dockerfile` | SDK Manager GUI image |
| `docker-compose.yml` | Wires both up, reads paths/uid/gid from `.env` |
| `.env.example` | Template for `.env` (committed) |
| `.env` | Your actual machine-specific paths (gitignored) |
| `setup.sh` | One-shot bootstrap for a fresh machine |

## License

This repository (Dockerfiles, scripts, patches, documentation) is licensed under the
[MIT License](LICENSE).

That license covers only what is in this repository. The images it builds download
third-party materials at build time that are **not** covered by it and are not
redistributed here: the Garmin Connect IQ SDK Manager and the Garmin Monkey C extension
are governed by the Garmin Connect IQ SDK License Agreement (bundled with the extension
as `LICENSE.txt`), which you accept by downloading them - i.e. by building these images.
The base Theia image is governed by its own licenses. Do not publish built images: the
Garmin agreement does not permit redistributing or hosting the SDK materials they contain.
