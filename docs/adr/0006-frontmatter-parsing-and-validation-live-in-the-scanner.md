# ADR-0006: Frontmatter interpretation and all validation rules live in the scanner; the TUI asks it to pre-check a candidate edit

- **Status**: accepted
- **Date**: 2026-08-13
- **Deciders**: `architect`, settling the scanner/TUI boundary before implementation splits

## Context

Two processes, written in two languages, need the same knowledge:

- The **scanner** (bash) must parse frontmatter to build the JSON and to emit
  CI findings (PRD FR-3).
- The **TUI** (Rust) must validate an edit *in memory before any disk write*
  (PRD FR-6) — `name` uniqueness across the whole tree, no `:` in `name`, no
  `hooks`/`mcpServers`/`permissionMode` on an agent, and the combined
  description length cap.

The obvious implementation writes a YAML-ish parser and four rules twice, once
per language. The PRD's own risk table already names the drift that follows.
Worse, one of the four rules — `name` uniqueness — is **tree-wide**, so a TUI
that checked it alone would have to maintain a shadow index of every other file
and keep it correct across writes.

Note also what the checks are *for*: they must produce the same verdict for CI
and for a pre-write check. If those two ever disagree, a maintainer can save an
edit the TUI blesses and watch CI reject it, which destroys trust in both.

## Decision

### One parser, one rule set, in bash

The scanner is the **only** component that interprets frontmatter and the
**only** place the validation rules exist. It exposes two subcommands:

```
scanner.sh scan  [--plugin-root P] [--mode M] [--path PROJECT]
    → the full document of ADR-0004 on stdout
    → exit 0 clean · 1 one or more severity:error findings · 2 usage/mode error

scanner.sh check --candidate <file-relative-to-root> \
                 --candidate-frontmatter <path-to-a-file-holding-the-new-block> \
                 [--plugin-root P]
    → the same document, produced as if <file> already contained that block
    → same exit codes
```

`check` re-scans the whole tree, substituting the candidate for that one file's
on-disk frontmatter. It writes nothing. The TUI writes **only** when `check`
exits 0 or exits 1 with no `severity: error` finding attributable to the tree.
Because `check` scans the real tree, `name` uniqueness is correct by
construction — there is no shadow index, and there is nothing to keep in sync.

The cost is that a pre-write check re-reads 33 files. At this size that is a
non-issue (ADR-0005), and it is the same work the TUI does after every write
anyway.

### The seam: structure versus bytes

The TUI does not parse frontmatter, but it does have to *write* it, and a
scanner that re-serialised YAML would reformat files nobody asked it to touch.
The line is drawn at interpretation:

| The scanner decides | The TUI does |
|---|---|
| Where the frontmatter block ends, which keys exist, what each value means, which keys are safely editable (`editableFields`) | Splits the file bytes at the block terminator, replaces the value on a key's line, splices the untouched body back |

The TUI performs **line-surgical substitution**, not a YAML round-trip. It
replaces the value of a key the scanner listed in `editableFields`, in place,
and changes nothing else: not key order, not quoting of other keys, not
whitespace, not comments, not the body's bytes, not the file's line endings
(CRLF versus LF is detected from the original bytes and preserved).

`editableFields` contains a key only when its value is a one-line scalar or a
plain block list of one-line scalars. Block scalars (`|`, `>`), anchors, aliases
and flow collections are **excluded**, and the TUI refuses to edit an excluded
key, offering `$EDITOR` on the raw file instead. That is a deliberate refusal to
handle the messy minority badly.

### The editor adds no keys, and removes only three

`ux-designer` found that PRD FR-5's second acceptance criterion — warn when a
user *enters* `hooks`, `mcpServers` or `permissionMode` — assumes the editor can
add a frontmatter key, which this line-surgical model does not support. Ruled:

**The editor never adds a key.** Adding one means deciding where in the block it
goes, how it is quoted, whether it is a scalar or a list, and how it is indented
— the exact YAML authoring decisions this ADR removed from the TUI. And the
capability exists in no story: E4-1 is a form over existing fields. Building an
add-key path so that a warning can fire about a field the user could only have
added because we built the path is circular.

The brief's underlying constraint — [observed, brief.md:94-97] "any editor
screen must not let a user set these fields on an agent without a visible
warning" — is satisfied more completely by construction than by a warning: the
field cannot be set at all. **PRD FR-5's second acceptance criterion is the
document that must change**, and `pm` should rewrite it against what actually
protects the user:

