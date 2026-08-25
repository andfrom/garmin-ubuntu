// Applies one fix for a real Theia <-> Monkey C extension incompatibility around
// starting a debug session ("Run App" / the green play button never completing).
// Found and verified via live container patching + browser breakpoint debugging, and
// confirmed against Theia's and VS Code's sources; see README.md's Troubleshooting
// section for the full investigation.
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
// (confirmed live: calling them in the wrong order throws "Task execution with id N is
// not found" - a bug in an earlier version of this patch, not in Theia; the same ordering
// constraint is documented in eclipse-theia/theia PR #8141).
{
  let src = fs.readFileSync(hostedPluginPath, "utf8");
  const needle = "this.taskWatcher.onTaskExit((event) => {\n            this.proxy.$onDidEndTask(event.taskId);\n        }));";
  const count = src.split(needle).length - 1;
  if (count !== 1) throw new Error(`patch needle found ${count} times in hosted-plugin.js, expected 1`);
  src = src.split(needle).join(
    "this.taskWatcher.onTaskExit((event) => {\n            if (event.code !== undefined) {\n                this.proxy.$onDidEndTaskProcess(event.code, event.taskId);\n            }\n            this.proxy.$onDidEndTask(event.taskId);\n        }));"
  );
  fs.writeFileSync(hostedPluginPath, src);
  console.log("onDidEndTaskProcess patch applied to", hostedPluginPath);
}
