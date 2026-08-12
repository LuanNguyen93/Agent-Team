# Agents

Eleven agents, each with a role boundary. The boundary is the point: an agent that
absorbs the next role's job breaks the handoff chain that makes the output
traceable.

| Agent | Consumes | Produces | Model | Tool access |
|---|---|---|---|---|
| `analyst` | The raw request | `docs/brief.md` | inherit | read + write docs |
| `pm` | brief | `docs/prd.md`, `docs/stories/*.md` | inherit | read + write docs |
| `architect` | PRD | `docs/architecture.md`, ADRs, diagrams | **opus** | read + write + bash |
| `ux-designer` | PRD | `docs/design-system.md`, `docs/ui-spec.md` | inherit | read + write docs |
| `planner` | story + architecture | an implementation plan | inherit | **read-only** |
| `implementer` | plan | code + tests | inherit | full |
| `backend-implementer` | plan + contract | server code + tests | inherit | full |
| `frontend-implementer` | plan + contract | client code + tests, stubbed then wired | inherit | full |
| `reviewer` | diff + spec | findings by severity | **opus** | **read-only** |
| `qa-verifier` | the change | gate table + verification evidence | inherit | read + bash |
| `debugger` | a failure | root cause + fix | **opus** | read + bash + edit |

## Why only three agents pin a model

Eight of the eleven omit `model`, so they inherit the session's model and the user's
choice governs. Pinning `opus` everywhere would override that choice and make a
PROJECT run expensive without changing the output much.

The three exceptions are the roles where reasoning depth changes the result, not
just the prose:

- **`debugger`** — root cause analysis is exactly where a weaker model stops at
  the first plausible theory. A confident wrong diagnosis costs more than no
  diagnosis.
- **`reviewer`** — it is the safety net, and its failures are silent. A missed
  defect looks identical to a clean review.
- **`architect`** — structural decisions are expensive to reverse, and the cost
  lands months later.

The other eight do structured work that the skills already specify: `analyst` asks
questions, `pm` transforms a brief against a template, `ux-designer` applies a
documented checklist, `planner` reads code and writes it down. Putting the
knowledge in skills is what makes this possible — the agent does not have to
carry the doctrine in raw capability.

Override any of them per project by copying the agent into `.claude/agents/`,
or per invocation when spawning.

## Why two agents are read-only

`planner` and `reviewer` set `disallowedTools: Edit, Write, NotebookEdit`:

- A planner that can edit will start editing instead of producing a plan
  specific enough for someone else to execute.
- A reviewer that can edit will fix what it finds, which loses the finding and
  removes the human decision point.

**This is a strong constraint, not an airtight one.** Both agents keep Bash —
`reviewer` needs it to run gates and read git history, `planner` needs it to
explore the repo — and Bash can write a file through `sed`, a heredoc, or a
redirect. Both agent bodies forbid this explicitly, and in testing `reviewer`
declined the escape hatch unprompted when told to fix what it found. If you need
a hard guarantee rather than a strong default, add a `PreToolUse` deny rule for
write-shaped Bash commands scoped to these agent types.

## Why review runs on fresh context

The agent that wrote the code cannot review it. It will defend its own choices,
and it cannot see the assumptions it made, because those assumptions are what
it used to write the code. `reviewer` is always spawned fresh.

## Who decides when a boundary is disputed

`reviewer` can report that an agent has absorbed the next role's job. It cannot
rule on it — it is read-only by design, and ruling is not reporting. The context
that wrote the code cannot rule either; it would be judging its own boundary.

So: **a role-boundary finding escalates to `architect`, which rules by writing an
ADR in `docs/adr/`.** `architect` already owns component boundaries and already
writes ADRs, so this is an existing job pointed at the agent team itself rather
than a new one.

The trigger is narrow, and staying narrow is what keeps this from being
ceremony. It applies only to a finding about **which agent owns something** — a
skill two agents both want, a section of prose that belongs to another agent's
file, a responsibility that two roles both claim or both disclaim. A finding
about code is a finding about code and goes back the normal way.

The ruling names the option not taken and the cost the chosen option pays, like
any other ADR. Its value is that the dispute stops being re-argued by whoever
reads the files next. `docs/adr/0001-role-boundary-rule-and-arbitration.md` is
the first, and sets two precedents worth knowing before you open a new one:

- **A shared skill is scoped, not owned.** Two agents may carry the same skill
  when the downstream one states the narrower scope in its own file and reports
  the decisions it had to make.
