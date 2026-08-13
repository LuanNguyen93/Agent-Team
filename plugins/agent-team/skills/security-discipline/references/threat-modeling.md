# Threat modelling that fits in a planning session

The formal version has a name and a workshop. This is the twenty-minute one
that catches most of what the workshop would, and it happens while the design is
still cheap to change.

Four questions, in order.

## 1. What are we building, and where are the boundaries?

Draw the flow and mark every place data crosses from one level of trust to
another: browser → server, service → service, your code → a third party, your
process → the database, a webhook arriving from outside.

Each crossing is where validation and authorisation belong. Inside a boundary,
say so explicitly rather than assuming it — "this queue is only reachable from
the VPC" is a statement that can be checked, and later found untrue.

## 2. Who would attack this, and what do they get?

Name the actors concretely. Not "a hacker" — that produces nothing usable:

- **A legitimate user** doing something they should not be allowed to. This is
  the most common one by far, and authorisation is the whole defence.
- **Another tenant** reaching data that is not theirs.
- **Someone with a stolen session or token.** Assume it happens; what does it
  buy them, and how long is it valid?
- **An insider or a compromised CI job** — what can it read that it need not?
- **The third party you integrate with**, compromised or simply wrong.

For each: what do they want here — money, data, disruption, or free compute?

## 3. What goes wrong?

Walk the flow with each actor. The recurring shapes:

| Shape | The question that surfaces it |
|---|---|
| Spoofing | Where do we decide *who* this is, and could it be forged? |
| Tampering | What does the client send that we then trust — price, quantity, role, tenant? |
| Repudiation | If this were disputed later, what record proves what happened? |
| Disclosure | What does an error message, a timing difference, or a 404-vs-403 reveal? |
| Denial of service | What here is expensive and unauthenticated? |
| Elevation | Which path lets someone become more than they are? |

Write the concrete failure — the input and the wrong result — not the category.
An unfalsifiable worry is noise; `architecture-discipline` and `reviewer` hold
the same standard.

## 4. What do we do about each one?

Every finding ends in one of four, stated explicitly:

- **Mitigate** — the control, and where it lives in the design.
- **Eliminate** — remove the feature or the data that creates it. Underrated.
- **Transfer** — the payment processor holds the card numbers, not you.
- **Accept** — with the reason and who accepted it. A written acceptance is a
  decision; an unwritten one is an oversight.

## Data classification, at the same time

For each field the design introduces:

| Field | Personal? | Who reads it | Retention | On deletion request |
|---|---|---|---|---|

Filling this while the schema is still a proposal costs minutes. Filling it
after launch is a migration, a backfill, and a conversation with legal.

## What this produces

Feed it into the **Security** section of `docs/architecture.md` — trust
boundaries, the actors, the decisions with their four-way disposition, and the
classification table. Not a paragraph saying security was considered.

If the design has no user input, no identity, no personal data and no money,
say that in one line and move on. Ceremony applied to a static page is how
teams learn to skip the step that mattered.
