#!/usr/bin/env bash
# Verifies that the five committed TUI binaries under bin/ still match
# bin/MANIFEST: each binary's own SHA-256, and the srcHash every MANIFEST line
# carries against the source tree that would produce it. This is CI's blocking
# gate against a binary that has silently lagged its source (docs/adr/0002).
#
# Exit codes (the only three-plus-usage contract a caller should rely on):
#   0  - every triple's checksum and srcHash match MANIFEST, OR the check was
#        skipped because no SHA-256 tool is on PATH (stdout says SKIPPED, with
#        the reason - never a silent pass, per CLAUDE.md).
#   1  - a real, blocking mismatch: a binary's checksum does not match, the
#        recomputed srcHash does not match MANIFEST's, OR bin/MANIFEST is
#        missing/unreadable while at least one triple's binary IS present.
#        That last case is not "nothing released yet" - the repo genuinely
#        has unverified binaries sitting in it (a bad rebase, a mis-resolved
#        conflict, or someone deleting MANIFEST to silence this gate), and
#        treating it as the empty state would let that merge green.
#   2  - genuinely empty: no bin/ directory, no MANIFEST, AND no binary
#        present for any triple. Deliberately distinct from 1 - the user's
#        call, authorised as a spec change from the story's original "empty
#        state -> exit 1" wording, because a PR workflow that is red until the
#        first release exists (and the first release is gated behind a PR)
#        cannot ever go green.
#   64 - usage error (sysexits.h EX_USAGE): a bad or incomplete flag. Kept
#        numerically distinct from the empty state (2) specifically so a
#        caller CAN tell "you invoked me wrong" apart from "nothing has been
#        released yet" - the two used to share exit 2, which made that
#        distinction impossible to act on.
#
# ALGORITHM for srcHash (mirrored in tui/rust/build.rs - keep both in sync):
#   Collect every file under rust/src/** (recursively) plus Cargo.toml and
#   Cargo.lock, as paths relative to rust/ with `/` separators, sort those
#   relative-path STRINGS byte-wise (LC_ALL=C), concatenate the raw byte
#   contents of the files in that order, and take the SHA-256 of the result.
#   Byte-wise string sort, not a component-wise path sort: "src/ui.rs" and
#   "src/ui/tree.rs" must land in the same relative order on both sides, and
#   a sort that compares path *components* (as Rust's PathBuf Ord does by
#   default) disagrees with a plain byte sort as soon as a file and a
#   same-named directory coexist. See tests/src-hash-consistency.test.sh.

set -u

# --tui-root PATH overrides the resolved root, for the fixture-driven test
# suite in tests/*.test.sh; CI and normal use rely on the default (the
# directory this script lives in).
# --print-src-hash prints only the recomputed srcHash and exits, skipping the
# bin/MANIFEST comparison entirely - used by
# tests/src-hash-consistency.test.sh to compare this script's recomputation
# directly against build.rs's embedded value, on the same source tree.
TUI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRINT_SRC_HASH=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tui-root)
      if [ "$#" -lt 2 ]; then
        echo "usage: check-binaries.sh [--tui-root PATH] [--print-src-hash]" >&2
        exit 64
      fi
      TUI_ROOT="$(cd "$2" && pwd)"
      shift 2
      ;;
    --print-src-hash)
      PRINT_SRC_HASH=1
      shift
      ;;
    *)
      echo "usage: check-binaries.sh [--tui-root PATH] [--print-src-hash]" >&2
      exit 64
      ;;
  esac
done

BIN_DIR="$TUI_ROOT/bin"
MANIFEST="$BIN_DIR/MANIFEST"
RUST_DIR="$TUI_ROOT/rust"

TRIPLES="x86_64-pc-windows-msvc x86_64-apple-darwin aarch64-apple-darwin x86_64-unknown-linux-musl aarch64-unknown-linux-musl"

binary_name_for() {
  case "$1" in
    x86_64-pc-windows-msvc) echo "agent-team-tui.exe" ;;
    *) echo "agent-team-tui" ;;
  esac
}

