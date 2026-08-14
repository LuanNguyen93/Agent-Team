# ADR-0004: The scanner JSON is a flat, fully-populated document versioned `MAJOR.MINOR`, with additive-only minors

- **Status**: accepted
- **Date**: 2026-08-13
- **Deciders**: `architect`, resolving brief.md Open Question 3 / PRD FR-3

## Context

The JSON is the contract between three consumers with different lifetimes: the
bash scanner that writes it, the Rust TUI that reads it, and CI which reads only
the exit code and `findings`. The PRD fixed the field *names*; types,
optionality and the versioning rule were left here. This document will outlive
v1, and the expensive mistake is optional fields — every optional field becomes
a conditional in the TUI and a place where CI and the TUI can come to believe
different things.

Two observations shape the types:

- [observed] Command files (`commands/*.md`) have **no `name` in frontmatter** —
  only `description` and `argument-hint`. Their identity is the filename.
- [observed] Agents carry `name`, `description`, `model`, `color`, `skills`;
  skills carry `name`, `description`, `when_to_use`. The three shapes are not
  interchangeable and are not worth unifying.

## Decision

### Versioning rule

`schemaVersion` is a **string** `"MAJOR.MINOR"`, starting at `"1.0"`.

- **MINOR** increments when, and only when, a field is **added** and every
  existing field keeps its name, type and meaning. An addition must never
  require a consumer update.
- **MAJOR** increments for anything else: removing a field, changing a type,
  changing what a field means, or changing an existing enum member.
- **Consumers must ignore unknown fields.** A consumer that fails on a field it
  does not recognise turns every additive change into a breaking one.
- **Consumers must refuse an unknown MAJOR.** The TUI parses the integer before
  the dot; if it is not `1` it shows an error screen naming both versions and
  reads nothing further. CI does the same.
- Enum members may be **added** in a MINOR only where the consumer already has a
  default branch. `findings[].code` is explicitly an open set — new codes may
  appear in any MINOR and consumers must render an unknown code as-is.

### Types

Every field listed is **required and always present**. An absent value is the
empty string, `0`, `false`, or `[]` — never `null`, never omitted. No consumer
ever writes `if (x !== undefined)`.

```
root object
  schemaVersion     string   "MAJOR.MINOR"
  generatedAt       string   ISO 8601 UTC, second precision: "2026-08-13T10:04:11Z"
  mode              string   "maintainer" | "user"
  root              string   absolute path of the scanned plugin root, forward slashes
  projectRoot       string   absolute path; "" in maintainer mode
  agents            agent[]
  skills            skill[]
  commands          command[]
  loadEdges         edge[]
  findings          finding[]

agent
  name              string   frontmatter `name`; "" if absent or unparsable
  file              string   path relative to `root`, forward slashes
  description       string   "" if absent
  descriptionLength integer  characters (not bytes) in `description`
  model             string   "" if absent
  color             string   "" if absent
  skills            string[] names declared in frontmatter `skills:`, source order
  loadedSkills      string[] names found loaded via the Skill tool in the body (best effort)
  forbiddenFields   string[] subset of ["hooks","mcpServers","permissionMode"] present
  parsed            boolean  false when the frontmatter block is missing or unparsable
  editableFields    string[] frontmatter keys the TUI may edit in place (ADR-0006)
  removableFields   string[] forbidden keys whose exact line span the scanner located,
                             and which the TUI may delete (ADR-0006); always a subset
                             of forbiddenFields; empty for skills

skill
  name              string   frontmatter `name`; falls back to the directory name if absent
  dir               string   path relative to `root`
  description       string
  descriptionLength integer
  whenToUse         string   frontmatter `when_to_use`; "" if absent
  whenToUseLength   integer
  hasManifest       boolean  false when the directory contains no SKILL.md
  hasReferences     boolean  a `references/` subdirectory exists
  parsed            boolean
  editableFields    string[]
  removableFields   string[] always empty for skills; present so both shapes
                             answer the same question

command
  name              string   file basename without `.md` — commands carry no frontmatter `name`
  file              string   path relative to `root`
  description       string
  argumentHint      string   frontmatter `argument-hint`; "" if absent
  parsed            boolean

edge
  agent             string   agent `name`
  skill             string   skill name as the agent writes it
  declaredOnly      boolean  in frontmatter `skills:`, not found loaded in the body
  loadedOnly        boolean  found loaded in the body, not in frontmatter `skills:`
                             (both false = a matched edge; both true is impossible)

finding
  severity          string   "error" | "warning"
  code              string   SCREAMING_SNAKE, stable once published; open set
  message           string   one line, human-readable, quoting the offending value
  file              string   path relative to `root`; "" for findings not tied to one file
  field             string   the frontmatter key this finding is about, when it is about
                             one — "name", "description", "hooks", … ; "" otherwise.
                             Lets the editor focus the offending field instead of making
                             the TUI infer it from `code`, which would put a second copy
                             of the rules in the TUI
  relatedFiles      string[] other files involved, e.g. the second half of a collision
```

