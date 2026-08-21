#!/usr/bin/env bash
# Tests for file-length-guard.sh
#
#   file-length-guard.sh  PostToolUse on Edit|Write|NotebookEdit - after a file
#                         is written, if it now exceeds AGENT_TEAM_MAX_FILE_LINES
#                         (default 800) emit a non-blocking nudge to split it.
#                         Once per file per session. Never blocks.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/../file-length-guard.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - skipping file-length guard tests"
  exit 0
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"
trap 'rm -rf "$TMP"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

PROJ="$TMP/proj"
mkdir -p "$PROJ"
git -C "$PROJ" init -q
export CLAUDE_PROJECT_DIR="$(native "$PROJ")"

mkfile() { # path lines
  local i=1; : > "$1"
  while [ $i -le "$2" ]; do echo "line $i" >> "$1"; i=$((i+1)); done
}
payload() { # tool file
  printf '{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$(native "$2")"
}
run() { printf '%s' "$1" | bash "$GUARD" 2>/dev/null; }

echo "file-length-guard.sh"

t="short file -> silent"
mkfile "$PROJ/a.ts" 50
OUT="$(run "$(payload Write "$PROJ/a.ts")")"; RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

t="exactly 800 lines -> silent"
mkfile "$PROJ/b.ts" 800
OUT="$(run "$(payload Edit "$PROJ/b.ts")")"
[ -z "$OUT" ] && ok "$t" || nope "$t" "out='$OUT'"

t="801 lines -> nudge envelope naming the file and count"
mkfile "$PROJ/c.ts" 801
OUT="$(run "$(payload Edit "$PROJ/c.ts")")"; RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q '"hookEventName":"PostToolUse"' \
   && printf '%s' "$OUT" | grep -q 'c.ts' && printf '%s' "$OUT" | grep -q '801'; then ok "$t"; else nope "$t" "rc=$RC out='$OUT'"; fi

t="same file again -> silent (one-shot per file)"
OUT="$(run "$(payload Edit "$PROJ/c.ts")")"
[ -z "$OUT" ] && ok "$t" || nope "$t" "out='$OUT'"

t="a different long file still fires"
mkfile "$PROJ/d.ts" 900
OUT="$(run "$(payload Write "$PROJ/d.ts")")"
printf '%s' "$OUT" | grep -q 'd.ts' && ok "$t" || nope "$t" "out='$OUT'"

t="custom limit via AGENT_TEAM_MAX_FILE_LINES"
mkfile "$PROJ/e.ts" 120
OUT="$(printf '%s' "$(payload Write "$PROJ/e.ts")" | AGENT_TEAM_MAX_FILE_LINES=100 bash "$GUARD" 2>/dev/null)"
printf '%s' "$OUT" | grep -q 'e.ts' && ok "$t" || nope "$t" "out='$OUT'"

t="non-matching tool -> silent"
mkfile "$PROJ/f.ts" 2000
OUT="$(run "$(payload Read "$PROJ/f.ts")")"
[ -z "$OUT" ] && ok "$t" || nope "$t" "out='$OUT'"

t="missing file -> silent, exit 0"
OUT="$(run "$(payload Write "$PROJ/nope.ts")")"; RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

t="garbage payload -> silent, exit 0"
OUT="$(printf 'not json' | bash "$GUARD" 2>/dev/null)"; RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

t="AGENT_TEAM_SKIP_FILE_LENGTH_GUARD=1 -> silent"
mkfile "$PROJ/g.ts" 2000
OUT="$(printf '%s' "$(payload Write "$PROJ/g.ts")" | AGENT_TEAM_SKIP_FILE_LENGTH_GUARD=1 bash "$GUARD" 2>/dev/null)"
[ -z "$OUT" ] && ok "$t" || nope "$t" "out='$OUT'"

t="lockfile / generated-looking file -> silent"
mkfile "$PROJ/package-lock.json" 3000
OUT="$(run "$(payload Write "$PROJ/package-lock.json")")"
[ -z "$OUT" ] && ok "$t" || nope "$t" "out='$OUT'"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
