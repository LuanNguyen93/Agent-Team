# Design system: Agent-Team TUI

- **Date**: 2026-08-13
- **Author**: `ux-designer`
- **Scope**: `plugins/agent-team/tui/` only. This is a terminal application —
  there is no font, no border-radius, no shadow, no spacing scale beyond the
  character cell. This document exists to fix the small set of things a TUI
  *does* get to decide, so three screens don't each invent their own answer.

[assumed] unless cited to `docs/architecture.md` or an ADR.

## 1. Hard constraint: colour is decoration, never the only carrier

The tool must be fully legible with `NO_COLOR` set, in a monochrome terminal,
and to a colour-blind user. **Every** colour-coded distinction in this document
has a second, colour-independent encoding (a glyph, a label word, or position)
specified alongside it. If a wireframe below shows colour doing work that has
no glyph fallback next to it, that wireframe is wrong — fix the glyph, not the
prose.

Detection: `NO_COLOR` env var set (any value) → colour off. Terminal reports
no colour capability (`$TERM=dumb`, or a `terminfo` lookup failing) → colour
off automatically, not just on request. There is no partial state — colour is
binary, on or off, for the whole session.

## 2. Colour roles (only used when colour is on)

Sixteen ANSI colours, used **by role**, never decoratively. `ui.rs` maps
role → ANSI code once; nothing else in the codebase names a colour directly.

| Role | ANSI | Used for | Glyph fallback (always present) |
|---|---|---|---|
| `fg.default` | default fg | body text | — |
| `fg.dim` | bright black / `2m` | secondary text (paths, timestamps, hints) | — |
| `accent` | cyan | the focused/selected row, the active panel border | `▶` prefix on the row, doubled border chars |
| `success` | green | write confirmed, scan clean | `✓` prefix |
| `warning` | yellow | `severity: warning` findings, declared/loaded mismatch | `!` prefix |
| `error` | red | `severity: error` findings, rejected write, blocked mode | `✗` prefix |
| `mode.maintainer` | magenta | header mode badge | text reads `[MAINTAINER]` |
| `mode.user` | blue | header mode badge | text reads `[USER]` |
| `unparsed` | red + dim | an entity with `parsed: false` | `⚠` prefix, row rendered in `[unparsed]` brackets |

No 256-colour value is required; if the terminal advertises it (`$COLORTERM`
or `terminfo` `colors ≥ 256`), the same eight roles above may use a closer
shade, but the 16-colour mapping is the floor and must always be correct on
its own.

## 3. Type scale — there isn't one, so use weight and structure instead

No font sizes exist in a terminal. Hierarchy is carried by, in order of
strength:

1. **Position** — header row (row 1) > panel title (row 2) > content.
2. **Bold** (`\x1b[1m`, degrades to nothing under `NO_COLOR`+no-bold terminals
   — acceptable, position still carries it).
3. **Case** — panel titles are UPPERCASE, content is not. This survives every
   terminal and every colour setting; it is the one hierarchy signal that
   never degrades.
4. **Indentation** — tree depth, 2 columns per level (§4).

## 4. Spacing scale

The only unit is the character cell. The scale is: **0, 1, 2 columns**, used
consistently:

- **1 column** — between a glyph/icon and its label (`✓ ` , `▶ `).
- **2 columns** — one tree-indent level; padding inside a bordered panel.
- **0** — never insert a blank column "for balance". If two elements are not
  related, put them in different panels, not extra gaps in one.

Vertical spacing: a single blank row separates unrelated sections within a
panel (e.g. findings list from the summary line below it). No panel ever has
more than one blank row in a row — that's dead space, not grouping.

## 5. Borders and panels

Single-line box-drawing (`─│┌┐└┘├┤`) for all panels — works in every terminal
that has any box-drawing glyphs at all. The **focused** panel gets a doubled
border (`═║╔╗╚╝`) — this is the accent role's glyph fallback, so panel focus
is never colour-only.

If box-drawing glyphs are unavailable (`--ascii` flag or detected `$TERM` that
predates UTF-8 assumptions — [assumed] a real but rare case), fall back to
`+`, `-`, `|` for all panels and `=` for the focused one. This is a build
decision for `implementer`, named here so it isn't invented ad hoc mid-render.

## 6. Iconography

No emoji (illegible in many terminal fonts, and CLAUDE.md's English-only /
professional-tool bar applies here too). ASCII/box-drawing glyphs only, each
with a word alternative available on request (`?` help overlay lists them,
§ keymap below):

| Glyph | Meaning | Word form (shown in help / narrow columns) |
|---|---|---|
| `▶` | selected / focused row | `>` |
| `✓` | success / matched edge | `OK` |
| `!` | warning finding | `WARN` |
| `✗` | error finding / rejected | `ERR` |
| `⚠` | unparsed entity | `UNPARSED` |
| `→` | declared-but-not-loaded edge | `-->` |
| `←` | loaded-but-not-declared edge | `<--` |
| `↔` | matched edge (both directions confirmed) | `<->` |
| `●` | modified-but-unsaved field | `*` |
| `…` | truncated text (name, description) | `...` |

## 7. States every screen must define (see `docs/ui-spec.md` for the per-screen instances)

Loading, empty, error, populated — plus, specific to this tool: **blocked**
(mode undetermined/ambiguous — a fifth state most components don't need, this
one does, per FR-2) and **stale-input** (a keystroke arrives while a
subprocess is running — must queue or drop, never crash).

## Assumptions

- [assumed] terminal supports UTF-8 box-drawing by default; ASCII fallback
  named but its trigger condition is `implementer`'s to wire up.
- [assumed] bold (`\x1b[1m`) is safe to emit unconditionally — universally
  supported enough that no fallback is specified beyond "degrades to plain
  text harmlessly."

## Not covered

- No web design tokens (radius, shadow, elevation) — do not apply; this is a
  terminal.
- Exact ANSI escape sequences / library calls — `implementer`'s job.

## Open

- **[OPEN: implementer]** Whether `--ascii` is a real flag or box-drawing is
  simply always assumed. Named in §5 as a decision this document does not
  make.