- a file that already carries a forbidden field is a `FORBIDDEN_FIELD` **error**
  from the scanner, visible in the tree and the findings panel; and
- because it is an error, `check` **blocks every save of that file**, which is
  strictly stronger than warning about it.

**One consequence must be fixed rather than accepted**: that block makes such a
file permanently un-editable in the TUI — the tool would refuse to save the very
repair that would unblock it. So the editor gains exactly one removal
affordance, and no more: **it may delete a key named `hooks`, `mcpServers` or
`permissionMode`, and nothing else.** It is not a general delete-key feature.

Serialisation of a removal stays inside the structure/bytes seam: the scanner
already parsed the block, so it publishes `removableFields` alongside
`editableFields`, and for each of those keys it states the exact line span (the
key line plus its contiguous more-indented continuation lines). The TUI deletes
that span from the verbatim block and touches nothing else — no reordering, no
requoting, no reflow. Removal then goes through the identical `check` → write
path as any other edit, so a removal that would break something else is refused
like anything else.

### Write mechanics

1. Read the file; record its byte length and mtime.
2. Apply every pending field change to the in-memory block — all of them, or
   none (PRD FR-5 "atomically").
3. Write that block to a temp file; run `scanner.sh check`.
4. On any `severity: error`, abort and show **every** failing check, not the
   first (PRD FR-6). Nothing has touched the target file.
5. Re-`stat` the target. If the length or mtime differs from step 1, or the file
   is gone, abort and tell the user to re-scan.
6. Write `<file>.tmp-<pid>` in the **same directory**, then rename it over the
   target — same-directory rename is the closest thing to atomic that is
   portable, and [observed, `std::fs::rename` documentation] it replaces an
   existing destination on Windows as well as on Unix.
7. Re-scan (ADR-0005), then state plainly that `claude plugin validate` has not
   been run and remains the user's job (PRD FR-6, brief.md constraint 6), and —
   for an agent file — that the change needs `/reload-plugins` to take effect
   [observed, `docs/HARNESS-NOTES.md` §9].

## Options considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| **Rules in the scanner; TUI calls `check` (chosen)** | One implementation; CI and the pre-write check cannot disagree; tree-wide uniqueness is free; the rules are exercised by CI every day | A subprocess call per save; the TUI cannot validate with the scanner missing | — |
| Implement the four rules in both languages | No subprocess; instant feedback | Guaranteed drift, named as a risk in the PRD; two places to fix every rule change | The drift is the whole problem |
| Rules in the TUI; the scanner shells out to it | One implementation | Inverts the dependency — CI would then need the TUI binary for whichever target it runs on, so a validator that must work everywhere inherits the five-triple problem | Breaks the scanner's independence (PRD §4 ordering) |
| A shared rules file both languages read (e.g. rules as data) | Single source | The rules are logic, not data: uniqueness needs a cross-file pass, the length cap needs UTF-8 character counting. Encoding them as data means writing two interpreters | A config file with two interpreters is two implementations wearing a hat |
| Scanner re-serialises the whole frontmatter block on write | The TUI writes no YAML at all | Reformats files nobody asked it to touch; loses comments and key order; a diff full of noise | Unacceptable in a repo where the prose is the product |

## Consequences

### Positive
- A rule is added or changed in exactly one file, and CI proves it on the next
  run. The pre-write check inherits it for free.
- The TUI never has to reason about YAML semantics, which is the part most
  likely to be subtly wrong.
- The scanner remains standalone and CI-invocable with no knowledge of the TUI
  whatsoever — the dependency points one way only.

### Negative
- **Every save spawns a subprocess and rescans the tree.** Saves will feel like
  they take a beat rather than being instant. Accepted at 33 files; it is the
  price of the check being the same check CI runs.
- The TUI is useless for editing if `bash` or the scanner is missing, even
  though it could technically write bytes. That is intentional: writing without
  the check is the one thing this design forbids.
- Line-surgical editing means an unusual frontmatter shape is not editable in
  the TUI at all. Users will meet a "not editable here" message and it will feel
  arbitrary until they read why.
- The mtime+size precondition narrows the two-writer window; it does not close
  it. Between step 5 and step 6 another writer can still land. There is no lock,
  and we are not inventing one for a single-user developer tool — the window is
  milliseconds and the loser is a file in a git working tree.

### What this makes harder later
Editing anything the scanner cannot model — a whole file body, `hooks.json`,
`plugin.json` — does not fit this path at all, because `check` validates
frontmatter within a plugin tree. Such a feature needs its own validation route
and should not be bolted onto `check` by widening what "candidate" means.
