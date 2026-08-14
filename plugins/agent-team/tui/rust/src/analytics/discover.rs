// The only filesystem access in E7: project_dir_for (port of the JS
// dash-replacement rule), the recursive .jsonl walk, file reads, and a
// typed DiscoveryError. Never parses a line, never computes a cost, never
// formats a message for the user — see docs/architecture-e7.md's
// dependency table. Never a `std::fs` write API.

use crate::analytics::parse::RawFile;
use std::io;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

/// A typed filesystem failure. `MissingProjectDir` and an empty-but-present
/// directory (`discover`'s `Ok` with zero files) are kept as two distinct
/// outcomes deliberately — architecture-e7.md flags collapsing them as the
/// thing a careless implementation gets wrong; FR-5 requires the screen to
/// render them differently.
#[derive(Debug, PartialEq, Eq, Clone)]
pub enum DiscoveryError {
    MissingProjectDir(PathBuf),
    PermissionDenied(PathBuf),
    Io(PathBuf, io::ErrorKind),
}

/// A file's contents plus the path relative to the project dir, both owned
/// so this can outlive the walk. `parse::RawFile` borrows from these.
#[derive(Debug)]
pub struct LoadedFile {
    pub rel_path: String,
    pub contents: String,
}

#[derive(Debug)]
pub struct Discovered {
    pub files: Vec<LoadedFile>,
    pub read_at: SystemTime,
}

impl Discovered {
    /// Borrows into the shape `analytics::parse::parse` takes. Kept as a
    /// method here (not on `parse`) so `discover.rs` is the only module
    /// that constructs a `RawFile` from real files — parse.rs stays a pure
    /// function of borrowed strings.
    pub fn as_raw_files(&self) -> Vec<RawFile<'_>> {
        self.files
            .iter()
            .map(|f| RawFile {
                rel_path: &f.rel_path,
                contents: &f.contents,
            })
            .collect()
    }
}

/// Claude Code stores a project's transcripts under a directory named after
/// the project path with every non-alphanumeric byte replaced by a dash —
/// port of measure-tokens.js's `projectDirFor`.
pub fn project_dir_for(home: &Path, cwd: &str) -> PathBuf {
    let mangled: String = cwd
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect();
    home.join(".claude").join("projects").join(mangled)
}

/// Existence is checked *before* the walk, on purpose: an empty walk result
/// must never stand in for a missing directory (architecture-e7.md, "The
/// distinction that will be got wrong").
pub fn discover(project_dir: &Path) -> Result<Discovered, DiscoveryError> {
    if !project_dir.exists() {
        return Err(DiscoveryError::MissingProjectDir(project_dir.to_path_buf()));
    }

    let mut files = Vec::new();
    walk(project_dir, project_dir, &mut files)?;

    Ok(Discovered {
        files,
        read_at: SystemTime::now(),
    })
}

fn walk(root: &Path, dir: &Path, out: &mut Vec<LoadedFile>) -> Result<(), DiscoveryError> {
    let entries = std::fs::read_dir(dir).map_err(|e| classify(dir, e))?;
    for entry in entries {
        let entry = entry.map_err(|e| classify(dir, e))?;
        let path = entry.path();
        if path.is_dir() {
            walk(root, &path, out)?;
        } else if path.extension().map(|e| e == "jsonl").unwrap_or(false) {
            let contents = std::fs::read_to_string(&path).map_err(|e| classify(&path, e))?;
            let rel_path = path
                .strip_prefix(root)
                .unwrap_or(&path)
                .to_string_lossy()
                .replace('\\', "/");
            out.push(LoadedFile { rel_path, contents });
        }
    }
    Ok(())
}

fn classify(path: &Path, e: io::Error) -> DiscoveryError {
    if e.kind() == io::ErrorKind::PermissionDenied {
        DiscoveryError::PermissionDenied(path.to_path_buf())
    } else {
        DiscoveryError::Io(path.to_path_buf(), e.kind())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn tempdir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("agent-team-tui-discover-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn project_dir_for_replaces_non_alphanumeric_bytes_with_dashes() {
        let home = Path::new("/home/user");
        let got = project_dir_for(home, "D:/Agent-Team");
        assert_eq!(
            got,
            home.join(".claude").join("projects").join("D--Agent-Team")
        );
    }

    #[test]
    fn missing_directory_is_a_distinct_outcome_from_an_empty_one() {
        let root = tempdir("missing");
        let missing = root.join("does-not-exist");
        let err = discover(&missing).unwrap_err();
        assert_eq!(err, DiscoveryError::MissingProjectDir(missing));
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn empty_but_present_directory_is_ok_with_zero_files_not_an_error() {
        let root = tempdir("empty");
        let result = discover(&root).expect("an existing empty dir is not an error");
        assert!(result.files.is_empty());
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn walk_finds_jsonl_files_recursively_and_reads_their_contents() {
        let root = tempdir("walk");
        fs::write(root.join("a.jsonl"), "line one").unwrap();
        fs::create_dir_all(root.join("a/subagents")).unwrap();
        fs::write(root.join("a/subagents/b.jsonl"), "line two").unwrap();
        fs::write(root.join("ignored.txt"), "not jsonl").unwrap();

        let result = discover(&root).unwrap();
        assert_eq!(result.files.len(), 2);
        let mut rels: Vec<&str> = result.files.iter().map(|f| f.rel_path.as_str()).collect();
        rels.sort();
        assert_eq!(rels, vec!["a.jsonl", "a/subagents/b.jsonl"]);
        fs::remove_dir_all(&root).ok();
    }
}
