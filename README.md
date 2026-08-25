![Project Logo](assets/logo.png)

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

## Patches applied, and what's needed to drop them

This is not a vanilla `theia-ide` image - `theia/Dockerfile` patches a few things to
work around real Theia/extension incompatibilities. None of them exist by choice; each
is a workaround for a specific, identified gap. This table is the single place to check
whether a patch can be dropped yet.

| Patch | Where | Why it exists | Upstream status |
|---|---|---|---|
| `taskType` compatibility (`sed`) | `extension.js` | Theia rewrites a task's `definition.type` to the underlying execution type and moves the extension's own custom type to `definition.taskType` instead; the extension's build-completion check only ever looks at `.type`. | **Permanent** - confirmed intentional Theia behavior, not a bug: [eclipse-theia/theia#8822](https://github.com/eclipse-theia/theia/issues/8822), closed as-is. Nothing to wait for. |
| Fix 1: double `registerDebugConfigurationProvider` registration | `extension.js` (`patch-debug-task-tracking.js`) | Extension registers its `monkeyc` debug config provider with `DebugConfigurationProviderTriggerKind.Dynamic` only; a second, default-trigger-kind registration was added to make Theia actually invoke it for a static `launch.json` entry. | Not filed anywhere - its own necessity is unverified (see Troubleshooting below). Not currently blocked on anything upstream. |
| Fix 2: synthesize `$onDidEndTaskProcess` | `hosted-plugin.js` (`patch-debug-task-tracking.js`) | Theia's `TaskServerImpl.fireTaskExitedEvent` only ever fires `onDidEndTaskProcess` for tasks `instanceof ProcessTask`, never for `CustomTask` (what the Monkey C build task actually is) - unlike real VS Code Desktop, where this fires correctly. | Draft ready at `scratch/bugreport-theia-customtask-onDidEndTaskProcess.md` (gitignored, not yet filed). **If fixed upstream, this patch can be dropped entirely.** |
| `.gz` regeneration after patching `hosted-plugin.js` | Dockerfile step | The base image ships every browser-served file with a pre-built `.gz` twin that its static server prefers over the plain file for any client advertising gzip support (every real browser) - so patching the plain file alone has zero effect on real users. | Draft ready at `scratch/bugreport-theia-ide-stale-gz-assets.md` (gitignored, not yet filed). Only needed as long as any frontend file under `lib/frontend/` is patched - **if Fix 2 above is ever dropped, this step becomes unnecessary too**, since it's the only frontend file this repo currently patches. |

The two draft bug reports aren't filed yet - they exist so filing them (or not) is a
deliberate choice, not something to lose track of. If either gets filed, link the actual
issue number in this table and in the corresponding Dockerfile comment.

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

### "Run App" / Start Debugging hangs forever, no error anywhere

Fixed - `patch-debug-task-tracking.js` applies two fixes for this (see the Dockerfile
comment above it), and the Dockerfile also regenerates `hosted-plugin.js.gz` right after
(see the next section below - that part turned out to be essential, not optional).
Documenting the full investigation here since each stage runs in a different process,
which made this hard to pin down: three independent execution contexts are involved,
only one of which (the frontend) is reachable via ordinary browser DevTools.

**Execution contexts involved** (which OS process each stage runs in):

- **Frontend** - plain JS in the browser tab. Reachable via Firefox/Chrome DevTools'
  normal Sources/Console panels.
- **Backend** - Theia's main Node.js process (`lib/backend/main.js`), which spawns the
  plugin-host. Not directly reachable via a browser debugger; observable via
  `docker logs`.
- **Plugin-host** - a *separate* Node.js child process (`lib/backend/plugin-host`, shown
  in logs as `PLUGIN_HOST(pid)`) that actually runs the Monkey C extension's own code
  (`extension.js`). Also not reachable via a browser debugger - its `console.log` output
  goes to `docker logs` (its stdout is piped through the backend process), and attaching
  a real debugger to it requires Node's inspector protocol (`kill -USR1 <pid>`), which
  Firefox cannot speak (its `about:debugging` remote-debugging feature only talks to
  other Firefox instances, not Node's V8 Inspector protocol - no combination of
  host/port there will work). Chrome/Chromium's `chrome://inspect` can, if available.

