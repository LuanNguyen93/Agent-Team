# PRD: Agent-Team TUI

## Context

[observed] `docs/brief.md` fixes four things as decided, not open: terminal
TUI, view+edit scope (monitoring deferred to v2), a scanner-script→JSON
pipeline that also serves as a CI validator, and a home at
`plugins/agent-team/tui/`. This PRD resolves the brief's four open items —
demo/definition of done, mode detection, scanner JSON schema, runtime
portability — as **PM proposals for user sign-off**, not restatements of
brief content. Everything marked "PM proposal" below is new and needs
explicit approval before `architect` designs against it.

## Users and needs

| Role | Needs | Why |
|---|---|---|
| Maintainer (works inside this repo) | See the full agent/skill/command tree and load-edges; edit agent/skill frontmatter safely | Currently must read Markdown frontmatter by hand or parse `claude plugin validate` output [observed, brief.md:8-15] |
| Consumer (works inside a project with agent-team installed) | View the installed team; edit that project's `.agent-team.json` | Same visibility gap, different root and different edit target [brief.md constraint 5] |

## Scope

### In scope
- A scanner script that parses `plugins/agent-team/agents/*.md`,
  `plugins/agent-team/skills/*/SKILL.md`, `plugins/agent-team/commands/*.md`
  frontmatter into one JSON document (FR-3).
- The scanner runnable standalone in CI, independent of the TUI (FR-3).
- A terminal TUI that reads the scanner's JSON and renders the tree +
  load-edges (FR-4).
- Mode detection: maintainer vs. user, with an explicit override (FR-2).
- Frontmatter edit + write-back with in-memory validation (FR-5, FR-6).
- `.agent-team.json` edit in user mode (FR-7).

### Out of scope
- Monitoring a running session — deferred to v2 [brief.md "Monitoring (v2
  candidate, not v1)"]. No hook instrumentation, no transcript tailing.
- A web or GUI version — terminal only [brief.md constraint 1].
- Replacing `claude plugin validate` — the TUI's pre-write check is additive,
  narrows the failure window, does not replace it [brief.md constraint 6].
- Creating a new `.agent-team.json` from maintainer mode — this repo has
  none of its own [brief.md, out of scope list].
- Redesigning routing, the agent list, or the skill list — view/edit the
  existing structure only [brief.md, out of scope list].

## Resolutions of the brief's open items (PM proposals — need sign-off)

### 1. Definition of done / demo (PM proposal)

**Proposed demo script**, checkable end to end:

1. Run the TUI from the Agent-Team repo root. It reports maintainer mode.
2. The tree view shows exactly 11 agents, 18 skills, 4 commands [observed
   counts from `plugins/agent-team/agents`, `/skills`, `/commands` as of this
   PRD], each edge between an agent and a skill it both declares in
   frontmatter `skills:` and loads via the Skill tool in its body.
3. Open `analyst.md` in the editor screen, change its `color` field, save.
4. The TUI confirms the write; `claude plugin validate ./plugins/agent-team`
   still exits 0.
5. Attempt an edit that adds `hooks:` to an agent's frontmatter. The TUI
   rejects it before writing, the file on disk is unchanged, and the
   rejection reason is shown.
6. Run the scanner standalone (no TUI) against the same repo; its JSON output
   is byte-identical in content to what the TUI loaded in step 2.

This script is FR-8's acceptance criteria, verbatim. If the user rejects this
demo as "done," FR-8 must be rewritten before `architect` starts.

### 2. Mode-detection rule (PM proposal — architect refines the mechanism)

**Proposed rule**: at the run root (current working directory, or a
`--path` override):
- If `<.claude-plugin/plugin.json>` exists at the root **and** its `name`
  field equals `agent-team` → **maintainer mode**.
- Else if a directory named `agent-team` exists under a plugin cache/install
  location reachable from the root (exact detection mechanism is
  `architect`'s to design — the brief already flags this as open) →
  **user mode**, scanning the installed copy.
- Else if neither is detected → the TUI does not guess. It reports
  "mode undetermined" and requires an explicit `--mode maintainer|user` flag
  or interactive prompt before doing anything else (FR-2).
- A detected mode is always overridable with an explicit flag, and the
  active mode is always displayed in the TUI's header, never left implicit.

This is a proposal for the *rule's shape* (detect, but always allow
override, never silently guess). The literal detection mechanism —
which files/paths to probe — is `architect`'s design job per the brief.

