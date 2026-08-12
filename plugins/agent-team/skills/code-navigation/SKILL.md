---
name: code-navigation
description: Find code by structure rather than by crawling files - query an index or language tooling first, establish the blast radius before changing a shared symbol, and never treat a grep miss as proof of absence. Use before reading, planning, changing, or reviewing unfamiliar code.
when_to_use: Locating where something lives, tracing a flow, finding every caller before a change, or judging what a change can break. Do NOT use as a substitute for reading the code it points you at.
---

# Code navigation

The default failure is not getting lost. It is **crawling** — grep, open a file,
grep again, rebuild the call graph by hand — and arriving with a confident map
that is missing the one edge that mattered.

## Order of discovery

Cheapest and most complete first. Drop to the next only when the one above is
unavailable:

1. **A code index**, when the repository has one — a `.codegraph/` directory
   means one query returns the relevant source, the call paths between symbols,
   and the blast radius, including dynamic-dispatch hops. Commands in
   `references/codegraph.md`.
2. **Language tooling** — the type checker, "find references", the build
   system's dependency graph. It knows what text search cannot.
3. **Search** — `rg` for a symbol, `git log -S` for when a behaviour appeared,
   `git blame` for why.
4. **Reading files**, once you know which ones.

Most crawling is step 3 and 4 doing step 1's job.

## Do not delegate the search you can answer directly

A structural query answers in one call. Handing the same question to an
exploration subagent that reads files reintroduces the crawl and pays for it
twice — the subagent burns the context, and you still have to verify its
summary. Delegate breadth, not structure: many independent questions, yes; one
call graph, no.

## A search that found nothing has not proved anything

Text search cannot follow: dynamic dispatch and interface→implementation,
dependency injection, string-keyed registries and event names, reflection,
generated or bundled code, framework routing that maps a URL to a handler by
convention, re-exports and barrel files that rename on the way through.

So `[observed] rg found no callers` supports only `[inferred] there may be no
static callers`. Before deleting or changing a signature on that basis, check
the graph, the DI container, the route table, and the string literals. Say which
of these you checked — that list is the evidence, not the empty grep output.

## Establish the blast radius before you change a shared symbol

Before editing anything with more than one caller, get: every caller, every
implementation of the interface, and the tests that cover them. `planner` names
them in the plan, `implementer` checks them before changing a signature, and
`reviewer` treats an unexamined caller as a real finding.

The question is not "does my change compile" but **"which callers assumed the
old behaviour"** — a compatible signature with different semantics breaks
silently, which is worse.

Then find the tests the change actually affects, and run those first — a fast
targeted run before the full suite is a shorter feedback loop, not a substitute
for it.

## An index can be stale

Any derived view — a graph, a cached symbol list, a summary from an earlier
turn — describes the code as of some moment. Before trusting it for a claim,
check its freshness, and read the file directly when it is behind. Treat an
index answer as `[observed]` only when you have reason to believe it is current;
otherwise it is `[inferred]`, per `handoff-contract`.

## Report what you searched

State the tool, the query, and the scope: "graph query for `AppButton` callers
across the repo" or "`rg` over `src/`, excluding generated". A finding with no
stated scope cannot be judged, and a scope silently narrower than the reader
assumes is how a missed caller ships.
