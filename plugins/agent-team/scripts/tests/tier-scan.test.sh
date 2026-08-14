#!/usr/bin/env bash
# Tests for tier-scan.js
#
#   tier-scan.js   Walks a transcript, finds the LAST top-level assistant text
#                  block announcing a tier (QUICK/FEATURE/PROJECT in backticks
#                  followed by a dash), and reports edits since and whether a
#                  Task ran since. Dumb fact-reporter - policy lives in
#                  tier-guard.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/../tier-scan.js"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - skipping tier-scan tests"
  exit 0
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"
trap 'rm -rf "$TMP"' EXIT

text_record() {  # text [attributionAgent]
  if [ -n "${2:-}" ]; then
    node -e 'const t=process.argv[1],a=process.argv[2];console.log(JSON.stringify({attributionAgent:a,message:{role:"assistant",content:[{type:"text",text:t}]}}))' "$1" "$2"
  else
    node -e 'const t=process.argv[1];console.log(JSON.stringify({message:{role:"assistant",content:[{type:"text",text:t}]}}))' "$1"
  fi
}

tool_record() {  # tool_name [attributionAgent]
  if [ -n "${2:-}" ]; then
    node -e 'const n=process.argv[1],a=process.argv[2];console.log(JSON.stringify({attributionAgent:a,message:{role:"assistant",content:[{type:"tool_use",name:n,input:{}}]}}))' "$1" "$2"
  else
    node -e 'const n=process.argv[1];console.log(JSON.stringify({message:{role:"assistant",content:[{type:"tool_use",name:n,input:{}}]}}))' "$1"
  fi
}

run() { node "$SCAN" "$1"; }

# tier-scan.js looks for the tier name in backticks; build those strings with
# a variable holding the backtick character to avoid fighting bash quoting.
BT=$'\x60'
FEATURE_ANNOUNCE="Routing this as ${BT}FEATURE${BT} - it touches more than one file."
PROJECT_ANNOUNCE="Routing this as ${BT}PROJECT${BT} - it is large."
QUICK_ANNOUNCE="This is a ${BT}QUICK${BT} - one-line fix."
FEATURE_ANNOUNCE2="Routing this as ${BT}FEATURE${BT} - actually bigger."

# --------------------------------------------------------------------------
# no announcement at all
# --------------------------------------------------------------------------
T1="$TMP/t1.jsonl"
{
  text_record "just some plain assistant text, no tier here"
  tool_record "Edit"
} > "$T1"
OUT="$(run "$T1")"
t="no announcement -> NONE 0 0"
[ "$OUT" = "NONE 0 0" ] && ok "$t" || nope "$t" "got '$OUT'"

# --------------------------------------------------------------------------
# announcement, then edits, then Task -> HAS_TASK_SINCE=1
# --------------------------------------------------------------------------
T2="$TMP/t2.jsonl"
{
  text_record "$FEATURE_ANNOUNCE"
  tool_record "Edit"
  tool_record "Edit"
  tool_record "Task"
} > "$T2"
OUT="$(run "$T2")"
t="announcement, edits, then Task -> HAS_TASK_SINCE=1"
[ "$OUT" = "FEATURE 2 1" ] && ok "$t" || nope "$t" "got '$OUT'"

# --------------------------------------------------------------------------
# announcement, edits, no Task -> correct count, HAS_TASK_SINCE=0
# --------------------------------------------------------------------------
T3="$TMP/t3.jsonl"
{
  text_record "$PROJECT_ANNOUNCE"
  tool_record "Edit"
  tool_record "Write"
  tool_record "NotebookEdit"
  tool_record "Edit"
  tool_record "Edit"
} > "$T3"
OUT="$(run "$T3")"
t="announcement, 5 edits, no Task -> correct count, 0"
[ "$OUT" = "PROJECT 5 0" ] && ok "$t" || nope "$t" "got '$OUT'"

# --------------------------------------------------------------------------
# QUICK announcement is still reported (scanner is a dumb fact-reporter)
# --------------------------------------------------------------------------
T4="$TMP/t4.jsonl"
{
  text_record "$QUICK_ANNOUNCE"
  tool_record "Edit"
} > "$T4"
OUT="$(run "$T4")"
t="QUICK announcement is still reported"
[ "$OUT" = "QUICK 1 0" ] && ok "$t" || nope "$t" "got '$OUT'"

# --------------------------------------------------------------------------
# announcement text inside a record WITH attributionAgent does not count
# --------------------------------------------------------------------------
T5="$TMP/t5.jsonl"
{
  text_record "$FEATURE_ANNOUNCE" "some-subagent"
  tool_record "Edit"
} > "$T5"
OUT="$(run "$T5")"
t="an announcement inside a record with attributionAgent does not count"
[ "$OUT" = "NONE 0 0" ] && ok "$t" || nope "$t" "got '$OUT'"

# --------------------------------------------------------------------------
# LAST announcement wins, and edits/Task from subagent records do not count
# --------------------------------------------------------------------------
T6="$TMP/t6.jsonl"
{
  text_record "$QUICK_ANNOUNCE"
  text_record "$FEATURE_ANNOUNCE2"
  tool_record "Edit" "some-subagent"
  tool_record "Task" "some-subagent"
  tool_record "Edit"
  tool_record "Edit"
} > "$T6"
OUT="$(run "$T6")"
t="last announcement wins, subagent tool_use records are excluded"
[ "$OUT" = "FEATURE 2 0" ] && ok "$t" || nope "$t" "got '$OUT'"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
