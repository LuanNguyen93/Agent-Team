# Re-renders

**Profile before you optimise.** React DevTools Profiler shows what actually
re-renders and how long it took. Intuition here is wrong more often than right,
and premature memoisation makes code harder to change while saving nothing.

## What causes a re-render

1. State changes in the component
2. A parent re-renders (regardless of props)
3. Context value changes
4. A hook the component uses triggers an update

Note point 2: props being "the same" does not stop a child re-rendering. It only
matters when the child is wrapped in `memo`.

## Fixes, in order of preference

### Move state down
The best fix, because it removes the work instead of caching it. If a parent
holds state only one subtree uses, push the state into that subtree.

```jsx
// Before: typing re-renders ExpensiveList
function Page() {
  const [query, setQuery] = useState('')
  return <><input value={query} onChange={...} /><ExpensiveList /></>
}

// After: typing re-renders only SearchBox
function Page() {
  return <><SearchBox /><ExpensiveList /></>
}
```

### Pass children as a prop
Content passed via `children` is created by the parent's parent, so it is not
recreated when the wrapper's state changes.

```jsx
function Wrapper({ children }) {
  const [open, setOpen] = useState(false)
  return <div>{open && children}</div>   // children not recreated on toggle
}
```

### Split context
A context holding several unrelated values re-renders every consumer when any
one changes. Split into separate contexts by change frequency, and memoise the
provider value.

```jsx
// The value object is new every render without this
const value = useMemo(() => ({ user, logout }), [user, logout])
```

### Then, and only then, memoise
`memo` on the child plus stable props. Both halves are required - `memo` with a
freshly-created object or inline arrow prop does nothing.

## When memoisation is justified without a profile

- The value is a dependency of `useEffect`/`useMemo`/`useCallback` and must be
  referentially stable to avoid an effect loop
- The computation is genuinely expensive (parsing, large sorts, big derived sets)
- The value is passed to a `memo`'d child in a hot list

Everywhere else, the comparison cost and the readability cost are real and the
benefit is not.

## Lists

- **Keys must be stable ids.** Index keys corrupt component state on reorder,
  insert, and delete - a real correctness bug, not a performance one.
- Virtualise beyond roughly 100 rows rather than memoising each row.
- Memoise the row component only once the profiler shows row renders dominating.
