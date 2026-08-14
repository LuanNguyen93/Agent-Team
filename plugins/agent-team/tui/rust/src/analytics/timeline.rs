// Pure: given jsonl files, meta.json sidecars and Rates, produce one
// SessionTimeline per session plus a ParseReport. No filesystem, no
// terminal — see docs/architecture-e7.md's dependency table, same rule
// parse.rs follows.
//
// `is_subagent`/`session_id_for` are duplicated from parse.rs rather than
// imported, per the E7-followups plan: these two are tiny (a handful of
// lines each) and coupling timeline.rs to parse.rs's module for them would
// buy nothing but a compile-time dependency neither module otherwise needs.

use crate::analytics::model::ParseReport;
use crate::analytics::parse::RawFile;
use crate::analytics::rates::{tier_of, Rates};
use crate::analytics::timeline_model::{AgentSpan, SessionTimeline};
use serde::Deserialize;
use std::collections::HashMap;

/// See timeline.rs's module comment: duplicated from parse.rs on purpose.
fn is_subagent(rel_path: &str) -> bool {
    rel_path.split('/').any(|seg| seg == "subagents")
}

/// See timeline.rs's module comment: duplicated from parse.rs on purpose.
fn session_id_for(rel_path: &str) -> String {
    let first = rel_path.split('/').next().unwrap_or(rel_path);
    first.strip_suffix(".jsonl").unwrap_or(first).to_string()
}

#[derive(Debug, Deserialize)]
struct ContentBlock {
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Message {
    #[serde(default)]
    usage: Option<crate::analytics::model::Usage>,
    #[serde(default)]
    model: Option<String>,
    #[serde(default)]
    content: Option<Vec<ContentBlock>>,
}

#[derive(Debug, Deserialize)]
struct Record {
    #[serde(default)]
    message: Option<Message>,
    #[serde(default)]
    timestamp: Option<String>,
}

/// Real sidecars on disk carry no `id` field (E7-followups real-data
/// finding) — the span id is derived from the filename stem instead, via
/// `span_id_for_meta_path`. Unknown extra fields (e.g. a future `model`)
/// must not break parsing, which `serde_json`'s default
/// deny-unknown-fields-off behaviour already gives us.
#[derive(Debug, Deserialize)]
struct MetaInfo {
    #[serde(rename = "agentType")]
    agent_type: String,
    #[serde(default)]
    description: String,
    #[serde(rename = "toolUseId", default)]
    tool_use_id: Option<String>,
    #[serde(rename = "spawnDepth", default)]
    spawn_depth: u32,
}

/// `sess1/subagents/agent-<id>.meta.json` -> `<id>`. Falls back to the
/// meta.json's own stem (minus `.meta.json`) if the `agent-` prefix is
/// absent, so an unexpected filename still yields a stable, non-empty id
/// rather than panicking.
fn span_id_for_meta_path(meta_rel_path: &str) -> String {
    let stem = meta_rel_path
        .rsplit('/')
        .next()
        .unwrap_or(meta_rel_path)
        .strip_suffix(".meta.json")
        .unwrap_or(meta_rel_path);
    stem.strip_prefix("agent-").unwrap_or(stem).to_string()
}

/// Hand-rolled RFC3339 UTC-fixed-offset parse for Claude Code's own
/// timestamp format (`YYYY-MM-DDTHH:MM:SS.sssZ`) — deliberately not the
/// `time`/`chrono` crates (not in this project's dependency list, and this
/// format is the only one ever written here). Returns `None` rather than
/// panicking on anything that does not match exactly; a malformed
/// timestamp degrades the span's start/end, it never aborts the parse.
fn parse_rfc3339_utc_ms(s: &str) -> Option<i64> {
    let b = s.as_bytes();
    if b.len() != 24
        || b[4] != b'-'
        || b[7] != b'-'
        || b[10] != b'T'
        || b[13] != b':'
        || b[16] != b':'
        || b[19] != b'.'
        || b[23] != b'Z'
    {
        return None;
    }
    let n = |a: usize, len: usize| -> Option<i64> { s.get(a..a + len)?.parse().ok() };
    let year = n(0, 4)?;
    let month = n(5, 2)?;
    let day = n(8, 2)?;
    let hour = n(11, 2)?;
    let min = n(14, 2)?;
    let sec = n(17, 2)?;
    let ms = n(20, 3)?;

    if !(1..=12).contains(&month) {
        return None;
    }
    if !(1..=days_in_month(year, month)).contains(&day) {
        return None;
    }
    // Leap seconds (:60) are rejected along with everything else out of
    // range — Claude Code's own writer never emits one, and accepting it
    // would just shift the millisecond arithmetic below by a second.
    if !(0..=23).contains(&hour) || !(0..=59).contains(&min) || !(0..=59).contains(&sec) {
        return None;
    }
    // Days since the epoch via a civil-to-days conversion (Howard Hinnant's
    // algorithm), avoiding a leap-year table by hand.
    let (y, m) = if month <= 2 {
        (year - 1, month + 12)
    } else {
        (year, month)
    };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let doy = (153 * (m - 3) + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;

    let secs_of_day = hour * 3600 + min * 60 + sec;
    Some(days * 86_400_000 + secs_of_day * 1000 + ms)
}

/// The real length of `month` in `year`, leap-year aware (`is_leap_year`
/// reuses the same 4/100/400 rule the civil-days conversion above already
/// depends on).
fn days_in_month(year: i64, month: i64) -> i64 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if is_leap_year(year) => 29,
        2 => 28,
        _ => 0,
    }
}

