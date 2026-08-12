# Agent Team

A Claude Code plugin: one coordinated set of agents for building software, at a
planning depth that matches the size of the work.

It distills nine well-regarded skill collections into a single non-overlapping
set — see [`docs/ATTRIBUTION.md`](docs/ATTRIBUTION.md). Installing those nine
together produces overlapping triggers, contradictory instructions, and a large
context cost. This is the reconciled version.

## What it does differently

**Planning depth scales with the work.** A bug fix does not get a PRD. A new
system does not get built straight from a one-line request.

**Gates are enforced, not requested.** An instruction in a skill is something a
model can ignore. A `TaskCompleted` hook that exits 2 is not. Quality gates here
run as a hook: while the suite is red, a task cannot be marked complete, and the
real failure output goes back to the agent as feedback.

**Review runs on fresh context.** The agent that wrote the code cannot see the
assumptions it made writing it. `reviewer` is always a separate context with
Edit and Write removed — it reports, and a human decides. It keeps Bash to run
gates, and is instructed not to write through it; see `docs/AGENTS.md` for how
airtight that is.

**Absent gates are reported, never invented.** A typecheck command made up for a
project with no TypeScript config would report a pass it has not earned.

## Install

```
/plugin marketplace add LuanNguyen93/Agent-Team
/plugin install agent-team
```

Then, in a project:

```
/stack-init          # detect this project's real gate commands
/build "add a login form with validation"
```

## Commands

| Command | Does |
|---|---|
| `/build <request>` | Route through the team at the right depth |
| `/spec <request>` | Planning artifacts only, no code |
| `/ship` | Gates, review, verification, then an atomic commit |
| `/stack-init` | Detect the stack and record its gate commands |

`/ship` is user-invocable only — Claude will not decide on its own that the code
looks ready to commit.

## The nine agents

`analyst` · `pm` · `architect` · `ux-designer` · `planner` · `implementer` ·
`reviewer` · `qa-verifier` · `debugger`

Each has a role boundary and an explicit list of what it does **not** do.
`planner` and `reviewer` have Edit and Write removed by configuration rather
than by instruction.

See [`docs/AGENTS.md`](docs/AGENTS.md) and [`docs/FLOW.md`](docs/FLOW.md).

## The ten skills

Doctrine lives in skills so it is defined once rather than duplicated across
nine system prompts.

`workflow-router` · `brainstorm-grilling` · `artifact-templates` ·
`tdd-discipline` · `quality-gates` · `debug-rca` · `design-intelligence` ·
`react-performance` · `browser-verify` · `diagram-excalidraw`

`react-performance` auto-activates on JS/TS files rather than costing context
every session.

## Configuration

Gate commands come from `.agent-team.json` in your project when present,
otherwise from `package.json` scripts:

```json
{ "gates": ["pnpm typecheck", "pnpm lint", "pnpm test"] }
```

| Variable | Effect |
|---|---|
| `AGENT_TEAM_SKIP_GATES=1` | Disable the enforcement hook |
| `AGENT_TEAM_SKIP_TESTS=1` | Skip the test gate (keep typecheck and lint) |
| `AGENT_TEAM_RUN_BUILD=1` | Include the build gate |

## Agent teams

The plugin works with ordinary subagents. Agent teams are opt-in and cost
significantly more tokens — worth it for parallel review and competing-hypothesis
debugging. Read [`docs/AGENT-TEAMS.md`](docs/AGENT-TEAMS.md) first; there is a
silent trap where teammates drop their skills.

## Adding a stack

Copy `plugins/agent-team/stacks/_template.md`. Keep it a lookup table, not a
tutorial.

## Notes on the harness

[`docs/HARNESS-NOTES.md`](docs/HARNESS-NOTES.md) records the Claude Code
constraints this plugin was built against — which fields plugins silently
ignore, where enforcement is actually possible, and what breaks in agent-team
mode.

## Licence

MIT
