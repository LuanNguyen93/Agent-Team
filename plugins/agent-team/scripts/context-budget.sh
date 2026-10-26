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
# This hook never blocks. It exits 0 always. On UserPromptSubmit, plain stdout
# is what the harness passes to the model as additional context - the
# documented delivery for that event. Registered on PostToolUse too (for the
# per-tool-call cadence a long dispatch does not otherwise get a budget
# check on), where plain stdout is NOT delivered and the non-blocking channel
# is instead a JSON envelope on stdout with exit 0 - see
# docs/HARNESS-NOTES.md section 14. `hook_event_name` in the payload tells
# this script which contract applies; anything other than "PostToolUse" is
# treated as the UserPromptSubmit contract, since that is this hook's
# original registration and the field is not guaranteed present there.
#
# A call carrying agent_id is a subagent's own tool call - skipped outright,
# since subagent-guard.sh is what measures a subagent's own context.
#
# Past the limit, this fires once per 50k-token band rather than once ever:
# a session that grows from 150k to 700k without compacting should hear about
# it again as it keeps climbing, not just at the first crossing.
#
# Opt out for a session with AGENT_TEAM_SKIP_CONTEXT_GUARD=1.

set -uo pipefail

[ "${AGENT_TEAM_SKIP_CONTEXT_GUARD:-}" = "1" ] && exit 0

PAYLOAD="$(cat)"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null 2>&1 || exit 0

FIELDS="$(printf '%s' "$PAYLOAD" | node -e '
let s="";
process.stdin.on("data", (d) => s += d).on("end", () => {
  try {
    const p = JSON.parse(s);
    console.log([p.agent_id || "", p.hook_event_name || "", p.transcript_path || "unknown"].join("\n"));
  } catch (e) { /* fail open */ }
});' 2>/dev/null)"

AGENT_ID="$(printf '%s' "$FIELDS" | sed -n '1p')"
EVENT="$(printf '%s' "$FIELDS" | sed -n '2p')"
TRANSCRIPT="$(printf '%s' "$FIELDS" | sed -n '3p')"

# A subagent's own tool call: subagent-guard.sh is what measures this context.
[ -z "$AGENT_ID" ] || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
SIZE="$(printf '%s' "$PAYLOAD" | node "$DIR/context-size.js" --project-dir "$ROOT" 2>/dev/null)"

# Anything unreadable reports 0. Silence is the right answer to "I don't know".
case "$SIZE" in ''|*[!0-9]*) exit 0 ;; esac

LIMIT="${AGENT_TEAM_CONTEXT_LIMIT:-150000}"
[ "$SIZE" -lt "$LIMIT" ] && exit 0

# One-shot per 50k band, not per session: state lives in .git, not the working
# tree, same convention as the other guards in this family.
BAND_STEP=50000
BAND=$(( SIZE / BAND_STEP ))

state_dir() {
  local gitdir
  gitdir="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir="$ROOT/.git"
  [ -d "$gitdir" ] || return 1
  mkdir -p "$gitdir/agent-team" 2>/dev/null || return 1
  printf '%s/agent-team' "$gitdir"
}

if DIR_STATE="$(state_dir)"; then
  STAMP="$DIR_STATE/context-budget-band-$(basename "${TRANSCRIPT:-unknown}")"
  LAST_BAND=""
  [ -f "$STAMP" ] && LAST_BAND="$(cat "$STAMP" 2>/dev/null)"
  if [ "$LAST_BAND" = "$BAND" ]; then
    exit 0    # already spoke up for this band; the agent has decided
  fi
  { printf '%s' "$BAND" > "$STAMP"; } 2>/dev/null || true
fi

SIZE_K=$(( SIZE / 1000 ))
LIMIT_K=$(( LIMIT / 1000 ))

# Past twice the limit the advice stops being a suggestion.
if [ "$SIZE" -ge $(( LIMIT * 2 )) ]; then
  MESSAGE="Context is now ~${SIZE_K}k tokens, more than twice the ${LIMIT_K}k working limit.
Every further turn re-reads all of it, so the rest of this session is being
billed mostly for material it is not using.

Compact or hand off before continuing. Follow the checklist in the
\`context-discipline\` skill (section 4) so the constraints survive: scope, the
dependency rule, the real gate commands, and what is still unverified.

If the remaining work is wide - a search, a file crawl, a noisy test run - run
it in a subagent instead and keep only what it returns."
else
  MESSAGE="Context is ~${SIZE_K}k tokens, past the ${LIMIT_K}k working limit. From here on,
each turn pays to re-read all of it.

Consider compacting, or folding the next wide sub-task into a subagent so its
intermediate material does not land here. See \`context-discipline\`."
fi

if [ "$EVENT" = "PostToolUse" ]; then
  ENVELOPE="$(printf '%s' "$MESSAGE" | node -e '
let s="";
process.stdin.on("data", (d) => s += d).on("end", () => {
  const out = { hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: s } };
  process.stdout.write(JSON.stringify(out));
});' 2>/dev/null)"
  [ -n "$ENVELOPE" ] && printf '%s' "$ENVELOPE"
else
  printf '%s\n' "$MESSAGE"
fi

exit 0
