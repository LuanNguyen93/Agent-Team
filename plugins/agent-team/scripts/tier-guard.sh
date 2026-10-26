#!/usr/bin/env bash
# PreToolUse hook: mechanically enforce "announced a tier -> spawn agents".
#
# workflow-router's "Routing means spawning, not imitating" section asks for
# this by hand; a skill only asks, per docs/HARNESS-NOTES.md section 1, only a
# hook enforces. This is the enforcement: if the main context announced a
# FEATURE or PROJECT tier and then kept editing without ever spawning a
# subagent, block the 5th such edit ONCE and point back at the router.
#
# tier-scan.js does the transcript reading and reports the plain facts (tier,
# edits since, whether a Task ran since); this script is the policy on top of
# those facts.
#
# Blocks (exit 2) only when ALL of:
#   - the last announced tier is FEATURE or PROJECT (QUICK and NONE pass)
#   - 5 or more undelegated edits happened since the announcement
#   - no Task call happened since the announcement
#
# One-shot per transcript+tier, same stamp-file convention as
# guard-heavy-load.sh: if the agent decides to proceed anyway, the next call
# goes through.
#
# Fails open (exit 0, no output) on: agent_id present (a subagent's own edit),
# a non-matching tool, AGENT_TEAM_SKIP_CONTEXT_GUARD=1, no node, unparseable
# payload, no .git, or an unwritable state dir. A missing transcript_path
# falls back to "unknown" rather than disabling the feature, same as
# delegation-nudge.sh.

set -uo pipefail

[ "${AGENT_TEAM_SKIP_CONTEXT_GUARD:-}" = "1" ] && exit 0

PAYLOAD="$(cat)"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null 2>&1 || exit 0

FIELDS="$(printf '%s' "$PAYLOAD" | node -e '
let s="";
process.stdin.on("data", (d) => s += d).on("end", () => {
  try {
    const p = JSON.parse(s);
    console.log([p.tool_name || "", p.transcript_path || "unknown", p.agent_id || ""].join("\n"));
  } catch (e) { /* fail open */ }
});' 2>/dev/null)"

TOOL="$(printf '%s' "$FIELDS" | sed -n '1p')"
TRANSCRIPT="$(printf '%s' "$FIELDS" | sed -n '2p')"
AGENT_ID="$(printf '%s' "$FIELDS" | sed -n '3p')"

case "$TOOL" in
  Edit|Write|NotebookEdit|Bash|Read|Grep|Glob) ;;
  *) exit 0 ;;
esac

# agent_id is present only inside a subagent invocation (docs/HARNESS-NOTES.md
# section 11): a subagent's own edit must never be blocked by the main
# context's tier discipline.
[ -z "$AGENT_ID" ] || exit 0

[ -n "$TRANSCRIPT" ] || TRANSCRIPT="unknown"

SCAN_OUT="$(node "$DIR/tier-scan.js" "$TRANSCRIPT" 2>/dev/null)"
TIER="$(printf '%s' "$SCAN_OUT" | sed -n '1p' | cut -d' ' -f1)"
EDITS="$(printf '%s' "$SCAN_OUT" | sed -n '1p' | cut -d' ' -f2)"
READONLY="$(printf '%s' "$SCAN_OUT" | sed -n '1p' | cut -d' ' -f3)"
HAS_TASK="$(printf '%s' "$SCAN_OUT" | sed -n '1p' | cut -d' ' -f4)"

case "$TIER" in
  FEATURE|PROJECT) ;;
  *) exit 0 ;;
esac
[ "$HAS_TASK" = "1" ] && exit 0
case "$EDITS" in ''|*[!0-9]*) EDITS=0 ;; esac
case "$READONLY" in ''|*[!0-9]*) READONLY=0 ;; esac
OVER=0
[ "$EDITS" -ge 5 ] && OVER=1
[ "$READONLY" -ge 15 ] && OVER=1
[ "$OVER" -eq 1 ] || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# State lives in .git, not the working tree - same convention as
# guard-heavy-load.sh and delegation-nudge.sh.
state_dir() {
  local gitdir
  gitdir="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir="$ROOT/.git"
  [ -d "$gitdir" ] || return 1
  mkdir -p "$gitdir/agent-team" 2>/dev/null || return 1
  printf '%s/agent-team' "$gitdir"
}

DIR_STATE="$(state_dir)" || exit 0
KEY="$(basename "$TRANSCRIPT")-$TIER"
STAMP="$DIR_STATE/tier-guard-stamp-$KEY"

if [ -f "$STAMP" ]; then
  exit 0    # already blocked once for this transcript+tier; the agent decided
fi
{ printf '' > "$STAMP"; } 2>/dev/null || exit 0

if [ "$TIER" = "FEATURE" ]; then
  AGENTS="analyst/planner -> implementer(s) -> reviewer"
else
  AGENTS="analyst -> pm -> architect -> per-story chain"
fi

{
  echo "This session announced tier \`$TIER\` and has made $EDITS edits and"
  echo "$READONLY read-only calls since"
  echo "without spawning a single subagent. $TIER names: $AGENTS."
  echo
  echo "Re-read the workflow-router skill's \"Routing means spawning, not"
  echo "imitating\" section and delegate the rest of this work instead of"
  echo "continuing to do it inline."
  echo
  echo "This blocks once per announced tier per session - the next edit goes"
  echo "through if you decide to proceed anyway."
} >&2

exit 2
