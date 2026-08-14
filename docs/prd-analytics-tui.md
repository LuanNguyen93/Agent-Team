# PRD: TUI Analytics Screen

## Context

[observed] `docs/brief-analytics-tui.md` is signed off by the user
(2026-08-14) on four decisions that this PRD holds as given, not reopens:
purpose (main-vs-subagent cost split is the headline), data path (Rust
parses transcript JSONL natively, `measure-tokens.js` is not retired),
sequencing (a shared ratatui shell is a prerequisite story ahead of both the
tree view and this screen), and liveness (post-hoc only, manual refresh, no
live tailing). [observed] `docs/prd.md` (the existing TUI PRD) does not
mention analytics in its FR list at all — this is a new, separate PRD,
additive to it, following the same house style.

[observed] `plugins/agent-team/tui/rust/src/main.rs` is 36 lines and
implements only `--build-info`. No event loop, no rendering, no JSONL
reading exists yet. [observed] `docs/adr/0002-tui-runtime-node-zero-dependency.md`
commits the TUI to Rust + ratatui with prebuilt binaries and no Node-runtime
bet — this PRD's FR-1 is bound by that ADR's "no shelling out to Node."

## Users and needs

| Role | Needs | Why |
|---|---|---|
| Maintainer or user running the TUI on a finished session | See, without leaving the screen, whether the session ran too much work in the main context instead of delegating it | Same signal the delegation-nudge hook already acts on; today only reachable via `node measure-tokens.js` [brief.md decision 1] |

## Scope

### In scope
- A native Rust transcript parser producing the same session/main/sub split
  and per-agent/model rows `measure-tokens.js` produces (FR-1).
- An analytics screen, built on the shared ratatui shell, showing the
  main-vs-subagent cost split first and the per-agent breakdown below it,
  no further navigation required (FR-2, FR-3).
- Manual refresh: re-read the transcript on a key press (FR-4).
- An error screen for missing/unreadable/malformed transcript data (FR-5).
- A shared fixture transcript, checked by a test in both `measure-tokens.js`
  and the Rust parser, so the two implementations' drift fails a gate
  instead of surfacing silently (FR-6).

### Out of scope
- Live/streaming updates while a session is in progress — monitoring stays
  v2 per `docs/brief.md`; not reopened here [brief-analytics-tui.md decision 4].
- Cost projection or forecasting future spend [brief-analytics-tui.md].
- Any write-back — this screen is read-only; it never touches transcripts or
  `.agent-team.json` [brief-analytics-tui.md].
- Cross-project aggregation beyond what `measure-tokens.js --project` already
  supports [brief-analytics-tui.md].
- Retiring or modifying `measure-tokens.js`'s CLI/CI behaviour
  [brief-analytics-tui.md decision 2].
- Designing the shared ratatui shell itself beyond what this screen and E3-1
  need from it — the shell's own acceptance criteria live in its own story
  (E7-1), not here.

## Resolutions of the brief's settled decisions

These four are recorded here for traceability only — they are not open for
this PRD to revisit.

1. **Purpose** [brief-analytics-tui.md decision 1]: the screen answers "is
   too much work running in the main context?" The main-vs-subagent cost
   split is the headline, shown first; the per-agent/model breakdown sits
   below it on the same screen.
2. **Data path** [brief-analytics-tui.md decision 2]: the Rust TUI parses
   transcript JSONL natively — no shelling out to Node, ADR-0002 stands
   unmodified. `measure-tokens.js` is not retired. **Accepted risk**: two
   implementations of cost/split logic that can drift; **mitigation this PRD
   holds someone to**: a shared fixture transcript with a test in each
   implementation (FR-6).
3. **Sequencing** [brief-analytics-tui.md decision 3]: the ratatui shell
   (event loop, screen switching, quit, resize, error screen) is its own
   prerequisite story (E7-1), shared by E3-1 (tree view) and this analytics
   screen (E7-2). Neither screen builds the shell as a side effect of
   shipping itself.
4. **Liveness** [brief-analytics-tui.md decision 4]: post-hoc only. The
   screen reads completed transcripts on open, with a manual refresh key to
   re-read. No background polling, no live tailing.
5. **Session scope** (settled by the user, 2026-08-14): the screen opens on
   the **most expensive session** in the project — not most-recent, not a
   project-wide roll-up — with `j`/`k` moving through the session list. This
   closes the gap `architect` and `ux-designer` both flagged: earlier
   wording of FR-2/FR-3 said "a session" without saying which.
