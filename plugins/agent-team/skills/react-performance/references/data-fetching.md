# Data fetching

This is where most real-world slowness lives. A single removed waterfall usually
beats every memoisation in the codebase.

## Waterfalls

A waterfall is a request that cannot start until an earlier one finishes. Some
are genuine dependencies; most are accidental.

```js
// Accidental - these do not depend on each other
const user = await getUser(id)
const posts = await getPosts(id)

// Fixed
const [user, posts] = await Promise.all([getUser(id), getPosts(id)])
```

**Component-level waterfalls** are harder to see: a parent fetches, renders a
child on success, and the child then fetches. The child's request could have
started immediately. Fix by hoisting the request, or by starting it in parallel
and passing the promise down.

**Genuine dependencies** - where the second request needs the first's result -
are fine. Where possible, fold them into one server-side query instead.

## Fetch on the server when you can

In Next.js App Router, fetch inside the server component that renders the data.
Requests dedupe within a render pass, no loading flash, no client bundle cost,
and no waterfall from client hydration.

Reach for client fetching only when the data depends on client-only state
(a live filter, a value from `localStorage`), or must poll.

## Streaming

Do not let the slowest query hold the whole page. Wrap the slow subtree in
`<Suspense>` with a skeleton so the shell paints immediately.

```jsx
<Shell>
  <FastSummary />
  <Suspense fallback={<TableSkeleton />}>
    <SlowTable />
  </Suspense>
</Shell>
```

## Caching and revalidation

Be deliberate; do not accept the default without deciding.

- Static data - cache aggressively
- Data that changes but tolerates staleness - time-based revalidation
- Must-be-fresh (dashboards, balances) - no cache, and say so explicitly
- After a mutation - revalidate the affected paths or tags, do not hand-patch
  client state and hope it matches the server

## Client-side data

Use a real data library (TanStack Query, SWR, or the framework's own) rather
than hand-rolling `useEffect` + `useState`. Hand-rolled fetching almost always
misses at least one of: race conditions between responses, cancellation on
unmount, error states, retry, and deduping.

**Race conditions**: a slower earlier request can resolve after a faster later
one and overwrite it. Guard with `AbortController` or an ignore flag.

```jsx
useEffect(() => {
  let ignore = false
  fetchData(id).then(d => { if (!ignore) setData(d) })
  return () => { ignore = true }
}, [id])
```

## Mutations

- Disable the trigger while in flight - double-submit is the most common bug here
- Make the endpoint idempotent where a retry is plausible
- Optimistic updates need a defined rollback path; without one, a failure leaves
  the UI lying to the user
