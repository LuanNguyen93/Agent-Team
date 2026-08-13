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
#
# The dependency-audit gate runs whenever its tool is on PATH. A missing tool or
# an unreachable advisory database is reported as ABSENT and does not fail the
# run - a gate that could not run must never be reported as a pass, and must not
# be reported as a failure either. AGENT_TEAM_SKIP_AUDIT=1 opts out.
# Projects declaring "gates" in .agent-team.json should list their audit command
# there; explicit configuration replaces this discovery entirely.
#
# The audit gate is cached against a fingerprint of the project's manifests and
# lockfiles, because it is the only gate here that makes a network call and its
# answer cannot change while its input has not. AGENT_TEAM_FORCE_AUDIT=1 ignores
# the cache. govulncheck is deliberately never cached - see run_audit.
#
# The secret-scan gate is stack-independent, so it runs for every project - it is
# the one gate an explicit "gates" list does not replace. It runs gitleaks or
# trufflehog over the working tree when one is on PATH. It scans the tree, not the history: history is slow and a hit there
# needs a rotation decision, not a blocked task. AGENT_TEAM_SCAN_HISTORY=1 scans
# the full history instead; AGENT_TEAM_SKIP_SECRET_SCAN=1 opts out.

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

# The audit and secret-scan gates depend on a tool that may not be installed and
# a service that may not be reachable. Either is "we do not know", which is
# absent, not green - and equally, not a failure to be debugged.
# "Could not run" and "found something" are different answers, and collapsing
# them is the one defect that makes every gate in this file worthless: an absent
# gate reported as green is a lie, and a tool error reported as a finding sends
# someone chasing a leak that is not there. One matcher, used by both gates.
looks_absent() {
  case "$1" in
    *ENOTFOUND*|*EAI_AGAIN*|*ETIMEDOUT*|*ECONNREFUSED*|*"no such host"*) return 0 ;;
    *"dial tcp"*|*"Temporary failure in name resolution"*) return 0 ;;
    *"connection refused"*|*"Could not resolve"*|*"Network is unreachable"*) return 0 ;;
    *"command not found"*|*"is not recognized"*|*"No module named"*) return 0 ;;
    *"Failed to spawn"*|*"executable file not found"*) return 0 ;;
  esac
  return 1
}

report_absent() {
  printf 'Gate ABSENT: %s did not run - tool missing or its service unreachable\n' "$1"
  printf 'This is not a pass. Install the tool or restore access, then re-run.\n'
}

# Everything that pins what a dependency audit would resolve. Listed rather than
# globbed so an unrelated file cannot silently invalidate - or silently preserve
# - a cached result.
AUDIT_INPUTS="package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock
bun.lock bun.lockb package.json requirements.txt requirements-dev.txt
poetry.lock uv.lock Pipfile.lock pyproject.toml Cargo.lock Cargo.toml go.mod
go.sum pubspec.lock packages.lock.json paket.lock"

# A cached result older than this is discarded: an advisory database gains
# entries against dependencies nobody touched, so "the lockfile has not changed"
# is only a good answer for a while.
AUDIT_TTL_HOURS="${AGENT_TEAM_AUDIT_TTL_HOURS:-24}"

# .NET pins versions in the project file, and the usual layout puts those under
# src/, not at the root. Bounded depth and pruned build output so this cannot
# turn into a repository walk.
audit_project_files() {
  find . -maxdepth 4 \
    \( -name node_modules -o -name .git -o -name obj -o -name bin \
       -o -name target -o -name .venv -o -name vendor \) -prune -o \
    -type f \( -name '*.csproj' -o -name '*.fsproj' \
       -o -name 'Directory.Packages.props' \) -print 2>/dev/null | LC_ALL=C sort
}

