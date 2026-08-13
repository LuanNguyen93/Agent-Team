# Flow

## Routing by scale

The router picks the smallest tier that fits. Over-planning a bug fix wastes the
user's time; under-planning a system produces code nobody can maintain.

```
                        /build <request>
                              |
                     workflow-router
                              |
        +---------------------+---------------------+
        |                     |                     |
      QUICK                FEATURE               PROJECT
   bug / tweak         one capability        new system / epic
        |                     |                     |
        |            analyst, if the problem   analyst -> docs/brief.md
        |            isn't already plain            |
        |               (grilling)                  |
        |                     |                  pm -> docs/prd.md
        |                     |                      |
        |                     |              [ user sign-off ]
        |                     |                      |
        |                     |                 architect -> architecture, ADRs
        |                     |                      |
        |                     |                ux-designer -> design system
        |                     |                      |
        |                     +----------+-----------+
        |                                |
        |                            planner  (read-only)
        |                                |
        +--------------------------------+
                                         |
                    does the plan split into two tracks?
                    (both surfaces + contract with error cases)
                                         |
                     no ---------+-------+------- yes
                      |                            |
                 implementer          backend-impl  ||  frontend-impl
             RED -> GREEN -> REFACTOR   server side      client side,
                      |                                  stubbed, then
                      |                                  wires the real
                      |                                  call last
                      |                            |
                      |                     neither waits for
                      |                        the other
                      |                            |
                      +-------------+--------------+
                                         |
                            +------------+------------+
                            |                         |
                        reviewer            qa-verifier, if there is
                     fresh context          a runnable surface to drive
                     spec + standards       (UI, endpoint, CLI)
                            |                         |
                            +------------+------------+
                                         |
                        +================================+
                        |  TaskCompleted hook (exit 2)   |
                        |  blocks while gates are red    |
                        +================================+
                                         |
                        failing ---------+--------- passing
                            |                         |
                        debugger                 atomic commit
                     reproduce/locate/
                     explain/fix
                            |
                            +--> back to implementer
```

## The invariants

These hold at every tier:

1. **No code before a plan.** On QUICK the plan is a sentence; it still exists.
2. **Review runs on fresh context.** The author cannot see their own assumptions.
3. **A failing gate stops the line.** Enforced by the hook, not by good intentions.

## Two execution modes

**Subagents (default).** Sequential, cheaper, results summarised back into the
main conversation. Right for QUICK and FEATURE.

**Agent team (opt-in).** Independent sessions with a shared task list and
peer-to-peer messaging. Enable with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

Worth the extra tokens for two cases:

- **PROJECT work** where teammates own separate files
- **Parallel review** — security, performance, and test coverage examined at
  once by teammates who then challenge each other's findings

Not worth it for sequential work, same-file edits, or anything with heavy
dependencies between steps. The docs recommend 3–5 teammates; more adds
coordination overhead faster than it adds throughput.

See `AGENT-TEAMS.md` before turning it on.
