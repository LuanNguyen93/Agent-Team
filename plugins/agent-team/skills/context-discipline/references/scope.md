# Declaring and honouring scope

## Why this exists

Most real work happens in a repository the team does not own end to end. A
monorepo has a frontend and a backend; you were brought in for one of them. A
platform repo has six services; your ticket touches one. Without a declared
scope the team behaves as if it owns everything: it reads the other surface,
reviews it, reports findings against it, and occasionally changes it.

That is expensive three ways. It burns context on code nobody asked about, it
produces review noise the owning team did not request, and it can produce a
change that lands in someone else's area without their knowledge.

## The config

`.agent-team.json`, in the project root:

```json
{
  "scope": {
    "owns": ["src/Api/**", "src/Application/**", "src/Domain/**", "src/Infrastructure/**"],
    "reads": ["web/src/api/**", "docs/**"],
    "excludes": ["web/**", "mobile/**", "infra/terraform/**"]
  },
  "gates": ["dotnet build", "dotnet test"]
}
```

| Key | Meaning |
|---|---|
| `owns` | plan, change, test, gate and review these |
| `reads` | read as evidence; never change; findings are notes, not blockers |
| `excludes` | do not read at all unless the user names the file |

All three are optional and all are glob patterns relative to the project root.
`owns` absent means the whole repository is owned - the correct default for a
single-surface project.

Precedence when a path matches more than one: `owns` wins over `reads`, `reads`
wins over `excludes`. So `owns: ["src/**"]` with `excludes: ["**/*.generated.cs"]`
does what it reads like.

## When scope is not declared

If `.agent-team.json` has no `scope` and the repository has more than one clear
surface - a `web/` next to a `src/Api/`, an `app/` next to a `backend/`,
multiple service directories - **ask** before the first wide search:

> This repo has `src/Api` (C#) and `web` (React). Which does this team own?
> I will scope searches, gates and review to that.

Then write the answer into `.agent-team.json` so it survives a compaction. One
question at the start is far cheaper than a review that spans a surface the user
does not maintain.

Do not ask on a single-surface repository, and do not ask when the user has
already named the files to change.

## What each mode permits

**Owned.** Normal work. Search it, plan against it, change it, run its gates,
review it, report findings as blocking.

**Read.** You may open the file to establish a contract - what a caller sends,
what shape a response must keep, what a shared type declares. You may quote it
as evidence. You may not edit it, count it in a review, or let its problems
block your change. If you find something genuinely wrong there, report it once,
in the closing block, addressed to whoever owns it:

> Open: `web/src/api/reports.ts` still sends `page_size` as a string; owned by
> the frontend team, not changed here. Our handler accepts both for now.

**Excluded.** Not read. If a task turns out to require it, stop and say the
scope is wrong rather than quietly widening it.

## Gates follow scope

A scoped team runs the gates of what it owns. In a monorepo that usually means
declaring the gates explicitly, with the directory in the command:

```json
{
  "scope": { "owns": ["backend/**"] },
  "gates": ["cd backend && dotnet build", "cd backend && dotnet test"]
}
```

Without that, gate discovery walks the project root, finds the frontend's
`package.json`, and runs the frontend suite - which is both slow and not yours.
When gates are declared explicitly they are the only gates that run.

A red gate outside the scope is **not your failure and not your pass**. Report
it as pre-existing and out of scope, with the command and output, and do not
attempt to fix it.

## Review follows scope

The reviewer reviews the diff, and the diff should already be inside `owns`. If
it is not, that is itself the first finding: a change landed outside the team's
scope. Say which file, and stop.
