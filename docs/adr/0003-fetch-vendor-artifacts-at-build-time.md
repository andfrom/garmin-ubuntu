# 0003 — Fetch vendor artifacts at build time; never commit binaries

**Status:** Accepted (backfilled 2026-08-25 from the 2026-08-02 initial commit)
**Date:** 2026-08-02

## Context

The images need two third-party artifacts: the Garmin Monkey C VS Code extension (a
`.vsix` from the Visual Studio Marketplace) and the Connect IQ SDK Manager (a `.zip`
from `developer.garmin.com`). Both are closed-source, both are versioned by the vendor,
and both are large enough to make git history painful. The repo is intended to be
public.

## Decision

Download both at `docker build` time with `curl` from the vendor's URL, with the
version pinned by a Dockerfile build arg (`MONKEYC_EXT_VERSION` for the extension). No
binary artifacts are committed.

## Alternatives considered

- **Commit the `.vsix`/`.zip`** — redistribution rights are unclear, git history bloats,
  and it hides which version is actually in use.
- **Git LFS** — solves size, not licensing; adds a tooling requirement to a repo whose
  goal is "clone and go".
- **Theia's Open VSX registry at runtime** — the Monkey C extension is only published
  to the Microsoft marketplace, and a runtime install is not reproducible.

## Consequences

- Builds require network access and depend on the vendor keeping the URL stable. If
  Garmin moves or removes a download, the build breaks loudly rather than silently
  running stale code.
- Reproducibility rests on the version pin plus the vendor not re-publishing under the
  same version; a checksum pin is a possible hardening (backlog).
- Patches that touch the extension's minified `extension.js` (see 0005) are coupled to
  `MONKEYC_EXT_VERSION` and must be re-verified on any bump.
