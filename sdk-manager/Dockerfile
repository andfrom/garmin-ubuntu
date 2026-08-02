# Garmin Connect IQ SDK Manager - standalone GUI-only image.
#
# The upstream sdkmanager binary is a native GTK/WebKit2GTK app linked against the
# *old* webkit2gtk-4.0 / libsoup2.4 stack (confirmed via ldd on a real install, and
# cross-checked against the Arch AUR package for connectiq-sdk-manager, which has to
# patchelf to newer libs precisely because Arch no longer ships the old ones). Debian
# 11 (bullseye) still carries the old stack natively, so we base on it instead of
# patching the binary - and it also matches the Theia image's own base OS, so the
# bind-mounted `simulator` binary from the SDK works identically in both containers.
# Since this all lives inside the container, the host's own Ubuntu version (24.04,
# 26.x, ...) doesn't matter - only Docker and an X server on the host are required.
FROM debian:11-slim

ARG UID=1000
ARG GID=1000

RUN apt-get update && apt-get install -y --no-install-recommends \
    libwebkit2gtk-4.0-37 \
    libsoup2.4-1 \
    libgtk-3-0 \
    libjpeg62-turbo \
    libsm6 \
    ca-certificates \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/lib/x86_64-linux-gnu/libjpeg.so.62 /usr/lib/x86_64-linux-gnu/libjpeg.so.8

RUN groupadd -g ${GID} garmin \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash garmin

WORKDIR /opt/sdk-manager
RUN curl -fsSL https://developer.garmin.com/downloads/connect-iq/sdk-manager/connectiq-sdk-manager-linux.zip -o sdkmanager.zip \
    && unzip -q sdkmanager.zip \
    && rm sdkmanager.zip \
    && chmod +x bin/sdkmanager \
    && chown -R garmin:garmin /opt/sdk-manager

USER garmin
ENV HOME=/home/garmin
ENV DISPLAY=:0

# The SDK Manager installs/updates SDKs and device profiles into $HOME/.Garmin/ConnectIQ
# at runtime - bind-mount that path from the host so Theia's Monkey C extension (running
# in the sibling container) can see the same installed SDKs and devices.
ENTRYPOINT ["/opt/sdk-manager/bin/sdkmanager"]
