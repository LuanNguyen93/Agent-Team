# PR description template

```
## What
<imperative summary of the change>
<bulleted list of concrete file-level changes: what was added/removed/modified and where>
<any deliberate non-changes worth calling out>

## Why
<work item link, or explicit "No work item linked — <reason>">
<narrative explanation of the root cause / motivation, with concrete technical detail>
<reasoning for the chosen approach over alternatives>
<cross-repo note: "Single-repo change — no sibling PRs." or link to sibling PRs>

## AC covered
<numbered/linked acceptance criteria from the story, or explicit "n/a — reason">

## Tests added
<what was added, or explicit "None added" + why that is still correct>
<actual gate output — real numbers — plus explanation of any pre-existing failures and why they're unrelated>
<a reviewer note calling out anything anomalous about the push, with specific reason and evidence>

## Screenshots
<n/a or actual screenshots>

## Self-review checklist
[ ] I read my own diff before opening this PR
[ ] Commit messages follow Conventional Commits
[ ] No secrets, credentials, or connection strings in the diff
[ ] Docs / comments updated where the change makes them wrong
[ ] Sibling PRs in other repos are linked above (or this story is single-repo)
```
Check a box `[x]` only after you actually verified it. Leave `[ ]` unchecked if you didn't check it.

## Worked example — "Why" with mechanism-level detail

Weak (do not write this):

> Fixed a bug where the endpoint didn't check permissions.

Better:

> `GET /api/reports/:id` resolved `:id` and returned the report body without
> checking that the requesting user belonged to the report's org. Any
> authenticated user could enumerate sequential report IDs and read other
> orgs' data — a horizontal privilege escalation, not just a missing null
> check. The blast radius is every report ever created, since the route has
> existed since the initial API (v1). Fix adds an org-scope check identical to
> the one already used in `GET /api/invoices/:id`, rather than inventing a new
> authorization pattern, so the codebase keeps one way to do object-level
> authorization instead of two.

## Worked example — reporting a bypassed or partial gate

> **Tests added**: Added `reports.authz.spec.ts` covering same-org access
> (200), cross-org access (403), and missing auth (401).
>
> Gate output (`npm test` — this session):
> ```
> Tests: 214 passed, 2 failed, 216 total
> FAIL src/legacy/csv-export.spec.ts
>   ✕ exports handle embedded commas (pre-existing, unrelated to this change)
>   ✕ exports handle BOM markers (pre-existing, unrelated to this change)
> ```
> **Reviewer note**: the 2 failures are in `csv-export.spec.ts`, a module this
> diff does not touch (confirmed via `git diff --stat`). They fail identically
> on `main` at the branch point (`git stash && npm test` reproduces the same 2
> failures before this change is applied). Not fixed here to keep this PR
> scoped to the authz bug; tracked separately.
