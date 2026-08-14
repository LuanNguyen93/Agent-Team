# UI spec: Agent-Team TUI

- **Date**: 2026-08-13
- **Author**: `ux-designer`
- **Sources**: `docs/prd.md` (FR-2, FR-4, FR-5, FR-6, FR-7), `docs/architecture.md`,
  ADR-0003 (mode detection), ADR-0004 (schema), ADR-0006 (edit/write path)
- Tokens, colour roles, glyphs and the spacing/type rules referenced throughout
  are defined in `docs/design-system.md` — this document does not repeat them.
- Every claim is labelled `[observed]`, `[inferred]` or `[assumed]` per
  `handoff-contract`. Unlabelled prose inside a wireframe is UI copy, not a
  claim.

## 0. Ground rules

- **Floor**: every screen specified at 80×24. A 120×40 note follows each
  screen only where more space is actually used for something (most screens:
  wider tree names, more visible list rows — not new panels).
- **`NO_COLOR` / monochrome**: every wireframe below is drawn in plain text
  with glyph prefixes exactly as it would render with colour off. Nothing in
  this spec relies on colour to be understood — verify that by covering the
  glyph column and reading the doc; if meaning is lost, that's a bug in this
  spec, not an acceptable state.
- **No independent parsing**: everything the TUI shows comes from the
  scanner's JSON (`ui.rs` never touches disk) [observed,
  `docs/architecture.md` "Components"]. A screen that looks empty because the
  document says it's empty is correct; a screen must never look empty because
  the TUI failed to read something — that's the error state, not the empty
  state.

## 1. Screen inventory

| # | Screen | Entered from | FR |
|---|---|---|---|
| 1 | Startup / mode resolution | process start | FR-2 |
| 2 | Mode-blocked (undetermined/ambiguous) | startup, exit 2 | FR-2 |
| 3 | Tree view (main screen) | after successful scan | FR-4 |
| 4 | Entity detail pane | `Enter` on a tree row | FR-4 |
| 5 | Findings panel | `f` from tree view, or auto-surfaced | FR-1, FR-3, FR-4 |
| 6 | Frontmatter editor | `e` on an editable entity | FR-5, FR-6 |
| 7 | Save confirmation / rejection | `Ctrl+S` from editor | FR-5, FR-6 |
| 8 | `.agent-team.json` editor (user mode) | `j` from tree view | FR-7 |
| 9 | Help overlay | `?` from anywhere | global |
| 10 | Fatal error screen | any unrecoverable failure | FR-4 failure path |
| 3a | Maintainer-mode staleness banner (state of screen 3) | startup, maintainer mode, `srcHash` mismatch | ADR-0002 |

## 2. The keymap

One table, global. "Global" keys work on every screen unless a panel is
mid-edit (noted). Terminals commonly swallow `Ctrl+S` (XOFF) and some swallow
`Ctrl+Q`; both have a non-chord alternative for that reason — no action in
this tool depends on a single chord with no fallback.

| Key | Scope | Action | Notes |
|---|---|---|---|
| `q` | global, not mid-edit | quit | mid-edit: prompts unsaved-changes first (§6.5) |
| `Ctrl+C` | global, always | quit immediately | only key that works even mid-edit, mid-write; unsaved changes are discarded, TUI says so on exit |
| `?` | global | open help overlay | overlay lists every key below with word-form glyphs |
| `Esc` | global | close overlay / cancel current field edit / back out one level | never closes the whole app — `q`/`Ctrl+C` only |
| `r` | tree view, detail pane, findings | re-scan | shows scanning spinner in header; input queued, not dropped (§7) |
| `↑` `↓` / `j` `k` | list/tree panels | move selection | `j`/`k` only when not conflicting with an active text field |
| `←` `→` / `h` `l` | tree | collapse / expand a node | |
| `Tab` | multi-panel screens | move focus between panels | doubled border marks focus (design-system §5) |
| `Enter` | tree/list row | open detail pane for the row | |
| `f` | tree view | jump to findings panel | badge shows count when > 0 |
| `e` | detail pane, on an editable entity | open frontmatter editor | disabled (greyed + `[locked]` label) when `parsed: false` |
| `j` | tree view, user mode only | open `.agent-team.json` editor | absent from the keymap hint bar entirely in maintainer mode, not just disabled — see §9 |
| `Tab` (in editor) | editor | move to next field | |
| `Enter` (in editor, on a field) | editor | commit this field's typed value into memory (not disk) | field shows `●` until saved or reverted |
| `Ctrl+S` **and** `s` | editor | save (run pre-write check, then write) | `s` is the fallback for terminals that eat `Ctrl+S` |
| `Esc` (in editor, field not focused) | editor | abandon the whole edit session | second confirm if any field shows `●` (§6.5) |
| `Ctrl+U` | editor, focused field | clear the current field to empty | distinct from `Esc` — clears one field, doesn't abandon the session |
| `--mode maintainer\|user` | CLI flag, not a keypress | override detected mode | only way past screen 2 |
| `--path <dir>` | CLI flag | override project root (user mode) | |
| `--plugin-root <dir>` | CLI flag | override plugin root | |

