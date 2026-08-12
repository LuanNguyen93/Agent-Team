# ADR-0001: A role boundary is drawn by scope of use, not by exclusive skill ownership — and `architect` arbitrates disputes about it

- **Status**: accepted
- **Date**: 2026-08-13
- **Deciders**: `architect`, acting as arbiter on findings F8 and F10 from the
  `reviewer` pass over the `implementer` split

## Context

Splitting `implementer` into `implementer` + `backend-implementer` +
`frontend-implementer` produced ten review findings. Eight were plain defects
and are fixed. Two were not defects at all — they were arguments about where a
role ends, and both had a real case on each side:

- **F8** — `frontend-implementer` declares and loads `design-intelligence`,
  which `docs/AGENTS.md` assigns to `ux-designer`. Without it, the loading,
  empty and error states the contract implies get built badly or not at all,
  which is the hole the split was meant to close. With it, the implementer can
  invent design decisions `ux-designer` already made.
- **F10** — `architect.md` describes the parallel-split routing condition, which
  `skills/workflow-router/SKILL.md` and `agents/planner.md` also describe. Three
  copies drift, and `CLAUDE.md` forbids duplicating doctrine into an agent body.

Two facts constrain the answer.

**Tier asymmetry** [observed, `skills/workflow-router/SKILL.md`]: `ux-designer`
runs only on the PROJECT tier. On QUICK and FEATURE there is no
`docs/design-system.md` and no `docs/ui-spec.md`. A rule that assumes a design
system exists is wrong for two of the three tiers.

**`paths` cannot express a partial load** [observed, `docs/HARNESS-NOTES.md` §4]:
`paths` controls *when* a skill activates, not *which sections* of it apply. A
skill is atomic. There is no mechanism that gives `frontend-implementer` the
checklist without also giving it the token-and-style-direction method. Adding
`paths` to `design-intelligence` would also auto-activate it in every unrelated
session touching a `.tsx` file — a global change to solve a per-agent problem.

Underneath both findings is a third gap: nothing in this repository says who
decides a boundary dispute. `reviewer` is read-only by design and reports rather
than rules; the context that wrote the code is the wrong party to rule on its
own boundary.

## Decision

**We draw a role boundary by the scope of an agent's use of a skill, not by
exclusive ownership of the skill — and where two agents share a skill, the
downstream agent's file states the narrower scope and reports what it decided.**

Three applications:

1. **F8 — `frontend-implementer` keeps `design-intelligence`, scoped to
   conformance.** It applies the pre-delivery checklist and the state rules to
   the states the contract implies. It does not choose a style direction or
   define tokens. Where `docs/design-system.md` or `docs/ui-spec.md` exists,
   those win outright. Where they do not exist — QUICK and FEATURE — it applies
   the checklist and **reports every state it had to design**, which is what
   keeps the decision traceable rather than silent. The boundary is preserved by
   making the decision visible, not by making it impossible.

2. **F10 — an agent's file may state the obligation it owns, never the routing
   that consumes it.** `architect` owns "the client/server seam is written
   down"; it does not own "then two implementers run in parallel". The sentence
   in `architect.md` is trimmed to the obligation plus one clause of motivation,
   naming no condition, no criteria and no implementer agents. The general rule,
   which is the precedent: **name the obligation, not the destination.** If an
   agent's file would restate a *condition*, a *list*, or a *procedure* that a
   skill already carries, that is the duplication `CLAUDE.md` forbids. A single
   clause saying what the agent's own output makes possible carries no criteria,
   so it has no surface to drift against.

3. **The escalation gap — `architect` is the named arbiter for role-boundary
   disputes, and rules by writing an ADR.** The trigger is narrow: a finding
   about *which agent owns something*, not about code. Everything else stays on
   the existing path. `docs/AGENTS.md` carries the rule; `reviewer` labels such
   findings rather than resolving them; `architect.md` gains one line, because
   an agent that is never told it arbitrates will not.

## Options considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| **Chosen: shared skill, scoped use, decisions reported** | Closes the error-state hole at every tier; keeps the boundary legible; costs one paragraph | Relies on prose the agent may under-apply; `frontend-implementer` still *can* over-reach | — |
| F8: strip `design-intelligence` from `frontend-implementer` | Cleanest possible boundary; one skill, one owner | On QUICK and FEATURE no `ux-designer` runs, so nothing carries the bar for error states — reopens the exact hole the split closed | Purity bought at the price of the defect the change existed to fix |
| F8: `paths`-scoped or partial load | Would give conformance without authoring | Not expressible — `paths` gates activation, not content (`HARNESS-NOTES.md` §4); would also auto-activate the skill globally | Mechanically impossible |
| F8: differ by tier — load only when no `ux-designer` ran | Matches the asymmetry exactly | Frontmatter is static; an agent cannot vary its declared skills per tier. It would become a runtime conditional in prose, more fragile than a scope rule | Cannot be expressed where it would have to hold |
| F10: delete the sentence, cross-reference only | Zero duplication | `architect` loses the reason its seam section matters, and a bare cross-reference to a skill it does not load changes no behaviour | Too weak to hold the behaviour the seam section exists for |
| F10: keep the full routing sentence | Strongest signal to `architect` | Third copy of a condition that will be edited in one place and not the other two | Drift is certain, and silent |
| Escalation: name no arbiter | No new ceremony | This dispute needed one and did not have one; the next is re-argued from scratch | The cost was already paid once |
| Escalation: add an `arbiter` agent | Clear separation of the job | A twelfth agent for a rare event, duplicating what `architect` already does with ADRs | Ceremony this team's size does not justify |

## Consequences

### Positive

- Error, empty and loading states have a named owner on every tier, not only
  PROJECT.
- The split condition exists in two places instead of three, and the remaining
  mention in `architect.md` states no criteria, so it cannot fall out of date.
- Boundary disputes now terminate in a dated document instead of being
  re-litigated by whoever reads the files next.
- The precedent generalises: any future "should agent X get skill Y" is answered
  by scope of use, not by ownership.

### Negative

- `frontend-implementer` can still over-reach. The scope limit is prose, and
  `HARNESS-NOTES.md` §1 is explicit that prose asks where a hook enforces. We
  accept a strong default over no default; there is no hook shape that could
  check this.
- On QUICK and FEATURE the implementer really is making design decisions. We
  have made that visible rather than eliminated it. Anyone wanting a hard
  guarantee that implementers never design must run `ux-designer`, which means
  running the PROJECT tier.
- `architect` is pinned to `opus` [observed, `docs/AGENTS.md`]. Routing a
  boundary dispute to it is expensive relative to the size of a QUICK-tier
  argument. Accepted because these disputes are rare and their outcome is
  permanent.
- `architect` now carries a second job unrelated to designing systems, which
  slightly dilutes its own role boundary — the thing this ADR is about.

### What this makes harder later

Splitting `design-intelligence` into an authoring skill and a conformance skill
is now harder to justify, even though it is the mechanically clean answer. This
ADR makes the shared-skill arrangement work well enough that the pressure to
split it goes away; if the skill later grows a large authoring half that costs
`frontend-implementer` real context, that split has to argue against a decision
on record as working. Supersede this ADR rather than quietly splitting the skill.

Second: naming `architect` as arbiter makes it harder to ever scope `architect`
to the PROJECT tier only. It is now reachable from a QUICK-tier dispute.
