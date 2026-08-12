# Agent Team — repo conventions

This repository *is* a Claude Code plugin. Everything here is configuration and
prose that another Claude reads at runtime, so the writing is the product.

## Layout rules that are not negotiable

- Only `plugin.json` lives in `plugins/agent-team/.claude-plugin/`.
  `agents/`, `skills/`, `commands/`, `hooks/`, `scripts/`, `stacks/` sit at the
  plugin root.
- `marketplace.json` lives in `.claude-plugin/` at the **repo** root.
- Agent and skill `name` values must be unique across the tree and cannot
  contain `:`.

## Before committing

```bash
claude plugin validate ./plugins/agent-team
```

Also check that no agent frontmatter uses `hooks`, `mcpServers`, or
`permissionMode` — plugins ignore all three silently.

## Writing rules

- **English throughout**, including artifact templates.
- Skills carry knowledge; agents carry a role. Never duplicate doctrine into an
  agent body — reference the skill instead.
- Every agent needs an explicit "what you do not do" section. Role boundaries
  are what keep the handoff chain intact.
- Every new agent must load its skills via the Skill tool in the body, in
  addition to declaring `skills:` in frontmatter. See `docs/HARNESS-NOTES.md` §2.
- Keep `description` + `when_to_use` under 1,536 characters combined.
- Skills use progressive disclosure: a short `SKILL.md`, detail in `references/`.

## Bash scripts

Hook scripts run on Windows (Git Bash), macOS, and Linux. Keep them POSIX-ish,
avoid tools that may be absent (`jq` in particular), and always handle the case
where the project has no gate command at all — absent must report as absent, not
as a pass.
