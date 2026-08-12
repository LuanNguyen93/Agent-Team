---
name: backend-discipline
description: Server-side rules that reviews catch late - trust boundaries, transaction scope, idempotency, unbounded queries, and migrations that must survive a rolling deploy. Use when writing or reviewing API handlers, jobs, queries, or schema changes.
when_to_use: Writing or reviewing an endpoint, background job, queue consumer, database query, or migration. Do NOT use for pure frontend work or for React rendering questions.
paths:
  - "**/api/**"
  - "**/routes/**"
  - "**/server/**"
  - "**/migrations/**"
  - "**/*.sql"
  - "**/*.prisma"
  - "**/schema.rb"
---

# Backend discipline

The defects here are the ones that pass review and fail in production, because
each looks correct in the diff and only breaks under a second request, a retry,
or a half-deployed cluster.

## Where this sits

Layering, placement, and algorithmic cost are `architecture-discipline`. This
skill is what is specific to the server: data, trust, transactions, retries,
and deploys.

## Read the schema, do not infer it

Open the migration or schema file before writing a query. Column names inferred
from a model name, a nullable column assumed non-null, a relation assumed to
exist — these produce code that typechecks and fails at runtime.

If you could not find the schema, say so and mark the query `[assumed]`.

## The trust boundary is the server

- Validate every input **at the edge**, with a schema, before it reaches logic.
- Authorisation belongs on the server. A hidden button is not access control.
  Check on every handler, not once in a middleware you assume runs.
- Authorise the **object**, not just the route. `GET /orders/:id` with a valid
  session is not authorisation; owning order `:id` is.
- Never log secrets, tokens, or PII. Never return an internal error message to
  a client — log it with an ID, return the ID.

## Transactions

State the boundary explicitly: what is inside, what is outside.

- **No network I/O inside a transaction.** An HTTP call, an email, a queue
  publish inside a transaction holds locks for the length of someone else's
  outage.
- Publish events *after* commit, or through an outbox. An event for a
  transaction that later rolled back is a lie that cannot be retracted.
- Check-then-act across a transaction boundary is a race. Use a unique
  constraint, an atomic update, or a lock — not a `SELECT` followed by an
  `INSERT`.

## Anything that can be retried must be idempotent

Webhooks, queue consumers, payment calls, and any handler behind a proxy will be
delivered twice. Design for it: an idempotency key, a unique constraint, or a
state transition that is a no-op when already applied.

Retrying is not the same as being safe to retry. Say which one you have.

## Queries

- Every list query has a **limit**. "There will never be many" is how tables
  reach ten million rows.
- Name the index each filtered or sorted column relies on. If there is none,
  say so — an unindexed query on a growing table is a scheduled outage.
- N+1: a query inside a loop over rows is a defect, not a style issue.

## Migrations must survive a rolling deploy

Old code and new code run at the same time. A migration that is only correct
after every process restarts will break the window in between.

Expand then contract, across separate deploys. Details:
`references/migrations.md`.

## Contracts

Changing a response shape, a status code, an error format, or a required field
is a breaking change even when nothing fails to compile. Additive by default;
if you must break it, say so loudly rather than shipping it quietly. Details:
`references/api-contracts.md`.

## Boring correctness

- Time in UTC, stored with a timezone, formatted only at the edge.
- Money in integer minor units. Never a float.
- IDs opaque and non-sequential where they are exposed.
- Every external call has a timeout. A missing timeout is an unbounded one.

## Reporting

Say which of these you checked and which you did not. "Idempotency not
considered" is a useful line in a report; silence reads as "handled".
