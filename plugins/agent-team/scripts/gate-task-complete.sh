#!/usr/bin/env bash
# TaskCompleted hook: refuse to mark a task complete while quality gates fail.
#
# This is the enforcement half of the quality-gates skill. The skill tells the
# model to stop on a failing gate; this makes stopping mandatory.
#
# Exit 2 blocks the completion and sends stderr back to the agent as feedback.
# Opt out for a session with AGENT_TEAM_SKIP_GATES=1.

set -uo pipefail

cat > /dev/null   # drain the hook payload; the gates only need the project dir

[ "${AGENT_TEAM_SKIP_GATES:-}" = "1" ] && exit 0

# Gates only tell you something when code changed. A task that read files,
# answered a question, or wrote docs pays a full test run for no signal - on a
# large suite that is minutes of latency per task.
#
# Every path in the change is prose. A typecheck, a test suite and a network
# audit have nothing to say about a paragraph, so charging minutes for one is
# how a team learns to set AGENT_TEAM_SKIP_GATES=1 and lose the gates entirely.
#
# Deliberately conservative: ONE non-doc path in the change and the gates run in
# full. A change that touches a doc and a source file is a source change.
# AGENT_TEAM_ALWAYS_GATE=1 turns the shortcut off.
docs_only_change() {
  local status_out="$1" line path saw_any=0

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # porcelain v1: two status columns, a space, then the path.
    path="${line:3}"
    # A rename reports "old -> new"; the new path is the one that exists.
    case "$path" in *" -> "*) path="${path##* -> }" ;; esac
    # A path with a space or a non-ASCII byte arrives quoted.
    path="${path%\"}"
    path="${path#\"}"
    saw_any=1

    case "$path" in
      *.md|*.mdx|*.markdown|*.txt|*.rst|*.adoc) ;;
      docs/*|doc/*|*/docs/*|*/doc/*) ;;
      LICENSE|LICENSE.*|NOTICE|NOTICE.*|AUTHORS|CHANGELOG|CHANGELOG.*) ;;
      *) return 1 ;;
    esac
  done <<EOF
$status_out
EOF

  [ "$saw_any" -eq 1 ]
}

# Not a git repo, or git unavailable: fall through and run the gates.
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  STATUS_OUT="$(git -C "$ROOT" status --porcelain 2>/dev/null)"

  # Nothing changed: nothing to gate.
  [ -z "$STATUS_OUT" ] && exit 0

  if [ "${AGENT_TEAM_ALWAYS_GATE:-}" != "1" ] && docs_only_change "$STATUS_OUT"; then
    exit 0
  fi
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT=$("$DIR/run-gates.sh" 2>&1)
STATUS=$?

if [ $STATUS -ne 0 ]; then
  {
    echo "Quality gates are failing, so this task is not complete."
    echo
    echo "$OUTPUT"
    echo
    echo "Do not weaken assertions, add suppressions, or skip tests to clear this."
    echo "Route to the debugger agent for root-cause analysis, fix the mechanism,"
    echo "then mark the task complete."
  } >&2
  exit 2
fi

exit 0
