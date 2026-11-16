# Colour & Physical Light Materiality

## Build the palette from roles, not from favourites

Define these roles first, then pick values. Naming by role is what allows dark
mode, circadian bio-environments, and archetype switching without touching components.

| Role | Purpose |
|---|---|
| `bg` | Page background (Sunlit Alabaster `#FAF8F5`, Anodized Stone `#F2EFE9`, or Carbon `#0B0D10`) |
| `surface` | Primary focal anchor background, raised from `bg` |
| `surface-hover` | Interactive surface state |
| `border` | Structural hairline separation (`1px solid`) |
| `text` | Primary content ink (`4.5:1 <= contrast <= 19.5:1` anti-halation window) |
| `text-muted` | Secondary content, captions, tracked mono labels |
| `accent` | Primary action - the one thing you want clicked |
| `accent-hover`, `accent-fg` | Its interactive state and its foreground |
| `joy-accent` | Eudaimonic milestone celebration / warmth accent (`#D97706` / `#F59E0B`) |
| `specular-rim` | Top `1px` inner highlight simulating overhead physical light |
| `shadow-ambient` | Dual-layer contact + diffuse ambient shadow |
| `success`, `warning`, `danger` | State communication only (use calm amber `#B45309` for recoverable pauses) |

## Archetype Palette Profiles

| Archetype | `bg` | `surface` | `text` | `text-muted` | `accent` | `border` |
|---|---|---|---|---|---|---|
| `swiss-editorial` | `#FAF8F5` | `#FFFFFF` | `#141413` | `#5C5954` | `#C83E2B` | `#DFDCD4` |
| `monolithic-precision` | `#0B0D10` | `#13161C` | `#F3F4F6` | `#8E95A2` | `#14B8A6` | `#222630` |
| `rams-industrial` | `#F2EFE9` | `#FAF8F4` | `#1E1E1C` | `#5A5751` | `#EA580C` | `#D5D1C7` |
| `shibui-organic` | `#FAF7F2` | `#FFFFFF` | `#1C1917` | `#57534E` | `#0D9488` | `#E7E5E4` |
| `kinetic-atelier` | `#F7F6F2` | `#FFFFFF` | `#121214` | `#52525B` | `#2563EB` | `#E4E4E7` |

## Rules

**Never pure black or pure white (`<= 19.5:1`).** `#000000` on `#FFFFFF` (`21:1`) causes retinal halation and astigmatism blur. Use warm alabaster (`#FAF8F5`) and espresso/charcoal ink (`#141413`–`#1C1917`).

**One primary accent.** Two competing accents mean neither means anything. Reserve a secondary warm token (`--joy-accent`) strictly for prosocial celebration (`data-eudaimonia="share-joy"`).

**Accent is scarce.** If most of the screen is accent-coloured, nothing is emphasised. Roughly one primary action per view.

**State colours are for state.** Using danger red decoratively trains users to ignore real errors.

**Neutrals and *Ma* do the work.** A masterwork UI is 90% neutral surface, structural whitespace (*Ma*), and crisp typography, with small, decisive accents (like Dieter Rams' Braun International Orange switch).

## Physical Light, Top Specular Rim & Dark Mode

Dark mode and elevated surfaces are not color inversions:

- **Top Specular Rim (`--specular-rim`)**: Real objects are lit from above. On dark surfaces (`monolithic-precision` or `[data-env="night"]`), flat borders disappear; add a `1px` top inner specular highlight (`inset 0 1px 0 0 rgba(255, 255, 255, 0.08)`) paired with a subtle outer hairline. On light surfaces, use `inset 0 1px 0 0 rgba(255, 255, 255, 0.75)`.
- **Raise `surface` above `bg` with perceptual OKLCH lightness**, not heavy drop shadows.
- **Desaturate accents slightly in dark mode** so saturated colour does not glare against dark backgrounds.

## Contrast targets (WCAG 2.2 + Photobiology Window)

| Pair | Target Window |
|---|---|
| `text` on `bg` or `surface` | `4.5:1 <= ratio <= 19.5:1` (anti-halation ceiling) |
| `text-muted` on `bg` | `>= 4.5:1` - muted still has to be readable |
| Large display figures (`>= 24px`) | `>= 3.0:1` |
| `border`, hairline dividers, focus ring | `>= 3.0:1` (`>= 1.5:1` decorative hairlines) |
| `accent-fg` on `accent` | `>= 4.5:1` |

Always verify with `contrast.py` and `bio_design_gate.py`. "Looks fine" is not a measurement.