fn is_leap_year(year: i64) -> bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

/// One jsonl file's aggregate: what a span needs, plus the tool_use ids it
/// carries (for parent resolution) and the earliest/latest timestamp seen.
#[derive(Default)]
struct FileAgg {
    calls: u64,
    cost: f64,
    output: u64,
    cache_read: u64,
    cache_write: u64,
    start_ms: Option<i64>,
    end_ms: Option<i64>,
    tool_use_ids: Vec<String>,
}

fn aggregate_file(contents: &str, rates: &Rates, report: &mut ParseReport) -> FileAgg {
    let mut agg = FileAgg::default();
    for line in contents.split('\n') {
        if line.trim().is_empty() {
            continue;
        }
        let record: Record = match serde_json::from_str(line) {
            Ok(r) => r,
            Err(_) => {
                report.malformed_lines += 1;
                continue;
            }
        };

        if let Some(ts) = record.timestamp.as_deref().and_then(parse_rfc3339_utc_ms) {
            agg.start_ms = Some(agg.start_ms.map_or(ts, |s| s.min(ts)));
            agg.end_ms = Some(agg.end_ms.map_or(ts, |e| e.max(ts)));
        }

        if let Some(blocks) = record.message.as_ref().and_then(|m| m.content.as_ref()) {
            for block in blocks {
                if block.kind == "tool_use" {
                    if let Some(id) = &block.id {
                        agg.tool_use_ids.push(id.clone());
                    }
                }
            }
        }

        let usage = match record.message.as_ref().and_then(|m| m.usage) {
            Some(u) => u,
            None => continue,
        };
        let model = record
            .message
            .as_ref()
            .and_then(|m| m.model.clone())
            .filter(|m| !m.is_empty())
            .unwrap_or_else(|| "(unknown model)".to_string());
        let cost = rates.cost_of(tier_of(&model), &usage);

        agg.calls += 1;
        agg.cost += cost;
        agg.output += usage.output_tokens;
        agg.cache_read += usage.cache_read_input_tokens;
        agg.cache_write += usage.cache_creation_input_tokens;
    }
    agg
}

