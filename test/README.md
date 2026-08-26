# Tests

Three checks, in increasing order of what they need to run.

| Check | What it proves | Needs | In CI? |
|---|---|---|---|
| `smoke-test.sh` (8 checks) | Both images build; the GTK binaries' shared libraries all resolve; the Monkey C extension unpacked; the Theia backend boots and serves HTTP; the patched frontend file is served identically over gzip (what browsers get); and the SDK Manager GUI actually launches and opens a window under Xvfb. | Docker only. Rebuilds with `--no-cache`. | **Yes** — `.github/workflows/smoke-test.yml`, every push/PR (alongside shellcheck, `setup.sh --no-build`, `docker compose config`, and an arm64 build of the Theia image). |
| `task-events.sh` (4 checks) | The Theia patch makes `tasks.onDidEndTaskProcess` fire **exactly once** for a `CustomExecution` task (the bug it fixes) and not twice for a `ShellExecution` task (a regression an earlier patch caused); and the Monkey C extension activates in a real frontend session. `--vanilla` also runs the unpatched base image to show the upstream gap is still there; `--vscode` builds VS Code Desktop under Xvfb to show the reference behavior. | Docker, Node ≥ 18, and a Chromium/Chrome on the host (`CHROME=/path` to override autodetection). | No — needs a browser. |
| `debug-path.sh <workspace> [port]` | End-to-end "Run App" against the **running** `garmin-theia` container: pressing F5 runs exactly one build, launches the simulator, and starts the Monkey C debug adapter. | The above, plus `docker compose up -d theia`, an installed SDK + devices, a developer key, a workspace with a `monkeyc` `launch.json`, and a valid X grant (`xhost +si:localuser:$(whoami)`). | No — needs a real SDK, a key, and a display. |

```sh
./test/smoke-test.sh
./test/task-events.sh --vanilla        # add --vscode for the VS Code reference run
./test/debug-path.sh AccelLogger
```

`node_modules/` (puppeteer-core) is installed on first run of the browser-based checks and
is gitignored. Screenshots land in `test/out/` (gitignored).

## Layout

- `smoke-test.sh` — the CI check, self-contained.
- `task-events.sh` + `task-events/ext/` (the probe extension) + `task-events/vscode/`
  (a Debian + VS Code Desktop + Xvfb image for the reference run).
- `debug-path.sh` + `debug-path.mjs` — the F5 driver.
- `lib-open-theia.mjs`, `lib-chrome.mjs` — shared helpers.
