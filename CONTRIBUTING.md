# Contributing

Thanks for looking. This is a small project; the bar is "don't break the inner loop and
say why you changed what you changed".

## Setup

```
git clone <this repo> && cd garmin-ubuntu
./setup.sh
docker compose up -d theia
```

See the [README](README.md) for usage and troubleshooting. Building the images downloads
Garmin materials under Garmin's SDK License Agreement (see [License](README.md#license)).

## Before opening a pull request

1. **Run the smoke test:** `./test/smoke-test.sh`. It rebuilds both images with
   `--no-cache` and checks shared libraries, the extension unpack, and backend boot. CI
   runs the same script.
2. **Check the debug path by hand** if you touched `theia/`: open the IDE, open a Monkey C
   project, and confirm "Run App" reaches the simulator. That part is not automated yet
   (`docs/backlog.md`).
3. **Every patch to upstream code needs a row** in the README's "Patches applied, and
   what's needed to drop them" table: where it applies, why it exists, and what upstream
   change would let it be removed. A patch without a drop condition won't be merged.
   Patch steps must fail the build when their needle no longer matches.
4. **Frontend patches regenerate their `.gz` twin.** Anything under `lib/frontend/` is
   served pre-compressed to browsers; verify with `curl -H "Accept-Encoding: gzip"`.
5. **Non-trivial decisions get an ADR** in `docs/adr/` (template there). Principles
   with tests live in `docs/principles.md`; check your change against them.
6. **Troubleshooting entries are for failures actually hit and diagnosed** — symptom,
   the command that exposes the cause, the fix. No hypotheticals.

## Commit messages

Imperative subject line, body explaining *why*. No local paths, usernames, or tool/session
identifiers in commits or files.
