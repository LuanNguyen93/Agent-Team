#!/usr/bin/env bash
# Build the Antigravity edition of this plugin and install it.
#
#   bash scripts/build-antigravity.sh [--force] [DEST]
#
# DEST defaults to ~/.gemini/config/plugins/agent-team. Restart Antigravity
# afterwards - a new plugin directory is only discovered at startup.
#
# Why a build and not the source tree: Antigravity reads the same folder names
# (agents/, skills/, hooks.json) with different contents. Pointed at this tree
# it loads Claude Code agent frontmatter it does not understand - no `tools`
# list, so every subagent comes up read-only; `skills:` names resolved as
# paths, which fails inside a plugin; `model: sonnet`, which is not a tier
# there. The Claude Code files stay the single source; this script derives the
# Antigravity ones from them. See docs/HARNESS-NOTES.md, "Antigravity".
#
# DEST is replaced wholesale. A DEST this script did not build is left alone
# unless --force is given.

set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FORCE=0
DEST=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 1 ;;
    *) DEST="$arg" ;;
  esac
done
DEST="${DEST:-$HOME/.gemini/config/plugins/agent-team}"
MARKER=".agent-team-build"

if [ -e "$DEST" ] && [ ! -f "$DEST/$MARKER" ] && [ "$FORCE" != "1" ]; then
  echo "refusing to replace $DEST: it was not built by this script." >&2
  echo "Move it out of ~/.gemini/config/plugins/ (not beside it - Antigravity would" >&2
  echo "load the copy too), or re-run with --force." >&2
  exit 1
fi

json_field() { # first "key": "value" in a flat JSON file
  sed -n -E "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\\1/p" "$2" | head -n 1
}

MANIFEST="$SRC/.claude-plugin/plugin.json"
VERSION="$(json_field version "$MANIFEST")"
DESCRIPTION="$(json_field description "$MANIFEST")"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/agent-team-agy.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
OUT="$STAGE/agent-team"
mkdir -p "$OUT/agents"

# --- content shared verbatim --------------------------------------------------
for dir in skills stacks workflows; do
  [ -d "$SRC/$dir" ] && cp -R "$SRC/$dir" "$OUT/$dir"
done

