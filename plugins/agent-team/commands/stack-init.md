---
description: Detect this project's stack and gate commands, then write .agent-team.json so the gates run correctly.
---

Set up the agent team for this project.

1. **Detect the stack.** Read `package.json`, `pyproject.toml`, `go.mod`,
   `Cargo.toml`, `*.csproj`, and the lockfile that indicates the package manager.
2. **Find the real gate commands.** Check the project's scripts, `Makefile`, and
   especially `.github/workflows/*.yml` — CI is the most reliable source, because
   it is what actually gates merges.
3. **Verify each command runs** before writing it down. A gate command that does
   not exist is worse than no gate, because it will be reported as a pass.
4. **Write `.agent-team.json`** in the project root:

```json
{
  "gates": ["pnpm typecheck", "pnpm lint", "pnpm test"]
}
```

Order gates cheapest-and-most-localised first, so failures read clearly.

5. **Check for a matching stack profile** in the plugin's `stacks/` directory and
   report whether one applies.

If a category has no command in this project, leave it out rather than inventing
one. Report what you found, what you verified, and what is missing.
