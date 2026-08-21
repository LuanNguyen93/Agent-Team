#!/usr/bin/env bash
# Tests for context-size.js - the helper both context hooks are built on.
#
# It answers one question: how large is the context right now. That number is
# not in any environment variable; it has to be read back out of the transcript
# the harness is writing, from the usage record of the most recent request.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIZER="$SCRIPT_DIR/../context-size.js"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - skipping context-size tests"
  exit 0
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"
trap 'rm -rf "$TMP"' EXIT

# A path that node itself can resolve.
#
# On Git Bash, MSYS rewrites POSIX paths in argv when it calls a native binary,
# so `node x.js --transcript /tmp/...` works while the same string arriving
# inside a JSON payload on stdin does not - nothing rewrites stdin. The harness
# sends a real OS path, so the test has to as well or it tests the rewrite
# rather than the code.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

rec() {  # cacheRead cacheWrite input
  printf '{"message":{"role":"assistant","model":"claude-opus-5","usage":{"input_tokens":%s,"output_tokens":50,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}\n' "$3" "$2" "$1"
}

T="$TMP/session.jsonl"
{ rec 10000 5000 2
  rec 90000 8000 3      # <- newest usage record: 90000 + 8000 + 3 = 98003
} > "$T"

# --- reads the size off the last usage record -------------------------------
OUT="$(node "$SIZER" --transcript "$T" 2>&1)"; RC=$?
t="prints the context size from the most recent usage record"
[ "$OUT" = "98003" ] && ok "$t" || nope "$t" "expected 98003 got '$OUT' rc=$RC"

# --- trailing non-usage lines must not blank the answer ---------------------
printf '{"type":"mode","mode":"normal"}\n' >> "$T"
printf 'garbage not json\n' >> "$T"
OUT="$(node "$SIZER" --transcript "$T" 2>&1)"
t="ignores trailing records that carry no usage"
[ "$OUT" = "98003" ] && ok "$t" || nope "$t" "expected 98003 got '$OUT'"

# --- payload on stdin, the way a hook receives it ---------------------------
OUT="$(printf '{"transcript_path":"%s","hook_event_name":"UserPromptSubmit"}' "$(native "$T")" | node "$SIZER" 2>&1)"
t="takes transcript_path from a hook payload on stdin"
[ "$OUT" = "98003" ] && ok "$t" || nope "$t" "expected 98003 got '$OUT'"

# --- falls back when the payload has no transcript_path ---------------------
# The harness is not guaranteed to pass one, and a hook that only works on the
# documented path is a hook that silently stops working.
OUT="$(printf '{"hook_event_name":"UserPromptSubmit"}' | node "$SIZER" --project-dir "$(native "$TMP")" 2>&1)"
t="falls back to the newest transcript under --project-dir"
[ "$OUT" = "98003" ] && ok "$t" || nope "$t" "expected 98003 got '$OUT'"

# --- nothing to read is 0 and exit 0, never a hook crash --------------------
OUT="$(printf '{}' | node "$SIZER" --project-dir "$TMP/nope" 2>&1)"; RC=$?
t="unknown context reports 0 and exits 0, so the hook never blocks a turn"
{ [ "$OUT" = "0" ] && [ $RC -eq 0 ]; } && ok "$t" || nope "$t" "got '$OUT' rc=$RC"

# --- an empty transcript is 0, not a crash ----------------------------------
: > "$TMP/empty.jsonl"
OUT="$(node "$SIZER" --transcript "$TMP/empty.jsonl" 2>&1)"; RC=$?
t="empty transcript reports 0 and exits 0"
{ [ "$OUT" = "0" ] && [ $RC -eq 0 ]; } && ok "$t" || nope "$t" "got '$OUT' rc=$RC"

# --------------------------------------------------------------------------
# agent_id in the payload resolves to the SUBAGENT's own transcript, not the
# parent's. Measured on this repository (docs/HARNESS-NOTES.md): the
# transcript_path a PreToolUse payload carries inside a subagent invocation is
# the PARENT session's own transcript, not the subagent's - the subagent's own
# records live at <project>/<session_id>/subagents/agent-<agent_id>.jsonl.
# --------------------------------------------------------------------------
PROJ="$TMP/proj"
SESSION_ID="sess-abc"
PARENT="$PROJ/$SESSION_ID.jsonl"
mkdir -p "$PROJ/$SESSION_ID/subagents"
{ rec 1000 0 0; } > "$PARENT"                                     # parent context = 1000
{ rec 42000 0 0; } > "$PROJ/$SESSION_ID/subagents/agent-agentXYZ.jsonl"  # subagent context = 42000

OUT="$(printf '{"transcript_path":"%s","session_id":"%s","agent_id":"agentXYZ"}' \
  "$(native "$PARENT")" "$SESSION_ID" | node "$SIZER" 2>&1)"
t="agent_id in the payload reports the subagent's own context, not the parent's"
[ "$OUT" = "42000" ] && ok "$t" || nope "$t" "expected 42000 got '$OUT'"

OUT="$(printf '{"transcript_path":"%s","session_id":"%s"}' \
  "$(native "$PARENT")" "$SESSION_ID" | node "$SIZER" 2>&1)"
t="no agent_id still reports the parent's own context"
[ "$OUT" = "1000" ] && ok "$t" || nope "$t" "expected 1000 got '$OUT'"

OUT="$(printf '{"transcript_path":"%s","session_id":"%s","agent_id":"no-such-agent"}' \
  "$(native "$PARENT")" "$SESSION_ID" | node "$SIZER" 2>&1)"
t="an agent_id with no matching subagent file falls back to the parent transcript"
[ "$OUT" = "1000" ] && ok "$t" || nope "$t" "expected 1000 got '$OUT'"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
