// Embeds three values as compile-time env vars, read back in `src/main.rs` via
// `env!(...)` for `--build-info`:
//
//   SRC_HASH    - see the ALGORITHM comment below. This side must stay in
//                 lockstep with `tui/check-binaries.sh`'s bash implementation
//                 of the same rule - both carry the same comment on purpose.
//   BUILD_TARGET - the target triple cargo is building for.
//   BUILD_DATE   - UTC date the binary was built, `YYYY-MM-DD`.
//
// ALGORITHM (mirrored in tui/check-binaries.sh - keep both in sync):
//   Collect every file under `rust/src/**` (recursively) plus `Cargo.toml` and
//   `Cargo.lock`, as paths relative to `rust/` joined with `/` (never `\`),
//   sort those relative-path STRINGS byte-wise, concatenate the raw byte
//   contents of the files in that order, and take the SHA-256 of the result.
//   Byte-wise string sort, not `Vec<PathBuf>::sort()`: `PathBuf`'s `Ord`
//   compares path *components*, which disagrees with bash's `LC_ALL=C sort`
//   (a plain byte sort) as soon as a file and a same-named directory coexist
//   - e.g. `src/ui.rs` next to `src/ui/tree.rs`. See
//   tests/src-hash-consistency.test.sh, which compares this file's output to
//   check-binaries.sh's directly.
//
// No `sha2` crate dependency: build.rs hand-rolls SHA-256 so the release
// pipeline never needs network access to fetch a hashing crate for a build
// script this small.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let src_dir = manifest_dir.join("src");

    // cargo re-runs this script whenever a file it named via
    // cargo:rerun-if-changed changes - but a file that did not exist yet
    // cannot be named. Watching the directory itself closes that gap: adding
    // a new file under src/ touches the directory's mtime, which re-triggers
    // the script even though the new file was never individually listed
    // before this run.
    println!("cargo:rerun-if-changed={}", src_dir.display());

    let mut rel_paths: Vec<String> = Vec::new();
    collect_files(&src_dir, &manifest_dir, &mut rel_paths);
    rel_paths.push("Cargo.toml".to_string());
    rel_paths.push("Cargo.lock".to_string());
    // Byte-wise string sort - see the ALGORITHM comment above.
    rel_paths.sort();

    let mut concatenated = Vec::new();
    for rel in &rel_paths {
        let full = manifest_dir.join(rel);
        // Unlike check-binaries.sh (which guards Cargo.toml/Cargo.lock with
        // `[ -f ]` and silently omits them if absent), this panics if either
        // is missing. Not reachable today - a crate with no Cargo.toml does
        // not build far enough to run this script - but noted so a future
        // change to how this script is invoked does not rediscover it as a
        // confusing build failure instead of a deliberate one.
        let bytes = fs::read(&full).unwrap_or_else(|e| panic!("reading {}: {}", full.display(), e));
        concatenated.extend_from_slice(&bytes);
        println!("cargo:rerun-if-changed={}", full.display());
    }

    let hash_hex = sha256_hex(&concatenated);
    println!("cargo:rustc-env=SRC_HASH={hash_hex}");

    let target = env::var("TARGET").unwrap_or_else(|_| "unknown-target".to_string());
    println!("cargo:rustc-env=BUILD_TARGET={target}");

    let build_date = build_date_utc();
    println!("cargo:rustc-env=BUILD_DATE={build_date}");
}

/// Recursively collects every regular file under `dir`, as `/`-joined paths
/// relative to `manifest_dir` (so they sort and print the same way
/// `check-binaries.sh` reports them, on every OS including Windows).
fn collect_files(dir: &Path, manifest_dir: &Path, out: &mut Vec<String>) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return, // src/ not created yet is a real state before the first file lands
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_files(&path, manifest_dir, out);
        } else if path.is_file() {
            // `Path::is_file()` follows symlinks; `find -type f` on the bash
            // side does not. A symlink under src/ would therefore be hashed
            // here and silently skipped there. Not reachable today - nothing
            // in this repo puts a symlink under tui/rust/src/ - but noted so
            // it is not rediscovered as a mysterious srcHash mismatch.
            let rel = path.strip_prefix(manifest_dir).unwrap_or(&path);
            let rel_str = rel
                .components()
                .map(|c| c.as_os_str().to_string_lossy().into_owned())
                .collect::<Vec<_>>()
                .join("/");
            out.push(rel_str);
        }
    }
}

fn build_date_utc() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock before epoch")
        .as_secs();
    let (y, m, d) = civil_from_days((secs / 86400) as i64);
    format!("{y:04}-{m:02}-{d:02}")
}

/// Howard Hinnant's `civil_from_days`: days-since-epoch -> (year, month, day).
/// Avoids a chrono dependency for a single date string.
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u64; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; // [0, 399]
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32; // [1, 12]
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

// --- Hand-rolled SHA-256 (FIPS 180-4), no external dependency. ---

fn sha256_hex(data: &[u8]) -> String {
    let digest = sha256(data);
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

fn sha256(data: &[u8]) -> [u8; 32] {
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    let mut msg = data.to_vec();
    let bit_len = (data.len() as u64) * 8;
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in msg.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[4 * i],
                chunk[4 * i + 1],
                chunk[4 * i + 2],
                chunk[4 * i + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let (mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh) =
            (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]);

        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = [0u8; 32];
    for (i, word) in h.iter().enumerate() {
        out[i * 4..i * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}
