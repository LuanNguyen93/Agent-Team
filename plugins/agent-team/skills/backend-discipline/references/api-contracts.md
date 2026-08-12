# API contracts

A contract breaks when a client that worked yesterday stops working — not when
the compiler complains. Most breaking changes compile fine.

## Breaking, even though nothing fails to build

- Removing or renaming a response field
- Changing a field's type, including `number` → `string` for a large ID
- Making an optional request field required, or narrowing accepted values
- Changing a status code, or the shape of an error body
- Changing default sort order, page size, or pagination style
- Tightening validation on something previously accepted
- Changing timezone, precision, or units of an existing field

Additive changes — a new optional request field, a new response field — are
safe, provided clients are not written to reject unknown fields.

## When you must break it

Say so explicitly in the report, and name:

- who consumes this endpoint, and how you determined that
- the version or migration path offered
- what happens to an in-flight client that has not updated

A breaking change shipped without this line is the one that gets discovered by a
user.

## Errors are part of the contract

One error shape across the API. Machine-readable code, human message, and a
correlation ID. Do not leak stack traces, SQL, or internal paths — log those
against the correlation ID instead.

The status code is part of the contract too: `4xx` means the client can fix it,
`5xx` means it cannot. A handler that returns `200` with `{"error": ...}` makes
every client's retry logic wrong.

## Pagination and limits

Every collection endpoint is paginated from the first version. Adding pagination
later is a breaking change; having it from the start is free.

State the default page size, the maximum, and whether the cursor is stable under
concurrent writes.

## Idempotency at the edge

Any non-`GET` endpoint a client may retry — payments, order creation, anything
behind a flaky network — accepts an idempotency key and returns the original
result on replay. See the transaction and idempotency sections in `SKILL.md`.