# --- Step 1: the genuinely empty state (exit 2, non-blocking) is narrower
# than "MANIFEST is missing" - it also requires that NO triple has a binary
# present. A populated bin/ with a missing or unreadable MANIFEST is not
# "nothing released yet"; it is a mismatch (exit 1, via Step 4's MISSING
# handling below), because the repo has unverified binaries sitting in it.
# Skipped entirely when we were only asked to print the srcHash, which needs
# neither bin/ nor MANIFEST to exist.
if [ "$PRINT_SRC_HASH" -ne 1 ]; then
  ANY_BINARY_PRESENT=0
  for triple in $TRIPLES; do
    bin_name="$(binary_name_for "$triple")"
    if [ -f "$BIN_DIR/$triple/$bin_name" ]; then
      ANY_BINARY_PRESENT=1
      break
    fi
  done

  if [ ! -f "$MANIFEST" ] && [ "$ANY_BINARY_PRESENT" -ne 1 ]; then
    # Emptiness alone does not prove bootstrap. `git rm -r bin` (or a merge
    # conflict resolved the wrong way) after a real release returns the repo
    # to exactly this state, and without a guard the gate would report a
    # clean bootstrap instead of a deleted release (ADR-0002, "Why exit 2 is
    # non-blocking, and the guard rail it needs"). `git log -- bin` is the
    # offline, local answer: any commit that ever touched bin/ means this is
    # a deletion (exit 1, blocking), not a bootstrap (exit 2).
    #
    # The guard itself can fail to answer - no git, not a git working tree,
    # or a shallow clone (whose truncated history makes `git log -- bin`
    # return nothing regardless of the real answer). In every one of those
    # cases we report the guard UNAVAILABLE and do NOT grant the non-blocking
    # exit 2 - CLAUDE.md's "absent must report as absent, not as a pass"
    # applies to the guard itself, not only to the SHA-256 tool check above.
    # An unavailable guard is not a clean bootstrap, so it falls back to the
    # same blocking exit 1 as a confirmed deletion: both mean "this needs a
    # human to look, it is not safely a first release."
    GUARD_STATE=""
    if ! command -v git >/dev/null 2>&1; then
      GUARD_STATE="unavailable: git is not on PATH"
    elif ! git -C "$TUI_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      GUARD_STATE="unavailable: $TUI_ROOT is not inside a git working tree"
    elif [ "$(git -C "$TUI_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
      GUARD_STATE="unavailable: this is a shallow git clone - full history is required (fetch-depth: 0)"
    elif [ -n "$(git -C "$TUI_ROOT" log --oneline -- bin 2>/dev/null)" ]; then
      GUARD_STATE="deletion: bin/ appears in git history but is absent from the working tree"
    else
      GUARD_STATE="never-existed: git history has no commit touching bin/"
    fi

    case "$GUARD_STATE" in
      never-existed:*)
        echo "check-binaries: bin/ or bin/MANIFEST is missing - nothing has been released yet ($GUARD_STATE)."
        for triple in $TRIPLES; do
          echo "MISSING: $triple"
        done
        exit 2
        ;;
      deletion:*)
        echo "check-binaries: bin/ is empty, but git history shows a release existed before ($GUARD_STATE). This is a DELETION, not a bootstrap - blocking."
        for triple in $TRIPLES; do
          echo "MISSING: $triple"
        done
        exit 1
        ;;
      *)
        echo "check-binaries: GUARD_UNAVAILABLE - cannot confirm bin/ has never existed ($GUARD_STATE). Treating as blocking rather than assuming a clean bootstrap."
        for triple in $TRIPLES; do
          echo "MISSING: $triple"
        done
        exit 1
        ;;
    esac
  fi
fi

# --- Step 2: find a SHA-256 tool. Absent must report as absent, not a pass. ---
sha256_of() {
  # $1 = file path
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    return 127
  fi
}

sha256_of_concat() {
  # $1 = a file containing a list of file paths, one per line, already in the
  # desired order. Hashes the CONTENTS of those files concatenated in that
  # order - not the list file itself, which is why this reads it line by line
  # rather than `cat "$1" | sha256sum`.
  if command -v sha256sum >/dev/null 2>&1; then
    while IFS= read -r f; do cat "$f"; done < "$1" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    while IFS= read -r f; do cat "$f"; done < "$1" | shasum -a 256 | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    while IFS= read -r f; do cat "$f"; done < "$1" | openssl dgst -sha256 | awk '{print $NF}'
  else
    return 127
  fi
}

if ! command -v sha256sum >/dev/null 2>&1 \
  && ! command -v shasum >/dev/null 2>&1 \
  && ! command -v openssl >/dev/null 2>&1; then
  echo "SKIPPED: no SHA-256 tool (sha256sum, shasum, or openssl) found on PATH - binary and srcHash staleness were not checked."
  exit 0
