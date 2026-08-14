# Project Brief: Agent-Team TUI

Date: 2026-08-13
Author: analyst

## Problem

[inferred] Right now, understanding the agent-team plugin's shape — which
agent loads which skill, how a request routes QUICK/FEATURE/PROJECT, what
`.agent-team.json` says for a given project, whether an edit to an agent or
skill file is well-formed — means reading Markdown frontmatter across
`plugins/agent-team/agents/*.md` and `plugins/agent-team/skills/*/SKILL.md` by
hand, or running `claude plugin validate` and parsing its output. There is no
single place that shows the structure, lets it be edited safely, or shows what
a running session is doing while it runs.

The user's own framing: "I want to build a UI Assembly to visualize and manage
the agent-team." The user has fixed the solution shape already (terminal TUI,
view+edit+monitor, scanner-JSON-fed, living inside `plugins/agent-team/`) as a
decided constraint, not a proposal to re-litigate. This brief scopes what that
TUI can honestly do against what the repository and Claude Code actually
expose — it does not question the four decided constraints.

## Decided constraints (not open for debate)

1. **Platform**: terminal TUI, runs alongside Claude Code in the terminal. Not
   web, not Electron.
2. **Scope**: view (agent/skill/command tree and relationships, routing flow)
   + edit (agent/skill frontmatter, `.agent-team.json`, written back to disk).
   Monitoring a running session is explicitly **out of v1** — see "Monitoring
   (v2 candidate, not v1)" below.
3. **Data source**: a scanner script parses
   `plugins/agent-team/agents/*`, `plugins/agent-team/skills/*`,
   `plugins/agent-team/commands/*` frontmatter into JSON; the TUI reads that
   JSON. The scanner doubles as a CI validator.
4. **Location**: a new top-level directory at the plugin root, e.g.
   `plugins/agent-team/tui/` — never inside `.claude-plugin/`, per
   `CLAUDE.md`'s layout rule that only `plugin.json` lives there.
