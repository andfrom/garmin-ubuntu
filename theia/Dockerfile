# Theia IDE preloaded with the Garmin Monkey C extension, for Connect IQ development.
#
# This is deliberately NOT the SDK Manager - the SDK Manager is a separate GUI-only
# image (see ../sdk-manager). Both containers share one host directory bind-mounted
# to $HOME/.Garmin/ConnectIQ: the SDK Manager installs/updates SDKs and device profiles
# there, and this image's Monkey C extension reads them from the same place.
#
# The SDK's native `simulator` binary (launched by the Monkey C debugger on "Run") is a
# GTK/WebKit2GTK app linked against the *old* webkit2gtk-4.0 / libsoup2.4 stack, which
# current Ubuntu releases no longer ship. This image's own base (Debian 11 bullseye)
# still carries them natively, so no patchelf/library surgery is needed - and it
# matches the sdk-manager image's library ABI exactly, since both read the very same
# bind-mounted SDK binaries. Because this all lives inside the container, it doesn't
# matter which Ubuntu version the host is running (24.04, 26.x, ...) - only Docker and
# an X server on the host are required.
FROM ghcr.io/eclipse-theia/theia-ide/theia-ide:1.60.100

USER root

# The base image's `theia` user is uid/gid 101, but bind-mounted host directories
# (workspaces, ConnectIQ SDK data) are owned by the host user - remap `theia` to match
# instead of fighting permissions at runtime (this bit earlier attempts: SDK-installed
# files showed up with a blank owner / group `messagebus` due to exactly this mismatch).
# theia's home dir itself (/home/theia) is NOT relocated - the base image's own launcher
# hardcodes /home/theia/applications/.../main.js as an absolute path, so moving the
# account's home (even with usermod -m, which relocates the actual files) breaks the
# container outright (learned by breaking it: "Cannot find module
# '/home/theia/applications/browser/lib/backend/main.js'").
#
# The base image also ships a pre-existing `node` user that happens to already sit at
# uid/gid 1000 - once `theia` is remapped to the same uid, both accounts resolve from
# that uid via getpwuid(), and glibc/the JVM pick whichever entry comes first in
# /etc/passwd (here: `node`, whose home is still the untouched default /home/node).
# This bit us for real: Java's `user.home` system property - which the Monkey C
# extension's bundled LanguageServer.jar uses to find ~/.Garmin/ConnectIQ - resolves via
# getpwuid(), not the $HOME env var, so setting ENV HOME alone was not enough; it kept
# resolving to /home/node regardless. Fix: repoint `node`'s passwd entry (not its files -
# nothing under the untouched /home/node matters) at theia's real, immovable home, so
# both accounts resolve to /home/theia regardless of which one getpwuid() picks.
ARG UID=1000
ARG GID=1000
RUN groupmod -o -g ${GID} theia \
    && usermod -o -u ${UID} -g ${GID} theia \
    && usermod -d /home/theia node \
    && chown -R theia:theia /home/theia

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless \
    libwebkit2gtk-4.0-37 \
    libsoup2.4-1 \
    libgtk-3-0 \
    libjpeg62-turbo \
    libsm6 \
    libusb-1.0-0 \
    ca-certificates \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/lib/x86_64-linux-gnu/libjpeg.so.62 /usr/lib/x86_64-linux-gnu/libjpeg.so.8

# Bake the Monkey C extension into the image itself (local-dir plugins are pre-unpacked
# directories with package.json + node_modules already present - no npm install needed).
ARG MONKEYC_EXT_VERSION=1.1.3
RUN mkdir -p /opt/theia-plugins/monkey-c \
    && curl -fsSL "https://garmin.gallery.vsassets.io/_apis/public/gallery/publisher/garmin/extension/monkey-c/${MONKEYC_EXT_VERSION}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage" -o /tmp/monkey-c.vsix \
    && cd /opt/theia-plugins/monkey-c \
    && unzip -q /tmp/monkey-c.vsix \
    && rm /tmp/monkey-c.vsix \
    && chown -R theia:theia /opt/theia-plugins

# Patch a genuine Theia/extension incompatibility: the extension waits for
# `tasks.onDidEndTaskProcess` and checks `e.execution.task.definition.type === "monkeyc"`
# to know its own build task finished, before it'll hand back a resolved debug
# configuration (which is what triggers spawning the actual debug adapter). That check
# is written for VSCode Desktop's behavior, where a custom task type is preserved in
# `definition.type`. Theia does something different by design (not a bug it intends to
# fix - see https://github.com/eclipse-theia/theia/issues/8822, closed as-is): it
# rewrites `definition.type` to the underlying execution type (e.g. "shell") and puts
# the original custom type in `definition.taskType` instead. The extension's check never
# matches under Theia, so it hangs forever - "Run"/"Debug" builds successfully (visible
# in the task terminal) but never proceeds any further, with no error anywhere. Patch
# every occurrence of the check to accept either field. The grep guard makes the build
# fail loudly if a new extension version changes the minified shape of that check -
# `sed` on its own silently matches nothing.
RUN EXT=/opt/theia-plugins/monkey-c/extension/dist/extension.js \
    && test "$(grep -o '"monkeyc"===e\.execution\.task\.definition\.type' "$EXT" | wc -l)" -ge 1 \
    && sed -i 's/"monkeyc"===e\.execution\.task\.definition\.type/("monkeyc"===e.execution.task.definition.type||"monkeyc"===e.execution.task.definition.taskType)/g' "$EXT" \
    && test "$(grep -o 'definition\.taskType' "$EXT" | wc -l)" -ge 1

# One more genuine Theia incompatibility around starting a debug session at all ("Run
# App" never completing, no error anywhere): Theia never fires onDidEndTaskProcess for
# CustomExecution tasks, which the extension awaits after its build. Found via live
# container patching and browser breakpoint debugging, then confirmed against Theia's
# and VS Code's sources; see README.md's Troubleshooting section for the full writeup.
# Applied by a helper script since it patches multi-line source in the Theia-IDE base
# image itself (not the extension), which is awkward to express as a single-line sed.
COPY patch-debug-task-tracking.js /tmp/patch-debug-task-tracking.js
RUN HP=/home/theia/applications/browser/lib/frontend/vendors-node_modules_theia_plugin-ext_lib_hosted_browser_hosted-plugin_js.js \
    && node /tmp/patch-debug-task-tracking.js "$HP" \
    && test "$(grep -c '_nativeProcessEnded' "$HP")" -ge 2 \
    && rm /tmp/patch-debug-task-tracking.js

# The base image ships every frontend (browser-served) file with a pre-built .gz
# sibling (bundle.js.gz, hosted-plugin.js.gz, ...), and its Express static server
# unconditionally serves the .gz version to any client advertising gzip support -
# which is every real browser, always. `curl` without matching Accept-Encoding
# doesn't, which is exactly what made this invisible: the plain .js file always
# looked correctly patched, while every actual browser silently kept executing the
# original, unpatched code with zero indication anything was wrong. Only the plugin
# frontend file patched above lives under lib/frontend (browser-served) - extension.js
# is loaded directly by the plugin-host's own `require()`, not served over HTTP, so it
# doesn't need this. Found the hard way; see README.md's Troubleshooting section.
RUN gzip -kf /home/theia/applications/browser/lib/frontend/vendors-node_modules_theia_plugin-ext_lib_hosted_browser_hosted-plugin_js.js

ENV THEIA_DEFAULT_PLUGINS=local-dir:/opt/theia-plugins
ENV DISPLAY=:0

USER theia
