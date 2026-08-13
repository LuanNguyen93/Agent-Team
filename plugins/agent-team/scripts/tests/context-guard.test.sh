#!/usr/bin/env bash
# Tests for the two context hooks.
#
#   context-budget.sh     UserPromptSubmit - surfaces the context size and, past
#                         a threshold, asks for a compaction. Never blocks.
#   guard-heavy-load.sh   PreToolUse on Skill and WebFetch - refuses to pull a
#                         large payload into an already-large main context,
#                         once, with advice to read it in a subagent instead.
#
# The failure this guards against is the measured one: a single skill load of
# 234k tokens took the context from 317k to 707k and tripled the per-turn cost
# for the rest of the session.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUDGET="$SCRIPT_DIR/../context-budget.sh"
GUARD="$SCRIPT_DIR/../guard-heavy-load.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - skipping context guard tests"
  exit 0
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"
trap 'rm -rf "$TMP"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# A fake project with a git dir, so the guard has somewhere to put its stamp.
PROJ="$TMP/proj"
mkdir -p "$PROJ/.git"

transcript_at() {  # size -> path
  local f="$TMP/t$1.jsonl"
  printf '{"message":{"usage":{"input_tokens":0,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s}}}\n' "$1" > "$f"
  printf '%s' "$f"
}

SMALL="$(transcript_at 40000)"
BIG="$(transcript_at 400000)"

payload() {  # transcript skill
  printf '{"transcript_path":"%s","tool_name":"Skill","tool_input":{"skill":"%s"}}' "$(native "$1")" "$2"
}

# --------------------------------------------------------------------------
# context-budget.sh
# --------------------------------------------------------------------------
OUT="$(printf '{"transcript_path":"%s"}' "$(native "$SMALL")" | CLAUDE_PROJECT_DIR="$PROJ" bash "$BUDGET" 2>&1)"; RC=$?
t="budget hook stays quiet and exits 0 on a small context"
{ [ $RC -eq 0 ] && [ -z "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

OUT="$(printf '{"transcript_path":"%s"}' "$(native "$BIG")" | CLAUDE_PROJECT_DIR="$PROJ" bash "$BUDGET" 2>&1)"; RC=$?
t="budget hook speaks up past the threshold, but still exits 0"
{ [ $RC -eq 0 ] && [ -n "$OUT" ]; } && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

t="budget hook names the actual size so the advice is checkable"
case "$OUT" in *400*) ok "$t";; *) nope "$t" "size not in: $OUT";; esac

OUT="$(printf '{"transcript_path":"%s"}' "$(native "$BIG")" | AGENT_TEAM_SKIP_CONTEXT_GUARD=1 CLAUDE_PROJECT_DIR="$PROJ" bash "$BUDGET" 2>&1)"
t="budget hook can be opted out of for a session"
[ -z "$OUT" ] && ok "$t" || nope "$t" "expected silence, got '$OUT'"

# --------------------------------------------------------------------------
# guard-heavy-load.sh
# --------------------------------------------------------------------------
OUT="$(payload "$SMALL" claude-api | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="guard allows any skill while the context is still small"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

OUT="$(payload "$BIG" claude-api | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="guard blocks a skill load into an already-large context"
[ $RC -eq 2 ] && ok "$t" || nope "$t" "expected exit 2, got rc=$RC out='$OUT'"

t="guard explains the alternative rather than just refusing"
case "$OUT" in *subagent*) ok "$t";; *) nope "$t" "no advice in: $OUT";; esac

# The second attempt must succeed, or the agent is stuck in a loop it cannot
# leave: the guard is advice with teeth, not a wall.
OUT="$(payload "$BIG" claude-api | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="guard allows the same skill on a second attempt, so nothing deadlocks"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "expected exit 0, got rc=$RC out='$OUT'"

# A different skill is a fresh decision.
OUT="$(payload "$BIG" some-other-skill | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="the one-warning allowance is per skill, not global"
[ $RC -eq 2 ] && ok "$t" || nope "$t" "expected exit 2, got rc=$RC"

OUT="$(payload "$BIG" yet-another | AGENT_TEAM_SKIP_CONTEXT_GUARD=1 CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="guard can be opted out of for a session"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC"

# A payload for some other tool must pass straight through.
OUT="$(printf '{"transcript_path":"%s","tool_name":"Bash","tool_input":{"command":"ls"}}' "$(native "$BIG")" \
  | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="guard ignores tools it does not cover"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

# --------------------------------------------------------------------------
# WebFetch - measured at ~14k tokens per call, the largest single tool sink in
# the most expensive session, and never reclaimed: a page fetched at turn 50 is
# still being re-read at turn 400.
# --------------------------------------------------------------------------
fetch_payload() {  # transcript url
  printf '{"transcript_path":"%s","tool_name":"WebFetch","tool_input":{"url":"%s"}}' "$(native "$1")" "$2"
}

OUT="$(fetch_payload "$SMALL" https://example.com/a | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="a fetch is allowed while the context is still small"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

OUT="$(fetch_payload "$BIG" https://example.com/a | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="a fetch into an already-large context is blocked"
[ $RC -eq 2 ] && ok "$t" || nope "$t" "expected exit 2, got rc=$RC out='$OUT'"

t="the fetch advice names the subagent alternative"
case "$OUT" in *subagent*) ok "$t";; *) nope "$t" "no advice in: $OUT";; esac

t="the fetch advice names the URL, so the warning is actionable"
case "$OUT" in *example.com/a*) ok "$t";; *) nope "$t" "url missing from: $OUT";; esac

OUT="$(fetch_payload "$BIG" https://example.com/a | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="the same URL goes through on a second attempt"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "expected exit 0, got rc=$RC"

OUT="$(fetch_payload "$BIG" https://example.com/b | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="a different URL is a fresh decision"
[ $RC -eq 2 ] && ok "$t" || nope "$t" "expected exit 2, got rc=$RC"

# A skill and a URL must not share a stamp key, or warning about one silently
# spends the other's allowance.
OUT="$(payload "$BIG" https://example.com/b | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="a skill named like an already-warned URL still gets its own warning"
[ $RC -eq 2 ] && ok "$t" || nope "$t" "expected exit 2, got rc=$RC"

# An unreadable payload must never block a turn.
OUT="$(printf 'not json' | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1)"; RC=$?
t="an unreadable payload fails open"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
