# Investigation: editing a frontend `.js` file has no effect in the browser

*Resolved. The Dockerfile regenerates the `.gz` twin of every frontend file it patches,
and `test/smoke-test.sh` checks the gzip-served bytes. The
[README Troubleshooting entry](../../README.md#editing-a-frontend-js-file-has-no-effect-in-the-browser-no-matter-what-you-try)
is the short version. This is the full mechanism; the upstream documentation request
drafted from it is tracked in [`docs/backlog.md`](../backlog.md) (Upstream).*

If you patch a file under `theia/` that ends up served to the browser (anything in
`lib/frontend/`, not `extension.js` - see below) and the change never seems to take
effect - not after a hard reload, not after fully quitting and relaunching the browser,
not even in a completely different browser - check for a stale `.gz` sibling file
first, before doubting anything else.

The official `theia-ide` base image ships every frontend file with a **pre-built `.gz`
counterpart** (`bundle.js` + `bundle.js.gz`, `hosted-plugin.js` +
`hosted-plugin.js.gz`, etc). Its Express static server unconditionally serves the `.gz`
version to any client whose `Accept-Encoding` header includes `gzip` - which is every
real browser, always. Editing the plain `.js` file does nothing for real users unless
the `.gz` sibling is regenerated to match:

```
gzip -kf path/to/the/file.js
```

`curl` without an explicit `Accept-Encoding: gzip` header doesn't request the
compressed variant, so it always sees the correctly-patched plain file - which is
exactly what makes this so misleading. Every verification method that relies on `curl`
(including this repo's own `test/smoke-test.sh` HTTP checks) will report success while
every actual browser keeps silently running the original, unpatched code. Confirmed
directly: `curl -H "Accept-Encoding: gzip" <url> | gunzip` returns different content
than a plain `curl <url>` for a patched-but-not-regenerated file.

This is also why `extension.js` doesn't need this treatment: it's loaded by the
plugin-host process via Node's own `require()`, never served over HTTP at all, so there
is no `.gz` sibling to worry about for it - only files under `lib/frontend/` are
affected. The Dockerfile regenerates `hosted-plugin.js.gz` right after
`patch-debug-task-tracking.js` runs, since that's the one frontend file this repo
currently patches. If you add another frontend patch later, regenerate its `.gz` too.