### 3. Scanner JSON schema (PM proposal, field-level — architect owns exact types/versioning)

Proposed top-level shape, since scanner/TUI/CI all depend on it existing
before any other work starts:

```
{
  "schemaVersion": "1.0",
  "generatedAt": "<ISO 8601>",
  "mode": "maintainer" | "user",
  "root": "<absolute path scanned>",
  "agents": [ { "name", "file", "description", "model", "skills": [names declared in frontmatter], "loadedSkills": [names actually loaded via Skill tool in body], "forbiddenFields": [any of hooks/mcpServers/permissionMode present], "descriptionLength": <int> } ],
  "skills": [ { "name", "dir", "hasReferences": bool } ],
  "commands": [ { "name", "file" } ],
  "loadEdges": [ { "agent", "skill", "declaredOnly": bool, "loadedOnly": bool } ],
  "findings": [ { "severity": "error"|"warning", "code", "message", "file" } ]
}
```
`findings` carries what the brief says the scanner must catch beyond
`claude plugin validate`: name collisions, `:` in names, forbidden
frontmatter fields, `description`+`when_to_use` over 1536 chars, and
declared-vs-loaded skill mismatches [brief.md:70-76]. Exact field types,
required-vs-optional, and schema versioning strategy are `architect`'s to
finalize (FR-3).

### 4. Runtime/portability bar (resolved by user decision — supersedes the PM proposal below)

[observed] This repo currently has **no `package.json` and no build
toolchain of any kind** — everything under `plugins/agent-team/` is Bash,
Markdown, and JSON. [observed] `CLAUDE.md` requires hook scripts to be
POSIX-ish bash runnable on Windows Git Bash, macOS, and Linux, with no `jq`
dependency.

**Decided bar, split by component** (ADR-0002, user override — the original
PM proposal below this list left the TUI runtime as `architect`'s call among
Node/Python/Go/Rust; the user decided it directly):
- **Scanner**: unchanged — POSIX-ish bash, no `jq`, runs under Windows Git
  Bash / macOS / Linux, because it is also the CI validator and CI already
  runs the existing bash scripts under this bar. No second runtime for the
  scanner.
- **TUI**: **Rust + ratatui**, distributed as **prebuilt binaries for five
  target triples, committed to this repository** (ADR-0002). A user needs no
  runtime and no toolchain to run the TUI — the cost moves instead to this
  repo: repo weight from committed binaries, a mandatory release pipeline
  that must exist before any binary is committed, and a binary that can lag
  its source between releases. All three costs are named in
  `docs/architecture.md` and in the release-pipeline story (E0-1) rather than
  absorbed silently.
- Consequence for FR/story ordering: because prebuilt binaries require a
  release pipeline that does not exist yet (`.github/workflows/` is
  currently empty [observed]), **that pipeline is now a prerequisite ahead of
  the scanner**, not merely parallel to it — nothing ships, including the
  scanner's own CI validation of the TUI contract, until the pipeline exists.
  See the epics/stories table: E0 precedes E1.

The original proposal, left here for the record of what was superseded:
the TUI "may introduce one runtime not currently in this repo... architect's
call which" and "must still run... without a compiled/platform-specific
artifact per OS unless architect explicitly accepts that build cost." The
user's decision explicitly accepts that build cost in exchange for a
zero-dependency install.

## Functional requirements

**FR-1 — Repository paths scanned**
- Description: the scanner reads exactly
  `plugins/agent-team/agents/*.md` [observed, 11 files],
  `plugins/agent-team/skills/*/SKILL.md` [observed, 18 skill directories],
  `plugins/agent-team/commands/*.md` [observed, 4 files] in maintainer mode,
  and the equivalent paths under the installed plugin location in user mode.
