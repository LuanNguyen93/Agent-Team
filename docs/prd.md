# PRD: Agent Team v0.8.0 — Universal Skill & Harness Upgrade

## Overview
Upgrades Agent Team across Claude Code, Antigravity, and Codex to satisfy 10 core engineering and operational capabilities:
1. High-efficacy output aligned with modern global business domains.
2. Self-adapting, continuous-learning agent loops.
3. Token and cost optimization via context discipline and small-model leverage.
4. Radical honesty and executive human-control reporting.
5. Second-brain knowledge distillation into Obsidian (`obsidian-second-brain`).
6. Anti-hype, single fit-for-purpose architectural decisions.
7. System One small-model (`haiku` / `flash-lite`) decision protocol.
8. Distilled wisdom from top tech-industry skill collections (`docs/ATTRIBUTION.md`).
9. In-flight self-correction & anti-repeat-failure reflexion loop.
10. Immutable software engineering invariants.

---

## Functional Requirements & Acceptance Criteria

### FR-1: Obsidian Second-Brain Knowledge Distillation (`obsidian-second-brain`)
- **Description**: Provide a first-class skill `plugins/agent-team/skills/obsidian-second-brain/SKILL.md`, reference templates (`references/note-templates.md`), and a zero-dependency CLI tool (`scripts/obsidian_distill.py`) that distils architectural decisions (ADRs), root-cause analysis (RCA) lessons, domain invariants, and recurring bug patterns into an Obsidian vault (or `docs/brain/` fallback).
- **Acceptance Criteria**:
  - **Given** a durable insight, ADR, RCA, or domain invariant, **When** `obsidian_distill.py` runs with `--vault <dir> --type <adr|rca|domain|pattern> --title <title> --domain <domain> --summary <text>`, **Then** it creates or updates an atomic `.md` file with valid Obsidian YAML frontmatter (`id`, `title`, `type`, `domain`, `confidence`, `verified_by`, `created`, `updated`, `tags`), Obsidian callouts (`> [!abstract]`, `> [!warning]`), and `[[wikilinks]]`, and updates `00-MOC.md` (Map of Content) without duplicating existing entries.
  - **Given** an existing note with the same slug, **When** `obsidian_distill.py` runs again with new evidence or `--merge`, **Then** it updates the `updated` timestamp and merges/appends the new section rather than creating a duplicate file.
  - **Given** a vault directory, **When** `obsidian_distill.py --lint <dir>` runs, **Then** it validates YAML frontmatter, checks for broken `[[wikilinks]]` and orphan notes, and exits `0` when clean or `1` when violations exist.

### FR-2: In-Flight Self-Correction & Anti-Repeat-Failure Loop (Reflexion & Two-Strike Rule)
- **Description**: Eliminate repeated failures on the same bug within a turn or across dispatches by embedding a deterministic **Strike-Count & Failed-Hypothesis Ledger** into `debug-rca`, `tdd-discipline`, `implementer`, `backend-implementer`, `frontend-implementer`, and `debugger`.
- **Acceptance Criteria**:
  - **Given** a test or gate failure during implementation or debugging, **When** the first fix attempt fails with the same error signature, **Then** the agent records `Attempt 1 | Hypothesis | Exact Error | Why Falsified | Negative Constraint` before touching code again.
  - **Given** 2 consecutive failed fix attempts on the same error signature within a turn (**Two-Strike Rule**), **When** Strike 2 occurs, **Then** the agent MUST `git checkout` / revert the failed speculative churn back to the last known state, stop blind editing, and either run full `debug-rca` Phase 2-3 (if in `implementer`) or escalate with the Failed-Hypothesis Ledger.

### FR-3: System One Small-Model Decision Protocol
- **Description**: Codify a fast decision matrix in `workflow-router`, `context-discipline`, and `router` so binary/bounded decisions (tier classification, parallel-safety check, scope boundary check, gate pass/fail triage, strike-count loop check) execute on the smallest model (`haiku` / `flash-lite`) or deterministic script (`fast_router.py`).
- **Acceptance Criteria**:
  - **Given** any incoming build/fix request or mid-flight triage decision, **When** `workflow-router` or `context-discipline` is consulted, **Then** the System One decision matrix specifies which decisions belong to `haiku`/`flash-lite` vs `sonnet` vs `opus`, and `fast_router.py` supports offline deterministic fallback (`--offline`) when no API key is present so routing can always be evaluated at zero token cost.

