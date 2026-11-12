---
id: rca-git-bash-utf8-sed-truncation-in-antigravity-hook
title: "Git Bash UTF8 Sed Truncation in Antigravity Hook"
type: rca
domain: engineering
confidence: observed
verified_by: "bash plugins/agent-team/scripts/tests/antigravity.test.sh"
created: 2026-11-12
updated: 2026-11-12
tags:
  - agent-team
  - rca
  - engineering
  - antigravity
  - hooks
---

# Git Bash UTF8 Sed Truncation in Antigravity Hook

> [!abstract] Essence
> POSIX sed without LC_ALL=C rejects raw UTF-8 emoji bytes on non-UTF8 Windows locales, returning an empty string.

## Mechanism & Invariant

Enforce LC_ALL=C on tr and sed pipelines in agy-lib.sh so byte-level regex extraction succeeds regardless of host locale.

## Verification & Evidence

- **Confidence**: `[observed]`
- **Verified by**: `bash plugins/agent-team/scripts/tests/antigravity.test.sh`

## Graph Links

- [[00-MOC]]
