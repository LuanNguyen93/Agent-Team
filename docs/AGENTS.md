# Agents

Nine agents, each with a role boundary. The boundary is the point: an agent that
absorbs the next role's job breaks the handoff chain that makes the output
traceable.

| Agent | Consumes | Produces | Model | Tool access |
|---|---|---|---|---|
| `analyst` | The raw request | `docs/brief.md` | opus | read + write docs |
| `pm` | brief | `docs/prd.md`, `docs/stories/*.md` | opus | read + write docs |
| `architect` | PRD | `docs/architecture.md`, ADRs, diagrams | opus | read + write + bash |
| `ux-designer` | PRD | `docs/design-system.md`, `docs/ui-spec.md` | opus | read + write docs |
| `planner` | story + architecture | an implementation plan | opus | **read-only** |
| `implementer` | plan | code + tests | inherit | full |
| `reviewer` | diff + spec | findings by severity | opus | **read-only** |
| `qa-verifier` | the change | gate table + verification evidence | inherit | read + bash |
| `debugger` | a failure | root cause + fix | opus | read + bash + edit |

## Why two agents are read-only

`planner` and `reviewer` set `disallowedTools: Edit, Write, NotebookEdit`. This
is enforcement, not etiquette:

- A planner that can edit will start editing instead of producing a plan
  specific enough for someone else to execute.
- A reviewer that can edit will fix what it finds, which loses the finding and
  removes the human decision point.

## Why review runs on fresh context

The agent that wrote the code cannot review it. It will defend its own choices,
and it cannot see the assumptions it made, because those assumptions are what
it used to write the code. `reviewer` is always spawned fresh.

## Skills per agent

Skills carry the knowledge; agents carry the role. This keeps doctrine defined
once rather than duplicated across nine system prompts.

| Agent | Skills |
|---|---|
| `analyst` | `brainstorm-grilling`, `artifact-templates` |
| `pm` | `artifact-templates` |
| `architect` | `artifact-templates`, `diagram-excalidraw` |
| `ux-designer` | `design-intelligence`, `artifact-templates` |
| `planner` | — reads the code directly |
| `implementer` | `tdd-discipline` (+ `react-performance` via `paths`) |
| `reviewer` | `quality-gates` (+ `react-performance` via `paths`) |
| `qa-verifier` | `quality-gates`, `browser-verify` |
| `debugger` | `debug-rca`, `tdd-discipline` |

Each agent declares its skills in frontmatter **and** loads them via the Skill
tool in its body. See `HARNESS-NOTES.md` §2 for why both are required.
