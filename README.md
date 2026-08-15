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

**Commits carry no tool attribution.** No `Co-Authored-By` naming an AI, no
"generated with" line, no emoji badge. Authorship is a statement about who is
accountable for the change, and that is the person who reviewed it — not the
tool that typed it. Ask for the trailer and you get it; the default is off.

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
| `/agent-team:review-panel` | Multi-lens review with adversarial verification (workflow) |

Commands also resolve under their namespaced form, `/agent-team:build`. Use that
form if a bare name collides with another plugin.

## The review workflow

`review-panel` is a [dynamic workflow](https://code.claude.com/docs/en/workflows)
rather than a skill, because the orchestration is worth codifying:

1. establish the scope of the change
2. four independent lenses review in parallel — correctness, security, tests,
   spec compliance
3. every finding is handed to a skeptic told to **refute** it, defaulting to
   refuted when the failure cannot be demonstrated
4. what survives is deduplicated and ranked

A single sequential reviewer anchors on one class of issue and stops. Splitting
the lenses covers more ground, and the refutation pass is what keeps
plausible-but-wrong findings out of the report — those are what train people to
ignore reviews.

The linear `brief → PRD → architecture` chain deliberately stays a skill, not a
workflow: workflows take no user input mid-run, and that chain needs your
sign-off after the PRD.

`/ship` is user-invocable only — Claude will not decide on its own that the code
looks ready to commit.

## The eleven agents

`analyst` · `pm` · `architect` · `ux-designer` · `planner` · `implementer` ·
`backend-implementer` · `frontend-implementer` · `reviewer` · `qa-verifier` ·
`debugger`

`backend-implementer` and `frontend-implementer` are the parallel split: when a
change spans both surfaces **and** the plan carries a contract with its error
cases, they run at the same time, neither waiting for the other.

Each has a role boundary and an explicit list of what it does **not** do.
`planner` and `reviewer` have Edit and Write removed by configuration rather
than by instruction.

See [`docs/AGENTS.md`](docs/AGENTS.md) and [`docs/FLOW.md`](docs/FLOW.md).

## The eighteen skills

Doctrine lives in skills so it is defined once rather than duplicated across
nine system prompts.

`workflow-router` · `brainstorm-grilling` · `artifact-templates` ·
`tdd-discipline` · `typescript-discipline` · `quality-gates` · `debug-rca` · `design-intelligence` ·
`react-performance` · `browser-verify` · `diagram-excalidraw` ·
`handoff-contract` · `backend-discipline` · `architecture-discipline` ·
`code-navigation` · `app-verify` · `context-discipline` · `ai-engineering` ·
`security-discipline`

`react-performance`, `backend-discipline`, `typescript-discipline` and `ai-engineering` auto-activate on matching paths
rather than costing context every session.

## Configuration

Gate commands come from `.agent-team.json` in your project when present,
otherwise discovered from `Cargo.toml`, `pubspec.yaml`, a `*.sln` / `*.csproj`,
`pyproject.toml`, `go.mod`, and `package.json` scripts — in that order, and a project can have more than one:

```json
{
  "scope": { "owns": ["backend/**"], "reads": ["web/src/api/**"], "excludes": ["web/**"] },
  "gates": ["cd backend && dotnet build --nologo", "cd backend && dotnet test --nologo --no-build"]
}
```

`scope` declares which part of the repository this team owns when you do not own
all of it. Outside it, files are read as evidence only — never changed, gated or
reviewed. Without it the team searches, gates and reviews the whole repo,
including the surface another team maintains.

Declare them explicitly for anything the discovery cannot know: a Cargo
workspace, a non-default feature set, `cargo nextest`, or a monorepo where the
commands run from subdirectories.

When a manifest is present but its toolchain is not on `PATH` — a `Cargo.toml`
with no `cargo`, a `.sln` with no `dotnet` — the run **fails** rather than reporting a pass it could not
earn.

| Variable | Effect |
|---|---|
| `AGENT_TEAM_SKIP_GATES=1` | Disable the enforcement hook |
| `AGENT_TEAM_SKIP_TESTS=1` | Skip the test gate (keep typecheck and lint) |
| `AGENT_TEAM_RUN_BUILD=1` | Include the build gate (`cargo build --release`, `flutter build`, `go build ./...`, `<pm> run build`; .NET always builds, since that is its typecheck) |
| `AGENT_TEAM_RUN_SONAR=1` | Include the static-analysis gate (`sonar` script, or `sonar-project.properties` + `sonar-scanner`) |
| `AGENT_TEAM_SKIP_AUDIT=1` | Skip the dependency-audit gate (`npm audit`, `pip-audit`, `govulncheck`, `cargo audit`, `dotnet list package --vulnerable`, `osv-scanner`) |
| `AGENT_TEAM_SKIP_SECRET_SCAN=1` | Skip the secret scan (`gitleaks`, or `trufflehog`) |
| `AGENT_TEAM_SCAN_HISTORY=1` | Scan the full git history for secrets instead of the working tree — slow |
| `AGENT_TEAM_FORCE_AUDIT=1` | Re-run the dependency audit even when no manifest or lockfile has changed since it last passed |
| `AGENT_TEAM_ALWAYS_GATE=1` | Run the gates even when every changed path is prose (`*.md`, `docs/**`, `LICENSE`) |
| `AGENT_TEAM_AUDIT_TTL_HOURS=<n>` | How long a cached audit pass stays valid (default 24) |

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
