---
description: Draft a PR description in the team's fixed format from the current diff, commits, and the last gate run.
argument-hint: [work item link or "no work item"]
disable-model-invocation: true
---

Draft a PR description for the current branch. Work item: **$ARGUMENTS**

1. Load the `pr-description` skill.
2. Gather evidence directly (do not delegate — this is read-only, single-pass):
   `git diff <base>...HEAD --stat`, `git log <base>..HEAD --oneline`, and the
   most recent gate output from this session.
3. If no gates were run this session, state that explicitly in "Tests added"
   instead of fabricating or estimating numbers — do not run gates
   automatically as part of this command.
4. Fill every section of the template. Use explicit "n/a — <reason>" rather
   than omitting a section with nothing to say.
5. Do not open the PR — print the drafted body for the user to review and
   paste, unless the user explicitly asks to open it via `gh pr create`.
