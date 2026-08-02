#!/usr/bin/env bash
# Bootstrap this Garmin Connect IQ dev environment on a fresh Ubuntu 24.04+ machine.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "==> Checking prerequisites"
command -v docker >/dev/null 2>&1 || { echo "docker not found - install Docker Engine first"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "docker compose plugin not found"; exit 1; }
command -v xhost >/dev/null 2>&1 || echo "WARNING: xhost not found (x11-xserver-utils) - GUI windows won't be reachable without it"

if [ ! -f .env ]; then
  echo "==> Generating .env from .env.example"
  sed -e "s|__HOME__|$HOME|g" \
      -e "s|^HOST_UID=.*|HOST_UID=$(id -u)|" \
      -e "s|^HOST_GID=.*|HOST_GID=$(id -g)|" \
      -e "s|^DISPLAY=.*|DISPLAY=${DISPLAY:-:0}|" \
      .env.example > .env
else
  echo "==> .env already exists, leaving it as-is"
fi

# shellcheck disable=SC1091
source .env
mkdir -p "$CONNECTIQ_DATA_DIR" "$WORKSPACES_DIR" "$THEIA_CONFIG_DIR"

if command -v xhost >/dev/null 2>&1; then
  echo "==> Granting local containers access to the X server"
  xhost "+si:localuser:$(whoami)" || echo "WARNING: xhost grant failed - GUI containers may not be able to open windows"
fi

echo "==> Building images"
docker compose build

echo
echo "Setup complete. Start the IDE with:"
echo "  docker compose up -d theia"
echo "Then open http://localhost:3000"
echo
echo "Install/update the SDK or device profiles on demand with:"
echo "  docker compose --profile sdk-manager up sdk-manager"
