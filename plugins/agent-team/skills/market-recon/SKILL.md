---
name: market-recon
description: Reverse-engineers a reference app into a structured recon map (screens S01..Snn, flows F01..Fnn, component inventory, inferred data model, feature matrix CSV) and mines real, linked public user reviews to rank complaints, missing requests, and positioning angles. Use when cloning, competing with, or improving upon an existing product.
when_to_use: When the user asks to clone, rebuild, compete with, or study an existing product, or wants competitive review analysis to find user pain points and positioning gaps. Do NOT use for internal refactoring or unrelated bug fixes.
---

# Market recon & review mining

A straight copy of an app has no reason to exist, and an unstructured clone
misses half the states. This skill does two things before architecture or code:

1. **Clean-room product decomposition** into a recon map (`docs/recon.md`) and
   a trackable feature matrix (`docs/features.csv`).
2. **Anti-hallucination review mining** (`scripts/reviews.py`) over real,
   linked public reviews (`docs/reviews.csv` -> `docs/feedback.md`) to find
   what users of the reference app hate, what they keep asking for, and the
   positioning angle that fixes it.

## Non-negotiable clean-room & evidence rules

- **Public sources and the user's own account only.** Never log into an account
  that is not the user's, never ask for a password, never bypass a paywall or
  login.
- **Reading, not scraping.** Read pages at human speed or use official public
  feeds/APIs within their terms:
  - Apple Customer Reviews RSS: `https://itunes.apple.com/us/rss/customerreviews/id=<APP_ID>/sortBy=mostRecent/json`
  - Hacker News Algolia API: `https://hn.algolia.com/api/v1/search?query=...`
  - Reddit official API under its terms
- **No source code, no private APIs.** Never inspect or copy a reference app's
  JS bundles, decompile its binary, or sniff its private network endpoints.
  Public API docs are fine.
- **Never fabricate reviews.** No invented quotes, ratings, counts, or URLs.
  `scripts/reviews.py` drops any CSV row without a valid `http(s)://` URL or
  text, deduplicates identical text, and guarantees every quote is a verbatim
  substring of a supplied row.
- **Reviewers are not your testimonials.** Their words are research; never put
  them on your landing page.

## Part 1: Clean-room product recon (`docs/recon.md` & `docs/features.csv`)

### 1. Scope the slice
Agree on three things with the user:
1. **Which app and platform** (web, iOS, Android, desktop).
2. **Which slice** — default to the core loop (the one flow users pay for), not
   every enterprise add-on.
3. **Who it is for** — the user's own team, a vertical niche, or a commercial
   competitor.

### 2. Build the sources table
Record every public source with its URL: help center / docs, pricing page,
changelog, App Store / Play listing, walkthrough videos, marketing site, public
API docs.

### 3. Screen inventory (`S01`, `S02`, ...)
Assign stable IDs (`S01`, `S02`...) that `pm`, `ux-designer`, `planner`, and
`qa-verifier` will cite:

`ID | screen | route / how to reach | purpose | key components | states seen`

Record all states seen: empty, loading, populated, error, permission denied,
mobile.

### 4. User flows (`F01`, `F02`, ...)
Map each core user goal across screen IDs and **count the clicks on the happy
path** — that click count is the target to beat:

```
F01 Guest books a meeting
    S07 booking page -> S08 pick a time -> S09 details form -> S10 confirmed
    happy path clicks: 4
    edge: no slots this week, time zone differs, slot taken while filling the form
```

### 5. Component inventory & inferred data model
- List repeated UI parts (variants, states, screens used on).
- List inferred entities, fields, relationships, evidence (`S09`, help docs),
  and confidence (`high | medium | guess`).

### 6. Feature matrix (`docs/features.csv`)
Start from `references/features.csv`:

```csv
feature,area,priority,original,clone,notes
```

- `priority`: `must | should | could`
- `original`: `yes | no` (`no` for differentiators you add from review mining)
- `clone`: starts at `no` (or `skip` for non-replicable moats), updated to
  `partial` / `yes` during implementation, and scored by `scripts/parity.py`.
- **Be honest about non-replicable moats (`skip`)**: licensed content
  catalogues, two-sided network liquidity, proprietary datasets, hardware, or
  regulated banking/health licences must be marked `skip` with the reason in
  `notes`.

## Part 2: Review mining & positioning (`docs/reviews.csv` -> `docs/feedback.md`)

### 1. Collect real reviews into `docs/reviews.csv`
Columns: `source,url,date,rating,text` (sources: `app-store`, `google-play`,
`g2`, `capterra`, `trustpilot`, `reddit`, `hacker-news`, public feature boards).
Include 1-3 star complaints and 3-4 star "Love it, but..." reviews.

### 2. Rank themes deterministically
Run `reviews.py` (which uses `references/themes.json` by default):

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/market-recon/scripts/reviews.py" docs/reviews.csv --out docs/feedback.md
```

How `reviews.py` scores:
- 1-star = `1.0`, 5-star = `0.2`, unrated = `0.6`.
- Reviews older than `--months` (default 18) count half (`0.5x`).
- Themes with `< 3` reviews or `< 2` sources are flagged `(thin)` so three
  angry comments on one thread are never presented as a market trend.
- Low-rated reviews matching no theme are surfaced under `## Read these by hand`.

### 3. Synthesize the fix plan and positioning angle
From `docs/feedback.md`, include in `docs/brief.md`:
1. **What they hate** (ranked complaints with review count, source count, and
   verbatim linked quotes).
2. **What is missing** (feature requests in users' own words).
3. **What is unsolved** (underserved segments or workflows).
4. **Top fixes** added to `docs/features.csv` with `original=no`.
5. **Positioning angle**:
   ```
   For <who> who <hate this about the original>,
   <our product> <does this instead>.
   Evidence: <theme>, <n> reviews across <m> sources.
   ```
