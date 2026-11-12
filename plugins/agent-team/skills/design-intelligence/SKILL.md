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

### 3c. Neuro-Ergonomic & Biological Design Laws (Bio-Adaptive UI)
Human eyes, hands, and working memory are biological organs, not mechanical sensors. Interfaces that ignore human biology feel harsh, exhausting, and "AI-assembled":

1. **Photobiology & Anti-Halation (Circadian Light Adaptation)**:
   - Never pair pure `#000000` with pure `#ffffff` (`21:1` contrast causes **retinal halation / astigmatism blur** in ~50% of humans when pupils dilate).
   - Keep text/surface contrast within the biological comfort window (`4.5:1 <= ratio <= 19.5:1`). Use warm/slate elevated surfaces (`#f8fafc` / `#f9fafb` in light mode; `#111418` / `#181c22` in circadian dark mode) and perceptual **OKLCH** lightness steps.
   - Support **3 Bio-Environment Modes** (`daylight` high ambient, `studio` balanced, `night` circadian low-glare).
2. **Foveal Vision & Cognitive Load (Saccadic & Working-Memory Limits)**:
   - The human fovea resolves sharp detail within a 2-degree visual angle. Constrain reading blocks to `45ch–65ch` (`max-width: 65ch`) to prevent exhausting horizontal saccades.
   - **Cowan's Working Memory Law ($4 \pm 1$)**: Never pack more than 3–4 primary KPI cards or top-level choices in a single visual cluster.
3. **Motor Biomechanics & Concentric Geometry**:
   - **Fitts's Law**: Interactive controls (`button`, `input`, `[role="button"]`) must be at least `40px–44px` tall with `>= 8px` dead-zone separation between adjacent actions.
   - **Concentric Curvature ($R_{inner} = R_{outer} - P$)**: When nesting a rounded element inside a card with outer radius $R_{outer}$ and padding $P$, scale the inner radius proportionally so corners look organically concentric, never pinched.
4. **Natural Physics Motion (Spring Kinematics vs. Linear Slop)**:
   - Nothing in biology moves at a constant `linear` velocity. Forbid `transition: ... linear` on spatial/layout movement; use critically damped spring or natural deceleration curves (`cubic-bezier(0.22, 1, 0.36, 1)`), micro-interaction feedback `< 120ms`, and always include `@media (prefers-reduced-motion: reduce)` for vestibular safety.

### 3d. Positive Design Philosophy & Eudaimonic Energy (Joy, Warmth & Shared Positivity)
Cold, hospital-grey interfaces (`#0f172a`), dystopian blue-black dark modes, and punitive red error states (`FATAL ERROR`, `NO DATA FOUND`) radiate negative energy and trigger sympathetic nervous system stress (tunnel vision and fatigue). Grounded in **Pieter Desmet & Anna Pohlmeyer's *Positive Design Framework* (Eudaimonia)**, **Don Norman's *Emotional Design***, **Ingrid Fetell Lee's *Aesthetics of Joy***, and **Barbara Fredrickson's *Broaden-and-Build Theory***, every interface MUST transmit warmth, optimism, and shared joy across three pillars:

1. **Pillar 1 — Visceral Pleasure & Sunlit Biophilic Warmth**:
   - Replace sterile hospital whites and cold steel greys with **Sunlit Alabaster / Warm Ivory (`#FAF8F5` / `#F5F3EF`)**, **Warm Espresso Ink (`#1C1917`)**, and **Golden Hearth Night (`#1C1917` / `#26221E`)** instead of cold dystopian blue-black.
   - Pair calm biophilic accents (Teal/Emerald `#0D9488` for vitality and Sunrise Amber `#D97706` for warmth and celebration).
2. **Pillar 2 — Personal Significance & Compassionate Microcopy (Zero Punitive Energy)**:
   - Highlight meaningful human progress and mastery rather than cold surveillance metrics.
   - **Never use hostile, blaming, or scarcity-laden copy** (`"FATAL ERROR"`, `"NO DATA FOUND"`, `"INVALID INPUT"`, `"OPERATION FAILED"`).
   - Frame **Empty States** as an inspiring **"Fresh Canvas"** (*"A fresh canvas for great work — begin your first milestone"*) and **Error States** as a reassuring **"Safe Pause"** in warm amber (`#B45309`) (*"A gentle pause — your progress is safely preserved"*).
3. **Pillar 3 — Virtue & Prosocial Sharing of Positivity (`data-eudaimonia="share-joy"`)**:
   - Happiness expands when shared. Every primary product surface and prototype MUST include a built-in **Shared Positivity / Gratitude / Milestone Celebration affordance** (`data-eudaimonia="share-joy"`) allowing humans to celebrate wins, send kudos/gratitude, or share positive progress with teammates or their community.

### 4. Lay out with a spacing scale
Use a geometric scale (4, 8, 12, 16, 24, 32, 48, 64). Space is how grouping is
communicated. Related things sit closer than unrelated things. Uniform padding
everywhere destroys that signal.

### 4b. Mandatory Interactive Prototype Gate (`docs/prototype.html`)
Humans cannot judge visual rhythm, biological comfort, or state transitions from a Markdown text file (`docs/ui-spec.md`). Before writing production framework code (`React`, `Next.js`, `Vue`), generate and customize a self-contained, clickable HTML prototype at `docs/prototype.html` and run the deterministic Bio-Design & Anti-Slop gate:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/design-intelligence/scripts/bio_design_gate.py" . --init-prototype docs/prototype.html --tokens docs/tokens.json --title "Screen Prototype"
python3 "${CLAUDE_PLUGIN_ROOT}/skills/design-intelligence/scripts/bio_design_gate.py" . --require-prototype
```

The interactive prototype MUST expose a sticky **Human Review HUD** allowing the user to toggle live between:
- **All 4 UX States**: `1. Populated`, `2. Loading (Shaped Skeleton)`, `3. Empty (Actionable)`, `4. Error (Recovery)`
- **All 3 Bio-Environments**: `Daylight`, `Studio`, `Circadian Night`
- **Bio-Guides Overlay**: `65ch` foveal reading boundary and `44px` Fitts's Law hit-target outlines.

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