# cksum is POSIX and present on Git Bash, macOS and Linux; md5sum is not on all
# three. The fingerprint only has to change when the input does, not be a hash.
audit_fingerprint() {
  local f found=0 projects
  projects=$(audit_project_files)

  # Existence is checked BEFORE the pipeline: a `found=1` set inside a piped
  # block runs in a subshell and never reaches the caller, which would silently
  # disable the cache instead of failing loudly.
  for f in $AUDIT_INPUTS; do
    [ -f "$f" ] && { found=1; break; }
  done
  [ -n "$projects" ] && found=1
  [ "$found" -eq 1 ] || return 1

  {
    for f in $AUDIT_INPUTS; do
      [ -f "$f" ] && { printf '%s:' "$f"; cat "$f"; }
    done
    printf '%s' "$projects" | while IFS= read -r f; do
      [ -n "$f" ] && { printf '%s:' "$f"; cat "$f"; }
    done
    # pipefail is on, and a block whose last command is a false test would make
    # the whole pipeline non-zero - which reads as "no fingerprint" and quietly
    # disables the cache.
    true
  } 2>/dev/null | cksum | awk '{print $1 "-" $2}'
}

# The stamp lives in .git, not the working tree: nothing to gitignore, nothing
# for the secret scan to walk, and it disappears with the clone.
audit_stamp_file() {
  local gitdir
  gitdir=$(git rev-parse --git-dir 2>/dev/null) || return 1
  [ -d "$gitdir" ] || return 1
  mkdir -p "$gitdir/agent-team" 2>/dev/null || return 1
  printf '%s/agent-team/audit-stamp' "$gitdir"
}

# A cached pass is only ever recorded for a gate that actually passed. An absent
# gate and a failing gate both stay uncached, so the next run tries again -
# caching either one would turn "we could not check" into "we checked" for as
# long as nobody touches a lockfile.
#
# The key is per audit tool, not per gate name. Both the .NET and the JS gate
# are called "dependency audit", and a shared key would let one report the
# other's pass in a repository that has both.
audit_is_cached() {
  local key="$1" stamp fp line stamped_fp stamped_at now age_limit
  [ "${AGENT_TEAM_FORCE_AUDIT:-}" = "1" ] && return 1
  stamp=$(audit_stamp_file) || return 1
  [ -f "$stamp" ] || return 1
  fp=$(audit_fingerprint) || return 1

  line=$(grep "^$key " "$stamp" 2>/dev/null | tail -1)
  [ -n "$line" ] || return 1
  stamped_fp=$(printf '%s' "$line" | awk '{print $2}')
  stamped_at=$(printf '%s' "$line" | awk '{print $3}')
  [ "$stamped_fp" = "$fp" ] || return 1

  # No timestamp means a stamp from an older version of this script: treat it as
  # expired rather than trusting it forever.
  case "$stamped_at" in ''|*[!0-9]*) return 1 ;; esac
  now=$(date +%s 2>/dev/null) || return 1
  case "$now" in ''|*[!0-9]*) return 1 ;; esac
  age_limit=$(( AUDIT_TTL_HOURS * 3600 ))
  [ $(( now - stamped_at )) -lt "$age_limit" ] || return 1
  return 0
}

audit_record_pass() {
  local key="$1" stamp fp tmp now
  stamp=$(audit_stamp_file) || return 0
  fp=$(audit_fingerprint) || return 0
  now=$(date +%s 2>/dev/null) || return 0
  tmp="$stamp.$$.tmp"
  { grep -v "^$key " "$stamp" 2>/dev/null; printf '%s %s %s\n' "$key" "$fp" "$now"; } > "$tmp" 2>/dev/null \
    && mv "$tmp" "$stamp" 2>/dev/null
  rm -f "$tmp" 2>/dev/null
  return 0
}

# The tool decides the cache key: `npm audit ...` -> npm, `pip-audit` -> pip-audit.
audit_key_for() {
  printf '%s' "$1" | awk '{print $1}'
}

