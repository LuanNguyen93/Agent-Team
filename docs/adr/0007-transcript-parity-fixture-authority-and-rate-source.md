# ADR-0007: One committed parity fixture under `tui/tests/fixtures/transcripts/`, `measure-tokens.js` is authoritative, and both implementations read one `rates.json`

- **Status**: accepted
- **Date**: 2026-08-14
- **Deciders**: `architect`, resolving the single open item carried forward by
  `docs/prd-analytics-tui.md` ("Open item carried forward", owner `architect`,
  blocking design on FR-1/FR-6)
- **Amended 2026-08-14**, during implementation of `docs/plan-e7.md` steps 1-5,
  after `implementer` found that the shape this ADR illustrated for
  `expected.json` is not the shape `measure-tokens.js --json` emits, and stopped
  rather than inventing past it. Three things changed and are marked in place:
  the `expected.json` shape is now a *normalised capture* with the three
  transforms enumerated; `malformedLines` is **removed from the parity
  contract** and replaced by a fixture change plus two named tests; and the
  tolerance table is restated against the real field list. The three decisions
  (a), (b), (c) themselves are unchanged.
- **Supersedes / amends**: nothing. Sits under ADR-0002 (Rust + ratatui) and
  beside ADR-0004 (schema style) and ADR-0005 (no cache), whose house rules —
  fully-populated documents, no persisted derived state — this follows.

## Context

[observed] `docs/brief-analytics-tui.md` decision 2, signed off by the user,
accepts a deliberate duplication: the Rust TUI parses transcript JSONL natively
and `plugins/agent-team/scripts/measure-tokens.js` is not retired. Two
implementations of the same cost arithmetic will exist.

[observed] The PRD's FR-6 requires a shared fixture tested from both
implementations, and names three things it does not decide: where the fixture
lives, which implementation wins a disagreement, and whether the rate table is
duplicated or generated. Those three are what this ADR decides, and nothing
else.

What the duplicated arithmetic actually is [observed,
`plugins/agent-team/scripts/measure-tokens.js`]:

- `RATES` — three tiers (`opus` 15/75, `sonnet` 3/15, `haiku` 1/5, list price
  per million tokens).
- Two multipliers applied inside `costOf`, not stored in `RATES`: cache write
  bills at **1.25×** input and cache read at **0.1×** input. The file's own
  comment states these are derived "rather than typed twice and left to drift".
  Any answer here that types `1.25` and `0.1` into a Rust file has reintroduced
  exactly the drift that comment was written to prevent, one language over.
- `tierOf` — substring match on the lowercased model string, `haiku` then
  `sonnet`, everything else falling through to `opus` so an unrecognised model
  bills at the most expensive tier rather than disappearing.
- `costOf`, `contextOf`, `isSubagent` (path *segment* match on `subagents`),
  `sessionIdFor` (first path segment, `.jsonl` stripped), `projectDirFor`
  (`~/.claude/projects/` + cwd with every non-alphanumeric byte replaced by a
  dash), `walk` (recursive, `.jsonl` only), and the row aggregation in
  `addToRow` / `sortedRows` (cost desc, then calls desc).

One existing constraint shapes the fixture decision, and it is a direct
objection to checking one in. [observed]
`plugins/agent-team/scripts/tests/measure-tokens.test.sh:6-9` builds its
fixtures in a tempdir and says why: *"They are generated here rather than
checked in because the assertions are about arithmetic on usage numbers, and a
checked-in fixture would drift from the pricing table without anything
noticing."* That objection is correct about **hand-typed expected numbers**. It
is not an objection to checked-in *input* data — and FR-6 cannot be satisfied
by a tempdir, because two test suites in two languages have to read the same
bytes.

[observed] `plugins/agent-team/tui/rust/Cargo.toml` declares no dependencies and
`src/main.rs` is 36 lines implementing only `--build-info`. [observed]
`plugins/agent-team/tui/tests/fixtures/` is already the named home for
"synthetic plugin trees + expected JSON (the contract)" in
`docs/architecture.md`, "Where the code goes".

## Decision

### (a) The fixture: input committed, expected values generated, both under `tui/tests/fixtures/transcripts/`

