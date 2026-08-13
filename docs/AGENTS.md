# Agents

Eleven agents, each with a role boundary. The boundary is the point: an agent that
absorbs the next role's job breaks the handoff chain that makes the output
traceable.

| Agent | Consumes | Produces | Model | Tool access |
|---|---|---|---|---|
| `analyst` | The raw request | `docs/brief.md` | sonnet | read + write docs |
| `pm` | brief | `docs/prd.md`, `docs/stories/*.md` | sonnet | read + write docs |
| `architect` | PRD | `docs/architecture.md`, ADRs, diagrams | **opus** | read + write + bash |
| `ux-designer` | PRD | `docs/design-system.md`, `docs/ui-spec.md` | sonnet | read + write docs |
| `planner` | story + architecture | an implementation plan | sonnet | **read-only** |
| `implementer` | plan | code + tests | sonnet | full |
| `backend-implementer` | plan + contract | server code + tests | sonnet | full |
| `frontend-implementer` | plan + contract | client code + tests, stubbed then wired | sonnet | full |
| `reviewer` | diff + spec | findings by severity | **opus** | **read-only** |
| `qa-verifier` | the change | gate table + verification evidence | sonnet | read + bash |
| `debugger` | a failure | root cause + fix | **opus** | read + bash + edit |

## Why every agent pins a model

None of the eleven inherits the session's model. Eight pin `sonnet`, because
inheritance couples the whole team's cost to whatever the session is on — one
forgotten `/model` after an expensive-model session bills the entire pipeline
through the heaviest agents. `docs/MODEL-GUIDE.md` carries the full rationale
and how to raise the tier deliberately.

Three pin `opus` — the roles where reasoning depth changes the result, not
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
documented checklist, `planner` reads code and writes it down, the implementers
execute an approved plan. Putting the knowledge in skills is what makes `sonnet`
sufficient — the agent does not have to carry the doctrine in raw capability.

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
| `architect` | `artifact-templates`, `diagram-excalidraw`, `architecture-discipline`, `security-discipline` |
| `ux-designer` | `design-intelligence`, `artifact-templates` |
| `planner` | `architecture-discipline`, `code-navigation` |
| `implementer` | `tdd-discipline`, `architecture-discipline`, `security-discipline`, `quality-gates`, `code-navigation` (+ `react-performance`, `backend-discipline`, `ai-engineering` via `paths`) |
| `backend-implementer` | as `implementer`, plus `backend-discipline` always on |
| `frontend-implementer` | as `implementer`, plus `react-performance` and `design-intelligence` always on (the latter scoped to conformance — see ADR-0001) |
| `reviewer` | `quality-gates`, `architecture-discipline`, `security-discipline`, `code-navigation` (+ `react-performance`, `backend-discipline`, `ai-engineering` via `paths`) |
| `qa-verifier` | `quality-gates`, `browser-verify`, `app-verify` |
| `debugger` | `debug-rca`, `tdd-discipline`, `code-navigation` |