5. **Audience: both, as two distinct modes.** One tool, two modes, selected by
   where it is run from:
   - **Maintainer mode** — detected when running inside this plugin's own
     repo. Scans and edits `plugins/agent-team/agents|skills|commands`
     (constraint 3's scanner target).
   - **User mode** — detected when running inside a project that has
     *installed* the plugin. Views the installed team (read from the
     installed plugin's own agents/skills/commands, same scanner, different
     root) and edits that project's `.agent-team.json`.
   The mode boundary decides what is editable in each context (this repo has
   no `.agent-team.json` of its own to edit; a consuming project does not own
   `plugins/agent-team/agents/*`), so **the detection rule and what each mode
   does and does not expose is now a first-class design question for
   `architect`**, not an implementation detail — e.g. how the tool tells the
   two apart (presence of `plugins/agent-team/.claude-plugin/plugin.json` at
   the run root vs. an installed-plugin marker), and whether a single binary
   ships both modes or the modes are two entry points.
6. **Write-back safety: validate before write.** Every edit is validated in
   memory before anything touches disk: `name` uniqueness across the tree, no
   `:` in a `name`, no `hooks`/`mcpServers`/`permissionMode` in agent
   frontmatter, and the combined `description` + `when_to_use` length under
   the 1,536-character cap (HARNESS-NOTES.md §6). The write only happens if
   all checks pass. **Known limitation, recorded rather than hidden**: this
   in-memory check cannot catch plugin-wide errors that only
   `claude plugin validate` sees (e.g. issues spanning `hooks/hooks.json` or
   `plugin.json` itself). Running the full `claude plugin validate` remains a
   separate, user-triggered action — the TUI's pre-write check narrows the
   failure window, it does not replace the existing safety net.

## What already exists that this must not duplicate or fight

- **`claude plugin validate ./plugins/agent-team`** [observed, CLAUDE.md:15-19]
  already checks `plugin.json`, agent/skill frontmatter, and `hooks/hooks.json`.
  The scanner/validator this project adds is a second, repo-specific check
  (naming collisions across the tree, `name` values containing `:`, skills
  declared in an agent's frontmatter that also load via the Skill tool per
  `HARNESS-NOTES.md` §2) — it should not silently re-implement what
  `claude plugin validate` already covers.
- **`hooks/hooks.json`** [observed] wires exactly two hooks:
  `SessionStart` → `scripts/session-routing.sh` (prints routing instructions
  to context; no state written) and `TaskCompleted` →
  `scripts/gate-task-complete.sh` (runs quality gates, exits 2 on failure).
  [observed] Neither hook writes a state file, a log file, or any artifact a
  second process could read. `grep` across `gate-task-complete.sh` for
  `.json`/`write`/`log`/`state` returned nothing.
- **No `.agent-team.json` exists in this repo** [observed] — it is a
  per-consuming-project config file (documented in `README.md:119-137`), not
  part of Agent-Team's own repo. Resolved by constraint 5: editing
  `.agent-team.json` is a **user-mode** capability only; maintainer mode
  (this repo) has no such file to edit and does not offer to create one as
  part of v1.
- **Live reload is partial** [observed, HARNESS-NOTES.md §9]: editing a
  `SKILL.md` takes effect immediately; editing `agents/`, `hooks/`, or
  `.mcp.json` needs `/reload-plugins` or a restart. A TUI that edits an agent
  file and implies the change is live without saying so would be wrong.
- **Plugin subagents silently ignore `hooks`, `mcpServers`, `permissionMode`**
  [observed, HARNESS-NOTES.md §3] — any editor screen must not let a user set
  these fields on an agent without a visible warning that they will be
  silently dropped.

## Success criteria

- [OPEN: user] What does "done" look like as a demo — e.g. "I can open the
  TUI, see all 11 agents and 18 skills as a tree with load-edges, edit
  `analyst.md`'s frontmatter, save, and `claude plugin validate` still
  passes"? No measurable acceptance criteria exist yet; PM cannot write
  checkable ACs without this.
- [inferred] At minimum, from the decided scope: (a) the scanner's JSON output
  matches the real frontmatter of every agent/skill/command file — no drift;
  (b) the tool correctly identifies maintainer mode vs. user mode for a given
  run root; (c) an edit made in the TUI passes the in-memory validation
  (constraint 6) before it is written, and a rejected edit never touches
  disk; (d) a write that would pass in-memory validation but that
  `claude plugin validate` would still flag is a known, documented gap, not a
  false "done."

## Constraints

- Must live at `plugins/agent-team/tui/` (or similar plugin-root dir), never
  under `.claude-plugin/`.
- Scanner script must be runnable standalone in CI, independent of the TUI.
- Bash-adjacent tooling in this repo targets Windows Git Bash, macOS, and
  Linux and avoids `jq` (CLAUDE.md "Bash scripts" section) — [OPEN: PM/
  architect] whether that same portability bar applies to the scanner and TUI
  runtime (language/framework choice), or whether a TUI is allowed a heavier
  dependency (Node, Python, Go, Rust) not required elsewhere in this repo,
  which is currently pure Bash + Markdown + JSON.
- Frontmatter edits must respect the existing rules: agent/skill `name`
  uniqueness, no `:` in names, no `hooks`/`mcpServers`/`permissionMode` in
  plugin agent frontmatter (silently ignored, not merely discouraged).

## Monitoring (v2 candidate, not v1)

Decided: **monitoring a running session is out of scope for v1.** v1 is view
+ edit only.

Why, recorded rather than silently dropped: [observed] neither hook this
plugin wires (`SessionStart` → `session-routing.sh`, `TaskCompleted` →
`gate-task-complete.sh`) writes any state file, log, or socket a second
process could read — `grep` across `gate-task-complete.sh` for
`.json`/`write`/`log`/`state` returned nothing. The two ways to get a monitor
surface are both bets this project does not need to take to ship v1:

- **New hook instrumentation** — adding a `PreToolUse`/`PostToolUse`/
  `SubagentStop` hook that writes state for the TUI to poll would touch the
  same `hooks/hooks.json` that carries the plugin's only real enforcement
  mechanism (`TaskCompleted` gating, per `HARNESS-NOTES.md` §1). Getting that
  wrong risks breaking gating for every consumer of the plugin, not just TUI
  users.
- **Tailing Claude Code's session transcript** (`~/.claude/projects/**/*.jsonl`)
  is [assumed, unverified] to carry enough structured data to reconstruct
  "agent X is running," and its format/stability across Claude Code versions
  is undocumented here.

The surface question is **still unresolved** and stays open for whenever
monitoring is picked up as v2 — it is not answered by deferring it, only
deferred.

## Out of scope (explicit)

- Redesigning the routing model, the agent list, or the skill list — the TUI
  visualizes and edits the existing structure, it does not change agent-team's
  doctrine.
- A web or GUI version. Explicitly terminal-only per constraint 1.
- Replacing `claude plugin validate` — the scanner/validator and the
  pre-write check (constraint 6) are additive; the full validate remains a
  separate, user-triggered action.
- Monitoring a running session — see "Monitoring (v2 candidate, not v1)"
  above.
- Creating a new `.agent-team.json` from the TUI in maintainer mode — this
  repo has none of its own; that file is a user-mode concept only
  (constraint 5).

## Glossary

| Term | Definition | Identity rule |
|---|---|---|
| Agent | A role definition file in `plugins/agent-team/agents/*.md`, with YAML frontmatter (`name`, `description`, `model`, `skills`, etc.) plus a body. | Unique by `name` field, no `:`. |
| Skill | A doctrine package under `plugins/agent-team/skills/<name>/SKILL.md`, optionally with `references/`. | Unique by directory name / `name` field. |
| Command | A slash-command definition under `plugins/agent-team/commands/*.md` (e.g. `/build`, `/spec`, `/ship`, `/stack-init`). | Unique by filename/invocation string. |
| Load edge | The relationship "agent X declares skill Y in frontmatter `skills:` and also loads it via the Skill tool in its body" (HARNESS-NOTES.md §2 — both required). | Pair (agent, skill); a mismatch between the two declarations is itself a finding worth surfacing. |
| Scanner | The new script (part of this project) that parses agent/skill/command frontmatter into one JSON document, runnable both by the TUI and by CI. | Single script, single JSON schema — [OPEN: exact schema, owned by architect]. |
| Maintainer mode | The TUI mode active when run inside this plugin's own repo: scans/edits `plugins/agent-team/agents\|skills\|commands`. | Detected by run root, not user choice — [OPEN: exact detection rule, owned by architect]. |
| User mode | The TUI mode active when run inside a project that has installed the plugin: views the installed team, edits that project's `.agent-team.json`. | Detected by run root; mutually exclusive with maintainer mode. |
| Session | Deferred to v2 along with monitoring — not defined in v1 scope, since v1 does not observe a running session at all. |
| `.agent-team.json` | Per-*consuming*-project gate config (scope + gates), documented in root `README.md`. Does not exist in this repo itself; editable only in user mode (constraint 5). | One per project root that uses agent-team. |

## Open questions

The three questions raised in the earlier round (monitor surface, audience,
write-back safety) are now decided — see constraints 2, 5, 6 and "Monitoring
(v2 candidate, not v1)" above. What remains genuinely unresolved:

1. **[OPEN: user] What does "done" look like as a demo?** No measurable
   acceptance criteria exist yet beyond the inferred minimum in Success
   Criteria. PM cannot write checkable ACs without a concrete demo scenario.

2. **[OPEN: architect] Mode-detection rule.** Constraint 5 decided *that*
   there are two modes; it did not decide *how* the tool tells them apart at
   a given run root (e.g. presence of
   `plugins/agent-team/.claude-plugin/plugin.json` vs. an installed-plugin
   marker), nor whether one binary serves both modes or the modes are
   separate entry points.

3. **[OPEN: architect] Scanner JSON schema.** Constraint 3 decided the
   scanner's existence and its two consumers (TUI, CI); the exact schema is
   not defined in this brief.

4. **[OPEN: PM/architect] Runtime/language portability bar.** Unchanged from
   the prior round: whether the scanner and TUI must hold the same Bash/no-`jq`
   portability bar as the rest of this repo's scripts, or may take on a
   heavier dependency (Node, Python, Go, Rust).

5. **[OPEN: whoever picks up v2] Monitoring surface.** Deferred, not
   resolved — see "Monitoring (v2 candidate, not v1)."

## Assumptions

- [assumed] The TUI is meant to be usable without any change to Claude Code
  itself — no custom Claude Code build, only what a hook script and a
  standalone terminal process can observe.
- [assumed] "Scanner runnable in CI" means CI for *this* repo (Agent-Team),
  not CI for a consumer project — not confirmed with the user.

## Not covered

- No design work was done — no screen layout, no framework choice, no ADR,
  no mode-detection rule, no scanner schema. That is `architect`/
  `ux-designer` territory once the PRD exists.
- No spike was run to confirm whether Claude Code's session transcript
  (`~/.claude/projects/**/*.jsonl`) is a stable, parseable surface — moot for
  v1 now that monitoring is deferred to v2, but still unresolved for whoever
  picks that up.
- Existing `claude plugin validate` internals were not read line-by-line;
  only its documented scope (CLAUDE.md:15-19, HARNESS-NOTES.md §10) was used.

## Open

- Open Question 1 (demo/acceptance definition) — resolves with the user;
  blocks `pm` from writing checkable ACs.
- Open Questions 2–3 (mode-detection rule, scanner schema) — resolve with
  `architect` once the PRD exists.
- Open Question 4 (runtime portability bar) — resolves with `pm`/`architect`.
- Open Question 5 (monitoring surface) — deferred to v2; resolves with
  whoever picks up that work, not blocking v1.
