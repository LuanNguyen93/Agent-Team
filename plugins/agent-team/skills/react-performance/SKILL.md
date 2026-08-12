---
name: react-performance
description: React and Next.js correctness and performance rules - re-renders, hooks dependencies, data fetching waterfalls, and bundle cost - ordered by real impact. Use when writing or reviewing React components.
when_to_use: Writing, refactoring, or reviewing React/Next.js code, or diagnosing a slow or misbehaving UI. Do NOT use for non-React frontends.
paths:
  - "**/*.tsx"
  - "**/*.jsx"
---

# React performance and correctness

Ordered by impact. Fixing a data waterfall is worth more than memoising a
hundred components, and most `useMemo` calls cost more than they save.

## Priority 1 - Data fetching

These dominate real-world perceived performance.

**Waterfalls.** Sequential awaits that could be parallel are the single most
common serious defect:

```js
// Bad - 3 round trips in series
const user = await getUser(id)
const org = await getOrg(user.orgId)
const plan = await getPlan(org.planId)

// Good - parallel where independent
const [profile, settings] = await Promise.all([getProfile(id), getSettings(id)])
```

**Fetch where the data is needed**, not at the top and drilled down. In Next.js
App Router, fetch in the server component that renders it; requests dedupe.

**Do not fetch in `useEffect` when the framework can fetch on the server.**
Client-side fetch-on-mount guarantees a loading flash and an extra round trip.

**Stream what is slow.** Wrap slow subtrees in `<Suspense>` so the shell paints
immediately rather than the whole page waiting on the slowest query.

## Priority 2 - Correctness of hooks

Bugs here are worse than slowness, because they are intermittent.

**Dependency arrays must be complete.** A missing dependency means a stale
closure, and stale closures produce bugs that only appear on the second
interaction. Never silence the lint rule to "fix" an infinite loop - the loop
means the dependency is unstable and needs `useCallback`, a ref, or restructuring.

**`useEffect` is for synchronising with something outside React.** It is not for
deriving state. If a value can be computed during render, compute it during
render:

```js
// Bad - extra render, can go stale
const [full, setFull] = useState('')
useEffect(() => { setFull(`${first} ${last}`) }, [first, last])

// Good
const full = `${first} ${last}`
```

**Clean up.** Subscriptions, timers, listeners, and in-flight requests need a
cleanup function, or you leak and set state after unmount.

**Never call hooks conditionally** or in loops. The order must be stable.

## Priority 3 - Re-renders

Measure before optimising. React DevTools Profiler tells you what actually
re-renders; intuition here is usually wrong.

**Do not memoise by default.** `useMemo`, `useCallback`, and `memo` each cost
comparison work and complexity. Reach for them when the profiler shows a real
problem, or when a value is a dependency of another hook and must be stable.

**Move state down.** A component that re-renders too much is often holding state
its parent does not need. Push it into the smallest subtree that uses it.

**Children as props avoids re-render.** Passing an element via `children` means
it is not recreated when the parent's state changes.

**Never create a new object, array, or function inline as a prop** to a memoised
child - it defeats the memo on every render.

**Keys must be stable and identity-bearing.** Array index as a key corrupts state
when the list reorders. Use the item's id.

## Priority 4 - Bundle and render cost

**Barrel imports.** `import { Button } from '@/components'` can pull the whole
barrel into the bundle. Import from the specific module.

**Client boundary.** In Next.js App Router, `'use client'` at the top of a
shared module drags everything it imports to the client. Push the directive to
the leaf that actually needs interactivity.

**Dynamic import** heavy, below-the-fold, or conditional components.

**Images** through `next/image` with explicit dimensions, so layout does not shift.

**Fonts** through `next/font` to avoid a render-blocking request and FOUT.

## Review checklist

- [ ] No sequential awaits that could be `Promise.all`
- [ ] No `useEffect` fetching what the server could fetch
- [ ] Every dependency array complete, no disabled lint rule
- [ ] No state derived in an effect that could be computed in render
- [ ] Every subscription, timer, and listener cleaned up
- [ ] List keys are stable ids, not indices
- [ ] Memoisation justified by a profile, not by habit
- [ ] `'use client'` sits at the leaf, not the shared module
- [ ] Images have dimensions; fonts loaded via the framework
