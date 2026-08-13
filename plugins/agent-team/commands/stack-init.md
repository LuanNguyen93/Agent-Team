---
description: Detect this project's stack and gate commands, then write .agent-team.json so the gates run correctly.
---

Set up the agent team for this project.

1. **Detect the stack.** Read `package.json`, `pyproject.toml`, `go.mod`,
   `Cargo.toml`, `pubspec.yaml`, `*.sln` / `*.csproj`, and the lockfile that
   indicates the package manager. A repository can have more than one - a
   `backend/` and a `web/` are two stacks, not one. Also determine whether each
   owned surface has a UI (React, Vue, Flutter, native UI code) versus being a
   pure API, service, CLI, or library.
2. **Establish scope.** If the repository has more than one surface, ask which
   one this team owns before going further:

   > This repo has `src/Api` (C#) and `web` (React). Which does this team own?
   > I will scope searches, gates and review to that.

   Skip the question on a single-surface repository. The scope rules are in the
   `context-discipline` skill.
3. **Find the real gate commands** for the owned surface. Check the project's
   scripts, `Makefile`, and especially `.github/workflows/*.yml` - CI is the
   most reliable source, because it is what actually gates merges.
4. **Verify each command runs** before writing it down. A gate command that does
   not exist is worse than no gate, because it will be reported as a pass.
5. **Write `.agent-team.json`** in the project root:

```json
{
  "scope": {
    "owns": ["src/Api/**", "src/Domain/**"],
    "reads": ["web/src/api/**"],
    "excludes": ["web/**"]
  },
  "surfaces": { "ui": false },
  "gates": ["dotnet build --nologo", "dotnet test --nologo --no-build"]
}
```

`surfaces.ui` records whether the owned scope has a user-facing UI;
`session-routing.sh` reads it to tell the session which UI-only agents and
skills are out of play. Set it explicitly, because an absent key is read as
"unknown", not "no UI".

Order gates cheapest-and-most-localised first, so failures read clearly. In a
monorepo, put the directory in the command (`cd backend && dotnet test`) -
otherwise discovery walks the root and runs the other team's suite.

Declared gates are the **only** gates that run. If you declare them, declare all
of them.

6. **Check for a matching stack profile** in the plugin's `stacks/` directory and
   report whether one applies.

If a category has no command in this project, leave it out rather than inventing
one. Report what you found, what you verified, and what is missing.