**Functional blocks involved** (which subsystem owns each stage, independent of which
process it happens to run in):

- **Debug Configuration Provider** - the extension's `Pn` class plus Theia's own
  `PluginDebugService`/`resolveDebugConfigurationByResolversChain`. Job: turn a
  `launch.json` entry into a fully-resolved config, including making sure a build has
  run first.
- **Tasks API bridge** - the VS Code Tasks API surface (`vscode.tasks.executeTask`,
  `vscode.tasks.onDidEndTaskProcess`) as exposed to extensions. Implemented by a
  `TasksExtImpl`-style class in the plugin-host, backed by a matching bridge class in
  the frontend that forwards real task events across the RPC boundary.
- **Task Server** - Theia's own core task-lifecycle engine (`@theia/task`, backend). Job:
  actually spawn the task's process and broadcast its lifecycle (created/exited) to every
  connected frontend.
- **Terminal widget** - a UI-only component that separately detects when a task's
  underlying process exits, purely to update what's shown in the terminal panel
  ("BUILD SUCCESSFUL", "Terminal will be reused by tasks"). Not wired to the Tasks API
  bridge at all - this is exactly why the terminal can show success while the extension
  never finds out.
- **Debug Adapter launch** - the step that never gets reached: actually starting the
  debug session once configuration resolution returns.

**The chain, and where it breaks** (`[Process / Functional block]` per stage):

```
[Frontend / Debug Configuration Provider]
User clicks "Run App" (static launch.json entry, type: monkeyc)
        │
        ▼
[Frontend / Debug Configuration Provider] Theia calls resolveDebugConfiguration
        │  → RPC to [Plugin-host / Debug Configuration Provider] extension's Pn.resolveDebugConfiguration
        │  → fills in defaults (type/name/request), returns almost instantly
        ▼
[Frontend / Debug Configuration Provider] Theia calls resolveDebugConfigurationWithSubstitutedVariables
        │  → RPC to [Plugin-host / Debug Configuration Provider] extension's Pn.resolveDebugConfigurationWithSubstitutedVariables
        ▼
[Plugin-host / Tasks API bridge] Extension calls vscode.tasks.executeTask() to start the Monkey C build
        │  → Promise resolves almost immediately (VS Code API contract: this means
        │    "task started", NOT "task finished" - confirmed via trace, not a bug)
        ▼
[Plugin-host / Tasks API bridge] Extension registers a ONE-TIME onDidEndTaskProcess
listener and returns a Promise that only resolves when THAT listener fires
        │
        ▼
[Backend / Task Server] Build genuinely runs (monkeybrains.jar) and succeeds
        │  ✔ confirmed independently: [Frontend / Terminal widget] shows
        │    "BUILD SUCCESSFUL" / "Terminal will be reused by tasks" - a separate
        │    detection mechanism, NOT wired to the Tasks API bridge below
        ▼
  ┌────────────────────────────────────────────────────────────────────┐
  │ SHOULD happen:                                                     │
  │ [Backend / Task Server] detects the process exited                 │
  │   → broadcasts a task-exit event to [Frontend / Tasks API bridge]  │
  │   → forwards it to [Plugin-host / Tasks API bridge] over RPC       │
  │   → [Plugin-host / Tasks API bridge] onDidEndTaskProcess fires     │
  │   → [Plugin-host / Debug Configuration Provider] Promise resolves  │
  │   → resolveDebugConfigurationWithSubstitutedVariables returns      │
  │   → [Frontend / Debug Adapter launch] Theia launches the adapter   │
  │                                                                     │
  │ ACTUALLY happens without Fix 2: none of it. The build task is a    │
  │ VS Code CustomExecution task (the extension spawns and manages its │
  │ own process via a Pseudoterminal, rather than using Theia's        │
  │ ShellExecution/ProcessExecution types). Theia's own                │
  │ TaskServerImpl.fireTaskExitedEvent only ever fires                 │
  │ onDidEndTaskProcess for tasks that are `instanceof ProcessTask` -  │
  │ never for CustomTask, unlike real VS Code Desktop. So              │
  │ onDidEndTaskProcess genuinely never fires for this task, by        │
  │ design, on Theia's end - confirmed via live tracing on both the    │
  │ frontend and the plugin-host independently. → extension's Promise  │
  │ never resolves → hangs forever, no error.                          │
  └────────────────────────────────────────────────────────────────────┘
```

