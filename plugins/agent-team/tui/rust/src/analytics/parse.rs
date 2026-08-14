// Pure: given (relative_path, &str contents) pairs, produce sessions, agent
// rows and a ParseReport. No filesystem, no terminal — see
// docs/architecture-e7.md's dependency table. `is_subagent`,
// `session_id_for`, line skipping, aggregation and ordering all live here,
// reproducing measure-tokens.js's `collect()` deliberately (ADR-0007(b)).

use crate::analytics::model::{AgentRow, Bucket, FileFailure, ParseReport, Session, Usage};
use crate::analytics::rates::{context_of, tier_of, Rates};
use serde::Deserialize;
use std::collections::HashMap;

/// One transcript file's path (relative to the project dir, `/`-separated)
/// and its raw contents. `parse` never touches a filesystem — `discover.rs`
/// is what turns real files into these.
pub struct RawFile<'a> {
    pub rel_path: &'a str,
    pub contents: &'a str,
}

#[derive(Debug, Deserialize)]
struct Message {
    #[serde(default)]
    usage: Option<Usage>,
    #[serde(default)]
    model: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Record {
    #[serde(default)]
    message: Option<Message>,
    #[serde(default)]
    #[serde(rename = "attributionAgent")]
    attribution_agent: Option<String>,
}

/// A transcript under a `subagents/` path segment (not filename) belongs to
/// a delegated context. Mirrors measure-tokens.js's `isSubagent`.
fn is_subagent(rel_path: &str) -> bool {
    rel_path.split('/').any(|seg| seg == "subagents")
}

/// The session a transcript belongs to is the first path segment, with a
/// top-level main transcript's `.jsonl` suffix dropped. Mirrors
/// measure-tokens.js's `sessionIdFor`.
fn session_id_for(rel_path: &str) -> String {
    let first = rel_path.split('/').next().unwrap_or(rel_path);
    first.strip_suffix(".jsonl").unwrap_or(first).to_string()
}

/// Internal accumulator for one (agent, model) row — a running sum, not the
/// public `AgentRow` shape, so `finalise` is the only place that produces
/// the public struct.
#[derive(Default)]
struct RowAcc {
    calls: u64,
    cache_read: u64,
    cache_write: u64,
    output: u64,
    cost: f64,
}

#[derive(Default)]
struct BucketAcc {
    calls: u64,
    cost: f64,
    output: u64,
    cache_read: u64,
    cache_write: u64,
    context_sum: u64,
    context_max: u64,
}

impl BucketAcc {
    fn finalise(self) -> Bucket {
        let avg_context = if self.calls > 0 {
            self.context_sum as f64 / self.calls as f64
        } else {
            0.0
        };
        Bucket {
            calls: self.calls,
            cost: self.cost,
            output: self.output,
            cache_read: self.cache_read,
            cache_write: self.cache_write,
            avg_context,
            max_context: self.context_max,
        }
    }
}

struct SessionAcc {
    main: BucketAcc,
    sub: BucketAcc,
    by_agent: HashMap<(String, String), RowAcc>,
    valid_lines: usize,
}

fn add_to_row(
    map: &mut HashMap<(String, String), RowAcc>,
    agent: &str,
    model: &str,
    usage: &Usage,
    cost: f64,
) {
    let key = (agent.to_string(), model.to_string());
    let row = map.entry(key).or_default();
    row.calls += 1;
    row.cache_read += usage.cache_read_input_tokens;
    row.cache_write += usage.cache_creation_input_tokens;
    row.output += usage.output_tokens;
    row.cost += cost;
}

/// Cost desc, then calls desc — mirrors measure-tokens.js's `sortedRows`.
/// The fixture is constructed so no two rows tie on both fields (ADR-0007).
fn sorted_rows(map: HashMap<(String, String), RowAcc>) -> Vec<AgentRow> {
    let mut rows: Vec<AgentRow> = map
        .into_iter()
        .map(|((agent, model), acc)| AgentRow {
            agent,
            model,
            calls: acc.calls,
            cache_read: acc.cache_read,
            cache_write: acc.cache_write,
            output: acc.output,
            cost: acc.cost,
        })
        .collect();
    rows.sort_by(|a, b| {
        b.cost
            .partial_cmp(&a.cost)
            .unwrap()
            .then(b.calls.cmp(&a.calls))
    });
    rows
}

/// O(n) in total input bytes; one pass per line, hash-map aggregation — see
/// docs/architecture-e7.md's complexity note. No nested scan over rows.
pub fn parse(files: &[RawFile<'_>], rates: &Rates) -> (Vec<Session>, ParseReport) {
    let mut sessions: HashMap<String, SessionAcc> = HashMap::new();
    let mut report = ParseReport::default();

    for file in files {
        let id = session_id_for(file.rel_path);
        let sub = is_subagent(file.rel_path);
        let session = sessions.entry(id).or_insert_with(|| SessionAcc {
            main: BucketAcc::default(),
            sub: BucketAcc::default(),
            by_agent: HashMap::new(),
            valid_lines: 0,
        });

        for line in file.contents.split('\n') {
            if line.trim().is_empty() {
                continue;
            }
            // A transcript can be appended to live; a half-written final
            // line is normal, not a reason to abort the whole file — the
            // line is skipped, counted, and parsing continues
            // (measure-tokens.js's `collect()`, ADR-0007(b)).
            let record: Record = match serde_json::from_str(line) {
                Ok(r) => r,
                Err(_) => {
                    report.malformed_lines += 1;
                    continue;
                }
            };

            let usage = match record.message.as_ref().and_then(|m| m.usage) {
                Some(u) => u,
                None => continue, // no usage: skipped silently, not an error
            };

            // A missing OR empty-string `model` key becomes the literal
            // `(unknown model)`, matching measure-tokens.js's normalisation —
            // deliberately reproduced, not "fixed" (ADR-0007(b)). JS uses
            // `record.message.model || '(unknown model)'` (measure-tokens.js),
            // and `||` is falsy-triggered: it fires on `""` as well as on a
            // missing/null key, so the empty-string case must fall back too.
            let model = record
                .message
                .as_ref()
                .and_then(|m| m.model.clone())
                .filter(|m| !m.is_empty())
                .unwrap_or_else(|| "(unknown model)".to_string());
            let tier = tier_of(&model);
            let cost = rates.cost_of(tier, &usage);
            let ctx = context_of(&usage);

            let bucket = if sub {
                &mut session.sub
            } else {
                &mut session.main
            };
            bucket.calls += 1;
            bucket.cost += cost;
            bucket.output += usage.output_tokens;
            bucket.cache_read += usage.cache_read_input_tokens;
            bucket.cache_write += usage.cache_creation_input_tokens;
            bucket.context_sum += ctx;
            if ctx > bucket.context_max {
                bucket.context_max = ctx;
            }
            session.valid_lines += 1;

            // Most subagent records carry attributionAgent, but a record
            // missing OR carrying an empty string is still delegated spend
            // and falls back on `sub`, not on a constant — the same rule
            // measure-tokens.js applies, and for the same reason (its own
            // comment: billing unattributed subagent spend to main would
            // silently disagree with the session's own main/sub buckets). JS
            // uses `record.attributionAgent || (...)` (measure-tokens.js),
            // and `||` is falsy-triggered: it fires on `""` as well as on a
            // missing/null key, so the empty-string case must fall back too.
            let agent_key = record
                .attribution_agent
                .clone()
                .filter(|a| !a.is_empty())
                .unwrap_or_else(|| {
                    if sub {
                        "(unattributed subagent)".to_string()
                    } else {
                        "(main context)".to_string()
                    }
                });
            add_to_row(&mut session.by_agent, &agent_key, &model, &usage, cost);
        }

        if session.valid_lines == 0 {
            let already = report.failed_files.iter().any(|(f, _)| f == file.rel_path);
            if !already {
                report
                    .failed_files
                    .push((file.rel_path.to_string(), FileFailure::NoValidLines));
            }
        }
    }

    // A session with zero valid calls in both buckets is filtered out
    // entirely, matching measure-tokens.js's `.filter(s => s.main.calls >
    // 0 || s.sub.calls > 0)`.
    let mut out: Vec<Session> = sessions
        .into_iter()
        .filter(|(_, acc)| acc.main.calls > 0 || acc.sub.calls > 0)
        .map(|(id, acc)| {
            let main = acc.main.finalise();
            let sub = acc.sub.finalise();
            let total_cost = main.cost + sub.cost;
            let sub_share = if total_cost != 0.0 {
                sub.cost / total_cost
            } else {
                0.0
            };
            Session {
                id,
                by_agent: sorted_rows(acc.by_agent),
                main,
                sub,
                total_cost,
                sub_share,
            }
        })
        .collect();

    // Most-expensive session first, matching measure-tokens.js's own sort
    // and this screen's settled session scope (docs/plan-e7.md).
    out.sort_by(|a, b| b.total_cost.partial_cmp(&a.total_cost).unwrap());

    (out, report)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rates() -> Rates {
        Rates::load()
    }

    fn line(model: &str, input: u64, output: u64, attribution: Option<&str>) -> String {
        let attr = match attribution {
            Some(a) => format!(r#","attributionAgent":"{a}""#),
            None => String::new(),
        };
        format!(
            r#"{{"message":{{"model":"{model}","usage":{{"input_tokens":{input},"output_tokens":{output},"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}}{attr}}}"#
        )
    }

    #[test]
    fn subagent_path_segment_attributes_calls_to_sub_not_main() {
        let files = [RawFile {
            rel_path: "sess1/subagents/agentA.jsonl",
            contents: &line("claude-sonnet-5", 1000, 100, Some("agent-team:implementer")),
        }];
        let (sessions, _) = parse(&files, &rates());
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].sub.calls, 1);
        assert_eq!(sessions[0].main.calls, 0);
    }

    #[test]
    fn unattributed_subagent_call_gets_the_fallback_label() {
        let files = [RawFile {
            rel_path: "sess1/subagents/orphan.jsonl",
            contents: &line("claude-haiku-4-5", 1000, 100, None),
        }];
        let (sessions, _) = parse(&files, &rates());
        assert_eq!(sessions[0].by_agent[0].agent, "(unattributed subagent)");
    }

    #[test]
    fn main_context_call_with_no_attribution_gets_main_context_label() {
        let files = [RawFile {
            rel_path: "sess1.jsonl",
            contents: &line("claude-opus-5", 1000, 100, None),
        }];
        let (sessions, _) = parse(&files, &rates());
        assert_eq!(sessions[0].by_agent[0].agent, "(main context)");
    }

    #[test]
    fn unknown_model_bills_at_opus_tier() {
        let cheap = {
            let files = [RawFile {
                rel_path: "sess1.jsonl",
                contents: &line("totally-unknown-model", 1_000_000, 0, None),
            }];
            parse(&files, &rates()).0[0].main.cost
        };
        let opus = {
            let files = [RawFile {
                rel_path: "sess2.jsonl",
                contents: &line("claude-opus-5", 1_000_000, 0, None),
            }];
            parse(&files, &rates()).0[0].main.cost
        };
        assert!((cheap - opus).abs() < 1e-9);
    }

    #[test]
    fn malformed_line_is_skipped_and_counted_not_aborting_the_file() {
        let contents = format!("not json\n{}", line("claude-opus-5", 1000, 10, None));
        let files = [RawFile {
            rel_path: "sess1.jsonl",
            contents: &contents,
        }];
        let (sessions, report) = parse(&files, &rates());
        assert_eq!(report.malformed_lines, 1);
        assert_eq!(
            sessions[0].main.calls, 1,
            "the valid line after it must still be counted"
        );
    }

    #[test]
    fn zero_jsonl_files_produce_zero_sessions() {
        let files: [RawFile; 0] = [];
        let (sessions, report) = parse(&files, &rates());
        assert!(sessions.is_empty());
        assert_eq!(report.malformed_lines, 0);
    }

    #[test]
    fn one_main_only_transcript_has_zero_sub_calls_and_full_main_split() {
        let files = [RawFile {
            rel_path: "sess1.jsonl",
            contents: &line("claude-opus-5", 1000, 100, None),
        }];
        let (sessions, _) = parse(&files, &rates());
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].sub.calls, 0);
        assert_eq!(sessions[0].sub_share, 0.0);
    }

    #[test]
    fn many_sessions_each_produce_their_own_entry() {
        let l = line("claude-opus-5", 1000, 100, None);
        let files = [
            RawFile {
                rel_path: "sess1.jsonl",
                contents: &l,
            },
            RawFile {
                rel_path: "sess2.jsonl",
                contents: &l,
            },
            RawFile {
                rel_path: "sess3.jsonl",
                contents: &l,
            },
        ];
        let (sessions, _) = parse(&files, &rates());
        assert_eq!(sessions.len(), 3);
    }

    #[test]
    fn record_missing_usage_is_skipped_silently() {
        let contents = r#"{"message":{"model":"claude-opus-5"}}"#;
        let files = [RawFile {
            rel_path: "sess1.jsonl",
            contents,
        }];
        let (sessions, report) = parse(&files, &rates());
        assert!(sessions.is_empty());
        assert_eq!(report.malformed_lines, 0);
    }

    /// The far-too-many NFR (FR-1 edge, docs/prd-analytics-tui.md): a
    /// single 50,000-line transcript parses within 5s on open. String built
    /// in memory — this measures parsing, not disk (architecture-e7.md).
    /// Run under `cargo test --release`; unoptimized this is far slower and
    /// not representative.
    #[test]
    fn fifty_thousand_lines_parse_within_five_seconds() {
        let one = line("claude-sonnet-5", 1000, 100, Some("agent-team:implementer"));
        let mut contents = String::with_capacity(one.len() * 50_000);
        for _ in 0..50_000 {
            contents.push_str(&one);
            contents.push('\n');
        }
        let files = [RawFile {
            rel_path: "big-session.jsonl",
            contents: &contents,
        }];
        let start = std::time::Instant::now();
        let (sessions, _report) = parse(&files, &rates());
        let elapsed = start.elapsed();
        assert_eq!(sessions[0].main.calls, 50_000);
        assert!(
            elapsed.as_secs_f64() < 5.0,
            "parse of 50,000 lines took {elapsed:?}, budget is 5s"
        );
    }

    #[test]
    fn record_missing_model_renders_as_unknown_model() {
        let contents = r#"{"message":{"usage":{"input_tokens":10,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#;
        let files = [RawFile {
            rel_path: "sess1.jsonl",
            contents,
        }];
        let (sessions, _) = parse(&files, &rates());
        assert_eq!(sessions[0].by_agent[0].model, "(unknown model)");
    }
}
