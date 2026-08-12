# Next.js

## Server and client boundary

Components are server components by default. `'use client'` marks a boundary:
that module **and everything it imports** goes to the client.

**Push the directive to the leaf.** Putting `'use client'` at the top of a
shared layout or barrel drags the whole tree into the bundle. Keep interactive
leaves small and let their parents stay on the server.

**Server components can render client components**, and can pass them
serialisable props. They cannot pass functions or class instances.

**Composition pattern**: to use a server component inside a client component,
pass it as `children` rather than importing it.

```jsx
// Works - server child rendered by a server parent, slotted into a client shell
<ClientShell>
  <ServerContent />
</ClientShell>
```

## Rendering strategy

Decide per route rather than accepting the default:

| Data | Approach |
|---|---|
| Same for everyone, rarely changes | Static |
| Same for everyone, changes periodically | Static + revalidation |
| Per-user or per-request | Dynamic |
| Slow but non-blocking | Stream with `<Suspense>` |

Reading cookies, headers, or `searchParams` opts a route into dynamic rendering.
Do it knowingly - an accidental `cookies()` call in a shared util makes every
route dynamic.

## Bundle

**Barrel imports** are a common and invisible cost. `import { Button } from
'@/components'` can pull the whole barrel. Import from the specific module, or
configure `optimizePackageImports`.

**Dynamic import** anything heavy, below the fold, or conditionally rendered:
editors, charts, maps, modals.

**Check the analyzer** before blaming React. The biggest wins are usually a
single accidentally-included dependency.

## Assets

- **Images**: `next/image` with explicit `width`/`height` (or `fill` plus a
  sized container) so layout does not shift. Set `priority` only on the LCP image.
- **Fonts**: `next/font` - self-hosts, removes the render-blocking request, and
  prevents layout shift from fallback swapping.

## Routing

- `loading.tsx` gives a route-level Suspense boundary for free
- `error.tsx` catches render errors; it must be a client component
- `not-found.tsx` for 404 states
- Colocate route-only components in the route folder; they are not part of the
  shared surface

## Server actions

- Validate every input on the server. The client is not a trust boundary, and an
  action is a public endpoint.
- Check authorisation inside the action itself, not only in the UI that calls it.
- Revalidate affected paths or tags after a mutation.
- Return a serialisable result, and handle the error case in the caller.
