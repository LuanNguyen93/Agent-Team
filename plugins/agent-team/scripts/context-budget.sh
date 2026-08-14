#!/usr/bin/env bash
# UserPromptSubmit hook: say how large the context has become, once it is large
# enough to be the dominant cost of the session.
#
# A context is not paid for once. It is re-read on every request that follows
# it, so the cost of a session is roughly context size x number of turns. Past
# a certain size, most of what each turn pays for is material it is not using.
#
# Measured on this repository: 53% of all spend was re-reading existing context,
# and the single most expensive session ran 414 turns against a context that
# grew to 729k without ever compacting.
#
# This hook never blocks. It exits 0 always, and only writes to stdout - which
# UserPromptSubmit passes to the model as additional context - when the number
# is worth acting on. Opt out for a session with AGENT_TEAM_SKIP_CONTEXT_GUARD=1.

set -uo pipefail

[ "${AGENT_TEAM_SKIP_CONTEXT_GUARD:-}" = "1" ] && exit 0

PAYLOAD="$(cat)"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null 2>&1 || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
SIZE="$(printf '%s' "$PAYLOAD" | node "$DIR/context-size.js" --project-dir "$ROOT" 2>/dev/null)"

# Anything unreadable reports 0. Silence is the right answer to "I don't know".
case "$SIZE" in ''|*[!0-9]*) exit 0 ;; esac

LIMIT="${AGENT_TEAM_CONTEXT_LIMIT:-150000}"
[ "$SIZE" -lt "$LIMIT" ] && exit 0

SIZE_K=$(( SIZE / 1000 ))
LIMIT_K=$(( LIMIT / 1000 ))

# Past twice the limit the advice stops being a suggestion.
if [ "$SIZE" -ge $(( LIMIT * 2 )) ]; then
  cat <<EOF
Context is now ~${SIZE_K}k tokens, more than twice the ${LIMIT_K}k working limit.
Every further turn re-reads all of it, so the rest of this session is being
billed mostly for material it is not using.

Compact or hand off before continuing. Follow the checklist in the
\`context-discipline\` skill (section 4) so the constraints survive: scope, the
dependency rule, the real gate commands, and what is still unverified.

If the remaining work is wide - a search, a file crawl, a noisy test run - run
it in a subagent instead and keep only what it returns.
EOF
else
  cat <<EOF
Context is ~${SIZE_K}k tokens, past the ${LIMIT_K}k working limit. From here on,
each turn pays to re-read all of it.

Consider compacting, or folding the next wide sub-task into a subagent so its
intermediate material does not land here. See \`context-discipline\`.
EOF
fi

exit 0
