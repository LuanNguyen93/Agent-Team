#!/usr/bin/env bash
# Plain POSIX-ish test runner for measure-tokens.js - no bats, no npm test
# runner, matching this repo's convention of avoiding tools that may be absent
# (CLAUDE.md).
#
# Fixtures are synthetic transcript trees built under a tempdir. They are
# generated here rather than checked in because the assertions are about
# arithmetic on usage numbers, and a checked-in fixture would drift from the
# pricing table without anything noticing.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEASURE="$SCRIPT_DIR/../measure-tokens.js"

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - skipping measure-tokens tests"
  exit 0
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"
trap 'rm -rf "$TMP"' EXIT

# A usage record. Args: model cacheRead cacheWrite out
usage_line() {
  printf '{"uuid":"u%s","message":{"role":"assistant","model":"%s","usage":{"input_tokens":0,"output_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}\n' \
    "$RANDOM" "$1" "$4" "$3" "$2"
}

# --- fixture: one project, one session, one subagent transcript -------------
PROJ="$TMP/proj"
mkdir -p "$PROJ/aaaaaaaa-1111/subagents"

# MAIN: 2 calls on opus.
#   call 1: read 100000, write 10000, out 1000
#   call 2: read 200000, write  5000, out  500
{ usage_line claude-opus-5 100000 10000 1000
  usage_line claude-opus-5 200000  5000  500
} > "$PROJ/aaaaaaaa-1111.jsonl"

# SUBAGENT: 1 call on sonnet, read 50000, write 2000, out 300, attributed to
# agent-team:implementer so byAgentModel can be tested independently of the
# main/sub split above.
usage_line claude-sonnet-5 50000 2000 300 \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s);o.attributionAgent="agent-team:implementer";console.log(JSON.stringify(o));})' \
  > "$PROJ/aaaaaaaa-1111/subagents/s1.jsonl"

# Expected, at list price (opus 15/75 in/out, write 1.25x in, read 0.1x in):
#   main read  = (100000+200000) * 1.5 /1e6 = 0.45
#   main write = ( 10000+  5000) * 18.75/1e6 = 0.28125
#   main out   = (  1000+   500) * 75  /1e6 = 0.1125
#   main total = 0.84375
#   sub  read  = 50000 * 0.3 /1e6 = 0.015
#   sub  write =  2000 * 3.75/1e6 = 0.0075
#   sub  out   =   300 * 15  /1e6 = 0.0045
#   sub  total = 0.027
#   grand      = 0.87075
#   main maxContext = 205000 ; main avgContext = (110000+205000)/2 = 157500

OUT="$(node "$MEASURE" --project "$PROJ" --json 2>&1)"
RC=$?

t="exits 0 on a valid project tree"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "exit=$RC out=$OUT"

get() { printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const o=JSON.parse(s);const v=process.argv[1].split(".").reduce((a,k)=>a&&a[/^\d+$/.test(k)?+k:k],o);
  console.log(typeof v==="number"?v.toFixed(5):JSON.stringify(v));}catch(e){console.log("PARSE_ERR")}});' "$1"; }

t="--json emits parseable JSON"
[ "$(get project)" != "PARSE_ERR" ] && ok "$t" || nope "$t" "$OUT"

t="main cost is computed at opus list price"
v="$(get sessions.0.main.cost)"
[ "$v" = "0.84375" ] && ok "$t" || nope "$t" "expected 0.84375 got $v"

t="subagent transcripts are attributed to sub, at sonnet price"
v="$(get sessions.0.sub.cost)"
[ "$v" = "0.02700" ] && ok "$t" || nope "$t" "expected 0.02700 got $v"

t="subagent call count is separate from main"
v="$(get sessions.0.sub.calls)"
[ "$v" = "1.00000" ] && ok "$t" || nope "$t" "expected 1 got $v"

t="maxContext is the largest single-call context"
v="$(get sessions.0.main.maxContext)"
[ "$v" = "205000.00000" ] && ok "$t" || nope "$t" "expected 205000 got $v"

t="avgContext is the mean context across main calls"
v="$(get sessions.0.main.avgContext)"
[ "$v" = "157500.00000" ] && ok "$t" || nope "$t" "expected 157500 got $v"

t="totals.cost sums main and sub"
v="$(get totals.cost)"
[ "$v" = "0.87075" ] && ok "$t" || nope "$t" "expected 0.87075 got $v"

