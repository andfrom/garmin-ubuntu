# Backlog

Open items, roughly by value. Nothing here is a commitment; move an item into an ADR or a
commit when it is actually decided or done. Done items get deleted, not ticked.

## Upstream

- **File the two drafted Theia bug reports.** Drafts exist locally (gitignored
  `scratch/`) for (a) `TaskServerImpl.fireTaskExitedEvent` never firing
  `onDidEndTaskProcess` for `CustomTask`, and (b) `theia-ide`'s static server preferring
  stale pre-built `.gz` assets. Filing them is what makes Fix 2 and the `.gz`
  regeneration step droppable (README "Patches applied" table). Once filed, link the
  issue numbers in that table and the Dockerfile comments.
- **Verify whether Fix 1 (double `registerDebugConfigurationProvider`) is needed at
  all.** Reverting it did not change the Run App hang outcome; its necessity is
  unverified either way. Test: build with Fix 1 removed, confirm a static `launch.json`
  entry still resolves. Drop it if so.

## Automation

- **Detect new Theia and Monkey C extension releases; bump automatically unless
  something breaks.** Today both pins are hand-edited (`theia/Dockerfile`: `FROM
  ...theia-ide:1.60.100` and `ARG MONKEYC_EXT_VERSION=1.1.2`) and nothing notices when
  upstream moves. The SDK Manager has the opposite problem: its download URL is
  unversioned (`connectiq-sdk-manager-linux.zip`), so it floats silently on every
  `--no-cache` build.

  *Sources to watch:*
  - Theia: tags of `ghcr.io/eclipse-theia/theia-ide/theia-ide` (or releases of
    `eclipse-theia/theia-ide` on GitHub).
  - Monkey C: the VS Marketplace gallery — the same `garmin.gallery.vsassets.io` host the
    Dockerfile already downloads from, queried for the latest version, or the
    `extensionquery` API.
  - SDK Manager: no version endpoint; hash the downloaded zip and compare to a pinned
    checksum (which requires pinning it first — see Hardening).

  *Gate — what "nothing is broken" must mean, in order of cost:*
  1. Build succeeds with every patch needle matching. Fix 1 and Fix 2 already `throw`
     on a needle count ≠ 1; the `taskType` `sed` does **not** and must be given the same
     zero-match assertion first (prerequisite).
  2. `test/smoke-test.sh` passes (`ldd` clean, HTTP up, extension activation log line).
  3. The debug path works end-to-end — the only thing that actually proves a bump is
     safe, and the one check that does not exist headlessly yet (Hardening, first
     item). Until it does, a bump can only be *proposed*, not merged.

  *Mechanism, two viable shapes:*
  - **Renovate**-style: `FROM` tags are handled natively; `MONKEYC_EXT_VERSION` needs a
    custom regex manager with a custom datasource; the marketplace has no standard
    datasource, so this may need a small JSON shim. Produces PRs; CI on the PR runs the
    gate.
  - **Own scheduled job** (GitHub Actions cron, or a local systemd timer if the repo is
    not on GitHub — there is no `.github/` yet): a script queries the sources, edits the
    pins, runs the gate, and opens a PR or commits to a branch. More code, no
    datasource gymnastics, and the gate can include the X11-dependent parts on a
    self-hosted runner.

  *Policy:* auto-merge only for bumps that pass gate 3; anything failing gate 1 or 2 is
  a PR with the failing output attached, since a needle miss means an upstream change
  that needs a human to re-derive the patch. Theia and the extension should bump
  independently — a needle break on one must not block the other.

  *Prerequisites already listed elsewhere:* `taskType` zero-match assertion (this
  item), headless debug-path check (Hardening), base-image digest pin and SDK Manager
  checksum pin (Hardening).

## Hardening

- **Smoke test coverage for the debug path.** `test/smoke-test.sh` verifies libraries and
  HTTP; it does not yet exercise "Run App" end-to-end. A headless check that
  `$onDidEndTaskProcess` fires for a CustomTask would catch a regression in Fix 2
  without a human clicking.
- **Make the `taskType` `sed` fail on zero matches.** Fix 1/Fix 2 assert their needle
  count; the `sed` in `theia/Dockerfile` silently does nothing if the extension's
  minified code changes shape. Add a `grep -c` check before/after so a build with a
  non-matching needle fails, not passes.
- **Pin the base image digest**, not just the `1.60.100` tag, so a rebuild months later
  reproduces the same bytes the patches were verified against.
- **Pin the SDK Manager download.** `connectiq-sdk-manager-linux.zip` has no version in
  its URL; record its `sha256` in the Dockerfile and fail the build on mismatch, so an
  upstream change is a deliberate bump rather than a surprise.
- **Smoke-test the served (gzip) bytes.** `test/smoke-test.sh` checks HTTP reachability
  with plain `curl`, which never sees the `.gz` twin that real browsers get. Add a fetch
  of `hosted-plugin.js` with `Accept-Encoding: gzip`, gunzipped, asserting Fix 2's
  marker is present — the exact trap that cost hours here (README, "Editing a frontend
  `.js` file has no effect").

## Portability

- **Remote/ARM64 editing container.** Theia's image is multi-arch and the compiler is
  a JVM app; a `buildx --platform linux/arm64` variant of `theia/` for a cluster node is
  plausible. The simulator and SDK Manager stay local (goals.md, non-goals).
- **Wayland-native display path.** Not planned (goals.md), but worth re-checking if
  XWayland is ever dropped from a default Ubuntu session.

## Documentation

- **Split the README.** It is ~27 KB and mixes quick start with a multi-page debugging
  investigation. Candidate: move the "Run App hang" chain diagram and the `.gz` trap into
  `docs/` (e.g. `docs/investigations/`) and leave a short pointer in Troubleshooting.
