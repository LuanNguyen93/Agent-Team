// The typed result of a parse: Session, Bucket, AgentRow, ParseReport. No
// I/O of any kind, no ratatui type — see docs/architecture-e7.md's
// dependency table. Plain structs only.

/// The subset of a transcript record's `usage` object the arithmetic
/// needs. Mirrors measure-tokens.js's field names 1:1 (snake_case, as the
/// JSONL itself uses) so `serde` can deserialize a record's `usage` object
/// directly with no renaming.
#[derive(Debug, PartialEq, Clone, Copy, Default, serde::Deserialize)]
pub struct Usage {
    #[serde(default)]
    pub input_tokens: u64,
    #[serde(default)]
    pub output_tokens: u64,
    #[serde(default)]
    pub cache_creation_input_tokens: u64,
    #[serde(default)]
    pub cache_read_input_tokens: u64,
}

#[derive(Debug, PartialEq, Clone, Default)]
pub struct Bucket {
    pub calls: u64,
    pub cost: f64,
    pub output: u64,
    pub cache_read: u64,
    pub cache_write: u64,
    pub avg_context: f64,
    pub max_context: u64,
}

#[derive(Debug, PartialEq, Clone)]
pub struct AgentRow {
    pub agent: String,
    pub model: String,
    pub calls: u64,
    pub cache_read: u64,
    pub cache_write: u64,
    pub output: u64,
    pub cost: f64,
}

#[derive(Debug, PartialEq, Clone)]
pub struct Session {
    pub id: String,
    pub main: Bucket,
    pub sub: Bucket,
    pub by_agent: Vec<AgentRow>,
    pub total_cost: f64,
    pub sub_share: f64,
}

/// A single file that produced zero valid lines — FR-5's "listed as a
/// failed session with a reason", not folded into a generic parse error.
#[derive(Debug, PartialEq, Clone)]
pub enum FileFailure {
    NoValidLines,
}

/// Counts and per-file facts about a parse, surfaced as a status line — a
/// bad line is data about the transcript, not a failure of parsing it
/// (docs/architecture-e7.md "Error-state propagation").
#[derive(Debug, PartialEq, Clone, Default)]
pub struct ParseReport {
    pub malformed_lines: usize,
    pub failed_files: Vec<(String, FileFailure)>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bucket_default_is_all_zero() {
        let b = Bucket::default();
        assert_eq!(b.calls, 0);
        assert_eq!(b.cost, 0.0);
        assert_eq!(b.max_context, 0);
    }

    #[test]
    fn session_and_agent_row_construct_and_compare_by_equality() {
        let row = AgentRow {
            agent: "(main context)".to_string(),
            model: "claude-opus-5".to_string(),
            calls: 1,
            cache_read: 100,
            cache_write: 10,
            output: 50,
            cost: 1.5,
        };
        let session = Session {
            id: "aaaa".to_string(),
            main: Bucket {
                calls: 1,
                cost: 1.5,
                output: 50,
                cache_read: 100,
                cache_write: 10,
                avg_context: 110.0,
                max_context: 110,
            },
            sub: Bucket::default(),
            by_agent: vec![row.clone()],
            total_cost: 1.5,
            sub_share: 0.0,
        };
        assert_eq!(session.by_agent[0], row);
        assert_eq!(session.total_cost, 1.5);

        let report = ParseReport {
            malformed_lines: 1,
            failed_files: vec![("x.jsonl".to_string(), FileFailure::NoValidLines)],
        };
        assert_eq!(report.malformed_lines, 1);
    }
}