6. **Rate table** (settled by the user, 2026-08-14): the shared
   `plugins/agent-team/tui/shared/rates.json` is accepted as the one source
   for pricing, with `cacheWriteMultiplier: 1.25` and
   `cacheReadMultiplier: 0.1` as data fields in it rather than literals in
   either implementation. The user explicitly accepted the named cost:
   `measure-tokens.js` stops being a self-contained file and reads this
   external file at startup.

### Open item — now settled (ADR-0007)

The brief required a new ADR before `architect` designed this screen,
covering three things decision 2 left unresolved: where the shared fixture
transcript (FR-6) lives, which implementation is authoritative when they
disagree, and whether the rate table is hand-duplicated or generated from
one source. **`docs/adr/0007-transcript-parity-fixture-authority-and-rate-source.md`
decides all three, and is accepted:**
- Fixture location: `plugins/agent-team/tui/tests/fixtures/transcripts/`,
  with committed JSONL input and an `expected.json` **generated** by
  `measure-tokens.js --json` (via a committed regeneration script), never
  hand-typed.
- Authority: `measure-tokens.js` is authoritative on any disagreement; the
  Rust parser conforms, including reproducing its quirks (e.g. unknown
  models billing at `opus`, a missing `model` key becoming
  `(unknown model)`).
- Rate source: the shared `tui/shared/rates.json` (decision 6 above) —
  `require`d by JS, embedded at compile time via `include_str!` in Rust.
- Tolerance: integer fields compare exactly; costs compare with an absolute
  tolerance of 1e-9 USD per bucket and per row.

FR-1 and FR-6 below are now checkable against this fixed contract; nothing
in this PRD remains open on data path, fixture, or authority.

## Functional requirements

**FR-1 — Native transcript parsing**
- Description: the Rust TUI reads `~/.claude/projects/<project>/**/*.jsonl`
  directly (same discovery rule as `projectDirFor`/`walk` in
  `measure-tokens.js`), computing per-session main/sub cost split and
  per-agent/model rows using the same semantics as `costOf`, `contextOf`,
  `isSubagent`, `sessionIdFor`, `tierOf` in `measure-tokens.js`. No process
  is shelled out to read this data.
- Acceptance criteria:
  - [ ] Given the shared fixture transcript (FR-6), when the Rust parser
    runs against it, then its computed main cost, sub cost, and per-agent
    rows match `node measure-tokens.js --json` run against the same fixture,
    within the tolerance ADR-0007 sets (integers exact, costs within 1e-9
    USD absolute).
  - [ ] Given a transcript containing at least one `subagents/` path, when
    parsed, then calls under it are attributed to sub, not main, using the
    same `isSubagent` rule (path segment match, not filename match).
  - [ ] Given a usage record with an unrecognised model string, when
    costed, then it bills at the `opus` tier, matching `tierOf`'s
    unknown-defaults-expensive rule — not silently dropped or zero-costed.
  - [ ] Edge: zero — a project directory with no `.jsonl` files produces an
    empty session list, not an error, and the screen shows an explicit
    empty state (see FR-5).
  - [ ] Edge: one — a single main-only transcript with no `subagents/`
    produces a session with `sub.calls == 0` and a 100%-main split.
  - [ ] Edge: many — a project with 50 sessions held in memory renders each
    frame within a **100ms per-frame budget** (chosen by `planner`,
    `plan-e7.md`) — a threshold distinct from, and tighter than, the
    far-too-many parse budget below.
  - [ ] Edge: far too many — a single transcript file of 50,000 lines
    parses within a 5s budget on open.
  - [ ] Failure: a line that is not valid JSON — the parser skips that line,
    counts it in a "malformed lines" figure shown on the error/status area,
    and continues; it does not abort the whole session's parse.

**FR-2 — Main-vs-subagent cost split as the headline**
- Description: on opening the screen, the **most expensive session in the
  project** (by `totalCost`, not most-recent, not a project-wide roll-up —
  settled by the user, see "Resolutions" decision 5) is selected by
  default; its main-context cost, subagent cost, and their ratio are the
  first thing rendered — not reached by navigating deeper. `j`/`k` move
  through the session list to select a different session.