# Antigravity plugins have no commands; a skill is the slash-invocable unit
# there, so each command becomes skills/<name>/SKILL.md. argument-hint has no
# equivalent, and $ARGUMENTS becomes a pointer to the user's own words.
for f in "$SRC"/commands/*.md; do
  [ -f "$f" ] || continue
  cmd="$(basename "$f" .md)"
  if [ -e "$OUT/skills/$cmd" ]; then
    echo "command $cmd collides with skill $cmd" >&2
    exit 1
  fi
  mkdir -p "$OUT/skills/$cmd"
  awk -v name="$cmd" '
    NR == 1 && $0 == "---" { print; print "name: " name; fm = 1; next }
    fm && $0 == "---" { fm = 0; print; next }
    fm && /^argument-hint:/ { next }
    { gsub(/\$ARGUMENTS/, "the text the user typed after the command"); print }
  ' "$f" > "$OUT/skills/$cmd/SKILL.md"
done
mkdir -p "$OUT/scripts"
for f in "$SRC"/scripts/*; do
  [ -f "$f" ] && cp "$f" "$OUT/scripts/"
done
chmod +x "$OUT"/scripts/*.sh

# Skills, converted commands among them, call scripts through
# ${CLAUDE_PLUGIN_ROOT}, which Antigravity never sets. Bake in the install path.
find "$OUT/skills" -name '*.md' -type f | while IFS= read -r f; do
  if grep -q 'CLAUDE_PLUGIN_ROOT' "$f"; then
    sed -e "s#\${CLAUDE_PLUGIN_ROOT}#$DEST#g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
done

# --- manifest -----------------------------------------------------------------
# Antigravity's loader drops unknown top-level fields; send only the ones it
# reads. `name` must match the install folder.
cat > "$OUT/plugin.json" <<EOF
{
  "name": "agent-team",
  "displayName": "Agent Team",
  "version": "$VERSION",
  "description": "$DESCRIPTION"
}
EOF

# --- hooks --------------------------------------------------------------------
# Commands run via `sh -c` with the plugin root as working directory. Call bash
# explicitly so a lost executable bit cannot disable a hook. Only the hooks
# that understand Antigravity's payload are registered; the rest read Claude
# Code fields and would fail open on every call.
cat > "$OUT/hooks.json" <<'EOF'
{
  "agent-team": {
    "SessionStart": [
      { "type": "command", "command": "bash ./scripts/session-routing.sh", "timeout": 10 }
    ],
    "PreToolUse": [
      {
        "matcher": "run_command",
        "hooks": [
          { "type": "command", "command": "bash ./scripts/commit-attribution-guard.sh", "timeout": 10 }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "edit_file|write_file|write_to_file|replace_file_content|multi_replace_file_content",
        "hooks": [
          { "type": "command", "command": "bash ./scripts/file-length-guard.sh", "timeout": 10 }
        ]
      }
    ],
    "PreInvocation": [
      { "type": "command", "command": "bash ./scripts/file-length-guard.sh", "timeout": 10 }
    ]
  }
}
EOF

# --- agents -------------------------------------------------------------------
# Tool names are the Antigravity CLI's own. An unknown name can hang the
# subagent, so add one only after seeing it in a real tool call.
READ_TOOLS="view_file run_command search_web"
WRITE_TOOLS="$READ_TOOLS write_file edit_file"

convert_agent() {
  local src="$1" dst="$2"
  local fm body name description model disallowed skills tools tier

  fm="$(awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside { print }' "$src")"
  body="$(awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { inside = 0; done = 1; next } done { print }' "$src")"

  name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p')"
  description="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p')"
  model="$(printf '%s\n' "$fm" | sed -n 's/^model:[[:space:]]*//p')"
  disallowed="$(printf '%s\n' "$fm" | sed -n 's/^disallowedTools:[[:space:]]*//p')"
  skills="$(printf '%s\n' "$fm" | awk '/^skills:/ { on = 1; next } on && /^[[:space:]]*-/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); print; next } on { on = 0 }')"

  # CLAUDE.md "Model Allocation": haiku is System One, opus is deep reasoning,
  # sonnet is the session's own tier.
  case "$model" in
    haiku) tier="flash" ;;
    opus) tier="pro" ;;
    *) tier="inherit" ;;
  esac

  case "$disallowed" in
    *Edit*|*Write*) tools="$READ_TOOLS" ;;
    *) tools="$WRITE_TOOLS" ;;
  esac

  {
    echo "---"
    echo "name: $name"
    printf 'description: "%s"\n' "$(printf '%s' "$description" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    echo "model: $tier"
    echo "mainAgent: false"
    echo "subagent: true"
    echo "tools:"
    for t in $tools; do echo "  - $t"; done
    echo "---"
    echo
    echo "# System Prompt"
    echo
    echo "Antigravity note: there is no Skill tool here. Wherever this prompt says to"
    echo "load a skill, read its SKILL.md with view_file instead, and its"
    echo "\`references/\` files the same way when the SKILL.md points to them."
    if [ -n "$skills" ]; then
      echo "Your skills:"
      printf '%s\n' "$skills" | while IFS= read -r s; do
        [ -n "$s" ] && echo "- \`$DEST/skills/$s/SKILL.md\`"
      done
    fi
    echo "Claude Code tool names map as: Read -> view_file, Edit -> edit_file,"
    echo "Write -> write_file, Bash -> run_command, Agent/Task -> invoke_subagent."
    echo
    printf '%s\n' "$body" | sed -e "s#\${CLAUDE_PLUGIN_ROOT}#$DEST#g"
  } > "$dst"
}

for f in "$SRC"/agents/*.md; do
  convert_agent "$f" "$OUT/agents/$(basename "$f")"
done

printf 'built from %s version %s\n' "$SRC" "$VERSION" > "$OUT/$MARKER"

# --- install ------------------------------------------------------------------
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -R "$OUT" "$DEST"

echo "Installed agent-team $VERSION for Antigravity at $DEST"
echo "  agents: $(ls "$DEST/agents" | wc -l | tr -d ' ')  skills: $(ls "$DEST/skills" | wc -l | tr -d ' ')"
echo "Restart Antigravity to load it."
