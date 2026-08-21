#!/usr/bin/env bash
# Tests for tier-guard.sh
#
#   tier-guard.sh   PreToolUse on Edit|Write|NotebookEdit - if a FEATURE or
#                   PROJECT tier was announced, 5+ undelegated edits have
#                   happened since, and no Task has run since, block ONCE
#                   (exit 2) with a message naming the tier and the agents it
#                   names, and telling the agent to re-read workflow-router.
#                   QUICK, no announcement, and a Task since all pass through.
#
# Mechanism mirrors delegation-nudge.sh / guard-heavy-load.sh: node does the
# JSON parsing, a stamp file under .git/agent-team/ makes the block one-shot,
# everything fails open.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/../tier-guard.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - skipping tier-guard tests"
  exit 0
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"
trap 'rm -rf "$TMP"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

PROJ="$TMP/proj"
mkdir -p "$PROJ/.git"

BT=$'\x60'

text_record() {  # text
  node -e 'const t=process.argv[1];console.log(JSON.stringify({message:{role:"assistant",content:[{type:"text",text:t}]}}))' "$1"
}
tool_record() {  # tool_name
  node -e 'const n=process.argv[1];console.log(JSON.stringify({message:{role:"assistant",content:[{type:"tool_use",name:n,input:{}}]}}))' "$1"
}

# Transcript: FEATURE announced, then N edits, optionally a Task.
feature_transcript() {  # file edit_count [with_task]
  local f="$1" n="$2" with_task="${3:-}"
  {
    text_record "Routing this as ${BT}FEATURE${BT} - more than one file."
    local i
    for ((i=0; i<n; i++)); do tool_record "Edit"; done
    [ -n "$with_task" ] && tool_record "Task"
  } > "$f"
}

# Transcript: FEATURE announced, then N read-only calls (Bash), optionally a Task.
feature_readonly_transcript() {  # file readonly_count [with_task]
  local f="$1" n="$2" with_task="${3:-}"
  {
    text_record "Routing this as ${BT}FEATURE${BT} - more than one file."
    local i
    for ((i=0; i<n; i++)); do tool_record "Bash"; done
    [ -n "$with_task" ] && tool_record "Task"
  } > "$f"
}

quick_transcript() {  # file edit_count
  local f="$1" n="$2" i
  {
    text_record "This is a ${BT}QUICK${BT} - one-liner."
    for ((i=0; i<n; i++)); do tool_record "Edit"; done
  } > "$f"
}

no_announce_transcript() {  # file edit_count
  local f="$1" n="$2" i
  {
    text_record "just doing some work"
    for ((i=0; i<n; i++)); do tool_record "Edit"; done
  } > "$f"
}

edit_payload() {  # transcript tool_name
  printf '{"transcript_path":"%s","tool_name":"%s","tool_input":{"file_path":"x.txt"}}' "$(native "$1")" "$2"
}

run() { CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1; }

# --------------------------------------------------------------------------
# FEATURE + 5 edits + no Task -> blocked, message names FEATURE
# --------------------------------------------------------------------------
T1="$TMP/t1.jsonl"
feature_transcript "$T1" 5
OUT="$(edit_payload "$T1" Edit | run)"; RC=$?
t="FEATURE announced, 5 edits, no Task -> exit 2"
[ $RC -eq 2 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"
t="block message names FEATURE"
case "$OUT" in *FEATURE*) ok "$t";; *) nope "$t" "not in: $OUT";; esac

