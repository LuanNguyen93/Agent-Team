#!/usr/bin/env bash
# Tests for commit-attribution-guard.sh
#
#   commit-attribution-guard.sh  PreToolUse on Bash - blocks a git commit, git
#                                tag or PR-creating command whose message
#                                carries tool attribution. Exit 2 blocks;
#                                exit 0 lets the command through.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/../commit-attribution-guard.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - skipping commit attribution guard tests"
  exit 0
fi

# expect <exit> <label> <command-string> [tool]
expect() {
  local want="$1" label="$2" cmd="$3" tool="${4:-Bash}" got payload
  payload="$(TOOL="$tool" CMD="$cmd" node -e '
    process.stdout.write(JSON.stringify({
      tool_name: process.env.TOOL,
      tool_input: { command: process.env.CMD },
    }));')"
  printf '%s' "$payload" | bash "$GUARD" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then ok "$label"; else nope "$label" "expected exit $want, got $got"; fi
}

echo "commit-attribution-guard:"

expect 2 "blocks a Co-Authored-By trailer naming Claude" \
  'git commit -m "feat: x

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"'

expect 2 "blocks a trailer naming the vendor address only" \
  'git commit -m "fix: y

co-authored-by: someone <bot@noreply@anthropic.com>"'

expect 2 "blocks a generated-with line in a PR body" \
  'gh pr create --body "what changed

Generated with Claude Code"'

expect 2 "blocks a robot badge" \
  'git tag -a v1.0.0 -m "release 🤖"'

expect 0 "lets a clean commit through" \
  'git commit -m "feat: x

why this changed, not how"'

expect 0 "lets a human co-author through" \
  'git commit -m "feat: x

Co-Authored-By: Luan Nguyen <theluannguyen93@gmail.com>"'

expect 0 "ignores a command that only reads history" \
  'git log --format=%B | grep -c Co-Authored-By'

expect 0 "ignores an unrelated command" 'npm test'

expect 0 "ignores a non-Bash tool" \
  'git commit -m "Co-Authored-By: Claude"' 'Edit'

# The opt-out: a user who explicitly asks for attribution gets it.
OPTOUT="$(TOOL=Bash CMD='git commit -m "x

Co-Authored-By: Claude <noreply@anthropic.com>"' node -e '
  process.stdout.write(JSON.stringify({
    tool_name: process.env.TOOL,
    tool_input: { command: process.env.CMD },
  }));')"
printf '%s' "$OPTOUT" | AGENT_TEAM_ALLOW_ATTRIBUTION=1 bash "$GUARD" >/dev/null 2>&1
if [ $? = 0 ]; then ok "AGENT_TEAM_ALLOW_ATTRIBUTION=1 stands aside"; else nope "AGENT_TEAM_ALLOW_ATTRIBUTION=1 stands aside" "expected exit 0"; fi

# Fails open rather than blocking work on a payload it cannot read.
printf 'not json' | bash "$GUARD" >/dev/null 2>&1
if [ $? = 0 ]; then ok "fails open on an unparseable payload"; else nope "fails open on an unparseable payload" "expected exit 0"; fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