t="byAgentModel has a row for the attributed subagent call"
found="no"
i=0
while [ "$i" -lt 5 ]; do
  a="$(get byAgentModel.$i.agent)"
  [ "$a" = "PARSE_ERR" ] && break
  if [ "$a" = '"agent-team:implementer"' ]; then
    w="$(get byAgentModel.$i.model)"
    x="$(get byAgentModel.$i.calls)"
    [ "$w" = '"claude-sonnet-5"' ] && [ "$x" = "1.00000" ] && found="yes"
    break
  fi
  i=$((i+1))
done
[ "$found" = "yes" ] && ok "$t" || nope "$t" "no matching agent-team:implementer/claude-sonnet-5/1 row found"

# --- second session, differently-attributed subagent, to test byAgent scoping
mkdir -p "$PROJ/bbbbbbbb-2222/subagents"
usage_line claude-opus-5 1000 100 50 > "$PROJ/bbbbbbbb-2222.jsonl"
usage_line claude-haiku-4-5 2000 200 20 \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s);o.attributionAgent="claude-code-guide";console.log(JSON.stringify(o));})' \
  > "$PROJ/bbbbbbbb-2222/subagents/s1.jsonl"

OUT="$(node "$MEASURE" --project "$PROJ" --json 2>&1)"

find_session_index() {
  local id="$1" i=0
  while [ "$i" -lt 10 ]; do
    v="$(get sessions.$i.id)"
    [ "$v" = "PARSE_ERR" ] && { echo -1; return; }
    if [ "$v" = "\"$id\"" ]; then echo "$i"; return; fi
    i=$((i+1))
  done
  echo -1
}

SI_A="$(find_session_index aaaaaaaa-1111)"
SI_B="$(find_session_index bbbbbbbb-2222)"

t="byAgent on session A does not contain claude-code-guide"
found="no"
i=0
while [ "$i" -lt 5 ]; do
  a="$(get sessions.$SI_A.byAgent.$i.agent)"
  [ "$a" = "PARSE_ERR" ] && break
  [ "$a" = '"claude-code-guide"' ] && found="yes" && break
  i=$((i+1))
done
[ "$found" = "no" ] && ok "$t" || nope "$t" "claude-code-guide leaked into session A's byAgent"

t="byAgent on session B contains claude-code-guide"
found="no"
i=0
while [ "$i" -lt 5 ]; do
  a="$(get sessions.$SI_B.byAgent.$i.agent)"
  [ "$a" = "PARSE_ERR" ] && break
  [ "$a" = '"claude-code-guide"' ] && found="yes" && break
  i=$((i+1))
done
[ "$found" = "yes" ] && ok "$t" || nope "$t" "claude-code-guide missing from session B's byAgent"

# cumulative is byAgentModel folded, independent of totals.cost - it must count
# every attributed call across every session, including session B's.
# Session A: 2 main opus + 1 sub sonnet = 3 calls, cacheRead 100000+200000+50000=350000
# Session B: 1 main opus + 1 sub haiku = 2 calls, cacheRead 1000+2000=3000
# cumulative.calls = 5, cumulative.cacheRead = 353000
t="cumulative.calls counts every call across every session"
v="$(get cumulative.calls)"
[ "$v" = "5.00000" ] && ok "$t" || nope "$t" "expected 5 got $v"

t="cumulative.cacheRead sums cacheRead across every session"
v="$(get cumulative.cacheRead)"
[ "$v" = "353000.00000" ] && ok "$t" || nope "$t" "expected 353000 got $v"

# --- --by-agent replaces the session table with the agent x model table -----
OUT="$(node "$MEASURE" --project "$PROJ" --by-agent 2>&1)"
t="--by-agent prints the attributed agent name"
case "$OUT" in *"agent-team:implementer"*) ok "$t";; *) nope "$t" "$OUT";; esac

t="--by-agent prints (main context) for unattributed calls"
case "$OUT" in *"(main context)"*) ok "$t";; *) nope "$t" "$OUT";; esac

# --- --per-session implies --by-agent: one heading per session --------------
OUT="$(node "$MEASURE" --project "$PROJ" --per-session 2>&1)"
# These match the literal "Session " heading printed only by --per-session
# (report.js:367), not the bare id, which the DEFAULT session table also
# prints via s.id.slice(0,8) - a bare-id match would pass whether or not
# --per-session did anything.
t="--per-session prints a heading for session A"
case "$OUT" in *"Session aaaaaaaa"*) ok "$t";; *) nope "$t" "$OUT";; esac

t="--per-session prints a heading for session B"
case "$OUT" in *"Session bbbbbbbb"*) ok "$t";; *) nope "$t" "$OUT";; esac

