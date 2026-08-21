---
name: pr-create
description: Open a pull request from the current branch with one gather call and one create call, on GitHub (gh), GitLab (glab) or Azure DevOps (az) as detected from origin. Resolves the base branch, refuses unsafe states (default branch, unpushed or stale branch, suspicious commit range), and writes the description with pr-description.
when_to_use: The user says create a PR, open a PR, raise the MR, ship this, or my branch is ready. Do NOT use to commit, push, rebase, or tidy the branch first - it turns work that already exists into a PR.
---

# Creating a pull request

Two scripts, two calls. Everything else is reading their output and writing
prose. Do not pad the sequence with `git log` / `git diff` / `git status` -
the gather call already answered those, and every extra call is a turn that
re-reads this whole context.

Both scripts take `--repo <path>`, so the current directory never has to
change. Invoke them by absolute path under the plugin root:
`${CLAUDE_PLUGIN_ROOT}/scripts/`.

## 1. Gather - one read-only call

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/pr-gather.sh" --repo .
```

One JSON object: `provider`, `currentBranch`, `baseBranch`, `defaultBranch`,
`hasUpstream`, `aheadOfUpstream`, `behindUpstream`, `aheadCount`,
`issueIds`, `commits`, `diffStat`, `numstat`, `totals`, `diff` (capped,
`diffTruncated` says when), `template`, and the four flags below.

Show the user a one-line summary - branch → base, commits, files, provider -
and then **stop on any of these before writing a word**:

| flag | meaning | do |
|---|---|---|
| `onDefaultBranch` | there is no feature branch | tell the user; do not work around it |
| `largeRange` (> 30 commits) | almost always a wrong base, not a big story | confirm the base, or pass `--base-branch` |
| `dirty` | uncommitted work the PR would not contain | say so; the user decides |
| `baseMissing` | `origin/<base>` does not exist | `--base-branch` explicitly |

`prReady: false` with none of those set means there is nothing to open. Say
so and stop; that is the normal state after a merge, not a failure.

Opening a PR is outward-facing and hard to take back. Confirm branch, base and
provider with the user once, here, before anything is created.

## 2. Title

`{type}({scope}): {description}` - Conventional Commits. Type from the
commits when they are conventional, inferred from the diff when they are not.
Scope is the area *inside* the repo, never the repo name. Under 72
characters, lowercase after the colon, no trailing period. Put the issue id
in the title when there is one (`feat(auth): add refresh flow (#42)`) so the
PR and the issue are visibly one unit of work.

## 3. Description

Fill the `template` the gather call returned - the repo's own when it has
one, otherwise the fixed template from `pr-description`. Load
`pr-description` for what goes in each section and the rules that do not
bend: every claim backed by the diff or this session's gate output, explicit
`n/a - reason` instead of a missing section, no checkbox ticked that was not
checked. Two rules that come from the gather output specifically:

- `diffTruncated: true` → say the description covers a truncated diff rather
  than guessing at the rest.
- File counts match `numstat`. Do not describe a test you cannot point at.

Keep it under ~2,000 characters; when trimming, cut prose summary first, then
change bullets, then file rows - never a heading. Show the user the title and
body, then write the body to a scratch `.md` file for the create call.

## 4. Push, if needed

The create script refuses to run from a branch that is ahead of, behind, or
without an upstream - a PR built from a stale remote reviews code nobody can
see. When `hasUpstream` is false or `aheadOfUpstream > 0`, push first
(`git push -u origin <branch>`), with the user's say-so.

## 5. Create

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/pr-create.sh" --repo . \
  --title "feat(auth): add refresh flow (#42)" \
  --description-file /path/to/body.md \
  --issues 42            # GitHub/GitLab: "Closes #42"; Azure: --work-items
  [--draft] [--reviewers a,b] [--target-branch x] [--dry-run]
```

Provider comes from `origin`: `github.com` → `gh pr create`, `gitlab` →
`glab mr create`, `dev.azure.com` / `visualstudio.com` → `az repos pr create`
with explicit `--organization/--project/--repository`, never `az`'s
auto-detection (a stale `az devops configure` default lands the PR in the
wrong project and reports success). Use `--dry-run` whenever anything about
the target looks uncertain; it prints the exact command and exits.

Report the PR URL. One repo, one PR; if the user has several repos to ship,
do them one at a time and report as you go so a failure halfway is obvious.

## When it fails

Name what is missing; do not retry blind.

- CLI not authenticated → `gh auth login` / `glab auth login` / `az login`
  or `AZURE_DEVOPS_EXT_PAT`.
- "behind upstream" → `git pull --rebase`, re-run. "ahead" → push, re-run.
- "cannot tell the hosting provider" → the remote is self-hosted or unusual;
  tell the user and offer the dry-run command to adapt by hand.
- "is this repo's default branch" → the work is not on a feature branch.
  Check out the right one; never pass `--target-branch` to get around it.

## What this skill does not do

Commit, amend, rebase, force-push, or edit code to make the PR look tidier.
Run the gates - that is `/ship` and `quality-gates`, before this. Track
sprint or story status in any tracker; that belongs to whatever owns the
tracker.