fi

# --- Step 3: recompute srcHash the same way build.rs does. ---
# Relative paths are built with parameter expansion (`${f#"$RUST_DIR/"}`),
# not `sed`, so a RUST_DIR containing a regex-special character such as `#`
# cannot corrupt the stripped path.
#
# Two known, currently-unreachable divergences from build.rs, noted rather
# than silenced:
#   - `find -type f` (here) does not follow symlinks; Rust's `Path::is_file()`
#     (build.rs) does. A symlink under rust/src/ would be hashed on one side
#     and skipped on the other. Nothing in this repo puts one there today.
#   - This guards Cargo.toml/Cargo.lock with `[ -f ]` and silently omits them
#     if absent; build.rs panics instead. A crate with no Cargo.toml does not
#     build far enough to run build.rs, so this is not reachable either.
FILELIST="$(mktemp)"
trap 'rm -f "$FILELIST"' EXIT

RELLIST="$(mktemp)"
{
  if [ -d "$RUST_DIR/src" ]; then
    find "$RUST_DIR/src" -type f | while IFS= read -r f; do
      printf '%s\n' "${f#"$RUST_DIR"/}"
    done
  fi
  [ -f "$RUST_DIR/Cargo.toml" ] && echo "Cargo.toml"
  [ -f "$RUST_DIR/Cargo.lock" ] && echo "Cargo.lock"
} | LC_ALL=C sort > "$RELLIST"

while IFS= read -r rel; do
  printf '%s\n' "$RUST_DIR/$rel"
done < "$RELLIST" > "$FILELIST"
rm -f "$RELLIST"

RECOMPUTED_SRC_HASH="$(sha256_of_concat "$FILELIST")"

if [ "$PRINT_SRC_HASH" -eq 1 ]; then
  echo "$RECOMPUTED_SRC_HASH"
  exit 0
fi

# --- Step 4: compare each triple's binary checksum and srcHash to MANIFEST. ---
MISSING=""
CHECKSUM_MISMATCH=""
SRC_HASH_MISMATCH=0

for triple in $TRIPLES; do
  bin_name="$(binary_name_for "$triple")"
  bin_path="$BIN_DIR/$triple/$bin_name"
  # MANIFEST itself may be absent here (Step 1 only rules out the case where
  # it's absent AND no binary exists anywhere) - 2>/dev/null keeps that a
  # quiet MISSING rather than a stray "No such file or directory".
  line="$(grep "^$triple	" "$MANIFEST" 2>/dev/null || true)"

  if [ ! -f "$bin_path" ] || [ -z "$line" ]; then
    MISSING="$MISSING $triple"
    continue
  fi

  manifest_sha256="$(printf '%s' "$line" | awk -F'\t' '{print $2}')"
  manifest_src_hash="$(printf '%s' "$line" | awk -F'\t' '{print $3}')"

  actual_sha256="$(sha256_of "$bin_path")"
  if [ "$actual_sha256" != "$manifest_sha256" ]; then
    CHECKSUM_MISMATCH="$CHECKSUM_MISMATCH $triple"
  fi

  if [ "$manifest_src_hash" != "$RECOMPUTED_SRC_HASH" ]; then
    SRC_HASH_MISMATCH=1
  fi
done

if [ -n "$MISSING" ]; then
  echo "check-binaries: one or more triples are missing a binary or a MANIFEST line."
  for triple in $MISSING; do
    echo "MISSING: $triple"
  done
  exit 1
fi

FAILED=0

if [ -n "$CHECKSUM_MISMATCH" ]; then
  echo "check-binaries: committed binary bytes do not match MANIFEST's checksum."
  for triple in $CHECKSUM_MISMATCH; do
    echo "CHECKSUM_MISMATCH: $triple"
  done
  FAILED=1
fi

if [ "$SRC_HASH_MISMATCH" -eq 1 ]; then
  echo "check-binaries: recomputed srcHash ($RECOMPUTED_SRC_HASH) does not match MANIFEST - every triple was built from different source and is stale."
  for triple in $TRIPLES; do
    echo "SRC_HASH_STALE: $triple"
  done
  FAILED=1
fi

if [ "$FAILED" -eq 1 ]; then
  exit 1
fi

echo "OK: all five triples match MANIFEST (checksum and srcHash)."
exit 0
