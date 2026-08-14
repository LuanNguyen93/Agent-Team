# UI spec: TUI Analytics screen (E7)

- **Date**: 2026-08-14
- **Author**: `ux-designer`
- **Sources**: `docs/prd-analytics-tui.md` (FR-2, FR-3, FR-4, FR-5),
  `docs/brief-analytics-tui.md`, `docs/stories/e7-1-tui-shell.md`,
  `docs/stories/e7-2-tui-analytics-screen.md`
- Tokens, colour roles, glyphs, spacing scale and panel/border conventions
  are defined in `docs/design-system.md` — this document extends it (§8
  below) rather than repeating it, and does not overwrite it.
- Real numbers throughout are from `docs/measurements/now.json`
  [observed]. Every other claim is labelled `[observed]`, `[inferred]` or
  `[assumed]` per `handoff-contract`.

## 0. What this screen is for

[observed, `docs/brief-analytics-tui.md`] The screen answers one question at
a glance: *is this session running too much work in the main context
instead of delegating it?* Not "what are the numbers" — the numbers exist to
answer that one question fast. Session `7e675a56` ($272.44, 414 calls, 0
subagent calls, 0% delegated, max context 729k) must read as **obviously
wrong** the instant the screen opens, before the viewer reads a single
digit. Session `9732d0cf` ($119.86, 75% delegated, 91k avg context) must
read as obviously fine, just as fast.

## 1. The at-a-glance mechanism

A **horizontal split bar**, one row, immediately under the session header,
built from block-drawing characters (`█` filled, `░` empty), width 40
columns at 80-col floor, scaled up at wide terminals. Main share fills from
the left in the `warning`-or-`error` role (see §8 threshold rule), sub
share fills from the right in `success`. The bar is followed on the same
line by the exact split as text — `72% main / 28% sub` — so the glyph and
the number never disagree and neither is required alone.