/// O(n) in total input bytes: one pass over every jsonl file to aggregate
/// per-file totals and collect tool_use ids, one pass over the meta.json
/// files to build spans, and a HashMap lookup (not a nested scan) to
/// resolve each span's parent from its `toolUseId` — see
/// docs/architecture-e7.md's complexity note.
pub fn build_timelines(
    files: &[RawFile<'_>],
    meta_files: &[RawFile<'_>],
    rates: &Rates,
) -> (Vec<SessionTimeline>, ParseReport) {
    let mut report = ParseReport::default();

    // Pass 1: aggregate every jsonl file and index which file owns which
    // tool_use id.
    let mut file_aggs: HashMap<&str, FileAgg> = HashMap::new();
    let mut tool_use_owner: HashMap<String, String> = HashMap::new();
    for file in files {
        let agg = aggregate_file(file.contents, rates, &mut report);
        for id in &agg.tool_use_ids {
            tool_use_owner.insert(id.clone(), file.rel_path.to_string());
        }
        file_aggs.insert(file.rel_path, agg);
    }

    // Pass 2: parse every meta.json, mapping its subagent jsonl file (same
    // path stem) to the span id it will get, so parent resolution and main
    // spans can be looked up by file path.
    struct MetaEntry<'a> {
        rel_path: &'a str,
        id: String,
        info: MetaInfo,
    }
    let mut metas: Vec<MetaEntry> = Vec::new();
    for meta_file in meta_files {
        match serde_json::from_str::<MetaInfo>(meta_file.contents) {
            Ok(info) => metas.push(MetaEntry {
                rel_path: meta_file.rel_path,
                id: span_id_for_meta_path(meta_file.rel_path),
                info,
            }),
            Err(_) => {
                report.malformed_lines += 1;
            }
        }
    }

    // file rel_path -> span id, so a tool_use owner file can be resolved to
    // the span that issued it. Main files map to "main"; subagent files map
    // to their meta's id.
    let mut file_to_span_id: HashMap<String, String> = HashMap::new();
    for file in files {
        if !is_subagent(file.rel_path) {
            file_to_span_id.insert(file.rel_path.to_string(), "main".to_string());
        }
    }
    for entry in &metas {
        if let Some(subagent_file) = subagent_jsonl_for(entry.rel_path) {
            file_to_span_id.insert(subagent_file, entry.id.clone());
        }
    }

    // Group main-file aggregates and meta entries by session.
    let mut sessions: HashMap<String, SessionTimeline> = HashMap::new();
    for file in files {
        if is_subagent(file.rel_path) {
            continue;
        }
        let session_id = session_id_for(file.rel_path);
        let agg = file_aggs.remove(file.rel_path).unwrap_or_default();
        let timeline = sessions
            .entry(session_id.clone())
            .or_insert_with(|| SessionTimeline {
                session_id: session_id.clone(),
                spans: Vec::new(),
            });
        timeline.spans.push(AgentSpan {
            id: "main".to_string(),
            parent_id: None,
            agent_type: "main".to_string(),
            description: "main session".to_string(),
            spawn_depth: 0,
            start_ms: agg.start_ms.unwrap_or(0),
            end_ms: agg.end_ms.unwrap_or(0),
            calls: agg.calls,
            cost: agg.cost,
            output: agg.output,
            cache_read: agg.cache_read,
            cache_write: agg.cache_write,
        });
    }

    for entry in metas {
        let session_id = session_id_for(entry.rel_path);
        let subagent_file = subagent_jsonl_for(entry.rel_path);
        let agg = subagent_file
            .as_deref()
            .and_then(|p| file_aggs.remove(p))
            .unwrap_or_default();

        // Unresolved toolUseId -> parent_id None, renders fine, never panics
        // (E7-followups plan).
        let parent_id = entry
            .info
            .tool_use_id
            .as_ref()
            .and_then(|tid| tool_use_owner.get(tid))
            .and_then(|owner_path| file_to_span_id.get(owner_path))
            .cloned();

        let timeline = sessions
            .entry(session_id.clone())
            .or_insert_with(|| SessionTimeline {
                session_id: session_id.clone(),
                spans: Vec::new(),
            });
        timeline.spans.push(AgentSpan {
            id: entry.id,
            parent_id,
            agent_type: entry.info.agent_type,
            description: entry.info.description,
            spawn_depth: entry.info.spawn_depth,
            start_ms: agg.start_ms.unwrap_or(0),
            end_ms: agg.end_ms.unwrap_or(0),
            calls: agg.calls,
            cost: agg.cost,
            output: agg.output,
            cache_read: agg.cache_read,
            cache_write: agg.cache_write,
        });
    }

    // spans[0] must be "main" (timeline_model.rs's contract) — a session
    // whose main file failed to parse but that still has subagent spans
    // would otherwise put a subagent first.
    let mut out: Vec<SessionTimeline> = sessions
        .into_values()
        .map(|mut t| {
            if let Some(main_idx) = t.spans.iter().position(|s| s.id == "main") {
                if main_idx != 0 {
                    t.spans.swap(0, main_idx);
                }
            }
            t
        })
        .collect();

    // Most-recent-first by main span start_ms, matching the cost screen's
    // own most-expensive-first convention (docs/plan-e7.md).
    out.sort_by(|a, b| {
        let a_start = a.spans.first().map(|s| s.start_ms).unwrap_or(0);
        let b_start = b.spans.first().map(|s| s.start_ms).unwrap_or(0);
        b_start.cmp(&a_start)
    });

    (out, report)
}

/// `sess1/subagents/agent-1.meta.json` -> `sess1/subagents/agent-1.jsonl`.
/// `None` if the meta path does not end in `.meta.json`.
fn subagent_jsonl_for(meta_rel_path: &str) -> Option<String> {
    meta_rel_path
        .strip_suffix(".meta.json")
        .map(|stem| format!("{stem}.jsonl"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rates() -> Rates {
        Rates::load()
    }

    fn line(ts: &str, tool_use_id: Option<&str>) -> String {
        let content = match tool_use_id {
            Some(id) => format!(r#","content":[{{"type":"tool_use","id":"{id}","name":"Agent"}}]"#),
            None => String::new(),
        };
        format!(
            r#"{{"timestamp":"{ts}","message":{{"model":"claude-sonnet-5","usage":{{"input_tokens":1000,"output_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}{content}}}}}"#
        )
    }

    // Real sidecars carry no `id` field (E7-followups); the span id comes
    // from the filename instead, so this fixture builder matches the shape
    // actually written to disk.
    fn meta(agent_type: &str, tool_use_id: &str, spawn_depth: u32) -> String {
        format!(
            r#"{{"agentType":"{agent_type}","description":"did the thing","toolUseId":"{tool_use_id}","spawnDepth":{spawn_depth}}}"#
        )
    }

    #[test]
    fn parse_rfc3339_matches_known_values() {
        assert_eq!(parse_rfc3339_utc_ms("1970-01-01T00:00:00.000Z"), Some(0));
        assert_eq!(parse_rfc3339_utc_ms("1970-01-01T00:00:01.500Z"), Some(1500));
        assert_eq!(
            parse_rfc3339_utc_ms("2024-01-01T00:00:00.000Z"),
            Some(1_704_067_200_000)
        );
        assert_eq!(parse_rfc3339_utc_ms("not-a-timestamp"), None);
    }

    #[test]
    fn parse_rfc3339_rejects_out_of_range_calendar_and_clock_fields() {
        assert_eq!(
            parse_rfc3339_utc_ms("2024-01-32T00:00:00.000Z"),
            None,
            "day 32 does not exist in any month"
        );
        assert_eq!(
            parse_rfc3339_utc_ms("2023-02-29T00:00:00.000Z"),
            None,
            "2023 is not a leap year, Feb has 28 days"
        );
        assert_eq!(
            parse_rfc3339_utc_ms("2024-01-01T99:00:00.000Z"),
            None,
            "hour 99 is not a valid hour"
        );
        assert!(
            parse_rfc3339_utc_ms("2024-02-29T00:00:00.000Z").is_some(),
            "2024 is a leap year, Feb 29 is valid"
        );
    }

    #[test]
    fn main_only_session_has_a_single_main_span() {
        let contents = line("1970-01-01T00:00:00.000Z", None);
        let files = [RawFile {
            rel_path: "sess1.jsonl",
            contents: &contents,
        }];
        let (timelines, report) = build_timelines(&files, &[], &rates());
        assert_eq!(timelines.len(), 1);
        assert_eq!(timelines[0].spans.len(), 1);
        assert_eq!(timelines[0].spans[0].id, "main");
        assert_eq!(report.malformed_lines, 0);
    }

    #[test]
    fn zero_subagents_produces_only_the_main_span() {
        let contents = line("1970-01-01T00:00:00.000Z", None);
        let files = [RawFile {
            rel_path: "sess1.jsonl",
            contents: &contents,
        }];
        let (timelines, _) = build_timelines(&files, &[], &rates());
        assert_eq!(timelines[0].spans.len(), 1);
    }

    #[test]
    fn subagent_resolves_to_main_via_matching_tool_use_id() {
        let main_contents = line("1970-01-01T00:00:00.000Z", Some("toolu_1"));
        let sub_contents = line("1970-01-01T00:00:05.000Z", None);
        let meta_contents = meta("implementer", "toolu_1", 1);
        let files = [
            RawFile {
                rel_path: "sess1.jsonl",
                contents: &main_contents,
            },
            RawFile {
                rel_path: "sess1/subagents/agent-1.jsonl",
                contents: &sub_contents,
            },
        ];
        let meta_files = [RawFile {
            rel_path: "sess1/subagents/agent-1.meta.json",
            contents: &meta_contents,
        }];
        let (timelines, _) = build_timelines(&files, &meta_files, &rates());
        assert_eq!(timelines.len(), 1);
        assert_eq!(timelines[0].spans.len(), 2);
        assert_eq!(timelines[0].spans[0].id, "main");
        let sub = &timelines[0].spans[1];
        assert_eq!(
            sub.id, "1",
            "id is derived from the agent-<id> filename stem"
        );
        assert_eq!(sub.parent_id.as_deref(), Some("main"));
        assert_eq!(sub.agent_type, "implementer");
        assert_eq!(sub.spawn_depth, 1);
    }

    #[test]
    fn unresolvable_tool_use_id_leaves_parent_id_none() {
        let main_contents = line("1970-01-01T00:00:00.000Z", None);
        let sub_contents = line("1970-01-01T00:00:05.000Z", None);
        let meta_contents = meta("implementer", "toolu_missing", 1);
        let files = [
            RawFile {
                rel_path: "sess1.jsonl",
                contents: &main_contents,
            },
            RawFile {
                rel_path: "sess1/subagents/agent-1.jsonl",
                contents: &sub_contents,
            },
        ];
        let meta_files = [RawFile {
            rel_path: "sess1/subagents/agent-1.meta.json",
            contents: &meta_contents,
        }];
        let (timelines, _) = build_timelines(&files, &meta_files, &rates());
        assert_eq!(timelines[0].spans[1].parent_id, None);
    }

    // Real sidecars on disk carry no `id` field — the span id is derived
    // from the filename stem (`agent-<id>.meta.json`) instead. Fixture is
    // byte-identical to a real
    // `.claude/projects/.../subagents/agent-a0e999668359243a9.meta.json`.
    #[test]
    fn real_sidecar_shape_with_no_id_field_still_produces_a_span() {
        let main_contents = line(
            "1970-01-01T00:00:00.000Z",
            Some("toolu_01WEnuG6ZxmM4YQE4CCq7xWM"),
        );
        let sub_contents = line("1970-01-01T00:00:05.000Z", None);
        let real_meta = r#"{"agentType":"agent-team:reviewer","description":"Review the three optimization commits","toolUseId":"toolu_01WEnuG6ZxmM4YQE4CCq7xWM","spawnDepth":1}"#;
        let files = [
            RawFile {
                rel_path: "sess1.jsonl",
                contents: &main_contents,
            },
            RawFile {
                rel_path: "sess1/subagents/agent-a0e999668359243a9.jsonl",
                contents: &sub_contents,
            },
        ];
        let meta_files = [RawFile {
            rel_path: "sess1/subagents/agent-a0e999668359243a9.meta.json",
            contents: real_meta,
        }];
        let (timelines, report) = build_timelines(&files, &meta_files, &rates());
        assert_eq!(report.malformed_lines, 0);
        assert_eq!(timelines[0].spans.len(), 2);
        let sub = &timelines[0].spans[1];
        assert_eq!(sub.id, "a0e999668359243a9");
        assert_eq!(sub.agent_type, "agent-team:reviewer");
        assert_eq!(sub.parent_id.as_deref(), Some("main"));
    }

    // A meta.json with a field we don't model yet (forward compatibility)
    // must still parse successfully rather than landing in malformed_lines.
    #[test]
    fn meta_json_with_an_unknown_extra_field_still_parses() {
        let main_contents = line("1970-01-01T00:00:00.000Z", None);
        let sub_contents = line("1970-01-01T00:00:05.000Z", None);
        let meta_with_extra = r#"{"agentType":"implementer","description":"do it","toolUseId":"toolu_1","spawnDepth":1,"model":"claude-sonnet-5"}"#;
        let files = [
            RawFile {
                rel_path: "sess1.jsonl",
                contents: &main_contents,
            },
            RawFile {
                rel_path: "sess1/subagents/agent-x.jsonl",
                contents: &sub_contents,
            },
        ];
        let meta_files = [RawFile {
            rel_path: "sess1/subagents/agent-x.meta.json",
            contents: meta_with_extra,
        }];
        let (timelines, report) = build_timelines(&files, &meta_files, &rates());
        assert_eq!(report.malformed_lines, 0);
        assert_eq!(timelines[0].spans[1].id, "x");
    }

    #[test]
    fn malformed_meta_json_is_counted_and_other_spans_unaffected() {
        let main_contents = line("1970-01-01T00:00:00.000Z", None);
        let files = [RawFile {
            rel_path: "sess1.jsonl",
            contents: &main_contents,
        }];
        let meta_files = [RawFile {
            rel_path: "sess1/subagents/broken.meta.json",
            contents: "not json",
        }];
        let (timelines, report) = build_timelines(&files, &meta_files, &rates());
        assert_eq!(report.malformed_lines, 1);
        assert_eq!(
            timelines[0].spans.len(),
            1,
            "the session's other span is unaffected"
        );
    }

    #[test]
    fn nested_spawn_depth_two_resolves_parent_to_another_subagent() {
        let main_contents = line("1970-01-01T00:00:00.000Z", Some("toolu_1"));
        let sub1_contents = line("1970-01-01T00:00:05.000Z", Some("toolu_2"));
        let sub2_contents = line("1970-01-01T00:00:07.000Z", None);
        let meta1 = meta("planner", "toolu_1", 1);
        let meta2 = meta("implementer", "toolu_2", 2);
        let files = [
            RawFile {
                rel_path: "sess1.jsonl",
                contents: &main_contents,
            },
            RawFile {
                rel_path: "sess1/subagents/agent-1.jsonl",
                contents: &sub1_contents,
            },
            RawFile {
                rel_path: "sess1/subagents/agent-2.jsonl",
                contents: &sub2_contents,
            },
        ];
        let meta_files = [
            RawFile {
                rel_path: "sess1/subagents/agent-1.meta.json",
                contents: &meta1,
            },
            RawFile {
                rel_path: "sess1/subagents/agent-2.meta.json",
                contents: &meta2,
            },
        ];
        let (timelines, _) = build_timelines(&files, &meta_files, &rates());
        let spans = &timelines[0].spans;
        let agent2 = spans.iter().find(|s| s.id == "2").unwrap();
        assert_eq!(agent2.parent_id.as_deref(), Some("1"));
        assert_eq!(agent2.spawn_depth, 2);
    }

    #[test]
    fn fifty_plus_span_session_builds_within_budget() {
        let mut files_owned: Vec<(String, String)> = Vec::new();
        files_owned.push((
            "sess1.jsonl".to_string(),
            line("1970-01-01T00:00:00.000Z", Some("toolu_main")),
        ));
        let mut metas_owned: Vec<(String, String)> = Vec::new();
        for i in 0..60 {
            let rel = format!("sess1/subagents/agent-{i}.jsonl");
            files_owned.push((rel, line("1970-01-01T00:01:00.000Z", None)));
            let meta_rel = format!("sess1/subagents/agent-{i}.meta.json");
            metas_owned.push((meta_rel, meta("implementer", "toolu_main", 1)));
        }
        let files: Vec<RawFile> = files_owned
            .iter()
            .map(|(p, c)| RawFile {
                rel_path: p,
                contents: c,
            })
            .collect();
        let meta_files: Vec<RawFile> = metas_owned
            .iter()
            .map(|(p, c)| RawFile {
                rel_path: p,
                contents: c,
            })
            .collect();

        let start = std::time::Instant::now();
        let (timelines, report) = build_timelines(&files, &meta_files, &rates());
        let elapsed = start.elapsed();
        assert_eq!(timelines[0].spans.len(), 61);
        assert_eq!(report.malformed_lines, 0);
        assert!(
            elapsed.as_millis() < 100,
            "build of 60 spans took {elapsed:?}, budget is 100ms"
        );
    }
}