t="--per-session prints claude-code-guide only under session B's heading"
# Split output on session B's own id line and check the agent name appears
# after it, proving the row is scoped rather than a flat by-agent dump.
AFTER_B="$(printf '%s' "$OUT" | awk '/bbbbbbbb/{f=1} f')"
case "$AFTER_B" in *"claude-code-guide"*) ok "$t";; *) nope "$t" "$OUT";; esac

# Restore OUT to --json mode for the remaining JSON-based assertions below.
OUT="$(node "$MEASURE" --project "$PROJ" --json 2>&1)"

t="byAgentModel has a (main context) row for unattributed calls"
found="no"
i=0
while [ "$i" -lt 5 ]; do
  a="$(get byAgentModel.$i.agent)"
  [ "$a" = "PARSE_ERR" ] && break
  [ "$a" = '"(main context)"' ] && found="yes" && break
  i=$((i+1))
done
[ "$found" = "yes" ] && ok "$t" || nope "$t" "no (main context) row found in byAgentModel"

# --- B1: a subagent record with no attributionAgent must not be billed to
# (main context) - it is still delegated spend, just unlabelled delegated
# spend. Two cuts of the same numbers must agree: the sum of byAgentModel
# rows tagged (main context) must equal the sum of sessions[].main.cost.
# That equality is exactly what broke when the fallback used a constant
# instead of `which`.
B1="$TMP/b1"
mkdir -p "$B1/proj/cccccccc-4444/subagents"
usage_line claude-opus-5 1000 100 10 > "$B1/proj/cccccccc-4444.jsonl"
# No attributionAgent on this one - a real, billed, unattributed subagent call.
usage_line claude-sonnet-5 2000 200 20 > "$B1/proj/cccccccc-4444/subagents/s1.jsonl"

OUT="$(node "$MEASURE" --project "$B1/proj" --json 2>&1)"

t="unattributed subagent spend is not billed to (main context)"
RESULT="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const o=JSON.parse(s);
  const mainFromAgentModel = o.byAgentModel
    .filter(r => r.agent === "(main context)")
    .reduce((a,r)=>a+r.cost,0);
  const mainFromSessions = o.sessions.reduce((a,sess)=>a+sess.main.cost,0);
  const diff = Math.abs(mainFromAgentModel - mainFromSessions);
  console.log(diff < 1e-9 ? "OK" : "MISMATCH " + mainFromAgentModel + " vs " + mainFromSessions);
});')"
[ "$RESULT" = "OK" ] && ok "$t" || nope "$t" "$RESULT"

t="unattributed subagent gets its own labelled bucket, not (main context)"
found="no"
i=0
while [ "$i" -lt 5 ]; do
  a="$(get byAgentModel.$i.agent)"
  [ "$a" = "PARSE_ERR" ] && break
  [ "$a" = '"(unattributed subagent)"' ] && found="yes" && break
  i=$((i+1))
done
[ "$found" = "yes" ] && ok "$t" || nope "$t" "no (unattributed subagent) row found"

# --- malformed lines must not abort the run --------------------------------
printf 'not json at all\n{"partial":\n' >> "$PROJ/aaaaaaaa-1111.jsonl"
OUT="$(node "$MEASURE" --project "$PROJ" --json 2>&1)"
t="malformed JSONL lines are skipped, not fatal"
v="$(get sessions.0.main.cost)"
[ "$v" = "0.84375" ] && ok "$t" || nope "$t" "expected 0.84375 got $v"

# --- a missing project dir is an error, not a silent empty report ----------
OUT="$(node "$MEASURE" --project "$TMP/does-not-exist" --json 2>&1)"
RC=$?
t="missing project dir exits non-zero"
[ $RC -ne 0 ] && ok "$t" || nope "$t" "exit=$RC out=$OUT"

t="missing project dir says so on stderr"
case "$OUT" in *"does-not-exist"*) ok "$t";; *) nope "$t" "$OUT";; esac

# --- fillers must read where the payload actually lives ---------------------
#
# A tool result appears twice in a transcript: a short reference inside
# message.content, and the real payload in the top-level toolUseResult. Reading
# only the former undercounts a large result by orders of magnitude - exactly
# backwards for the one function whose job is finding what filled the context.
FILL="$TMP/fill"
mkdir -p "$FILL"
BIG="$(node -e 'console.log("x".repeat(40000))')"
{
  printf '{"uuid":"a1","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"tool_use","id":"t1","name":"WebFetch","input":{}}],"usage":{"input_tokens":0,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000}}}\n'
  printf '{"uuid":"a2","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"see toolUseResult"}]},"toolUseResult":"%s"}\n' "$BIG"
} > "$FILL/sess.jsonl"

