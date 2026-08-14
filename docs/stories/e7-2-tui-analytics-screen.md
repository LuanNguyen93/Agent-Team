# E7-2: Analytics screen — native transcript parsing, cost split, per-agent breakdown, manual refresh

**Related FR**: FR-1, FR-2, FR-3, FR-4, FR-5, FR-6 (docs/prd-analytics-tui.md)
**Priority**: high
**Estimate**: L

## Story
As a maintainer or user, I want a screen in the TUI that shows a completed
session's main-context-vs-subagent cost split first, with the per-agent/
model breakdown visible below it, so that I can tell whether a session ran
too much work in the main context instead of delegating it — without
running `measure-tokens.js` separately.

## Acceptance criteria
- [ ] Given a session's transcript directory, when the screen opens, then
  the Rust TUI parses the `.jsonl` files natively — no shelling out to
  Node — and renders the main/sub cost split as the first visible content.
- [ ] Given the parsed session, when rendered, then the per-agent/model
  breakdown (agent, model, calls, cost) appears below the split on the same
  screen, matching `measure-tokens.js --by-agent`'s rows.
- [ ] Given the shared fixture transcript (FR-6), when the Rust parser runs
  against it, then its main cost, sub cost, and per-agent rows match
  `node measure-tokens.js --json` run against the same fixture, within the
  tolerance the required new ADR sets (see Dependencies).
- [ ] Given the screen is open, when the manual refresh key is pressed,
  then the transcript is re-read from disk and the split/breakdown update;
  no background polling occurs at any other time.

### Edges
- [ ] Empty: no `.jsonl` files under the project directory — an explicit
  "no sessions found" state, not a blank screen.
- [ ] One: a single main-only transcript with zero subagent calls — split
  renders as 100% main / 0% sub, not a blank or omitted sub row.
- [ ] Many: a project with 50 sessions and 30 distinct (agent, model) pairs
  in one session — breakdown scrolls without truncating rows silently.
- [ ] Far too many: a single 50,000-line transcript file — parses and
  renders within a 5s budget on open.

### Failures
- [ ] Given a `.jsonl` line that is not valid JSON, when parsed, then the
  parser skips it, counts it in a visible "malformed lines" figure, and
  continues — it does not abort the whole session's parse.
- [ ] Given the transcript directory does not exist or is unreadable, when
  the screen opens, then it shows an error naming the specific problem
  (missing path vs. permission denied), distinguished from the empty-
  sessions state.
- [ ] Given a refresh is attempted after the transcript became unreadable
  since the last successful read, then the screen keeps showing the last
  good numbers with a stale-data indicator, rather than blanking them.

## Out of scope for this story
- The ratatui shell itself (event loop, screen switching, quit, resize,
  generic error screen) — that is E7-1, which this story depends on.
- Live/streaming updates while a session is running — monitoring stays v2
  per `docs/brief.md`, not reopened by `docs/brief-analytics-tui.md`.
- Cost projection or forecasting.
- Any write-back — this screen is read-only.
- Cross-project aggregation beyond `measure-tokens.js --project`'s existing
  behaviour.
- Retiring, modifying, or rewriting `measure-tokens.js` — it keeps serving
  CLI/CI use unchanged.

## Dependencies
E7-1 (ratatui shell must exist for this screen to render into). Blocked on
a new ADR — owner `architect`, required before design starts on this
story's FR-1/FR-6 acceptance criteria — deciding: where the shared fixture
transcript (FR-6) lives, which implementation (JS or Rust) is authoritative
when they disagree, and whether the rate table (`RATES` in
`measure-tokens.js`) is hand-duplicated in Rust or code-generated from one
source. See `docs/prd-analytics-tui.md` "Open item carried forward."

## Technical notes
Rust + ratatui, no Node runtime bet, per ADR-0002
(`docs/adr/0002-tui-runtime-node-zero-dependency.md`) and
`docs/brief-analytics-tui.md` decision 2. Parsing semantics to match
`plugins/agent-team/scripts/measure-tokens.js`'s `costOf`, `contextOf`,
`isSubagent`, `sessionIdFor`, `tierOf`, `walk`, `projectDirFor` functions —
`architect` designs the Rust module structure and the shared-fixture
mechanism once the ADR above lands.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
