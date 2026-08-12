# Stack profile: React / Next.js / TypeScript

Applies when `package.json` lists `next` or `react`.

## Gates

| Gate | Typical command | Notes |
|---|---|---|
| typecheck | `tsc --noEmit` | Usually a `typecheck` script. Without one, there is no type gate — say so. |
| lint | `next lint` or `eslint .` | |
| test | `vitest run` / `jest` / `playwright test` | Distinguish unit from e2e; e2e usually needs the app running. |
| build | `next build` | Slow. Run before shipping, not on every task. |

## Conventions to detect and follow

- **Router**: App Router (`app/`) or Pages Router (`pages/`). They differ in
  data fetching, layouts, and where `'use client'` matters. Do not mix idioms.
- **Styling**: Tailwind, CSS Modules, styled-components, or vanilla-extract.
  Extend what is there.
- **Package manager**: from the lockfile — `pnpm-lock.yaml`, `yarn.lock`,
  `package-lock.json`, `bun.lockb`.
- **Path aliases**: read `tsconfig.json` `paths` and use them.
- **Component location**: colocated in the route folder, or a shared `components/`.

## Skills that apply

- `react-performance` — auto-activates on `.tsx`/`.jsx`/`.ts`/`.js`
- `design-intelligence` — for any UI work
- `browser-verify` — verification drives the real app

## Things to check in review on this stack

- `'use client'` sits on the interactive leaf, not a shared module or barrel
- No sequential awaits that could be `Promise.all`
- No `useEffect` fetching what a server component could fetch
- Dependency arrays complete, with no disabled lint rule
- List keys are stable ids, not array indices
- Images through `next/image` with dimensions; fonts through `next/font`
- Server actions validate input and check authorisation server-side