run_audit() {
  local name="$1" cmd="$2" out status
  if [ "${AGENT_TEAM_SKIP_AUDIT:-}" = "1" ]; then
    printf 'Gate SKIPPED: %s (AGENT_TEAM_SKIP_AUDIT=1)\n' "$name"
    return 0
  fi
  # govulncheck is the exception: it reports only vulnerabilities the code can
  # actually reach, so its answer changes when the code changes, not just when
  # go.sum does. Caching it on the manifest alone would hide a vulnerability that
  # a new call path just made reachable.
  case "$cmd" in
    govulncheck*) : ;;
    *)
      if audit_is_cached "$(audit_key_for "$cmd")"; then
        printf 'Gate CACHED: %s passed, and no manifest or lockfile has changed since\n' "$name"
        return 0
      fi
      ;;
  esac
  out=$(eval "$cmd" 2>&1)
  status=$?
  if [ $status -ne 0 ]; then
    if looks_absent "$out"; then
      report_absent "$name"
      return 0
    fi
    printf 'Gate FAILED: %s\n' "$name"
    printf 'Command: %s\n' "$cmd"
    printf 'Exit code: %s\n\n' "$status"
    printf '%s\n' "$out" | tail -40
    printf '\nDo not raise the severity threshold or ignore the advisory to clear this.\n'
    return 1
  fi
  case "$cmd" in
    govulncheck*) : ;;
    *) audit_record_pass "$(audit_key_for "$cmd")" ;;
  esac
  return 0
}

# Secrets are stack-independent, so this gate runs once for the whole project
# rather than inside each language block.
run_secret_scan() {
  if [ "${AGENT_TEAM_SKIP_SECRET_SCAN:-}" = "1" ]; then
    printf 'Gate SKIPPED: secret scan (AGENT_TEAM_SKIP_SECRET_SCAN=1)\n'
    return 0
  fi
  local cmd="" cfg=""
  # A project's own config always wins. Otherwise use the one shipped with the
  # plugin, which allowlists node_modules, vendor, .venv and build output - see
  # scripts/gitleaks-default.toml for why.
  if [ ! -f .gitleaks.toml ] && [ ! -f gitleaks.toml ]; then
    SCAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [ -f "$SCAN_DIR/gitleaks-default.toml" ] && cfg=" --config $SCAN_DIR/gitleaks-default.toml"
  fi
  if command -v gitleaks >/dev/null 2>&1; then
    if [ "${AGENT_TEAM_SCAN_HISTORY:-}" = "1" ]; then
      # `gitleaks git` is v8.19+; `detect` is the older spelling of the same scan.
      if gitleaks git --help >/dev/null 2>&1; then
        cmd="gitleaks git . --no-banner --redact$cfg"
      else
        cmd="gitleaks detect --no-banner --redact$cfg"
      fi
    elif gitleaks dir --help >/dev/null 2>&1; then
      cmd="gitleaks dir . --no-banner --redact$cfg"
    else
      cmd="gitleaks detect --no-git --no-banner --redact$cfg"
    fi
  elif command -v trufflehog >/dev/null 2>&1; then
    # NOT --results=verified: verification needs the provider's API, so offline it
    # reports nothing and exits 0, and a private key or a database password has no
    # provider to verify against at all. Either way a verified-only scan passes a
    # tree that holds a real secret. Take the noise instead.
    cmd="trufflehog filesystem . --results=verified,unknown,unverified --fail --no-update"
  else
    printf 'Gate ABSENT: no secret scanner on PATH (gitleaks or trufflehog)\n'
    printf 'This is not a pass. Nothing checked whether a credential is in the tree.\n'
    return 0
  fi

  local out status
  out=$(eval "$cmd" 2>&1)
  status=$?
  [ $status -eq 0 ] && return 0
  # A scanner that could not run is not a leak. Saying "rotate your credentials"
  # because gitleaks was pointed at a non-git directory burns the gate's credibility.
  if looks_absent "$out"; then
    report_absent "secret scan"
    return 0
  fi
  case "$out" in
    *"not a git repository"*|*"failed to open"*|*"error parsing"*|*"unknown flag"*|\
    *"invalid config"*|*"no such file or directory"*)
      report_absent "secret scan"
      return 0
      ;;
  esac
  printf 'Gate FAILED: secret scan\n'
  printf 'Command: %s\n' "$cmd"
  printf 'Exit code: %s\n\n' "$status"
  printf '%s\n' "$out" | tail -40
  printf '\nA committed secret is a leaked secret: the fix is to ROTATE the credential,\n'
  printf 'not to delete the line or amend the commit. Tell the user before doing\n'
  printf 'anything else - only they can rotate it. If this is genuinely a false\n'
  printf 'positive, it needs a .gitleaksignore entry with a comment saying why.\n'
  return 1
}

