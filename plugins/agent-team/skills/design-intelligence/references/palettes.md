# Colour

## Build the palette from roles, not from favourites

Define these roles first, then pick values. Naming by role is what allows dark
mode and rebranding without touching components.

| Role | Purpose |
|---|---|
| `bg` | Page background |
| `surface` | Card / panel background, raised from bg |
| `surface-hover` | Interactive surface state |
| `border` | Hairline separation |
| `text` | Primary content |
| `text-muted` | Secondary content, captions |
| `accent` | Primary action - the one thing you want clicked |
| `accent-hover`, `accent-fg` | Its interactive state and its foreground |
| `success`, `warning`, `danger` | State communication only |

## Rules

**Never pure black or pure white.** Black on white vibrates and feels cheap.
Use near-neutrals instead.

**One accent.** Two accents means neither means anything. If you need a second,
you probably need a state colour.

**Accent is scarce.** If most of the screen is accent-coloured, nothing is
emphasised. Roughly one primary action per view.

**State colours are for state.** Using danger red decoratively trains users to
ignore real errors.

**Neutrals do the work.** A good UI is mostly neutral with small amounts of
colour. If it looks bland in neutrals only, the problem is hierarchy, not colour.

## Dark mode

Define the full light palette on the root, then redefine **only the tokens**
under the dark condition. Never give a colour its only definition inside a dark
block - a viewer on the default system setting gets an undefined value.

Dark mode is not inversion:

- Raise `surface` above `bg` with lightness, not shadow. Shadows barely read on dark.
- Desaturate accents slightly. Saturated colour glares on dark backgrounds.
- Reduce pure-white text to around 90% to cut halation.

## Contrast targets

| Pair | Minimum |
|---|---|
| `text` on `bg` or `surface` | 4.5:1 |
| `text-muted` on `bg` | 4.5:1 - muted still has to be readable |
| Large text (18.66px bold, or 24px) | 3:1 |
| `border`, icons, focus ring | 3:1 |
| `accent-fg` on `accent` | 4.5:1 |

Check computed values. "Looks fine" is not a measurement, and muted text is
where this fails most often.
