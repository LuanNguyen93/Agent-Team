#!/usr/bin/env bash
# Tests for delegation-nudge.sh
#
#   delegation-nudge.sh   PreToolUse on Edit|Write|NotebookEdit|Task - counts
#                         consecutive main-context edits since the last
#                         subagent spawn, and at a threshold (5) emits a
#                         ONE-TIME non-blocking nudge that the router's tier
#                         names agents that were never spawned. A Task call
#                         resets the counter and re-arms the nudge.
#
# Measured: the two most expensive sessions ($272 and $82) spawned zero
# subagents.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUDGE="$SCRIPT_DIR/../delegation-nudge.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - skipping delegation nudge tests"
  exit 0
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"
trap 'rm -rf "$TMP"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

PROJ="$TMP/proj"
mkdir -p "$PROJ/.git"

TRANSCRIPT="$TMP/t.jsonl"
: > "$TRANSCRIPT"

edit_payload() {  # tool_name
  printf '{"transcript_path":"%s","tool_name":"%s","tool_input":{"file_path":"x.txt"}}' "$(native "$TRANSCRIPT")" "$1"
}

task_payload() {
  printf '{"transcript_path":"%s","tool_name":"Task","tool_input":{}}' "$(native "$TRANSCRIPT")"
}

edit_payload_for() {  # transcript tool_name
  printf '{"transcript_path":"%s","tool_name":"%s","tool_input":{"file_path":"x.txt"}}' "$(native "$1")" "$2"
}

edit_payload_no_transcript() {  # tool_name
  printf '{"tool_name":"%s","tool_input":{"file_path":"x.txt"}}' "$1"
}

edit_payload_agent() {  # transcript tool_name agent_id
  printf '{"transcript_path":"%s","tool_name":"%s","agent_id":"%s","tool_input":{"file_path":"x.txt"}}' "$(native "$1")" "$2" "$3"
}

run() { CLAUDE_PROJECT_DIR="$PROJ" bash "$NUDGE" 2>&1; }

# --------------------------------------------------------------------------
# counter increments, no nudge below threshold
# --------------------------------------------------------------------------
for i in 1 2 3 4; do
  OUT="$(edit_payload Edit | run)"; RC=$?
  t="edit $i below threshold exits 0 with no nudge"
  { [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"
done

# 5th edit crosses the threshold
OUT="$(edit_payload Edit | run)"; RC=$?
t="5th consecutive edit fires the nudge, still exits 0"
{ [ $RC -eq 0 ] && [ -n "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

t="nudge references the measured cost"
case "$OUT" in *272*) ok "$t";; *) nope "$t" "no cost figure in: $OUT";; esac

# 6th edit must NOT re-fire
OUT="$(edit_payload Write | run)"; RC=$?
t="nudge fires only once - 6th edit is silent"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# Task resets counter and re-arms the nudge
# --------------------------------------------------------------------------
OUT="$(task_payload | run)"; RC=$?
t="Task call resets counter, exits 0 silently"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

for i in 1 2 3 4; do
  OUT="$(edit_payload Edit | run)"; RC=$?
  t="post-delegation edit $i below threshold is silent"
  { [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"
done

OUT="$(edit_payload Edit | run)"; RC=$?
t="nudge can fire again after delegation resets it"
{ [ $RC -eq 0 ] && [ -n "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# never blocks, fails open
# --------------------------------------------------------------------------
OUT="$(printf 'not json' | CLAUDE_PROJECT_DIR="$PROJ" bash "$NUDGE" 2>&1)"; RC=$?
t="garbage stdin exits 0 with no output"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

OUT="$(printf '{}' | CLAUDE_PROJECT_DIR="$PROJ" bash "$NUDGE" 2>&1)"; RC=$?
t="payload with no session id exits 0"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

NOGIT="$TMP/nogit"
mkdir -p "$NOGIT"
OUT="$(edit_payload NotebookEdit | CLAUDE_PROJECT_DIR="$NOGIT" bash "$NUDGE" 2>&1)"; RC=$?
t="a project dir with no .git fails open: exit 0, no output"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# A read-only agent-team/ state dir must also fail open. chmod on Windows Git
# Bash frequently cannot make a directory truly unwritable, so this case only
# asserts when the platform actually enforces it.
ROPROJ="$TMP/roproj"
mkdir -p "$ROPROJ/.git/agent-team"
chmod 555 "$ROPROJ/.git/agent-team" 2>/dev/null
if ! ( : > "$ROPROJ/.git/agent-team/writetest" ) 2>/dev/null; then
  OUT="$(edit_payload NotebookEdit | CLAUDE_PROJECT_DIR="$ROPROJ" bash "$NUDGE" 2>&1)"; RC=$?
  t="a read-only agent-team/ dir fails open: exit 0, no output"
  { [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"
else
  echo "  skip a read-only agent-team/ dir fails open (platform does not enforce chmod 555)"
fi
chmod 755 "$ROPROJ/.git/agent-team" 2>/dev/null

# --------------------------------------------------------------------------
# SF-3: missing transcript_path falls back to "unknown", like
# guard-heavy-load.sh, rather than silently disabling the feature.
# --------------------------------------------------------------------------
# Every call below shares the "unknown" key (no transcript_path in the
# payload). If the script still counted a real increment per call, the 5th
# would fire; if it silently no-ops (the old bail-out), none of them ever
# will, and this loop would fail to observe a nudge.
for i in 1 2 3 4; do
  OUT="$(edit_payload_no_transcript Edit | run)"; RC=$?
  t="unknown-keyed edit $i below threshold is silent, exits 0"
  { [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"
done
OUT="$(edit_payload_no_transcript Edit | run)"; RC=$?
t="a payload with no transcript_path still increments (keyed unknown) and fires at 5"
{ [ $RC -eq 0 ] && [ -n "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# SF-4: per-transcript keying, and a non-matching tool does not increment.
# --------------------------------------------------------------------------
T2="$TMP/t2.jsonl"
: > "$T2"
for i in 1 2 3 4; do
  edit_payload_for "$T2" Edit | run >/dev/null 2>&1
done
OUT="$(edit_payload_for "$T2" Edit | CLAUDE_PROJECT_DIR="$PROJ" bash "$NUDGE" 2>&1)"; RC=$?
t="a different transcript has its own counter and fires at its own 5th edit"
{ [ $RC -eq 0 ] && [ -n "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

OUT="$(printf '{"transcript_path":"%s","tool_name":"Bash","tool_input":{"command":"ls"}}' "$(native "$T2")" \
  | CLAUDE_PROJECT_DIR="$PROJ" bash "$NUDGE" 2>&1)"; RC=$?
t="a non-matching tool (Bash) does not increment or output anything"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# C-1: a subagent's own edits (agent_id present) must not burn the main
# context's one-time nudge. Per docs/HARNESS-NOTES.md:121-123, agent_id is
# present only inside a subagent invocation.
# --------------------------------------------------------------------------
T3="$TMP/t3.jsonl"
: > "$T3"
for i in 1 2 3 4 5 6; do
  OUT="$(edit_payload_agent "$T3" Edit sub-1 | CLAUDE_PROJECT_DIR="$PROJ" bash "$NUDGE" 2>&1)"; RC=$?
  t="subagent edit $i neither increments nor fires"
  { [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"
done

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
