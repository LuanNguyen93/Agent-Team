# Migrations under a rolling deploy

During a deploy, the old code and the new code run against the same database at
the same time. Every migration must be correct for **both**.

The rule: a single deploy may change the schema **or** depend on the change,
never both.

## Expand and contract

Renaming `users.name` to `users.full_name`, safely, is three deploys:

1. **Expand** — add `full_name`, nullable. Old code ignores it. Backfill it, and
   have new code write **both** columns.
2. **Migrate** — new code reads `full_name`, still writes both. Verify the
   backfill is complete before moving on.
3. **Contract** — stop writing `name`, then drop it. Only once no running
   process reads it.

A one-step rename breaks every old process still in the pool.

## Destructive operations

Dropping a column or table, or making a nullable column `NOT NULL`, is only safe
once you can show nothing still writes to it or writes null. "I grepped the
repo" does not cover other services, jobs, or analytics.

Never combine a destructive migration with the code change that makes it
correct. If the deploy rolls back, the schema does not.

## Locks

On a large table, these take a lock long enough to be an outage:

- Adding a column **with a default** on older Postgres/MySQL versions
- Adding a `NOT NULL` constraint without a prior validated check
- Creating an index without `CONCURRENTLY` (Postgres)
- `ALTER TABLE` that rewrites the table

Say which of these your migration does, and on a table of what size. If you do
not know the row count, that is the first thing to find out.

## Backfills

A backfill over a large table runs in batches with a bound, not as one statement.
It must be resumable and safe to run twice. Run it as its own step, not inside
the migration that adds the column.

## Down migrations

Write one, or state plainly that the migration is not reversible and what the
recovery path is instead (restore, manual fix). An untested `down` that would
lose data is worse than an honest "irreversible".
