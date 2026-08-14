# E2-1: Detect maintainer vs. user mode at run root

**Related FR**: FR-2
**Priority**: high
**Estimate**: M

## Story
As a user of the TUI in either context, I want it to correctly tell whether
it's running inside the Agent-Team repo itself or inside a project that has
installed the plugin, so that it scans and offers to edit the right files
without me having to specify this every time.

## Acceptance criteria
- [ ] Given the Agent-Team repo root, when the TUI starts with no flag, then
  it reports maintainer mode in its header before any other content renders.
- [ ] Given a project root with agent-team installed as a plugin (no
  `plugins/agent-team/.claude-plugin/plugin.json` of its own), when the TUI
  starts with no flag, then it reports user mode.
- [ ] Given a detected mode, when the TUI's header renders, then the active
  mode is always visibly displayed — never left implicit.

### Edges
- [ ] Empty: a root with no signal of either mode at all (see E2-2 for the
  required behavior — this story only needs the detector to correctly
  report "no match," not the blocking behavior).
- [ ] One: exactly one signal present — unambiguous, detects correctly.
- [ ] Many: a root nested inside another agent-team checkout (both signals
  present) — detector reports the conflict rather than picking one silently
  (see E2-2 for override requirement).
- [ ] Far too many: not applicable — mode is binary per run, no scaling
  edge here.

### Failures
- [ ] When the detection mechanism itself errors (e.g. permission denied
  reading `.claude-plugin/plugin.json`), the TUI reports the error instead
  of defaulting silently to either mode.

## Out of scope for this story
- The `--mode` override flag and the blocking behavior on ambiguity/failure
  (E2-2).
- What each mode actually permits editing (E4 stories).

## Dependencies
None structurally, but pairs with E1 since the detected mode determines
which scanner invocation (E1-1) runs.

## Technical notes
Exact detection mechanism (which files/paths signal "installed plugin") is
explicitly `architect`'s design job per `docs/prd.md` — this story
implements whatever `architect` specifies, following the proposed rule
shape in the PRD (detect via `.claude-plugin/plugin.json` name match, or an
installed-plugin marker).

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
