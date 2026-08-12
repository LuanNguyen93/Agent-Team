# Using a code index

Written against CodeGraph 1.5, which is the index this doctrine was drawn from.
The commands are specific; the habits they encode are not, and the fallbacks in
`without-an-index.md` reproduce them badly but honestly.

**Only when `.codegraph/` exists at the repo root.** No index directory means
indexing was not the user's choice — do not run `codegraph init` to create one.
Use the fallbacks instead.

## The one call that replaces the crawl

```bash
codegraph explore "how does X reach Y"        # a flow
codegraph explore "AppButton variants"        # an area
codegraph explore "src/ui/AppButton.tsx"      # a file, line-numbered
```

It returns the relevant symbols' verbatim source grouped by file, the call paths
between them, and a blast-radius summary — in one round trip. Name a symbol or a
file in the query to get its current source.

When an MCP tool is available it is the same thing: `codegraph_explore` is
deliberately the only tool exposed by default, because a single strong tool gets
picked correctly more often than a menu of narrow ones.

## Before changing a shared symbol

```bash
codegraph callers  handleSubmit          # who depends on this
codegraph callees  handleSubmit          # what it depends on
codegraph impact   handleSubmit -d 2     # the radius, at depth 2
codegraph affected src/ui/AppButton.tsx  # the test files this change touches
```

`impact` answers the planner's question — what else has to change, or at least be
looked at. `affected` answers QA's — which tests are worth running first. Neither
replaces the full suite before a commit.

## Freshness

```bash
codegraph status        # index statistics, and a "Pending sync:" section if behind
```

The watcher syncs on save after a short debounce, and the MCP responses flag a
file that is mid-sync — when a response says a file is pending, read that file
directly rather than trusting the graph for it. That flag is the mechanism, and
the general rule in `SKILL.md` is what to do when you have no such flag.

## Other projects from the same session

Every command takes a project path (`-p`, or `projectPath` on the MCP tool), and
resolves the nearest `.codegraph/` at or above it. A monorepo service or a second
repository can be queried without leaving the session. A path with no index
returns guidance rather than an error.

## What it can see that search cannot

Dynamic-dispatch hops — callbacks, interface to implementation, framework
re-render paths — plus framework routing that links a URL pattern to its handler,
and cross-language bridges. These are exactly the edges a `rg` sweep misses, so
they are the reason a graph answer and a grep answer disagreeing means the grep
was wrong, not the graph.

Still not omniscient: anything constructed at runtime from a computed string, or
code the parser could not read, is invisible to any static index. Both tools
share that blind spot.