run_secret_scan || exit 1

# A prose-only change still gets the secret scan - a token pasted into a README
# example is one of the commonest ways a credential is committed - but nothing
# else, because no other gate has anything to say about a paragraph.
[ "${AGENT_TEAM_SECRET_SCAN_ONLY:-}" = "1" ] && exit 0

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
  command -v cargo-audit >/dev/null 2>&1 && { run_audit "cargo audit" "cargo audit" || exit 1; }
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
  command -v osv-scanner >/dev/null 2>&1 && [ -f pubspec.lock ] && {
    run_audit "osv-scanner" "osv-scanner --lockfile=pubspec.lock" || exit 1
  }
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
  # `dotnet list package --vulnerable` is the one command here whose exit code
  # cannot be trusted in either direction: it exits 0 when it finds vulnerable
  # packages, and non-zero when the project could not be restored or the SDK is
  # too old for the flag. So: read the status to decide ABSENT, and read the
  # output to decide FAILED - and read it as JSON, because the English sentence
  # is localized and would miss every finding on a non-English SDK.
  if [ "${AGENT_TEAM_SKIP_AUDIT:-}" = "1" ]; then
    printf 'Gate SKIPPED: dependency audit (AGENT_TEAM_SKIP_AUDIT=1)\n'
  elif audit_is_cached "dotnet-vulnerable"; then
    printf 'Gate CACHED: dependency audit passed, and no project file has changed since\n'
  else
    DN_LIST="dotnet list \"$DOTNET_TARGET\" package --vulnerable --include-transitive"
    VULN=$(eval "$DN_LIST --format json" 2>&1)
    DN_STATUS=$?
    DN_JSON=1
    if [ $DN_STATUS -ne 0 ]; then
      # --format is .NET 7+. Fall back to the text output on an older SDK.
      VULN=$(eval "$DN_LIST" 2>&1)
      DN_STATUS=$?
      DN_JSON=0
    fi
    if [ $DN_STATUS -ne 0 ]; then
      report_absent "dependency audit"
      printf 'Command: %s\n' "$DN_LIST"
      printf '%s\n' "$VULN" | tail -20
    else
      DN_HIT=0
      if [ $DN_JSON -eq 1 ]; then
        # A JSON report lists vulnerabilities only when it found some, and the
        # key names are not translated.
        case "$VULN" in *'"severity"'*) DN_HIT=1 ;; esac
      else
        case "$VULN" in *"has the following vulnerable packages"*) DN_HIT=1 ;; esac
      fi
      if [ $DN_HIT -eq 1 ]; then
        printf 'Gate FAILED: dependency audit\n'
        printf 'Command: %s\n\n' "$DN_LIST"
        printf '%s\n' "$VULN" | tail -40
        printf '\nDo not raise the severity threshold or ignore the advisory to clear this.\n'
        exit 1
      fi
      audit_record_pass "dotnet-vulnerable"
    fi
  fi
  [ "${AGENT_TEAM_SKIP_TESTS:-}" = "1" ] || {
    run_gate test "dotnet test \"$DOTNET_TARGET\" --nologo --no-build" || exit 1
  }
fi

