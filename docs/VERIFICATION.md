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

## Autonomy: does the team run without being told?

This was tested directly, with the same prompt before and after adding the
`SessionStart` routing hook, in a fresh project with no slash command typed.

**Before the hook** — nothing activated. No router, no plan, no test, no agent.
Claude wrote the feature inline and moved on. The plugin was inert until the
user typed `/build`, because a skill only loads when Claude judges it relevant
and nothing told it to route.

**After the hook** — same prompt, no command. The run produced a failing-test
file first, split a seam for the data source, named two decisions for the user,
and stated plainly that it could not execute the tests in that session so the
result was unverified.

That last part was load-bearing. The test script it wrote, `node --test test/`,
is **broken on Node 22** — it resolves `test` as a module and fails. The seven
tests themselves pass when run as `node --test test/cart.test.js`. So the thing
it flagged as unverified genuinely was broken, and the `TaskCompleted` gate hook
blocks on exactly that failure.

**What still does not happen automatically**: Claude follows the doctrine inline
rather than spawning `implementer` and `reviewer` as subagents. For most roles
inline is fine and cheaper. For `reviewer` it is a real loss, because fresh
context is the entire mechanism. Spawning works when asked; it does not happen
unprompted.

## Agent teams

Tested with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` against a fixture with
three seeded defects (crash on unknown user, `Math.random()` session tokens, an
authorisation check read into a variable and never used).

| Question | Result |
|---|---|
| Does a team actually form? | Only on an explicit request. "Spawn three teammates to review in parallel" produced **subagents** — no team directory. "Create an agent team" produced `~/.claude/teams/<id>/inboxes/{alpha,beta}.json`. |
| Do teammates message each other? | Yes. Mailboxes carried task assignments and peer messages. |
| Is peer review worth the tokens? | Yes on this evidence: a credential-free admin bypass was invisible to the security lens and surfaced only from the correctness lens, and five duplicates were reconciled before reporting. |
| Do teammates get coordination tools? | **No, with a `tools:` allowlist.** A `reviewer` teammate had exactly its five allowlisted tools and no `SendMessage`. Removing the allowlist restored `SendMessage`; `TaskList`/`TaskUpdate` were still absent, so the lead drives the task list. |
| Do teammate skills load? | Yes. `quality-gates` was fully in the teammate's context, contradicting the documentation. |
| Does read-only hold in team mode? | Yes. The `reviewer` teammate had no Edit or Write. |

The coordination-tools finding was a real defect in this plugin and is fixed:
no agent declares `tools:` any more. See `HARNESS-NOTES.md` §2b.

All three seeded defects were found, plus plaintext password storage,
non-constant-time comparison, unbounded session growth, and the observation that
the existing test would still pass if `login` returned a constant.

## Not yet verified

- `browser-verify` against a running web app
- `diagram-excalidraw` output opened in Excalidraw
- Stacks other than the TypeScript profile