- Acceptance criteria:
  - [ ] Given a project with multiple sessions of different total cost, when
    the screen first opens, then the session with the highest `totalCost`
    is the one rendered, not the most recently modified transcript.
  - [ ] Given the session list, when `j` or `k` is pressed, then the
    selection moves to the next/previous session by the list's order and
    that session's split/breakdown render.
  - [ ] Given a parsed session, when the analytics screen first renders,
    then main cost, sub cost, and total cost are visible without any
    keypress beyond opening the screen.
  - [ ] Given a session with zero subagent calls, when rendered, then the
    split shows 100% main / 0% sub explicitly, not a blank or omitted sub
    row.
  - [ ] Given the main share of total cost, when rendered, then a
    word-form verdict is shown alongside it using the thresholds `planner`
    fixed from `ui-spec-analytics.md` §8.2: 0–40% main share → `[DELEGATED]`;
    40–80% → `[MOSTLY MAIN]`; 80–100% (or `$0`/`$0`, no billed activity) →
    `[ALL MAIN]` / `[NO BILLED ACTIVITY]`.
  - [ ] Edge: a session with cost `0` in both buckets (e.g. a
    transcript with only non-billable events) — the split renders as
    `$0 / $0`, not a division-by-zero error or blank screen, and the
    verdict reads `[NO BILLED ACTIVITY]`.

**FR-3 — Per-agent/model breakdown**
- Description: below the split, without leaving the screen, show the rows
  `measure-tokens.js --by-agent` produces: agent name, model, calls, cost.
- Acceptance criteria:
  - [ ] Given a session with 3 distinct (agent, model) pairs, when
    rendered, then 3 rows appear below the split on the same screen.
  - [ ] Given a subagent call with no `attributionAgent`, when rendered,
    then it appears as a row labelled `(unattributed subagent)`, matching
    `measure-tokens.js`'s fallback.
  - [ ] Edge: zero — a session with only main-context calls shows exactly
    one row, `(main context)`.
  - [ ] Edge: many — 30 distinct (agent, model) pairs render in a
    scrollable list without truncating data silently.

**FR-4 — Manual refresh**
- Description: a dedicated key re-reads the transcript from disk and
  recomputes the screen's numbers. No background polling, no live tailing.
- Acceptance criteria:
  - [ ] Given the screen is open, when the refresh key is pressed, then the
    transcript is re-read from disk and the split/breakdown update to match.
  - [ ] Refresh is synchronous, not concurrent: `LoadState::Refreshing`
    renders once — the last-good data plus a refreshing indicator, both on
    screen together — before the blocking load runs, then the frame swaps
    atomically to the new data. Given a refresh is triggered, then the
    previously-loaded data stays visible up to that point, the table is
    never blank and never partially overwritten mid-load, and the screen is
    genuinely unresponsive to further input for the duration of the load
    itself — true concurrency (a non-blocking load that keeps accepting
    input) is an explicitly deferred follow-up behind `load()`, not part of
    this criterion.
  - [ ] Given no refresh key is pressed, when time passes with the
    transcript file changing on disk, then the screen's numbers do not
    change — confirming no background polling exists.
  - [ ] Failure: the transcript file is deleted or becomes unreadable
    between opening the screen and a refresh — refresh shows the FR-5 error
    state and leaves the last successfully-read numbers visible with a
    stale-data indicator, rather than blanking them.

**FR-5 — Error and empty states**
- Description: every place FR-1's parsing can fail or return nothing has an
  explicit, named screen state — never a blank render or a crash.
- Acceptance criteria:
  - [ ] Given no `.jsonl` files exist under the project directory, when the
    screen opens, then it shows an explicit "no sessions found" state
    naming the path it looked in.
  - [ ] Given the project directory itself does not exist (e.g. run from an
    unrecognised path), when the screen opens, then it shows an error
    naming the missing path, not an empty-sessions state (the two are
    distinguished).
  - [ ] Given a `.jsonl` file exists but is completely unparsable (zero
    valid lines), when the screen opens, then it is listed as a failed
    session with a reason, and other valid sessions still render.
  - [ ] Failure: permission denied reading the transcript directory — the
    screen states that specifically, not a generic parse-error message.

**FR-6 — Shared fixture parity (risk mitigation)**
- Description: one fixture transcript, committed to the repo, that both
  `measure-tokens.js` and the Rust parser are tested against, so a
  divergence in cost/split logic between the two implementations fails a
  test rather than surfacing as a silent discrepancy in production.