Rules that keep this consistent:
- Every destructive action (`q` mid-edit, `Esc` abandoning edits) confirms
  once, in place, never as a modal that steals a whole screen.
- No two keys on the same screen do different things depending on hidden
  state, except `Esc`, whose behaviour is always "undo the smallest possible
  unit" (one field → one edit session → one overlay), which is one rule, not
  several.
- `Ctrl+C` is the one universal escape hatch specifically because chord
  swallowing is a real risk everywhere else — if every other key were somehow
  unavailable, quitting must still work.

## 3. Screen 1 — Startup / mode resolution

Transient (typically under a second per the scanner's 2s NFR budget) but must
render *something* the instant scanning takes visibly longer than instant, so
the terminal doesn't look hung.

### Loading (shown only if scan exceeds ~150ms — avoid a flash for the common fast case)

```
┌ agent-team ──────────────────────────────────────────────────────────────┐
│                                                                            │
│   Resolving plugin root and mode...                                      │
│   Scanning plugins/agent-team ...                                        │
│                                                                            │
│   [ this can take a few seconds on a large tree ]                        │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```
No spinner glyph animation is specified — a static message is sufficient at
this budget and avoids terminals that render spinner frames as garbage
scrollback. [assumed]

### Populated → falls straight through to Screen 3 (tree view). There is no
separate "success" screen — mode and root are shown permanently in the tree
view's header (§4.1), never only flashed once.

## 4. Screen 2 — Mode-blocked

Reached when the scanner exits 2 with mode `ambiguous` or `undetermined`
(ADR-0003). **All read/edit actions are blocked** — this is not a degraded
tree view, it is a dead end until re-invoked with `--mode` [observed, PRD FR-2
acceptance criteria].

```
┌ agent-team — MODE UNDETERMINED ───────────────────────────────────────────┐
│                                                                            │
│  ✗ Could not determine whether this is a maintainer checkout or an        │
│    installed copy.                                                       │
│                                                                            │
│  Resolved plugin root:                                                   │
│    /home/user/some/path/tui                                              │
│                                                                            │
│  Probe results:                                                          │
│    SOURCE    (marketplace.json + .git present)     : no                  │
│    INSTALLED (path contains plugins/cache/)         : no                 │
│                                                                            │
│  Neither signal matched. This tool will not guess.                       │
│                                                                            │
│  Re-run with an explicit mode:                                           │
│    agent-team-tui --mode maintainer                                      │
│    agent-team-tui --mode user                                            │
│                                                                            │
│  q  quit                                                                 │
└────────────────────────────────────────────────────────────────────────────┘
```

The **ambiguous** case (both probes hit) uses the identical layout with
`both: yes` in the probe table and the header reading `MODE AMBIGUOUS`. Same
remedy, same two commands offered — the fix is identical from the user's side
even though the cause differs, so the copy differs by exactly the words that
differ.

`--mode invalid-value` (a usage error, not an ambiguity) is a **different**,
narrower screen — printed to stderr per ADR-0003/scanner contract, not
rendered as a TUI screen at all, since the TUI never launches (exit 2 before
any scan attempt). [inferred from architecture.md's seam table: exit 2 with
no stdout, TUI shows "error screen" — for a bad flag specifically this is
effectively the wrapper/CLI's stderr, since nothing was parsed to render]

## 5. Screen 3 — Tree view (main screen)

**The one thing this screen is for**: let the user find an entity and see its
edges. Findings are secondary (a badge, not a competing panel by default) —
promoting them to equal size with the tree would mean two things compete for
attention on the screen users spend the most time on.

### 5.1 Header (present on every screen after startup, not just this one)

```
agent-team [MAINTAINER]  a1b2c3d 2026-08-01  root: /repo/plugins/agent-team  scanned: 10:04:11Z  findings: 2 ✗ 3 !
```
Mode badge text is always literal (`[MAINTAINER]` / `[USER]`), never colour
alone (design-system §2). `findings: N ✗ M !` is omitted entirely (not shown
as `0 ✗ 0 !`) when there are zero of both — an all-clear header just omits the
segment, since a persistent "0 0" reads as noise on the one screen that's open
the whole session.

**The build stamp is not optional chrome.** ADR-0002 names three enforcement
points for a stale binary and calls the header one of them: "the TUI header
shows the short `srcHash` and build date, so a stale binary is legible even
when a check did not run" [observed, ADR-0002 "Visible always"]. `a1b2c3d` is
the short `srcHash` (7 hex chars, matching `--build-info`'s output), followed
by the build date — both come from the wrapper/binary at start-up, not the
scanner document, and stay fixed for the whole session (a re-scan does not
change the binary that is running). Unlike the findings segment, this pair is
**always shown**, even when nothing is stale — staleness is a maintainer-mode
banner (§5.1a below), not a reason to hide the stamp in user mode.

### 5.1a Maintainer-mode staleness banner

The second of ADR-0002's three enforcement points: in **maintainer mode
only** — a user-mode tree is always a copy, so the check would only cost
startup time and never fire [observed, ADR-0002 "the user's tree is a copy,
the hash always matches"] — the wrapper recomputes `srcHash` from the working
tree and compares it to the running binary's embedded `--build-info` value.
On a mismatch it shows a banner: **warn, do not block** [observed, ADR-0002:
"it warns; it does not block, because refusing to run the tool a maintainer
is mid-edit on would be hostile"]. This is a state of the tree view (and every
screen after it, since the header persists), not a separate screen — it does
not gate startup and nothing behind it is disabled:

```
agent-team [MAINTAINER]  a1b2c3d 2026-08-01  root: /repo/plugins/agent-team  scanned: 10:04:11Z  findings: 0
┌──────────────────────────────────────────────────────────────────────────┐
│ ⚠ This binary was built from different source than the tree on disk.     │
│   Run tui/build-local.sh or cargo run to pick up your edits.             │
└──────────────────────────────────────────────────────────────────────────┘
┌ TREE ══════════════════════════════════╗┌ EDGES ───────────────────────────┐
```
The banner sits between the header and the tree, as an inset the same width
as the panels below it — not a modal, not a full-screen interrupt — and
persists for the session (checked once at startup, not polled, matching the
"no filesystem watching" rule elsewhere in this spec). It carries the same
`⚠` glyph as an unparsed entity but is text-first: the sentence names the
problem and the fix without relying on the glyph to carry either. Dismissible
with any key that would normally act on the tree below it — it does not
consume a keypress of its own, since blocking interaction over a warning
would contradict "warn, do not block."

If no SHA-256 tool is available to perform the comparison, the check is
**skipped, and says so** rather than silently passing [observed, ADR-0002 /
`CLAUDE.md` "absent must report as absent, not as a pass"]:
```
│ ⚠ Staleness check skipped: no sha256 tool found (tried sha256sum,         │
│   shasum, openssl). Build stamp above may not reflect the tree on disk.   │
```

### 5.2 Populated, 80×24

```
agent-team [MAINTAINER]  a1b2c3d 2026-08-01  root: /repo/plugins/agent-team  scanned: 10:04:11Z  findings: 1 ✗ 2 !
┌ TREE ══════════════════════════════════╗┌ EDGES (implementer) ────────────┐
│▶ AGENTS (11)                            ║│ ↔ tdd-discipline                │
│  analyst                                ║│ ↔ handoff-contract              │
│  architect                              ║│ → design-intelligence           │
│  backend-implementer                    ║│   (declared, not seen loaded)   │
│  debugger                               ║│                                 │
│  frontend-implementer                   ║│                                 │
│  implementer                            ║│                                 │
│  ⚠ planner  [unparsed]                  ║│                                 │
│  pm                                     ║│                                 │
│  qa-verifier                            ║│                                 │
│  reviewer                               ║│                                 │
│  ux-designer                            ║│                                 │
│ SKILLS (18)                             ║│                                 │
│ COMMANDS (4)                            ║│                                 │
├──────────────────────────────────────────┤                                 │
│ e edit  f findings  j .agent-team.json ↑↓ move  Enter open  ? help  q quit │
└────────────────────────────────────────────────────────────────────────────┘
```
- Doubled border on `TREE` marks it focused (`Tab` moves focus to `EDGES`).
- `implementer` is selected (`▶`); the right panel shows its edges live —
  this is the load-bearing interaction, so it updates on every `↑`/`↓`, not
  only on `Enter`.
- `↔` = matched edge, `→` = declared-only (colour: `warning` role, but the
  glyph and the parenthetical word carry the meaning without colour) — per
  FR-4's acceptance criterion that a mismatch is "visually distinguished," this
  is done with glyph + inline text, not shading alone.
- The unparsed `planner` row: `⚠` glyph, `[unparsed]` literal suffix, and (not
  visible in monochrome-safe terms above, but true) rendered dim/red when
  colour is on. Selecting it shows no edge panel content — instead:
  `EDGES` panel reads `— entity is unparsed, no edges available —`.
- Keymap hint bar is always visible at the bottom of the tree view specifically
  (not every screen) because it's the screen new users land on most.
- The `j` hint (`.agent-team.json`) is present because this render is
  maintainer mode... **correction, this is the bug case to avoid**: in
  maintainer mode `j` must NOT appear in the hint bar or the keymap at all
  (§9). The wireframe above is drawn for **user mode**; the maintainer-mode
  hint bar reads:
  `e edit  f findings  ↑↓ move  Enter open  ? help  q quit` (no `j`).

### 5.3 Long name / column overflow

A name wider than the panel truncates with `…` and the full name is always
recoverable in the detail pane (Enter) — never lost:

```
│  a-genuinely-too-long-agent-name-that-e…║
```
Truncation point: panel width minus the deepest-visible indent minus 1 column
for the ellipsis. Never truncates mid-multibyte-character (counts by rune, not
byte, matching ADR-0004's character-based length rule).

### 5.4 200-entry findings badge / long lists

The tree itself doesn't grow unboundedly (33 entities today, and the schema
has no soft cap), but **findings** can, and the PRD's 500-synthetic-agent edge
case means the findings list realistically can hit hundreds. The tree view
never inlines the findings list — it's summarized in the header badge and the
full list lives in Screen 5, which is scrollable (§8).

### 5.5 Empty states

- **Zero skills** (FR-4 edge case, explicit acceptance criterion): the
  `SKILLS (0)` tree node is still shown, expandable to reveal one line:
  `— no skills found under skills/ —`. Never a blank collapsed node with no
  explanation for why it has nothing under it.
- **Zero agents, zero commands**: same pattern, each independently — the three
  sections don't disappear, they each say what's missing in their own row.
- **One agent, zero declared skills** (FR-4 edge case): `EDGES` panel reads
  `— no skills declared —`, not a blank panel (which would be indistinguishable
  from "still loading" or "nothing selected").

### 5.6 120×40 gain

Wider: tree names stop truncating for all but the extreme outliers, and the
`EDGES` panel gains a third column showing each edge's source (`declared` /
`body` / `both`) spelled out instead of only glyphed. Taller: more tree rows
visible without scrolling — 33 entities fit without scrolling at 40 rows;
findings panel (if open side-by-side, layout below) shows more rows per page.

At 120×40 only, findings may render as a **third column** beside TREE/EDGES
instead of requiring `f` to switch — this is additive screen real estate, not
a different information architecture, so 80×24 users lose nothing but a
convenience.

## 6. Screen 4 — Entity detail pane

Reached via `Enter` on a tree row. Shows every field from the schema for that
entity (ADR-0004), read-only, plus an `[e] edit` hint if `editableFields` is
non-empty and `parsed: true`.

```
┌ implementer  (plugins/agent-team/agents/implementer.md) ─────────────────┐
│ name         implementer                                                 │
│ description  Executes an approved plan using strict red-green-refactor…  │
│              (312 / 1536 chars)                                          │
│ model        sonnet                                                      │
│ color        green                                                       │
│ skills       tdd-discipline, handoff-contract, design-intelligence       │
│ loadedSkills tdd-discipline, handoff-contract                            │
│ forbidden    (none)                                                      │
│                                                                            │
│ e edit   Esc back                                                        │
└────────────────────────────────────────────────────────────────────────────┘
```
An agent has no `when_to_use` field [observed, `docs/architecture.md` "Data
model": an Agent carries `name`, `description`, `model`, `color`, `skills`;
only a Skill carries `description` + `when_to_use`]; its `descriptionLength`
cap is counted on `description` alone, so the length line reads
`(N / 1536 chars)` with no "combined with when_to_use" clause. A **skill's**
detail pane is the one that shows the combined count, since the 1536 cap
there is `descriptionLength + whenToUseLength` together:
```
┌ tdd-discipline  (plugins/agent-team/skills/tdd-discipline/SKILL.md) ──────┐
│ name          tdd-discipline                                             │
│ description   Enforce red-green-refactor when writing or changing code…  │
│               (198 / 1536 chars combined with when_to_use)               │
│ when_to_use   Any code-writing task. Do NOT use for pure reads…          │
│                                                                            │
│ e edit   Esc back                                                        │
└────────────────────────────────────────────────────────────────────────────┘
```
Description truncates with `…` at panel width; full text available by opening
the editor (view mode there shows the untruncated textarea, read-only, before
any field is focused for edit).

**Unparsed entity** (`parsed: false`) detail pane:
```
┌ planner  (plugins/agent-team/agents/planner.md)  ⚠ UNPARSED ─────────────┐
│ Reason: FRONTMATTER_UNPARSABLE — unterminated --- block                  │
│                                                                            │
│ This entity's frontmatter could not be parsed. It is shown using only    │
│ its filename. Editing is disabled here — open the file directly.         │
│                                                                            │
│ Esc back   (no [e] hint — edit is not offered)                           │
└────────────────────────────────────────────────────────────────────────────┘
```

## 7. Screen 5 — Findings panel

```
agent-team [MAINTAINER]  a1b2c3d 2026-08-01  root: /repo/plugins/agent-team  scanned: 10:04:11Z  findings: 1 ✗ 2 !
┌ FINDINGS (3) ══════════════════════════════════════════════════════════╗
│▶ ✗ FORBIDDEN_FIELD        agents/planner.md                             │
│    hooks: present — plugin subagents silently ignore this field         │
│  ! SKILL_DECLARED_NOT_LOADED  agents/implementer.md → design-intell…    │
│  ! SKILL_DECLARED_NOT_LOADED  agents/reviewer.md → tdd-discipline       │
│                                                                            │
│                                                                            │
├────────────────────────────────────────────────────────────────────────────┤
│ ↑↓ move  Enter jump to file's entity  Esc back  ? help                  │
└────────────────────────────────────────────────────────────────────────────┘
```
Sorted per ADR-0004: severity, then code, then file — so `✗ error`s are always
first and stable across re-scans. `Enter` on a finding jumps to Screen 4 for
the named entity (or the first-named entity if `relatedFiles` has more than
one, e.g. a `NAME_COLLISION`).

### 200-entry findings list

Scrolls; a fixed **page indicator** replaces the blank space at the bottom
when the list exceeds the visible rows:
```
│ … 184 more (Enter on ▶ row still works; PgDn / PgUp to scroll)          │
```
No pagination clicks required — continuous scroll with `↑`/`↓`/`PgUp`/`PgDn`.
The count in the header badge (`findings: 1 ✗ 2 !`) is always the true total,
not "showing X of Y" — the panel's own scroll affordance carries that.

### Empty findings

```
┌ FINDINGS (0) ══════════════════════════════════════════════════════════╗
│  ✓ No findings. The tree is clean.                                      │
│                                                                            │
│  This does not replace `claude plugin validate` — run that separately   │
│  before publishing a change.                                            │
└────────────────────────────────────────────────────────────────────────────┘
```
Per PRD FR-6/brief.md constraint 6, the tool must never imply full validation
happened — this reminder is permanent on the clean-findings state, not a
one-time toast.

## 8. Screen 6 — Frontmatter editor

**The highest-risk flow.** Full end-to-end spec below; every step maps to
ADR-0006's seven write-mechanics steps and PRD FR-5/FR-6's acceptance criteria.

### 8.1 Entry

`e` from Screen 4, only when `parsed: true` and `editableFields` is non-empty.
If `editableFields` is empty (every field is a block scalar, anchor, or flow
collection — ADR-0006), `e` is not offered at all; Screen 4 shows instead:
```
│ This file's frontmatter uses a shape the editor cannot safely edit       │
│ (block scalars / anchors). Open it directly: agents/whatever.md          │
```

### 8.2 Editing, in-memory only

```
┌ EDIT implementer  (agents/implementer.md) ────────────────────────────────┐
│                                                                            │
│  name          implementer                                               │
│  description   Executes an approved plan using strict red-green-refac…  │
│                 ● 314 / 1536 chars                                       │
│  model          sonnet                                                   │
│▶ color        ● green_                                                   │
│  skills        tdd-discipline, handoff-contract, design-intelligence     │
│                                                                            │
│  Tab next field   Enter commit field   Ctrl+U clear field                │
│  s / Ctrl+S save   Esc abandon edit                                      │
└────────────────────────────────────────────────────────────────────────────┘
```
- `●` marks any field changed from its on-disk value this session (design-
  system §6) — appears the instant a keystroke changes a field, clears if the
  field is edited back to its original value.
- Cursor (`_`) shown in the focused field only; nothing else on this screen
  animates.
- **The editor has no add-key path at all** [observed, `docs/architecture.md`
  "Key flows" §3: "The editor adds no keys"]. `editableFields` only ever lists
  existing scalar/list keys, and `hooks`/`mcpServers`/`permissionMode` are not
  editable values on any field — they are only ever *removable*, via the
  narrow `removableFields` affordance (§8.2a below). There is therefore
  nothing for a keystroke-time check to catch: a forbidden field cannot be
  typed in, on this or any field, so no local shape-matching rule set is drawn
  here. Per ADR-0006, the TUI holds no validation rules of its own; the
  scanner is the only authority on what a field means.
- **What protects the user instead**: a file that already carries a forbidden
  field is a scanner `FORBIDDEN_FIELD` **error** [observed,
  `docs/architecture.md` "Failure modes"], visible on the entity in the tree
  (§5.2) and in the findings panel (§7), and it **blocks every save of that
  file** — `check` returns `severity: error` and Screen 7's rejection view
  (§8.4) fires — until the field is removed. This is the scanner's rule,
  enforced at the one seam that exists (`check`), not a second rule set in the
  editor.

### 8.2a Removing a forbidden field

The one exception to "no field is ever added or removed" (ADR-0006): a key
listed in `removableFields` — only ever `hooks`, `mcpServers` or
`permissionMode`, and only when the scanner located its exact line span — gets
a delete affordance so a file blocked by `FORBIDDEN_FIELD` has a way back:

```
┌ EDIT planner  (agents/planner.md)  ⚠ 1 finding on this file ──────────────┐
│                                                                            │
│  name          planner                                                   │
│  description   Turns a story or a request into a concrete…               │
│  hooks         { pre: "..." }                          [x] remove field  │
│                 ✗ FORBIDDEN_FIELD — plugin subagents silently ignore this │
│                                                                            │
│  Tab next field   x remove field (on a removable field)                  │
│  s / Ctrl+S save   Esc abandon edit                                      │
└────────────────────────────────────────────────────────────────────────────┘
```
`x` on a focused removable field marks it for deletion (shown struck through
or `[removed]`, not blanked — the user can still see what will disappear) and
sets `●` exactly as any other change does. Save goes through the identical
`check` → write path (§8.4): if removing the field clears the
`FORBIDDEN_FIELD` error and nothing else fails, the write proceeds; if it
does not (e.g. another error remains), the rejection view lists what's still
wrong, same as any other save.

### 8.3 Clearing a required field

```
│  name          _                                                         │
│                ✗ name cannot be empty — required field                   │
```
Shown inline, immediately on `Ctrl+U`/empty commit, not deferred to save time
(FR-5 edge case: "rejected with a specific message, not a silent no-op"). This
inline message is presentation only — a hint, not a verdict. `NAME_MISSING`
[observed, `docs/architecture.md` "Failure modes" / ADR-0004 finding codes] is
a scanner rule, and per ADR-0006 the TUI holds no rule of its own that could
stand in for it. So pressing `s` still runs the full save sequence: the
candidate (with the empty `name`) is written to a temp file and
`scanner.sh check` is still invoked against it (§8.4) — the local hint does
not short-circuit that call. In practice the scanner will reject it with the
same `NAME_MISSING` finding, so the visible result is unchanged from before;
the difference is that the verdict comes from the one place empowered to give
it, at the cost of one subprocess call, which ADR-0006 already accepts as the
price of a single rule set.

### 8.4 Save → pre-write check (Screen 7)

`s` / `Ctrl+S` triggers, matching ADR-0006 steps 1–4:

```
┌ EDIT implementer — checking… ─────────────────────────────────────────────┐
│                                                                            │
│  Running scanner.sh check against the full tree...                       │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```
This is a real subprocess call (ADR-0006: "saves will feel like they take a
beat") — always show this transitional state, even if it resolves in under
100ms, so a save never looks like nothing happened.

**Check passes → write succeeds:**
```
┌ SAVED ─────────────────────────────────────────────────────────────────┐
│                                                                            │
│  ✓ agents/implementer.md written.                                        │
│                                                                            │
│  claude plugin validate has NOT been run — that remains your job.        │
│  This is an agent file: run /reload-plugins for the change to take       │
│  effect in a running session.                                            │
│                                                                            │
│  Enter back to tree (re-scanned)                                          │
└────────────────────────────────────────────────────────────────────────────┘
```
Both reminders are always shown together on every successful agent-file save,
worded plainly, per ADR-0006 step 7 and PRD FR-6's acceptance criterion — never
abbreviated to a bare "Saved." Non-agent files (skills) omit only the
`/reload-plugins` line, not the `claude plugin validate` line.

**Check fails → write refused, ALL failing checks shown together (not just
the first — FR-6's explicit multi-failure acceptance criterion):**
```
┌ SAVE REJECTED — nothing was written ──────────────────────────────────────┐
│                                                                            │
│  ✗ NAME_COLLISION                                                        │
│    "implementer" also used by agents/backend-implementer.md              │
│                                                                            │
│  ✗ DESCRIPTION_TOO_LONG                                                  │
│    description + when_to_use = 1541 chars (limit 1536)                  │
│                                                                            │
│  The file on disk is unchanged. Fix the fields below and save again,     │
│  or Esc to abandon this edit entirely.                                   │
│                                                                            │
│  ↑↓ jump to a listed field   s retry save   Esc abandon                  │
└────────────────────────────────────────────────────────────────────────────┘
```
`Enter`/`↑↓` on a listed rejection jumps focus back to Screen 6 with that
specific field focused and the `✗` reason shown inline next to it (same inline
pattern as §8.3), so the user isn't left cross-referencing an error list
against a form by hand. The user stays in the edit session — nothing is lost,
all `●` marks persist — this is a **recoverable** state, not a dead end.

This draws correctly against the schema: each finding carries its own
`field` — [observed, ADR-0004: "`field` string — the frontmatter key this
finding is about, when it is about one. Lets the editor focus the offending
field instead of making the user guess"]. The jump target is that field
directly; the TUI does not map finding codes to fields itself, it reads the
mapping the scanner already sent. A finding with no `field` (e.g.
`NAME_COLLISION`, which is about the *value* shared across files rather than
one field in isolation — though the example above names `name` specifically
since that is the colliding key) still renders in the list; `↑↓` on a
fieldless finding jumps to the top of the form instead of a specific field,
since there is nothing more specific to jump to.

### 8.5 Abandoning an edit (`Esc`, or `q`)

If no field carries `●`: exits immediately, no prompt (nothing to lose).

If any field carries `●`:
```
┌ Discard unsaved changes? ──────────────────────────────────────────────┐
│  2 fields changed (description, color) will be lost.                    │
│  y discard   n / Esc stay                                               │
└────────────────────────────────────────────────────────────────────────────┘
```
Rendered as a one-line-taller inset within the same screen (not a full-screen
replacement) — consistent with §2's rule that confirmations happen in place.

### 8.6 File changed on disk mid-edit (ADR-0006 step 5)

Detected at save time, not continuously polled (no filesystem watching per
architecture's rejected-options list). If `stat` at save time disagrees with
the read-time snapshot:
```
┌ SAVE REJECTED — file changed since you opened it ─────────────────────────┐
│                                                                            │
│  agents/implementer.md was modified or deleted outside this session.     │
│  Nothing was written. Your in-progress edits are still here.             │
│                                                                            │
│  r  re-scan and reload the file (discards your changes)                  │
│  Esc  abandon                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```
**Ruling: no "retry save anyway."** An earlier draft offered `s` here.
Removed, for the same reason §11 states as a general rule for this spec: this
precondition failure is deterministic — the mtime/size mismatch that caused
the rejection is still true a moment later, since nothing about retrying
changes it — so `s` would offer an action known in advance to fail the same
way. It is worse than merely useless when the file was **deleted**: there is
then no target to write to at all, and "retry" implies one still exists. The
two live options are the only ones that change anything: `r` re-scans and
reloads the current on-disk state (discarding this session's edits, since
there is no way to merge them against a file the TUI never validated), or
`Esc` abandons. This keeps §8.6 consistent with §11's rule rather than being
the exception to it.

### 8.7 120×40 gain

Field values that would wrap or truncate at 80 columns (long `description`)
show full-width without truncation; the rejection list (§8.4) and the field
form can render side by side instead of the rejection screen replacing the
form, so the user sees both without a screen transition. At 80×24 the
transition is unavoidable and is why §8.4 explicitly returns focus to the
right field rather than leaving the user to remember which field was which.

## 9. Screen 8 — `.agent-team.json` editor (user mode only)

Per architecture.md §4: plain JSON, not frontmatter — no scanner involvement,
no line-surgical editing, straight `serde_json` parse/serialise. Simpler
validation surface, but the disabled/absent states matter as much as the
happy path (FR-7's explicit edge/failure criteria).

**Maintainer mode**: `j` is not in the keymap hint bar at all (§5.2 correction)
and pressing an unbound key does nothing observable — there's no "disabled"
row to click, because the action doesn't exist in this mode's vocabulary. This
is a stronger form of "unavailable" than a greyed-out option: FR-7's
acceptance criterion is "unavailable/disabled," and unavailable-from-the-menu
is more consistent with "maintainer mode has no `.agent-team.json`, full
stop" than a control that's visible but does nothing.

**User mode, file exists:**
```
┌ .agent-team.json  (/project/.agent-team.json) ────────────────────────────┐
│  scope   { "paths": ["src/**"] }                                          │
│  gates   { "test": "npm test", "lint": "npm run lint" }                  │
│                                                                            │
│  s save   Esc abandon                                                    │
└────────────────────────────────────────────────────────────────────────────┘
```
**FR-7 is resolved**: `.agent-team.json` is edited as raw JSON with parse
errors reported, not field-aware [observed, per the task briefing this
document was corrected against]. This screen's raw form — a text area per
top-level key, parsed and re-serialised as JSON with `serde_json`, not typed
fields per key — is therefore the final draw, not a placeholder pending a PM
decision. The `[OPEN: PM]` this section previously carried is closed.

**User mode, file absent:**
```
┌ .agent-team.json — not found ─────────────────────────────────────────────┐
│  No .agent-team.json at /project.                                        │
│  This tool does not create one. See README.md for the format if you      │
│  want to add it by hand.                                                 │
│  Esc back                                                                │
└────────────────────────────────────────────────────────────────────────────┘
```
Explicitly does not offer a "create" affordance — matches PRD FR-7's edge
case and the brief's out-of-scope list.

**User mode, malformed JSON:**
```
┌ .agent-team.json — parse error ────────────────────────────────────────────┐
│  Unexpected token } at line 4, column 12.                                │
│  Shown raw below — this tool will not guess the intended structure.      │
│  ------------------------------------------------------------------      │
│  { "scope": { "paths": ["src/**"] },                                     │
│    "gates": { "test": "npm test" }                                       │
│    }}                                                                     │
│  ------------------------------------------------------------------      │
│  Esc back  (editing disabled — fix the file directly, then r to re-scan) │
└────────────────────────────────────────────────────────────────────────────┘
```

## 10. Screen 9 — Help overlay (`?`, any screen)

A fixed-content overlay listing the full keymap table (§2) filtered to keys
valid on the current screen, plus the glyph legend from `docs/design-system.md`
§6 in word form — this is the one place glyph-to-word mapping is spelled out
in full, so a user who can't tell `↔` from `→` at a glance always has `?` as
the answer.

```
┌ HELP ══════════════════════════════════════════════════════════════════╗
│  GLOBAL                                                                  │
│    q          quit                                                      │
│    Ctrl+C     force quit (always works, even mid-edit)                  │
│    ?          this help                                                 │
│    Esc        cancel current step / go back                            │
│                                                                            │
│  TREE VIEW                                                               │
│    ↑↓ / j k   move   ←→ / h l  collapse/expand   Enter  open            │
│    e          edit    f  findings    r  re-scan                        │
│                                                                            │
│  GLYPHS                                                                  │
│    ▶ selected   ✓ OK / matched   ! WARN   ✗ ERR   ⚠ UNPARSED           │
│    → declared-only   ← loaded-only   ↔ matched edge   ● unsaved         │
│                                                                            │
│  Esc close                                                               │
└────────────────────────────────────────────────────────────────────────────┘
```

## 11. Screen 10 — Fatal error screen

One shared template, filled per architecture.md's failure-mode table (JSON
missing/unparsable, unknown schema MAJOR, scanner/bash missing, an unshipped
target triple — this last one is the **wrapper's** own message, printed
before the TUI binary is ever invoked, styled identically for consistency
even though no Rust process is running yet to draw it):

```
┌ agent-team — cannot continue ─────────────────────────────────────────────┐
│                                                                            │
│  ✗ <one-line problem statement, verbatim from architecture.md's table>   │
│                                                                            │
│  <the specific detail: path tried, versions compared, or first 200       │
│   bytes of unreadable output>                                            │
│                                                                            │
│  <the one remedial action, if one exists — e.g. the scanner.sh command   │
│   that yields the same data without the TUI>                            │
│                                                                            │
│  q quit                                                                  │
└────────────────────────────────────────────────────────────────────────────┘
```
No retry offered from this screen for schema-major mismatch or missing
scanner — those require a fix outside the TUI's control, and offering a `r`
that will deterministically fail again is worse than not offering it
(distinct from Screen 3's `r`, which retries a scan that plausibly succeeds
next time). **This is the general rule for the whole spec: no screen offers a
retry that is known in advance to fail the same way, or that could be
meaningless because the target no longer exists** — see §8.6 below, which
this rule now also governs.

**Unshipped target triple / missing binary for a shipped triple**
[observed, `docs/architecture.md` "Failure modes": "Unshipped target
triple | wrapper | exit 3"; "Binary missing for a shipped triple | wrapper |
exit 3"] replaces the old Node-absent case — the runtime is Rust with
committed per-target binaries, not Node, so there is no interpreter to be
missing; the equivalent failing population is a machine whose OS/arch does
not map to one of the five shipped triples, or a triple we claim to ship but
whose binary is absent from `bin/`. The wrapper (bash, running before any
Rust binary starts) prints this and exits **3**, not the fatal-screen exit
implied by an in-TUI error, because there is no TUI process alive to render a
screen at all — the box-drawing template above is followed as plain stderr
text for visual consistency with the in-TUI version, not rendered by
`ratatui`:

```
agent-team: cannot start — no build for this platform

  Detected: uname -s = Linux, uname -m = riscv64
  Derived target triple: riscv64-unknown-linux-gnu (unrecognised)

  Shipped triples:
    x86_64-pc-windows-msvc
    x86_64-apple-darwin
    aarch64-apple-darwin
    x86_64-unknown-linux-musl
    aarch64-unknown-linux-musl

  Two ways forward:
    - Build from source:  cd tui/rust && cargo build --release
    - Skip the TUI and read the same data as JSON:
        tui/scanner.sh scan --plugin-root <path>

  Exiting 3.
```
A binary that is missing for a triple the wrapper otherwise recognises as
shipped uses the identical template with `Derived target triple:
x86_64-pc-windows-msvc (recognised, but bin/x86_64-pc-windows-msvc/ is
empty or absent)` — **never a silent fallthrough to a different triple's
binary** [observed, `docs/architecture.md` "Binary distribution"].

## 12. Mode visibility — cross-screen summary

Per FR-2, "mode is always displayed, never implicit." Concretely:
- The header (§5.1) is present on **every** screen after startup, including
  the editor and the findings panel — not only the tree view. Screen 2 and
  Screen 10 are the only exceptions, because in both of those no mode was
  successfully resolved (Screen 2) or the header itself may be unrenderable
  (Screen 10) — both states are self-evidently not-yet-in-the-app.
- Mode is never colour-only: `[MAINTAINER]` / `[USER]` is literal text, always
  present, colour is additive.
- Screen 8 (`.agent-team.json`) existing at all as a reachable screen is
  itself a mode signal — but §9 goes further and removes the keymap entry
  entirely in maintainer mode, so the absence is discoverable via `?` too
  (the help overlay in maintainer mode simply never lists `j`).

## Assumptions

- [assumed] a static "scanning…" message (no animated spinner) at startup and
  on save is sufficient; not verified against real terminal emulators.
- [assumed] box-drawing glyphs (`┌─│═║` etc.) render correctly in the target
  terminals; ASCII fallback trigger condition is named in
  `docs/design-system.md` §5 but not decided here.
- [observed, `docs/architecture.md` "Key flows" §3] `hooks` / `mcpServers` /
  `permissionMode` never appear in `editableFields` — they are excluded from
  the editable set entirely and are only ever reachable through the narrow
  removal affordance (§8.2a). No assumption needed here any more; this
  replaces the earlier assumed narrow-trigger note now that architect has
  ruled the editor has no add-key path at all.

## Not covered

- Exact rendering library/escape-sequence choices — `implementer`'s job, not
  design's.
- The 500-finding stress case's *visual* pagination performance (whether
  scrolling 500 rows in `ratatui` without virtualization stays responsive) —
  a technical feasibility question, not a design one; flagging for
  `implementer`/`qa-verifier` to confirm against the NFR's 30s scan budget
  (which is the scanner's budget, not the render's — render-side performance
  at 500 findings is unmeasured).
- CI-facing output (the scanner's raw JSON/stderr) — out of this document's
  scope; that's a CLI contract already fully specified in
  `docs/architecture.md`'s "seam" section, not a UI.

## Open

- **[Closed]** §8.2's warning-at-entry OPEN item is resolved: architect ruled
  the editor gains no add-key path at all, so a forbidden field cannot be
  typed in on any field. §8.2 is redrawn against the scanner's
  `FORBIDDEN_FIELD` error instead of a TUI-side entry warning.
- **[Closed]** §9's field-aware-vs-raw-JSON OPEN item is resolved: FR-7 is
  raw JSON with parse errors reported, not field-aware. §9 now states this
  directly instead of flagging it open.
- **[OPEN: implementer]** Whether box-drawing has a real ASCII fallback mode
  or is assumed always available — named in `docs/design-system.md` §5, not
  resolved here.
