#!/usr/bin/env bash
# Shared helpers for the Antigravity side of the hook scripts. Source it; do
# not run it.
#
# Antigravity hooks differ from Claude Code hooks in three ways that matter
# here (see docs/HARNESS-NOTES.md, "Antigravity hooks"):
#   - the payload is camelCase protojson ({conversationId, toolCall: {name,
#     args}, workspacePaths}), not {session_id, tool_name, tool_input};
#   - every handler must answer with a JSON object on stdout, and blocking is a
#     {"decision": "deny"} answer, not exit 2;
#   - the working directory is the plugin root, not the project.
#
# The shell Antigravity runs hooks in often has no node on PATH, so nothing
# here uses node. The parsing is plain text matching, which is enough for the
# few string fields the hooks read.

# True when the payload came from Antigravity. Claude Code never sends
# conversationId.
agy_is_payload() {
  case "$1" in
    *'"conversationId"'*) return 0 ;;
  esac
  return 1
}

# The first string value of key $2 anywhere in JSON $1, with \\ and \/
# unescaped. Good enough for paths and ids; not a JSON parser.
agy_string_field() {
  printf '%s' "$1" | tr -d '\r\n' \
    | sed -n -E "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\".*/\\1/p" \
    | head -n 1 | sed -e 's#\\/#/#g' -e 's#\\\\#\\#g'
}

# The first entry of workspacePaths - the project root, since the hook's own
# working directory is the plugin.
agy_workspace() {
  printf '%s' "$1" | tr -d '\r\n' \
    | sed -n -E 's/.*"workspacePaths"[[:space:]]*:[[:space:]]*\[[[:space:]]*"([^"]*)".*/\1/p' \
    | head -n 1
}

# $1 as a JSON string literal, quotes included.
agy_json_string() {
  printf '"'
  printf '%s' "$1" | awk 'BEGIN { ORS = "" } {
    gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "")
    if (NR > 1) print "\\n"
    print
  }'
  printf '"'
}

# Per-conversation scratch space for stamps and pending notes. Kept out of the
# project so a hook never writes into the user's tree.
agy_state_dir() {
  local dir="${TMPDIR:-/tmp}"
  dir="${dir%/}/agent-team-agy"
  mkdir -p "$dir" 2>/dev/null || return 1
  printf '%s' "$dir"
}
