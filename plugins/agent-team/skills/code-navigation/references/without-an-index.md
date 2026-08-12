# Navigating without an index

The habits survive the tool. These are slower and less complete — say so when
you report on them.

## Find every caller

Use the language's own resolver first; it understands imports, aliases, and
types that text search does not.

| Stack | Command |
|---|---|
| TypeScript | `npx tsc --noEmit` after the change — the compiler *is* a caller check; plus `rg -n "\bsymbol\b" --type ts` |
| Python | `python -m pyflakes`, or `rg -n "\bsymbol\b" -g '*.py'` plus a check of `getattr` and string dispatch |
| Go | `go build ./...`, `grep -rn` for interface satisfaction (implicit, so nothing declares it) |
| Java / C# | the compiler, then a search for reflection and DI registration |
| Rust | `cargo check`, and trait impls found by `rg "impl .* for "` |

Then widen the net where the compiler stops:

```bash
rg -n "\bhandleSubmit\b"                    # direct references
rg -n "handleSubmit" --glob '!node_modules' # including strings and comments
rg -n "'handleSubmit'|\"handleSubmit\""     # string-keyed dispatch, DI tokens, events
git log -S "handleSubmit" --oneline         # when it appeared or disappeared
git log -L :handleSubmit:src/form.ts        # its whole history, if the file survived
```

The third line is the one people skip, and it is where dynamic dispatch hides.

## Find the tests that cover a change

```bash
rg -l "AppButton" --glob '**/*.{test,spec}.*'      # tests naming the symbol
rg -l "from .*AppButton" --glob '**/*.{test,spec}.*'
```

Both miss a test that exercises the symbol through three layers of imports. When
that matters, run the suite rather than guessing — and say that the targeted
selection was best-effort.

## Trace a flow

Work outward from a fixed point rather than from a guess:

1. Start at the entry point the user described — a route, a CLI command, an
   event handler — not at the symbol you suspect.
2. Follow one hop at a time, reading the called function rather than assuming
   what its name implies.
3. Write the chain down as you go. A flow reconstructed twice because the first
   pass was not recorded is the most common waste in this work.

## Judge the blast radius

Without a graph, approximate it and label the approximation:

- Direct callers from the compiler and search — reasonably complete.
- Transitive callers — one more level by hand, then stop and say where you
  stopped.
- Dynamic edges — enumerate the mechanisms this codebase actually uses (DI
  container, event bus, route table, reflection) and check each one.

Report it as `[inferred]`, with the scope stated. A blast radius presented as
complete, from tools that cannot be complete, is the failure this whole skill
exists to prevent.
