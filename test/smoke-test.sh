#!/usr/bin/env bash
# Headless smoke test: catches the failure classes that actually broke this project
# before (missing shared libraries in the GTK binaries, broken image builds, patched
# frontend files masked by a stale .gz twin, and a GUI that won't start). Runs against
# ephemeral containers/ports/dirs, so it's safe alongside a running `docker compose up
# -d theia`. Needs only Docker (the SDK Manager GUI check adds Xvfb in a throwaway image),
# so it runs in CI.
#
# NOT checked here (needs a browser or an SDK, so it lives in the other test scripts):
# that the Monkey C extension activates in a real frontend session (test/task-events.sh)
# and that "Run App" reaches the simulator end-to-end (test/debug-path.sh). See
# test/README.md.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

PASS=0
FAIL=0
pass() { echo "OK:   $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP_WORKSPACE=$(mktemp -d)
TMP_THEIA_CONFIG=$(mktemp -d)
CONTAINER=garmin-theia-smoketest
PORT=13100

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$TMP_WORKSPACE" "$TMP_THEIA_CONFIG"
}
trap cleanup EXIT

# --profile sdk-manager: `profiles:` gates `docker compose build` too, not just `up` -
# omitting this flag silently skips building sdk-manager entirely and this script would
# happily test whatever stale image happened to already have that tag.
# --no-cache: a cached build was separately observed to silently reuse a stale,
# already-broken layer during testing, masking a missing-library regression entirely.
echo "==> Building images (--no-cache)"
if docker compose --profile sdk-manager build --no-cache >/tmp/smoke-test-build.log 2>&1; then
  pass "docker compose build"
else
  fail "docker compose build (see /tmp/smoke-test-build.log)"
  echo "Build failed, skipping remaining checks."
  exit 1
fi

echo "==> Checking for missing shared libraries (the libwebkit2gtk/libsoup/libSM/libusb class of bug)"
check_ldd() {
  local label="$1" image="$2" bin="$3"
  shift 3
  local missing
  missing=$(docker run --rm --entrypoint bash "$@" "$image" -c "ldd '$bin' 2>&1 | grep -i 'not found' || true")
  if [ -n "$missing" ]; then
    fail "$label: missing libraries:"$'\n'"$missing"
  else
    pass "$label: all shared libraries resolved"
  fi
}
check_ldd "sdk-manager image / sdkmanager binary" garmin-sdk-manager:latest /opt/sdk-manager/bin/sdkmanager

# The SDK's `simulator` binary isn't baked into the theia image (it comes from the
# bind-mounted SDK data dir), so only check it if a real SDK is already installed.
if [ -f .env ]; then
  # shellcheck disable=SC1091
  CONNECTIQ_DATA_DIR=$(grep -E '^CONNECTIQ_DATA_DIR=' .env | cut -d= -f2-)
