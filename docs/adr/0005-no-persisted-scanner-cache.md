# ADR-0005: Scanner JSON is never persisted between sessions; the TUI re-scans instead of invalidating

- **Status**: accepted
- **Date**: 2026-08-13
- **Deciders**: `architect`, resolving the PRD's Data-section open question

## Context

The PRD leaves it to `architect` whether the TUI caches scanner JSON to disk
between sessions, while stating that the JSON is "a derived, disposable artifact
— never the source of truth, regenerated on each run."

The numbers that decide it: [observed] the tree is 11 agents, 18 skills and 4
commands — 33 frontmatter blocks, roughly 33 small file reads. The PRD's own NFR
budgets under 2 seconds for this tree, and it is [inferred] well under that,
since the existing `run-gates.sh` does considerably more work per invocation.
[inferred] A cache would therefore save at most a second or two, once per
session, at the cost of a staleness-detection mechanism.

Staleness detection is not cheap to get right. The scan depends on the content
of every file, the *set* of files, and directory membership (an empty
`skills/<x>/` is itself a finding). A correct fingerprint has to cover creation
and deletion, not just modification — and mtime granularity on Windows plus
Git checkouts that rewrite mtimes make an mtime-only fingerprint unreliable.
The cheap version of the cache is the wrong version.

## Decision

**No disk cache. No cache file, no cache directory, no fingerprint.**

- The TUI runs the scanner at startup and holds the result **in memory** for the
  session.
- `r` re-scans on demand.
- The TUI re-scans **automatically after every successful write**, because a
  write changes the very tree-wide facts (name uniqueness, edges) that the next
  validation depends on.
- Between re-scans the in-memory copy can go stale if another process edits the
  tree. That is **not** handled by a cache layer. It is handled at the only
  point where staleness can cause damage — the write path, which re-checks the
  target file's existence, size and mtime against what was read before writing,
  and refuses if they changed (ADR-0006 and `docs/architecture.md`, Failure
  modes).
- CI runs the scanner directly and never sees this question at all.

## Options considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| **No cache; re-scan (chosen)** | Nothing to invalidate; the tree on screen is the tree on disk as of a known moment; zero new code | Every start pays the full scan; a foreign edit is invisible until `r` | — |
| Cache keyed on an mtime+size fingerprint of every scanned file | Fast start | Must also cover added and deleted files and directories; [inferred] unreliable across Git checkouts and Windows mtime granularity | Saves ~1s and buys a class of wrong-tree bugs |
| Cache keyed on a content hash of the tree | Correct | Hashing every file costs about what scanning them costs | Pays the price it was meant to avoid |
| Cache keyed on git HEAD + dirty state | Cheap key | Wrong for uncommitted working-tree edits, which is the maintainer's normal state | Wrong exactly when the tool is being used |
| Filesystem watching instead of a cache | Live updates, no staleness | [assumed] recursive watch behaviour is inconsistent across platforms, notably on Windows; a new source of missed and duplicated events, and another dependency | Not worth it for a viewer refreshed by one keypress |

## Consequences

### Positive
- There is no cache-invalidation bug, because there is no cache. This removes
  the single most common defect class in tools of this shape.
- The `generatedAt` timestamp in the header is always honest and always refers
  to a scan that actually ran in this session.
- The scanner stays a pure function of the tree, which is what lets CI and the
  TUI share it (ADR-0006).

### Negative
- **A maintainer editing files in another editor sees a stale tree until they
  press `r`.** We are explicitly choosing a manual refresh over a live one. The
  header shows the scan time so staleness is visible rather than assumed.
- Startup pays the scan every time. If the tree ever grows to the 500-file scale
  the PRD uses as an edge case, startup becomes noticeable and this ADR should
  be revisited — with a measurement, not a guess.

### What this makes harder later
Nothing structural. Adding a cache later is a self-contained change behind the
"run the scanner, get a document" call, and it will land with the fingerprint
question properly costed instead of assumed away. That is the right order.
