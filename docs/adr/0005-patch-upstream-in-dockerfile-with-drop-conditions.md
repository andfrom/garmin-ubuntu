# 0005 — Patch Theia/extension in the Dockerfile, each patch with a stated drop condition

**Status:** Accepted (backfilled 2026-08-25 from commits `44c21a9` 2026-08-02 and
`7ac1126`/`c86d8d9` 2026-08-03). The "Fix 1" registration this ADR mentions was later
removed as redundant (it doubled every build and rested on a premise Theia's and VS
Code's sources contradict); see the "dead ends" section of
[`docs/investigations/run-app-hang.md`](../investigations/run-app-hang.md) and git history.
**Date:** 2026-08-03

## Context

The Monkey C extension is built and tested against VS Code Desktop; Theia's VS Code API
compatibility has gaps that break the extension's "Run App"/debug flow:

- Theia rewrites a task's `definition.type` and moves the extension's custom type to
  `definition.taskType`; the extension only checks `.type`. Intentional Theia behavior
  (eclipse-theia/theia#8822), not going to change.
- Theia's `TaskServerImpl.fireTaskExitedEvent` never fires `onDidEndTaskProcess` for a
  `CustomTask`, so the extension's build-then-debug Promise never resolves: "Run App"
  hangs forever with no error.
- The base image serves pre-built `.gz` twins of every frontend file in preference to the
  plain file, so patching a frontend file has no effect on real browsers unless the `.gz`
  is regenerated.

Forking Theia or the extension is out of proportion for a single-purpose dev image.

## Decision

Apply targeted patches at image build time — a `sed` for the `taskType` check, and
`theia/patch-debug-task-tracking.js` for the debug-provider registration (Fix 1) and the
synthesized `$onDidEndTaskProcess` (Fix 2) — followed by regenerating the `.gz` sibling of
every patched frontend file.

Every patch must be listed in the README's "Patches applied, and what's needed to drop
them" table with: where it applies, why it exists, and its upstream status or drop
condition. A patch without a drop condition is not accepted.

## Alternatives considered

- **Fork Theia and build a custom image** — a full Theia build for a two-function fix;
  the maintenance cost dwarfs the patch.
- **Fork the extension** — closed-source, minified; a `sed` on the minified bundle is the
  same thing with less pretence.
- **Wait for upstream** — one of the gaps is closed as-intended; the other two are not
  yet filed (drafts exist; backlog). Waiting means no working debugger.
- **Bypass the extension's task tracking with a custom launch task** — would work
  around Fix 2 but reimplement the extension's build logic; more surface, less fidelity.

## Consequences

- The image is not vanilla `theia-ide`; the README table is the single place to check
  whether a patch can go.
- Fix 2's event order is load-bearing (`$onDidEndTaskProcess` must precede
  `$onDidEndTask`, which deletes the execution record) — documented in the script and
  README.
- Any patch to a file under `lib/frontend/` *must* regenerate its `.gz`, and any
  verification of such a patch *must* request gzip encoding (principles.md P7).
- Patches are coupled to `theia-ide:1.60.100` and `MONKEYC_EXT_VERSION`; bumping either
  requires re-verifying every `sed`/patch still matches (backlog).
- Fix 1's necessity is unverified; it stays only until tested (backlog).
  (Later tested against Theia's and VS Code's sources and removed as redundant; see
  [`docs/investigations/run-app-hang.md`](../investigations/run-app-hang.md).)
