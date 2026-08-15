//! WASM-compatible telemetry and efficiency scoring engine.
//! Pure computations over in-memory event streams with zero syscalls.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Lifecycle state for an agent session.
#[derive(Debug, PartialEq, Eq, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentLifecycleState {
    Idle,
    Running,
    Handoff,
    Failed,
    Completed,
}

/// Incoming telemetry event structure.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TelemetryEvent {
    pub session_id: String,
    pub agent: String,
    pub model: String,
    #[serde(default)]
    pub event_type: String, // e.g. "task_completed", "tool_call", "gate_run"
    #[serde(default)]
    pub input_tokens: u64,
    #[serde(default)]
    pub output_tokens: u64,
    #[serde(default)]
    pub cache_read_tokens: u64,
    #[serde(default)]
    pub cache_write_tokens: u64,
    #[serde(default)]
    pub gate_passed: Option<bool>,
    #[serde(default)]
    pub is_error: bool,
}

/// Aggregated metrics for an agent session.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct SessionMetrics {
    pub session_id: String,
    pub state: Option<AgentLifecycleState>,
    pub total_input_tokens: u64,
    pub total_output_tokens: u64,
    pub total_cache_read_tokens: u64,
    pub total_cache_write_tokens: u64,
    pub total_events: u64,
    pub gate_runs: u64,
    pub gate_passes: u64,
    pub error_count: u64,
    pub agent_calls: HashMap<String, u64>,
}

impl SessionMetrics {
    pub fn new(session_id: String) -> Self {
        Self {
            session_id,
            state: Some(AgentLifecycleState::Idle),
            ..Default::default()
        }
    }

    /// Calculate first-pass success rate (0.0 to 1.0)
    pub fn gate_success_rate(&self) -> f64 {
        if self.gate_runs == 0 {
            return 1.0;
        }
        self.gate_passes as f64 / self.gate_runs as f64
    }

    /// Calculate efficiency score (0.0 to 100.0) based on pass rate and error penalty
    pub fn calculate_efficiency_score(&self) -> f64 {
        let pass_score = self.gate_success_rate() * 70.0;
        let error_penalty = (self.error_count as f64 * 5.0).min(30.0);
        let base_score = pass_score + (30.0 - error_penalty);
        base_score.clamp(0.0, 100.0)
    }
}

/// Core WASM Agent Manager
#[derive(Debug, Default)]
pub struct WasmAgentManager {
    sessions: HashMap<String, SessionMetrics>,
}

impl WasmAgentManager {
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
        }
    }

    /// Ingest a telemetry event JSON string
    pub fn ingest_event_json(&mut self, event_json: &str) -> Result<(), String> {
        let event: TelemetryEvent = serde_json::from_str(event_json)
            .map_err(|e| format!("Invalid telemetry event JSON: {}", e))?;
        self.ingest_event(event);
        Ok(())
    }

    /// Ingest a structured telemetry event
    pub fn ingest_event(&mut self, event: TelemetryEvent) {
        let metrics = self
            .sessions
            .entry(event.session_id.clone())
            .or_insert_with(|| SessionMetrics::new(event.session_id));

        metrics.total_input_tokens += event.input_tokens;
        metrics.total_output_tokens += event.output_tokens;
        metrics.total_cache_read_tokens += event.cache_read_tokens;
        metrics.total_cache_write_tokens += event.cache_write_tokens;
        metrics.total_events += 1;

        if event.is_error {
            metrics.error_count += 1;
        }

        if let Some(passed) = event.gate_passed {
            metrics.gate_runs += 1;
            if passed {
                metrics.gate_passes += 1;
            }
        }

        *metrics.agent_calls.entry(event.agent).or_insert(0) += 1;

        metrics.state = if event.is_error {
            Some(AgentLifecycleState::Failed)
        } else if metrics.gate_runs > 0 && metrics.gate_passes == metrics.gate_runs {
            Some(AgentLifecycleState::Completed)
        } else {
            Some(AgentLifecycleState::Running)
        };
    }

    /// Retrieve session metrics as JSON string
    pub fn get_metrics_json(&self, session_id: &str) -> Result<String, String> {
        let metrics = self
            .sessions
            .get(session_id)
            .ok_or_else(|| format!("Session '{}' not found", session_id))?;
        serde_json::to_string(metrics)
            .map_err(|e| format!("Serialization error: {}", e))
    }

    /// Get the efficiency score for a session
    pub fn get_efficiency_score(&self, session_id: &str) -> Result<f64, String> {
        let metrics = self
            .sessions
            .get(session_id)
            .ok_or_else(|| format!("Session '{}' not found", session_id))?;
        Ok(metrics.calculate_efficiency_score())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_wasm_agent_manager_lifecycle_and_scoring() {
        let mut manager = WasmAgentManager::new();
        
        let event_json = r#"{
            "session_id": "session-123",
            "agent": "frontend-implementer",
            "model": "gemini-2.5-pro",
            "event_type": "gate_run",
            "input_tokens": 1200,
            "output_tokens": 300,
            "cache_read_tokens": 500,
            "cache_write_tokens": 100,
            "gate_passed": true,
            "is_error": false
        }"#;

        assert!(manager.ingest_event_json(event_json).is_ok());

        let score = manager.get_efficiency_score("session-123").unwrap();
        assert_eq!(score, 100.0);

        let metrics_json = manager.get_metrics_json("session-123").unwrap();
        assert!(metrics_json.contains("session-123"));
        assert!(metrics_json.contains("frontend-implementer"));
    }

    #[test]
    fn test_error_penalty_scoring() {
        let mut manager = WasmAgentManager::new();
        
        manager.ingest_event(TelemetryEvent {
            session_id: "session-err".into(),
            agent: "debugger".into(),
            model: "gemini-2.5-pro".into(),
            event_type: "error".into(),
            input_tokens: 500,
            output_tokens: 100,
            cache_read_tokens: 0,
            cache_write_tokens: 0,
            gate_passed: Some(false),
            is_error: true,
        });

        let score = manager.get_efficiency_score("session-err").unwrap();
        // pass_score = 0, penalty = 5 -> base = 25.0
        assert_eq!(score, 25.0);
    }
}