# --------------------------------------------------------------------------
# Second call, same transcript -> one-shot, exit 0 silent
# --------------------------------------------------------------------------
OUT="$(edit_payload "$T1" Edit | run)"; RC=$?
t="second call after a block exits 0 (one-shot)"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# Task present after announcement -> exit 0 silent
# --------------------------------------------------------------------------
T2="$TMP/t2.jsonl"
feature_transcript "$T2" 5 with_task
OUT="$(edit_payload "$T2" Edit | run)"; RC=$?
t="Task ran since announcement -> exit 0 silent"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# QUICK -> exit 0
# --------------------------------------------------------------------------
T3="$TMP/t3.jsonl"
quick_transcript "$T3" 5
OUT="$(edit_payload "$T3" Edit | run)"; RC=$?
t="QUICK tier -> exit 0"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# no announcement -> exit 0
# --------------------------------------------------------------------------
T4="$TMP/t4.jsonl"
no_announce_transcript "$T4" 5
OUT="$(edit_payload "$T4" Edit | run)"; RC=$?
t="no announcement -> exit 0"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# FEATURE + fewer than 5 edits -> exit 0
# --------------------------------------------------------------------------
T5="$TMP/t5.jsonl"
feature_transcript "$T5" 4
OUT="$(edit_payload "$T5" Edit | run)"; RC=$?
t="FEATURE announced, only 4 edits -> exit 0"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# AGENT_TEAM_SKIP_CONTEXT_GUARD=1 -> exit 0
# --------------------------------------------------------------------------
T6="$TMP/t6.jsonl"
feature_transcript "$T6" 5
OUT="$(edit_payload "$T6" Edit | AGENT_TEAM_SKIP_CONTEXT_GUARD=1 CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="AGENT_TEAM_SKIP_CONTEXT_GUARD=1 -> exit 0"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# agent_id present (subagent's own edit) -> exit 0, never blocks
# --------------------------------------------------------------------------
T7="$TMP/t7.jsonl"
feature_transcript "$T7" 5
PAYLOAD="$(printf '{"transcript_path":"%s","tool_name":"Edit","agent_id":"sub-1","tool_input":{"file_path":"x.txt"}}' "$(native "$T7")")"
OUT="$(printf '%s' "$PAYLOAD" | run)"; RC=$?
t="agent_id present -> exit 0, never blocks"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# non-matching tool -> exit 0
#
# Bash/Read/Grep/Glob are now matched too (READONLY widening), so a truly
# non-matching tool is one outside that whole set.
# --------------------------------------------------------------------------
T8="$TMP/t8.jsonl"
feature_transcript "$T8" 5
OUT="$(printf '{"transcript_path":"%s","tool_name":"WebFetch","tool_input":{}}' "$(native "$T8")" | run)"; RC=$?
t="a non-matching tool (WebFetch) -> exit 0"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# fail-open cases
# --------------------------------------------------------------------------
OUT="$(printf 'not json' | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="garbage stdin exits 0"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

NOGIT="$TMP/nogit"
mkdir -p "$NOGIT"
T9="$TMP/t9.jsonl"
feature_transcript "$T9" 5
OUT="$(edit_payload "$T9" Edit | CLAUDE_PROJECT_DIR="$NOGIT" bash "$GUARD" 2>&1)"; RC=$?
t="a project dir with no .git fails open: exit 0"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

OUT="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"x.txt"}}' | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="missing transcript_path falls back to unknown and fails open: exit 0"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# FEATURE + 16 readonly (Bash) calls + no Task -> blocked
# --------------------------------------------------------------------------
T10="$TMP/t10.jsonl"
feature_readonly_transcript "$T10" 16
OUT="$(edit_payload "$T10" Bash | run)"; RC=$?
t="FEATURE announced, 16 readonly calls, no Task -> exit 2"
[ $RC -eq 2 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# FEATURE + 4 edits + 14 readonly calls (both under their own thresholds) -> pass
# --------------------------------------------------------------------------
T11="$TMP/t11.jsonl"
{
  text_record "Routing this as ${BT}FEATURE${BT} - more than one file."
  for ((i=0; i<4; i++)); do tool_record "Edit"; done
  for ((i=0; i<14; i++)); do tool_record "Bash"; done
} > "$T11"
OUT="$(edit_payload "$T11" Edit | run)"; RC=$?
t="4 edits + 14 readonly, both under their own thresholds -> exit 0"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# a readonly tool (Grep) -> exit 0 when under the readonly threshold
# --------------------------------------------------------------------------
T12="$TMP/t12.jsonl"
feature_readonly_transcript "$T12" 3
OUT="$(edit_payload "$T12" Grep | run)"; RC=$?
t="a readonly tool under threshold -> exit 0"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
