#!/usr/bin/env bash
# Collect everything needed to write one PR, in a single read-only call.
#
# One call replaces the dozen `git log` / `git diff` / `git merge-base` /
# `git status` round-trips a context otherwise spends before it can write a
# description - and each of those round-trips is a turn that re-reads the whole
# context (context-discipline). Output is one JSON object on stdout.
#
# Resolves: the hosting provider from `origin` (github | gitlab | azure |
# unknown), the base branch (`develop` if it exists on origin, else the remote
# default from origin/HEAD, else main), the merge-base range, ahead/behind
# upstream, issue ids from the branch name, the commits, diffstat, numstat, the
# diff (capped), and the PR template - repo's own first, then the plugin's
# fixed template from skills/pr-description.
#
# Flags the caller must look at before writing anything:
#   onDefaultBranch  - no feature branch; a PR from here proposes everything.
#   largeRange       - more than --large-range commits (default 30); usually a
#                      wrong base, not a big story. Confirm the base.
#   dirty            - uncommitted changes the PR would not contain.
#   diffTruncated    - the description covers a truncated diff; say so.
#
# Usage: pr-gather.sh [--repo <path>] [--base-branch <b>] [--max-diff-bytes <n>] [--large-range <n>]

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="."; BASE=""; MAX_DIFF=60000; LARGE=30
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --base-branch) BASE="$2"; shift 2 ;;
    --max-diff-bytes) MAX_DIFF="$2"; shift 2 ;;
    --large-range) LARGE="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

command -v node >/dev/null 2>&1 || { echo "Error: node is required." >&2; exit 1; }
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "Error: $REPO is not a git repository." >&2; exit 1; }
REPO="$(git -C "$REPO" rev-parse --show-toplevel)"

# shellcheck source=./pr-lib.sh
. "$DIR/pr-lib.sh"

BRANCH="$(git -C "$REPO" branch --show-current 2>/dev/null)"; [ -n "$BRANCH" ] || BRANCH="(detached)"
REMOTE="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"
pr_parse_remote "$REMOTE"   # sets PR_PROVIDER PR_ORG PR_PROJECT PR_REPO
DEFAULT="$(pr_default_branch "$REPO")"
[ -n "$BASE" ] || BASE="$(pr_resolve_base "$REPO")"