- Acceptance criteria:
  - [ ] Given the Agent-Team repo root, when the scanner runs, then its JSON
    `agents` array has exactly 11 entries, `skills` has exactly 18, `commands`
    has exactly 4.
  - [ ] Edge: empty — an `agents/` directory with zero `.md` files produces
    an empty `agents` array, not an error.
  - [ ] Edge: one — a single agent file produces a one-element array with
    all fields populated.
  - [ ] Edge: many — no upper bound enforced; scanner does not truncate.
  - [ ] Edge: far too many — 500 synthetic agent files scan without crashing
    or exceeding a 30s wall-clock budget.
  - [ ] Failure: a malformed frontmatter block (unparsable YAML) produces a
    `findings` entry with `severity: error` naming the file, not a scanner
    crash; scanner exits non-zero for CI purposes but still emits JSON.

**FR-2 — Mode detection with explicit override**
- Description: the tool determines maintainer vs. user mode per the rule in
  "Resolutions of the brief's open items" §2, and always accepts an explicit
  override.
- Acceptance criteria:
  - [ ] Given the Agent-Team repo root, when the TUI starts with no flag,
    then it reports maintainer mode in its header.
  - [ ] Given a project root with agent-team installed as a plugin and no
    `agent-team/.claude-plugin/plugin.json` of its own, when the TUI starts
    with no flag, then it reports user mode.
  - [ ] Given a root matching neither signal, when the TUI starts with no
    flag, then it reports "mode undetermined" and blocks all read/edit
    actions until `--mode` is supplied.
  - [ ] Edge: a root matching both signals (e.g. nested checkout) — the TUI
    reports the ambiguity explicitly rather than picking silently, and
    requires `--mode` to proceed.
  - [ ] Failure: `--mode invalid-value` — the TUI rejects the flag with a
    usage message and exits non-zero; no scan is attempted.

**FR-3 — Scanner JSON schema and CI validator**
- Description: the scanner emits JSON matching the schema in "Resolutions"
  §3, and can run standalone (`scanner <path> [--mode]`) exiting non-zero on
  any `findings` entry with `severity: error`.
- Acceptance criteria:
  - [ ] Given the current repo, when the scanner runs standalone, then its
    exit code is 0 and `findings` contains zero `severity: error` entries
    (repo is currently valid per `claude plugin validate` [assumed — not
    re-verified in this PRD]).
  - [ ] Given an agent file with `hooks:` in frontmatter, when the scanner
    runs, then `findings` contains one `error` entry naming that file and
    the forbidden field.
  - [ ] Given two agents sharing the same `name`, when the scanner runs,
    then `findings` contains one `error` entry naming both files.
  - [ ] Edge: empty — no agents/skills/commands directories at all — scanner
    emits valid JSON with empty arrays and exits 0.
  - [ ] Failure: target path does not exist — scanner exits non-zero with a
    message identifying the missing path; emits no JSON to stdout.

**FR-4 — TUI tree view (read-only)**
- Description: renders agents, skills, commands as a navigable tree with
  load-edges, sourced only from the scanner's JSON (no independent parsing).
- Acceptance criteria:
  - [ ] Given the scanner's JSON for this repo, when the TUI loads it, then
    all 11 agents, 18 skills, 4 commands appear, and each load edge from the
    JSON's `loadEdges` is rendered as a visible connection.
  - [ ] Given a `loadEdges` entry with `declaredOnly: true` or
    `loadedOnly: true` (a mismatch), when displayed, then it is visually
    distinguished from a matched edge.
  - [ ] Edge: empty — zero skills — the skill pane shows an explicit empty
    state, not a blank screen.
  - [ ] Edge: one agent, zero skills declared — renders with no outgoing
    edges, no crash.
  - [ ] Failure: JSON file missing or unparsable — TUI shows an error
    screen naming the problem and does not fall back to a stale or empty
    tree silently.

**FR-5 — Frontmatter editor**
- Description: lets a user open an agent or skill file's frontmatter fields
  in a form and edit them.
- Revision: the second acceptance criterion below originally described
  warning the user at the moment they typed `hooks`, `mcpServers`, or
  `permissionMode` as a **new** key. `architect` established that the editor
  never adds keys — it edits values of `editableFields` and deletes keys in
  `removableFields` only — so that add-a-forbidden-field path does not exist
  to warn against (ADR-0006). `architect` ruled the PRD is the document that
  must change, not the design. The criterion below now describes what
  actually protects the user, which is a hard block rather than a dismissible
  warning.