- Acceptance criteria:
  - [ ] Given the shared fixture, when `measure-tokens.js`'s own test suite
    runs, then it asserts exact main cost, sub cost, and per-agent rows
    against it.
  - [ ] Given the shared fixture, when the Rust parser's test suite runs,
    then it asserts the same figures against the same fixture.
  - [ ] Given a future change to either implementation's cost logic that
    changes the fixture's computed numbers without updating the other
    implementation to match, when both test suites run in CI, then at
    least one fails.
  - [ ] Edge: the fixture must itself exercise every case FR-1's edges
    cover — zero subagent calls, at least one subagent call, an
    unrecognised model, at least one malformed line — so parity is checked
    on the cases most likely to diverge, not only the happy path.
  - [ ] Settled by ADR-0007 (see "Resolutions" above): fixture at
    `plugins/agent-team/tui/tests/fixtures/transcripts/`, `expected.json`
    generated by `measure-tokens.js --json` and never hand-typed,
    `measure-tokens.js` authoritative on disagreement, tolerance integers
    exact / costs within 1e-9 USD absolute.

## Non-functional requirements

| Type | Target | How measured |
|---|---|---|
| Correctness parity | Rust and JS implementations agree on the shared fixture within the ADR's stated tolerance | FR-6 test suites in CI |
| Performance | Screen renders a 50,000-line transcript within 5s on open | Timed test against a synthetic fixture |
| Safety | No write access to any transcript, `.agent-team.json`, or other file from this screen | Code review / static check: no write syscalls reachable from the analytics module |
| Portability | Same five target triples as ADR-0002; no new runtime introduced | Inherits E0-1's CI matrix — no separate build for this screen |
| Minimum viable width | Screen degrades, rather than breaks, at a **60-column** floor (`ui-spec-analytics.md` §10, chosen by `planner`) | Rendered at 60 columns in a terminal-size test; below it the by-agent table degrades per the UI spec |

## Data

- **Source of truth**: `~/.claude/projects/<project>/**/*.jsonl` transcript
  files, read fresh on open and on manual refresh. Never cached to disk by
  this feature, never written to.
- **Retention**: none — no persistent state of its own.
- **Migration**: none.

## Epics and stories

| Epic | Story | Related FR | Priority |
|---|---|---|---|
| E7: TUI shell + analytics | E7-1 Ratatui shell: event loop, screen switching, quit, resize, error screen | prerequisite for FR-2–FR-5 and for `docs/stories/e3-1-tui-tree-view.md` | high |
| E7: TUI shell + analytics | E7-2 Analytics screen: native transcript parsing, cost split, per-agent breakdown, manual refresh | FR-1, FR-2, FR-3, FR-4, FR-5, FR-6 | high |

Dependency order: **E7-1 before E7-2, and E7-1 before E3-1** (`docs/stories/e3-1-tui-tree-view.md`
did not previously depend on a shell story because none existed; it now
does — see that story's amended Dependencies section). E7-2 additionally
depends on the new ADR (owner `architect`) landing before its FR-1/FR-6
acceptance criteria can be implemented against a fixed contract.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Rust and JS cost logic drift silently | Numbers shown in the TUI disagree with `measure-tokens.js` output for the same transcript, undermining trust in both | FR-6: shared fixture, tested in both implementations, in CI |
| `measure-tokens.js` loses self-containment (now reads `tui/shared/rates.json`) | Running the script from a copied-out location, without the file beside it, now fails | Accepted by the user (decision 6); `rates.json` ships alongside the script inside the plugin tree |
| Ratatui shell (E7-1) slips | Both E3-1 and E7-2 are blocked, since neither can render without it | E7-1 is sequenced first and carries no functional scope beyond the shell itself, keeping it small |
| Large/malformed transcripts (corrupted JSONL, huge sessions) | Screen could hang or crash on a real user's transcript | FR-1's edges + FR-5's error states test malformed lines and 50k-line files explicitly |

## Open questions

- None blocking. The ADR required by decision 2 (fixture location,
  authoritative implementation, rate-table source) is decided in
  ADR-0007 and accepted. Session scope and rate-table sourcing are settled
  by the user (decisions 5–6). Verdict thresholds, the 60-column floor, and
  the 100ms per-frame render budget are fixed by `planner` in `plan-e7.md`.
- Not open: purpose, data path, sequencing, liveness, session scope, rate
  table — all six are settled and restated, not revisited, above.
- ADR-0007 itself carries two low-severity open items of its own (tie-break
  ordering on an exact cost/calls tie; whether a user-supplied price
  override belongs in `.agent-team.json`) — owned by `implementer` and the
  user respectively, tracked in the ADR, not repeated here.
</content>
