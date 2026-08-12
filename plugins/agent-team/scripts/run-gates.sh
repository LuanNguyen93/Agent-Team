#!/usr/bin/env bash
# Discover and run this project's quality gates in order.
# Exit 0 when every discovered gate passes or when none exist.
# Exit 1 when a gate fails; the failing gate and its output go to stdout.
#
# Gates can be declared explicitly in .agent-team.json:
#   { "gates": ["pnpm typecheck", "pnpm lint", "pnpm test"] }
# Otherwise they are discovered from package.json scripts.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$ROOT" 2>/dev/null || exit 0

run_gate() {
  local name="$1" cmd="$2" out status
  out=$(eval "$cmd" 2>&1)
  status=$?
  if [ $status -ne 0 ]; then
    printf 'Gate FAILED: %s\n' "$name"
    printf 'Command: %s\n' "$cmd"
    printf 'Exit code: %s\n\n' "$status"
    printf '%s\n' "$out" | tail -40
    return 1
  fi
  return 0
}

# 1. Explicit configuration wins.
if [ -f .agent-team.json ] && command -v node >/dev/null 2>&1; then
  mapfile -t GATES < <(node -e '
    try {
      const c = require("./.agent-team.json");
      if (Array.isArray(c.gates)) c.gates.forEach(g => console.log(g));
    } catch (e) {}
  ' 2>/dev/null)
  if [ "${#GATES[@]}" -gt 0 ]; then
    for g in "${GATES[@]}"; do
      run_gate "$g" "$g" || exit 1
    done
    exit 0
  fi
fi

# 2. Otherwise discover from package.json.
[ -f package.json ] || exit 0
command -v node >/dev/null 2>&1 || exit 0

# A package.json that cannot be parsed is a real problem, and it must not be
# mistaken for "this project has no gates" - that silently reports a pass.
if ! node -e 'require("./package.json")' 2>/dev/null; then
  printf 'Gate FAILED: package.json is present but could not be parsed
'
  printf 'Command: node -e '"'"'require("./package.json")'"'"'

'
  node -e 'require("./package.json")' 2>&1 | head -10
  exit 1
fi

PM=npm
[ -f pnpm-lock.yaml ] && PM=pnpm
[ -f yarn.lock ] && PM=yarn
[ -f bun.lockb ] && PM=bun
command -v "$PM" >/dev/null 2>&1 || PM=npm

has_script() {
  node -e '
    try {
      const s = (require("./package.json").scripts) || {};
      process.exit(s[process.argv[1]] ? 0 : 1);
    } catch (e) { process.exit(1); }
  ' "$1" 2>/dev/null
}

# Ordered cheapest-and-most-localised first, so failures read clearly.
for script in typecheck type-check tsc lint test build; do
  case "$script" in
    type-check|tsc) has_script typecheck && continue ;;
    test) [ "${AGENT_TEAM_SKIP_TESTS:-}" = "1" ] && continue ;;
    build) [ "${AGENT_TEAM_RUN_BUILD:-}" = "1" ] || continue ;;
  esac
  if has_script "$script"; then
    run_gate "$script" "$PM run $script" || exit 1
  fi
done

exit 0
