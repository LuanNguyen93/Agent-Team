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
