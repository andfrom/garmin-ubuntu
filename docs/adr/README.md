# Architecture Decision Records

One file per decision, numbered, never edited after acceptance except to change status
(e.g. *Superseded by NNNN*). Format: see [0000-template.md](0000-template.md).

Statuses: **Proposed** (drafted, awaiting review) → **Accepted** / **Rejected**; later
possibly **Superseded**.

ADRs 0001–0006 were backfilled on 2026-08-25 from decisions made 2026-08-02 → 03 and
recorded at the time only in commit messages and README prose; their `Date` is the date
of the original decision.

| # | Title | Status |
|---|---|---|
| [0001](0001-two-sibling-containers-not-one-image.md) | Two sibling containers, not one combined image | Accepted |
| [0002](0002-debian-11-base-for-legacy-webkit-stack.md) | Debian 11 base images for the legacy WebKit2GTK stack | Accepted |
| [0003](0003-fetch-vendor-artifacts-at-build-time.md) | Fetch vendor artifacts at build time; never commit binaries | Accepted |
| [0004](0004-shared-home-theia-across-both-containers.md) | Both containers use the literal home `/home/theia` | Accepted |
| [0005](0005-patch-upstream-in-dockerfile-with-drop-conditions.md) | Patch Theia/extension in the Dockerfile, each with a drop condition | Accepted |
| [0006](0006-consolidated-host-data-under-garmin-dev.md) | All host-side data under one directory, `~/garmin-dev/` | Accepted |
