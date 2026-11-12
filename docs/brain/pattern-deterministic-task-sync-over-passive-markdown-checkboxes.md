---
id: pattern-deterministic-task-sync-over-passive-markdown-checkboxes
title: "Deterministic Task Sync Over Passive Markdown Checkboxes"
type: pattern
domain: engineering
confidence: observed
verified_by: "python3 -m unittest discover -s plugins/agent-team/tests"
created: 2026-11-12
updated: 2026-11-12
tags:
  - agent-team
  - pattern
  - engineering
  - task-sync
  - tdd
---

# Deterministic Task Sync Over Passive Markdown Checkboxes

> [!abstract] Essence
> Prevent stale task lists and unticked checkboxes by adding a mandatory TICK step (task_sync.py) to the TDD loop and gating completion via run-gates.sh.

## Mechanism & Invariant

LLMs suffer from attention decay and skip full-file rewrites for markdown checkboxes. Atomic CLI ticking (--tick / --tick-csv with [observed] evidence) plus mechanical gate verification eliminates unticked tasks.

## Verification & Evidence

- **Confidence**: `[observed]`
- **Verified by**: `python3 -m unittest discover -s plugins/agent-team/tests`

## Graph Links

- [[00-MOC]]