Arrays are **sorted**: agents and commands by `file`, skills by `dir`, edges by
`agent` then `skill`, findings by `severity` then `code` then `file`. Sorting is
part of the contract — it makes the output diffable, and it makes PRD FR-8
step 6 ("byte-identical in content") checkable with `diff`.

### Finding codes at v1.0

| Code | Severity | Rule |
|---|---|---|
| `FRONTMATTER_UNPARSABLE` | error | No `---` block, an unterminated block, or a line that is neither `key:` nor a list item |
| `NAME_MISSING` | error | Agent or skill with no `name` |
| `NAME_COLLISION` | error | Two entities share a `name` anywhere in the tree |
| `NAME_CONTAINS_COLON` | error | `name` contains `:` |
| `FORBIDDEN_FIELD` | error | `hooks`, `mcpServers`, or `permissionMode` in agent frontmatter |
| `SKILL_MISSING_MANIFEST` | error | A `skills/<x>/` directory with no `SKILL.md` |
| `DESCRIPTION_TOO_LONG` | error | `descriptionLength + whenToUseLength` exceeds 1536 |
| `SKILL_DECLARED_NOT_LOADED` | warning | A `declaredOnly` edge |
| `SKILL_LOADED_NOT_DECLARED` | warning | A `loadedOnly` edge |

The two `SKILL_*` edge findings are `warning`, not `error`, because they rest on
text search over an agent's prose body — the PRD's own risk table accepts that
this check is best-effort at v1. A warning never fails CI and never blocks a
write. Everything else is an `error`: exit 1 from the scanner, blocked write in
the TUI.

The 1536 boundary is **inclusive**: exactly 1536 passes, 1537 fails. This was
briefly contradictory — `CLAUDE.md` said "under 1,536" — and was resolved in
favour of inclusive, because [observed] `docs/HARNESS-NOTES.md` §6 describes the
listing as *truncating* at 1,536 characters, so 1,536 characters still arrive
intact. `CLAUDE.md`'s wording has since been corrected; the PRD stands as
written.

## Options considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| **Flat, all-required, `MAJOR.MINOR` (chosen)** | No optionality branches in consumers; additive evolution is free; diffable | Verbose; empty strings everywhere | — |
| Optional fields, omitted when absent | Smaller output | Every consumer grows `undefined` checks, and a scanner bug becomes indistinguishable from a genuinely absent value | Silence and absence must not look alike |
| Integer `schemaVersion` (`1`, `2`) | Simplest possible | No way to signal an additive change, so every addition either looks breaking or is invisible | Loses the additive path, which is the common case |
| Full semver `1.0.0` | Familiar | The patch digit would never carry meaning — this document has no bug-fix axis separate from its shape | A digit that never changes is noise |
| One polymorphic `entities[]` with a `kind` field | One array, one loop | [observed] agents, skills and commands differ in identity rule and in fields; the union would be mostly-empty rows | They are not the same shape |
| Ship a JSON Schema and validate at runtime | Machine-checkable | Needs a validator; ADR-0002 forbids dependencies, and a hand-written validator is exactly the drift it was meant to prevent | Golden fixtures under `tui/tests/fixtures/` are the executable contract instead |

## Consequences

### Positive
- The TUI's read path is total: every field is present every time, so there is
  no defaulting logic and therefore no way for the TUI's defaults to disagree
  with the scanner's.
- Sorted output makes FR-8 step 6 a `diff` and makes CI failures readable.
- CI needs only the major version, `findings`, and the exit code — it is
  insulated from everything else the document grows.

### Negative
- The document restates a lot of empty values and is larger than it needs to be.
  At 33 entities that is irrelevant; it would be a real cost only at a scale
  this tool will not reach.
- `descriptionLength` is **denormalised** — derivable from `description`. It is
  kept because the 1536 rule counts characters and counting UTF-8 characters
  correctly in bash is the fiddly part; doing it once in the scanner stops the
  TUI counting differently. Source of truth is `description`; the scanner is the
  only writer of the length, and the TUI must never recompute it or trust a
  count of its own.
- "Consumers ignore unknown fields" is a rule with no enforcement. A reviewer
  has to catch a consumer that breaks it.

### What this makes harder later
A v2 monitoring surface (brief.md's deferred question) will want per-session,
time-varying data, which does not belong in a document whose entire premise is a
single point-in-time scan. That is a **new** document with its own version line,
not a MAJOR bump of this one. Resist widening this schema into a general-purpose
state file.
