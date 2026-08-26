// Applies one fix for a real Theia <-> Monkey C extension incompatibility around
// starting a debug session ("Run App" / the green play button never completing).
// Confirmed against Theia's and VS Code's sources; the full investigation is in
// docs/investigations/run-app-hang.md.
//
// Usage: node patch-debug-task-tracking.js <hosted-plugin.js path>
const fs = require("fs");
const [, , hostedPluginPath] = process.argv;
if (!hostedPluginPath) throw new Error("usage: patch-debug-task-tracking.js <hosted-plugin.js path>");

// hosted-plugin.js is part of the Theia-IDE base image itself. The extension's
// build-then-launch flow waits on tasks.onDidEndTaskProcess to know the build task
// finished. The build task is a VS Code CustomExecution task (the extension spawns and
// manages its own process via a Pseudoterminal) - and Theia's TaskServerImpl only ever
// fires onDidEndTaskProcess for tasks that are `instanceof ProcessTask`, never for
// CustomTask, unlike VS Code (whose terminalTaskSystem fires processEnded for every task
// with a terminal, custom executions included). So that wait never resolves. onTaskExit
// *does* fire reliably for every task type, and its event object already carries the
// process exit code, so this synthesizes the missing $onDidEndTaskProcess notification
// from that reliable signal instead - and does so *before* $onDidEndTask, since
// TasksExtImpl.$onDidEndTask removes the task's execution record as part of its own
// cleanup, and $onDidEndTaskProcess needs that record to still exist when it runs
// (calling them in the wrong order throws "Task execution with id N is not found" - a
// bug in an earlier version of this patch, not in Theia; the same ordering constraint is
// documented in eclipse-theia/theia PR #8141).
{
  let src = fs.readFileSync(hostedPluginPath, "utf8");

  // Part A: remember every task for which Theia itself already sent
  // $onDidEndTaskProcess (ProcessTask - shell/process executions). The task server
  // broadcasts onDidEndTaskProcess *before* onTaskExit for those, over the same ordered
  // channel, so by the time onTaskExit arrives we know whether to synthesize or not.
  // Without this, process tasks get the event twice (verified with a repro extension:
  // a ShellExecution task fired onDidEndTaskProcess twice under an earlier version of
  // this patch).
  const nativeNeedle = "this.toDispose.push(this.taskWatcher.onDidEndTaskProcess((event) => {\n            if (event.code !== undefined) {\n                this.proxy.$onDidEndTaskProcess(event.code, event.taskId);\n            }\n        }));";
  const nativeCount = src.split(nativeNeedle).length - 1;
  if (nativeCount !== 1) throw new Error(`native onDidEndTaskProcess needle found ${nativeCount} times in hosted-plugin.js, expected 1`);
  src = src.split(nativeNeedle).join(
    "this.toDispose.push(this.taskWatcher.onDidEndTaskProcess((event) => {\n            if (event.code !== undefined) {\n                (this._nativeProcessEnded || (this._nativeProcessEnded = new Set())).add(event.taskId);\n                this.proxy.$onDidEndTaskProcess(event.code, event.taskId);\n            }\n        }));"
  );

  // Part B: synthesize $onDidEndTaskProcess from onTaskExit for every task Theia did
  // NOT already cover (i.e. CustomTask), before $onDidEndTask.
  const exitNeedle = "this.taskWatcher.onTaskExit((event) => {\n            this.proxy.$onDidEndTask(event.taskId);\n        }));";
  const exitCount = src.split(exitNeedle).length - 1;
  if (exitCount !== 1) throw new Error(`onTaskExit needle found ${exitCount} times in hosted-plugin.js, expected 1`);
  src = src.split(exitNeedle).join(
    "this.taskWatcher.onTaskExit((event) => {\n            if (this._nativeProcessEnded && this._nativeProcessEnded.delete(event.taskId)) {\n                // Theia already sent $onDidEndTaskProcess for this (process) task\n            } else if (event.code !== undefined) {\n                this.proxy.$onDidEndTaskProcess(event.code, event.taskId);\n            }\n            this.proxy.$onDidEndTask(event.taskId);\n        }));"
  );
  fs.writeFileSync(hostedPluginPath, src);
  console.log("onDidEndTaskProcess patch applied to", hostedPluginPath);
}
