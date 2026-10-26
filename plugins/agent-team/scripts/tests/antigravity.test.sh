#!/usr/bin/env bash
# Tests for the Antigravity edition
#
#   build-antigravity.sh  derives the Antigravity plugin from the Claude Code
#                         sources - manifest, hooks.json, converted agents.
#   *.sh hooks            the Antigravity side of session-routing,
#                         commit-attribution-guard and file-length-guard:
#                         camelCase payload in, JSON answer out, no node.
#
# Runs without node on purpose: Antigravity's shell often has none, and the
# hooks must not need it there.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$SCRIPT_DIR/../build-antigravity.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"

DEST="$TMP/plugins/agent-team"
WS="$TMP/ws"
mkdir -p "$WS"

echo "build-antigravity.sh"

t="builds into an empty destination"
OUT="$(bash "$BUILD" "$DEST" 2>&1)"; RC=$?
[ $RC -eq 0 ] && [ -f "$DEST/plugin.json" ] && [ -f "$DEST/hooks.json" ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

t="refuses a destination it did not build"
mkdir -p "$TMP/foreign"
OUT="$(bash "$BUILD" "$TMP/foreign" 2>&1)"; RC=$?
[ $RC -ne 0 ] && ok "$t" || nope "$t" "rc=$RC"

t="rebuilds over its own output"
OUT="$(bash "$BUILD" "$DEST" 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC out='$OUT'"

t="manifest carries only fields Antigravity reads"
grep -q '"author"\|"keywords"\|"license"' "$DEST/plugin.json" && nope "$t" "$(cat "$DEST/plugin.json")" || ok "$t"

t="hook commands go through bash, relative to the plugin root"
BAD="$(grep '"command"' "$DEST/hooks.json" | grep -v '"bash \./scripts/')"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

t="no agent keeps a Claude-only key or a bare skill name"
BAD="$(grep -l -E '^(skills|disallowedTools|color):|^model: (sonnet|opus|haiku)' "$DEST"/agents/*.md)"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

t="every agent declares tools"
BAD=""
for f in "$DEST"/agents/*.md; do grep -q '^tools:' "$f" || BAD="$BAD $f"; done
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

t="read-only agents get no write tools"
BAD="$(grep -l -E '^  - (write_file|edit_file)$' "$DEST/agents/reviewer.md" "$DEST/agents/planner.md" "$DEST/agents/router.md")"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

t="implementer can write and run commands"
grep -q '^  - edit_file$' "$DEST/agents/implementer.md" && grep -q '^  - run_command$' "$DEST/agents/implementer.md" && ok "$t" || nope "$t" "$(sed -n '1,14p' "$DEST/agents/implementer.md")"

t="model tiers map haiku->flash, opus->pro"
grep -q '^model: flash$' "$DEST/agents/router.md" && grep -q '^model: pro$' "$DEST/agents/architect.md" && ok "$t" || nope "$t" "router/architect model wrong"

t="skills are listed as absolute SKILL.md paths that exist"
BAD=""
for p in $(grep -h -o "\`$DEST/skills/[^\`]*SKILL.md\`" "$DEST"/agents/*.md | tr -d '\`'); do [ -f "$p" ] || BAD="$BAD $p"; done
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

t="no unresolved CLAUDE_PLUGIN_ROOT in skills or agents"
BAD="$(grep -rl 'CLAUDE_PLUGIN_ROOT' "$DEST/skills" "$DEST/agents")"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

t="commands ship as skills, with no commands/ folder"
BAD=""
for c in build pr ship spec stack-init; do
  grep -q "^name: $c$" "$DEST/skills/$c/SKILL.md" 2>/dev/null || BAD="$BAD $c"
done
[ -d "$DEST/commands" ] && BAD="$BAD commands/"
grep -l -E 'ARGUMENTS|^argument-hint:' "$DEST"/skills/*/SKILL.md >/dev/null 2>&1 && BAD="$BAD leftover-arguments"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

t="shipped scripts are executable"
BAD=""
for f in "$DEST"/scripts/*.sh; do [ -x "$f" ] || BAD="$BAD $f"; done
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

echo
echo "hooks, Antigravity payload"

COMMON="\"conversationId\":\"conv-1\",\"workspacePaths\":[\"$WS\"],\"modelName\":\"auto\""
hook() { # script payload - runs like Antigravity: sh -c, cwd = plugin root
  (cd "$DEST" && printf '%s' "$2" | sh -c "bash ./scripts/$1" 2>/dev/null)
}
cmd_payload() {
  printf '{%s,"toolCall":{"name":"run_command","args":{"CommandLine":"%s"}}}' "$COMMON" "$1"
}

t="session-routing injects a system message"
OUT="$(hook session-routing.sh "{$COMMON}")"
case "$OUT" in '{"injectSteps":[{"systemMessage":{"systemMessage":"The agent-team plugin is active.'*) ok "$t" ;; *) nope "$t" "out='$OUT'" ;; esac

t="session-routing reads .agent-team.json from the workspace, not the cwd"
echo '{"ui": false}' > "$WS/.agent-team.json"
OUT="$(hook session-routing.sh "{$COMMON}")"
case "$OUT" in *"no UI surface"*) ok "$t" ;; *) nope "$t" "out='$OUT'" ;; esac
rm -f "$WS/.agent-team.json"

t="attribution guard: ordinary command -> {} (never allow)"
OUT="$(hook commit-attribution-guard.sh "$(cmd_payload 'git status')")"
[ "$OUT" = "{}" ] && ok "$t" || nope "$t" "out='$OUT'"

t="attribution guard: clean commit -> {}"
OUT="$(hook commit-attribution-guard.sh "$(cmd_payload 'git commit -m \"fix: x\"')")"
[ "$OUT" = "{}" ] && ok "$t" || nope "$t" "out='$OUT'"

t="attribution guard: AI trailer -> deny"
OUT="$(hook commit-attribution-guard.sh "$(cmd_payload 'git commit -m \"fix: x\\n\\nCo-Authored-By: Claude <noreply@anthropic.com>\"')")"
case "$OUT" in '{"decision":"deny","reason":"Blocked:'*) ok "$t" ;; *) nope "$t" "out='$OUT'" ;; esac

t="attribution guard: escaped robot badge -> deny"
OUT="$(hook commit-attribution-guard.sh "$(cmd_payload 'gh pr create --body \"🤖 done\"')")"
case "$OUT" in *'"decision":"deny"'*'robot badge'*) ok "$t" ;; *) nope "$t" "out='$OUT'" ;; esac

t="attribution guard: opt-out -> {}"
OUT="$(cd "$DEST" && printf '%s' "$(cmd_payload 'git commit -m \"Co-Authored-By: Claude\"')" | AGENT_TEAM_ALLOW_ATTRIBUTION=1 sh -c 'bash ./scripts/commit-attribution-guard.sh')"
[ "$OUT" = "{}" ] && ok "$t" || nope "$t" "out='$OUT'"

i=1; : > "$WS/big.ts"; while [ $i -le 820 ]; do echo "line $i" >> "$WS/big.ts"; i=$((i+1)); done
edit_payload() { printf '{%s,"toolCall":{"name":"edit_file","args":{"Path":"%s","Target":"a","Replacement":"b"}}}' "$COMMON" "$1"; }
invoke_payload() { printf '{%s,"invocationNum":%s,"initialNumSteps":3}' "$COMMON" "$1"; }

t="file-length guard: PostToolUse always answers {}"
OUT="$(hook file-length-guard.sh "$(edit_payload "$WS/big.ts")")"
[ "$OUT" = "{}" ] && ok "$t" || nope "$t" "out='$OUT'"

t="file-length guard: next PreInvocation delivers the note"
OUT="$(hook file-length-guard.sh "$(invoke_payload 1)")"
case "$OUT" in '{"injectSteps":[{"ephemeralMessage":"File length: '*'820 lines'*) ok "$t" ;; *) nope "$t" "out='$OUT'" ;; esac

t="file-length guard: the note is delivered once"
OUT="$(hook file-length-guard.sh "$(invoke_payload 2)")"
[ "$OUT" = "{}" ] && ok "$t" || nope "$t" "out='$OUT'"

t="file-length guard: once per file per conversation"
hook file-length-guard.sh "$(edit_payload "$WS/big.ts")" >/dev/null
OUT="$(hook file-length-guard.sh "$(invoke_payload 3)")"
[ "$OUT" = "{}" ] && ok "$t" || nope "$t" "out='$OUT'"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
