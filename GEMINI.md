# Agent Team Workspace Rules

This workspace operates under the **Agent Team** workflow.

## Commands & Build Trigger
Whenever the user prompts `/build <request>`, `build <request>`, or requests to implement a feature/fix:
1. **Load the `workflow-router` skill** immediately.
2. **System One Fast Classification**:
   - Use fast/lightweight model tier (`flash_lite` or `flash`) for rapid, structured decision-making without extra API keys.
   - Classify the request into `QUICK`, `FEATURE`, or `PROJECT` based on scope.
3. Follow the strict multi-agent handoff pipeline:
   - `QUICK`: Execute straight with TDD test & implementation.
   - `FEATURE`: Generate implementation plan & API contract -> Execute Backend & Frontend with strict TDD -> Run quality gates & verification.
   - `PROJECT`: Analysis -> PRD -> User Approval -> Architecture & Plan -> Parallel implementation -> QA & Review.
4. **Model Allocation & Token Discipline**:
   - **Router / Triage / Guardrails**: `flash_lite` (Instant System One decision, schema-constrained, 0 extra API key).
   - **Code Review / Test & Gate Checks**: `flash` (Fast analysis of diffs, lint, and test logs).
   - **Complex Planning / Architecture / Core Implementation**: `pro` or `inherit` (Deep reasoning, PRD, refactoring).
   - Limit handoff reports to 30-60 lines.
   - Query CodeGraph/symbols before reading entire files.
   - Never write code before an approved plan (except on `QUICK` tier).

## Language & Artifact Conventions
- **Chat Response**: Respond to the user in Vietnamese (or user's preferred language).
- **Files & Codebase**: All created/modified files, documentation (`docs/*.md`, artifacts, PRD, comments, code, commit messages) **MUST be written in English throughout**, adhering strictly to CLAUDE.md / Agent Team writing rules.