# 5. Python, via pyproject.toml or setup.cfg.
if [ -f pyproject.toml ] || [ -f setup.cfg ]; then
  # The runner is what decides the command prefix: uv and poetry both put the
  # tools in an environment that a bare `ruff` on PATH is not part of.
  PY_RUN=""
  if [ -f uv.lock ] && command -v uv >/dev/null 2>&1; then
    PY_RUN="uv run"
  elif [ -f poetry.lock ] && command -v poetry >/dev/null 2>&1; then
    PY_RUN="poetry run"
  elif ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    printf 'Gate FAILED: pyproject.toml is present but no python is on PATH\n'
    printf 'The gates for this project cannot be verified, so it must not be\n'
    printf 'reported as passing. Activate the environment, or declare the real\n'
    printf 'commands in .agent-team.json.\n'
    exit 1
  fi

  py_has() { [ -n "$PY_RUN" ] && return 0; command -v "$1" >/dev/null 2>&1; }
  py_cmd() { if [ -n "$PY_RUN" ]; then printf '%s %s' "$PY_RUN" "$1"; else printf '%s' "$1"; fi; }

  # Configured tools only. An invented mypy run on a project that never typed
  # its code produces noise, not a gate.
  if grep -q 'ruff' pyproject.toml 2>/dev/null || [ -f ruff.toml ] || [ -f .ruff.toml ]; then
    py_has ruff && {
      run_gate format "$(py_cmd 'ruff format --check .')" || exit 1
      run_gate lint "$(py_cmd 'ruff check .')" || exit 1
    }
  fi
  if grep -q 'mypy' pyproject.toml setup.cfg 2>/dev/null || [ -f mypy.ini ]; then
    py_has mypy && { run_gate typecheck "$(py_cmd 'mypy .')" || exit 1; }
  fi
  py_has pip-audit && { run_audit "pip-audit" "$(py_cmd 'pip-audit')" || exit 1; }
  if [ "${AGENT_TEAM_SKIP_TESTS:-}" != "1" ]; then
    if grep -q 'pytest' pyproject.toml setup.cfg 2>/dev/null || [ -f pytest.ini ] || [ -d tests ]; then
      # A missing linter is a skipped gate; a missing test runner on a project
      # that has tests is an unverifiable one, and that is a failure.
      if py_has pytest; then
        run_gate test "$(py_cmd 'pytest -q')" || exit 1
      else
        printf 'Gate FAILED: this project has tests but pytest is not runnable\n'
        printf 'The test gate cannot be verified, so it must not be reported as a\n'
        printf 'pass. Install the dev dependencies, activate the environment, or\n'
        printf 'declare the real command in .agent-team.json.\n'
        exit 1
      fi
    fi
  fi
fi

# 6. Go, via go.mod.
if [ -f go.mod ]; then
  if ! command -v go >/dev/null 2>&1; then
    printf 'Gate FAILED: go.mod is present but go is not on PATH\n'
    printf 'The gates for this project cannot be verified, so it must not be\n'
    printf 'reported as passing. Install the Go toolchain, or declare the real\n'
    printf 'commands in .agent-team.json.\n'
    exit 1
  fi
  # gofmt -l exits 0 and prints the offending files, so the list is the failure.
  run_gate format 'test -z "$(gofmt -l .)" || { gofmt -l .; false; }' || exit 1
  run_gate vet "go vet ./..." || exit 1
  command -v govulncheck >/dev/null 2>&1 && { run_audit govulncheck "govulncheck ./..." || exit 1; }
  [ "${AGENT_TEAM_SKIP_TESTS:-}" = "1" ] || { run_gate test "go test ./..." || exit 1; }
  [ "${AGENT_TEAM_RUN_BUILD:-}" = "1" ] && { run_gate build "go build ./..." || exit 1; }
fi

# 7. JavaScript and TypeScript, via package.json.
if [ ! -f package.json ] || ! command -v node >/dev/null 2>&1; then
  exit 0
fi