```
plugins/agent-team/tui/tests/fixtures/transcripts/
├── README.md                  # what each case exercises, and how to regenerate
├── project/                   # the fixture *input* — a synthetic project dir
│   ├── aaaaaaaa-1111.jsonl            # main transcript
│   ├── aaaaaaaa-1111/subagents/
│   │   ├── implementer-01.jsonl       # attributionAgent present
│   │   └── orphan-02.jsonl            # no attributionAgent → (unattributed subagent)
│   ├── bbbbbbbb-2222.jsonl            # main-only session, zero subagent calls
│   └── cccccccc-3333.jsonl            # unrecognised model + one malformed line
└── expected.json              # generated, committed, never hand-edited
```

**Why this location.** It is inside `tui/`, so it adds no top-level directory
[observed, `CLAUDE.md` layout rules]; `tui/tests/fixtures/` already means
"fixture plus expected output, treated as the contract" in this repo, so the
convention is reused rather than a second one invented; and it is reachable by a
short relative path from both consumers — `../../tui/tests/fixtures/transcripts`
from `scripts/tests/`, `../tests/fixtures/transcripts` from `rust/`.

**Shape of the input.** Plain JSONL, byte-identical to what Claude Code writes,
committed with **LF line endings pinned by `.gitattributes`** — a CRLF checkout
on Windows changes the bytes both parsers see and would produce a parity failure
that has nothing to do with cost logic. The input contains no personal data and
no secrets: model strings, token counts and synthetic agent names only.

**Shape of `expected.json`.** It is the output of
`node measure-tokens.js --project <fixture>/project --json`, **plus exactly
three declared normalisations applied by the regeneration script**
`plugins/agent-team/tui/tests/regen-transcript-expected.sh`:

| Normalisation | Why it is not a "fix" to be reverted |
|---|---|
| **`project` is deleted** | [observed] `--json` emits it as an absolute path (`D:/Agent-Team/.../project` on the machine that generated the committed file). A machine-specific value in a committed generated file means every regeneration on a different checkout produces a different byte, and it carries zero parity information — both implementations are pointed at the fixture by their test harness, not by this field |
| **`fixtureVersion: "1.0"` is added** | The fixture's own contract version, bumped when a case is added or the input changes shape. Nothing in `measure-tokens.js` knows this exists |
| **`generator: "measure-tokens.js --json"` is added** | Provenance for ADR-0007(b): the file names its own authority, so a reader cannot mistake it for a Rust capture |

**`expected.json` is therefore a normalised capture, not a raw one.** That
sentence is load-bearing: the earlier draft of this ADR illustrated a shape
`measure-tokens.js` does not emit, and the implementer correctly stopped rather
than inventing past it. The three transforms above are the *whole* list — the
script performs no others, adds no computed values, and **must never add a field
that neither implementation produces**, because such a field looks like evidence
of parity and is not. The regeneration script carries this table as a comment,
and a test asserts that re-running the script leaves `expected.json` byte-identical.

The parity comparison **ignores `fixtureVersion` and `generator`** — they are
provenance, not data either implementation computes.

Every other field is `measure-tokens.js`'s output verbatim [observed, the
committed file]: `sessions[]` (`id`, `main`/`sub` buckets of `calls`, `cost`,
`output`, `cacheRead`, `cacheWrite`, `avgContext`, `maxContext`, plus `byAgent`,
`totalCost`, `subShare`), `byAgentModel[]`, `cumulative`, and `totals.cost`.

It is **generated, never authored**. `bash
plugins/agent-team/tui/tests/regen-transcript-expected.sh` writes it; nobody
types a number into it, so no number can be typed wrong, and a rate change
updates it by regeneration. That is what answers the objection recorded at
`plugins/agent-team/scripts/tests/measure-tokens.test.sh:6-9`.

**Both suites assert against `expected.json`, and this is what makes drift
fail:**

| Change made | What fails |
|---|---|
| JS cost logic changes, `expected.json` not regenerated | the JS test — computed ≠ committed expected |
| JS cost logic changes **and** `expected.json` regenerated, Rust not updated | the Rust test — Rust ≠ the new expected |
| Rust cost logic changes alone | the Rust test |
| `rates.json` changes | both, until `expected.json` is regenerated; then Rust and JS still both pass only if they read the same file (they do — see (c)) |

There is no combination of one-sided edits that leaves CI green. That is the
whole requirement of FR-6.

