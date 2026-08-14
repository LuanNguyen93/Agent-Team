// FR-6 parity test: reads the shared fixture, calls `analytics::parse`,
// compares against `expected.json` at ADR-0007's amended tolerance.
// `project`, `fixtureVersion` and `generator` are excluded from the
// comparison — provenance, not data either implementation computes.

use agent_team_tui::analytics::model::Session;
use agent_team_tui::analytics::parse::{parse, RawFile};
use agent_team_tui::analytics::rates::Rates;
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};

const COST_TOL: f64 = 1e-9;
const AVG_CTX_TOL: f64 = 1e-6;
const SUB_SHARE_TOL: f64 = 1e-12;

fn fixture_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../tests/fixtures/transcripts")
}

/// Recursively collects every `.jsonl` file under `dir`, relative-pathed
/// with `/` separators so the fixture reads the same on Windows and Unix.
fn collect_files(root: &Path, dir: &Path, out: &mut Vec<(String, String)>) {
    for entry in fs::read_dir(dir).expect("read fixture dir") {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.is_dir() {
            collect_files(root, &path, out);
        } else if path.extension().map(|e| e == "jsonl").unwrap_or(false) {
            let rel = path
                .strip_prefix(root)
                .unwrap()
                .to_string_lossy()
                .replace('\\', "/");
            let contents = fs::read_to_string(&path).expect("read fixture file");
            out.push((rel, contents));
        }
    }
}

fn approx_eq(a: f64, b: f64, tol: f64) -> bool {
    (a - b).abs() <= tol
}

fn assert_bucket_matches(prefix: &str, got: &Value, want: &Value) {
    assert_eq!(got["calls"], want["calls"], "{prefix}.calls");
    assert_eq!(got["output"], want["output"], "{prefix}.output");
    assert_eq!(got["cacheRead"], want["cacheRead"], "{prefix}.cacheRead");
    assert_eq!(got["cacheWrite"], want["cacheWrite"], "{prefix}.cacheWrite");
    assert_eq!(got["maxContext"], want["maxContext"], "{prefix}.maxContext");
    let got_cost = got["cost"].as_f64().unwrap();
    let want_cost = want["cost"].as_f64().unwrap();
    assert!(
        approx_eq(got_cost, want_cost, COST_TOL),
        "{prefix}.cost: got {got_cost}, want {want_cost}"
    );
    let got_avg = got["avgContext"].as_f64().unwrap();
    let want_avg = want["avgContext"].as_f64().unwrap();
    assert!(
        approx_eq(got_avg, want_avg, AVG_CTX_TOL),
        "{prefix}.avgContext: got {got_avg}, want {want_avg}"
    );
}

fn session_to_json(s: &Session) -> Value {
    serde_json::json!({
        "id": s.id,
        "main": {
            "calls": s.main.calls, "cost": s.main.cost, "output": s.main.output,
            "cacheRead": s.main.cache_read, "cacheWrite": s.main.cache_write,
            "avgContext": s.main.avg_context, "maxContext": s.main.max_context,
        },
        "sub": {
            "calls": s.sub.calls, "cost": s.sub.cost, "output": s.sub.output,
            "cacheRead": s.sub.cache_read, "cacheWrite": s.sub.cache_write,
            "avgContext": s.sub.avg_context, "maxContext": s.sub.max_context,
        },
        "byAgent": s.by_agent.iter().map(|r| serde_json::json!({
            "agent": r.agent, "model": r.model, "calls": r.calls,
            "cacheRead": r.cache_read, "cacheWrite": r.cache_write,
            "output": r.output, "cost": r.cost,
        })).collect::<Vec<_>>(),
        "totalCost": s.total_cost,
        "subShare": s.sub_share,
    })
}

#[test]
fn rust_parser_matches_measure_tokens_js_on_the_shared_fixture() {
    let root = fixture_root();
    let project = root.join("project");
    let mut files_owned = Vec::new();
    collect_files(&project, &project, &mut files_owned);
    // Deterministic order for a deterministic test, independent of parse's
    // own internal ordering guarantees.
    files_owned.sort();

    let raw: Vec<RawFile> = files_owned
        .iter()
        .map(|(rel, contents)| RawFile {
            rel_path: rel,
            contents,
        })
        .collect();

    let rates = Rates::load();
    let (sessions, _report) = parse(&raw, &rates);

    let expected_raw = fs::read_to_string(root.join("expected.json")).expect("read expected.json");
    let expected: Value = serde_json::from_str(&expected_raw).unwrap();
    let expected_sessions = expected["sessions"].as_array().unwrap();

    assert_eq!(
        sessions.len(),
        expected_sessions.len(),
        "session count mismatch"
    );

    for want in expected_sessions {
        let id = want["id"].as_str().unwrap();
        let got_session = sessions
            .iter()
            .find(|s| s.id == id)
            .unwrap_or_else(|| panic!("Rust parser did not produce session {id}"));
        let got = session_to_json(got_session);

        assert_bucket_matches(&format!("{id}.main"), &got["main"], &want["main"]);
        assert_bucket_matches(&format!("{id}.sub"), &got["sub"], &want["sub"]);

        let got_total = got["totalCost"].as_f64().unwrap();
        let want_total = want["totalCost"].as_f64().unwrap();
        assert!(
            approx_eq(got_total, want_total, COST_TOL),
            "{id}.totalCost: got {got_total}, want {want_total}"
        );

        let got_share = got["subShare"].as_f64().unwrap();
        let want_share = want["subShare"].as_f64().unwrap();
        assert!(
            approx_eq(got_share, want_share, SUB_SHARE_TOL),
            "{id}.subShare: got {got_share}, want {want_share}"
        );

        let got_rows = got["byAgent"].as_array().unwrap();
        let want_rows = want["byAgent"].as_array().unwrap();
        assert_eq!(got_rows.len(), want_rows.len(), "{id}.byAgent length");
        for (gr, wr) in got_rows.iter().zip(want_rows.iter()) {
            assert_eq!(gr["agent"], wr["agent"], "{id}.byAgent.agent");
            assert_eq!(gr["model"], wr["model"], "{id}.byAgent.model");
            assert_eq!(gr["calls"], wr["calls"], "{id}.byAgent.calls");
            assert_eq!(gr["cacheRead"], wr["cacheRead"], "{id}.byAgent.cacheRead");
            assert_eq!(
                gr["cacheWrite"], wr["cacheWrite"],
                "{id}.byAgent.cacheWrite"
            );
            assert_eq!(gr["output"], wr["output"], "{id}.byAgent.output");
            let gc = gr["cost"].as_f64().unwrap();
            let wc = wr["cost"].as_f64().unwrap();
            assert!(
                approx_eq(gc, wc, COST_TOL),
                "{id}.byAgent.cost: got {gc}, want {wc}"
            );
        }
    }
}