Every agent additionally carries `handoff-contract` and `context-discipline` —
see below.

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
typecheck  →  lint  →  dependency audit  →  test  →  build  →  static analysis
```

A secret scan runs alongside it, outside the chain, because it depends on no
stack and applies even to a project that has no other gate.

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


## Context discipline and scope

A large context window is not a large working memory. Recall degrades as the
context fills, and the model does not report an error — it simply attends less
accurately to what is buried under the noise. Two concrete failures were
showing up, and `context-discipline` addresses both.

**The team assumed it owned the whole repository.** Joining a project to work on
a C# backend does not make the React frontend your business, but nothing said
so: the reviewer reviewed it, searches walked it, and gate discovery ran its
suite. `.agent-team.json` now takes a `scope` block with `owns` / `reads` /
`excludes`. Outside `owns`, a file is evidence — readable to establish a
contract, never changed, gated, or reported as a blocking finding. When a
repository has more than one surface and no scope is declared, the team asks
once, at the start, and writes the answer down.

**Constraints did not survive a compaction.** When a long session is
summarised, what gets dropped first is what was said once at the beginning —
which is where the scope, the dependency rule, and the gate commands live. The
work then continues fluently without them. Every agent now re-states scope, the
dependency rule, and which gates have *actually been run* after any compaction,
recovering each from disk rather than from memory. A gate that cannot be traced
to a real run with an exit code is **not run**, whatever the summary says.

The skill also codifies folding: run a wide, noisy, self-contained sub-task in a
subagent and keep only what it returns. Fold the search, keep the reading — a
subagent that paraphrases the code you are about to change has cost you the
accuracy of the source.

## C# and .NET

`run-gates.sh` had the same silent-pass hole for .NET that it had for Rust and
Flutter: a solution with no `package.json` enforced nothing while appearing to.
It now discovers `*.sln`, `*.slnx`, `*.csproj` and `*.fsproj`, and runs
`dotnet format --verify-no-changes`, `dotnet build`, and `dotnet test`.

Two things are specific to this stack. The **build is the typecheck**, so unlike
JavaScript it is never opt-in behind `AGENT_TEAM_RUN_BUILD`. And there is no
separate lint gate unless the project has one — analyzers run inside the build,
and whether they block depends on `TreatWarningsAsErrors`. A .NET project with
three gates is complete, not missing two.

`app-verify` also gained `references/service-verify.md`, because its service row
was one line in a skill otherwise shaped around a device. An API breaks on the
things a green suite cannot see: a dependency that only resolves at request
time, configuration that bound to nothing, migrations not applied to the
database the process actually connected to, an endpoint never called without a
token. `qa-verifier` now loads both verification skills on a full-stack change,
since the client and the server are separate surfaces.

`stacks/csharp-dotnet.md` carries the review items a general reviewer misses:
`async void`, `.Result` / `.Wait()` deadlocks, a `CancellationToken` accepted
and then not passed on, `HttpClient` per call, EF Core lazy loading in a loop or
a query with no `Take()`, a `DbContext` in a singleton, `throw ex;` resetting
the stack trace, and `DateTime.Now` on a stored value.


## AI engineering

Every other skill here assumes the same input produces the same output. A model
call does not, and that single fact breaks three things at once.

The skill is deliberately language-neutral: it describes what a model call is,
not what an SDK looks like, so it applies unchanged in Rust or Go. Where those
ecosystems have no eval harness to reach for, you write one - a dataset file, a
runner, a pass-rate report. That changes the amount of code, not the standard of
evidence.

**It breaks the test gate.** Red-green-refactor needs a deterministic
assertion; a single passing output from a model proves nothing. `ai-engineering`
splits the work: everything around the model - parsing, validation, retrieval,
routing, tool schemas, storage - stays ordinary TDD, because that is where most
of the code and most of the bugs are. Only the model-dependent behaviour moves
to a dataset and a pass rate, with a measured baseline, a held-out split, and
the regressions listed. "It looks better now" is not a result, and a change that
fixed five cases while breaking three reads like progress.

**It breaks the flaky rule.** `quality-gates` says re-run once and treat a flip
as flaky. For a model call variation is the expected behaviour, not a broken
test - the answer is n runs and a rate against a declared threshold, not a
re-run. Both skills now say so explicitly, and the original rule still governs
every deterministic test in the same suite.

**It adds a trust boundary.** `backend-discipline` puts the boundary at the
server and authorises the object rather than the route. With a model there is a
second one: anything reaching the prompt can try to instruct it - a retrieved
document, an uploaded file, a field another user wrote, a tool result. So model
output never authorises an action on its own; the server re-checks the *user*
with the same authorisation code an ordinary endpoint uses. The model proposes,
the server decides. `references/llm-boundaries.md` also covers what the rest of
this plugin would otherwise have said nothing about: timeouts and retries on a
call that is expensive and not idempotent, iteration and spend caps on an agent
loop, an unpinned model alias changing behaviour with no diff, and prompts
containing personal data being logged to a third party.

## Python and Go

`run-gates.sh` had the silent-pass hole for both of these too, and it mattered more than the
others because AI engineering is overwhelmingly Python. It now discovers
`pyproject.toml` / `setup.cfg`, prefixes commands with `uv run` or `poetry run`
when a matching lockfile is present, and runs only the tools the project
actually configures - an invented `mypy` run on an unannotated codebase gates
nothing.

One asymmetry is deliberate: a missing linter is a **skipped** gate, but a
missing `pytest` on a project that has tests is a **failure**. One is absent by
choice; the other is unverifiable, and unverifiable must never read as a pass.

Go discovers `go.mod` and runs `gofmt`, `go vet` and `go test`. The format gate
needs care: `gofmt -l` exits 0 and prints the offending files, so the *list* is
the failure and a naive exit-code check reports a pass on unformatted code.
`stacks/go.md` and `stacks/python.md` carry the review items - an unchecked
error, a shadowed `err`, a goroutine with no way to stop, a mutex copied by
value; a mutable default argument, blocking I/O inside an async function, a
`requests` call with no timeout.
