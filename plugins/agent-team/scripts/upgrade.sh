#!/usr/bin/env bash
# Self-Upgrade and Synchronization utility for Agent Team across platforms:
# Claude Code, Antigravity (Gemini), and Codex.
#
#   bash scripts/upgrade.sh [--pull] [--skip-tests] [--force]
#
# Steps:
# 1. Inspect git upstream & current version.
# 2. Run verification quality gates (unit tests & platform tests).
# 3. Transpile & install to Antigravity (~/.gemini/config/plugins/agent-team).
# 4. Export & install to Codex (~/.agents/skills).
# 5. Output multi-platform readiness status.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"

PULL=0
SKIP_TESTS=0
FORCE=1
CHECK_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --pull) PULL=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    --check-only) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

echo "=================================================="
echo "    Agent Team Universal Self-Upgrade Engine      "
echo "=================================================="

# 1. Upstream & Version Check
MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"
VERSION="$(sed -n -E 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$MANIFEST" | head -n 1)"
echo "Current Version: $VERSION"

if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "detached")"
  COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
  echo "Git Branch: $BRANCH ($COMMIT)"

  if [ "$PULL" = "1" ]; then
    echo "Pulling latest updates from git upstream..."
    git -C "$REPO_ROOT" pull --rebase origin "$BRANCH" || {
      echo "Failed to pull from upstream. Aborting." >&2
      exit 1
    }
  fi
fi

# 2. Quality Gates & Regression Verification
if [ "$SKIP_TESTS" != "1" ]; then
  echo ""
  echo "--- Running Quality Gates & Invariant Verification ---"
  
  echo "1. Unit & Integrity Tests:"
  python3 -m unittest discover -s "$PLUGIN_ROOT/tests"
  
  echo "2. Plugin Shipping & Manifest Gates:"
  bash "$PLUGIN_ROOT/scripts/tests/plugin-shipping.test.sh"
  
  echo "3. Antigravity Platform Gates:"
  bash "$PLUGIN_ROOT/scripts/tests/antigravity.test.sh"
  
  echo "4. Agent Quantitative Benchmark & Eval Invariants:"
  python3 "$PLUGIN_ROOT/scripts/eval.py" --strict
  
  echo "All Quality Gates passed successfully!"
else
  echo "Skipping verification tests as requested."
fi

if [ "$CHECK_ONLY" = "1" ]; then
  echo "Check-only mode completed. No files modified."
  exit 0
fi

# 3. Synchronize Antigravity Platform
echo ""
echo "--- Synchronizing Antigravity Platform ---"
bash "$PLUGIN_ROOT/scripts/build-antigravity.sh" --force

# 4. Synchronize Codex Platform
echo ""
echo "--- Synchronizing Codex Platform ---"
bash "$PLUGIN_ROOT/scripts/build-codex.sh" --force

echo ""
echo "=================================================="
echo "       Upgrade & Synchronization Complete         "
echo "=================================================="
echo "Version:     $VERSION"
echo "Claude Code: Ready (source at plugins/agent-team)"
echo "Antigravity: Installed (~/.gemini/config/plugins/agent-team)"
echo "Codex:       Installed (~/.agents/skills)"
echo ""
echo "Note: If running Antigravity, restart it to load any new skills or agents."
