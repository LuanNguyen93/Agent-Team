---
name: browser-verify
description: Drive the running app in a real browser to confirm a change actually works, instead of inferring it from passing unit tests. Use before declaring UI or full-stack work done.
when_to_use: Verifying a web feature end to end, reproducing a UI bug, or checking a flow across pages. Do NOT use for pure backend or library changes with no UI surface.
---

# Browser verification

A green test suite says the code does what the tests describe. It does not say
the feature works. Wiring, routing, env config, hydration, and CSS all sit
outside most unit tests — and that is where features actually break.

**Verification means: the app ran, you drove it, you saw the result.**

## Procedure

### 1. Start the app for real
Find the dev command from `package.json` / CI config. Start it, and wait for the
ready line. If it fails to boot, **that is the finding** — stop and report it;
do not go looking for a way to test around a broken app.

### 2. Drive the actual user path
Not the happy path only. Walk the flow a user walks:
- Navigate to the entry point
- Perform the interaction (click, type, submit)
- Assert on what a user would see, not on internal state

### 3. Check the things tests routinely miss (15-item edge-case matrix)
- **Console errors** — read them. A red console on a "working" page is a defect.
- **Network** — failed requests, 4xx/5xx, requests fired twice, waterfalls.
- **1. Empty input** — submit with nothing, or spaces only; inline message, no crash.
- **2. Very long input** — 10,000 characters in a field; rejected cleanly or truncated without breaking layout.
- **3. Emoji, accents, non-ASCII** — `José`, `👩‍💻`, `日本語`, quotes and `<script>`; saved and shown back unchanged, never executed.
- **4. Two tabs open at once** — change something in tab A, act in tab B; refreshes or shows a clear conflict.
- **5. Double-click / rapid double-submit** — click the main action twice fast; button disables, one record created, not two.
- **6. Browser Back and Forward mid-flow** — step 2 -> Back -> Forward; state stays sensible, no duplicate submit.
- **7. Page refresh (F5) mid-flow** — reload on every screen; stays signed in, URL reflects where you are.
- **8. Slow network** — throttle to Slow 3G; loading state appears, nothing jumps when it finishes.
- **9. Offline** — cut network and click; clear message, recovers when back.
- **10. Expired session** — delete auth cookie and click; redirected to sign in, then back to where you were.
- **11. Second user's data** — signed in as user B, open user A's URL or ID; 403 or 404, zero data from user A.
- **12. Time zones and daylight saving** — change browser time zone; times shown in the user's zone, stored in UTC.
- **13. Mobile viewport** — 375px / 390x844; no horizontal scroll, tap targets at least 44x44px.
- **14. Keyboard only** — Tab, Shift+Tab, Enter, Escape through the whole flow; visible focus ring, modals trap focus and close on Escape.
- **15. Screen reader labels & axe scan** — every input has a label, every icon button has an `aria-label`, `@axe-core/playwright` finds zero critical/serious violations.

### 4. Capture evidence
A screenshot of the working result, and the console/network output. "It works"
without evidence is an assertion, not a verification.

## Automated E2E baseline (Playwright + Axe)

Start from `references/e2e.example.spec.ts` when writing or extending Playwright E2E specs:
- Use accessible locators (`getByRole`, `getByLabel`, `getByText`) so tests survive restyling.
- Fail automatically on any `console.error`, uncaught `pageerror`, or HTTP `>= 500` response in `test.beforeEach`.
- Run `new AxeBuilder({ page }).analyze()` on each key screen and assert `violations` is empty.

## Deterministic visual & layout diffing (`imgdiff.py`)

When reference screenshots (`docs/screens/` or `replica/screens/`) or baseline screenshots exist, run the zero-dependency PNG comparison script:

```bash
# Structural layout comparison (ignores colour differences from rebranding, compares edge density per grid cell)
python3 "${CLAUDE_PLUGIN_ROOT}/skills/browser-verify/scripts/imgdiff.py" reference.png current.png --out diff.png --json

# Exact pixel regression comparison (for before/after on the same app)
python3 "${CLAUDE_PLUGIN_ROOT}/skills/browser-verify/scripts/imgdiff.py" baseline.png current.png --mode pixel --fail-under 95
```

Pass `--json` outputs to `scripts/parity.py --visual` when computing combined feature + layout parity.

## Honest reporting

State exactly what you exercised and what you did not:

> Verified: login with valid credentials redirects to /dashboard and the session
> survives reload. Console clean.
> Not verified: password reset (needs a mail server), SSO path (no test account).

Never write "verified" for a path you did not drive. Unverified scope is normal
and useful information; a false claim of verification is a trap for whoever
ships next.

## Dialogs

Do not trigger `alert`, `confirm`, or `prompt` — a modal dialog blocks the
automation channel and the session stops responding. If the flow requires one,
warn the user before proceeding.

## When the browser is unavailable

If no browser automation is available, say so and fall back explicitly:
run the app, `curl` the endpoints, read the server logs — and label the result
as partial verification, not full.
