# Brand Naming, Trademark Screening & Clean-Room Identity

Nothing launches under a reference app's identity. Use this workflow to name or
rebrand a product, verify trademark and domain availability honestly, and
prepare `docs/brand.json` for `scripts/sweep.py` and `listing.py`.

## Step 1: Generate 20 Candidates -> Filter to 5

Read the positioning angle from `docs/brief.md` or `docs/feedback.md`. Generate
20 name candidates across five styles:
- **Descriptive** (e.g., Booklink)
- **Compound** (e.g., Slotwise)
- **Invented** (e.g., Calvo)
- **Metaphor** (e.g., Harbor)
- **Verb** (e.g., Book)

Filter down to the top 5 using these rules:
- **Not confusingly similar to the reference app** in sound, appearance, or
  meaning, nor to any other product in the same category (the likelihood-of-confusion
  standard used by trademark offices). No puns on a competitor's name, no
  rhyming `-ly` / `-ify` twin.
- Short, spellable after hearing it once, no unintended meaning in major
  languages.
- Reinforces or fits the positioning angle.

## Step 2: Run Screening Checks (Observed, Never Assumed)

For each of the 5 finalists, build a screening table. Mark each cell with the
observed result and date run, or **`[to run]`** if unreachable. **Never write
"available" for a check you did not actually run.**

| Check | Where to check |
|---|---|
| US trademark | `tmsearch.uspto.gov` (Nice Classes 9 for software, 42 for SaaS) |
| EU trademark | `euipo.europa.eu` eSearch or TMview |
| Canada | `ised-isde.canada.ca` Canadian Trademarks Database |
| Global | WIPO Global Brand Database |
| Domain | `whois <name>.com` or registrar lookup |
| App Store & Google Play | Search exact name in both stores |
| Social & dev handles | X, Instagram, TikTok, GitHub |
| Web collision | Search `"<name>" + <category>` |

*Note: Screening checks filter out obvious collisions; they are not formal legal
clearance.*

## Step 3: Distinct Palette & Contrast Verification

Choose a primary brand hue from a different colour family than the reference
app's (if theirs is blue, do not pick a nearby blue). Update `docs/tokens.json`
and run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/design-intelligence/scripts/contrast.py" docs/tokens.json
```

Require zero AA failures (`exit 0`). Record the reference app's brand hex
colours in `docs/brand.json` under `"colors"` so `scripts/sweep.py` catches any
leftover hex values in CSS or components.

## Step 4: Logo Brief & Deliverable Specs

Write a concise logo brief:
- **Core idea** in one sentence tied to the name and angle
- **Mark type**: wordmark, symbol + wordmark, or monogram
- **Scale test**: must read clearly at `16x16` (favicon) and `1024x1024` (app icon)
- **Deliverables**: vector SVG, `1024x1024` iOS app icon (no alpha/transparency),
  favicon set (`16x16`, `32x32`, `apple-touch-icon.png`), OpenGraph social card
  (`1200x630`)
- **Trade-dress rule**: must not share shape, colour pair, or letterform motif
  with any competitor's mark.

## Step 5: Brand Voice & Top-10 UI Copy Rewrite

- Define **3 voice attributes** with "is / is not" bounds (e.g., *Direct, not
  blunt*).
- Write **5 do / don't phrasing pairs**.
- Rewrite the **10 most-seen UI strings** in the product (sign-up headline,
  primary CTA, empty state, loading state, confirmation screen, error banner,
  onboarding step, email subject, settings header, upgrade prompt) so zero
  phrasing echoes the reference app.

## Step 6: Write `docs/brand.json` and Run `sweep.py`

Write `docs/brand.json`:

```json
{
  "avoid": ["Reference App Name", "Reference Company Inc"],
  "domains": ["referenceapp.com"],
  "colors": ["#006bff"]
}
```

Then run the codebase sweep:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/sweep.py" . --config docs/brand.json
```

Fix every hit in code, filenames, and identifiers until `sweep.py` exits `0`.
