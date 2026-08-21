#!/usr/bin/env bash
# Tests for the SAST gate in run-gates.sh
#
#   Runs semgrep over the working tree when it is on PATH. ABSENT (not pass,
#   not fail) when it is missing or cannot reach its rules; FAILED on findings;
#   AGENT_TEAM_SKIP_SAST=1 opts out. Stack-independent, like the secret scan.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATES="$SCRIPT_DIR/../run-gates.sh"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"
trap 'rm -rf "$TMP"' EXIT
PROJ="$TMP/proj"; BIN="$TMP/bin"; mkdir -p "$PROJ" "$BIN"
git -C "$PROJ" init -q
# No other tools: an empty PATH apart from coreutils + our fake semgrep.
export AGENT_TEAM_SKIP_SECRET_SCAN=1 AGENT_TEAM_SKIP_AUDIT=1
run() { (cd "$PROJ" && CLAUDE_PROJECT_DIR="$PROJ" PATH="$BIN:$PATH" bash "$GATES" 2>&1); }
fake() { # mode
  cat > "$BIN/semgrep" <<EOS
#!/usr/bin/env bash
echo "\$@" > "$TMP/semgrep-args"
case "$1" in
  clean)   exit 0 ;;
  finding) echo "src/a.js:3: javascript.lang.security.audit.eval"; exit 1 ;;
  offline) echo "Failed to download config from https://semgrep.dev: ENOTFOUND"; exit 2 ;;
esac
EOS
  chmod +x "$BIN/semgrep"
}

echo "SAST gate"

t="no semgrep on PATH -> ABSENT, exit 0"
rm -f "$BIN/semgrep"
OUT="$(PATH="$BIN" run)"; RC=$?
# PATH="$BIN" would lose bash itself on some systems; fall back to hiding semgrep only.
OUT="$(run)"; RC=$?
if command -v semgrep >/dev/null 2>&1; then echo "  skip (real semgrep on PATH)"; else
  [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q 'Gate ABSENT: SAST' && ok "$t" || nope "$t" "rc=$RC out='$OUT'"; fi

t="semgrep clean -> exit 0, no ABSENT/FAILED line"
fake clean; OUT="$(run)"; RC=$?
[ $RC -eq 0 ] && ! printf '%s' "$OUT" | grep -qE 'ABSENT: SAST|FAILED: SAST' && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

t="semgrep invoked with --error and a config"
grep -q -- '--error' "$TMP/semgrep-args" && grep -q -- '--config' "$TMP/semgrep-args" && ok "$t" || nope "$t" "args='$(cat "$TMP/semgrep-args")'"

t="project .semgrep.yml wins over auto"
: > "$PROJ/.semgrep.yml"; run >/dev/null
grep -q -- '--config .semgrep.yml' "$TMP/semgrep-args" && ok "$t" || nope "$t" "args='$(cat "$TMP/semgrep-args")'"
rm -f "$PROJ/.semgrep.yml"

t="findings -> Gate FAILED: SAST, exit 1, finding shown"
fake finding; OUT="$(run)"; RC=$?
[ $RC -eq 1 ] && printf '%s' "$OUT" | grep -q 'Gate FAILED: SAST' && printf '%s' "$OUT" | grep -q 'audit.eval' && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

t="rules unreachable -> ABSENT, exit 0"
fake offline; OUT="$(run)"; RC=$?
[ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q 'ABSENT' && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

t="AGENT_TEAM_SKIP_SAST=1 -> SKIPPED"
fake finding; OUT="$(AGENT_TEAM_SKIP_SAST=1 run)"; RC=$?
[ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q 'SKIPPED: SAST' && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

t="prose-only run (SECRET_SCAN_ONLY) does not run SAST"
fake finding; OUT="$(AGENT_TEAM_SECRET_SCAN_ONLY=1 run)"; RC=$?
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

echo; echo "passed: $PASS  failed: $FAIL"; [ "$FAIL" -eq 0 ]
