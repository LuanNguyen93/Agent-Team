#!/usr/bin/env bash
# Compares the two independent srcHash implementations against each other on
# the same source tree: tui/rust/build.rs (embedded, read via --build-info)
# and tui/check-binaries.sh's recomputation (--print-src-hash). They must
# agree, including once src/ has a subdirectory - the case a flat fixture
# cannot exercise. This is the test the reviewer asked for: nothing else in
# this suite compares the two implementations against each other, which is
# exactly why the component-vs-byte sort divergence (B3) was invisible.
#
# Requires cargo on PATH; this test is skipped (not failed) if it is absent,
# consistent with this repo's "absent must report as absent" rule for gates
# that genuinely cannot run here.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_BINARIES="$SCRIPT_DIR/../check-binaries.sh"

if ! command -v cargo >/dev/null 2>&1; then
  echo "SKIPPING src-hash-consistency.test.sh: cargo not on PATH"
  exit 0
fi

PASS=0
FAIL=0

run_case() {
  desc="$1"
  fixture="$2"

  # 2>&1 (was the no-op typo `2>&2`, C2): merges cargo's stderr into the
  # captured output so a build failure here shows up as a real diagnosis
  # instead of a silently empty build_hash that would fail the comparison
  # below for the wrong reason.
  build_output="$(cd "$fixture/rust" && cargo build --quiet 2>&1)"
  build_status=$?
  if [ "$build_status" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc - cargo build failed (exit $build_status):"
    echo "$build_output"
    return
  fi

  build_hash="$(cd "$fixture/rust" && ./target/debug/agent-team-tui --build-info | awk -F': ' '/^srcHash/ {print $2}')"
  script_hash="$("$CHECK_BINARIES" --tui-root "$fixture" --print-src-hash)"

  if [ "$build_hash" = "$script_hash" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc"
    echo "  build.rs (--build-info):        $build_hash"
    echo "  check-binaries.sh (recomputed): $script_hash"
  fi
}

# A fixture crate that mirrors the real one but adds a sibling file+directory
# pair under src/ - exactly the shape the reviewer named: "src/ui.rs" next to
# "src/ui/tree.rs". A component-wise path sort (Rust's default PathBuf Ord)
# and a byte-wise string sort disagree on the order of these two.
build_subdir_fixture() {
  fixture="$1"
  mkdir -p "$fixture/rust/src/ui"
  cp "$SCRIPT_DIR/../rust/Cargo.toml" "$fixture/rust/Cargo.toml"
  cp "$SCRIPT_DIR/../rust/Cargo.lock" "$fixture/rust/Cargo.lock"
  cp "$SCRIPT_DIR/../rust/build.rs" "$fixture/rust/build.rs"
  cp "$SCRIPT_DIR/../rust/src/main.rs" "$fixture/rust/src/main.rs"
  echo "// ui module file" > "$fixture/rust/src/ui.rs"
  echo "// ui/tree.rs submodule" > "$fixture/rust/src/ui/tree.rs"
}

fixture="$(mktemp -d)"
build_subdir_fixture "$fixture"
run_case "srcHash agrees once src/ has a sibling file+directory pair" "$fixture"
rm -rf "$fixture"

# A second, differently-shaped fixture (C3): multiple levels of nesting
# (src/a/b/c.rs) rather than one sibling pair, so this pins the general
# property - "the two implementations agree on any src/ shape" - not just
# the single instance that caused the original bug report.
build_deep_nesting_fixture() {
  fixture="$1"
  mkdir -p "$fixture/rust/src/a/b"
  cp "$SCRIPT_DIR/../rust/Cargo.toml" "$fixture/rust/Cargo.toml"
  cp "$SCRIPT_DIR/../rust/Cargo.lock" "$fixture/rust/Cargo.lock"
  cp "$SCRIPT_DIR/../rust/build.rs" "$fixture/rust/build.rs"
  cp "$SCRIPT_DIR/../rust/src/main.rs" "$fixture/rust/src/main.rs"
  echo "// a module file" > "$fixture/rust/src/a.rs"
  echo "// a/b module file" > "$fixture/rust/src/a/b.rs"
  echo "// a/b/c.rs, three levels deep" > "$fixture/rust/src/a/b/c.rs"
}

fixture="$(mktemp -d)"
build_deep_nesting_fixture "$fixture"
run_case "srcHash agrees with multiple levels of nesting (src/a/b/c.rs)" "$fixture"
rm -rf "$fixture"

echo
echo "src-hash-consistency.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