### FR-4: Modern Global Business Domains & Anti-Hype Single-Solution Doctrine
- **Description**: Upgrade `analyst`, `architect`, `architecture-discipline`, and `backend-discipline` with modern business domain invariants (AI-native token/latency unit economics & trust boundaries, FinTech double-entry & idempotency invariants, Multi-tenant B2B SaaS isolation & usage metering, GDPR/data residency) and the **Single Fit-for-Purpose Solution Rule** (reject crowd hype; recommend the one right-sized architecture for the actual input bound).
- **Acceptance Criteria**:
  - **Given** `analyst` or `architect` prompts and `architecture-discipline`, **When** evaluated by `eval.py`, **Then** they explicitly enforce modern business domain checks and the Anti-Hype Single Fit-for-Purpose rule.

### FR-5: Immutable Software Engineering Invariants
- **Description**: Embed the 7 timeless software engineering laws into `architecture-discipline`, `tdd-discipline`, and `backend-discipline`:
  1. **Parse, Don't Validate** at trust boundaries.
  2. **Make Illegal States Unrepresentable** (discriminated unions / state machines over boolean flags).
  3. **Locality of Behaviour & High Cohesion / Low Coupling**.
  4. **Idempotency & Deterministic State Transitions** (safe retries, ACID / outbox).
  5. **Bounded Resource Contracts** (every query paginated, every queue bounded, every external I/O timed out).
  6. **Zero Garbage & Root-Cause Fix** (delete dead code; never patch-on-patch).
  7. **Mechanical Enforcement over Verbal Wishes** (tests and hooks over comments).
- **Acceptance Criteria**:
  - **Given** `architecture-discipline/SKILL.md` and `tdd-discipline/SKILL.md`, **When** inspected and tested via `eval.py`, **Then** all 7 immutable engineering invariants are concisely codified and checked.

### FR-6: Radical Honesty & Executive Human-Control Reporting
- **Description**: Enhance `handoff-contract/references/report-discipline.md` and `references/role-contracts.md` (while keeping `handoff-contract/SKILL.md <= 2000` bytes) with a **Human Control & Honesty Block**: explicit blast radius, failed attempts count, unverified surface, and decision trade-offs so a human operator can audit everything in 10 seconds.
- **Acceptance Criteria**:
  - **Given** `handoff-contract/SKILL.md`, **When** `plugin-shipping.test.sh` runs, **Then** `SKILL.md` is `<= 2000` bytes.
  - **Given** `report-discipline.md` and `role-contracts.md`, **When** inspected, **Then** they require reporting failed attempts (`Strike count`), blast radius, and `[observed]` vs `[inferred]` vs `[assumed]` evidence.

### FR-7: Distilled Attribution & Cross-Harness Upgrade (`v0.8.0`)
- **Description**: Update `docs/ATTRIBUTION.md` with the newly distilled skill sources (`kepano/obsidian-skills`, Shinn et al. *Reflexion*, Replica clean-room product engineering, Addy Osmani AI coding workflows), bump `plugin.json` to `0.8.0`, add unit tests for `obsidian_distill.py` and `fast_router.py --offline`, update `eval.py`, and run `scripts/upgrade.sh` to synchronize Claude Code, Antigravity, and Codex.
- **Acceptance Criteria**:
  - **Given** the updated repository, **When** `bash plugins/agent-team/scripts/upgrade.sh` runs, **Then** all unit tests, `plugin-shipping.test.sh`, `antigravity.test.sh`, and `eval.py --strict` pass with 0 failures, and Antigravity (`~/.gemini/config/plugins/agent-team`) and Codex (`~/.agents/skills`) are updated to `0.8.0`.

---

## Story Breakdown
- **Story 1**: Build `obsidian-second-brain` skill, `references/note-templates.md`, `scripts/obsidian_distill.py`, and `tests/test_obsidian_distill.py` (FR-1, FR-2).
- **Story 2**: Upgrade core skills (`debug-rca`, `tdd-discipline`, `architecture-discipline`, `backend-discipline`, `context-discipline`, `workflow-router`, `handoff-contract`) with In-Flight Self-Correction, Immutable Engineering Invariants, Modern Business Domains, System One Decision Matrix, and Human-Control Reporting (FR-2, FR-3, FR-4, FR-5, FR-6).
- **Story 3**: Upgrade agents (`analyst`, `architect`, `implementer`, `backend-implementer`, `frontend-implementer`, `debugger`, `reviewer`, `router`) and `scripts/fast_router.py` (`--offline` mode), plus update `docs/ATTRIBUTION.md`, `README.md`, `evals/benchmark.json`, `scripts/eval.py`, and bump version to `0.8.0` across all harnesses (FR-3, FR-4, FR-7).
