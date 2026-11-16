# Typography & High-Dynamic-Range (HDR) Hierarchy

Type carries more of the hierarchy than colour does, and it is where generic AI-generated UI gives itself away fastest.

## High-Dynamic-Range (HDR) Scale Contrast

Generic UIs cluster every font size into a narrow middle band (`14px`, `16px`, `18px`, `22px`), creating visual mush. Master typographers (Bringhurst, Müller-Brockmann) use **extreme contrast between the smallest and largest elements** while eliminating mid-sized clutter:

| Step | Size & Tracking | Structural Role |
|---|---|---|
| `micro` `11px` | `uppercase`, `letter-spacing: 0.09em`, `font-weight: 600` | Tracked index labels, column headers, metadata coordinates |
| `sm` `13px–14px` | `line-height: 1.5`, `tabular-nums` | Secondary ledger values, timestamps, captions |
| `base` `15px–16px` | `line-height: 1.6`, `max-width: 65ch` | Primary reading prose. Never smaller for long-form reading. |
| `lg` `18px–20px` | `font-weight: 600`, `letter-spacing: -0.015em` | Section anchor titles |
| `display` `44px–72px` | `font-weight: 600`, `letter-spacing: -0.035em`, `line-height: 1.02` | **Single Dominant Focal Anchor** figure or editorial headline |

**Use at most 3–4 steps on one screen.** Pair a razor-sharp `11px` tracked uppercase mono label directly above a `56px` display figure (`5x` scale contrast) — skip intermediate `20px`/`24px` sub-headers inside the focal anchor.

## Tri-Voice Pairing System

While a single grotesque works for simple utilities, signature art-directed products use a **Tri-Voice Pairing System** where each font family owns a strict structural role:

| Voice Token | Category & Exemplars | Assigned Role |
|---|---|---|
| `--font-display` | Editorial Serif (`Instrument Serif`, `Newsreader`, `Playfair Display`) or Tight Display Sans (`Geist`, `Inter Display`) | Dominant focal figures (`44px–72px`), primary page title |
| `--font-sans` | Neutral Grotesque / Humanist (`Inter`, `Geist`, `Plus Jakarta Sans`, `IBM Plex Sans`) | Body copy (`45ch–65ch`), interactive buttons, form controls |
| `--font-mono` | Technical Tabular Mono (`JetBrains Mono`, `Geist Mono`, `IBM Plex Mono`) | `11px` tracked index labels, KPI deltas, IDs, code, timestamps |

Never pair two fonts from the same category for the same role. Every voice switch must signal a semantic shift (Narrative Display vs Reading Prose vs Precision Telemetry).

## Weight

Two or three weights, no more: Regular `400`, Medium `500`, Semibold `600`.
Prefer stepping **weight and tracking** over stepping size by `2px` for adjacent hierarchy levels.

## Measure, Rhythm & Optical Gravity Balance

- **Foveal Line Length (`45ch–65ch`)**: Constrain reading blocks to `max-width: 65ch`. Beyond `70ch` the human eye loses the horizontal line on return saccades.
- **Line Height**: `1.55–1.65` for body prose; `1.15–1.25` for section headings; `1.0–1.05` for `44px+` display figures.
- **Optical Gravity Padding (`padding: 20px 28px 26px`)**: Geometric vertical centering (`padding: 24px`) makes typography look like it is sinking because the human eye locates the optical center ~5% above the mathematical center. Always set bottom padding ~15–20% larger than top padding on focal containers and hairline ledger rows.
- **Alignment**: Left-align prose and ledger labels; right-align tabular numerical values in ledgers so decimal points align vertically.

## Numbers

Enforce `font-variant-numeric: tabular-nums` anywhere numbers appear: hero figures, hairline ledgers, prices, counters, and timers. Proportional figures jitter horizontally and destroy Swiss grid precision.