**Cases the fixture must cover** — FR-6's edge criterion, made concrete: zero
subagent calls (session `bbbb`), at least one attributed subagent call, one
subagent call with no `attributionAgent`, one call per tier (opus, sonnet,
haiku), one unrecognised model string billing at opus, one malformed line, one
blank line, one usage record with a missing `model` key (→ `(unknown model)`),
and one record with no `usage` at all (skipped, not zero-costed).

### The malformed line: what is parity evidence and what is not

`measure-tokens.js` skips a malformed line and counts nothing [observed,
`collect()`'s `catch (e) { continue; }`]. The Rust side must additionally
*count* them, because FR-1 requires the figure on screen. **A `malformedLines`
field in a JS-generated `expected.json` would therefore be fabricated by the
generator, and a fabricated field looks like evidence of parity while being
evidence of nothing.** It is removed from the contract. The behaviour splits in
two, and both halves get a real check:

**(i) Skip-and-continue is parity evidence, and the fixture must make it so.**
The distinction that matters is *skip the line* versus *abort the file*, and
that distinction is visible in the cost totals — but **only if a billable record
follows the malformed line in the same file**. [observed] it currently does not:
`fixtures/transcripts/project/cccccccc-3333.jsonl` is two lines, the malformed
one last, so a Rust parser that aborted the whole file on the first bad line
would produce numbers identical to one that skipped it, and the parity test
would pass. That is a hole in the fixture, not in the idea.

**Required fixture change**: append a third line to `cccccccc-3333.jsonl` — a
valid, billable usage record *after* the malformed line — and regenerate
`expected.json`. Abort-on-bad-line then changes `totals.cost` and fails the
parity test, which is the property FR-1's failure criterion actually needs.
This is a normative requirement of this ADR, not a suggestion.

**(ii) The count is Rust-only, and is verified by two tests that brace each
other.** Neither is a parity test, and neither is described as one:

| Check | Where | What it catches |
|---|---|---|
| `assert_eq!(report.malformed_lines, 1)` against the fixture | Rust unit test | the counter is wrong, or stops counting |
| the fixture contains exactly 1 line that fails `JSON.parse` | the existing bash suite, asserted over the fixture files directly | the fixture silently loses its malformed line, which would make the Rust assertion above pass vacuously |

The second is a test **on the fixture**, not new output from
`measure-tokens.js` — no CLI flag, no new field, no behaviour change — so it
stays inside the PRD's "not modifying its CLI/CI behaviour" line. The expected
count lives in the fixture `README.md`, which is where the fixture's own facts
are authored, and never in the generated file.

**Tolerance**, restated against the shape `--json` actually emits [observed,
the committed `expected.json`]. The earlier draft named `malformedLines`, which
does not exist, and omitted three fields that do:

| Field | Comparison | Why |
|---|---|---|
| `id`, `agent`, `model` | exact string | identity, not arithmetic |
| `calls`, `output`, `cacheRead`, `cacheWrite`, `maxContext` | **exact** | integers; a difference of one is a real disagreement |
| every `cost`, `totalCost`, `totals.cost`, `cumulative.cost` | absolute **1e-9 USD** | both sides are IEEE-754 f64 over the same multiplications, so this only absorbs summation order; a real pricing divergence is at least 1e-6 USD |
| `avgContext` | absolute **1e-6 tokens** | a mean of values of order 1e5, so f64 rounding is around 1e-10; 1e-6 is slack with three orders of magnitude to spare and still catches an off-by-one in the divisor |
| `subShare` | absolute **1e-12** | a ratio in [0,1]; nothing legitimate moves it further |
| `project`, `fixtureVersion`, `generator` | **not compared** | machine state and provenance, produced by neither parser |

Rust keeps a running sum and max for context rather than the JS's per-call
`Vec` (`docs/architecture-e7.md`), which is exactly the kind of
summation-order difference the cost and `avgContext` tolerances exist to
absorb.

**Row ordering.** `sortedRows` orders by cost desc then calls desc [observed],
and beyond that relies on JS insertion order — a tie-break Rust has no reason to
reproduce. Rather than change `measure-tokens.js`'s output (out of scope per the
PRD), **the fixture is constructed so no two rows tie on both cost and calls**,
and the parity assertion compares rows keyed by `(agent, model)` with the
ordering asserted only where the fixture makes it total. See "Open" below.

