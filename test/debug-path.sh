#!/usr/bin/env bash
# End-to-end "Run App" check against the RUNNING garmin-theia container: opens the given
# workspace headlessly, presses F5, and verifies from the container that exactly one
# build ran, the simulator started, and the Monkey C debug adapter was launched.
# Usage: test/debug-path.sh <workspace-name> [port]
# Prerequisites (local only, not CI): `docker compose up -d theia`; an SDK and devices
# installed via sdk-manager; a developer key; the workspace under $WORKSPACES_DIR with a
# launch.json (type "monkeyc"); a valid X grant (`xhost +si:localuser:$(whoami)`) so the
# simulator can open; Node >= 18 and a Chromium/Chrome on the host (CHROME=/path).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
WS=${1:?usage: test/debug-path.sh <workspace-name> [port]}; PORT=${2:-3000}
PASS=0; FAIL=0
pass() { echo "OK:   $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
docker inspect garmin-theia >/dev/null 2>&1 || { echo "garmin-theia is not running (docker compose up -d theia)"; exit 2; }
[ -d test/node_modules/puppeteer-core ] || (cd test && npm install --silent --no-audit --no-fund >/dev/null)
BEFORE=$(docker logs garmin-theia 2>&1 | grep -c "Created new custom task")
SINCE=$(date -u +%Y-%m-%dT%H:%M:%S)
echo "==> Opening workspace '$WS' on :$PORT and pressing F5 (this takes ~2 minutes)"
(cd test && node debug-path.mjs "$WS" "$PORT") || fail "browser driver failed"
AFTER=$(docker logs garmin-theia 2>&1 | grep -c "Created new custom task")
BUILDS=$((AFTER - BEFORE))
[ "$BUILDS" = 1 ] && pass "exactly one build task ran" || fail "expected 1 build task, saw $BUILDS"
docker exec garmin-theia pgrep -f "DebugServer.jar" >/dev/null && pass "Monkey C debug adapter (DebugServer.jar) is running" || fail "debug adapter not running - 'Run App' did not get past the build (see docker logs garmin-theia)"
docker exec garmin-theia pgrep -x simulator >/dev/null && pass "simulator is running" || fail "simulator not running"
if docker logs --since "$SINCE" garmin-theia 2>&1 | grep -q "AWTError"; then fail "build hit java.awt.AWTError (X grant lapsed? see README Troubleshooting)"; fi
echo "    screenshot: test/out/debug-path.png"
# Leave the IDE as we found it: end the session's processes we started.
docker exec garmin-theia sh -c 'pkill -f DebugServer.jar; pkill -x simulator' >/dev/null 2>&1 || true
echo; echo "==> $PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]