fi
# shellcheck disable=SC2012  # controlled glob under the SDK dir; ls is fine and simpler than find here
SIM_BIN=$(ls "${CONNECTIQ_DATA_DIR:-/nonexistent}"/Sdks/*/bin/simulator 2>/dev/null | head -1 || true)
if [ -n "$SIM_BIN" ]; then
  check_ldd "theia image / SDK simulator binary" garmin-theia:latest "/sdk-check/$(basename "$SIM_BIN")" \
    -v "$SIM_BIN:/sdk-check/$(basename "$SIM_BIN"):ro"
else
  echo "SKIP: no installed SDK found in CONNECTIQ_DATA_DIR - run the sdk-manager service first to check the simulator binary too"
fi

echo "==> Checking the Monkey C extension unpacked correctly"
EXT_CHECK=$(docker run --rm --entrypoint bash garmin-theia:latest -c \
  "cat /opt/theia-plugins/monkey-c/extension/package.json 2>/dev/null" | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('name'), d.get('version'))" 2>&1)
if [[ "$EXT_CHECK" == monkey-c* ]]; then
  pass "monkey-c extension present and valid ($EXT_CHECK)"
else
  fail "monkey-c extension missing or corrupt: $EXT_CHECK"
fi

echo "==> Booting theia and checking the backend comes up clean"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" -p "127.0.0.1:${PORT}:3000" \
  -v "$TMP_WORKSPACE:/home/theia/workspaces" \
  -v "$TMP_THEIA_CONFIG:/home/theia/.theia-ide" \
  garmin-theia:latest >/dev/null

BOOTED=0
for _ in $(seq 1 20); do
  if docker logs "$CONTAINER" 2>&1 | grep -q "Finished starting backend application"; then
    BOOTED=1
    break
  fi
  sleep 1
done
if [ "$BOOTED" = 1 ]; then
  pass "theia backend started"
else
  fail "theia backend did not report started within 20s (see: docker logs $CONTAINER)"
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}" || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "theia web UI reachable (HTTP $HTTP_CODE)"
else
  fail "theia web UI not reachable (HTTP $HTTP_CODE)"
fi

# The bytes a browser actually gets: the base image ships pre-compressed .gz twins of every
# frontend file and the server prefers them for any client accepting gzip (every browser),
# so a patched plain file with a stale .gz twin looks fine to plain curl and is a no-op in
# reality. Check the patched file through the gzip path, and that both paths agree.
echo "==> Checking the patched frontend file as served with gzip (what browsers receive)"
HP=vendors-node_modules_theia_plugin-ext_lib_hosted_browser_hosted-plugin_js.js
PLAIN=$(curl -s "http://127.0.0.1:${PORT}/${HP}" | grep -c "_nativeProcessEnded" || true)
GZ=$(curl -s -H "Accept-Encoding: gzip" "http://127.0.0.1:${PORT}/${HP}" | gunzip 2>/dev/null | grep -c "_nativeProcessEnded" || true)
if [ "${GZ:-0}" -ge 2 ] && [ "$GZ" = "$PLAIN" ]; then
  pass "patched hosted-plugin.js served identically via gzip (${GZ} markers)"
else
  fail "gzip-served hosted-plugin.js differs from plain (plain=${PLAIN} gzip=${GZ}) - stale .gz twin?"
fi

echo "==> Checking the SDK Manager GUI actually launches (headless, under Xvfb)"
# A GTK/WebKit app that is missing a library or can't reach a display dies immediately.
# So: start Xvfb, launch sdkmanager, and assert it is still alive and has opened an X
# window after a few seconds. Uses a throwaway image = the real sdk-manager image + Xvfb,
# so the production image stays free of test-only packages. Needs no host X server, so it
# runs in CI.
GUI_IMG=garmin-sdk-manager-guitest
if docker build -q -t "$GUI_IMG" - >/dev/null 2>&1 <<'DOCKERFILE'
FROM garmin-sdk-manager:latest
USER root
RUN apt-get update && apt-get install -y --no-install-recommends xvfb x11-utils && rm -rf /var/lib/apt/lists/*
USER garmin
DOCKERFILE
then
  GUI_OUT=$(docker run --rm --entrypoint bash "$GUI_IMG" -c '
    export DISPLAY=:99
    Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &
    sleep 2
    /opt/sdk-manager/bin/sdkmanager >/tmp/sdkm.log 2>&1 &
    SDKM=$!
    sleep 12
    if kill -0 "$SDKM" 2>/dev/null && xwininfo -root -tree 2>/dev/null | grep -qi ""sdkmanager""; then
      echo GUI_OK
    else
      echo GUI_FAIL; tail -5 /tmp/sdkm.log
    fi' 2>/dev/null)
  if printf '%s' "$GUI_OUT" | grep -q GUI_OK; then
    pass "sdk-manager GUI launches and opens a window (GTK/WebKit init OK)"
  else
    fail "sdk-manager GUI did not launch (crashed or no window) - $(printf '%s' "$GUI_OUT" | tail -3 | tr '\n' ' ')"
  fi
  docker rmi -f "$GUI_IMG" >/dev/null 2>&1 || true
else
  fail "could not build the sdk-manager GUI test image"
fi

echo
echo "==> $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