### (b) `measure-tokens.js` is authoritative

When the two disagree, **`measure-tokens.js` is right by definition and the Rust
parser is wrong**, until the user decides otherwise on a specific case.

It earns that not by being better code but by being the incumbent: it is
[observed] already shipped, already the source of `docs/measurements/*.json`,
and already the semantics the delegation-nudge hook's signal is discussed in.
Two implementations need a tie-break that is decidable without a meeting, and
"the one that was here first and has users" is decidable.

Three consequences that must be honoured, or the rule is decorative:

1. `expected.json` is generated by the JS, never by the Rust. A generator is an
   authority claim; only one tool gets to make it.
2. A JS **bug** is still a bug. Authoritative means the Rust conforms
   *pending a fix*, not that the JS is correct. The fix goes into the JS first,
   `expected.json` is regenerated, and the Rust follows — never the reverse
   order, because the reverse order is how the fixture silently becomes a
   record of the Rust's opinion.
3. The Rust parser therefore reproduces JS quirks deliberately, including the
   ones that look like defects: unknown models billing at opus, a missing
   `model` becoming the literal string `(unknown model)`, and sessions with zero
   billed calls being filtered out entirely. Each of these gets a comment in the
   Rust naming `measure-tokens.js` as the reason, so the next reader does not
   "fix" one of them.

### (c) One rate file, read by both — `tui/shared/rates.json`

```jsonc
// plugins/agent-team/tui/shared/rates.json
{
  "rateVersion": "1.0",
  "note": "List price per million tokens. Cache write and cache read are derived from input.",
  "cacheWriteMultiplier": 1.25,
  "cacheReadMultiplier": 0.1,
  "tiers": {
    "opus":   { "input": 15, "output": 75 },
    "sonnet": { "input": 3,  "output": 15 },
    "haiku":  { "input": 1,  "output": 5  }
  }
}
```

- **JS** reads it with `require(path.join(__dirname, '..', 'tui', 'shared', 'rates.json'))`
  — Node parses JSON via `require` natively, so this stays zero-dependency, and
  `RATES` becomes `rates.tiers` with the two multipliers read from the same
  object instead of being literals inside `costOf`. This is the one edit to
  `measure-tokens.js` this ADR authorises: **no CLI flag, no output format, no
  arithmetic changes** — the same numbers come out, sourced from a file instead
  of a literal, which is inside the PRD's "not retiring or modifying its CLI/CI
  behaviour" line rather than across it.
- **Rust** embeds it at compile time with
  `include_str!("../../shared/rates.json")` and parses it once with `serde_json`
  into a `Rates` struct. Embedded, not read at run time: a binary that needs a
  file beside it breaks the moment it is copied, and ADR-0002's whole point is
  that the shipped binary needs nothing on the user's machine.
- **The multipliers exist once, in this file.** Neither language contains the
  literals `1.25` or `0.1` in a costing path. That is the specific drift the
  question named, and it is closed by the data file rather than by a comment
  asking people to be careful.
- **A missing or malformed `rates.json` is a hard failure on both sides** —
  build failure in Rust (`include_str!` on a missing path does not compile;
  a malformed body fails the parse test), a thrown error in the JS. Never a
  silent fallback table, because a silent fallback is a wrong invoice.

**`tierOf` stays hand-written in both.** The keyword list and its order are three
lines of logic, not data, and pushing it into the file would mean shipping a
matcher spec that both languages must interpret identically — replacing a small
duplication with a small language. The fixture covers all four branches
(haiku, sonnet, opus, unrecognised), which is what makes the duplication safe to
have. Applying the skill's own rule: two occurrences of a *keyword list* are a
coincidence; two occurrences of a *number nobody can see is wrong* are the
defect, and only the second one gets a mechanism.

## Options considered

