// The typed result of a timeline build: AgentSpan, SessionTimeline. No I/O
// of any kind, no ratatui type — mirrors model.rs's role for the timeline
// feature (docs/architecture-e7.md's dependency table). Plain structs only.

/// One agent's slice of a session: the main context (spawn_depth 0,
/// parent_id None) or a spawned subagent. `output`/`cache_read`/
/// `cache_write` mirror `Bucket`'s field names so screen-layer formatting
/// code can share helpers with the cost-analytics screen.
#[derive(Debug, PartialEq, Clone)]
pub struct AgentSpan {
    pub id: String,
    pub parent_id: Option<String>,
    pub agent_type: String,
    pub description: String,
    pub spawn_depth: u32,
    pub start_ms: i64,
    pub end_ms: i64,
    pub calls: u64,
    pub cost: f64,
    pub output: u64,
    pub cache_read: u64,
    pub cache_write: u64,
}

/// A session's agent-flow tree, flattened into a `Vec` rather than a real
/// tree — `spawn_depth` plus `parent_id` is enough for the screen to render
/// indentation, and a flat vec keeps `build_timelines` a single pass with no
/// recursive struct to build. `spans[0]` is always "main" (spawn_depth 0).
#[derive(Debug, PartialEq, Clone)]
pub struct SessionTimeline {
    pub session_id: String,
    pub spans: Vec<AgentSpan>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn main_span() -> AgentSpan {
        AgentSpan {
            id: "main".to_string(),
            parent_id: None,
            agent_type: "main".to_string(),
            description: "main session".to_string(),
            spawn_depth: 0,
            start_ms: 0,
            end_ms: 1000,
            calls: 3,
            cost: 1.5,
            output: 100,
            cache_read: 10,
            cache_write: 5,
        }
    }

    #[test]
    fn agent_span_constructs_and_compares_by_equality() {
        let a = main_span();
        let b = main_span();
        assert_eq!(a, b);
    }

    #[test]
    fn session_timeline_first_span_is_main() {
        let sub = AgentSpan {
            id: "agent-1".to_string(),
            parent_id: Some("main".to_string()),
            agent_type: "implementer".to_string(),
            description: "do the thing".to_string(),
            spawn_depth: 1,
            start_ms: 100,
            end_ms: 500,
            calls: 1,
            cost: 0.2,
            output: 10,
            cache_read: 1,
            cache_write: 1,
        };
        let timeline = SessionTimeline {
            session_id: "sess1".to_string(),
            spans: vec![main_span(), sub],
        };
        assert_eq!(timeline.spans[0].agent_type, "main");
        assert_eq!(timeline.spans[1].parent_id.as_deref(), Some("main"));
    }
}
