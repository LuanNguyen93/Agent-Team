# Brief: Analytics UI in the TUI

- **Status**: draft — open questions block handoff to `pm`/`architect`
- **Date**: 2026-08-14
- **Analyst**: agent-team `analyst`
- **Source request**: "tạo UI Analytics trên TUI" (build an Analytics UI inside the TUI)

## Problem

[assumed] The user wants the TUI (`plugins/agent-team/tui/`) to show token/cost
analytics — the data `scripts/measure-tokens.js` already computes — as a
rendered screen instead of a Node CLI report. This is a solution-shaped
request; the underlying need was not stated in the message and is the first
open question below.

[observed] `docs/measurements/*.json` and `measure-tokens.js --json` already
answer "where did the money go" for a *finished* session, via `pnpm`-free
Node. [observed] `docs/brief.md` (the existing TUI brief) explicitly defers
**all monitoring** — "no hook instrumentation, no transcript tailing" — to a
v2 not yet scoped. Analytics-while-a-session-runs would fall inside that
deferred scope; analytics of *past* sessions (what `measure-tokens.js`
already does) would not — it's a new read-only view over existing data, not
monitoring a live one.

## What already exists [observed]

- `plugins/agent-team/tui/rust/src/main.rs` — 36 lines. Only `--build-info`
  is implemented. No event loop, no rendering, no ratatui `Terminal` setup,
  no scanner-JSON loading. **Any rendered screen, analytics or otherwise, is
  the first one this binary would ever draw.**
- `docs/adr/0002-tui-runtime-node-zero-dependency.md` — the TUI is Rust +
  ratatui, prebuilt binaries, explicitly **no runtime bet on Node being on
  PATH**. This was decided over a Node-only option specifically to kill that
  bet.
- `plugins/agent-team/scripts/measure-tokens.js` — zero-dep Node CommonJS.
  Reads `~/.claude/projects/<project>/**/*.jsonl`, splits cost into
  main-context vs. subagent, per-agent/model rows, and a `--fillers`
  breakdown of what filled the largest context. Has `--json`.
- `docs/stories/e3-1-tui-tree-view.md`, `e3-2-tui-load-edges.md` — the
  planned, **not yet built**, first screen (agent/skill/command tree). Same
  status as this request: written, not implemented, no event loop to run
  either of them yet.
- `docs/prd.md` — scope is tree view + frontmatter edit + `.agent-json`
  edit. Analytics is not in this PRD's FR list at all.

## The load-bearing question: where does the data come from

`measure-tokens.js` reads Claude Code's own transcript JSONL under
`~/.claude/projects/...` — a Node-and-filesystem operation. The TUI is Rust.
Two ways to get that data into a ratatui screen, and they have very
different costs:

1. **Rust re-implements the transcript reader** (JSONL walk, usage-record
   parsing, the cost table, the main/sub split) natively in
   `tui/rust/src/`. Keeps ADR-0002's zero-runtime-bet intact. Cost: a second
   implementation of `measure-tokens.js`'s logic that must be kept in sync
   with it, in a different language, or one of the two becomes the
   throwaway.
2. **The Rust TUI shells out to `node measure-tokens.js --json`** and
   parses the output. Cost: **this is exactly the bet ADR-0002 rejected** —
   "Node may not be on PATH" was the stated reason Node-only was turned
   down for the *whole TUI*. Doing it here for one screen reopens that
   decision for that screen specifically, silently, unless it's written down.

There is no third option that avoids picking one of these. **This needs its
own ADR before `architect` designs the screen** — it is not a detail
`architect` can quietly resolve while designing layout, because it either
upholds or breaches a standing decision.

## Success criteria

- On opening the screen for a completed session, the main-context-vs-subagent
  cost split (the same split `measure-tokens.js` leads with, and the same
  signal the existing delegation-nudge hook acts on) is the first thing
  visible — not a number reached by navigating deeper.