### (a) Fixture location and shape

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| **`tui/tests/fixtures/transcripts/`, input committed + generated `expected.json` (chosen)** | One copy of the bytes; reuses the existing fixtures convention; no number is ever hand-typed, which answers the existing test file's stated objection; short relative path from both suites | A committed synthetic transcript is ~a few KB of data nobody reads; `expected.json` must be regenerated deliberately, and someone will forget — though forgetting fails the JS test loudly | — |
| `scripts/tests/fixtures/transcripts/` | Beside the JS test that exists today | Puts a Rust test's contract inside the shell-scripts tree, and makes the Rust the "visitor"; inverts the direction of the E7 work | Wrong owner; the fixture belongs to the parity contract, not to either consumer |
| A new top-level `docs/fixtures/` or `fixtures/` | Neutral ground, belongs to neither implementation | [observed] `CLAUDE.md` fixes the plugin layout and the brief forbids new top-level dirs outside `tui/`; also puts test data outside the thing that ships | Violates a non-negotiable layout rule for a naming preference |
| Generate the fixture in both suites from a shared spec (no committed JSONL) | Nothing to drift; matches the current tempdir habit | Two generators is two implementations of the *fixture*, which is the same drift one level down — and a generator bug makes both suites agree on the wrong thing | Recreates the exact problem FR-6 exists to solve |
| Committed JSONL with hand-written expected numbers in each suite | Simple; no regeneration step | Exactly what `measure-tokens.test.sh:6-9` warns against — the numbers drift from the pricing table with nothing noticing, and now in two places | Rejected by an objection already recorded in this repo |
| No fixture; compare the two tools' output on the developer's real transcripts | Zero fixture maintenance | Not reproducible, not committable, contains real prompt data, and cannot run in CI | Not a gate |

### (b) Which implementation is authoritative

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| **`measure-tokens.js` authoritative (chosen)** | It is the incumbent with existing output and existing users; a single generator for `expected.json` follows naturally; the TUI is the new thing and new things conform | Freezes JS quirks into the Rust, including ones that look wrong; a JS bug propagates rather than being caught by disagreement | — |
| Rust authoritative | Typed, tested with `cargo test`, likely the long-term survivor; better place for the semantics to live eventually | Reverses the burden onto the tool people already rely on; `expected.json` would be generated by a binary that does not exist yet, blocking the fixture on E7-2 | Bootstrapping is impossible: the authority would have to exist before the thing it certifies |
| Neither — a written spec is authoritative, both conform to it | Language-neutral; the right answer for a long-lived contract | Prose cannot be executed, so a third artifact drifts from both; someone must still decide who is right *today* when they disagree | Adds a document without removing a decision |
| No authority; a disagreement is simply a failed gate someone investigates | Honest about uncertainty | Every disagreement becomes a discussion; a gate with no rule for resolving it gets disabled | A tie-break that requires a meeting is not a tie-break |

### (c) Rate table source

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| **Shared `rates.json`, `require`d by JS and `include_str!`+`serde_json` in Rust (chosen)** | One copy of every number *including the 1.25/0.1 multipliers*; no build-time toolchain; the binary stays self-contained; a rate change is a one-file diff | A small edit to `measure-tokens.js` (literals → file read); the JSON must be valid or both fail; the file is a new artifact to keep inside the shipped tree | — |
| Hand-duplicate `RATES` in Rust | Zero new mechanism; the fastest thing to write | Six numbers plus two multipliers typed twice, in two languages, changed at different times; the fixture catches it only if the fixture happens to exercise the tier that changed | The question explicitly asks that the 1.25/0.1 derivation not be typed twice; this types it twice |
| Generate `rates.rs` from `measure-tokens.js` at build time (`build.rs` shells to Node) | One source; Rust sees plain constants | Puts a **Node-on-PATH bet into the build**, which is the bet ADR-0002 exists to kill — and [observed] `build.rs` was deliberately written to hand-roll SHA-256 so the release pipeline needs nothing extra. It would also make a cross-compilation runner need Node | Reintroduces the rejected dependency one layer down, in the one place ADR-0002 was careful about |
| Generate `rates.rs` from `rates.json` in `build.rs` (pure Rust, no Node) | One source; no runtime parse; constants inlined | Needs a JSON parser inside `build.rs` — either a build-dependency or a second hand-rolled parser — to save one `serde_json` call on a file of eight numbers | Real cost, imaginary benefit |
| Fetch live pricing from an API | Always current | Network at run time, an API key, and a tool that reports different numbers on different days; ADR-0002 forbids run-time network | Wrong shape entirely; the file's own comment says these are list rates and the *split* is the point |
| A shared `.env`/plain-text table parsed by both | No JSON parser needed in either | A bespoke format needs two parsers written by us, which is worse than one format both languages already read | Invents a format to avoid a dependency both already have |

