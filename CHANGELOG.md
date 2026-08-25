# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Two-container Garmin Connect IQ development environment for Ubuntu 24.04+: Eclipse
  Theia IDE with the Monkey C extension baked in, and the Connect IQ SDK Manager, both
  Debian 11-based so Garmin's GTK/WebKit2GTK binaries run without library surgery.
- `setup.sh` one-shot bootstrap (`.env` generation, data directories, X access, build)
  and `docker-compose.yml` wiring with the SDK Manager profile-gated for on-demand use.
- Shared, bind-mounted SDK/device data (`~/garmin-dev/` layout by default) so both
  containers see the same installed SDKs, and existing native `~/.Garmin/ConnectIQ`
  installs can be reused.
- Working build → simulator → debug flow from the IDE, via two documented patches to
  Theia/extension integration gaps (a `taskType` compatibility fix in the extension and a
  synthesized `onDidEndTaskProcess` for CustomExecution tasks in Theia), with `.gz`
  asset regeneration so patched frontend files actually reach browsers.
- Headless smoke test (`test/smoke-test.sh`) covering image builds, shared-library
  resolution of the GTK binaries, extension unpack, and backend boot; run in CI via
  GitHub Actions on every push and pull request.
- Documentation: README with verified troubleshooting entries, `docs/` with project
  goals, design principles, Architecture Decision Records, and backlog.
- MIT license for the repository's own content, with the Garmin SDK License Agreement
  scope for build-time downloads spelled out.
