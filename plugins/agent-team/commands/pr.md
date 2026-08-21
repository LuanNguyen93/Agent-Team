---
description: Open a pull request from the current branch - one gather call, a description in the team's fixed format, one create call on GitHub, GitLab or Azure DevOps.
argument-hint: [issue id or "no issue"] [--draft] [--dry-run]
disable-model-invocation: true
---

Open a PR for the current branch. Arguments: **$ARGUMENTS**

1. Load the `pr-create` skill and follow it; it loads `pr-description` for
   the body.
2. Gather with one call - `"${CLAUDE_PLUGIN_ROOT}/scripts/pr-gather.sh"` -
   not with hand-run `git` commands. Do not delegate; this is read-only and
   single-pass.
3. Stop and ask when the gather output flags `onDefaultBranch`, `largeRange`,
   `dirty`, or `baseMissing`. Otherwise confirm branch → base → provider once.
4. Write the title and fill the template. "Tests added" carries this
   session's real gate output or an explicit statement that no gates ran -
   do not run gates as part of this command, and never estimate numbers.
5. Show the drafted title and body. If `--dry-run` was given, or the user
   wants to paste it themselves, stop there with the `--dry-run` command
   printed. Otherwise push if needed (ask first) and create with
   `"${CLAUDE_PLUGIN_ROOT}/scripts/pr-create.sh"`, passing `--draft` when
   asked, and report the URL.
