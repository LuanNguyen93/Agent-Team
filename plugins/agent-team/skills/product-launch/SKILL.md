---
name: product-launch
description: Prepares a product or clean-room clone for commercial launch and production cutover - brand naming and trademark screening, landing page and evidence-backed pricing, App Store and Google Play listing linting (listing.py), and the production preflight checklist (preflight.md). Use when naming/rebranding, writing launch or store metadata, or preparing a production deployment.
when_to_use: When the user asks to name or rebrand the product, design pricing and landing page copy, prepare App Store or Google Play listings, or run a production launch / cutover checklist. Do NOT use for ordinary internal code commits.
---

# Product launch, brand & production cutover

Takes a verified product from "working in dev" to a commercial launch under its
own identity, with zero leaked competitor trade dress, linted store metadata,
and a gated production cutover.

## Non-negotiable rules

- **Nothing goes live without the user's explicit go.** Run preflight, show the
  results, and ask before any production deploy or store submission.
- **The user owns accounts, domains, and live credentials.** Never buy a domain,
  enter a card, type a password, or paste a live API key. Write the exact DNS
  records, env var names, and commands; the user performs the account actions.
- **No fake social proof.** Never invent testimonials, user counts, star
  ratings, press logos, or "trusted by" rows. Never use competitor review quotes
  as testimonials on your landing page.
- **Competitor names stay out of store listings, titles, keywords, and ads.**
  Apple App Review (Guideline 4.1 Copycats) and Google Play reject metadata
  containing another app's trademarked name.

## Phase 1: Brand identity, trademark screening & clean-room sweep

See `references/brand-and-trademark.md` for the full 6-step procedure:
1. Generate 20 name candidates across 5 styles and filter to 5 that pass the
   likelihood-of-confusion filter.
2. Run USPTO, EUIPO/TMview, CIPO, WIPO, domain, App Store/Play, and handle
   checks — recording `[observed]` results or `[to run]`, never assuming
   "available".
3. Pick a primary brand hue from a distinct colour family, update
   `docs/tokens.json`, and verify `contrast.py` exits `0`.
4. Write `docs/brand.json` (`avoid`, `domains`, `colors`) and run:
   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/sweep.py" . --config docs/brand.json
   ```
   until it exits `0`.

## Phase 2: Landing page & evidence-backed pricing

1. **Landing page structure** (`docs/launch/landing.md`):
   - **Hero**: positioning angle headline (what it does, for whom), subhead, one
     primary CTA, real product screenshot.
   - **Problem**: top two complaint themes from `docs/feedback.md`, paraphrased
     in plain words (never quoting reviewers).
   - **How it works**: 3 steps from the core flow (`F01`).
   - **Differentiators**: lead with the fixes (`original=no` rows in
     `docs/features.csv`), not table-stakes parity features.
   - **Pricing**: transparent tier table (at most 3 tiers) with one-click
     cancellation promised and implemented.
   - **FAQ & final CTA**.
2. **Pricing analysis** (`docs/launch/pricing.md`):
   - Table of reference app and 2-3 alternatives' public pricing with URL and
     date read.
   - Summary of pricing/billing complaints from `docs/feedback.md`.
   - Tier structure (free tier or trial, flat vs per-seat, monthly + annual) and
     exact Stripe product/price definitions for the user to create.

## Phase 3: App Store & Google Play listing linter (`listing.py`)

Start from `references/listing.example.json`, populate `docs/launch/listing.json`
(including the `"avoid"` list from `docs/brand.json`), and run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/product-launch/scripts/listing.py" docs/launch/listing.json
```

What `listing.py` enforces (exits `1` on any error):
- **App Store limits**: `name` (30), `subtitle` (30), `promotional_text` (170),
  `keywords` (100), `description` (4000), `whats_new` (4000).
- **Google Play limits**: `title` (30), `short_description` (80),
  `full_description` (4000).
- **Unicode grapheme cluster counting**: emoji sequences and combining marks
  count the way a human and the stores count them.
- **Copycat & trademark guard**: any mention of a name in `avoid` (or `--avoid`)
  anywhere in the listing is a hard `error`.
- **Store policy warnings**: ranking/price claims (`#1`, `best`, `free`, `% off`)
  or emoji in short fields, spaces after commas in App Store keywords, duplicate
  keywords, or keywords that repeat words already in `name` / `subtitle`.

## Phase 4: Production preflight & cutover (`references/preflight.md`)

Copy `references/preflight.md` to `docs/deploy.md` and run every preflight gate
before cutover:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-gates.sh"
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/parity.py" docs/features.csv --require-must-haves
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/sweep.py" . --config docs/brand.json
python3 "${CLAUDE_PLUGIN_ROOT}/skills/product-launch/scripts/listing.py" docs/launch/listing.json
```

Then guide the user through the production cutover items in
`references/preflight.md`:
- Separate production database with backups enabled and automated migrations
- Production env vars matching `.env.example`
- Stripe live mode products/prices, production webhook endpoint + signing
  secret, and one real purchase + refund test
- OAuth redirect URIs and authorised origins updated for the production domain
- Custom domain DNS (`A @`, `CNAME www`, canonical redirect, HTTPS) and email
  authentication (`SPF`, `DKIM`, `DMARC`)
- Error tracking, uptime checks, and live smoke test on desktop and mobile
