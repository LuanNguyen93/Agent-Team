#!/usr/bin/env bash
# PreToolUse hook: refuse, once, to pull a large payload into a main context
# that is already large.
#
# Two tools do almost all of this damage, both measured on this repository's own
# transcripts:
#
#   Skill     - one load put 234k tokens into a single turn, taking the context
#               from 317k to 707k. Cost per turn went $0.49 -> $1.55 and stayed
#               there for the remaining 65 turns: about $69 from one tool call.
#
#   WebFetch  - 227k tokens across 16 calls in that same session, 36% of
#               everything that filled it. The first eight cost 20-25k each. A
#               single WebFetch is worth roughly a hundred Bash calls, and it is
#               never reclaimed: a page fetched at turn 50 is still being
#               re-read at turn 400.
#
# Read in a subagent, the same payload costs the same once and nothing
# afterwards, because that context is discarded.
#
# Exit 2 blocks the call and returns stderr to the agent as feedback. It blocks
# each target only ONCE per transcript: if the agent decides it really does need
# this here, the second attempt goes through. A hook the agent cannot get past
# is a hook that gets disabled.
#
# Opt out for a session with AGENT_TEAM_SKIP_CONTEXT_GUARD=1.

set -uo pipefail

[ "${AGENT_TEAM_SKIP_CONTEXT_GUARD:-}" = "1" ] && exit 0

PAYLOAD="$(cat)"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null 2>&1 || exit 0

# Pull the fields out in one pass. Anything unparseable prints nothing, and
# every branch below then falls through to exit 0 - a hook that cannot read its
# payload must not take the turn with it.
FIELDS="$(printf '%s' "$PAYLOAD" | node -e '
let s="";
process.stdin.on("data", (d) => s += d).on("end", () => {
  try {
    const p = JSON.parse(s);
    const i = p.tool_input || {};
    // The thing being pulled in: a skill by name, a page by URL.
    const target = i.skill || i.name || i.url || "";
    console.log([p.tool_name || "", target, p.transcript_path || ""].join("\n"));
  } catch (e) { /* fail open */ }
});' 2>/dev/null)"

TOOL="$(printf '%s' "$FIELDS" | sed -n '1p')"
TARGET="$(printf '%s' "$FIELDS" | sed -n '2p')"
TRANSCRIPT="$(printf '%s' "$FIELDS" | sed -n '3p')"

case "$TOOL" in
  Skill|WebFetch) ;;
  *) exit 0 ;;
esac
[ -n "$TARGET" ] || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
SIZE="$(printf '%s' "$PAYLOAD" | node "$DIR/context-size.js" --project-dir "$ROOT" 2>/dev/null)"
case "$SIZE" in ''|*[!0-9]*) exit 0 ;; esac

LIMIT="${AGENT_TEAM_CONTEXT_LIMIT:-150000}"
[ "$SIZE" -lt "$LIMIT" ] && exit 0

# The stamp lives in .git, not the working tree: nothing to gitignore, nothing
# for a `git status` to trip over. Same convention as run-gates.sh.
stamp_file() {
  local gitdir
  gitdir="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir="$ROOT/.git"
  [ -d "$gitdir" ] || return 1
  mkdir -p "$gitdir/agent-team" 2>/dev/null || return 1
  printf '%s/agent-team/context-guard-stamp' "$gitdir"
}

# Keyed by transcript, tool and target: per session, per tool, per thing. The
# tool belongs in the key because a skill and a URL can read the same, and
# warning about one must not silently spend the other's allowance.
KEY="$(basename "${TRANSCRIPT:-unknown}") $TOOL $TARGET"
STAMP="$(stamp_file)" || STAMP=""

if [ -n "$STAMP" ] && [ -f "$STAMP" ] && grep -Fxq "$KEY" "$STAMP" 2>/dev/null; then
  exit 0    # already said this once; the agent has decided
fi
[ -n "$STAMP" ] && printf '%s\n' "$KEY" >> "$STAMP" 2>/dev/null

SIZE_K=$(( SIZE / 1000 ))
LIMIT_K=$(( LIMIT / 1000 ))

if [ "$TOOL" = "Skill" ]; then
  {
    echo "Context is already ~${SIZE_K}k tokens, past the ${LIMIT_K}k limit, and loading"
    echo "\`$TARGET\` here adds its full text to every remaining turn of this session."
    echo
    echo "Read it in a subagent instead and keep only what it returns - the tokens die"
    echo "with that context rather than being re-read for the rest of the session. This"
    echo "is the fold described in \`context-discipline\` section 2."
    echo
    echo "If you genuinely need the doctrine in this context, ask again and it will go"
    echo "through - this fires once per skill."
  } >&2
else
  {
    echo "Context is already ~${SIZE_K}k tokens, past the ${LIMIT_K}k limit, and a fetch"
    echo "of"
    echo "  $TARGET"
    echo "lands its whole page here and is re-read on every turn that follows."
    echo
    echo "Measured on this repository: WebFetch averaged ~14k tokens per call and was"
    echo "36% of everything that filled the most expensive session. Nothing reclaims it."
    echo
    echo "Fetch it in a subagent and have that subagent return the answer, not the page."
    echo "If you need the page itself in this context, ask again - this fires once per URL."
  } >&2
fi

exit 2
