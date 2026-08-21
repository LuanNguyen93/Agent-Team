#!/usr/bin/env bash
# Tests for subagent-guard.sh
#
#   subagent-guard.sh   PreToolUse on Bash|Read|Edit|Write|Grep|Glob|Task|Agent
#                       - runs ONLY when agent_id is present (a subagent's own
#                       call). Once that subagent's own context crosses
#                       AGENT_TEAM_SUBAGENT_LIMIT (default 100000), emits a
#                       ONE-TIME non-blocking nudge telling it to finish the
#                       current cycle and hand back. Never blocks.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/../subagent-guard.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - skipping subagent guard tests"
  exit 0
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"
trap 'rm -rf "$TMP"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

PROJ="$TMP/proj"
mkdir -p "$PROJ/.git"

SESSION_ID="sess-abc"
PARENT="$TMP/$SESSION_ID.jsonl"
SUBDIR="$TMP/$SESSION_ID/subagents"
mkdir -p "$SUBDIR"

rec() {  # cacheRead -> file
  printf '{"message":{"usage":{"input_tokens":0,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s}}}\n' "$1"
}

# Parent stays small throughout - proves the guard reads the SUBAGENT's own
# context (via context-size.js's agent_id resolution), not the parent's.
rec 1000 > "$PARENT"

payload() {  # agent_id tool_name cache_read
  local aid="$1" tool="$2" cr="$3"
  rec "$cr" > "$SUBDIR/agent-$aid.jsonl"
  printf '{"transcript_path":"%s","session_id":"%s","agent_id":"%s","tool_name":"%s","tool_input":{}}' \
    "$(native "$PARENT")" "$SESSION_ID" "$aid" "$tool"
}

run() { CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1; }

assert_nudge_json() {  # label output
  local label="$1" out="$2"
  printf '%s' "$out" | node -e '
let s="";
process.stdin.on("data", (d) => s += d).on("end", () => {
  try {
    const p = JSON.parse(s);
    const ctx = (p.hookSpecificOutput || {}).additionalContext || "";
    if (p.hookSpecificOutput && p.hookSpecificOutput.hookEventName === "PreToolUse"
        && ctx.indexOf("Finish the red-green cycle") !== -1) {
      process.exit(0);
    }
    process.exit(1);
  } catch (e) { process.exit(1); }
});' && ok "$label" || nope "$label" "not valid nudge JSON: $out"
}

# --------------------------------------------------------------------------
# no agent_id -> silent, this hook is only for subagents
# --------------------------------------------------------------------------
OUT="$(printf '{"transcript_path":"%s","tool_name":"Bash","tool_input":{}}' "$(native "$PARENT")" | run)"; RC=$?
t="no agent_id -> exit 0, no output"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# agent_id present, under limit -> silent
# --------------------------------------------------------------------------
OUT="$(payload agent1 Bash 5000 | run)"; RC=$?
t="under limit -> exit 0, no output"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# agent_id present, over limit -> envelope + stamp
# --------------------------------------------------------------------------
OUT="$(payload agent2 Bash 150000 | run)"; RC=$?
t="over limit -> exit 0 with a non-blocking nudge"
{ [ $RC -eq 0 ] && [ -n "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"
assert_nudge_json "nudge is valid JSON with hookSpecificOutput.additionalContext" "$OUT"

GITDIR="$(git -C "$PROJ" rev-parse --absolute-git-dir 2>/dev/null || printf '%s/.git' "$PROJ")"
t="a stamp file is written for agent2"
[ -f "$GITDIR/agent-team/subagent-guard-stamp-agent2" ] && ok "$t" || nope "$t" "no stamp file"

# --------------------------------------------------------------------------
# second call for the same agent_id -> silent (one-shot)
# --------------------------------------------------------------------------
OUT="$(payload agent2 Bash 160000 | run)"; RC=$?
t="second call for the same agent_id -> exit 0, no output"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# a different agent_id gets its own independent nudge
# --------------------------------------------------------------------------
OUT="$(payload agent3 Read 150000 | run)"; RC=$?
t="a different agent_id fires its own nudge"
{ [ $RC -eq 0 ] && [ -n "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"
assert_nudge_json "second agent's nudge is valid JSON" "$OUT"

# --------------------------------------------------------------------------
# AGENT_TEAM_SKIP_CONTEXT_GUARD=1 -> exit 0
# --------------------------------------------------------------------------
OUT="$(payload agent4 Bash 150000 | AGENT_TEAM_SKIP_CONTEXT_GUARD=1 CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="AGENT_TEAM_SKIP_CONTEXT_GUARD=1 -> exit 0, no output"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# a non-matching tool -> exit 0
# --------------------------------------------------------------------------
OUT="$(payload agent5 WebFetch 150000 | run)"; RC=$?
t="a non-matching tool (WebFetch) -> exit 0, no output"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# fail-open cases
# --------------------------------------------------------------------------
OUT="$(printf 'not json' | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="garbage stdin exits 0"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

NOGIT="$TMP/nogit"
mkdir -p "$NOGIT"
OUT="$(payload agent6 Bash 150000 | CLAUDE_PROJECT_DIR="$NOGIT" bash "$GUARD" 2>&1)"; RC=$?
t="a project dir with no .git fails open: exit 0"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
