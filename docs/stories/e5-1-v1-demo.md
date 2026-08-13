# E5-1: v1 demo script passes end to end

**Related FR**: FR-8
**Priority**: high
**Estimate**: S

## Story
As the project owner, I want the six-step demo script from `docs/prd.md`
("Resolutions of the brief's open items §1") to pass against the real
Agent-Team repo, so that "v1 is done" is a checkable fact, not a judgment
call made at the end of the project.

## Acceptance criteria
- [ ] Given the TUI run from the Agent-Team repo root, when started with no
  flag, then it reports maintainer mode.
- [ ] Given the tree view, when rendered, then it shows exactly 11 agents,
  18 skills, 4 commands with load-edges between agents and the skills they
  both declare and load.
- [ ] Given `analyst.md` opened in the editor, when its `color` field is
  changed and saved, then the TUI confirms the write and
  `claude plugin validate ./plugins/agent-team` still exits 0.
- [ ] **Revised (PRD FR-5 correction)**: the editor cannot add `hooks:` — it
  adds no keys at all. Given a file whose frontmatter already carries
  `hooks`, `mcpServers`, or `permissionMode`, when the TUI scans it, then a
  `FORBIDDEN_FIELD` error is shown on the entity and in the findings panel,
  and every save attempt on that file is blocked until the field is removed
  via the editor's single removal affordance — the file is never left
  changed by a rejected save.
- [ ] Given the scanner run standalone (no TUI) against the same repo, when
  compared to what the TUI loaded, then the JSON content is identical.

### Edges
- [ ] Not applicable as a separate dimension — this story's whole purpose
  is running the FR-8 script as written; each of its six steps already
  carries its own edge/failure coverage in the stories that implement it
  (E1-E4).

### Failures
- [ ] Given any one of the six steps fails, the story is not done — this
  story does not pass partially.

## Out of scope for this story
- Building any new functionality — this story is pure integration
  verification of E1 through E4.

## Dependencies
E0-1, E1-1, E1-2, E1-3, E2-1, E2-2, E3-1, E3-2, E4-1, E4-2. (E0-1 because the
demo runs the shipped TUI, which requires a released binary; E4-3 not
required for this specific demo script, which runs in maintainer mode only —
but should be spot-checked separately before calling v1 fully done, since
FR-7 is in scope even though FR-8's literal six steps don't exercise it. E6-1
is also not exercised by this script, which invokes the TUI directly rather
than via the `commands/` entry.)

## Technical notes
Run this as the final gate before declaring v1 shipped. If any step fails,
the failure traces back to whichever story owns that behavior.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
