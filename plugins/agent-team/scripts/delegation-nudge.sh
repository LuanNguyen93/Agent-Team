#!/usr/bin/env bash
# PreToolUse hook: notice when the main context keeps editing without ever
# delegating, and say so once.
#
# Measured on this repository: the two most expensive sessions cost $272 and
# $82, and both spawned zero subagents - every edit happened in the main
# context, which is billed again on every remaining turn. The workflow-router
# skill names a tier of agents for exactly this kind of work; a session that
# never spawns one is not using the router at all.
#
# Mechanism: a per-session counter of consecutive Edit/Write/NotebookEdit
# calls since the last Task (subagent spawn). At the threshold (5) this fires
# a ONE-TIME non-blocking nudge - stdout on a PreToolUse hook reaches Claude
# as additional context without denying the call, the same convention
# context-budget.sh uses. A Task call resets the counter and the fired flag,
# so a genuine QUICK stretch of edits after delegating can trip the nudge
# again.
#
# This hook never blocks. Missing/unparseable stdin or an unwritable state dir
# fail open with exit 0 and no output. A missing transcript_path falls back to
# an "unknown" key instead of disabling the feature - same convention as
# guard-heavy-load.sh - since docs/HARNESS-NOTES.md notes the field can be
# absent on some harness builds. A call carrying agent_id (a subagent's own
# edit) is skipped outright so it cannot burn the main context's nudge.
#
# Opt out for a session with AGENT_TEAM_SKIP_CONTEXT_GUARD=1.

set -uo pipefail

[ "${AGENT_TEAM_SKIP_CONTEXT_GUARD:-}" = "1" ] && exit 0

PAYLOAD="$(cat)"

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
  # "Agent" is the subagent-spawn tool_name in this harness (measured); "Task"
  # is kept too for older builds. Both reset the counter below.
  Edit|Write|NotebookEdit|Task|Agent) ;;
  *) exit 0 ;;
esac

# agent_id is present only inside a subagent invocation (docs/HARNESS-NOTES.md
# §11): a subagent's own edits must not burn the main context's one-time
# nudge, so skip entirely when this call came from a subagent.
[ -z "$AGENT_ID" ] || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# State lives in .git, not the working tree - same convention as
# guard-heavy-load.sh's stamp file.
state_dir() {
  local gitdir
  gitdir="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir="$ROOT/.git"
  [ -d "$gitdir" ] || return 1
  mkdir -p "$gitdir/agent-team" 2>/dev/null || return 1
  printf '%s/agent-team' "$gitdir"
}

DIR="$(state_dir)" || exit 0
KEY="$(basename "$TRANSCRIPT")"
COUNT_FILE="$DIR/delegation-nudge-count-$KEY"
FIRED_FILE="$DIR/delegation-nudge-fired-$KEY"

if [ "$TOOL" = "Task" ] || [ "$TOOL" = "Agent" ]; then
  rm -f "$COUNT_FILE" "$FIRED_FILE" 2>/dev/null
  exit 0
fi

COUNT=0
[ -f "$COUNT_FILE" ] && COUNT="$(cat "$COUNT_FILE" 2>/dev/null)"
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
COUNT=$((COUNT + 1))
{ printf '%s' "$COUNT" > "$COUNT_FILE"; } 2>/dev/null || true

THRESHOLD=5
[ "$COUNT" -ge "$THRESHOLD" ] || exit 0
[ -f "$FIRED_FILE" ] && exit 0

MESSAGE="This is the ${COUNT}th consecutive edit in this session without spawning a
subagent. The workflow-router skill names a tier of agents for work like this
- planner, implementer, reviewer - and none of them has run.

Measured on this repository: the two most expensive sessions, \$272 and \$82,
delegated nothing. Every edit happened in the main context, which is billed
again on every turn that follows it.

If this stretch of edits is genuinely small, ignore this - it fires once per
delegation gap. If not, consider handing the rest to a subagent."

# PreToolUse: plain stdout with exit 0 is NOT delivered to Claude, and exit 2
# reaches Claude but blocks the tool call (docs/HARNESS-NOTES.md §1/§14). The
# non-blocking channel that injects text into context is this JSON envelope
# on stdout with exit 0. Built with node/JSON.stringify (already a dependency
# of this script) rather than hand-rolled escaping, since the message
# contains newlines and dollar signs.
#
# FIRED_FILE is only written after the emit is confirmed to have produced
# output - if node fails or is killed mid-emit, the flag must stay unset so
# the nudge can still fire on a later call, not be silently burned into the
# void the way the original plain-stdout defect was.
ENVELOPE="$(printf '%s' "$MESSAGE" | node -e '
let s="";
process.stdin.on("data", (d) => s += d).on("end", () => {
  const out = { hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: s } };
  process.stdout.write(JSON.stringify(out));
});' 2>/dev/null)"

if [ -n "$ENVELOPE" ]; then
  printf '%s' "$ENVELOPE"
  { printf '' > "$FIRED_FILE"; } 2>/dev/null || true
fi

exit 0
