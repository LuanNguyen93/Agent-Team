---
name: architecture-discipline
description: Keeps a change inside the architecture that was agreed - a declared dependency rule, right-sized structure, patterns used only where they earn their place, and algorithms whose cost is stated. Use when designing, planning, writing, or reviewing code.
when_to_use: Designing a system, planning a change, writing code that adds a file or a layer, or reviewing whether a change fits the agreed shape. Do NOT use to impose a layered architecture on a project that has deliberately declared none.
---

# Architecture discipline

Architecture decays one reasonable-looking commit at a time. Each commit fits
the file it lands in; the sum does not fit anything. Three rules hold it
together, and one rule stops the cure being worse than the disease.

## 1. The dependency rule is declared, once

`architect` writes it into `docs/architecture.md` as a table. Everyone else
obeys it. It is a **direction**, not a folder layout:

| Layer | May import | Must never import |
|---|---|---|
| domain | nothing outside itself | framework, ORM, HTTP, other layers |
| application | domain | framework, HTTP, ORM types |
| adapters | application, domain | — |
| entrypoints | application | domain internals |

The direction points inward. Anything that violates it is **blocking**, even
when it works, because the violation is what makes the next one look normal.

Presets — clean/hexagonal, simple layered, and the honest "no layers, and why" —
are in `references/dependency-rules.md`. Pick one and say which.

**A project may declare no layering.** That is a valid, recorded decision, not
an absence. Then the rule is simply: business logic does not live in a route
handler or a component, and nothing else is enforced.

## 2. Right-size it — over-engineering is a defect

The cost of structure is paid every time someone reads the code; the benefit
arrives only if the predicted change actually happens.

Do not add, without a named present requirement:

- An interface with exactly one implementation, existing only "for testing"
- A layer that forwards calls without transforming anything
- Configuration for a value that has never changed
- A generic mechanism inferred from a single case
- An abstraction over a library, in case the library is replaced

**Two occurrences are a coincidence. Three are a pattern.** Duplicate once and
wait; a wrong abstraction costs more than the duplication it removed, because it
must be un-wound before anything can move.

The test: name the concrete requirement this structure serves *today*. "We might
need to..." is not one. If you cannot name it, delete the structure and ship the
straight-line code.

## 3. Design patterns are applied, not decorated

Reach for a pattern when the problem it solves is present, and **name it** — in
the type name or a one-line comment — so the next reader recognises the shape
instead of reverse-engineering it.

The common miss is the opposite of the common excess: a chain of `if`s that grows
per type wants a strategy or polymorphism; hand-rolled subscriber lists want an
observer; scattered `new` with conditional wiring wants a factory. Missing the
obvious pattern costs as much as inventing one nobody asked for.

The line: if the pattern removes a conditional that would otherwise grow, it
earns its place. If it only adds a name and a file, it does not.
`references/patterns-and-complexity.md` lists the triggers.

## 4. State the cost of every algorithm

Write the best algorithm the problem admits, and say what it is.

- Name the complexity, in time and memory, for anything non-obvious —
  `// O(n log n), n = orders in the window`.
- **A loop inside a loop over the same growing input is a defect.** Hash, index,
  sort first, or push the work into the database.
- Know the input bound. `n ≤ 20` makes O(n²) correct and readable, and reaching
  for something clever there is over-engineering. `n` unbounded from user data
  makes the same code an outage.
- Never optimise without a measurement. "Faster" that was never measured is a
  guess that cost readability.
- Optimise the algorithm before the constant factor. Micro-tuning inside an
  O(n²) loop is effort spent in the wrong place.

Cost and clarity conflict rarely. When they do, take the faster algorithm and
explain it in a comment — but only once the input bound proves it matters.

## Conformance

Before reporting a change complete, state:

- which layer each new file belongs to, and that no import crosses the rule
- any structure you added, and the requirement it serves today
- the complexity of anything that loops over unbounded input
- any ADR this change touches, and whether it still holds

If the change cannot be made inside the agreed architecture, **stop and hand
back to `architect`**. Quietly inventing a second architecture is how a codebase
ends up with two of everything.
