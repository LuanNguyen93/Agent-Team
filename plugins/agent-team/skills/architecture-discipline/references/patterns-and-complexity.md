# Patterns and complexity

Two failure modes, opposite in direction, equally expensive: structure nobody
needed, and structure everybody needed that was never added.

## Patterns by trigger

Reach for the pattern when the **trigger** is present, not when the name sounds
right. Name it in the code so the reader sees the shape.

| Trigger you can observe | Pattern | Do not use it when |
|---|---|---|
| A conditional on a type/kind that grows with every new case | Strategy, or polymorphism | The set is closed and has two members |
| Object construction with conditional wiring, repeated | Factory | There is one construction site |
| Hand-rolled subscriber lists, or "also do X after Y" piling up | Observer / events | Two callers, called directly |
| The same multi-step setup repeated with one step differing | Template method | The steps differ more than they match |
| A third-party API awkward at every call site | Adapter | You call it in one place |
| Cross-cutting behaviour (auth, logging, retry) copied per handler | Decorator / middleware | It applies to one handler |
| A multi-step build where half the arguments are optional | Builder | The constructor takes three arguments |
| Complex state with illegal transitions reachable by accident | State machine | Two states and one flag |

Note the right column. Every one of these becomes over-engineering at low
cardinality — the pattern earns its place by **removing a conditional that would
otherwise grow**, not by existing.

## Patterns that are almost always a mistake here

- **Singleton** — a global with ceremony. Pass the dependency.
- **Repository over an ORM that is already a repository** — a layer that
  forwards `findById` and nothing else.
- **Abstract base class with one subclass** — the subclass is the class.
- **Generic `BaseService<T>`** — inheritance chosen before the second case
  existed. Extract a function instead.
- **Event bus for two components** — indirection that hides the call graph and
  makes the flow untraceable.

## Complexity, stated

Write the complexity where the reader would otherwise have to derive it:

```ts
// O(n + m) — index lookups by id, n = orders, m = line items
```

Table of the traps that actually appear in application code:

| Shape | Cost | Fix |
|---|---|---|
| `array.find()` inside a loop over another array | O(n·m) | Build a `Map` once, look up in the loop |
| `array.includes()` in a loop | O(n²) | `Set` |
| A query inside a loop over rows | N+1 round trips | One query with `IN`, or a join |
| Sorting inside a loop | O(n² log n) | Sort once outside |
| Repeated `array.shift()` on a large array | O(n²) | Index pointer, or a deque |
| String concatenation in a hot loop | O(n²) in some runtimes | Collect and join |
| Recomputing a derived value per iteration | O(n·k) | Hoist it |

## Choosing the algorithm

1. **Find the input bound first.** Everything else follows from it. Ask for the
   real number: rows today, rows in a year, per request or per job.
2. **At small bounds, choose the readable one.** `n ≤ 100` and a linear scan is
   the right answer; a hand-written index there is over-engineering.
3. **At unbounded input, choose the right complexity class** — hash, sort,
   index, or push it to the database, which is better at this than your loop.
4. **Push work to where the data is.** Filtering ten thousand rows in
   application code that the database could have filtered is the most common
   real-world instance of a bad algorithm.
5. **Streaming beats loading** when the input can exceed memory. Say which one
   you chose and what bound makes it safe.

## Measure before the clever version

Micro-optimisation without a profile is a guess that costs readability. The
order is: correct algorithm → measure → optimise the hot path if the measurement
says so → record the measurement in a comment so the next reader does not undo
it.

A comment saying *why* a fast-but-odd implementation exists is what keeps it
alive. Without it, someone will "clean it up" and reintroduce the problem.
