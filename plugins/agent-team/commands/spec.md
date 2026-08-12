---
description: Produce planning artifacts only - brief, PRD, architecture, UI spec - without writing any implementation code.
argument-hint: [what to specify]
---

Produce planning artifacts for: **$ARGUMENTS**

Write documents only. Do not implement anything, and do not create stub files.

Run as far down this chain as the request needs, then stop:

1. `analyst` → `docs/brief.md`
2. `pm` → `docs/prd.md` and `docs/stories/*.md`
3. `architect` → `docs/architecture.md`, `docs/adr/*.md`, diagrams
4. `ux-designer` → `docs/design-system.md`, `docs/ui-spec.md` (skip if there is no UI)

Check in with the user after the PRD before continuing to architecture and design.

If an upstream artifact is missing, say so and stop rather than inventing its
contents. A PRD built on a guessed brief is worse than no PRD.

Report which artifacts you wrote and every `[OPEN: ...]` question that still
needs the user to answer it.
