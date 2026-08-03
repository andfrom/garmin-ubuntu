// Applies two fixes for a real Theia <-> Monkey C extension incompatibility around
// starting a debug session ("Run App" / the green play button never completing).
// Both were found and verified via live container patching + browser breakpoint
// debugging; see README.md's Troubleshooting section for the full investigation.
//
// Usage: node patch-debug-task-tracking.js <extension.js path> <hosted-plugin.js path>
const fs = require("fs");
const [, , extensionPath, hostedPluginPath] = process.argv;

// Fix 1 (extension.js): the extension registers its "monkeyc" debug configuration
// provider with DebugConfigurationProviderTriggerKind.Dynamic. VS Code Desktop still
// routes a static launch.json entry's "Start Debugging" through that provider's
// resolveDebugConfiguration - Theia does not, so it was never being called at all.
// Registering the same provider a second time with the default (Initial) trigger kind
// makes Theia actually invoke resolution.
{
  let src = fs.readFileSync(extensionPath, "utf8");
  const needle = 'Cr=e.debug.registerDebugConfigurationProvider("monkeyc",new Pn,e.DebugConfigurationProviderTriggerKind.Dynamic),Dr=';
  const count = src.split(needle).length - 1;
  if (count !== 1) throw new Error(`Fix 1 needle found ${count} times in extension.js, expected 1`);
  src = src.split(needle).join(
    'Cr=e.debug.registerDebugConfigurationProvider("monkeyc",new Pn,e.DebugConfigurationProviderTriggerKind.Dynamic),e.debug.registerDebugConfigurationProvider("monkeyc",new Pn),Dr='
  );
  fs.writeFileSync(extensionPath, src);
  console.log("Fix 1 applied to", extensionPath);
}

// Fix 2 (hosted-plugin.js, part of the Theia-IDE base image itself): the extension's
// build-then-launch flow waits on tasks.onDidEndTaskProcess to know the build task
// finished. The build task is a VS Code CustomExecution task (the extension spawns and
// manages its own process via a Pseudoterminal) - and Theia's TaskServerImpl only ever
// fires onDidEndTaskProcess for tasks that are `instanceof ProcessTask`, never for
// CustomTask, unlike real VS Code Desktop. So that wait never resolves. onTaskExit
// *does* fire reliably for every task type, and its event object already carries the
// process exit code, so this synthesizes the missing $onDidEndTaskProcess notification
// from that reliable signal instead - and does so *before* $onDidEndTask, since
// TasksExtImpl.$onDidEndTask removes the task's execution record as part of its own
// cleanup, and $onDidEndTaskProcess needs that record to still exist when it runs
// (confirmed live: calling them in the wrong order throws "Task execution with id N is
// not found" - a bug in this patch itself, not in Theia).
{
  let src = fs.readFileSync(hostedPluginPath, "utf8");
  const needle = "this.taskWatcher.onTaskExit((event) => {\n            this.proxy.$onDidEndTask(event.taskId);\n        }));";
  const count = src.split(needle).length - 1;
  if (count !== 1) throw new Error(`Fix 2 needle found ${count} times in hosted-plugin.js, expected 1`);
  src = src.split(needle).join(
    "this.taskWatcher.onTaskExit((event) => {\n            if (event.code !== undefined) {\n                this.proxy.$onDidEndTaskProcess(event.code, event.taskId);\n            }\n            this.proxy.$onDidEndTask(event.taskId);\n        }));"
  );
  fs.writeFileSync(hostedPluginPath, src);
  console.log("Fix 2 applied to", hostedPluginPath);
}
