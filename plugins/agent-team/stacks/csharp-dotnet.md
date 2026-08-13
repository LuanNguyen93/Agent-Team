# Stack profile: C# / .NET

Applies when: a `*.sln`, `*.slnx`, `*.csproj` or `*.fsproj` at the repo root, or
in the backend directory of a monorepo.

## Gates

| Gate | Typical command | Notes |
|---|---|---|
| format | `dotnet format <target> --verify-no-changes` | fails on diff; never plain `dotnet format` in a gate - that edits |
| build | `dotnet build <target> --nologo` | this **is** the typecheck for C#, so it is never opt-in |
| test | `dotnet test <target> --nologo --no-build` | `--no-build` reuses the build gate's output |

There is no separate typecheck step: the compiler is the type checker. There is
no separate lint step either unless the project adds one - analyzers run inside
the build, and `TreatWarningsAsErrors` in the `.csproj` or `Directory.Build.props`
is what decides whether an analyzer warning blocks. Check that property before
claiming lint is enforced; if it is `false`, warnings are noise and the build
gate is weaker than it looks.

The runner discovers these automatically. Declare `.agent-team.json` explicitly
for a monorepo (`cd backend && dotnet build`), a specific configuration, or a
solution filter (`*.slnf`).

## Conventions to detect and follow

- **SDK version**: `global.json` pins it. Mismatched SDK is the usual cause of
  "works on my machine".
- **Solution layout**: `src/` and `tests/` beside each other is the common shape;
  project names carry the layer (`Acme.Api`, `Acme.Application`, `Acme.Domain`,
  `Acme.Infrastructure`). Those names *declare* a dependency rule - check the
  `ProjectReference` graph matches it before adding one.
- **Nullable**: `<Nullable>enable</Nullable>` in the csproj or props. If it is
  enabled, a `!` null-forgiving operator is a finding, not a fix.
- **Test framework**: xUnit, NUnit or MSTest - read the package reference, do
  not assume xUnit.
- **Formatting config**: `.editorconfig` is authoritative and `dotnet format`
  reads it. Analyzer severity also lives there.
- **DI registration**: `Program.cs` / `Startup.cs`, or an extension method per
  project. New services must be registered where the existing ones are.

## Skills that apply

`backend-discipline`, `architecture-discipline`, `quality-gates`,
`code-navigation`, `context-discipline`, `app-verify` (for a service surface),
`tdd-discipline`.

## How to verify a change

`app-verify` → `references/service-verify.md` is the checklist. The three that
catch the most on this stack:

- **Hit every endpoint the change touched.** A missing `AddScoped` compiles and
  boots, then throws `Unable to resolve service for type ...` on the first call.
- **Send one request without a token**, and one with a token for the wrong
  user. A suite that always runs authenticated never checks the gate exists.
- **Read the startup log** for the environment and the bound URLs. Running under
  `Development` binds a different `appsettings` than the one you are reasoning
  about.

For a change with a React frontend, `browser-verify` covers the client and this
covers the server. Both are needed - the point where they meet is where a
leftover stub hides.

## Things to check in review on this stack

- **`async void`** anywhere except an event handler. The exception cannot be
  caught by the caller and takes the process down.
- **`.Result` or `.Wait()` on a Task** - deadlocks under a synchronisation
  context and burns a thread pool thread everywhere else. `GetAwaiter().GetResult()`
  is the same bug with better manners.
- **A missing `CancellationToken`** on an async method that does I/O, or one
  accepted and then not passed through. A token that stops at the first layer
  is decoration.
- **`IDisposable` not disposed** - especially `HttpClient` created per call
  (socket exhaustion; use `IHttpClientFactory`) and streams in a `catch` path.
- **EF Core: lazy loading in a loop** - the N+1 that does not look like a query.
  Also `ToList()` before the filter, which pulls the table into memory.
- **EF Core: a query without `AsNoTracking()`** on a read path, and any query
  with no `Take()` bound. See `backend-discipline` for the unbounded-query rule.
- **`DbContext` captured in a singleton** or shared across threads. It is not
  thread-safe and the failure is intermittent.
- **Exceptions used for control flow**, and `catch (Exception)` that logs and
  continues. Swallowing loses the stack trace; `throw ex;` also resets it -
  use bare `throw;`.
- **`DateTime.Now`** on anything stored or compared. `DateTimeOffset.UtcNow`.
- **Configuration read via `IConfiguration["key"]` at call sites** instead of a
  bound options class - a typo becomes a silent null at runtime.
- **A record or DTO exposed straight from the domain** through the API, so an
  internal rename becomes a breaking contract change.
