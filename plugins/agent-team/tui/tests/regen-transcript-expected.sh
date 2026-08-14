#!/usr/bin/env bash
# Regenerates plugins/agent-team/tui/tests/fixtures/transcripts/expected.json
# from the committed fixture input, via measure-tokens.js --json.
#
# Per ADR-0007(a): measure-tokens.js is authoritative and the only generator
# of expected.json - the Rust side is tested against this file, never the
# other way around. Never hand-edit expected.json; re-run this script.
#
# The raw --json capture is machine-specific: `project` is an absolute path,
# so a byte-for-byte capture would rewrite itself on every checkout and
# produce a permanent merge conflict. This script therefore normalises the
# capture with EXACTLY three transforms and no others - do not "fix" this
# back to a pure capture, and do not add a field neither implementation
# produces:
#   - delete `project` (machine state, no parity value - both parsers are
#     pointed at the fixture by their own harness)
#   - add `fixtureVersion: "1.0"`
#   - add `generator: "measure-tokens.js --json"`
# All three are excluded from the parity comparison.
#
# POSIX-ish on purpose (CLAUDE.md): this must run unmodified on Windows Git
# Bash, macOS and Linux.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures/transcripts"
PROJECT_DIR="$FIXTURES_DIR/project"
MEASURE="$SCRIPT_DIR/../../scripts/measure-tokens.js"
OUT="$FIXTURES_DIR/expected.json"

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - cannot regenerate expected.json" >&2
  exit 1
fi

node "$MEASURE" --project "$PROJECT_DIR" --json | node -e '
  let s = "";
  process.stdin.on("data", (d) => (s += d));
  process.stdin.on("end", () => {
    const raw = JSON.parse(s);
    delete raw.project;
    const out = { fixtureVersion: "1.0", generator: "measure-tokens.js --json", ...raw };
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
  });
' > "$OUT"

echo "wrote $OUT"
