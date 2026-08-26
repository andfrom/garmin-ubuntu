#!/usr/bin/env bash
# Regression test for theia/patch-debug-task-tracking.js: which `vscode.tasks.*` events
# fire for a CustomExecution task and for a ShellExecution task. A tiny extension
# (test/task-events/ext) runs both tasks on activation and logs the events; this script
# runs it inside the built image and asserts each task kind gets onDidEndTaskProcess
# exactly once. Options:
#   --vanilla   also run the unmodified theia-ide base image (documents the upstream gap)
#   --vscode    also build+run VS Code Desktop under Xvfb (documents the reference behavior)
# Local check, not CI: needs Docker, Node >= 18 and a Chromium/Chrome on the host
# (CHROME=/path overrides autodetection). Nothing here touches ~/garmin-dev or the
# running garmin-theia container.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
PASS=0; FAIL=0
pass() { echo "OK:   $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
VANILLA=0; VSCODE=0
for a in "$@"; do case "$a" in --vanilla) VANILLA=1;; --vscode) VSCODE=1;; *) echo "unknown option $a"; exit 2;; esac; done
[ -d test/node_modules/puppeteer-core ] || (cd test && npm install --silent --no-audit --no-fund >/dev/null)
EXT="$PWD/test/task-events/ext"
CONTAINER=garmin-theia-taskevents
PORT=13210
cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; rm -rf "${TMP_WS:-}"; }
trap cleanup EXIT

run_theia() { # $1 image -> prints the SUMMARY line
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  TMP_WS=$(mktemp -d)
  docker run -d --name "$CONTAINER" -p "127.0.0.1:${PORT}:3000" \
    -e THEIA_DEFAULT_PLUGINS=local-dir:/repro-plugins -e REPRO_LOG=/tmp/repro-task-events.log \
    -v "$EXT:/repro-plugins/repro-task-events:ro" -v "$TMP_WS:/home/theia/ws" "$1" >/dev/null
  for _ in $(seq 1 30); do docker logs "$CONTAINER" 2>&1 | grep -q "Finished starting backend" && break; sleep 1; done
  (cd test && node lib-open-theia.mjs "http://127.0.0.1:${PORT}/#/home/theia/ws" 50000) >/dev/null 2>&1
  docker exec "$CONTAINER" cat /tmp/repro-task-events.log 2>/dev/null | grep '^.*SUMMARY' | sed 's/.*SUMMARY //'
}
events() { echo "$1" | sed -n "s/.*$2([A-Za-z]*)=\[\([^]]*\)\].*/\1/p"; }
count() { echo "$1" | tr ',' '\n' | grep -c "^$2\$"; }

echo "==> Patched image (garmin-theia:latest)"
S=$(run_theia garmin-theia:latest); echo "    $S"
C=$(events "$S" custom); H=$(events "$S" shell)
if [ "$(count "$C" onDidEndTaskProcess)" = 1 ]; then pass "CustomExecution: onDidEndTaskProcess fires exactly once"; else fail "CustomExecution: onDidEndTaskProcess count=$(count "$C" onDidEndTaskProcess), events=[$C]"; fi
if [ "$(count "$H" onDidEndTaskProcess)" = 1 ]; then pass "ShellExecution: onDidEndTaskProcess fires exactly once (no duplicate)"; else fail "ShellExecution: onDidEndTaskProcess count=$(count "$H" onDidEndTaskProcess), events=[$H]"; fi
if [ "$(count "$C" onDidEndTask)" = 1 ] && [ "$(count "$H" onDidEndTask)" = 1 ]; then pass "onDidEndTask fires once per task"; else fail "onDidEndTask counts custom=$(count "$C" onDidEndTask) shell=$(count "$H" onDidEndTask)"; fi

if [ "$VANILLA" = 1 ]; then
  BASE=$(sed -n 's/^FROM \([^ ]*\).*/\1/p' theia/Dockerfile | head -1)
  echo "==> Vanilla base image ($BASE) - informational"
  S=$(run_theia "$BASE"); echo "    $S"
  C=$(events "$S" custom)
  [ "$(count "$C" onDidEndTaskProcess)" = 0 ] && echo "    (upstream gap still present: no onDidEndTaskProcess for CustomExecution - the patch is still needed)" \
    || echo "    (upstream now fires onDidEndTaskProcess for CustomExecution - the patch may be droppable; see README 'Patches applied')"
fi

if [ "$VSCODE" = 1 ]; then
  echo "==> VS Code Desktop (reference) - informational"
  docker build -q -t garmin-ubuntu-test-vscode test/task-events/vscode >/dev/null && \
  S=$(timeout 300 docker run --rm -v "$EXT:/ext:ro" garmin-ubuntu-test-vscode 2>/dev/null | sed -n 's/.*SUMMARY //p'); echo "    $S"
  C=$(events "$S" custom)
  if [ "$(count "$C" onDidEndTaskProcess)" = 1 ]; then pass "VS Code fires onDidEndTaskProcess for CustomExecution (reference behavior holds)"; else fail "VS Code reference behavior changed: [$C]"; fi
fi
echo "==> Monkey C extension activation (default plugins, real image)"
# Separate from the task-event checks above: those load ONLY the probe extension (via
# THEIA_DEFAULT_PLUGINS override) to isolate task behavior, so the Monkey C extension is
# absent there. Here we boot the image as shipped - no plugin override - so Monkey C
# loads, connect a browser to spawn the plugin host, and assert it activated. Needs only
# Docker + a browser (no SDK), same as the checks above.
ACT=garmin-theia-activation
docker rm -f "$ACT" >/dev/null 2>&1 || true
ACT_WS=$(mktemp -d)
docker run -d --name "$ACT" -p "127.0.0.1:13211:3000" -v "$ACT_WS:/home/theia/ws" garmin-theia:latest >/dev/null
for _ in $(seq 1 30); do docker logs "$ACT" 2>&1 | grep -q "Finished starting backend" && break; sleep 1; done
(cd test && node lib-open-theia.mjs "http://127.0.0.1:13211/#/home/theia/ws" 30000) >/dev/null 2>&1
if docker logs "$ACT" 2>&1 | grep -q "Debug configuration provider has been registered: monkeyc"; then
  pass "Monkey C extension activated (debug configuration provider registered)"
else
  fail "Monkey C extension did not activate - no registration line in logs"
fi
docker rm -f "$ACT" >/dev/null 2>&1 || true; rm -rf "$ACT_WS"

echo; echo "==> $PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]
