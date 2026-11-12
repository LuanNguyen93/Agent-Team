# Architecture: Agent Team v0.8.0 — Universal Skill & Harness Upgrade

## Overview
Agent Team v0.8.0 extends the multi-harness plugin architecture (Claude Code source of truth in `plugins/agent-team/`, transpiled to Antigravity via `scripts/build-antigravity.sh` and exported to Codex via `scripts/build-codex.sh`) with three new structural mechanisms:
1. **Obsidian Second-Brain Distillation Substrate** (`skills/obsidian-second-brain/` + `scripts/obsidian_distill.py`): Local-first Markdown knowledge graph with YAML frontmatter, `[[wikilinks]]`, callouts, and `00-MOC.md` index maintenance.
2. **Deterministic In-Flight Self-Correction & Two-Strike Circuit Breaker** (`skills/debug-rca/`, `skills/tdd-discipline/`, and implementer/debugger agents): Prevents intra-turn FlipFlop loops by mandating a Failed-Hypothesis Ledger and git-revert pivot after 2 strikes on the same error signature.
3. **System One Small-Model Decision Engine** (`skills/workflow-router/`, `skills/context-discipline/`, `scripts/fast_router.py --offline`): Routes binary/triage decisions to deterministic rules or `haiku`/`flash-lite` before spending frontier tokens.

## Constraints that drove the design
- **Zero external runtime dependencies**: Scripts must run on any user's Python 3 standard library and POSIX `bash`.
- **Strict context budget**: `handoff-contract/SKILL.md` <= 2,000 bytes; all skill descriptions <= 1,536 chars; all files <= 800 lines.
- **Cross-harness parity**: Every skill and agent in `plugins/agent-team/` must transpile cleanly into `~/.gemini/config/plugins/agent-team` (Antigravity) and `~/.agents/skills` (Codex).

## Solution Options & CTO Trade-off Matrix
| Option | Complexity | Scalability / Performance | Operational Cost (TCO) | Verdict |
|---|---|---|---|---|
| Option A: Prompt-only instructions | Lowest | Fragile (models forget or duplicate notes) | $0 | Rejected (no deterministic enforcement) |
| Option B: Modular Skill + Stdlib Python CLI + Eval Gates | Moderate | High (deterministic MOC/YAML/linting + offline routing) | $0 extra (local Markdown + stdlib) | **RECOMMENDED** |
| Option C: External Vector DB + MCP Memory Server | High | High | Paid infra / daemon setup tax | Rejected (Overkill, violates local-first constraint) |

Rationale for Option B: Fits the existing codebase's exact pattern (`contrast.py`, `reviews.py`, `listing.py`, `parity.py`, `sweep.py`) — pairing concise markdown doctrine with a zero-dependency standard-library Python tool verified by unit tests.

## Components
| Component | Responsible for | NOT responsible for |
|---|---|---|
| `skills/obsidian-second-brain/SKILL.md` | Doctrine for distilling ADRs, RCAs, domain rules, and patterns into Obsidian Flavored Markdown | Replacing project `docs/brief.md` or `docs/prd.md` |
| `skills/obsidian-second-brain/scripts/obsidian_distill.py` | Creating/merging atomic Obsidian notes with YAML frontmatter, updating `00-MOC.md`, and linting vault links/frontmatter | Running an LLM or external database |
| `skills/debug-rca/SKILL.md` & `skills/tdd-discipline/SKILL.md` | In-flight Two-Strike Rule, Failed-Hypothesis Ledger, and 7 Immutable Engineering Invariants | Inter-agent pass counting (owned by `workflow-router`) |
| `skills/architecture-discipline/SKILL.md` & `skills/backend-discipline/SKILL.md` | Single Fit-for-Purpose Solution Rule, Modern Global Business Domains, and Immutable Engineering Invariants | UI styling (owned by `design-intelligence`) |
| `scripts/fast_router.py` | Online (`gemini-2.5-flash`) and deterministic `--offline` System One classification + strike-count triage | Spawning subagents directly |
| `scripts/eval.py` & `evals/benchmark.json` | Verifying all structural prompt invariants and routing accuracy across all 10 user objectives | Mutating plugin files |

## Dependency rule
| Layer | May import | Must never import |
|---|---|---|
| `skills/*/SKILL.md` | `references/*` and `scripts/*` within the same skill or `${CLAUDE_PLUGIN_ROOT}/scripts/*` | Agent definitions (`agents/*.md`) |
| `agents/*.md` | `skills/*` (via frontmatter `skills:` and Step 0 load) | Other agent files |
| `scripts/*.py` | Python 3 standard library only | Third-party pip packages (`requests`, `pydantic`, `yaml`) |
| `tests/test_*.py` | `scripts/*.py` and `skills/*/scripts/*.py` via `_load.py` | External network services |

## Data model (Obsidian Evergreen Note & Attempt Ledger)
1. **Obsidian Note Frontmatter**:
   - `id`: canonical slug (`adr-001-...`, `rca-...`, `domain-...`, `pattern-...`)
   - `title`: human-readable title
   - `type`: `adr | rca | domain | pattern | moc`
   - `domain`: business or technical domain (`fintech`, `ai-engineering`, `saas`, `architecture`, `debugging`)
   - `confidence`: `observed | inferred | assumed`
   - `verified_by`: command or test that proved the insight
   - `created` / `updated`: ISO-8601 date (`YYYY-MM-DD`)
   - `tags`: list of hierarchical tags (`[agent-team, rca, ...]`)
2. **Failed-Hypothesis Ledger Row**:
   - `Attempt #` | `Error Signature` | `Hypothesis Tested` | `Observed Result` | `Negative Constraint (Do Not Repeat)`

## Failure modes
| Where it fails | Who notices | What the system does | What the user sees |
|---|---|---|---|
| Agent fails twice on the same test error | Agent (`Two-Strike Rule`) | Reverts speculative diff, logs Failed-Hypothesis Ledger, pivots to `debug-rca` Phase 2-3 or escalates | Explicit 2-strike ledger instead of 10 blind retries |
| `obsidian_distill.py` called on existing note slug | `obsidian_distill.py` | Merges/appends new evidence and updates `updated:` date instead of creating duplicate file | Clean, deduplicated Obsidian vault |
| Broken `[[wikilink]]` or missing YAML in vault | `obsidian_distill.py --lint` | Exits `1` with `file:line` report of broken links or missing frontmatter keys | Actionable lint report |
| No `GEMINI_API_KEY` set when calling `fast_router.py --offline` | `fast_router.py` | Falls back to deterministic rule engine and exits `0` with structured JSON/line | Instant 0-token System One routing |
