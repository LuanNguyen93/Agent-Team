// include_str!-embeds and parses tui/shared/rates.json (ADR-0007(c)): the
// single rate source for both this Rust parser and measure-tokens.js.
// Embedded at compile time, never read at run time — a binary that needs a
// file beside it breaks the moment it's copied (ADR-0002).

use serde::Deserialize;

const RATES_JSON: &str = include_str!("../../../shared/rates.json");

#[derive(Debug, Deserialize)]
pub struct TierRate {
    pub input: f64,
    pub output: f64,
}

#[derive(Debug, Deserialize)]
pub struct Tiers {
    pub opus: TierRate,
    pub sonnet: TierRate,
    pub haiku: TierRate,
}

#[derive(Debug, Deserialize)]
pub struct Rates {
    #[allow(dead_code)]
    #[serde(rename = "rateVersion")]
    pub rate_version: String,
    #[serde(rename = "cacheWriteMultiplier")]
    pub cache_write_multiplier: f64,
    #[serde(rename = "cacheReadMultiplier")]
    pub cache_read_multiplier: f64,
    pub tiers: Tiers,
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Tier {
    Opus,
    Sonnet,
    Haiku,
}

impl Rates {
    /// Parses the embedded rates.json. Panics on a malformed body — per
    /// ADR-0007(c), a missing or malformed rates.json is a hard build/test
    /// failure on both sides, never a silent fallback table.
    pub fn load() -> Self {
        serde_json::from_str(RATES_JSON).expect("tui/shared/rates.json is malformed")
    }

    fn rate_for(&self, tier: Tier) -> &TierRate {
        match tier {
            Tier::Opus => &self.tiers.opus,
            Tier::Sonnet => &self.tiers.sonnet,
            Tier::Haiku => &self.tiers.haiku,
        }
    }

    /// usage-record cost for one call. Mirrors measure-tokens.js's `costOf`
    /// exactly, including operand order (input, output, cache write, cache
    /// read), per ADR-0007(b).
    pub fn cost_of(&self, tier: Tier, usage: &crate::analytics::model::Usage) -> f64 {
        let r = self.rate_for(tier);
        (usage.input_tokens as f64 * r.input
            + usage.output_tokens as f64 * r.output
            + usage.cache_creation_input_tokens as f64 * r.input * self.cache_write_multiplier
            + usage.cache_read_input_tokens as f64 * r.input * self.cache_read_multiplier)
            / 1e6
    }
}

/// Substring match on the lowercased model string, haiku then sonnet,
/// everything else — including an empty/unrecognised string — falls
/// through to opus. Mirrors measure-tokens.js's `tierOf` verbatim
/// (ADR-0007(b)): an unrecognised model bills at the most expensive tier
/// rather than disappearing or erroring.
pub fn tier_of(model: &str) -> Tier {
    let m = model.to_lowercase();
    if m.contains("haiku") {
        Tier::Haiku
    } else if m.contains("sonnet") {
        Tier::Sonnet
    } else {
        Tier::Opus
    }
}

/// What one request had to carry: input + cache creation + cache read.
/// Mirrors measure-tokens.js's `contextOf`.
pub fn context_of(usage: &crate::analytics::model::Usage) -> u64 {
    usage.input_tokens + usage.cache_creation_input_tokens + usage.cache_read_input_tokens
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::analytics::model::Usage;

    #[test]
    fn tier_of_matches_haiku_sonnet_and_falls_back_to_opus() {
        assert_eq!(tier_of("claude-haiku-x"), Tier::Haiku);
        assert_eq!(tier_of("claude-sonnet-5"), Tier::Sonnet);
        assert_eq!(tier_of("claude-opus-5"), Tier::Opus);
        assert_eq!(tier_of("unknown-model"), Tier::Opus);
    }

    #[test]
    fn cost_of_matches_a_hand_computed_number_against_the_committed_rates() {
        let rates = Rates::load();
        // opus: input 15/M, output 75/M, cache write x1.25, cache read x0.1
        let usage = Usage {
            input_tokens: 100_000,
            output_tokens: 1_000,
            cache_creation_input_tokens: 8_000,
            cache_read_input_tokens: 120_000,
        };
        let expected =
            (100_000.0 * 15.0 + 1_000.0 * 75.0 + 8_000.0 * 15.0 * 1.25 + 120_000.0 * 15.0 * 0.1)
                / 1e6;
        let got = rates.cost_of(Tier::Opus, &usage);
        assert!(
            (got - expected).abs() < 1e-9,
            "got {got}, expected {expected}"
        );
    }
}