- Acceptance criteria:
  - [ ] Given an agent's frontmatter loaded in the editor, when a field is
    changed and the user requests save, then the in-memory validation from
    FR-6 runs before any disk write.
  - [ ] Given a file whose frontmatter **already contains**
    `hooks`, `mcpServers`, or `permissionMode`, when the scanner scans it,
    then it produces a `FORBIDDEN_FIELD` finding with `severity: error`,
    visible both on the entity in the tree and in the findings panel — and
    because it is an error, not a warning, **every save attempt on that file
    is blocked** until the field is removed; the user cannot dismiss it and
    proceed.
  - [ ] Given a file carrying a `FORBIDDEN_FIELD` finding, when the editor is
    open on it, then the only remedy offered is the single removal
    affordance in the next criterion — there is no path in the UI to save
    the file with the forbidden field still present.
  - [ ] Given the scanner's `removableFields` for an entity, when the editor
    renders it, then it offers deletion of a key **only** if its name is
    `hooks`, `mcpServers`, or `permissionMode` **and** the scanner supplied
    an exact line span for it in `removableFields`; no other key is
    removable, and no key can be added, from the editor.
  - [ ] Edge: empty — clearing a required field (`name`, `description`) is
    rejected with a specific message, not a silent no-op.
  - [ ] Edge: one — editing a single scalar field (e.g. `model`) round-trips
    correctly on save.
  - [ ] Edge: many — editing multiple fields in one session saves all of
    them atomically (all-or-nothing).
  - [ ] Failure: validation fails — the file on disk is byte-identical to
    before the edit attempt, and the TUI states which check failed.

**FR-6 — Write-back validation**
- Description: implements the exact checks in brief.md constraint 6 —
  `name` uniqueness tree-wide, no `:` in `name`, no
  `hooks`/`mcpServers`/`permissionMode` in agent frontmatter, combined
  `description`+`when_to_use` under 1536 chars — entirely in memory before
  any write.
- Acceptance criteria:
  - [ ] Given an edit that would duplicate an existing `name` elsewhere in
    the tree, when save is attempted, then the write is rejected and no
    file changes.
  - [ ] Given an edit that would push `description`+`when_to_use` to 1537
    characters, when save is attempted, then the write is rejected with the
    character count shown.
  - [ ] Given an edit that passes all in-memory checks, when save is
    attempted, then the file is written and the TUI states plainly that
    `claude plugin validate` has not been run and remains the user's
    responsibility to run separately [brief.md constraint 6, known
    limitation].
  - [ ] Edge: a `name` of exactly 1536-char combined length — boundary is
    inclusive, passes.
  - [ ] Edge: a `name` at 1537 — boundary is exclusive, fails.
  - [ ] Failure: two validation failures at once (duplicate name AND forbidden
    field) — both are reported together, not just the first one found.

**FR-7 — `.agent-team.json` edit (user mode only)**
- Description: **resolved by the user — closes the brief's open item.** In
  user mode, the TUI lets a user edit the consuming project's
  `.agent-team.json` as **raw JSON text**, not through field-aware forms.
  There is no schema-driven editor for scope/gates; the TUI reads the file's
  bytes into a text buffer, lets the user edit that buffer, and on save
  attempts to parse the result as JSON before writing.
- Acceptance criteria:
  - [ ] Given user mode with an existing `.agent-team.json`, when opened in
    the editor, then its raw text contents are shown in an editable text
    buffer, unmodified and unreformatted.
  - [ ] Given edited text that parses as valid JSON, when save is attempted,
    then the file on disk is overwritten with exactly that text.
  - [ ] Given edited text that does **not** parse as valid JSON, when save is
    attempted, then the write is rejected, the file on disk is left
    byte-identical to before the attempt, and the TUI shows the parse error
    (message and, where the parser provides one, line/column) rather than a
    generic failure.
  - [ ] Given a maintainer-mode session, when the user attempts to open
    `.agent-team.json` editing, then the action is unavailable/disabled,
    consistent with brief.md's explicit exclusion of creating this file from
    maintainer mode.
  - [ ] Edge: `.agent-team.json` does not exist in user mode — the TUI does
    not fabricate one; it states the file is absent and (per out-of-scope)
    does not offer to create it as part of v1.
  - [ ] Edge: an already-malformed `.agent-team.json` is opened before any
    edit — the TUI shows the existing parse error immediately on open, not
    only on save, and still permits editing the raw text to fix it.
  - [ ] Failure: a save that would parse but produces an empty file (zero
    bytes) — treated as invalid JSON like any other parse failure; rejected,
    nothing written.

