#!/usr/bin/env bash
# Discover and run this project's quality gates in order.
# Exit 0 when every discovered gate passes or when none exist.
# Exit 1 when a gate fails; the failing gate and its output go to stdout.
#
# Gates can be declared explicitly in .agent-team.json:
#   { "gates": ["pnpm typecheck", "pnpm lint", "pnpm test"] }
# Otherwise they are discovered from package.json scripts.
#
# AGENT_TEAM_RUN_SONAR=1 adds the static-analysis gate when the project has a
# "sonar" script or a sonar-project.properties plus sonar-scanner on PATH.

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

# 2. Rust, via Cargo.
if [ -f Cargo.toml ]; then
  if ! command -v cargo >/dev/null 2>&1; then
    printf 'Gate FAILED: Cargo.toml is present but cargo is not on PATH\n'
    printf 'The gates for this project cannot be verified, so it must not be\n'
    printf 'reported as passing. Install the Rust toolchain, or declare the real\n'
    printf 'commands in .agent-team.json.\n'
    exit 1
  fi
  command -v rustfmt >/dev/null 2>&1 && { run_gate fmt "cargo fmt --check" || exit 1; }
  cargo clippy --version >/dev/null 2>&1 && { run_gate clippy "cargo clippy --all-targets -- -D warnings" || exit 1; }
  [ "${AGENT_TEAM_SKIP_TESTS:-}" = "1" ] || { run_gate test "cargo test" || exit 1; }
  [ "${AGENT_TEAM_RUN_BUILD:-}" = "1" ] && { run_gate build "cargo build --release" || exit 1; }
fi

# 3. Dart and Flutter, via pubspec.yaml.
if [ -f pubspec.yaml ]; then
  DART=dart
  grep -q '^ *flutter:' pubspec.yaml && DART=flutter
  if ! command -v "$DART" >/dev/null 2>&1; then
    printf 'Gate FAILED: pubspec.yaml is present but %s is not on PATH\n' "$DART"
    printf 'The gates cannot be verified, so this must not be reported as a pass.\n'
    exit 1
  fi
  if command -v dart >/dev/null 2>&1; then
    run_gate format "dart format --set-exit-if-changed ." || exit 1
  fi
  run_gate analyze "$DART analyze" || exit 1
  [ "${AGENT_TEAM_SKIP_TESTS:-}" = "1" ] || { run_gate test "$DART test" || exit 1; }
fi

# 4. C# and .NET, via a solution or project file.
DOTNET_TARGET=""
for f in *.sln *.slnx; do [ -e "$f" ] && DOTNET_TARGET="$f" && break; done
if [ -z "$DOTNET_TARGET" ]; then
  for f in *.csproj *.fsproj; do [ -e "$f" ] && DOTNET_TARGET="$f" && break; done
fi
if [ -n "$DOTNET_TARGET" ]; then
  if ! command -v dotnet >/dev/null 2>&1; then
    printf 'Gate FAILED: %s is present but dotnet is not on PATH\n' "$DOTNET_TARGET"
    printf 'The gates for this project cannot be verified, so it must not be\n'
    printf 'reported as passing. Install the .NET SDK, or declare the real\n'
    printf 'commands in .agent-team.json.\n'
    exit 1
  fi
  # dotnet format ships with the SDK from .NET 6; older SDKs need it installed.
  dotnet format --version >/dev/null 2>&1 && {
    run_gate format "dotnet format \"$DOTNET_TARGET\" --verify-no-changes" || exit 1
  }
  # For C# the build IS the typecheck, so it is not opt-in the way it is for JS.
  run_gate build "dotnet build \"$DOTNET_TARGET\" --nologo" || exit 1
  [ "${AGENT_TEAM_SKIP_TESTS:-}" = "1" ] || {
    run_gate test "dotnet test \"$DOTNET_TARGET\" --nologo --no-build" || exit 1
  }
fi

# 5. JavaScript and TypeScript, via package.json.
if [ ! -f package.json ] || ! command -v node >/dev/null 2>&1; then
  exit 0
fi

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

# Static analysis is opt-in: it needs a server and a token, and it is far slower
# than the local gates. Absent stays absent - never substitute a scanner run.
if [ "${AGENT_TEAM_RUN_SONAR:-}" = "1" ]; then
  if has_script sonar; then
    run_gate sonar "$PM run sonar" || exit 1
  elif [ -f sonar-project.properties ] && command -v sonar-scanner >/dev/null 2>&1; then
    run_gate sonar sonar-scanner || exit 1
  fi
fi

exit 0
