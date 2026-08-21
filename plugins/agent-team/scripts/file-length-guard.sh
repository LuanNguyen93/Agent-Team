#!/usr/bin/env bash
# PostToolUse hook on Edit|Write|NotebookEdit: after a file is written, if it
# now exceeds AGENT_TEAM_MAX_FILE_LINES (default 800) lines, tell the writer
# once - per file, per session - to split it before moving on.
#
# Doctrine lives in skills/quality-gates/SKILL.md ("File length"); this hook is
# the reminder that reaches whichever context is doing the writing, main or
# subagent, at the moment the file crosses the line. It never blocks: a file
# mid-refactor may legitimately be long for one edit, and the reviewer holds
# the hard line.
#
# Emits the non-blocking PostToolUse JSON envelope (docs/HARNESS-NOTES.md
# section 16). Fails open on: non-matching tool, missing file, no node,
# unparseable payload, no .git, or an unwritable state dir. Skips files that
# are generated rather than written (lockfiles, minified bundles, snapshots).
#
# Opt out with AGENT_TEAM_SKIP_FILE_LENGTH_GUARD=1.

set -uo pipefail

[ "${AGENT_TEAM_SKIP_FILE_LENGTH_GUARD:-}" = "1" ] && exit 0

PAYLOAD="$(cat)"
command -v node >/dev/null 2>&1 || exit 0

FIELDS="$(printf '%s' "$PAYLOAD" | node -e '
let s="";
process.stdin.on("data", (d) => s += d).on("end", () => {
  try {
    const p = JSON.parse(s);
    const ti = p.tool_input || {};
    console.log([p.tool_name || "", ti.file_path || ti.notebook_path || "", p.session_id || "nosession"].join("\n"));
  } catch (e) { /* fail open */ }
});' 2>/dev/null)"

TOOL="$(printf '%s' "$FIELDS" | sed -n '1p')"
FILE="$(printf '%s' "$FIELDS" | sed -n '2p')"
SESSION="$(printf '%s' "$FIELDS" | sed -n '3p')"

case "$TOOL" in
  Edit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

BASE="$(basename "$FILE")"
case "$BASE" in
  package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|go.sum|poetry.lock|Gemfile.lock|composer.lock|*.min.js|*.min.css|*.snap|*.svg|*.json|*.lock|*.map) exit 0 ;;
esac

LINES="$(wc -l < "$FILE" 2>/dev/null | tr -d '[:space:]')"
case "$LINES" in ''|*[!0-9]*) exit 0 ;; esac

LIMIT="${AGENT_TEAM_MAX_FILE_LINES:-800}"
[ "$LINES" -le "$LIMIT" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
state_dir() {
  local gitdir
  gitdir="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir="$ROOT/.git"
  [ -d "$gitdir" ] || return 1
  mkdir -p "$gitdir/agent-team" 2>/dev/null || return 1
  printf '%s/agent-team' "$gitdir"
}
DIR_STATE="$(state_dir)" || exit 0

# One nudge per file per session. Key by a hash of the path so odd characters
# never reach the filesystem; cksum is POSIX, unlike md5sum/shasum.
KEY="$(printf '%s' "$FILE" | cksum | cut -d' ' -f1)"
STAMP="$DIR_STATE/file-length-stamp-$SESSION-$KEY"
[ -f "$STAMP" ] && exit 0
{ printf '' > "$STAMP"; } 2>/dev/null || exit 0

MESSAGE="File length: $FILE is now $LINES lines, over the $LIMIT-line limit
(quality-gates skill, \"File length\").

Split it before moving on - by responsibility, not by line count: extract the
cohesive cluster (a type family, a handler group, a helper set) into its own
module and import it. Do it inside the current red-green cycle so the suite
stays green. The reviewer blocks on files over the limit that the plan did not
explicitly exempt.

This fires once per file per session."

ENVELOPE="$(printf '%s' "$MESSAGE" | node -e '
let s="";
process.stdin.on("data", (d) => s += d).on("end", () => {
  const out = { hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: s } };
  process.stdout.write(JSON.stringify(out));
});' 2>/dev/null)"

[ -n "$ENVELOPE" ] && printf '%s' "$ENVELOPE"
exit 0
