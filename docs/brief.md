# Brief: Agent Team v0.8.0 — Universal Skill & Harness Upgrade

## Problem
Autonomous coding agents across harnesses (Claude Code, Antigravity, Codex) still suffer from three systemic failures:
1. **In-flight repetition of the same failure** (FlipFlop loops, blind retries, and unrecorded failed hypotheses when a gate or test fails).
2. **Session amnesia** — hard-won architectural decisions, root causes, and domain invariants die when a session ends instead of compounding into a persistent Second Brain (Obsidian).
3. **Expensive decision overhead & cargo-cult engineering** — burning frontier tokens on binary/routing decisions that a System One small model can make deterministically, or over-engineering trendy architectures instead of building the single right-sized solution grounded in immutable engineering invariants and modern business domains.

## Evidence
- `[observed]` `docs/HARNESS-NOTES.md` and `skills/context-discipline/SKILL.md`: Unscoped sessions without subagent delegation and small-model routing cost up to $272 (729k context), with 53% of spend re-reading existing context.
- `[observed]` `skills/workflow-router/SKILL.md` & `skills/debug-rca/SKILL.md`: While inter-agent review passes are capped at 2 attempts / 3 passes, *intra-turn* self-correction lacks a mandatory Strike-Count & Failed-Hypothesis Ledger, allowing an implementer or debugger to repeat the same fix strategy within a single turn.
- `[observed]` Industry research (Shinn et al. *Reflexion*, `kepano/obsidian-skills`, Addy Osmani's AI engineering workflows, `obra/superpowers`): Agents that record structured failure reflections and distil atomic evergreen notes into an Obsidian vault avoid repeating mistakes across sessions.

## Cost of doing nothing
Agents continue to loop on recurring errors within turns, lose institutional knowledge between sessions, over-spend tokens on routine decisions, and drift from core software engineering invariants.

## Success criteria
- [x] **Obsidian Second-Brain Distillation (`obsidian-second-brain`)**: New skill + deterministic CLI script (`scripts/obsidian_distill.py`) that distils session insights, ADRs, RCA lessons, and domain rules into atomic Obsidian Flavored Markdown notes (YAML frontmatter, `[[wikilinks]]`, callouts, MOC updates) with zero duplication. (`[observed: test_obsidian_and_router.py]`)
- [x] **In-Flight Self-Correction & Anti-Loop Reflexion (`debug-rca`, `tdd-discipline`, `implementer`, `debugger`)**: Mandatory **Strike-Count & Failed-Hypothesis Ledger** (`.agent-team/Attempt-Ledger.md` or in-turn table). After 2 failed attempts on the same error signature, the agent MUST stop editing, record the falsified hypothesis and negative constraint, and pivot or escalate — never repeating a failed approach. (`[observed: eval.py]`)
- [x] **System One Small-Model Decision Protocol (`workflow-router`, `context-discipline`, `scripts/fast_router.py`)**: Fast, deterministic + SLM (`haiku` / `flash-lite`) decision rubric for routing, scope triage, and strike-count detection before invoking frontier reasoning. (`[observed: test_obsidian_and_router.py]`)
- [x] **Modern Global Business Domains & Anti-Hype Single-Solution Doctrine (`analyst`, `architect`, `architecture-discipline`, `backend-discipline`)**: Domain rules for AI-native unit economics, FinTech ledger integrity, multi-tenant B2B SaaS, and global compliance, paired with strict anti-hype right-sizing (propose the single best-fit solution rather than following crowd trends) and immutable software engineering invariants (Parse Don't Validate, Make Illegal States Unrepresentable, Law of Locality, Idempotency, Bounded Resource Contracts). (`[observed: eval.py]`)
- [x] **Radical Honesty & Human Control (`handoff-contract`)**: Keep `SKILL.md` <= 2,000 bytes while strengthening `references/report-discipline.md` and `references/role-contracts.md` with human-controllable executive visibility (blast radius, failed-attempt ledger, unverified risks). (`[observed: plugin-shipping.test.sh]`)
- [x] **Distilled Attribution (`docs/ATTRIBUTION.md`)**: Updated to credit the newly distilled industry sources (`kepano/obsidian-skills`, Reflexion / Shinn et al., Replica clean-room product engineering, etc.). (`[observed: eval.py]`)
- [x] **Cross-Harness Sync (`Claude Code`, `Antigravity`, `Codex`)**: Version bumped to `0.8.0`, all unit/shipping/platform/eval gates pass 100%, and `scripts/upgrade.sh` synchronizes all three harnesses cleanly. (`[observed: upgrade.sh]`)

## Constraints
- `plugins/agent-team/skills/handoff-contract/SKILL.md` MUST remain `<= 2000` bytes (`plugin-shipping.test.sh` gate).
- Every skill `description` + `when_to_use` MUST remain `<= 1536` characters (`CLAUDE.md` §Writing rules).
- Every file MUST remain `<= 800` lines (`test_plugin_integrity.py` gate).
- Every skill on disk MUST be referenced by an agent, a command, or a `paths:` glob (`plugin-shipping.test.sh` orphan check).
- Every skill loaded in an agent's Step 0 paragraph MUST match its frontmatter `skills:` list (`plugin-shipping.test.sh`).
- English throughout all repository files, skills, agents, docs, and tests.

## Out of scope
- Proprietary vector database dependencies or external paid memory SaaS (Obsidian vault is local-first plain Markdown).
- Modifying unrelated TUI Rust binaries unless touched.

## Business Invariants & Rules
- `BR-01` (**No Repeat Hypothesis**): An agent may never execute two code edits for the same error signature without first recording the falsified hypothesis (`Attempt #N -> Input/Diff -> Exact Error -> Why Falsified -> Negative Constraint`).
- `BR-02` (**Two-Strike Pivot**): Two consecutive failed fixes for the same error signature within a turn trigger an immediate stop-and-pivot (revert working tree churn to last green state, switch to `debug-rca` Phase 2/3, or escalate).
- `BR-03` (**Atomic Evergreen Distillation**): Second-brain notes written to Obsidian must update existing evergreen notes or link into a Map of Content (`[[MOC]]`) with YAML properties (`type`, `domain`, `confidence`, `verified_by`, `updated`) rather than dumping unlinked raw chat transcripts.
- `BR-04` (**Single Fit-for-Purpose Recommendation**): When presenting options, agents must converge on **one** decisive, right-sized recommendation tailored to the actual input bound and team scale, explicitly rejecting cargo-cult crowd trends.
- `BR-05` (**System One First**): Classification, triage, gate exit-code checks, and loop detection run on the smallest model tier (`haiku` / `flash-lite`) or deterministic scripts before spending `sonnet` / `opus` tokens.

## Business State Machine (In-Flight Self-Correction & Knowledge Loop)
| Current State | Trigger Event | Guard / Conditions | Target State | Side Effects |
|---|---|---|---|---|
| `Executing` | Gate / Test Fails (Strike 1) | Error signature extracted | `Diagnosing_S1` | Record Attempt 1 in Failed-Hypothesis Ledger; state negative constraint |
| `Diagnosing_S1` | Targeted Fix Applied | New hypothesis falsifiable | `Executing` | Run deterministic gate |
| `Executing` | Same Error Signature Fails (Strike 2) | Strike count == 2 | `Circuit_Broken` | Revert failed churn; forbid 3rd blind edit; escalate to `debugger` or human |
| `Executing` | All Gates Green | `[observed]` exit code 0 | `Distilling` | Extract reusable ADR / RCA / domain invariant into Obsidian Second Brain |
| `Distilling` | `obsidian_distill.py` passes | Valid YAML + wikilinks | `Completed` | Deliver honest Human Control Report |

## Deprecations & Cleanup Targets
- Remove duplicate lines in `plugins/agent-team/agents/frontend-implementer.md` (lines 115-120 duplicate lines 106-111).
- Update stale skill count in `README.md` ("The eighteen skills" -> updated count including `market-recon`, `product-launch`, and `obsidian-second-brain`).

## Glossary
| Term | Meaning | Identity rule |
|---|---|---|
| **Error Signature** | Normalized `(file_or_test, error_type, key_message_slug)` | Two failures with the same tuple are the same bug |
| **Failed-Hypothesis Ledger** | Structured record of what was tried, why it failed, and what is now forbidden | Keyed by Error Signature + Attempt # |
| **Evergreen Note** | Atomic, linked Obsidian `.md` note representing one durable engineering truth or domain invariant | Keyed by canonical slug + YAML `id` |

## Open questions
None — all 10 user objectives are clear, self-contained, and verifiable against existing harness gates.
