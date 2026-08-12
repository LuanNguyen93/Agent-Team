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
├── brief.md
├── prd.md
├── architecture.md
├── design-system.md
├── ui-spec.md
├── adr/0001-<slug>.md
└── stories/<epic>-<n>-<slug>.md
```

Check whether the project already has a docs convention and follow it instead.
Do not impose this layout on a repo that has its own.
