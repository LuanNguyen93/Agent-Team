# Hooks correctness

Bugs here are worse than slowness because they are intermittent: they appear on
the second click, or only after a prop changes, and they survive review.

## Dependency arrays

**Complete, always.** Every value from component scope that the effect reads
goes in the array. A missing dependency captures a stale closure.

```jsx
// Bug: always logs the count from the render the effect last ran in
useEffect(() => {
  const id = setInterval(() => console.log(count), 1000)
  return () => clearInterval(id)
}, [])   // count missing
```

**Never disable the lint rule to stop a loop.** The loop is the symptom; the
cause is a dependency whose identity changes every render. Fix the cause:

- Function dependency: wrap in `useCallback`, or move it inside the effect
- Object/array dependency: `useMemo` it, or depend on the primitive fields
- Only needed as a "latest value", not as a trigger: hold it in a ref

## useEffect is for external synchronisation

It exists to sync React with something outside React: subscriptions, timers,
the DOM, network, browser APIs. It is not a place to compute state.

**Do not derive state in an effect.** If it can be computed during render,
compute it during render - one fewer render, and it can never be stale.

```jsx
// Bad
const [visible, setVisible] = useState([])
useEffect(() => { setVisible(items.filter(i => i.active)) }, [items])

// Good
const visible = items.filter(i => i.active)
```

**Do not sync props into state.** It creates two sources of truth. If you need
to reset on a prop change, use a `key` on the component instead.

**Do not fetch in an effect when the framework can fetch on the server.** It
guarantees a loading flash plus an extra round trip.

## Cleanup

Anything that outlives the render needs a cleanup function:

- `setInterval` / `setTimeout` - clear
- Event listeners - remove
- Subscriptions / sockets - unsubscribe / close
- In-flight requests - `AbortController`, so a late response cannot set state
  on an unmounted component or overwrite a newer one

Cleanup also runs between re-runs of the effect, not only on unmount. Write it
so running twice is safe.

## Rules of hooks

- Never call a hook conditionally, in a loop, or after an early return. The call
  order must be identical on every render.
- Hooks only from components or other hooks.

## useRef vs useState

- `useState` when the UI must react to the change.
- `useRef` for values that must persist without triggering a render: timer ids,
  DOM nodes, the previous value, "latest" callbacks.

Mutating a ref does not re-render. If the screen should update, it is state.

## useLayoutEffect

Only when you must read layout and mutate the DOM before paint - measuring an
element and positioning something against it. It blocks paint, so everything
else belongs in `useEffect`.