UPSTREAM="$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
AHEAD_UP=0; BEHIND_UP=0
if [ -n "$UPSTREAM" ]; then
  AHEAD_UP="$(git -C "$REPO" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  BEHIND_UP="$(git -C "$REPO" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
fi

MERGE_BASE=""; RANGE=""; BASE_MISSING=false
if git -C "$REPO" show-ref --verify --quiet "refs/remotes/origin/$BASE"; then
  MERGE_BASE="$(git -C "$REPO" merge-base "origin/$BASE" HEAD 2>/dev/null || true)"
elif git -C "$REPO" show-ref --verify --quiet "refs/heads/$BASE"; then
  MERGE_BASE="$(git -C "$REPO" merge-base "$BASE" HEAD 2>/dev/null || true)"
else
  BASE_MISSING=true
fi
[ -n "$MERGE_BASE" ] && RANGE="$MERGE_BASE..HEAD"

AHEAD=0
[ -n "$RANGE" ] && AHEAD="$(git -C "$REPO" rev-list --count --no-merges "$RANGE" 2>/dev/null || echo 0)"
DIRTY=false; [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] && DIRTY=true
ON_DEFAULT=false; [ -n "$DEFAULT" ] && [ "$BRANCH" = "$DEFAULT" ] && ON_DEFAULT=true

TEMPLATE_PATH=""
for c in \
  "$REPO/.github/PULL_REQUEST_TEMPLATE.md" "$REPO/.github/pull_request_template.md" \
  "$REPO/PULL_REQUEST_TEMPLATE.md" "$REPO/docs/PULL_REQUEST_TEMPLATE.md" \
  "$REPO/.gitlab/merge_request_templates/Default.md" \
  "$REPO/.azuredevops/pull_request_template.md" \
  "$DIR/../skills/pr-description/references/template.md"; do
  [ -f "$c" ] && { TEMPLATE_PATH="$c"; break; }
done

T="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"; trap 'rm -rf "$T"' EXIT
if [ -n "$RANGE" ]; then
  git -C "$REPO" log --no-merges --format='%H%x1f%s%x1f%b%x1e' "$RANGE" > "$T/commits" 2>/dev/null || true
  git -C "$REPO" diff --stat "$RANGE" > "$T/diffstat" 2>/dev/null || true
  git -C "$REPO" diff --numstat "$RANGE" > "$T/numstat" 2>/dev/null || true
  git -C "$REPO" diff "$RANGE" 2>/dev/null | head -c "$MAX_DIFF" > "$T/diff" || true
fi
[ -n "$TEMPLATE_PATH" ] && cp "$TEMPLATE_PATH" "$T/template"

G_DIR="$T" G_REPO="$REPO" G_BRANCH="$BRANCH" G_DEFAULT="$DEFAULT" G_BASE="$BASE" G_BASE_MISSING="$BASE_MISSING" \
G_RANGE="$RANGE" G_MERGE_BASE="$MERGE_BASE" G_UPSTREAM="$UPSTREAM" G_AHEAD_UP="$AHEAD_UP" G_BEHIND_UP="$BEHIND_UP" \
G_AHEAD="$AHEAD" G_DIRTY="$DIRTY" G_ON_DEFAULT="$ON_DEFAULT" G_LARGE="$LARGE" G_MAX_DIFF="$MAX_DIFF" \
G_PROVIDER="$PR_PROVIDER" G_ORG="$PR_ORG" G_PROJECT="$PR_PROJECT" G_REPO_NAME="$PR_REPO" G_TEMPLATE_PATH="$TEMPLATE_PATH" \
node -e '
const fs = require("fs"), path = require("path"), e = process.env;
const read = (n) => { const p = path.join(e.G_DIR, n); return fs.existsSync(p) ? fs.readFileSync(p, "utf8") : ""; };
const commits = read("commits").split("\x1e").map(r => r.replace(/^\n/, "")).filter(Boolean).map(r => {
  const [hash = "", subject = "", body = ""] = r.split("\x1f");
  return { hash: hash.slice(0, 12), subject, body: body.trim() };
});
let additions = 0, deletions = 0;
const numstat = read("numstat").split("\n").map(l => l.split("\t")).filter(c => c.length === 3).map(([a, d, file]) => {
  const add = a === "-" ? 0 : +a, del = d === "-" ? 0 : +d; additions += add; deletions += del;
  return { file, additions: add, deletions: del };
});
const diff = read("diff");
const issueIds = [...new Set((e.G_BRANCH.match(/\d{2,}/g) || []))];
const ahead = +e.G_AHEAD;
const out = {
  repoPath: e.G_REPO, provider: e.G_PROVIDER || "unknown",
  organization: e.G_ORG || null, project: e.G_PROJECT || null, repository: e.G_REPO_NAME || null,
  currentBranch: e.G_BRANCH, defaultBranch: e.G_DEFAULT || null, baseBranch: e.G_BASE,
  baseMissing: e.G_BASE_MISSING === "true", commitRange: e.G_RANGE || null, mergeBase: e.G_MERGE_BASE || null,
  upstream: e.G_UPSTREAM || null, hasUpstream: !!e.G_UPSTREAM, aheadOfUpstream: +e.G_AHEAD_UP, behindUpstream: +e.G_BEHIND_UP,
  aheadCount: ahead, onDefaultBranch: e.G_ON_DEFAULT === "true", dirty: e.G_DIRTY === "true",
  largeRange: ahead > +e.G_LARGE,
  prReady: e.G_ON_DEFAULT !== "true" && ahead > 0 && e.G_BASE_MISSING !== "true",
  issueIds, commits, diffStat: read("diffstat"), numstat,
  totals: { filesModified: numstat.length, additions, deletions, totalLinesChanged: additions + deletions },
  diffTruncated: Buffer.byteLength(diff, "utf8") >= +e.G_MAX_DIFF, diff,
  templatePath: e.G_TEMPLATE_PATH || null, template: read("template"),
};
process.stdout.write(JSON.stringify(out, null, 2) + "\n");
'
