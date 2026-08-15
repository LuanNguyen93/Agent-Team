# Project Brief: WASM Dashboard for Agent-Team

Date: 2026-08-15
Author: analyst

## Problem

The user's request, verbatim (translated from Vietnamese): "create me a WASM
[app] to manage agent-team so I can visualize things more easily."

[observed] The repo already has a terminal TUI at
`plugins/agent-team/tui/rust` (crate `agent-team-tui`, ratatui + crossterm)
with an `analytics` module
(`plugins/agent-team/tui/rust/src/analytics/{model,parse,timeline,
timeline_model,timeline_screen,discover,rates,screen}.rs`) that already
renders an agent-flow timeline screen (`docs/brief-analytics-tui.md`,
`docs/prd-analytics-tui.md`, `docs/ui-spec-analytics.md`, story
`1e52d04 feat: add an agent-flow timeline screen to the TUI`). A prior brief
(`docs/brief-analytics-tui.md`) also already scoped a **structure** TUI (view
+ edit agent/skill/command frontmatter, `.agent-team.json`) fed by a scanner
script, explicitly as a terminal-only tool with monitoring deferred to v2.

[inferred] "Manage" + "visualize... more easily" most plausibly means: the
existing terminal TUI is not easy enough to look at (terminal-only, has to be
launched, no persistent/shareable view), and the user wants the same kind of
data — agent/skill structure and/or the token-cost timeline — in a browser
tab instead, likely via a WASM build so it can reuse the existing Rust
analytics code rather than reimplementing it in JS.

[assumed] The user has not asked to replace the terminal TUI, and has not
asked for a live control-plane that starts/stops/kills real agent sessions.
"Manage" in the request most likely means the same edit-frontmatter scope the
structure-TUI brief already defined, not process control. This is a guess
that needs confirmation — see Open Questions.

## What already exists (do not rebuild)

- [observed] `plugins/agent-team/scripts/measure-tokens.js` — reads Claude
  Code session transcripts, computes per-agent token/cost split using
  `plugins/agent-team/tui/shared/rates.json`. This is the numeric source the
  analytics TUI screen visualizes.
- [observed] `plugins/agent-team/tui/rust/src/analytics/*` — Rust model of
  agent rows/spans and a rendered timeline screen, currently ratatui-only
  (terminal backend), not wasm-bindgen'd.
- [observed] `docs/brief-analytics-tui.md`, `docs/prd-analytics-tui.md`,
  `docs/ui-spec-analytics.md` — a full prior spec for a *structure* TUI
  (agent/skill/command tree, routing, config edit), terminal-only,
  monitoring explicitly deferred.
- [observed] No `wasm` reference in the TUI's `Cargo.toml` or elsewhere in
  `plugins/agent-team/tui` — there is no existing WASM target or build step.

## Success criteria (draft — needs user sign-off)

1. A user can open a browser tab and see agent-team's structure and/or
   session cost data rendered visually (not scrolled terminal text),
   without needing to keep a terminal TUI session running.
2. The view reuses the existing Rust `analytics` model/data rather than a
   parallel reimplementation, if a WASM build of that module is feasible
   within `wasm-bindgen`'s constraints (no direct file I/O in wasm — needs a
   data-loading strategy, see Open Questions).
3. [OPEN — see below] "Manage" actions, if any, are named and scoped before
   design starts.

## Out of scope (proposed)

- Replacing or deprecating the terminal TUI.
- Multi-user / hosted deployment — this is a local, single-user dashboard.
- Real-time streaming of an in-progress session, unless the PRD's
  session-control work (decision 1) requires it for live status; default
  assumption is point-in-time refresh, not push/streaming, and the PRD
  should confirm which.

Note: live process control (start/stop/kill) was moved IN scope by the
user's decision above and is no longer excluded — see Decisions §1.

## Glossary

| Term | Definition | Identity rule |
|---|---|---|
| agent-team | This Claude Code plugin (`plugins/agent-team/`) | the plugin dir |
| structure | agents/skills/commands and their frontmatter relationships | one row per file scanned |
| session data / analytics | per-agent token/cost/timeline data from `measure-tokens.js` | one span per agent invocation in a transcript |
| WASM dashboard | the requested browser-based visualization | new, not yet built |
| manage | [OPEN] unclear whether this means "edit config/frontmatter" (per the existing structure-TUI brief) or "control running agents" | undefined until user answers |

## Decisions (user sign-off, 2026-08-15)

1. **Scope of "manage"**: **control of running sessions** (start/stop/kill),
   not just config edit. This is a materially bigger scope than the prior
   structure-TUI brief's "edit frontmatter" — it requires a live control
   plane over real Claude Code agent processes, which does not exist
   anywhere in the repo today. Architecture must define how the browser
   (sandboxed, no process access) reaches a process-control backend safely.
2. **What gets visualized**: **both** — the structure graph (agents/skills/
   commands + routing) and the cost/timeline analytics (token usage,
   agent-flow timeline).
3. **Relationship to the existing terminal TUI**: **second frontend, shared
   core** — new WASM/web frontend alongside the existing terminal TUI,
   reusing the Rust `analytics`/structure model via `wasm-bindgen` where
   feasible. The ratatui TUI is not replaced.
4. **Data delivery**: **local server feeds JSON** — a small local process
   generates/serves data (reusing `measure-tokens.js` / scanner logic
   and/or a new Rust-native server) that the WASM/web app fetches. This same
   local server is the natural place to host session-control actions from
   decision 1 (start/stop/kill), since the browser cannot reach processes
   directly.
5. **Runtime target**: not yet asked explicitly — defer to `pm`/`architect`
   to propose (likely a local command that starts the server and opens a
   browser tab, consistent with decision 4). Flag as a residual open item
   for the PRD.
6. **Multi-project or this-repo-only**: not yet asked explicitly — defer to
   `pm` to confirm in the PRD; default assumption is this repo's own
   agent-team install only, matching the existing TUI's scope.

## Constraints

- [observed] Per `CLAUDE.md`: any new component must sit at the plugin root
  (e.g. `plugins/agent-team/tui/` sibling or a new `plugins/agent-team/web/`
  dir), never inside `.claude-plugin/`.
- [observed] If new code touches `plugins/agent-team/tui/**`, the CI workflow
  `.github/workflows/tui-pr.yml` fires and runs the full gate list
  (`cargo fmt/clippy/test/build --release`, `check-binaries.test.sh`,
  `src-hash-consistency.test.sh`, `check-binaries.sh`) across Windows/macOS/
  Linux — a WASM target inside that crate would need to fit or be exempted
  from that matrix; needs architect attention.
- [assumed] No existing package.json/npm toolchain in the repo for a web
  frontend — `measure-tokens.js` is deliberately zero-dependency Node. A
  WASM dashboard likely introduces the repo's first JS build toolchain
  (wasm-pack, bundler) unless kept to a pure static-HTML + wasm-bindgen
  glue file with no bundler. Worth flagging to the user/architect as new
  tooling surface.

---

Assumptions: the terminal TUI stays and this is additive; "manage" means
config edit rather than process control; target is a single-user local
dashboard, not a hosted multi-user service; this repo's own agent-team
install is the only target (not arbitrary projects) — none of these are
confirmed by the user yet.

Not covered: no design or architecture decisions made (WASM build tooling,
data-loading mechanism, UI layout) — those belong to `pm`/`architect` once
the open questions above are answered.

Open: all six numbered questions above need the user's answer before this
goes to `pm`/`architect`. Item 4 (data delivery) is the one most likely to
change technical shape and should be resolved first.
