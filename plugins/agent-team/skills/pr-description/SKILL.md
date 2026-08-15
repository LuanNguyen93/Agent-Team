---
name: pr-description
description: Fixed PR description template - What, Why, AC covered, Tests added, Screenshots, Self-review checklist - drafted from the real diff, commits, and this session's gate output.
when_to_use: Drafting or writing a PR description for the current branch. Do NOT use for commit messages, or when no diff exists yet.
---

# PR description

A PR description is a claim about the diff, read by someone who was not in
this session. Every section is either backed by something you observed this
session, or explicitly marked absent — never filled in to look complete.

The template is fixed. Read `references/template.md` for the literal text and
two worked examples before drafting.

## Where each section comes from

**What** — `git diff <base>...HEAD --stat`, then read the diff itself.
Bulleted, file-level, concrete: what was added/removed/modified and where.
Call out any deliberate non-change worth flagging (e.g. "config left
untouched — see Why").

**Why** — a work-item link if the user supplied one; otherwise the explicit
line "No work item linked — `<reason>`". A narrative of the root cause or
motivation with concrete technical detail, not "fixed a bug". State why this
approach was chosen over alternatives. Add a cross-repo note: "Single-repo
change — no sibling PRs." or links to the sibling PRs.

**AC covered** — acceptance criteria from the story or plan for this session,
numbered or linked. If none exists, "n/a — `<reason>`" (e.g. "n/a — no story,
this is a direct bug fix").

**Tests added** — what was added, or "None added" plus why that is still
correct (e.g. pure config, no executable behavior). Then the actual gate
output from this session, real numbers, with the command that reproduces it.
If no gates ran this session, say so explicitly — never fabricate or
estimate. Add a reviewer note for anything anomalous: a skipped gate, a
`--no-verify` push, a pre-existing unrelated failure — each with a specific
justification, not a wave-off.

**Screenshots** — "n/a" or actual screenshots.

**Self-review checklist** — verify each line yourself before checking it:
read the diff, check commit messages against Conventional Commits, grep the
diff for secret-shaped strings, check whether docs/comments now read wrong.
Check a box only when you actually did the check that box names.

## Never

- Never write a gate number that was not observed this session.
- Never silently omit a section — use explicit "n/a — `<reason>`" instead.
- Never tick a self-review checklist box that was not actually verified.
