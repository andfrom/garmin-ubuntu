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
ARG MONKEYC_EXT_VERSION=1.1.2
RUN mkdir -p /opt/theia-plugins/monkey-c \
    && curl -fsSL "https://garmin.gallery.vsassets.io/_apis/public/gallery/publisher/garmin/extension/monkey-c/${MONKEYC_EXT_VERSION}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage" -o /tmp/monkey-c.vsix \
    && cd /opt/theia-plugins/monkey-c \
    && unzip -q /tmp/monkey-c.vsix \
    && rm /tmp/monkey-c.vsix \
    && chown -R theia:theia /opt/theia-plugins

ENV THEIA_DEFAULT_PLUGINS=local-dir:/opt/theia-plugins
ENV DISPLAY=:0

USER theia
