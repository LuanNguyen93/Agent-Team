# E10-1: Web app shell + launch command

**Related FR**: FR-7
**Priority**: high
**Estimate**: M

## Story
As a dashboard user, I want a single local command that starts the data
server and opens a browser tab to the dashboard, so that I don't have to
run multiple steps to visualize this repo's agent-team install.

## Acceptance criteria
- [ ] Given the command is run from the repo root, when it executes, then
  the local server (E8-1) starts, binds localhost-only, and a browser tab
  opens showing the dashboard shell for this repo.

### Edges
- [ ] Empty: N/A.
- [ ] One / Many / Far too many: N/A for this story (shell only).

### Failures
- [ ] Given the command is run a second time while an instance is already
  running, it either reuses the existing instance and opens a new tab, or
  reports "already running" — it never silently binds a conflicting second
  instance without telling the user.
- [ ] Given the local port is unavailable, the command reports the
  specific bind failure, not a generic crash.

## Out of scope for this story
- Structure view (E10-2), analytics view (E10-3), session control UI
  (E10-4) — this story is the empty shell + launch mechanics only.

## Dependencies
E8-1 (server must exist to launch).

## Technical notes
Toolchain choice (wasm-pack, bundler-free static HTML + wasm-bindgen, etc.)
is an architect decision per `docs/brief-wasm-dashboard.md` constraints —
not decided in this story. New code must sit at plugin root
(`plugins/agent-team/web/` or similar), never inside `.claude-plugin/`, per
`CLAUDE.md`.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
