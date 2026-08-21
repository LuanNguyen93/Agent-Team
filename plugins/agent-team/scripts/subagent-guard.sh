#!/usr/bin/env bash
# PreToolUse hook: tell a SUBAGENT, once, when its own context has grown large
# enough that it should stop and hand back rather than keep working.
#
# This is the inverse of every other guard in this repo: guard-heavy-load.sh,
# delegation-nudge.sh and tier-guard.sh all skip a call when agent_id is
# present, because they police the MAIN context's discipline and a subagent's
# own tool calls must never count against it (docs/HARNESS-NOTES.md section
# 11). This hook runs ONLY when agent_id is present - it exists entirely to
# police the subagent's own context, which none of the others measure.
#
# Measured on this repository (docs/HARNESS-NOTES.md, the transcript_path
# finding): the transcript_path a PreToolUse payload carries inside a
# subagent invocation is the PARENT session's own transcript, not the
# subagent's. context-size.js now resolves the subagent's own transcript from
# session_id + agent_id when both are present in the payload, which is what
# makes this hook possible - a naive read of transcript_path here would
# report the parent's size, not the subagent's own.
#
# Fires ONCE per subagent (stamped by agent_id, not by transcript, since a
# subagent's context never resets mid-dispatch the way a session's does) with
# a non-blocking PreToolUse JSON envelope (docs/HARNESS-NOTES.md section 14)
# telling it to finish the current red-green cycle, write its handoff report,
# and stop rather than start new scope.
#
# Fails open on: no agent_id, non-matching tool, AGENT_TEAM_SKIP_CONTEXT_GUARD=1,
# no node, unparseable payload, no .git, or an unwritable state dir.

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
    console.log([p.tool_name || "", p.agent_id || ""].join("\n"));
  } catch (e) { /* fail open */ }
});' 2>/dev/null)"

TOOL="$(printf '%s' "$FIELDS" | sed -n '1p')"
AGENT_ID="$(printf '%s' "$FIELDS" | sed -n '2p')"

# This hook exists ONLY for subagents - a call with no agent_id is the main
# context's own, and every other guard already covers that.
[ -n "$AGENT_ID" ] || exit 0

case "$TOOL" in
  Bash|Read|Edit|Write|Grep|Glob|Task|Agent) ;;
  *) exit 0 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
SIZE="$(printf '%s' "$PAYLOAD" | node "$DIR/context-size.js" --project-dir "$ROOT" 2>/dev/null)"
case "$SIZE" in ''|*[!0-9]*) exit 0 ;; esac

LIMIT="${AGENT_TEAM_SUBAGENT_LIMIT:-100000}"
[ "$SIZE" -lt "$LIMIT" ] && exit 0

# State lives in .git, not the working tree - same convention as every other
# guard in this file's family. Stamped by agent_id: a subagent's context only
# grows across its own dispatch, so a one-shot per agent_id is correct - it
# never needs to re-arm the way a per-transcript nudge does.
state_dir() {
  local gitdir
  gitdir="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir="$ROOT/.git"
  [ -d "$gitdir" ] || return 1
  mkdir -p "$gitdir/agent-team" 2>/dev/null || return 1
  printf '%s/agent-team' "$gitdir"
}

DIR_STATE="$(state_dir)" || exit 0
STAMP="$DIR_STATE/subagent-guard-stamp-$AGENT_ID"

[ -f "$STAMP" ] && exit 0
{ printf '' > "$STAMP"; } 2>/dev/null || exit 0

SIZE_K=$(( SIZE / 1000 ))
LIMIT_K=$(( LIMIT / 1000 ))

MESSAGE="This subagent's own context is now ~${SIZE_K}k tokens, past the ${LIMIT_K}k
working limit for a single dispatch.

Finish the red-green cycle you are currently in, write your handoff report per
the handoff-contract skill, and return - do not start new scope in this same
dispatch. Whoever spawned you can continue the rest as a fresh dispatch, which
starts with none of this context's cost.

This fires once for this subagent."

ENVELOPE="$(printf '%s' "$MESSAGE" | node -e '
let s="";
process.stdin.on("data", (d) => s += d).on("end", () => {
  const out = { hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: s } };
  process.stdout.write(JSON.stringify(out));
});' 2>/dev/null)"

[ -n "$ENVELOPE" ] && printf '%s' "$ENVELOPE"

exit 0
