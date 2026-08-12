# Dependency rule presets

`architect` picks one, writes it into `docs/architecture.md`, and says why.
Everyone downstream obeys the table, not the folder names.

The only property that matters is the **direction** of imports. Folder layout is
a convention; direction is the rule.

## Preset A — Clean / hexagonal

For systems with real domain logic, more than one entrypoint (HTTP + queue +
cron), or a long life expectancy.

| Layer | May import | Must never import |
|---|---|---|
| `domain` | nothing outside itself | framework, ORM, HTTP, SDKs |
| `application` (use cases) | `domain` | framework, HTTP types, ORM types |
| `adapters` (repos, clients) | `application` ports, `domain` | other adapters |
| `entrypoints` (routes, jobs) | `application` | `domain` internals, adapters directly |

Consequences to accept before choosing it:

- The domain defines the **port**; the adapter implements it. Dependencies point
  inward, always.
- No ORM entity crosses into `domain`. Map at the boundary, and accept that the
  mapping code is real work.
- Every use case is a class or function with one public entry.

Do not choose this for a CRUD app whose logic is validation plus a database
write. The mapping cost is paid daily; the benefit never arrives.

## Preset B — Simple layered

The right default for most web applications.

| Layer | May import | Must never import |
|---|---|---|
| `models` / schema | nothing | services, routes |
| `services` (business logic) | models | routes, request/response types |
| `routes` / handlers | services | models directly for writes |

The one rule that carries most of the value: **a route handler contains no
business logic** — it parses, calls one service, and formats the result. If a
handler has a branch on a domain condition, that branch belongs in a service.

## Preset C — No layering, declared

Correct for a script, a prototype, a small tool, or a codebase of a few hundred
lines. Write it down so nobody adds layers as an implicit "fix":

> No layering. Logic sits beside its use. Revisit if the codebase passes ~2k
> lines or gains a second entrypoint.

Still enforced: no business logic inside a route handler or a UI component, and
no I/O buried inside a pure function.

## Enforcing it cheaply

Prose in a doc drifts. When the project already has the tooling, encode the rule
so it fails a gate rather than a review:

- ESLint `import/no-restricted-paths`, or `eslint-plugin-boundaries`
- `dependency-cruiser` with a rule per row of the table
- Python `import-linter` contracts
- Go: internal packages, or `go-arch-lint`

Adding one of these is usually a ten-line config, and it converts a recurring
review argument into an exit code. Suggest it once; do not install a new tool
into a project that did not ask for one.

## Recording a deliberate exception

Exceptions happen. An unrecorded one becomes precedent. Record it where the code
is, not only in a doc:

```ts
// ARCH-EXCEPTION(ADR-0007): reads the ORM type directly to avoid mapping
// 40 columns for the export job. Revisit if a second consumer appears.
```

One line, an owner, and a condition for revisiting. An exception with no
condition is just a violation with better manners.
