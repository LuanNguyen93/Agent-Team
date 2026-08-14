#!/usr/bin/env bash
# Plain POSIX-ish test runner for check-binaries.sh - no bats, matching this
# repo's convention of avoiding tools that may be absent (CLAUDE.md).
#
# Each test builds a throwaway fixture tree under a tempdir, runs
# check-binaries.sh --tui-root <fixture> and asserts on its exit code and
# stdout. Fixtures are generated here (not checked in) because they must
# carry real SHA-256 checksums computed by whatever hash tool the running
# machine has, or the fixtures themselves would go stale.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_BINARIES="$SCRIPT_DIR/../check-binaries.sh"

PASS=0
FAIL=0

sha_tool_present() {
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  fi
}

sha256_of_concat() {
  if command -v sha256sum >/dev/null 2>&1; then
    while IFS= read -r f; do cat "$f"; done < "$1" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    while IFS= read -r f; do cat "$f"; done < "$1" | shasum -a 256 | awk '{print $1}'
  else
    while IFS= read -r f; do cat "$f"; done < "$1" | openssl dgst -sha256 | awk '{print $NF}'
  fi
}

TRIPLES="x86_64-pc-windows-msvc x86_64-apple-darwin aarch64-apple-darwin x86_64-unknown-linux-musl aarch64-unknown-linux-musl"

bin_name_for() {
  case "$1" in
    x86_64-pc-windows-msvc) echo "agent-team-tui.exe" ;;
    *) echo "agent-team-tui" ;;
  esac
}

# Builds a well-formed fixture (all five triples present, checksums and
# srcHash all correct) under $1. Returns the computed srcHash on stdout.
build_matching_fixture() {
  fixture="$1"
  mkdir -p "$fixture/rust/src" "$fixture/bin"
  echo "fn main() {}" > "$fixture/rust/src/main.rs"
  echo "[package]" > "$fixture/rust/Cargo.toml"
  echo "name = \"agent-team-tui\"" >> "$fixture/rust/Cargo.toml"
  echo "# lockfile" > "$fixture/rust/Cargo.lock"

  filelist="$fixture/.filelist"
  {
    find "$fixture/rust/src" -type f | sed "s#^$fixture/rust/##"
    echo "Cargo.toml"
    echo "Cargo.lock"
  } | LC_ALL=C sort | sed "s#^#$fixture/rust/#" > "$filelist"
  src_hash="$(sha256_of_concat "$filelist")"
  rm -f "$filelist"

  : > "$fixture/bin/MANIFEST"
  for triple in $TRIPLES; do
    bin_name="$(bin_name_for "$triple")"
    mkdir -p "$fixture/bin/$triple"
    echo "binary contents for $triple" > "$fixture/bin/$triple/$bin_name"
    checksum="$(sha256_of "$fixture/bin/$triple/$bin_name")"
    printf '%s\t%s\t%s\n' "$triple" "$checksum" "$src_hash" >> "$fixture/bin/MANIFEST"
  done

  echo "$src_hash"
}

assert_exit() {
  desc="$1"; expected="$2"; actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc - expected exit $expected, got $actual"
  fi
}

assert_contains() {
  desc="$1"; haystack="$2"; needle="$3"
  case "$haystack" in
    *"$needle"*) PASS=$((PASS + 1)) ;;
    *)
      FAIL=$((FAIL + 1))
      echo "FAIL: $desc - expected output to contain '$needle'"
      echo "  output was: $haystack"
      ;;
  esac
}

git_available() {
  command -v git >/dev/null 2>&1
}

# A git repo whose history never touched bin/ - the ADR-0002 "never existed"
# case exit 2 is meant for. Fixture root ($1) becomes the git top-level so
# check-binaries.sh's `git -C "$TUI_ROOT" log -- bin` runs against it
# directly.
git_init_never_touched_bin() {
  fixture="$1"
  git -C "$fixture" init -q; git -C "$fixture" config core.autocrlf false
  git -C "$fixture" config user.email "test@example.com"
  git -C "$fixture" config user.name "test"
  mkdir -p "$fixture/rust/src"
  echo "fn main() {}" > "$fixture/rust/src/main.rs"
  git -C "$fixture" add -A
  git -C "$fixture" commit -q -m "initial commit, no bin/"
}