- **An agent's file names the obligation it owns, never the routing that
  consumes it.** Stating a condition, a list, or a procedure that a skill already
  carries is the duplication `CLAUDE.md` forbids; one clause of motivation
  carrying no criteria has no surface to drift against.

## Skills per agent

Skills carry the knowledge; agents carry the role. This keeps doctrine defined
once rather than duplicated across eleven system prompts.

| Agent | Skills |
|---|---|
| `analyst` | `brainstorm-grilling`, `artifact-templates` |
| `pm` | `artifact-templates` |
| `architect` | `artifact-templates`, `diagram-excalidraw`, `architecture-discipline` |
| `ux-designer` | `design-intelligence`, `artifact-templates` |
| `planner` | `architecture-discipline`, `code-navigation` |
| `implementer` | `tdd-discipline`, `architecture-discipline`, `quality-gates`, `code-navigation` (+ `react-performance`, `backend-discipline` via `paths`) |
| `backend-implementer` | as `implementer`, plus `backend-discipline` always on |
| `frontend-implementer` | as `implementer`, plus `react-performance` and `design-intelligence` always on (the latter scoped to conformance — see ADR-0001) |
| `reviewer` | `quality-gates`, `architecture-discipline`, `code-navigation` (+ `react-performance`, `backend-discipline` via `paths`) |
| `qa-verifier` | `quality-gates`, `browser-verify`, `app-verify` |
| `debugger` | `debug-rca`, `tdd-discipline`, `code-navigation` |

Every agent additionally carries `handoff-contract` — see below.

Each agent declares its skills in frontmatter **and** loads them via the Skill
tool in its body. See `HARNESS-NOTES.md` §2 for why both are required.

## Why every agent carries `handoff-contract`

A handoff is where a hallucination gets laundered. The upstream agent hedges —
"the session store is probably Redis" — and the downstream agent, reading a plan
rather than a conversation, drops the hedge and builds on it. Nobody invented
anything; the confidence simply did not survive the trip.

Three mechanisms in the skill, all cheap:

1. **Three labels — `[observed]`, `[inferred]`, `[assumed]`.** An unlabelled
   claim reads as observed, which is exactly the failure mode, so anything else
   must be marked. `[assumed]` is what a downstream agent verifies first.
2. **Evidence, not paraphrase.** `file:line`, the command with its exit code,
   the real output. Paraphrasing an error is how a hard failure becomes a soft
   one.
3. **A closing block** — assumptions, not covered, open — present even when
   empty. An empty list is information; an absent list is not.

`references/role-contracts.md` fixes the report shape per role, so each agent
produces the fields its specific consumer needs rather than a generic summary.

This is deliberately not a per-agent instruction. Nine copies of the same rule
drift; one skill does not.

## How the architecture stays consistent across a run

`architect` produced a design; nothing used to hold later agents to it. The
components table said what each part was *not* responsible for, and then
`planner` read code, `implementer` matched surrounding style, and `reviewer`
checked spec plus engineering. Three reasonable steps, none of which looks at
the agreed shape — which is exactly how a codebase acquires two architectures.

`architecture-discipline` closes it with one declared artifact and three checks:

- **`architect`** declares a **dependency rule** — a table of which layer may
  import which — in `docs/architecture.md`. Presets: clean/hexagonal, simple
  layered, or a recorded "no layering, and why". Declaring none is a valid
  decision; leaving it unstated is not, because then every commit invents one.
- **`planner`** places each new file in a layer and hands back to `architect`
  rather than planning a step that crosses the rule.
- **`implementer`** stays inside it, and stops rather than crossing it quietly.
- **`reviewer`** gains **Axis 3**, where a crossing import is *blocking* — the
  first one is what makes the second look normal.

The same skill carries the two rules that pull against structure, because they
are the same judgement call:

- **Over-engineering is a finding**, not a style note: an interface with one
  implementation, a forwarding layer, a generic built from one case. Structure
  is read far more often than it is written. Patterns are used where they remove
  a conditional that would otherwise grow — and *missing* an obvious one costs
  as much as inventing one nobody needed.
- **Algorithmic cost is stated.** Find the input bound first: at a small bound
  the readable loop is correct and a hand-built index is over-engineering; at an
  unbounded one the same loop is an outage.

`backend-discipline` deliberately does not repeat any of this — it points here
and stays on what is specific to the server.

## The SonarQube standard

The gate chain ends in static analysis where the project configures one:

```
typecheck  →  lint  →  test  →  build  →  static analysis
```

Two things had to change for that to mean anything.

