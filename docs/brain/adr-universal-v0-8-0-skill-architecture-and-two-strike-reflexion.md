---
id: adr-universal-v0-8-0-skill-architecture-and-two-strike-reflexion
title: "Universal v0.8.0 Skill Architecture and Two-Strike Reflexion"
type: adr
domain: architecture
confidence: observed
verified_by: "python3 plugins/agent-team/scripts/eval.py --strict"
created: 2026-11-12
updated: 2026-11-12
tags:
  - agent-team
  - adr
  - architecture
  - reflexion
---

# Universal v0.8.0 Skill Architecture and Two-Strike Reflexion

> [!abstract] Essence
> Combine local-first Obsidian Markdown distillation, deterministic Two-Strike circuit breakers, and System One offline/SLM routing without external DB dependencies.

## Mechanism & Invariant

Chosen Option B (Modular Skill + Stdlib Python CLI + Eval Gates) over vector DBs or prompt-only instructions.

## Verification & Evidence

- **Confidence**: `[observed]`
- **Verified by**: `python3 plugins/agent-team/scripts/eval.py --strict`

## Graph Links

- [[00-MOC]]
- [[rca-git-bash-utf8-sed-truncation-in-antigravity-hook]]