Fix 2 in `patch-debug-task-tracking.js` synthesizes the missing `$onDidEndTaskProcess`
from `onTaskExit`, which *does* fire reliably for every task type and already carries
the exit code. **Ordering matters**: it must fire `$onDidEndTaskProcess` *before*
`$onDidEndTask` - the latter deletes the task's execution record from the plugin-host's
internal map as part of its own cleanup (`TasksExtImpl.$onDidEndTask`), so calling them
in the wrong order makes `$onDidEndTaskProcess` throw `Error: Task execution with id N
is not found` (a bug in an earlier version of this patch, not in Theia).

**Dead ends ruled out along the way** (kept here so they don't get re-chased):

- The duplicate `registerDebugConfigurationProvider` call in Fix 1 is **not** the cause
  of this hang - reverting it to a single registration didn't change the outcome. Its
  own necessity remains unverified rather than confirmed either way.
- A breakpoint on the shared `resolveDebugConfigurationByResolversChain` helper hitting
  twice is expected, normal behavior (it's called once from `resolveDebugConfiguration`
  and again from `resolveDebugConfigurationWithSubstitutedVariables`) - not evidence of
  a duplicate-registration bug.
- Firefox DevTools' Sources panel appearing to show stale code, `console.log` calls
  embedded in frontend files never firing, and even a blocking `alert()` never
  triggering, all turned out to be the **same single cause**: see the next
  troubleshooting entry below. It looked like a browser-execution mystery for hours; it
  was actually the server silently sending stale pre-compressed bytes the whole time.

### Editing a frontend `.js` file has no effect in the browser, no matter what you try

If you patch a file under `theia/` that ends up served to the browser (anything in
`lib/frontend/`, not `extension.js` - see below) and the change never seems to take
effect - not after a hard reload, not after fully quitting and relaunching the browser,
not even in a completely different browser - check for a stale `.gz` sibling file
first, before doubting anything else.

The official `theia-ide` base image ships every frontend file with a **pre-built `.gz`
counterpart** (`bundle.js` + `bundle.js.gz`, `hosted-plugin.js` +
`hosted-plugin.js.gz`, etc). Its Express static server unconditionally serves the `.gz`
version to any client whose `Accept-Encoding` header includes `gzip` - which is every
real browser, always. Editing the plain `.js` file does nothing for real users unless
the `.gz` sibling is regenerated to match:

```
gzip -kf path/to/the/file.js
```

`curl` without an explicit `Accept-Encoding: gzip` header doesn't request the
compressed variant, so it always sees the correctly-patched plain file - which is
exactly what makes this so misleading. Every verification method that relies on `curl`
(including this repo's own `test/smoke-test.sh` HTTP checks) will report success while
every actual browser keeps silently running the original, unpatched code. Confirmed
directly: `curl -H "Accept-Encoding: gzip" <url> | gunzip` returns different content
than a plain `curl <url>` for a patched-but-not-regenerated file.

This is also why `extension.js` doesn't need this treatment: it's loaded by the
plugin-host process via Node's own `require()`, never served over HTTP at all, so there
is no `.gz` sibling to worry about for it - only files under `lib/frontend/` are
affected. The Dockerfile regenerates `hosted-plugin.js.gz` right after
`patch-debug-task-tracking.js` runs, since that's the one frontend file this repo
currently patches. If you add another frontend patch later, regenerate its `.gz` too.

## Documentation

User-facing *how* lives in this README. The *why* — project goals and non-goals, design
principles, and Architecture Decision Records for every non-trivial choice (two
containers, Debian 11 base, shared `/home/theia`, the Theia patches, the `~/garmin-dev/`
layout) — lives in [`docs/`](docs/README.md).

## Files

| File | Purpose |
|---|---|
| `theia/Dockerfile` | Theia + Monkey C extension image |
| `sdk-manager/Dockerfile` | SDK Manager GUI image |
| `docker-compose.yml` | Wires both up, reads paths/uid/gid from `.env` |
| `.env.example` | Template for `.env` (committed) |
| `.env` | Your actual machine-specific paths (gitignored) |
| `setup.sh` | One-shot bootstrap for a fresh machine |
