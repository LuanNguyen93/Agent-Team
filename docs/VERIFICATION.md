# Verification

What was actually exercised, on Claude Code v2.1.228, Windows, against a real
TypeScript project with working `typecheck` and `test` gates (tsc + vitest).

## Manifests

| Check | Result |
|---|---|
| `claude plugin validate ./plugins/agent-team` | PASS |
| `claude plugin validate .` (marketplace) | PASS |

`metadata.pluginRoot` with a shorthand `source` **failed** validation despite
being documented. The marketplace uses the explicit `./plugins/agent-team` path.

## Installation

Added the local directory as a marketplace and installed the plugin. All nine
agents and all ten skills were visible in a fresh session, plus `build`, `spec`
and `stack-init` as commands.

`ship` was **not** visible — correct, because it sets
`disable-model-invocation: true`. That flag is doing its job.

Note: the marketplace source form is `./` — a bare `.` is rejected. After
`plugin marketplace update`, commands briefly resolve only under their
namespaced form (`/agent-team:build`) until the plugin reloads.

## The enforcement hook

The `TaskCompleted` hook was driven directly with a hook payload on stdin:

| Scenario | Expected | Result |
|---|---|---|
| Green suite | exit 0, silent | PASS |
| Failing vitest test | exit 2, real failure output as feedback | PASS |
| Type error present | typecheck fails **first**, test never runs | PASS |
| Explicit gates in `.agent-team.json` | run in declared order, block on failure | PASS |
| No `package.json` | exit 0, no invented gate | PASS |

The blocked case returned the actual vitest diff — expected/received, file and
line — not a paraphrase.

## Routing

Three requests, classified with reasoning:

| Request | Tier | Correct |
|---|---|---|
| Fix a bug in one known function | QUICK | yes |
| Add a user-management screen with permissions | FEATURE | yes |
| Build a task-management app from scratch | PROJECT | yes |

The FEATURE case additionally surfaced an unresolved question (role-based vs
granular permissions) before proposing work, which is the grilling behaviour
the router is supposed to trigger.

## Read-only agents

`reviewer` was explicitly instructed to fix what it found. It reported having no
Edit or Write tool, declined, and the file was unchanged on disk.

It also identified a genuine hole: it retains Bash and could have written
through `sed`. It declined unprompted, but both `reviewer` and `planner` now
forbid this explicitly in their bodies, and `docs/AGENTS.md` states plainly that
this is a strong default rather than an airtight guarantee.

## End-to-end

`/agent-team:build` on a real regex bug in the fixture project:

- classified QUICK and said so before acting
- routed implementer, then reviewer on fresh context
- the reviewer caught that the reported case `a@..b` is also a *leading*-dot
  case, so a fix banning only leading dots would pass while leaving the stated
  bug — a test for `a@b..com` was added on that finding
- the produced fix passes 7/7 tests when run afterwards

**The most important result**: Bash was denied in that headless session, so the
suite never ran. The agent reported "the test gate never ran" and "RED was never
observed", and explicitly declined to claim the code worked. It did not
fabricate a passing gate. That honesty is the property the whole design depends
on.

## Workflow

`workflows/review-panel.js` parses as an async body (top-level `return` and
`await` are legal there because the runtime wraps the script), its `meta` block
is a pure literal, and the four phase titles match the `phase()` calls. After
install it registers as `/agent-team:review-panel`.

Not yet run end to end against a real diff.

## Not yet verified

- Agent-team mode (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), including whether
  teammates load their skills through the Skill tool as intended
- `browser-verify` against a running web app
- `diagram-excalidraw` output opened in Excalidraw
- Stacks other than the TypeScript profile