# --- Test 1: bin/ and MANIFEST absent, AND git history confirms bin/ has
# never existed in this repo -> exit 2 (distinct from a real mismatch's exit
# 1), all five named MISSING. Exit 2, not 1: authorised spec change (B4) - a
# PR workflow that is red until the first release exists, and the first
# release is gated behind a PR, can never go green. The empty state reports
# clearly but must not block.
#
# The git-history confirmation itself is required (ADR-0002 "Why exit 2 is
# non-blocking, and the guard rail it needs"): without it, `git rm -r bin`
# after a real release would satisfy the same emptiness check and the gate
# would report a clean bootstrap instead of a deleted release. See
# test_bin_deleted_after_being_committed below for that case. ---
test_empty_state() {
  if ! git_available; then
    echo "SKIPPING test_empty_state: git not on PATH"
    return
  fi
  fixture="$(mktemp -d)"
  git_init_never_touched_bin "$fixture"
  out="$("$CHECK_BINARIES" --tui-root "$fixture" 2>&1)"
  status=$?
  assert_exit "empty state (git-confirmed never-existed) exits 2, not 1" 2 "$status"
  for triple in $TRIPLES; do
    assert_contains "empty state names $triple missing" "$out" "MISSING: $triple"
  done
  rm -rf "$fixture"
}

# --- Test 1b: bin/ was committed (a real release happened) and later
# removed - `git rm -r bin`, or a merge conflict resolved the wrong way. This
# is NOT the empty state even though the working tree looks identical to
# Test 1's: history proves a release existed, so this must block (exit 1),
# never silently confirm a clean bootstrap. ---
test_bin_deleted_after_being_committed() {
  if ! git_available || ! sha_tool_present; then
    echo "SKIPPING test_bin_deleted_after_being_committed: needs git and a SHA-256 tool"
    return
  fi
  fixture="$(mktemp -d)"
  git -C "$fixture" init -q; git -C "$fixture" config core.autocrlf false
  git -C "$fixture" config user.email "test@example.com"
  git -C "$fixture" config user.name "test"
  build_matching_fixture "$fixture" > /dev/null
  git -C "$fixture" add -A
  git -C "$fixture" commit -q -m "release: commit bin/"
  git -C "$fixture" rm -rq bin
  git -C "$fixture" commit -q -m "oops: bin/ removed"

  out="$("$CHECK_BINARIES" --tui-root "$fixture" 2>&1)"
  status=$?
  assert_exit "bin/ deleted after being committed exits 1, not 2" 1 "$status"

  rm -rf "$fixture"
}

# --- Test 1c: a shallow clone cannot answer "did bin/ ever exist" - `git
# log -- bin` on a shallow clone returns nothing regardless of the true
# answer. The guard must report itself UNAVAILABLE and refuse to grant the
# non-blocking exit 2 rather than silently trusting a query it cannot
# actually answer (CLAUDE.md: absent must report as absent, not a pass). ---
test_shallow_clone_guard_unavailable() {
  if ! git_available; then
    echo "SKIPPING test_shallow_clone_guard_unavailable: git not on PATH"
    return
  fi
  origin="$(mktemp -d)"
  git -C "$origin" init -q; git -C "$origin" config core.autocrlf false
  git -C "$origin" config user.email "test@example.com"
  git -C "$origin" config user.name "test"
  mkdir -p "$origin/rust/src"
  echo "fn main() {}" > "$origin/rust/src/main.rs"
  git -C "$origin" add -A
  git -C "$origin" commit -q -m "commit 1"
  echo "fn main() { /* 2 */ }" > "$origin/rust/src/main.rs"
  git -C "$origin" add -A
  git -C "$origin" commit -q -m "commit 2"

  clone="$(mktemp -d)/clone"
  # --depth is silently ignored for a plain local-path clone ("--depth is
  # ignored in local clones; use file:// instead") - file:// forces a real
  # network-style transfer so the shallow clone is actually shallow.
  git clone -q --depth 1 "file://$origin" "$clone" 2>/dev/null

  out="$("$CHECK_BINARIES" --tui-root "$clone" 2>&1)"
  status=$?
  assert_exit "shallow clone exits 1 (guard unavailable), not a silent 2" 1 "$status"
  assert_contains "shallow clone reports the guard as unavailable" "$out" "UNAVAILABLE"

  rm -rf "$origin" "$clone"
}