**FR-9 — TUI invocation via Claude Code command**
- Description: resolved by the user. The plugin ships a `commands/` entry
  that launches the TUI wrapper by expanding `${CLAUDE_PLUGIN_ROOT}`, so a
  user invokes the TUI from within Claude Code rather than typing a
  filesystem path to the binary or wrapper script by hand.
- Acceptance criteria:
  - [ ] Given the plugin installed and the command invoked, when it runs,
    then it launches `tui/agent-team-tui` resolved through
    `${CLAUDE_PLUGIN_ROOT}`, in the correct mode for where it was invoked.
  - [ ] Given the wrapper exits 3 (unshipped target triple or missing
    binary), when invoked via the command, then the command surfaces that
    exact message to the user rather than swallowing it or showing a generic
    launch failure.
  - [ ] Edge: `${CLAUDE_PLUGIN_ROOT}` does not resolve (unset or the plugin
    is not actually installed at the expected location) — the command
    reports the resolution failure explicitly; it does not fall back to a
    relative path that could launch a different installed copy.
  - [ ] Failure: the resolved wrapper path exists but is not executable
    (permissions) — the command reports that specific failure, not a bare
    "command not found".

**FR-8 — v1 demo / definition of done**
- Description: the six-step demo script in "Resolutions" §1 passes in full
  against the real Agent-Team repo.
- Acceptance criteria: the six numbered steps in §1, each independently
  checkable by running the TUI and the scanner. This FR exists specifically
  so "done" is not decided informally at the end of the project.

## Non-functional requirements

| Type | Target | How measured |
|---|---|---|
| Portability (scanner) | Runs on Windows Git Bash, macOS, Linux; no `jq` | CI matrix runs the scanner on all three OSes |
| Portability (TUI) | Runs on Windows, macOS, and Linux via prebuilt binaries for five target triples, committed to the repo; a user needs no runtime or toolchain (ADR-0002) | Manual run on each OS during FR-8 demo; release-pipeline CI (E0-1) builds and tests all five triples on every change; `check-binaries.sh` blocks CI on a real staleness mismatch (exit 1) once `bin/` exists, but does not block a PR before the first release (exit 2, reported distinctly, never treated as a pass); the PR workflow additionally rebuilds natively and compares embedded `srcHash` against `bin/MANIFEST` for four of the five triples (all but `aarch64-unknown-linux-musl`, which has no PR-time native runner) |
| Performance (scanner) | Completes on the current 11/18/4-file tree in under 2s; under 30s at 500 synthetic agent files (FR-1 edge) | Timed CI run |
| Safety (write-back) | Zero disk writes on any failed validation | FR-6 test suite: assert file mtime/hash unchanged after rejected save |

## Data

- **Source of truth**: the Markdown files under `plugins/agent-team/agents`,
  `/skills`, `/commands` (maintainer mode) or their installed-copy
  equivalents (user mode), plus a consuming project's `.agent-team.json`
  (user mode only). The scanner's JSON is a derived, disposable artifact —
  never the source of truth, regenerated on each run.
- **Retention**: scanner JSON is not persisted between runs by requirement;
  whether the TUI caches it to disk between sessions is an implementation
  choice for `architect`, not a data-retention requirement here.
- **Migration**: none — v1 introduces no persistent schema of its own beyond
  the existing Markdown/JSON files it reads and writes in place.

## Epics and stories

