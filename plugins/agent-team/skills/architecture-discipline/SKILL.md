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

## 5. CTO System Design & Operational Architecture

A Principal Architect designs solutions for production reliability and operational simplicity,
not textbook purity:

1. **Async vs Sync Workload Partitioning**:
   - Any operation that takes > 200ms, does heavy computation (PDF, CSV, image encoding), or calls third-party APIs (Stripe, OpenAI, SendGrid) MUST be decoupled into background jobs/queues. Never hold an HTTP request open waiting on an external network dependency.
2. **Data Access & Query Optimization**:
   - All foreign keys and query filter columns must declare database indexes.
   - N+1 query waterfalls are architectural defects: mandate batch loading (`JOIN`, `IN (?, ?)`, or DataLoader).
   - Use atomic transactions (ACID) for multi-table mutations. Require idempotency keys for any mutation involving money, inventory, or irreversible state changes.
3. **Concurrency & Race Conditions**:
   - For concurrent record updates, use optimistic locking (a `version` column checked on update).
   - For inventory/balance deductions, use atomic database updates (`UPDATE accounts SET balance = balance - 10 WHERE balance >= 10`).
4. **Caching Strategy with Invalidation**:
   - Never introduce caching without stating: (1) what is cached, (2) the TTL, and (3) the exact mutation events that invalidate the cache.
5. **Infrastructure Pragmatism & TCO**:
   - Maximize existing stack components before recommending new services. A PostgreSQL database with standard indexes can easily handle tens of thousands of queries per second before requiring specialized search engines or NoSQL clusters.
6. **Anti-Hype Single Fit-for-Purpose Solution (Do Not Follow the Crowd)**:
   - Never adopt microservices, event sourcing, Kafka, or complex multi-layer abstractions simply because they are popular in industry blogs.
   - Always converge on **one decisive, right-sized architecture** tailored to the actual input bound, latency budget, and team size. When presenting options, name the crowd-hype option explicitly under Rejected/Overkill and recommend the single simplest design that holds under production load.

## 6. The 7 Immutable Software Engineering Invariants

Frameworks and languages change every year; these seven laws of software engineering are invariant across every stack and harness:

1. **Parse, Don't Validate at Trust Boundaries**: Transform untrusted raw input (HTTP body, CLI args, env vars, LLM JSON, DB rows) into strongly-typed domain structures at the perimeter. Downstream core logic never re-checks raw strings or nullable maps.
2. **Make Illegal States Unrepresentable**: Model state lifecycles using discriminated unions or explicit state machines (`Draft | PendingReview | Approved | Rejected`), never uncoordinated boolean flags (`isApproved && isRejected`).
3. **Locality of Behaviour & High Cohesion / Low Coupling**: Things that change together live together. A reader should understand what a unit does without jumping across five pass-through files.
4. **Idempotency & Deterministic State Transitions**: Every network retry, webhook handler, queue consumer, and financial mutation must produce the exact same state whether delivered once or five times.
5. **Bounded Resource Contracts**: Every list query has a `LIMIT`, every queue has a maximum depth/backpressure policy, every loop has a known input bound, and every external I/O call has an explicit timeout.
6. **Zero Garbage & Root-Cause Fix**: Fix the mechanism in the model, never patch-on-patch with nested defensive `if` wrappers. Delete dead code, orphaned types, and obsolete flags in the same commit.
7. **Mechanical Enforcement over Verbal Wishes**: An invariant that matters is enforced by a type, a database constraint, a deterministic test, or a blocking hook — never just a comment asking developers to be careful.

## 7. Modern Global Business Domain Invariants

Align technical architecture directly with modern global business realities:
- **AI-Native & Agentic Unit Economics**: Bound token/context cost per request, isolate untrusted prompt inputs from tool-execution privileges, cache deterministic lookups, and evaluate non-deterministic outputs against golden datasets (`ai-engineering`).
- **FinTech & Ledger Integrity**: Store money in integer minor units (never IEEE-754 floats), enforce double-entry or append-only audit trails, and guard every balance mutation with an idempotency key and atomic row check (`balance >= amount`).
- **Multi-Tenant B2B SaaS Isolation**: Enforce tenant isolation at the data layer (Row-Level Security or mandatory `tenant_id` composite indexes) verified by a second-tenant isolation test, plus usage metering and RBAC on the object.
- **Global Privacy & Data Residency**: Classify PII at the schema level, support deterministic right-to-erasure (`DELETE` / anonymisation cascades), and never leak PII or secrets into logs, analytics, or LLM prompts.

## Conformance

Before reporting a change complete, state:

- which layer each new file belongs to, and that no import crosses the rule
- any structure you added, and the requirement it serves today
- the complexity of anything that loops over unbounded input
- any ADR this change touches, and whether it still holds

If the change cannot be made inside the agreed architecture, **stop and hand
back to `architect`**. Quietly inventing a second architecture is how a codebase
ends up with two of everything.
