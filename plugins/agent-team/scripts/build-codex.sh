#!/usr/bin/env bash
# Build and export Agent Team skills for OpenAI Codex / Codex-compatible runners.
#
#   bash scripts/build-codex.sh [--force] [DEST]
#
# DEST defaults to ~/.agents/skills (or .agents/skills if project-local).
# Codex reads agent skills directly from the skills directory.

set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
FORCE=0
DEST=""

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "unknown option: $arg" >&2
      exit 1
      ;;
    *)
      DEST="$arg"
      ;;
  esac
done

DEST="${DEST:-$HOME/.agents/skills}"
mkdir -p "$DEST"

echo "Exporting Agent Team skills to Codex destination: $DEST"

# Copy each skill folder to DEST
for skill_dir in "$SRC"/skills/*; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  target_dir="$DEST/$skill_name"
  
  if [ -e "$target_dir" ] && [ "$FORCE" != "1" ]; then
    rm -rf "$target_dir"
  fi
  
  cp -R "$skill_dir" "$DEST/"
done

# Ensure helper scripts inside skills have executable permissions
chmod +x "$DEST"/*/scripts/*.py 2>/dev/null || true
chmod +x "$DEST"/*/scripts/*.sh 2>/dev/null || true

SKILL_COUNT=$(ls -d "$DEST"/* 2>/dev/null | wc -l | tr -d ' ')
echo "Successfully exported $SKILL_COUNT skills for Codex at $DEST"