| Epic | Story | Related FR | Priority |
|---|---|---|---|
| E0: Release pipeline | E0-1 Release CI builds/tests five target triples and gates on binary staleness | NFR (portability, TUI); ADR-0002 | high |
| E1: Scanner | E1-1 Scanner parses agents/skills/commands into schema JSON | FR-1, FR-3 | high |
| E1: Scanner | E1-2 Scanner findings: forbidden fields, name collisions, `:` in name, length cap | FR-3, FR-6 | high |
| E1: Scanner | E1-3 Scanner runs standalone in CI with correct exit codes | FR-1, FR-3 | high |
| E2: Mode detection | E2-1 Detect maintainer vs. user mode at run root | FR-2 | high |
| E2: Mode detection | E2-2 Explicit `--mode` override and ambiguity handling | FR-2 | high |
| E3: TUI read | E3-1 TUI renders agent/skill/command tree from scanner JSON | FR-4 | high |
| E3: TUI read | E3-2 TUI renders load-edges, flags declared/loaded mismatches | FR-4 | medium |
| E4: TUI edit | E4-1 Frontmatter editor form for agents/skills | FR-5 | medium |
| E4: TUI edit | E4-2 In-memory write-back validation before disk write | FR-6 | high |
| E4: TUI edit | E4-3 `.agent-team.json` raw-JSON edit in user mode | FR-7 | medium |
| E5: Acceptance | E5-1 v1 demo script passes end to end | FR-8 | high |
| E6: Invocation | E6-1 TUI invocation via a `commands/` entry using `${CLAUDE_PLUGIN_ROOT}` | FR-9 | high |

Dependency order: **E0 → E1 → E2 → E3 → E4 → E5.** E0 now precedes
everything else — prebuilt binaries need a release pipeline that does not
exist yet, and ADR-0002 states nothing ships until it does; this reorders the
original E1-first sequence. Within E1, E1-1 before E1-2/E1-3. Within E4,
E4-2 before E4-1 (validation must exist before the editor can call it) and
both before E4-3. E6-1 depends only on E0 (a working wrapper/binary to
launch) and can proceed in parallel with E1–E5 once E0 lands; it is not
required for the E5-1 demo script, which invokes the TUI directly.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Rust + committed binaries adds a toolchain and a release pipeline this repo has never had | Build/CI complexity grows; repo weight grows monotonically with each binary-carrying commit | Named explicitly in `docs/architecture.md` and costed in ADR-0002; E0-1 builds the pipeline before any binary is committed; scanner still ships and is CI-validated independently in bash |
| Binaries are refreshed only on a `plugin.json` version bump, not per PR | A TUI bug fix lands in source but does not reach an installed user until the next version bump — a user can run a stale binary for an arbitrary length of time even though the fix already exists | **Stated consequence, not a resolved decision** — `architect` flagged this as an open product question; the user has not ruled on whether refresh cadence should instead track something other than version bumps (see Open questions) |
| Mode-detection false positive/negative (nested checkout, unusual install layout) | Wrong root scanned or edited, wrong file written | FR-2 requires visible mode display + mandatory override on ambiguity, never a silent guess |
| In-memory validation diverges from `claude plugin validate`'s real rules over time | A write that "passes" the TUI still fails full validate | FR-6 explicitly states this as a known, permanent limitation, not a bug to eventually fix; full validate stays a required separate step |
| Declared-vs-loaded skill mismatch detection (HARNESS-NOTES.md §2) requires parsing agent body text, not just frontmatter — harder than the rest of the scanner | Scanner findings for this rule may be unreliable at v1 | Architect scopes this as best-effort text search in E1-2; FR-3's acceptance criteria do not require 100% precision on this one check, only frontmatter-derived findings |

## Open questions

- Whether the TUI caches scanner JSON to disk between sessions — deferred to
  `architect` (Data section above).
- **Resolved**: exact mode-detection mechanism — `architect` designed it as
  self-location plus two `test -e` probes (ADR-0003).
- **Resolved**: TUI runtime choice — the user decided Rust + ratatui with
  prebuilt binaries committed to the repo (ADR-0002), superseding the
  original "architect's call among Node/Python/Go/Rust" proposal.
- **Resolved**: `.agent-team.json` editing is raw JSON text with parse errors
  reported on save (and on open, if already malformed) — see FR-7.
- **Open, unresolved by the user**: tying binary refresh to `plugin.json`
  version bumps means a TUI-only fix reaches installed users only at the next
  release, not on their next pull of this repo. `architect` flagged this as a
  product question, not an implementation detail — whether that lag is
  acceptable, or whether refresh should track something else (e.g. a
  TUI-specific version marker independent of the plugin's own version), is
  for the user to rule on. Recorded here as a stated consequence of ADR-0002,
  not silently accepted.
- Monitoring surface — explicitly deferred to v2, not this PRD's concern.
</content>
