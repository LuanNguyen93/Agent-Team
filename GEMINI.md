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
4. **Model Allocation & Token Discipline**:
   - **Router / Triage / Guardrails**: `flash-lite` (instant System One decision, no extra API key when run in-session).
   - **Code Review / Test & Gate Checks**: `flash` (Fast analysis of diffs, lint, and test logs).
   - **Complex Planning / Architecture / Core Implementation**: `pro` or `inherit` (Deep reasoning, PRD, refactoring).
   - Limit handoff reports to 30-60 lines.
   - Query CodeGraph/symbols before reading entire files.
   - Never write code before an approved plan (except on `QUICK` tier).

## Language & Artifact Conventions
- **Chat Response**: Respond to the user in Vietnamese (or user's preferred language).
- **Files & Codebase**: All created/modified files, documentation (`docs/*.md`, artifacts, PRD, comments, code, commit messages) **MUST be written in English throughout**, adhering strictly to CLAUDE.md / Agent Team writing rules.

