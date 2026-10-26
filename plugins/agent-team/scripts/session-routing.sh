#!/usr/bin/env bash
# SessionStart hook: make the team the default path for build-shaped work.
#
# Without this, the plugin is inert until the user types /build - skills only
# load when the model judges them relevant, and nothing otherwise tells it to
# route. Claude Code adds SessionStart stdout to context; Antigravity wants the
# same text wrapped as an injected system message.
#
# Keep it SHORT. It costs context on every request of every session.
#
# Opt out with AGENT_TEAM_NO_AUTOROUTE=1.

set -uo pipefail

PAYLOAD="$(cat)"

. "$(dirname "$0")/agy-lib.sh"
AGY=0
agy_is_payload "$PAYLOAD" && AGY=1

if [ "${AGENT_TEAM_NO_AUTOROUTE:-}" = "1" ]; then
  [ "$AGY" = "1" ] && echo '{}'
  exit 0
fi

MSG='The agent-team plugin is active. For any request to build, change, fix, or
design software in this session:

- Load the `workflow-router` skill and route through it. Do not implement
  directly, and do not wait for the user to type /build.
- No code before a plan. On a small fix the plan may be one sentence, but state
  it first.
- Write the failing test before the implementation, and report the actual
  result. Never claim a gate passed that you did not run.
- Review runs on a fresh context via the `reviewer` agent - never the context
  that wrote the code.

Answer questions directly; this applies to build requests, not to explanations.'

# Tell the session when the owned scope has no UI, so it does not waste context
# considering UI-only agents and skills. Absent key means unknown, not "no UI" -
# only an explicit `false` triggers the hint. Keep it to one line; see the note
# above about cost per request.
if [ "$AGY" = "1" ]; then
  ROOT="$(agy_workspace "$PAYLOAD")"
else
  ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
fi
# Plain text match, not a JSON parser - works without node, which is often
# absent on the Go/Python/.NET projects this hint targets most. Only an
# explicit `false` matches; absent key, `true`, and malformed JSON all stay
# silent because none of them contain this literal.
if [ -n "$ROOT" ] && [ -f "$ROOT/.agent-team.json" ] && grep -Eq '"ui"[[:space:]]*:[[:space:]]*false' "$ROOT/.agent-team.json" 2>/dev/null; then
  MSG="$MSG
no UI surface in this project - ux-designer, frontend-implementer, design-intelligence, react-performance, browser-verify are not in play"
fi

if [ "$AGY" = "1" ]; then
  printf '{"injectSteps":[{"systemMessage":{"systemMessage":%s}}]}\n' "$(agy_json_string "$MSG")"
else
  printf '%s\n' "$MSG"
fi

exit 0
