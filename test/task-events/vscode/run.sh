#!/bin/sh
# Launch VS Code with the dev extension, wait for its DONE marker, print the log.
rm -f "$REPRO_LOG"; touch "$REPRO_LOG"
code --version | head -1 > /tmp/code-version.txt
xvfb-run -a code --no-sandbox --disable-gpu --disable-dev-shm-usage \
  --user-data-dir=/tmp/ud --extensions-dir=/tmp/ed --disable-workspace-trust \
  --disable-extensions --extensionDevelopmentPath=/ext /ws >/tmp/code.out 2>&1 &
for i in $(seq 1 120); do grep -q '^.*DONE$' "$REPRO_LOG" && break; sleep 1; done
echo "=== VS Code $(cat /tmp/code-version.txt) ==="; cat "$REPRO_LOG"
grep -q DONE "$REPRO_LOG" || { echo "--- timed out; code output:"; tail -30 /tmp/code.out; }
pkill -f /usr/share/code >/dev/null 2>&1; exit 0