# A package.json that cannot be parsed is a real problem, and it must not be
# mistaken for "this project has no gates" - that silently reports a pass.
if ! node -e 'require("./package.json")' 2>/dev/null; then
  printf 'Gate FAILED: package.json is present but could not be parsed\n'
  printf 'Command: node -e '"'"'require("./package.json")'"'"'

'
  node -e 'require("./package.json")' 2>&1 | head -10
  exit 1
fi

PM=npm
[ -f pnpm-lock.yaml ] && PM=pnpm
[ -f yarn.lock ] && PM=yarn
[ -f bun.lockb ] && PM=bun
[ -f bun.lock ] && PM=bun
command -v "$PM" >/dev/null 2>&1 || PM=npm

has_script() {
  node -e '
    try {
      const s = (require("./package.json").scripts) || {};
      process.exit(s[process.argv[1]] ? 0 : 1);
    } catch (e) { process.exit(1); }
  ' "$1" 2>/dev/null
}

# The audit command differs per package manager. yarn 1's exit code is a bitmask
# of the severities found, and whether --level narrows it is undocumented, so a
# low advisory may fail the gate.
# Reporting that as absent beats a gate that fails on a low advisory, because a
# gate people learn to ignore is worse than one they know is missing.
js_audit_cmd() {
  case "$PM" in
    npm)  printf 'npm audit --audit-level=high' ;;
    pnpm) printf 'pnpm audit --audit-level high' ;;
    bun)  printf 'bun audit' ;;
    yarn)
      case "$(yarn --version 2>/dev/null)" in
        1.*) printf '' ;;
        *)   printf 'yarn npm audit --severity high' ;;
      esac
      ;;
  esac
}

# Ordered cheapest-and-most-localised first, so failures read clearly.
for script in typecheck type-check tsc lint audit test build; do
  case "$script" in
    type-check|tsc) has_script typecheck && continue ;;
    test) [ "${AGENT_TEAM_SKIP_TESTS:-}" = "1" ] && continue ;;
    build) [ "${AGENT_TEAM_RUN_BUILD:-}" = "1" ] || continue ;;
    audit)
      if [ "${AGENT_TEAM_SKIP_AUDIT:-}" = "1" ]; then
        printf %s "Gate SKIPPED: dependency audit (AGENT_TEAM_SKIP_AUDIT=1)"; printf "
"
        continue
      fi
      has_script audit && { run_gate audit "$PM run audit" || exit 1; continue; }
      has_script security && { run_gate security "$PM run security" || exit 1; continue; }
      # The lockfile has to match the package manager we are about to audit with.
      # Any lockfile is not enough: when the project's own manager is not
      # installed, PM falls back to npm above, and `npm audit` against a
      # bun.lock or pnpm-lock.yaml project dies with ENOLOCK - which is an
      # absent gate wearing a failure's clothes.
      HAVE_LOCK=0
      case "$PM" in
        npm)  { [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; } && HAVE_LOCK=1 ;;
        pnpm) [ -f pnpm-lock.yaml ] && HAVE_LOCK=1 ;;
        yarn) [ -f yarn.lock ] && HAVE_LOCK=1 ;;
        bun)  { [ -f bun.lockb ] || [ -f bun.lock ]; } && HAVE_LOCK=1 ;;
      esac
      if [ "$HAVE_LOCK" -eq 0 ]; then
        printf 'Gate ABSENT: dependency audit found no lockfile for %s\n' "$PM"
        printf 'Without one the audit describes the registry today, not what ships.\n'
        continue
      fi
      AUDIT_CMD="$(js_audit_cmd)"
      if [ -z "$AUDIT_CMD" ]; then
        printf 'Gate ABSENT: %s has no usable audit command\n' "$PM"
        printf 'Run osv-scanner against the lockfile, or declare one in .agent-team.json.\n'
        continue
      fi
      run_audit "dependency audit" "$AUDIT_CMD" || exit 1
      continue
      ;;
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
