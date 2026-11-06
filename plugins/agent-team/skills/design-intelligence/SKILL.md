---
name: design-intelligence
description: Design a coherent UI - style direction, colour, typography, spacing, and UX behaviour - so generated interfaces look deliberate rather than machine-assembled. Use when building or reviewing any user-facing screen.
when_to_use: Creating a design system, laying out a screen, choosing colours or fonts, or reviewing UI quality. Do NOT use for charts and dashboards - use the dataviz skill for those.
---

# Design intelligence

Most AI-generated UI fails the same way: every element is technically fine, but
nothing relates to anything. Even spacing everywhere, one weight of text, a
purple gradient, cards with equal emphasis. It reads as assembled, not designed.

The fix is **hierarchy and consistency**, not decoration.

## Method

Work in this order. Skipping to the last step is what produces the generic look.

### 1. Decide the one thing the screen is for
Name the primary action or the primary information. Everything else is
secondary and must look it. A screen where three things compete equally has no
hierarchy, and the user has to do the sorting.

### 2. Pick a style direction, once
Choose one and commit. Mixing directions is what makes a UI feel unresolved.
See `references/styles.md` for the catalogue and when each fits.

### 3. Build the token set before any component
Colour, type scale, spacing scale, radius, shadow, border. Components consume
semantic tokens; they never hardcode raw hex values or arbitrary pixel values.
This is what makes a system feel like one cohesive product.

- Colour: Semantic hierarchy (`primary`, `primary-foreground`, `surface`, `muted`, `muted-foreground`, `accent`, `destructive`, `border`, `ring`) in `references/palettes.md`
- Type: `references/typography.md`
- Machine-readable token template: `references/tokens.json` (`color`, `pairs`, `font`, `type`, `space`, `radius`, `shadow`, `motion`)

Run the deterministic WCAG 2.2 contrast checker against your token file (or two hex colours directly) after every palette choice or rebrand:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/design-intelligence/scripts/contrast.py" docs/tokens.json
python3 "${CLAUDE_PLUGIN_ROOT}/skills/design-intelligence/scripts/contrast.py" "#5b6470" "#ffffff"
```

Exit code `1` (any AA failure: `< 4.5:1` normal text, `< 3.0:1` large text or UI boundaries) blocks handoff and must be fixed in the tokens, never per-component.

### 3b. Design System Architecture: Primitives, CVA & Composition
Expert frontend engineering treats UI as a composable Design System, never as ad-hoc utility strings:

1. **Atomic Primitives First**: Build or reuse atomic primitives (`Button`, `Input`, `Dialog`, `Card`, `Badge`) before assembling screens.
2. **Class Variance Authority (CVA)**: Manage component variants (`primary`, `secondary`, `outline`, `destructive`) and sizes (`sm`, `md`, `lg`) using CVA or strict typed variant maps. Never concatenate dynamic strings with ternary spaghetti.
3. **Slot & `asChild` Composition**: Support polymorphic rendering (e.g., a button rendered as an `<a>` link) via Slot composition (Radix `Slot`) rather than nesting unnecessary `<div>` or duplicate markup.
4. **Presentational vs Container Separation**:
   - **Presentational Component**: Pure UI, accepts typed props, renders semantic tokens, zero API fetching, 100% testable and reusable.
   - **Container / Custom Hook**: Encapsulates state machines, API queries, cache invalidation, and business logic.
5. **No Blind Tailwind Injection**: Do not litter arbitrary utilities like `className="p-[13px] bg-[#234567] text-white"`. Every class must resolve to design system scales.

### 4. Lay out with a spacing scale
Use a geometric scale (4, 8, 12, 16, 24, 32, 48, 64). Space is how grouping is
communicated. Related things sit closer than unrelated things. Uniform padding
everywhere destroys that signal.

### 5. Apply UX behaviour rules
Loading, empty, error, and success states are part of the design, not an
afterthought. See `references/ux-rules.md`.

### 6. Check accessibility
Not optional, and cheaper to do now than to retrofit. See `references/a11y.md`.

### 7. Build primitives in isolation first
Before building multi-screen flows, render all core component primitives and
their states (buttons, inputs, cards, badges, modals, tables, empty/loading/error)
together on an isolated preview route (`/design` or Storybook) and screenshot it
to verify hierarchy, spacing, and states side by side.

## The pre-delivery checklist

Run this before showing UI to the user. It catches the generic-look failure
modes directly:

- [ ] **Hierarchy** - squint at it. Does the primary action still stand out?
- [ ] **Type scale** - at most 3-4 sizes, and weight carries as much of the
      hierarchy as size does
- [ ] **Spacing** - every value from the scale; no arbitrary 13px
- [ ] **Colour** - from tokens; accent used sparingly enough to mean something
- [ ] **Alignment** - elements share edges; nothing is off by 2px
- [ ] **States** - hover, focus, active, disabled, loading, empty, error all exist
- [ ] **Empty state** - says what to do next, not just "No data"
- [ ] **Contrast** - 4.5:1 body, 3:1 large text and UI boundaries (`contrast.py` exit 0)
- [ ] **Focus visible** - keyboard focus ring on every interactive element
- [ ] **Narrow viewport** - holds at 375px without horizontal scroll
- [ ] **Dark mode** - if supported, tokens redefined, nothing hardcoded
- [ ] **Real content** - a long name, a missing avatar, 0 rows, 500 rows

## Things to avoid

These read as "AI made this" or violate clean-room rules:

- Purple-to-blue gradient as the primary brand device
- Every card with the same shadow and the same emphasis
- Emoji as iconography in a professional interface
- Centred text in long-form content
- Placeholder text used as a label - it disappears on focus, and fails a11y
- Pure black on pure white
- Uniform 16px padding on everything regardless of relationship
- Copying a reference app's proprietary logos, icons, illustrations, licensed font files, verbatim UI copy, or signature brand hex values (use open icon sets like Lucide, Phosphor, Heroicons, or Tabler, and open fonts like Inter, Geist, IBM Plex, Manrope, or Source Serif)
