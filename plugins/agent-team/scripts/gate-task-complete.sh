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
  local status_out="$1" line path other saw_any=0

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local code="${line:0:2}"
    path="${line:3}"

    # An unmerged or conflicted path is never prose-only, whatever it is called.
    case "$code" in
      UU|AA|DD|AU|UA|DU|UD) return 1 ;;
    esac

    # A rename or copy has two sides, and BOTH have to be prose. Moving a module
    # into docs/ empties a source directory while looking like a doc change.
    other=""
    case "$path" in
      *" -> "*)
        other="${path%% -> *}"
        path="${path##* -> }"
        ;;
    esac

    saw_any=1
    is_prose "$path" || return 1
    if [ -n "$other" ]; then
      is_prose "$other" || return 1
    fi
  done <<EOF
$status_out
EOF

  [ "$saw_any" -eq 1 ]
}

# One path. Anything not recognised as prose returns false, which gates the
# change - the safe direction when this is wrong.
is_prose() {
  local path="$1"

  # git quotes a path containing a space, a backslash or a non-ASCII byte, and
  # C-escapes what is inside. Rather than decode that, gate it: an unusual path
  # is not worth a wrong skip.
  case "$path" in
    '"'*) return 1 ;;
  esac

  # git reports a new untracked directory as `dir/` without listing what is in
  # it, so the name says nothing about the contents.
  case "$path" in
    */) return 1 ;;
  esac

  # A manifest or lockfile is the one input the dependency audit exists for, and
  # several of them end in .txt.
  case "$path" in
    requirements*.txt|constraints*.txt|CMakeLists.txt) return 1 ;;
    */requirements*.txt|*/constraints*.txt|*/CMakeLists.txt) return 1 ;;
  esac

  case "$path" in
    *.md|*.mdx|*.markdown|*.txt|*.rst|*.adoc) return 0 ;;
    docs/*|doc/*|*/docs/*|*/doc/*) return 0 ;;
    LICENSE|LICENSE.*|NOTICE|NOTICE.*|AUTHORS|CHANGELOG|CHANGELOG.*) return 0 ;;
  esac
  return 1
}

# Not a git repo, or git unavailable: fall through and run the gates.
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  STATUS_OUT="$(git -C "$ROOT" status --porcelain 2>/dev/null)"

  # Nothing changed: nothing to gate.
  [ -z "$STATUS_OUT" ] && exit 0

  if [ "${AGENT_TEAM_ALWAYS_GATE:-}" != "1" ] && docs_only_change "$STATUS_OUT"; then
    DOCS_ONLY=1
  fi
fi

# A prose-only change skips the gates that have nothing to say about prose, but
# NOT the secret scan: a credential pasted into a README example is one of the
# commonest ways one gets committed, and that change is doc-only by definition.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${DOCS_ONLY:-0}" = "1" ]; then
  OUTPUT=$(AGENT_TEAM_SECRET_SCAN_ONLY=1 "$DIR/run-gates.sh" 2>&1)
else
  OUTPUT=$("$DIR/run-gates.sh" 2>&1)
fi
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
