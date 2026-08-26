# Design Principles

**Status:** v1 — 2026-08-25 (backfilled; each principle is one the repo already obeys)

The rules the design must obey, in priority order. Each carries the test we hold work
against. Changing this list is an architectural decision — do it via an ADR.

## P1 — The host is only Docker plus an X server
Every library-version concern is resolved *inside* the images, pinned to their base
distribution. Nothing depends on the host's package versions.
*Test: the Dockerfiles and `setup.sh` reference no host package beyond Docker Engine,
`docker compose`, and `xhost`. A host upgrade requires zero changes to this repo.*

## P2 — One GUI process per container
Native GTK apps (`sdkmanager`, `simulator`) each own their container's foreground; they
are never combined with another long-running GUI in the same image.
*Test: `docker-compose.yml` has one service per GUI binary; the IDE container's only
foreground process is Theia's Node server. (ADR-0001.)*

## P3 — Data lives on the host, images are disposable
SDKs, device profiles, workspaces, and IDE config are bind-mounted from
`$CONNECTIQ_DATA_DIR`, `$WORKSPACES_DIR`, `$THEIA_CONFIG_DIR`. Rebuilding or deleting an
image loses nothing.
*Test: `docker compose down --rmi all`, rebuild, `up` — installed SDKs, recent
workspaces, and settings are all still there.*

## P4 — Both containers see the same `$HOME`
Garmin's tooling hardcodes `~/.Garmin/ConnectIQ` and persists *absolute* paths into it,
and Java resolves `user.home` via `getpwuid()`, not `$HOME`. Both containers therefore
run their user with the literal home `/home/theia`, and no other passwd entry may
resolve to a different home at the shared uid.
*Test: `java -XshowSettings:properties -version 2>&1 | grep user.home` prints
`/home/theia` in both images; `current-sdk.cfg` written by one container is valid in the
other. (ADR-0004.)*

## P5 — No binaries in git, no secrets in images
Third-party artifacts (the Monkey C VSIX, the SDK Manager zip) are fetched at build time
from their vendor URLs, version-pinned by build arg. Machine-specific values
(paths, uid/gid, `DISPLAY`) come from a gitignored `.env`; `.env.example` holds only
generic `__HOME__`-based placeholders.
*Test: `git ls-files` contains no `.vsix`, `.zip`, `.jar`, or `.env`; `grep -r
/home/ --include=*.md --include=*.yml --include=Dockerfile .` returns only the
container-internal `/home/theia`.*

## P6 — Every patch has a drop condition
Any modification to upstream code (Theia, the extension) is applied by a named, commented
step in the Dockerfile, is listed in the README's "Patches applied" table with its reason,
and states what upstream change would let it be removed.
*Test: for each `sed`/patch step in `theia/Dockerfile`, there is a matching table row;
for each row, the "Upstream status" column is non-empty. (ADR-0005.)*

## P7 — Verification goes through the same path the user takes
A check that can pass while the real thing fails is not a check. In particular: anything
served to the browser is verified with `Accept-Encoding: gzip` (the base image serves
pre-built `.gz` twins), and "installable" is never taken to mean "runnable" (`ldd`
against the actual binary, not `apt-get`'s exit code).
*Test: `test/smoke-test.sh` runs `ldd | grep 'not found'` against both GUI binaries, and
fetches the patched frontend file with `Accept-Encoding: gzip`, gunzips it, and asserts it
matches the plain file — so a stale `.gz` twin fails the build.*

## P8 — Troubleshooting is a record, not a guess
A troubleshooting entry is added only for a failure that was actually hit and diagnosed
here, and it says how it was diagnosed. Dead ends that cost real time are recorded so they
are not re-chased.
*Test: each entry names the observable symptom, the command that exposes the cause, and
the fix — no "try restarting" entries.*
