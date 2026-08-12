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

### 3. Check the things tests routinely miss
- **Console errors** — read them. A red console on a "working" page is a defect.
- **Network** — failed requests, 4xx/5xx, requests fired twice, waterfalls.
- **Empty and error states** — not just the populated one.
- **Reload** — does the state survive? Does the URL reflect where you are?
- **Narrow viewport** — does the layout hold at ~375px?

### 4. Capture evidence
A screenshot of the working result, and the console/network output. "It works"
without evidence is an assertion, not a verification.

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