# --- Test 1d: not a git repository at all - the guard cannot run its query
# and must not assume a clean bootstrap on that basis either. ---
test_not_a_git_repo_guard_unavailable() {
  fixture="$(mktemp -d)"
  mkdir -p "$fixture/rust/src"
  out="$("$CHECK_BINARIES" --tui-root "$fixture" 2>&1)"
  status=$?
  assert_exit "non-git directory exits 1 (guard unavailable), not a silent 2" 1 "$status"
  assert_contains "non-git directory reports the guard as unavailable" "$out" "UNAVAILABLE"
  rm -rf "$fixture"
}

# --- Test 2: no SHA-256 tool on PATH -> exit 0, SKIPPED + reason. ---
test_no_sha_tool() {
  fixture="$(mktemp -d)"
  build_matching_fixture "$fixture" > /dev/null

  # A PATH with no sha256sum/shasum/openssl, otherwise intact: a full copy of
  # the directory bash itself lives in (not symlinks - on Windows a bare
  # symlink into /usr/bin does not carry the shared libraries bash needs
  # alongside it, and the copy needs those to even start), minus the three
  # hashing tools. This matches the story's "no SHA-256 tool" scenario rather
  # than "no shell at all".
  real_bin_dir="$(dirname "$(command -v bash)")"
  stripped_path="$(mktemp -d)"
  cp -a "$real_bin_dir"/. "$stripped_path"/
  rm -f "$stripped_path"/sha256sum* "$stripped_path"/shasum* "$stripped_path"/openssl*

  out="$(PATH="$stripped_path" "$CHECK_BINARIES" --tui-root "$fixture" 2>&1)"
  status=$?
  assert_exit "no sha tool exits 0" 0 "$status"
  assert_contains "no sha tool reports SKIPPED" "$out" "SKIPPED"
  assert_contains "no sha tool names the reason" "$out" "SHA-256 tool"

  rm -rf "$fixture" "$stripped_path"
}

# --- Test 3: one binary's bytes changed -> exit 1 naming exactly that triple. ---
test_one_binary_stale() {
  fixture="$(mktemp -d)"
  build_matching_fixture "$fixture" > /dev/null

  changed_triple="x86_64-apple-darwin"
  bin_name="$(bin_name_for "$changed_triple")"
  echo "tampered bytes" > "$fixture/bin/$changed_triple/$bin_name"

  out="$("$CHECK_BINARIES" --tui-root "$fixture" 2>&1)"
  status=$?
  assert_exit "one stale binary exits 1" 1 "$status"
  assert_contains "names the changed triple" "$out" "CHECKSUM_MISMATCH: $changed_triple"
  for triple in $TRIPLES; do
    if [ "$triple" != "$changed_triple" ]; then
      case "$out" in
        *"CHECKSUM_MISMATCH: $triple"*)
          FAIL=$((FAIL + 1))
          echo "FAIL: one stale binary - unexpectedly named $triple too"
          ;;
        *) PASS=$((PASS + 1)) ;;
      esac
    fi
  done

  rm -rf "$fixture"
}

# --- Test 4: recomputed srcHash differs from MANIFEST's -> exit 1, all five. ---
test_src_hash_mismatch() {
  fixture="$(mktemp -d)"
  build_matching_fixture "$fixture" > /dev/null

  # Simulate "source moved on since MANIFEST was written": change source
  # after the MANIFEST (and its embedded srcHash) was generated.
  echo "fn main() { /* changed */ }" > "$fixture/rust/src/main.rs"

  out="$("$CHECK_BINARIES" --tui-root "$fixture" 2>&1)"
  status=$?
  assert_exit "srcHash mismatch exits 1" 1 "$status"
  for triple in $TRIPLES; do
    assert_contains "srcHash mismatch lists $triple" "$out" "SRC_HASH_STALE: $triple"
  done

  rm -rf "$fixture"
}

# --- Test 5a (B1): binaries present but MANIFEST absent is NOT the empty
# state - it is a mismatch (exit 1), because the repo genuinely has
# unverified binaries sitting in it (a bad rebase, a mis-resolved conflict,
# or someone deleting MANIFEST to silence the gate). Only "no bin/ AND no
# MANIFEST AND no binary for any triple" is genuinely empty (exit 2). ---
test_binaries_present_manifest_absent() {
  if ! sha_tool_present; then
    return
  fi
  fixture="$(mktemp -d)"
  build_matching_fixture "$fixture" > /dev/null
  rm -f "$fixture/bin/MANIFEST"

  out="$("$CHECK_BINARIES" --tui-root "$fixture" 2>&1)"
  status=$?
  assert_exit "binaries present, MANIFEST absent exits 1 (not 2)" 1 "$status"

  rm -rf "$fixture"
}

