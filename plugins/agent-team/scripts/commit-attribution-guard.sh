#!/usr/bin/env bash
# PreToolUse hook on Bash (Claude Code) and run_command (Antigravity): block a
# git commit, git tag or PR-creating command whose message carries tool
# attribution - a `Co-Authored-By` trailer naming an AI or its vendor, a
# "generated with" line, or a robot badge.
#
# Doctrine lives in skills/quality-gates/SKILL.md ("Atomic commits"). Prose was
# not enough: the harness adds the trailer by default at message-composition
# time, and any commit made outside /ship never reads that skill. This hook is
# the enforcement that reaches every context, main or subagent, at the moment
# the command is about to run.
#
# Claude Code: blocks with exit 2 (docs/HARNESS-NOTES.md section 4) so the
# agent sees the reason and re-issues the command without the trailer.
# Antigravity: answers {"decision":"deny"} to block and {} otherwise. Never
# "allow" - that would auto-approve every command and skip the user's own
# permission prompt.
#
# Fails open on: a non-shell tool, no node (Claude side), an unparseable
# payload, or a command that is not a commit/tag/PR.
#
# The doctrine is a default, not a prohibition on what the user may want:
# AGENT_TEAM_ALLOW_ATTRIBUTION=1 opts out for a user who asks for the trailer.

set -uo pipefail

PAYLOAD="$(cat)"

. "$(dirname "$0")/agy-lib.sh"
AGY=0
agy_is_payload "$PAYLOAD" && AGY=1

pass() {
  [ "$AGY" = "1" ] && echo '{}'
  exit 0
}

[ "${AGENT_TEAM_ALLOW_ATTRIBUTION:-}" = "1" ] && pass

if [ "$AGY" = "1" ]; then
  # No node here. The matcher already limits this to run_command, and the
  # patterns below are distinctive enough to match against the raw payload:
  # JSON escaping leaves "git commit" and "co-authored-by:" intact.
  [ "$(agy_string_field "$PAYLOAD" name)" = "run_command" ] || pass
  CMD="$(agy_string_field "$PAYLOAD" CommandLine)"
  BADGE=""
  # The badge arrives either as raw UTF-8 or as a 🤖 escape.
  if printf '%s' "$PAYLOAD" | LC_ALL=C grep -q -i -e "$(printf '\360\237\244\226')" -e '\\ud83e\\udd16'; then
    BADGE="badge"
  fi
else
  command -v node >/dev/null 2>&1 || exit 0

  FIELDS="$(printf '%s' "$PAYLOAD" | node -e '
let s="";
process.stdin.on("data", (d) => s += d).on("end", () => {
  try {
    const p = JSON.parse(s);
    const cmd = (p.tool_input || {}).command || "";
    // Newlines are the field separator below, so flatten the command onto one
    // line. Attribution is matched case-insensitively on the flattened form.
    console.log(p.tool_name || "");
    console.log(cmd.replace(/[\r\n]+/g, " "));
    // Emoji detection happens here rather than in the shell: a shell pattern
    // holding the character itself depends on the locale the hook runs under,
    // and these hooks run on Git Bash too.
    console.log(/\u{1F916}/u.test(cmd) ? "badge" : "");
  } catch (e) { /* fail open */ }
});' 2>/dev/null)"

  TOOL="$(printf '%s' "$FIELDS" | sed -n '1p')"
  CMD="$(printf '%s' "$FIELDS" | sed -n '2p')"
  BADGE="$(printf '%s' "$FIELDS" | sed -n '3p')"

  [ "$TOOL" = "Bash" ] || exit 0
fi

[ -n "$CMD" ] || pass

# Only commands that write a message someone will read later.
case "$CMD" in
  *"git commit"*|*"git tag"*|*"gh pr create"*|*"gh pr edit"*|*"glab mr create"*|*"az repos pr create"*) ;;
  *) pass ;;
esac

LOWER="$(printf '%s' "$CMD" | tr '[:upper:]' '[:lower:]')"

FOUND=""
case "$LOWER" in
  *"co-authored-by:"*claude*|*"co-authored-by:"*anthropic*|*"co-authored-by:"*"noreply@anthropic"*)
    FOUND="a Co-Authored-By trailer naming an AI" ;;
  *"co-authored-by:"*gemini*|*"co-authored-by:"*antigravity*)
    FOUND="a Co-Authored-By trailer naming an AI" ;;
  *"generated with"*|*"co-authored-by:"*" ai "*|*"co-authored-by:"*copilot*|*"co-authored-by:"*cursor*)
    FOUND="a \"generated with\" line" ;;
esac

# The robot badge, flagged above.
if [ -z "$FOUND" ] && [ "$BADGE" = "badge" ]; then
  FOUND="a robot badge"
fi

[ -n "$FOUND" ] || pass

REASON="Blocked: this command's message carries $FOUND.

Re-issue it with the attribution removed. A commit's authorship line
says who is accountable for the change, and that is the person who
reviewed it and pressed the button, not the tool that typed it.
See skills/quality-gates/SKILL.md, \"Atomic commits\".

If the user explicitly asked for the attribution, set
AGENT_TEAM_ALLOW_ATTRIBUTION=1 for that command."

if [ "$AGY" = "1" ]; then
  printf '{"decision":"deny","reason":%s}\n' "$(agy_json_string "$REASON")"
  exit 0
fi

printf '%s\n' "$REASON" >&2
exit 2
