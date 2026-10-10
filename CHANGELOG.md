# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Image builds failed with apt 404s: Debian 11 reached end of life on 2026-08-31 and its
  security packages left deb.debian.org. Both Dockerfiles now fetch from
  archive.debian.org, whose bullseye indexes are byte-identical, so the installed
  versions are unchanged.

### Changed

- The smoke-test workflow also runs weekly, so breakage outside the repo surfaces
  within days rather than on the next push.

## [0.1.0] - 2026-08-26

First public release.

### Added

- Two-container Garmin Connect IQ development environment for Ubuntu 24.04+: Eclipse
  Theia IDE that fetches the Monkey C extension from the VS Marketplace at build time,
  and the Connect IQ SDK Manager, both
  Debian 11-based so Garmin's GTK/WebKit2GTK binaries run without library surgery.
- `setup.sh` one-shot bootstrap (`.env` generation, data directories, X access, build)
  and `docker-compose.yml` wiring with the SDK Manager profile-gated for on-demand use.
- Shared, bind-mounted SDK/device data (`~/garmin-dev/` layout by default) so both
  containers see the same installed SDKs, and existing native `~/.Garmin/ConnectIQ`
  installs can be reused.
- Working build → simulator → debug flow from the IDE, via documented patches to
  Theia/extension integration gaps (a `taskType` compatibility fix in the extension and a
  synthesized `onDidEndTaskProcess` for CustomExecution tasks in Theia), with `.gz`
  asset regeneration so patched frontend files actually reach browsers. Each patch fails
  the build if its target no longer matches, and is listed with a drop condition in the
  README.
- Tests under `test/`: a headless smoke test (image builds, GTK shared-library
  resolution, extension unpack, backend boot, the gzip-served frontend bytes, and a
  headless SDK Manager GUI launch under Xvfb); a task-event regression test that pins the
  Theia patch's behavior against VS Code's; and an end-to-end "Run App" debug-path check.
- Continuous integration (GitHub Actions) on every push and pull request: shellcheck,
  `setup.sh --no-build`, `docker compose config` validation, the smoke test, and an
  `arm64` build of the Theia image (which the image supports).
- Build reproducibility and portability: the base image is pinned by digest, the SDK
  Manager archive by `sha256`, and the JVM runs headless so builds do not depend on an X
  server; the Theia image builds for `linux/arm64`.
- Documentation: README with verified troubleshooting entries, `docs/` with project
  goals, design principles, Architecture Decision Records, and backlog.
- MIT license for the repository's own content, with the Garmin SDK License Agreement
  scope for build-time downloads spelled out.
