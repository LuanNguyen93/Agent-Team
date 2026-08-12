# Choosing models and effort

Sourced from Anthropic's own documentation. Links at the bottom.

## The pricing gap is smaller than it feels

Per 1M tokens, Anthropic first-party API rates:

| Model | Input | Output |
|---|---|---|
| Claude Fable 5 | $10 | $50 |
| **Claude Opus 5** | **$5** | **$25** |
| **Claude Sonnet 5** | **$3** ($2 intro through 2026-08-31) | **$15** ($10 intro) |
| Claude Haiku 4.5 | $1 | $5 |

**Opus 5 costs about 1.7x Sonnet 5** — 2.5x at the current introductory rate. Not
the 5x gap earlier model generations had. Before restructuring an agent roster
around model tier, check whether tier is actually where your spend is going.

## Anthropic's decision framework

From the model-and-effort blog post, and it is the sharpest heuristic here:

> **When Claude gets it wrong, ask: did it lack knowledge, or lack effort?**
> Knowledge deficit → larger model. Effort deficit → higher effort level.

Two separate dials. Reaching for a bigger model when the real problem was
shallow reasoning wastes money and doesn't fix the failure.

| Reach for a **smaller model** | Reach for a **larger model** |
|---|---|
| Routine, precisely-described edits | Subtle bugs, unfamiliar domains |
| Mechanical changes | Architecture decisions under ambiguity |
| Questions about code already in context | Multi-step work where smaller models hit a ceiling |

| Raise **effort** when Claude | |
|---|---|
| Skips files without reading them | |
| Neglects to run tests | |
| Abandons a multi-step refactor partway | |

Effort levels are `low`, `medium`, `high`, `xhigh`, `max`; the default is `high`
on every model that supports it. Thinking tokens bill as **output** tokens, so
effort is a direct cost lever — often a larger one than model tier.

## Where the spend actually goes

The costs page names the usual culprits, and model tier is only one of them:

> Unexpectedly high spend usually traces back to **long sessions that were never
> cleared**, or to **Opus left as the default model**.

Note the order. Token cost scales with context size, and Claude Code sends the
full conversation with every request. A one-line question in a session that has
been open all day still draws usage for the whole conversation.

Levers, roughly by size of effect:

1. **`/clear` between unrelated tasks.** Stale context is billed on every
   subsequent message.
2. **Effort level** (`/effort`) — thinking tokens are output tokens.
3. **Model tier** (`/model`) — the 1.7x lever.
4. **Keep CLAUDE.md under 200 lines**; move reference material to skills, which
   load on demand.
5. **Delegate verbose work to subagents** so logs and test output stay out of
   the main context.
6. **Prefer CLI tools over MCP servers** where one exists (`gh`, `aws`, `gcloud`)
   — no per-tool listing cost.

Measure with `/usage` (per-model token breakdown, and on a plan, an attribution
breakdown by skill / subagent / MCP server) and `/context`.

## What this plugin does, and why

Every agent pins a `model` — none inherits the session. Three pin `opus`
(`debugger`, `reviewer`, `architect`); the other eight pin `sonnet`.

Earlier versions let those eight inherit so the user's `/model` choice governed
the whole team. That was reversed deliberately: inheritance couples every
subagent's cost to whatever the session happens to be on, so one forgotten
`/model` after a Fable session bills the entire pipeline — and `implementer`,
the heaviest token consumer, is exactly where it lands. A hook cannot catch
this (hook input does not carry the session model), so the pin is the only
deterministic guard. The `sonnet` choice follows the decision framework above:
those eight roles do routine, precisely-specified work whose knowledge lives in
skills.

The cost of the reversal: `/model` now changes only the main conversation. To
raise the whole team's tier, edit the `model:` lines in
`plugins/agent-team/agents/` — one line each.

**This is a deliberate departure from Anthropic's subagent guidance**, which is:

> Start with default settings. Adjust based on task complexity and observed
> failure patterns rather than preemptively increasing either setting.

The pins are a preemptive increase. The argument for them is that all three
roles fail *silently* — a missed defect looks exactly like a clean review, a
confidently wrong root cause looks like a diagnosis, and a bad structural
decision surfaces months later. "Adjust based on observed failure" assumes you
observe the failure.

That argument is reasonable, not settled. If you would rather follow the default
guidance, delete the `model: opus` line from those three files — one line each.

## Agent teams cost roughly 7x

Agent teams use approximately **7x more tokens** than a standard session when
teammates run in plan mode: each teammate is a separate Claude instance with its
own context window. If you enable them:

- Use Sonnet for teammates
- Keep teams to 3–5
- Keep spawn prompts focused — teammates load CLAUDE.md, MCP servers, and skills
  automatically, and everything in the spawn prompt adds on top
- Shut teammates down when their work is done; an idle teammate still consumes

Teammates do **not** inherit the lead's `/model` by default — there is a separate
**Default teammate model** setting in `/config`. If team costs come in above
expectation, check that first.

## Sources

- [Choosing a Claude model and effort level in Claude Code](https://claude.com/blog/claude-model-and-effort-level-in-claude-code) — the decision framework above
- [Model configuration](https://code.claude.com/docs/en/model-config) — effort levels, defaults, `/effort`, `/model`
- [Manage costs effectively](https://code.claude.com/docs/en/costs) — spend drivers, `/usage`, agent team costs
- [Pricing](https://platform.claude.com/docs/en/pricing) — current per-token rates
- [Subagents → Choose a model](https://code.claude.com/docs/en/sub-agents) — model resolution order for subagents
- [Agent teams](https://code.claude.com/docs/en/agent-teams) — teammate model setting, token scaling