# A subagent transcript for this same session, attributed to a different agent,
# using a distinct tool with its own large payload - fillers must show both
# agents' groupings, not merge them or drop the subagent one.
mkdir -p "$FILL/sess/subagents"
BIG2="$(node -e 'console.log("y".repeat(20000))')"
{
  printf '{"uuid":"b1","attributionAgent":"agent-team:implementer","message":{"role":"assistant","model":"claude-sonnet-5","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{}}],"usage":{"input_tokens":0,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":500}}}\n'
  printf '{"uuid":"b2","attributionAgent":"agent-team:implementer","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"see toolUseResult"}]},"toolUseResult":"%s"}\n' "$BIG2"
} > "$FILL/sess/subagents/s1.jsonl"

OUT="$(node "$MEASURE" --project "$FILL" --fillers 2>&1)"
t="fillers attributes the toolUseResult payload to its tool"
case "$OUT" in *WebFetch*) ok "$t";; *) nope "$t" "no WebFetch row: $(printf '%s' "$OUT" | tail -5)";; esac

t="fillers counts the real payload size, not the reference stub"
SIZE="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const m=s.match(/WebFetch\s+\d+\s+(\d+)k/);
  console.log(m?m[1]:"0");
});')"
[ "$SIZE" -ge 9 ] && ok "$t" || nope "$t" "expected ~10k tokens, got ${SIZE}k"

t="fillers groups the main context tool under (main context)"
case "$OUT" in *"(main context)"*) ok "$t";; *) nope "$t" "$OUT";; esac

t="fillers groups the subagent tool under its attributed agent"
case "$OUT" in *"agent-team:implementer"*) ok "$t";; *) nope "$t" "$OUT";; esac

t="fillers shows the subagent's own tool, Bash"
case "$OUT" in *Bash*) ok "$t";; *) nope "$t" "no Bash row: $OUT";; esac

# --- an unrecognised model still shows up, billed at the opus tier ---------
#
# tierOf() already defaults an unknown model to opus so a new model can never
# silently disappear from the report. This locks that guarantee in for the
# agent x model table specifically, where a vanished row would look like a
# missing agent rather than a pricing miss.
UNK="$TMP/unknown"
mkdir -p "$UNK"
usage_line claude-nonexistent-9 1000 100 10 > "$UNK/ccccccc-3333.jsonl"

OUT="$(node "$MEASURE" --project "$UNK" --json 2>&1)"
t="an unrecognised model appears in byAgentModel rather than vanishing"
found="no"
MATCH_I=-1
i=0
while [ "$i" -lt 5 ]; do
  m="$(get byAgentModel.$i.model)"
  [ "$m" = "PARSE_ERR" ] && break
  if [ "$m" = '"claude-nonexistent-9"' ]; then found="yes"; MATCH_I="$i"; break; fi
  i=$((i+1))
done
[ "$found" = "yes" ] && ok "$t" || nope "$t" "claude-nonexistent-9 missing from byAgentModel"

t="an unrecognised model is billed at the opus tier (15/75 per 1M)"
# usage_line args are (model cacheRead cacheWrite out) = (1000, 100, 10):
# out 10*75/1e6 + write 100*18.75/1e6 + read 1000*1.5/1e6 = 0.00075+0.001875+0.0015 = 0.004125
v="$(get byAgentModel.$MATCH_I.cost)"
[ "$v" = "0.00413" ] && ok "$t" || nope "$t" "expected 0.00413 got $v"

# --- S2: a record with no message.model must not crash --by-agent, and must
# still appear (labelled) rather than vanish - the file's own stated contract
# at :40 is that an unrecognised model can never silently disappear.
NOMODEL="$TMP/nomodel"
mkdir -p "$NOMODEL"
printf '{"uuid":"n1","message":{"role":"assistant","usage":{"input_tokens":0,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000}}}\n' \
  > "$NOMODEL/dddddddd-5555.jsonl"

OUT="$(node "$MEASURE" --project "$NOMODEL" --by-agent 2>&1)"
RC=$?
t="--by-agent does not crash on a record with no message.model"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "exit=$RC out=$OUT"

t="--by-agent labels a missing model rather than dropping the row"
case "$OUT" in *"(unknown model)"*) ok "$t";; *) nope "$t" "$OUT";; esac

