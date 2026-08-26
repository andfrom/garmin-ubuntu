// Minimal reproduction: does tasks.onDidEndTaskProcess fire for a CustomExecution task?
// Runs automatically on activation; logs to $REPRO_LOG (default /tmp/repro-task-events.log).
// Control: the same listeners on a ShellExecution task, which must fire everywhere.
const vscode = require("vscode");
const fs = require("fs");
const cp = require("child_process");
const LOG = process.env.REPRO_LOG || "/tmp/repro-task-events.log";
const log = (m) => fs.appendFileSync(LOG, `${new Date().toISOString()} ${m}\n`);

class Pty {
  constructor(exitCode) {
    this.exitCode = exitCode;
    this.w = new vscode.EventEmitter(); this.c = new vscode.EventEmitter();
    this.onDidWrite = this.w.event; this.onDidClose = this.c.event;
  }
  open() {
    const p = cp.spawn("sh", ["-c", `echo hello-from-child; exit ${this.exitCode}`]);
    p.stdout.on("data", (d) => this.w.fire(d.toString().replace(/\n/g, "\r\n")));
    p.on("exit", (code) => { log(`[custom] child exited code=${code}; closeEmitter.fire(${code})`); this.w.fire(`exit ${code}\r\n`); this.c.fire(code); });
  }
  close() {}
}

function runTask(label, task) {
  return new Promise((resolve) => {
    const seen = [];
    const subs = [
      vscode.tasks.onDidStartTask((e) => e.execution.task.name === task.name && (seen.push("onDidStartTask"), log(`[${label}] onDidStartTask`))),
      vscode.tasks.onDidStartTaskProcess((e) => e.execution.task.name === task.name && (seen.push("onDidStartTaskProcess"), log(`[${label}] onDidStartTaskProcess processId=${e.processId}`))),
      vscode.tasks.onDidEndTaskProcess((e) => e.execution.task.name === task.name && (seen.push("onDidEndTaskProcess"), log(`[${label}] onDidEndTaskProcess exitCode=${e.exitCode} definition.type=${e.execution.task.definition.type} definition.taskType=${e.execution.task.definition.taskType}`))),
      vscode.tasks.onDidEndTask((e) => e.execution.task.name === task.name && (seen.push("onDidEndTask"), log(`[${label}] onDidEndTask`))),
    ];
    log(`[${label}] executeTask()`);
    vscode.tasks.executeTask(task).then(() => log(`[${label}] executeTask() promise resolved`), (err) => log(`[${label}] executeTask() rejected: ${err}`));
    setTimeout(() => { subs.forEach((s) => s.dispose()); log(`[${label}] RESULT after 15s: ${seen.join(",") || "NO EVENTS"}`); resolve(seen); }, 15000);
  });
}

async function activate(ctx) {
  log(`activate: appName="${vscode.env.appName}" version=${vscode.version} uiKind=${vscode.env.uiKind} appHost=${vscode.env.appHost}`);
  ctx.subscriptions.push(vscode.tasks.registerTaskProvider("repro", { provideTasks: () => [], resolveTask: (t) => t }));
  await new Promise((r) => setTimeout(r, 3000));
  const scope = (vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0]) || vscode.TaskScope.Workspace;
  const custom = new vscode.Task({ type: "repro", kind: "custom" }, scope, "repro-custom", "repro", new vscode.CustomExecution(async () => new Pty(7)));
  const shell = new vscode.Task({ type: "repro", kind: "shell" }, scope, "repro-shell", "repro", new vscode.ShellExecution("sh -c 'echo hello-from-shell; exit 3'"));
  const a = await runTask("custom", custom);
  const b = await runTask("shell", shell);
  log(`SUMMARY custom(CustomExecution)=[${a.join(",")}] shell(ShellExecution)=[${b.join(",")}]`);
  log("DONE");
}
module.exports = { activate, deactivate() {} };