## Consequences

### Positive
- FR-6 becomes checkable: there is a path, a file, a generator command, a
  tolerance, and a named table of which edit fails which suite.
- The 1.25/0.1 derivation exists exactly once in the repository, which is a
  strictly better state than today, where it exists once **only because there is
  one implementation**.
- The authority rule makes a parity failure a five-second triage — the Rust is
  wrong — instead of a debate about pricing semantics.
- `expected.json` doubles as documentation of what the JS actually computes,
  in a form a reviewer can diff.

### Negative — what this costs
- **`measure-tokens.js` is edited.** It gains a file read at startup and a
  relative path dependency on `tui/shared/rates.json`. A script that was a
  single self-contained file no longer is, and running it from a copied-out
  location now fails. That is a real regression in its portability, accepted
  because the alternative is duplicated pricing.
- **`expected.json` is a normalised capture, so "just re-run the tool and diff"
  is not quite the rule.** Three transforms sit between the tool and the file.
  They are enumerated in the ADR, commented in the script, and covered by a
  byte-identity test — three defences, because a future reader who assumes a raw
  capture will delete them and reintroduce the absolute path.
- **Malformed-line *counting* is verified but not parity-verified.** Nothing
  compares it across the two implementations, because nothing can — the JS has
  no such counter. The count is checked in Rust, and the fixture's continued
  possession of a malformed line is checked in bash. If someone later adds a
  counter to `measure-tokens.js`, this becomes parity-checkable and should be
  moved into the contract.
- **A regeneration step exists and will be forgotten.** The failure is loud
  (the JS suite goes red) but it is a new step in the loop, and the error
  message must say `regen-transcript-expected.sh` or the next person will edit
  `expected.json` by hand — which is the one thing it must never be.
- **The Rust deliberately reproduces JS quirks**, so a defect in the JS is now a
  defect in two places by design. The fixture will happily certify the same
  wrong answer twice; it detects *divergence*, not *incorrectness*, and nobody
  should read a green parity gate as "the costs are right".
- **A committed fixture is a maintenance surface.** If Claude Code's transcript
  format changes, the fixture keeps both parsers agreeing on a format that no
  longer exists — a green gate over a dead contract. Nothing here detects that;
  only a human noticing real transcripts stopped parsing will.
- **CRLF is a live hazard.** A `.gitattributes` entry pinning `*.jsonl` under
  the fixture to LF is load-bearing, not tidiness. Without it, the parity gate
  fails on Windows for a reason unrelated to cost.

### What this makes harder later
- Moving the semantics' home to Rust — the obvious eventual direction, since the
  TUI is the long-lived artifact — now means reversing a written authority rule
  and re-pointing the generator, not just deleting a script.
- Adding a fourth pricing tier, or a model whose cache multipliers differ from
  1.25/0.1, breaks the shape of `rates.json`: the multipliers are global there.
  A per-tier multiplier is a `rateVersion` MAJOR bump and touches both readers.
- Changing row ordering or the tie-break in `measure-tokens.js` now has a second
  consumer that must match it, where today it has none.

## Open

- **[OPEN: `implementer`, low severity]** If a real transcript ever produces two
  rows tying on both cost and calls, the two implementations may order them
  differently and the display will disagree between tools. The fix is a third
  tie-break — `agent` then `model`, ascending — added to **both** at once. It is
  not added now because it changes `measure-tokens.js`'s output ordering, which
  the PRD placed out of scope, and the fixture is built to avoid the case.
- **[RESOLVED 2026-08-14, elsewhere]** The questions this ADR's sibling
  (`docs/architecture-e7.md`) left open are settled and recorded here so they
  are not re-asked: verdict thresholds 40% / 80%, a 60-column floor
  (`ux-designer`), a 100ms per-frame render budget at 50 sessions, and session
  scope of most-expensive-first with `j`/`k` (`planner`). None of them touch
  the parity contract.
- **[OPEN: user]** `rates.json` carries list prices, not this account's prices
  [observed, the comment in `measure-tokens.js`]. Whether a user-supplied
  override belongs in `.agent-team.json` is a product question, deliberately not
  answered here.