**It is judged on new code.** Sonar's default gate asks for zero new issues,
100% of security hotspots reviewed, ≥80% coverage and ≤3% duplication *on the
change* — which is why a legacy repository with thousands of existing findings
can still pass. `quality-gates` → `references/sonarqube.md` carries the
thresholds, and the instruction to read the project's own gate rather than
assume the defaults.

**Passing it dishonestly is enumerated, not left to judgement.** `// NOSONAR`, a
hotspot marked safe without a reason, a path added to `sonar.exclusions`, a test
that executes a line without asserting anything, a shortened New Code period —
each is listed as forbidden alongside the existing `@ts-ignore` and skipped-test
rules, because they are the same move.

`implementer` now loads `quality-gates` and writes to the standard rather than
repairing afterwards: bounded cognitive complexity, no copied blocks, no empty
`catch`, no commented-out code or bare `TODO` in the diff, and the error path
covered. Fixing smells after the fact is how a change acquires a second, worse
diff.

The gate is **opt-in locally** — `AGENT_TEAM_RUN_SONAR=1` — because analysis
needs a server and a token and is far slower than the local chain. Without a
configured scanner the gate is **absent**, which is a result, not a pass.

## Finding code by structure, not by crawling

`code-navigation` distils what a code index (CodeGraph, in the case this was
drawn from) does, into rules that hold whether or not the repository has one.

The measured claim behind it: on seven open-source repos, an agent answering an
architecture question **with** an index used 2–3 tool calls and read **zero**
files, against 5–57 calls and up to 4.3M tokens without. The reason is not
speed — it is that the crawl reconstructs a call graph by hand and gets it
subtly wrong.

Four rules survive the tool:

- **Order of discovery**: index → language tooling → search → reading files.
  Most crawling is search and reading doing the index's job.
- **A search that found nothing has proved nothing.** Text search cannot follow
  dynamic dispatch, DI, string-keyed registries, reflection, generated code, or
  convention-based routing. An empty `rg` supports "there may be no *static*
  callers" and nothing stronger — which is why the skill requires the searched
  scope to be reported alongside the result.
- **Blast radius before a shared change.** `planner` names the callers,
  `implementer` asks which of them assumed the old behaviour, `reviewer` treats
  an unexamined caller as a finding. A signature that still compiles but means
  something different is the failure mode.
- **Do not delegate a structural question to a file-reading subagent.** It pays
  the crawl twice: the subagent burns context rebuilding what one query returns,
  and its summary still has to be verified. This is CodeGraph's own documented
  caveat, and it generalises.

Plus one that ties back to `handoff-contract`: **an index can be stale**. Any
derived view is `[observed]` only when its freshness was checked; otherwise it
is `[inferred]`.

`references/codegraph.md` carries the commands, and only applies when the repo
already has a `.codegraph/` directory — indexing is the user's decision, not an
agent's. `references/without-an-index.md` reproduces each habit with compilers,
`rg`, and `git log -S`, and is explicit that the result is an approximation to
be labelled as one.

## Stacks beyond JavaScript

The doctrine skills are language-agnostic, but three things were not, and a
Rust + Flutter project exposed all three:

**The gate runner only knew `package.json`.** A Rust or Flutter project has no
such file, so discovery fell through to `exit 0` — the `TaskCompleted` hook
enforced nothing while looking like it did, which is the worst possible failure
for a gate. It now discovers `Cargo.toml` (`cargo fmt --check`, `clippy -D
warnings`, `cargo test`) and `pubspec.yaml` (`dart format`, `analyze`, `test`)
as well, and a project with several manifests runs all of them.

A manifest present with its toolchain missing — `Cargo.toml` and no `cargo` —
**fails** rather than passing. It is the same rule as an absent gate: what
cannot be verified is not a pass.

**`browser-verify` assumes a browser.** `qa-verifier` loaded it unconditionally,
so on a Flutter app it would run the gates and stop, losing half its value.
`app-verify` covers mobile, desktop, CLI, and services: cold start rather than
hot reload, the failure path triggered on purpose, permissions on a device that
has not granted them, and "no device available" reported as **blocked** rather
than passed. `qa-verifier` now picks the skill that matches the surface.

**Stack profiles existed only for React.** `stacks/rust.md` and
`stacks/flutter.md` carry what a general reviewer misses — a `std::sync::Mutex`
held across an `.await`, `unsafe` with no `// SAFETY:` comment, a `BuildContext`
used after an `await`, a missing `dispose()`, a `ListView` with fixed children.

`backend-discipline` also gained `**/handlers/**` to its `paths`, because that
is where Axum and Actix put what Express calls `routes/`.
