# Agent Team Workspace Rules

This workspace operates under the **Agent Team** workflow.

## Commands & Build Trigger
Whenever the user prompts `/build <request>`, `build <request>`, or requests to implement a feature/fix:
1. **Load the `workflow-router` skill** immediately.
2. **Classify** the request into `QUICK`, `FEATURE`, or `PROJECT` based on scope.
3. Follow the strict multi-agent handoff pipeline:
   - `QUICK`: Execute straight with TDD test & implementation.
   - `FEATURE`: Generate implementation plan & API contract -> Execute Backend & Frontend with strict TDD -> Run quality gates & verification.
   - `PROJECT`: Analysis -> PRD -> User Approval -> Architecture & Plan -> Parallel implementation -> QA & Review.
4. **Enforce Token Discipline**:
   - Limit handoff reports to 30-60 lines.
   - Query CodeGraph/symbols before reading entire files.
   - Never write code before an approved plan (except on `QUICK` tier).

## Language & Artifact Conventions
- **Chat Response**: Respond to the user in Vietnamese (or user's preferred language).
- **Files & Codebase**: All created/modified files, documentation (`docs/*.md`, artifacts, PRD, comments, code, commit messages) **MUST be written in English throughout**, adhering strictly to CLAUDE.md / Agent Team writing rules.
