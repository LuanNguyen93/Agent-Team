---
name: artifact-templates
description: Templates and quality bars for planning artifacts - project brief, PRD, architecture doc, ADR, and user story. Use when producing any of these documents so downstream agents receive a predictable shape.
when_to_use: Writing a brief, PRD, architecture doc, ADR, or story. Do NOT use for code comments or commit messages.
---

# Planning artifacts

Each artifact exists to be **consumed by the next role**. Write for that reader,
not for a filing cabinet. If a section would not change what the next person
does, cut it.

The chain:

```
brief  →  PRD  →  architecture  →  story  →  plan  →  code
```

Each link must be traceable to the one before. A requirement nobody can trace to
a problem is scope creep with paperwork.

## Templates

Full templates live alongside this skill. Read the one you need:

- `references/brief.md` — project brief (analyst → PM)
- `references/prd.md` — product requirements (PM → architect)
- `references/architecture.md` — technical design (architect → planner)
- `references/adr.md` — architecture decision record
- `references/story.md` — user story with acceptance criteria (PM → planner)
- `docs/prototype.html` — self-contained clickable bio-adaptive HTML prototype (`ux-designer` → human visual review & `frontend-implementer`, generated and audited via `bio_design_gate.py`)

## Rules that apply to all of them

**Write in English.** All artifacts, headings, and body text are English, so
the documents stay portable across teams and tools.

**Acceptance criteria must be checkable.** "Fast" is not a criterion; "responds
under 300ms at p95 with 1k rows" is. If you cannot describe how to check it, you
do not yet understand the requirement.

**Mark unknowns explicitly.** Use `[OPEN: question]` inline. An artifact that
hides its uncertainty behind confident prose costs more than one that admits it.

**Record what is out of scope.** Unstated exclusions get built by accident.

**Keep them short.** A PRD nobody reads is worse than a page that gets read. Cut
any section that restates another document.

**Date and attribute decisions.** Especially ADRs — the value is in knowing what
was true when the choice was made.

## Where files go

```
docs/
├── brief.md          # ONE canonical active brief (SSOT)
├── recon.md          # optional: clean-room screen/flow/entity map (market-recon)
├── reviews.csv       # optional: verbatim linked public reviews (market-recon)
├── feedback.md       # optional: ranked review themes from reviews.py
├── features.csv      # optional: feature parity matrix scored by parity.py
├── prd.md            # ONE canonical active PRD (SSOT)
├── architecture.md   # ONE canonical active architecture doc (SSOT)
├── tokens.json       # machine-readable design tokens checked by contrast.py
├── design-system.md  # ONE canonical active design system (SSOT)
├── ui-spec.md        # ONE canonical active UI spec (SSOT)
├── brand.json        # optional: competitor names/domains/hex colours for sweep.py
├── adr/0001-<slug>.md
├── stories/<epic>-<n>-<slug>.md
└── archive/          # superseded phase/historical docs stamped "Status: Superseded"
```

### Big-Tech SSOT & Anti-Doc-Sprawl Rule (Stripe / Linear / Uber Standard)

Never create competing phase-suffixed files in `docs/` (`brief-v2.md`, `prd-new.md`, `architecture-phase2.md`, `plan-e7.md`). Leaving multiple versions of a spec in `docs/` destroys transparency and causes downstream agents to read stale requirements:

1. **In-Place Canonical Update**: Always update the single canonical file (`docs/brief.md`, `docs/prd.md`, `docs/architecture.md`, `docs/ui-spec.md`) in place.
2. **Supersede & Archive When Replacing a Phase**: If an older phase's document must be preserved for historical audit, run:
   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/garbage_sweep.py" . --archive-stale-docs
   ```
   which stamps the old file with `Status: Superseded by docs/<canonical>.md` and moves it into `docs/archive/`.
3. **Immutable ADRs**: ADRs in `docs/adr/` are never overwritten; when a decision changes, write a new ADR and mark the old ADR's status header `Status: Superseded by ADR-XXXX`.

Check whether the project already has a docs convention and follow it instead.
Do not impose this layout on a repo that has its own.