Why a bar and not just the table `measure-tokens.js` already prints
(`docs/prd-analytics-tui.md` FR-2, and the incumbent report at
`plugins/agent-team/scripts/measure-tokens.js:374-386`): the incumbent's
`sub%` column is one number among nine, `padStart`-aligned in a row that
looks identical whether it's 0% or 90%. Reading it requires finding the
column, reading the digits, and knowing 0% is bad. A filled/empty bar is
read by shape, not arithmetic — the brief's own bar for success
(`docs/brief-analytics-tui.md` "without running `measure-tokens.js`
separately") is met by making the bad case *visibly* different, not just
numerically different. [inferred] This is a genuine improvement over the
incumbent table for the stated purpose; the table format is still used
below the bar for the per-agent breakdown, where scanning rows one at a
time is the correct behaviour (FR-3), not a headline judgement.

A second, smaller signal reinforces the bar without duplicating colour-only
meaning: a **word-form verdict** to its right, chosen by the same threshold
as the colour (§8): `[ALL MAIN]`, `[MOSTLY MAIN]`, `[DELEGATED]`. This is
the glyph's fallback and is present even when colour is on — not shown only
under `NO_COLOR` — because it is also what makes the screen readable in a
5-second glance without stopping to interpret a bar's proportions.

## 2. Screen inventory addition

Extends `docs/ui-spec.md` §1 (screen inventory table lives there for the
tree-view PRD; this table is the same shape for the analytics epic and does
not renumber that one):

| # | Screen | Entered from | FR |
|---|---|---|---|
| A1 | Analytics screen — populated | screen-switch key from shell (E7-1) | FR-2, FR-3 |
| A2 | Analytics screen — loading (initial parse) | screen entry, before first parse completes | FR-1 |
| A3 | Analytics screen — refreshing (manual) | `r` on A1 | FR-4 |
| A4 | Analytics screen — empty (no sessions) | screen entry, zero `.jsonl` under project dir | FR-5 |
| A5 | Analytics screen — error: project dir missing | screen entry, dir does not exist | FR-5 |
| A6 | Analytics screen — error: permission denied | screen entry, dir unreadable | FR-5 |
| A7 | Analytics screen — partial: unparsable session | screen entry, one dir has 0 valid lines among valid ones | FR-1, FR-5 |
| A8 | Analytics screen — stale after failed refresh | refresh fails on A1/A3 | FR-4 |

## 3. Default populated state (80×24)

Session `9732d0cf` ($119.86 total, 75.5% delegated), the case the screen
should make look *fine*.

```
┌ ANALYTICS ── session 9732d0cf ──────────────────────────────────── [r]efresh ┐
│                                                                              │
│  main  ████████████░░░░░░░░░░░░░░░░░░░░░░░░  sub   25% main / 75% sub  [DELEGATED] │
│                                                                              │
│  total     $119.86      main  $30.46 (25%)      sub  $89.40 (75%)          │
│                                                                              │
│  BY AGENT / MODEL                                            30+ rows ↓ [j/k]│
│  agent                       model            calls    cost              │
│  ──────────────────────────────────────────────────────────────────────  │
│  agent-team:architect        claude-opus-5       74   $35.53             │
│  (main context)               claude-opus-5      102   $30.46             │
│  agent-team:reviewer          claude-opus-5       72   $19.63             │
│  agent-team:implementer       claude-sonnet-5    271   $19.37             │
│  agent-team:ux-designer       claude-sonnet-5     95    $4.36             │
│  agent-team:pm                claude-sonnet-5     80    $4.00             │
│  agent-team:analyst           claude-sonnet-5     43    $2.73             │
│  agent-team:qa-verifier       claude-sonnet-5     80    $2.53             │
│  agent-team:planner           claude-sonnet-5     20    $1.25             │
│                                                                              │
│  9 rows                                                                     │
└──────────────────────────────────────────────────────────────────────────┘
  q quit   r refresh   ?  help                                    last read 0s ago
```

Notes:
- The session list (§9) sits between the header and the split bar on every
  screen in this section, opened with the cursor `▶` on the most-expensive
  session — omitted from this particular mockup only to keep it narrow
  enough to read; see §9 for the list itself with the cursor drawn.
- `[DELEGATED]` renders in `success` role when colour is on; the word form
  is present regardless — no colour-only signal (design-system.md §1).
- Row order: highest cost first, matching `measure-tokens.js --by-agent`'s
  existing sort [inferred from `byAgent` array order in
  `docs/measurements/now.json`, descending cost].
- `last read Ns ago` in the footer is the staleness clock — always visible,
  not only shown when data is stale, so its absence in the "fresh" state is
  itself informative (compare §7 below).

### 3a. Wide terminal (160×40)

At width, the byAgent table gains `cache rd`, `cache wr`, `output` columns
(matching the incumbent report's fields at
`plugins/agent-team/scripts/measure-tokens.js:336-345`) and the split bar
widens to 80 columns for finer visual resolution; the underlying threshold
and verdict logic are unchanged. Agent/model names stop truncating at 27/19
chars (`measure-tokens.js:342`'s `slice(0,27)` limit is a narrow-terminal
concession only, see §8 truncation rule).

## 4. Zero-subagent case — must render explicitly (FR-2 edge)

Session `7e675a56` ($272.44, 414 calls, 0 sub calls, max context 729k). The
case the screen must make look *obviously wrong*.

```
┌ ANALYTICS ── session 7e675a56 ──────────────────────────────────── [r]efresh ┐
│                                                                              │
│  main  ████████████████████████████████████████  sub   100% main / 0% sub  [ALL MAIN] │
│                                                                              │
│  total     $272.44      main  $272.44 (100%)     sub    $0.00 (0%)         │
│                                                                              │
│  ! max context reached 729k tokens in main — nothing was delegated         │
│                                                                              │
│  BY AGENT / MODEL                                                          │
│  agent                       model            calls    cost              │
│  ──────────────────────────────────────────────────────────────────────  │
│  (main context)               claude-opus-5      414  $272.44             │
│                                                                              │
│  1 row                                                                      │
└──────────────────────────────────────────────────────────────────────────┘
  q quit   r refresh   ?  help                                    last read 0s ago
```

The `0% sub` half of the bar is drawn as an explicit empty segment
(`░░░░...`), never omitted — FR-2's edge criterion demanded exactly this:
"not a blank or omitted sub row." `[ALL MAIN]` uses the `error` role (not
`warning`) once main share is 100% AND max context exceeds the warning
threshold (§8) — this is the one state the whole screen exists to flag, so
it gets the strongest available signal, plus the advisory line under the
totals (`!` glyph, `warning`/`error` role, plain-text fallback already the
glyph's word form per design-system.md §6).

## 5. The $0 / $0 case (FR-2 edge — no division by zero)

A transcript with only non-billable events (e.g. all `<synthetic>` model
rows, cost 0, as seen for the trailing row in several real sessions in
`now.json`, e.g. session `2ccd7568`'s last byAgent entry).

```
│  main  ────────────────────────────────────────  sub    $0 / $0  [NO BILLED ACTIVITY] │
│                                                                              │
│  total      $0.00      main   $0.00 (—)          sub    $0.00 (—)          │
```

Rule: when `total cost == 0`, the bar renders as a flat dashed line (`─`,
neutral `fg.dim`, no fill in either colour role — there is no share to
show), the percentage fields render `—` instead of `0%` (division is never
attempted; `pct(total ? x/total : 0)` guards this the same way
`measure-tokens.js:390-391` already guards its own totals line), and the
verdict reads `[NO BILLED ACTIVITY]` rather than `[ALL MAIN]` — a session
with nothing billed is a different fact from a session that spent
everything in main, and the two must not collapse to the same glyph.

## 6. Empty and error states (FR-5 — all five distinguished)

FR-5 requires five states that must never collapse into each other. Each
gets its own screen body; the header/footer chrome is identical across all
of them so the eye always knows it's still the analytics screen.

### 6a. Empty — no sessions found (A4)

```
┌ ANALYTICS ──────────────────────────────────────────────────────────────────┐
│                                                                              │
│                                                                              │
│                       No sessions found.                                   │
│                                                                              │
│         Looked in: ~/.claude/projects/D--Agent-Team                        │
│                                                                              │
│         Run a session in this project, then press r to check again.       │
│                                                                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────┘
  q quit   r refresh   ?  help
```

Names the exact path searched [FR-5 acceptance criterion], and says the
next action (per design-intelligence: "no data" alone is a design failure).
This is not an error — no `!`/`✗` glyph, `fg.default` text only.

### 6b. Error — project directory missing (A5)

```
┌ ANALYTICS ── ERROR ──────────────────────────────────────────────────────────┐
│                                                                              │
│  ✗ Project directory does not exist                                        │
│                                                                              │
│    ~/.claude/projects/D--Agent-Team                                        │
│                                                                              │
│    This path is derived from the current working directory. If you        │
│    expected data here, check you're running the TUI from the right repo.  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────┘
  q quit   r refresh   ?  help
```

Distinguished from 6a by the `✗ ERROR` panel-title suffix, `error` role,
and different copy — "does not exist" vs "no sessions found" — per FR-5's
explicit requirement that these two never be the same screen.

### 6c. Error — permission denied (A6)

```
│  ✗ Permission denied reading project directory                            │
│                                                                              │
│    ~/.claude/projects/D--Agent-Team                                        │
│                                                                              │
│    The TUI process does not have read access to this path.                │
```

Named specifically (FR-5 failure criterion: "not a generic parse-error
message") — never folded into a generic "could not read" message.

### 6d. Partial — one session unparsable, others fine (A7)

```
│  ⚠ 1 session failed to parse — 8 shown below                              │
│                                                                              │
│  session   total     main      sub    verdict                             │
│  ──────────────────────────────────────────────────────────                │
│  9732d0cf  $119.86   25%       75%    [DELEGATED]                         │
│  ...                                                                        │
│  ⚠ 3daec7f  unreadable — 0 valid JSON lines                              │
```

The failed session is listed inline, in place, with its own `⚠` row and
reason — not dropped from the list and not blocking the valid sessions
(FR-5: "other valid sessions still render", FR-1: "malformed lines" figure
shown in the error/status area). If the *currently selected* session is the
failed one, the detail panel below shows this same message instead of a
split bar — never a bar computed from partial/zero data pretending to be
complete.

## 7. Refresh states (FR-4)

### 7a. Refresh in progress (A3)

```
┌ ANALYTICS ── session 9732d0cf ────────────────────────────── ⟳ refreshing… ┐
│                                                                              │
│  main  ████████████░░░░░░░░░░░░░░░░░░░░░░░░  sub   25% main / 75% sub  [DELEGATED] │
...  (last-good content stays fully visible and interactive underneath)
└──────────────────────────────────────────────────────────────────────────┘
  q quit   (refreshing — please wait)                                last read 0s ago
```

`⟳ refreshing…` sits where `[r]efresh` normally sits in the header — the
same corner, not a new element, so it's noticed without hunting. Per FR-4's
own acceptance criterion this is non-blocking: the previous frame's data
stays on screen unchanged and scrollable until the new data is ready, then
swaps atomically in one frame — never a partially-overwritten table (no
row-by-row streaming update).

### 7b. Stale after failed refresh (A8)

```
┌ ANALYTICS ── session 9732d0cf ── ⚠ STALE (refresh failed 12s ago) ── [r]refresh ┐
│                                                                              │
│  main  ████████████░░░░░░░░░░░░░░░░░░░░░░░░  sub   25% main / 75% sub  [DELEGATED] │
...  (unchanged last-good numbers, fully visible)
│                                                                              │
│  ⚠ Last refresh failed: permission denied. Showing data from 3m ago.       │
└──────────────────────────────────────────────────────────────────────────┘
  q quit   r retry refresh   ?  help                              last read 3m ago
```

The last-good numbers stay exactly as they were (FR-4 failure criterion:
"leaves the last successfully-read numbers visible with a stale-data
indicator, rather than blanking them") — two independent signals mark
staleness: the header badge (`⚠ STALE`, persistent, not a toast that
disappears) and the footer's `last read 3m ago` clock, which is present on
every state (§3) and is the thing that makes "stale" mean something
concrete rather than a vague warning.

## 8. Extension to `docs/design-system.md`

The base design system (colour roles, glyphs, spacing, borders) applies
unmodified. This screen needs two conventions the base document doesn't
define, because no other screen in the tree-view PRD needed them:

**8.1 The split bar** is a new component: 40 (or 80 at wide) character
cells, filled left-to-right for main share in `warning`/`error` role
(threshold below), right-to-left for sub share in `success` role, `█`
filled / `░` empty, degrading under `NO_COLOR` to the same characters in
`fg.default` — the fill pattern itself (which side is solid) is the
non-colour carrier, exactly as design-system.md §1 requires. When main
share is 0 (fully delegated), main's `█` segment is 0 cells wide, not
omitted — same explicit-empty-segment rule as §4.

**8.2 The three-way verdict threshold** (new — the base doc has no
percentage-based role rule):

| Main share | Colour role | Word form |
|---|---|---|
| 0% – 40% | `success` | `[DELEGATED]` |
| 40% – 80% | `warning` | `[MOSTLY MAIN]` |
| 80% – 100%, or $0/$0 | `error` / neutral | `[ALL MAIN]` / `[NO BILLED ACTIVITY]` |

[assumed] Thresholds (40/80) are not stated in the PRD or brief — chosen to
put the two named real sessions on opposite sides with margin (7e675a56 at
100% main → `[ALL MAIN]`; 9732d0cf at 25% main → `[DELEGATED]`) and left
here as a named, changeable constant rather than folded silently into
render code. **This is a threshold `architect`/`implementer` should treat
as configurable, not hand-tuned further without a reason.**

**8.3 Truncation** follows the existing rule at
`plugins/agent-team/scripts/measure-tokens.js:342` (agent name 27 chars,
model 19 chars, `…` suffix) at 80-col floor; not truncated at 160-col width
(§3a). This matches design-system.md §6's `…` glyph, word form `...`.

## 9. Session list and scrolling (FR-3 edge, plus settled session-scope)

**Session scope is now settled, not assumed** (supersedes §11's old
`[assumed] Tab-switches-session` line and the Open item that named it): the
screen opens on the **most expensive session**, and a session list is a
permanent part of this screen, not a hypothetical. Two lists therefore
exist on screen at once — the session list and the selected session's
by-agent table — and `docs/architecture-e7.md` reserves `Tab`/`Shift+Tab`
globally for the shell's screen-switching, so neither list may use it.

Resolution: **the two lists use disjoint keys, permanently, with no
focus-dependent remapping.** `j`/`k` (and `↑`/`↓`) always move the session
cursor; they never scroll the by-agent table under any state. The by-agent
table scrolls only with `PgUp`/`PgDn`. This was chosen over the
focus-dependent proposal (`j`/`k` meaning session-move or row-scroll
depending on which panel currently has scroll focus) because a
focus-dependent binding makes the same keypress do two different things
based on state that is easy to lose track of at the terminal — exactly the
failure mode a fixed keymap exists to avoid. The cost is that the by-agent
table has no single-row step, only page-step; acceptable because FR-3's own
bar is "scrolls without truncating silently," which `PgUp`/`PgDn` satisfies,
and because the by-agent table is the secondary, detail-level list — the
session list is the one this screen's headline judgement depends on, so it
gets the more precise (single-row) control.

Session list, sorted most-expensive-first, with the cursor always visible
via the same `▶` glyph / `accent` role the tree view already uses for a
selected row (`docs/design-system.md` §6) — this is what makes "which
session is active" observable state, not implicit:

```
│  SESSIONS (11)                                            most expensive first │
│▶ 7e675a56   $272.44   100% main   [ALL MAIN]                                 │
│  d476f824   $183.31    90% main   [MOSTLY MAIN]                              │
│  9732d0cf   $119.86    25% main   [DELEGATED]                                │
│  04a8f641   $113.82    87% main   [ALL MAIN]                                 │
│  ...                                                        7 more ↓ [j/k]   │
```

Selecting a row (moving the `▶` cursor with `j`/`k`/`↑`/`↓`) updates the
split bar, totals, and by-agent table below it in the same frame — the
headline for the newly-selected session, satisfying FR-2 on every session
the cursor lands on, not only the one shown at open.

The by-agent panel, independently scrollable once content exceeds the
available rows (at 80×24, roughly 6-8 visible once the session list above
it takes its own rows):

- `PgUp`/`PgDn` — page-scroll the by-agent table. Not `j`/`k` (reserved for
  the session list, above) and not `Tab` (reserved by the shell).
- A scroll indicator replaces the static row count in the panel's
  top-right corner: `30 rows, 12-21 shown ↕` — never silently truncates
  with no indicator (FR-3: "without truncating data silently").
- The split bar, totals line, session list, and header never scroll from a
  by-agent `PgUp`/`PgDn` — only the by-agent table body does.

## 10. Narrow terminal — degradation order and floor

Below 80 columns, degrade in this order (most expendable first), matching
the general TUI narrow-width convention `docs/ui-spec.md` uses elsewhere:

1. **First to drop**: `cache rd`/`cache wr`/`output` wide columns (already
   absent below 160, §3a — nothing new here).
2. **Second**: the word-form verdict shrinks from `[MOSTLY MAIN]` to
   `[MAIN]`/`[SUB]`/`[MIX]` — still present, never removed, just shorter.
3. **Third**: the split bar shortens proportionally (minimum 20 cells) —
   it does not disappear, because it is the primary at-a-glance mechanism
   (§1); losing it would defeat the screen's purpose before losing anything
   else would.
4. **Fourth**: agent/model column truncation tightens (27/19 → 16/12
   chars) before the columns are dropped.
5. **Minimum viable width: 60 columns.** Below 60, the by-agent table's
   `calls`/`cost` columns no longer fit next to a legible agent name; the
   screen instead shows one line per agent (`name — model — $cost`,
   wrapped) and a footer note: `narrow terminal — widen for full columns`.
   [assumed] 60 is not stated anywhere upstream; chosen as the width where
   `agent name (16) + model (12) + calls (6) + cost (9) + padding` first
   stops fitting cleanly. Flag as a value `implementer` should verify
   against the actual ratatui layout math, not treat as final.
6. **Below 40 columns**: out of scope — the shell (E7-1) is not specified
   to support terminals this narrow for any screen; this screen inherits
   that floor rather than setting its own lower one.

## 11. Key bindings

Extends `docs/ui-spec.md` §2's global keymap table — these are additional
to the global keys (`q`, `Ctrl+C`, `?`, `Esc`, tree-navigation keys), not a
replacement:

| Key | Scope | Action | Notes |
|---|---|---|---|
| `r` | analytics screen | manual refresh (FR-4) | re-reads transcript from disk; no-op if already refreshing (input not dropped, just ignored — matches `docs/ui-spec.md`'s "input queued, not dropped" convention for `r` on the tree view) |
| `↑`/`↓`, `j`/`k` | session list | move session cursor | §9. Always this — never remapped by focus. Updates split bar/totals/by-agent table for the newly-selected session in the same frame. |
| `PgUp`/`PgDn` | by-agent panel | scroll by-agent table one page | §9. Never bound to `j`/`k` — that pair is reserved for the session list, above, so the same key never means two things. |

`Tab`/`Shift+Tab` are not available to this screen — `docs/architecture-e7.md`
gives the shell global ownership of them for screen-switching, and the shell
does not forward them to the active screen.

Where shown: the footer status line (present on every state, §3-§7) always
lists the two or three keys live on the current screen, plus `?` for the
full overlay — same convention as `docs/ui-spec.md`'s existing footer/help
overlay pattern (§2 there), not a new one invented for this screen.

## 12. Accessibility position on colour

Per `docs/design-system.md` §1 (binding on this screen, restated because
it's the one rule this whole spec leans on hardest): every colour-coded
distinction here has a working non-colour fallback, verified explicitly:

- Split bar: fill pattern (which side is solid `█` vs `░`) carries the
  split, not colour — a monochrome or `NO_COLOR` viewer sees the same
  proportions, colourblind or not.
- Verdict: word form (`[ALL MAIN]` / `[MOSTLY MAIN]` / `[DELEGATED]` /
  `[NO BILLED ACTIVITY]`) is present at all times, not conditionally on
  `NO_COLOR` — this is the primary fallback and it's always rendered, per
  §1's binding rule that fallbacks are not degraded-mode-only additions.
- Stale/error/warning: `⚠`/`✗`/`!` glyphs plus full-word labels
  ("STALE", "ERROR", failed reason text) — none of these states is
  colour-only anywhere in this spec.
- Under `NO_COLOR` or a `terminfo` failure (`docs/design-system.md` §1
  detection rule), every mockup above renders identically minus the ANSI
  codes — verified by construction, since none of the mockups use colour
  to convey information not already present in the glyph/word text shown.

## Assumptions

- [assumed] Verdict thresholds (40%/80% main share, §8.2) — not specified
  upstream, chosen for margin against the two named real sessions, flagged
  as configurable.
- [assumed] Minimum viable width of 60 columns (§10) — not specified
  upstream, derived from column-fit arithmetic, not verified against actual
  ratatui measurement.
- [assumed] Row sort order within the by-agent table (cost descending)
  follows `now.json`'s existing `byAgent` array order; not independently
  confirmed against `measure-tokens.js`'s sort implementation.
- [observed] Session list order is most-expensive-first — settled by the
  user, no longer assumed (§9).
- [observed] `Tab`/`Shift+Tab` are unavailable to this screen —
  `docs/architecture-e7.md` reserves them for shell screen-switching (§9,
  §11).

## Not covered

- Exact ratatui widget types (`Gauge` vs custom-drawn bar, `List` vs
  `Table`) — implementation detail for `architect`/`implementer`.
- ANSI escape sequences and exact ratatui `Style` calls — same.
- The shared-fixture transcript's exact contents (FR-6) — that's a data/test
  artifact, not a UI concern; owned by the ADR `docs/prd-analytics-tui.md`
  still names as open, per `architect`.

## Open

- **[OPEN: architect]** The verdict thresholds (§8.2) and minimum width
  (§10) are placeholder-reasonable values, not requirements — worth a
  one-line confirmation before `implementer` hand-tunes them differently
  under time pressure. [Update: `analytics/screen.rs` has since adopted
  both as named constants — confirmed as-is, see summary.]
</content>