- The per-agent/model breakdown is visible below the split without leaving
  the screen (matches `measure-tokens.js --by-agent`'s rows).
- A user can look at the screen and answer "is this session running too much
  work in the main context instead of delegating it?" without running
  `measure-tokens.js` separately.
- Numbers rendered by the Rust screen match `node measure-tokens.js --json`
  run against the same transcript, within the shared fixture's tolerance
  (see risk below) — checkable by running both against one fixture
  transcript and diffing.
- Manual refresh re-reads the transcript on key press and updates the
  numbers; no background polling, no partial render while reading.

## Constraints [observed/inferred]

- Must not reintroduce a Node-on-PATH bet without a named ADR (see above).
- No event loop exists yet in the Rust TUI; this can't render anything
  until one does (main.rs has none).
- `CLAUDE.md`: English throughout, plugin layout rules, no new top-level
  dirs outside `tui/`.
- `docs/brief.md`'s existing TUI scope explicitly excludes live monitoring
  from v1 — a *live* analytics view (tokens ticking as a session runs)
  would conflict with that unless the user is deliberately re-opening it.

## Out of scope (proposed — confirm with user)

- Live/streaming updates while a session is in progress (monitoring — v2
  per the existing brief, unless the user explicitly reopens that decision).
- Cost projection / forecasting future spend.
- Any write-back (the analytics screen is read-only; it does not touch
  transcripts or `.agent-team.json`).
- Cross-project aggregation beyond what `measure-tokens.js --project`
  already supports.

## Glossary

| Term | Definition | Identity rule |
|---|---|---|
| Session | One `~/.claude/projects/<project>/<id>.jsonl` main transcript plus its `subagents/` tree | `session.id` = the file/dir name |
| Main context | Token/cost spend recorded outside any `subagents/` directory | `isSubagent()` in measure-tokens.js |
| Subagent spend | Token/cost spend recorded under a `subagents/` path, attributed via `attributionAgent` or falling back to `(unattributed subagent)` | same |
| Filler | A single tool result/prompt/thinking block's byte contribution to the largest session's context | `fillers()` in measure-tokens.js |
| Scanner JSON | The existing tree-view data source (`plugins/agent-team/agents`/`skills`/`commands` parsed to JSON) — **not** the same data as analytics; unrelated pipeline | schema in `docs/architecture.md` |

## Decisions (settled by the user 2026-08-14)

1. **Purpose.** The screen answers "is this session running too much work in
   the main context instead of delegating it?" — the same signal the
   existing delegation-nudge hook acts on, and the same emphasis
   `measure-tokens.js` already leads with. Main-context-vs-subagent cost
   split is the headline, shown first; the per-agent breakdown sits below
   it, not behind further navigation.
2. **Data path.** The Rust TUI parses transcript JSONL **natively** — no
   shelling out to Node. ADR-0002's no-Node-runtime-bet stands unmodified;
   the TUI binary keeps working standalone. `measure-tokens.js` is **not
   retired** — it keeps serving CLI/CI use. **Accepted risk**: cost/pricing
   and split logic now exists in two implementations (JS and Rust) that can
   drift. **Mitigation the PRD must hold someone to**: a shared fixture
   transcript that both implementations are tested against, with a test in
   each that asserts on it, so drift fails a gate rather than surfacing as a
   silent discrepancy. **A new ADR is still required before design starts**,
   and must decide: where the shared fixture lives, which implementation is
   authoritative when they disagree, and whether the rate table
   (`RATES` in `measure-tokens.js`) is hand-duplicated in Rust or code-generated
   from one source.
3. **Sequencing.** The ratatui shell — event loop, screen switching, quit,
   resize handling, the error screen — becomes its **own prerequisite
   story**, shared by both E3-1 (tree view) and this analytics screen.
   Analytics does not build the event loop as a side effect of shipping
   itself; it is built once, underneath both screens.
4. **Liveness.** Post-hoc only: the screen reads completed transcripts on
   open, with a manual refresh key to re-read. No background polling, no
   live tailing. The existing brief's "monitoring is v2, no live tailing"
   line holds and is **not** reopened by this feature.

## Assumptions / Not covered / Open

**Assumptions**: The user's second sentence about "đo lường và xem chỗ nào
đang tốn token nhất" describes the *reason* for wanting this screen, not an
additional deliverable for this agent — treated as background motivation
only, per the routing instruction given to this analyst.

**Not covered**: Screen layout, widget choice, colour/design (that's
`ux-designer`/`architect` territory once Q1–Q3 are answered). No code was
written or read beyond what's cited above.

**Open**: the new ADR required by decision 2 (fixture location, authoritative
implementation on disagreement, rate-table source) — for `architect`, before
design starts.
