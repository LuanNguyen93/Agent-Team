# Agent Team Workspace Rules

This workspace operates under the **Agent Team** workflow.

## Commands & Build Trigger
Whenever the user prompts `/build <request>`, `build <request>`, or requests to implement a feature/fix:
1. **Load the `workflow-router` skill** immediately.
2. **System One Fast Classification**:
   - Classify the request into `QUICK`, `FEATURE`, or `PROJECT` using the skill's Classify section, preferably on a fast model tier (`flash-lite` or `flash`).
   - Optional: `python3 plugins/agent-team/scripts/fast_router.py "<request>" --format line` does the same through the Gemini API. It needs `GEMINI_API_KEY`; exit 2 means no key, so classify in-session instead.
   - Announce the tier as `` `TIER` — reason `` in one line before doing anything else.
3. Follow the strict multi-agent handoff pipeline:
   - `QUICK`: Execute straight with TDD test & implementation.
   - `FEATURE`: Generate implementation plan & API contract -> Execute Backend & Frontend with strict TDD -> Run quality gates & verification.
   - `PROJECT`: Analysis -> PRD -> User Approval -> Architecture & Plan -> Parallel implementation -> QA & Review.
4. **Model Allocation & Token Discipline (`Hydrogen + Flash + Pro` Triad)**:
   - **Primary Session Model**: Set active model to **Gemini 4 Hydrogen** (`medium` or `high` thinking). All `inherit` agents run on Hydrogen for high-speed, flat-rate (`$1.50/$7.50`) execution without Argon/Carbon overhead.
   - **Tier 0 — Deterministic CLI (`0` tokens)**: `fast_router.py --offline`, `context_kernel.py`, `kernel_forge.py`, `run-gates.sh`.
   - **Tier 1 — Router / Triage / QA Gate Checks (`flash_lite` & `flash`)**: `router` (`flash_lite`), `qa-verifier` (`flash`), wide search/fetch folding, and diff/log checks.
   - **Tier 2 — Planning, Core TDD Implementation & Fresh-Context Review (`inherit` -> Gemini 4 Hydrogen)**: `analyst`, `pm`, `ux-designer`, `planner`, `implementer`, `backend-implementer`, `frontend-implementer`, and `reviewer`.
   - **Tier 3 — System Architecture & Strike-2 RCA Escalation (`pro` or Hydrogen `xhigh`)**: Reserved strictly for `architect` (system design/ADRs) and `debugger` (only after Two-Strike repeated failure).
   - Limit handoff reports to 30-60 lines.
   - Query CodeGraph/AST skeleton (`context_kernel.py skeleton` / `prefix-pack`) before reading entire files.
   - Never write code before an approved plan (except on `QUICK` tier).

## Autonomous Decision Doctrine (Zero-Nudge Execution)
- **Zero-Nudge Execution**: Sub-agents and main agent MUST NOT ask the user for permission to read files, write tests, modify code, run linters/tests, or refactor within the scope of the task/plan.
- **Decision Boundary**:
  - *Decide and proceed*: Implementation details, file structure, test cases, bug fixing iterations, error handling. Execute completely and provide a concise summary report at the end.
  - *Only ask when*:
    1. A destructive, irreversible action is required (e.g. dropping DB, hard git resets losing uncommitted work).
    2. Missing fundamental domain decisions or business requirements not in the spec.
    3. Loop budget or quality gate is hard-blocked.

## Language & Artifact Conventions
- **Chat Response**: Respond to the user in Vietnamese (or user's preferred language).
- **Files & Codebase**: All created/modified files, documentation (`docs/*.md`, artifacts, PRD, comments, code, commit messages) **MUST be written in English throughout**, adhering strictly to CLAUDE.md / Agent Team writing rules.

