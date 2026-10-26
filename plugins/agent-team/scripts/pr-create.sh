#!/usr/bin/env bash
# Open one pull request from the current branch, on whichever host `origin`
# points at: GitHub (gh), GitLab (glab), or Azure DevOps (az, with explicit
# --organization/--project/--repository so a wrong `az devops configure`
# default can never land the PR in the wrong project).
#
# It does NOT push, commit, or rebase. It refuses when the branch has no
# upstream, is ahead of or behind it, or is the repo's default branch - a PR
# built from a stale remote reviews code nobody can see, and a PR from main
# proposes everything that ever landed there.
#
# Usage: pr-create.sh --title <t> --description-file <path>
#          [--repo <path>] [--target-branch <b>] [--reviewers a,b]
#          [--issues 1,2] [--draft] [--dry-run]
#
# --issues: GitHub/GitLab get "Closes #n" appended to the body (the host links
# it); Azure gets --work-items (plain "AB#n" text does not link in a native
# ADO PR). --dry-run prints the exact command and exits 0.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./pr-lib.sh
. "$DIR/pr-lib.sh"

REPO="."; TARGET=""; TITLE=""; DESC=""; REVIEWERS=""; ISSUES=""; DRAFT=false; DRY=false
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --target-branch) TARGET="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --description-file) DESC="$2"; shift 2 ;;
    --reviewers) REVIEWERS="$2"; shift 2 ;;
    --issues|--work-items) ISSUES="$2"; shift 2 ;;
    --draft) DRAFT=true; shift ;;
    --dry-run) DRY=true; shift ;;
    *) sed -n '12,18p' "$0" >&2; exit 1 ;;
  esac
done
[ -n "$TITLE" ] && [ -n "$DESC" ] || { sed -n '12,18p' "$0" >&2; exit 1; }
[ -f "$DESC" ] || { echo "Error: description file not found: $DESC" >&2; exit 1; }

git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "Error: $REPO is not a git repository." >&2; exit 1; }
REPO="$(git -C "$REPO" rev-parse --show-toplevel)"

BRANCH="$(git -C "$REPO" branch --show-current)"
[ -n "$BRANCH" ] || { echo "Error: detached HEAD; check out a branch first." >&2; exit 1; }
[ -n "$TARGET" ] || TARGET="$(pr_resolve_base "$REPO")"
[ "$BRANCH" != "$TARGET" ] || { echo "Error: source and target are both '$BRANCH'." >&2; exit 1; }

DEFAULT="$(pr_default_branch "$REPO")"
if [ -n "$DEFAULT" ] && [ "$BRANCH" = "$DEFAULT" ]; then
  echo "Error: '$BRANCH' is this repo's default branch - a PR from it into '$TARGET'" >&2
  echo "would propose everything that ever landed on it. Check out the feature branch." >&2
  exit 1
fi

if ! git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  echo "Error: '$BRANCH' has no upstream. Push first:  git -C $REPO push -u origin $BRANCH" >&2
  exit 1
fi
UP="$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}')"
AHEAD="$(git -C "$REPO" rev-list --count '@{u}..HEAD')"; BEHIND="$(git -C "$REPO" rev-list --count 'HEAD..@{u}')"
[ "$BEHIND" -eq 0 ] || { echo "Error: '$BRANCH' is $BEHIND commit(s) behind '$UP'. git pull --rebase, then re-run." >&2; exit 1; }
[ "$AHEAD" -eq 0 ]  || { echo "Error: '$BRANCH' is $AHEAD commit(s) ahead of '$UP'. Push first, then re-run." >&2; exit 1; }

REMOTE="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"
[ -n "$REMOTE" ] || { echo "Error: no 'origin' remote." >&2; exit 1; }
if ! pr_parse_remote "$REMOTE"; then
  echo "Error: cannot tell the hosting provider from origin: $REMOTE" >&2
  echo "Supported: github.com, gitlab, dev.azure.com / visualstudio.com." >&2
  exit 1
fi

BODY="$DESC"
if [ -n "$ISSUES" ] && [ "$PR_PROVIDER" != "azure" ]; then
  BODY="$(mktemp 2>/dev/null || mktemp -t agentteam)"; trap 'rm -f "$BODY"' EXIT
  cat "$DESC" > "$BODY"; printf '\n' >> "$BODY"
  for i in $(printf '%s' "$ISSUES" | tr ',' ' '); do printf 'Closes #%s\n' "${i#\#}" >> "$BODY"; done
fi

CMD=()
case "$PR_PROVIDER" in
  github)
    [ "$DRY" = true ] || command -v gh >/dev/null 2>&1 || { echo "Error: gh (GitHub CLI) not on PATH." >&2; exit 1; }
    CMD=(gh pr create --base "$TARGET" --head "$BRANCH" --title "$TITLE" --body-file "$BODY")
    [ -n "$REVIEWERS" ] && CMD+=(--reviewer "$REVIEWERS")
    [ "$DRAFT" = true ] && CMD+=(--draft) ;;
  gitlab)
    [ "$DRY" = true ] || command -v glab >/dev/null 2>&1 || { echo "Error: glab (GitLab CLI) not on PATH." >&2; exit 1; }
    CMD=(glab mr create --target-branch "$TARGET" --source-branch "$BRANCH" --title "$TITLE" --description "$(cat "$BODY")" --yes)
    [ -n "$REVIEWERS" ] && CMD+=(--reviewer "$REVIEWERS")
    [ "$DRAFT" = true ] && CMD+=(--draft) ;;
  azure)
    [ "$DRY" = true ] || command -v az >/dev/null 2>&1 || { echo "Error: az (Azure CLI) not on PATH." >&2; exit 1; }
    CMD=(az repos pr create --organization "$PR_ORG" --project "$PR_PROJECT" --repository "$PR_REPO"
         --source-branch "$BRANCH" --target-branch "$TARGET" --title "$TITLE"
         --description "$(cat "$BODY")" --detect false --output json)
    if [ -n "$REVIEWERS" ]; then CMD+=(--reviewers); for r in $(printf '%s' "$REVIEWERS" | tr ',' ' '); do CMD+=("$r"); done; fi
    if [ -n "$ISSUES" ]; then CMD+=(--work-items); for i in $(printf '%s' "$ISSUES" | tr ',' ' '); do CMD+=("${i#\#}"); done; fi
    [ "$DRAFT" = true ] && CMD+=(--draft true) ;;
esac

echo "Provider: $PR_PROVIDER  ${PR_ORG:+($PR_ORG${PR_PROJECT:+ / $PR_PROJECT})}"
echo "Branch:   $BRANCH -> $TARGET  (in sync with $UP)"
if [ "$DRY" = true ]; then
  printf 'DRY RUN - would run:\n '
  for a in "${CMD[@]}"; do
    if [ "$a" = "$(cat "$BODY")" ]; then printf ' <contents of %s>' "$DESC"; else printf ' %q' "$a"; fi
  done
  printf '\n'; exit 0
fi

echo "Creating PR..."
OUT="$(cd "$REPO" && "${CMD[@]}")" || { printf '%s\n' "$OUT"; exit 1; }
if [ "$PR_PROVIDER" = "azure" ] && command -v node >/dev/null 2>&1; then
  ID="$(printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).pullRequestId||"")}catch(e){}})')"
  [ -n "$ID" ] && { echo "PR !$ID created: $PR_ORG/$(printf '%s' "$PR_PROJECT" | sed 's/ /%20/g')/_git/$PR_REPO/pullrequest/$ID"; exit 0; }
fi
printf '%s\n' "$OUT"