# --- Test 5: everything matches -> exit 0. ---
test_all_match() {
  fixture="$(mktemp -d)"
  build_matching_fixture "$fixture" > /dev/null

  out="$("$CHECK_BINARIES" --tui-root "$fixture" 2>&1)"
  status=$?
  assert_exit "all match exits 0" 0 "$status"
  assert_contains "all match reports OK" "$out" "OK"

  rm -rf "$fixture"
}

# --- Test 6 (C3, S1): --tui-root with no value is a usage error (exit 64,
# sysexits.h EX_USAGE, a clear message), not a `set -u` unbound-variable
# crash, and not the same exit code as the genuinely-empty state (2) - the
# two must be distinguishable by exit code alone. ---
test_tui_root_missing_value() {
  out="$("$CHECK_BINARIES" --tui-root 2>&1)"
  status=$?
  assert_exit "--tui-root with no value exits 64 (EX_USAGE), not 2" 64 "$status"
  assert_contains "--tui-root with no value prints usage" "$out" "usage:"
  case "$out" in
    *"unbound variable"*)
      FAIL=$((FAIL + 1))
      echo "FAIL: --tui-root with no value leaked a set -u crash: $out"
      ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

# --- Test 7 (C4): a --tui-root path containing `#` must not corrupt the
# recomputed srcHash. The old implementation stripped the RUST_DIR prefix
# with `sed "s#^$RUST_DIR/##"`, so a `#` inside RUST_DIR collided with sed's
# own delimiter. ---
test_tui_root_with_hash_in_path() {
  if ! sha_tool_present; then
    return
  fi
  parent="$(mktemp -d)"
  fixture="$parent/has#hash"
  mkdir -p "$fixture/rust/src"
  echo "fn main() {}" > "$fixture/rust/src/main.rs"
  echo "[package]" > "$fixture/rust/Cargo.toml"
  echo "# lockfile" > "$fixture/rust/Cargo.lock"

  out="$("$CHECK_BINARIES" --tui-root "$fixture" --print-src-hash 2>&1)"
  status=$?
  assert_exit "srcHash path containing # exits 0" 0 "$status"
  case "$out" in
    "" )
      FAIL=$((FAIL + 1))
      echo "FAIL: --print-src-hash with a # in --tui-root produced no hash"
      ;;
    *) PASS=$((PASS + 1)) ;;
  esac

  rm -rf "$parent"
}

# --- Test 8 (S1): pins all four exit codes the header documents, in one
# place, so the contract cannot silently drift back to two meanings sharing
# one number. ---
test_exit_code_contract() {
  fixture="$(mktemp -d)"

  if git_available; then
    git_init_never_touched_bin "$fixture"
    status_empty=$("$CHECK_BINARIES" --tui-root "$fixture" > /dev/null 2>&1; echo $?)
    assert_exit "contract: genuinely empty (git-confirmed) -> 2" 2 "$status_empty"
  else
    mkdir -p "$fixture/rust/src"
  fi

  status_usage=$("$CHECK_BINARIES" --bogus-flag > /dev/null 2>&1; echo $?)
  assert_exit "contract: usage error -> 64" 64 "$status_usage"

  if sha_tool_present; then
    build_matching_fixture "$fixture" > /dev/null
    status_ok=$("$CHECK_BINARIES" --tui-root "$fixture" > /dev/null 2>&1; echo $?)
    assert_exit "contract: all match -> 0" 0 "$status_ok"

    bin_name="$(bin_name_for "x86_64-apple-darwin")"
    echo "tampered" > "$fixture/bin/x86_64-apple-darwin/$bin_name"
    status_mismatch=$("$CHECK_BINARIES" --tui-root "$fixture" > /dev/null 2>&1; echo $?)
    assert_exit "contract: real mismatch -> 1" 1 "$status_mismatch"
  fi

  rm -rf "$fixture"
}

test_empty_state
test_bin_deleted_after_being_committed
test_shallow_clone_guard_unavailable
test_not_a_git_repo_guard_unavailable
test_tui_root_missing_value
test_tui_root_with_hash_in_path
test_exit_code_contract
if sha_tool_present; then
  test_no_sha_tool
  test_binaries_present_manifest_absent
  test_one_binary_stale
  test_src_hash_mismatch
  test_all_match
else
  echo "SKIPPING sha-tool-dependent tests: no SHA-256 tool on this machine's PATH"
fi

echo
echo "check-binaries.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
