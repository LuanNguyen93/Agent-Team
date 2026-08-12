# Typography

Type carries more of the hierarchy than colour does, and it is where generic UI
gives itself away fastest.

## Scale

Pick a scale and use only its steps. A 1.25 ratio suits dense product UI; 1.333
suits editorial.

| Step | Use |
|---|---|
| `xs` 12px | Captions, table meta, badges |
| `sm` 14px | Secondary body, dense tables, form help |
| `base` 16px | Body. Never smaller for long-form reading. |
| `lg` 18-20px | Lead paragraph, card titles |
| `xl` 24px | Section headings |
| `2xl` 32px | Page title |
| `3xl` 48px+ | Marketing hero only |

**Use at most 3-4 steps on one screen.** More reads as noise. Weight and colour
carry the rest of the hierarchy.

## Weight

Two or three weights, no more. Regular 400, medium 500, semibold 600. Bold 700
for rare emphasis.

Prefer stepping **weight** over stepping size for adjacent levels. A 16px
semibold label above 16px regular body creates hierarchy without changing rhythm.

## Pairing

The safest system uses one family across the whole UI, with weight and size
doing the work. Pair two only when they have a job each.

| Pairing | Works because |
|---|---|
| One grotesque (Inter, Geist) throughout | Neutral, invisible, never wrong |
| Serif headings + grotesque body | Editorial contrast, clear role split |
| Grotesque UI + mono for data | Numbers and code align and scan |
| Humanist (Source Sans) throughout | Warmer than a grotesque, still neutral |

Never pair two fonts of the same category. The reader cannot tell why they
differ, so it reads as a mistake.

## Measure and rhythm

- **Line length**: 45-75 characters for prose. Beyond that the eye loses the line.
- **Line height**: 1.5-1.6 body, 1.2-1.3 headings. Tight headings, loose body.
- **Letter spacing**: leave it alone, except slightly negative on large headings
  and slightly positive on all-caps.
- **Alignment**: left-align. Centred text is for short display lines only;
  justified text creates rivers without hyphenation.

## Numbers

Use tabular figures (`font-variant-numeric: tabular-nums`) anywhere numbers
stack: tables, prices, metrics, timers. Proportional figures jitter column
alignment and make data look sloppy.
