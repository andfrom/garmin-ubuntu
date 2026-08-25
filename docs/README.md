# Documentation

Where the *why* of this repo lives. The top-level `README.md` is the *how* (quick start,
usage, troubleshooting) and stays the entry point for users; everything here is for
maintainers and contributors deciding what to change and why.

| Doc | What it holds | Changes when |
|---|---|---|
| [goals.md](goals.md) | What the project is for, who it serves, explicit non-goals | Scope is deliberately widened or narrowed |
| [principles.md](principles.md) | Rules the design must obey, each with a test | A principle is added, dropped, or reprioritized (via an ADR) |
| [adr/](adr/README.md) | Architecture Decision Records — one file per decision, immutable once accepted | Every non-trivial, hard-to-reverse choice |
| [backlog.md](backlog.md) | Open items, ordered roughly by value; not a commitment | Continuously |

## Conventions

- **Decisions go in ADRs, not in commit messages or README prose.** The README may
  *explain* a decision for users, but the record of alternatives and consequences is
  the ADR. Link from README to the ADR where helpful, not the other way round.
- **ADRs are append-only.** Never edit an accepted ADR except to change its status
  (`Superseded by NNNN`). To change a decision, write a new ADR.
- **Principles carry tests.** A principle with no way to check it is an aspiration,
  not a principle; put it in `goals.md` instead.
- **Only version-controlled material is referenced.** Docs never depend on paths or
  files outside this repo (the one exception is `.gitignore`, whose job that is).
  Drafts in `scratch/` are gitignored working material — a tracked doc may note that
  a draft exists, but must stand on its own without it.
- **Dates are absolute** (`2026-08-03`), never "last week".
