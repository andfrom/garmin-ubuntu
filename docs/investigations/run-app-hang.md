# Investigation: "Run App" / Start Debugging hangs forever, no error anywhere

*Resolved. This is the full write-up of a bug that is now fixed by
`theia/patch-debug-task-tracking.js`; the [README Troubleshooting entry](../../README.md#run-app--start-debugging-hangs-forever-no-error-anywhere)
is the short version. Kept because the diagnosis spans three OS processes and was hard to
pin down — worth not re-deriving. The upstream bug report drafted from this is tracked in
[`docs/backlog.md`](../backlog.md) (Upstream).*

Fixed - `patch-debug-task-tracking.js` patches Theia for this (see the Dockerfile
comment above it), and the Dockerfile also regenerates `hosted-plugin.js.gz` right after
(see the next section below - that part turned out to be essential, not optional).
Documenting the full investigation here since each stage runs in a different process,
which made this hard to pin down: three independent execution contexts are involved,
only one of which (the frontend) is reachable via ordinary browser DevTools.

**Execution contexts involved** (which OS process each stage runs in):

- **Frontend** - plain JS in the browser tab. Reachable via Firefox/Chrome DevTools'
  normal Sources/Console panels.
- **Backend** - Theia's main Node.js process (`lib/backend/main.js`), which spawns the
  plugin-host. Not directly reachable via a browser debugger; observable via
  `docker logs`.
- **Plugin-host** - a *separate* Node.js child process (`lib/backend/plugin-host`, shown
  in logs as `PLUGIN_HOST(pid)`) that actually runs the Monkey C extension's own code
  (`extension.js`). Also not reachable via a browser debugger - its `console.log` output
  goes to `docker logs` (its stdout is piped through the backend process), and attaching
  a real debugger to it requires Node's inspector protocol (`kill -USR1 <pid>`), which
  Firefox cannot speak (its `about:debugging` remote-debugging feature only talks to
  other Firefox instances, not Node's V8 Inspector protocol - no combination of
  host/port there will work). Chrome/Chromium's `chrome://inspect` can, if available.

**Functional blocks involved** (which subsystem owns each stage, independent of which
process it happens to run in):

- **Debug Configuration Provider** - the extension's `Pn` class plus Theia's own
  `PluginDebugService`/`resolveDebugConfigurationByResolversChain`. Job: turn a
  `launch.json` entry into a fully-resolved config, including making sure a build has
  run first.
- **Tasks API bridge** - the VS Code Tasks API surface (`vscode.tasks.executeTask`,
  `vscode.tasks.onDidEndTaskProcess`) as exposed to extensions. Implemented by a
  `TasksExtImpl`-style class in the plugin-host, backed by a matching bridge class in
  the frontend that forwards real task events across the RPC boundary.
- **Task Server** - Theia's own core task-lifecycle engine (`@theia/task`, backend). Job:
  actually spawn the task's process and broadcast its lifecycle (created/exited) to every
  connected frontend.
- **Terminal widget** - a UI-only component that separately detects when a task's
  underlying process exits, purely to update what's shown in the terminal panel
  ("BUILD SUCCESSFUL", "Terminal will be reused by tasks"). Not wired to the Tasks API
  bridge at all - this is exactly why the terminal can show success while the extension
  never finds out.
- **Debug Adapter launch** - the step that never gets reached: actually starting the
  debug session once configuration resolution returns.

**The chain, and where it breaks** (`[Process / Functional block]` per stage):

```
[Frontend / Debug Configuration Provider]
User clicks "Run App" (static launch.json entry, type: monkeyc)
        │
        ▼
[Frontend / Debug Configuration Provider] Theia calls resolveDebugConfiguration
        │  → RPC to [Plugin-host / Debug Configuration Provider] extension's Pn.resolveDebugConfiguration
        │  → fills in defaults (type/name/request), returns almost instantly
        ▼
[Frontend / Debug Configuration Provider] Theia calls resolveDebugConfigurationWithSubstitutedVariables
        │  → RPC to [Plugin-host / Debug Configuration Provider] extension's Pn.resolveDebugConfigurationWithSubstitutedVariables
        ▼
[Plugin-host / Tasks API bridge] Extension calls vscode.tasks.executeTask() to start the Monkey C build
        │  → Promise resolves almost immediately (VS Code API contract: this means
        │    "task started", NOT "task finished" - confirmed via trace, not a bug)
        ▼
[Plugin-host / Tasks API bridge] Extension registers a ONE-TIME onDidEndTaskProcess
listener and returns a Promise that only resolves when THAT listener fires
        │
        ▼
[Backend / Task Server] Build genuinely runs (monkeybrains.jar) and succeeds
        │  ✔ confirmed independently: [Frontend / Terminal widget] shows
        │    "BUILD SUCCESSFUL" / "Terminal will be reused by tasks" - a separate
        │    detection mechanism, NOT wired to the Tasks API bridge below
        ▼
  ┌────────────────────────────────────────────────────────────────────┐
  │ SHOULD happen:                                                     │
  │ [Backend / Task Server] detects the process exited                 │
  │   → broadcasts a task-exit event to [Frontend / Tasks API bridge]  │
  │   → forwards it to [Plugin-host / Tasks API bridge] over RPC       │
  │   → [Plugin-host / Tasks API bridge] onDidEndTaskProcess fires     │
  │   → [Plugin-host / Debug Configuration Provider] Promise resolves  │
  │   → resolveDebugConfigurationWithSubstitutedVariables returns      │
  │   → [Frontend / Debug Adapter launch] Theia launches the adapter   │
  │                                                                     │
  │ ACTUALLY happens without the patch: none of it. The build task is  │
  │ VS Code CustomExecution task (the extension spawns and manages its │
  │ own process via a Pseudoterminal, rather than using Theia's        │
  │ ShellExecution/ProcessExecution types). Theia's own                │
  │ TaskServerImpl.fireTaskExitedEvent only ever fires                 │
  │ onDidEndTaskProcess for tasks that are `instanceof ProcessTask` -  │
  │ never for CustomTask, unlike real VS Code Desktop. So              │
  │ onDidEndTaskProcess genuinely never fires for this task, by        │
  │ design, on Theia's end - confirmed via live tracing on both the    │
  │ frontend and the plugin-host independently. → extension's Promise  │
  │ never resolves → hangs forever, no error.                          │
  └────────────────────────────────────────────────────────────────────┘
```

`patch-debug-task-tracking.js` synthesizes the missing `$onDidEndTaskProcess`
from `onTaskExit`, which *does* fire reliably for every task type and already carries
the exit code. **Ordering matters**: it must fire `$onDidEndTaskProcess` *before*
`$onDidEndTask` - the latter deletes the task's execution record from the plugin-host's
internal map as part of its own cleanup (`TasksExtImpl.$onDidEndTask`), so calling them
in the wrong order makes `$onDidEndTaskProcess` throw `Error: Task execution with id N
is not found` (a bug in an earlier version of this patch, not in Theia).

**Dead ends ruled out along the way** (kept here so they don't get re-chased):

- A second `registerDebugConfigurationProvider` registration (an earlier "Fix 1" in
  this repo, added on the theory that Theia skips a `Dynamic`-trigger provider's
  `resolveDebugConfiguration` for static `launch.json` entries) is **not** needed and
  was removed. Neither Theia (`PluginDebugService`, which filters resolvers by type
  only) nor VS Code (`debugConfigurationManager.resolveConfigurationByProviders`, same)
  consults `triggerKind` when *resolving* - it only affects *providing* configurations.
  Worse, two providers of the same type both run the build-and-wait resolver, so the
  extra registration made every "Run App" build twice.
- A breakpoint on the shared `resolveDebugConfigurationByResolversChain` helper hitting
  twice is expected, normal behavior (it's called once from `resolveDebugConfiguration`
  and again from `resolveDebugConfigurationWithSubstitutedVariables`) - not evidence of
  a duplicate-registration bug.
- Firefox DevTools' Sources panel appearing to show stale code, `console.log` calls
  embedded in frontend files never firing, and even a blocking `alert()` never
  triggering, all turned out to be the **same single cause**: see the next
  troubleshooting entry below. It looked like a browser-execution mystery for hours; it
  was actually the server silently sending stale pre-compressed bytes the whole time.
