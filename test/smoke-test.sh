#!/usr/bin/env bash
# Headless smoke test: catches the two failure classes that actually broke this project
# before (missing shared libraries in the GTK binaries, and broken image builds), without
# needing a GUI or a real browser. Runs against ephemeral containers/ports/dirs, so it's
# safe to run alongside an already-running `docker compose up -d theia`.
#
# What this does NOT check: that the Monkey C extension fully activates in a real
# frontend session (confirmed manually by opening http://localhost:3000 and checking
# `docker compose logs theia` for "Debug configuration provider has been registered:
# monkeyc"). Headless-browser automation of that check (snap Firefox --headless) proved
# unreliable in testing - it never triggered the frontend websocket connection - so this
# script deliberately doesn't fake it. Do that check by hand after any Dockerfile change
# that touches the extension or Theia version.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

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

echo
echo "==> $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
