---
name: obsidian-second-brain
description: Distils verified architectural decisions (ADRs), root-cause analysis (RCA) lessons, domain invariants, and reusable engineering patterns into an Obsidian Second Brain vault as atomic Markdown notes with YAML properties, wikilinks, callouts, and an automated Map of Content (00-MOC.md). Use when capturing durable institutional knowledge after solving a bug, making an architectural trade-off, or discovering a business domain invariant.
when_to_use: After resolving a non-trivial bug (RCA), recording an architectural decision (ADR), or establishing a business domain invariant that future sessions must remember. Do NOT use to dump raw chat transcripts or unverified guesses.
---

# Obsidian Second Brain & Knowledge Distillation

A chat transcript is not institutional memory — it dies when the session ends or compacts. An Obsidian vault is a **local-first, plain-Markdown knowledge graph** where verified truths compound across sessions and across harnesses (Claude Code, Antigravity, Codex).

## 1. Extract Essence, Never Dump Transcripts

A Second Brain fails when agents append verbose session logs that bloat search results. Follow three rules distilled from `kepano/obsidian-skills` and evergreen Zettelkasten engineering:

1. **One Atomic Truth per Note**: Title each note by the invariant or causal mechanism it establishes (e.g., `Stripe Webhook Idempotency Race`, `Single Postgres Queue Over Kafka`), never by date or task ticket (`Session Log 2026-11-12`).
2. **Merge Over Multiply**: If an evergreen note for the topic already exists, merge the new evidence (`[observed]` command/output) into it and update `updated:` rather than creating a competing file.
3. **Only Verified Knowledge Enters**: Every note carries a `confidence` (`observed | inferred | assumed`) and a `verified_by` command or test path. Unverified speculation stays out of the vault.

## 2. Obsidian Flavored Markdown Contract

Every distilled note uses strict Obsidian syntax (see `references/note-templates.md`):
- **YAML Frontmatter Properties**: `id`, `title`, `type` (`adr | rca | domain | pattern | moc`), `domain`, `confidence`, `verified_by`, `created`, `updated`, and `tags`.
- **Callouts for Scannability**: Start with `> [!abstract] Essence` for the one-sentence takeaway, and use `> [!warning] Failure Mode` or `> [!tip] Invariant` where relevant.
- **Graph Connectivity (`[[wikilinks]]`)**: Every note links back to `[[00-MOC]]` and to related domain or architecture notes (`[[adr-...]]`, `[[rca-...]]`, `[[domain-...]]`). Orphans are defects.

## 3. Deterministic Distillation & Vault Linting (`obsidian_distill.py`)

Never hand-format YAML frontmatter or manually edit `00-MOC.md` when the CLI tool can do it deterministically without duplicates:

```bash
# Distil or merge an atomic evergreen note and auto-update 00-MOC.md:
python3 "${CLAUDE_PLUGIN_ROOT}/skills/obsidian-second-brain/scripts/obsidian_distill.py" \
  --vault docs/brain \
  --type rca \
  --title "Stripe Webhook Idempotency Race" \
  --domain fintech \
  --summary "Concurrent webhook deliveries caused duplicate ledger postings without a unique idempotency constraint." \
  --details "Enforce INSERT ... ON CONFLICT (idempotency_key) DO NOTHING before mutating account balances." \
  --confidence observed \
  --verified-by "pytest tests/test_webhooks.py" \
  --link "[[domain-fintech-ledger]]" \
  --tag fintech --tag idempotency

# Lint the vault for missing YAML properties or broken [[wikilinks]]:
python3 "${CLAUDE_PLUGIN_ROOT}/skills/obsidian-second-brain/scripts/obsidian_distill.py" \
  --vault docs/brain --lint
```

If the user specifies an external Obsidian vault path (e.g., via `OBSIDIAN_VAULT_PATH` or `.agent-team.json`), pass that path to `--vault`; otherwise default to `docs/brain`.

## 4. Continuous Self-Adaptation Loop

Before starting complex work in a domain (`fintech`, `saas`, `ai-engineering`, `architecture`), check `docs/brain/00-MOC.md` (if present) so the team inherits prior RCA lessons and ADRs instead of repeating past mistakes.