# --- cost is sourced from tui/shared/rates.json, not a literal in this file -
#
# Copies the script and rates.json into an isolated tree (preserving the
# relative path from scripts/ to tui/shared/), mutates the opus input rate in
# the copy, and checks the reported cost moves with it. If the script still
# carries its own hardcoded RATES table this is a no-op and the cost will not
# move.
RATE_TEST="$TMP/rate-source"
mkdir -p "$RATE_TEST/plugins/agent-team/scripts" "$RATE_TEST/plugins/agent-team/tui/shared"
cp "$MEASURE" "$RATE_TEST/plugins/agent-team/scripts/measure-tokens.js"
cp "$SCRIPT_DIR/../../tui/shared/rates.json" "$RATE_TEST/plugins/agent-team/tui/shared/rates.json"
node -e '
  const fs = require("fs");
  const p = process.argv[1];
  const r = JSON.parse(fs.readFileSync(p, "utf8"));
  r.tiers.opus.input = 999;
  fs.writeFileSync(p, JSON.stringify(r, null, 2));
' "$RATE_TEST/plugins/agent-team/tui/shared/rates.json"

RATE_PROJ="$RATE_TEST/proj"
mkdir -p "$RATE_PROJ"
# Cache-write tokens only, so the whole cost is driven by the (mutated) opus
# input rate and its 1.25x multiplier - nothing else contributes.
usage_line claude-opus-5 0 1000 0 > "$RATE_PROJ/ffffffff-7777.jsonl"

RATE_OUT="$(node "$RATE_TEST/plugins/agent-team/scripts/measure-tokens.js" --project "$RATE_PROJ" --json 2>&1)"
get_from() { printf '%s' "$1" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const o=JSON.parse(s);const v=process.argv[1].split(".").reduce((a,k)=>a&&a[/^\d+$/.test(k)?+k:k],o);
  console.log(typeof v==="number"?v.toFixed(5):JSON.stringify(v));}catch(e){console.log("PARSE_ERR")}});' "$2"; }

t="cost derives from tui/shared/rates.json rather than a hardcoded literal"
CW_COST="$(get_from "$RATE_OUT" sessions.0.main.cost)"
# With the mutated input rate 999: 1000 cache-write tokens * 999 * 1.25 / 1e6 = 1.24875
[ "$CW_COST" = "1.24875" ] && ok "$t" || nope "$t" "expected 1.24875 (rate read from mutated rates.json) got $CW_COST"

# --- fixture-only checks (not parity, not measure-tokens.js behaviour) -----
FIXTURE_DIR="$SCRIPT_DIR/../../tui/tests/fixtures/transcripts"
REGEN="$SCRIPT_DIR/../../tui/tests/regen-transcript-expected.sh"

# This asserts a property of the committed FIXTURE file, not of
# measure-tokens.js: exactly one line in cccccccc-3333.jsonl must fail
# JSON.parse. Without this, someone silently dropping the malformed line
# (or "fixing" it to valid JSON) makes a future Rust malformed_lines==1 test
# pass vacuously - it would no longer be testing anything.
t="cccccccc-3333.jsonl fixture contains exactly one line that fails JSON.parse"
BAD_COUNT="$(node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  let bad = 0;
  for (const line of lines) {
    if (!line.trim()) continue;
    try { JSON.parse(line); } catch (e) { bad++; }
  }
  console.log(bad);
' "$FIXTURE_DIR/project/cccccccc-3333.jsonl")"
[ "$BAD_COUNT" = "1" ] && ok "$t" || nope "$t" "expected exactly 1 malformed line, got $BAD_COUNT"

# expected.json regeneration must be a pure function of the committed
# fixture input: re-running it must leave the file byte-identical, on any
# machine - this is what catches the absolute-path leak that broke it before.
t="regenerating expected.json twice leaves it byte-identical"
if [ -x "$REGEN" ] || [ -f "$REGEN" ]; then
  bash "$REGEN" >/dev/null
  FIRST="$(cat "$FIXTURE_DIR/expected.json")"
  bash "$REGEN" >/dev/null
  SECOND="$(cat "$FIXTURE_DIR/expected.json")"
  [ "$FIRST" = "$SECOND" ] && ok "$t" || nope "$t" "expected.json changed on re-run"
else
  nope "$t" "regen script not found at $REGEN"
fi

t="expected.json carries no machine-specific project path"
case "$(cat "$FIXTURE_DIR/expected.json")" in
  *'"project"'*) nope "$t" "expected.json still contains a project field";;
  *) ok "$t";;
esac

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
