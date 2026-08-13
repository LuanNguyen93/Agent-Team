# The dependency audit gate

## Where it sits

```
typecheck  →  lint  →  dependency audit  →  test  →  build  →  static analysis
```

It runs before `test` because it is fast, needs nothing running, and its failure
message is unambiguous — the same reason `lint` precedes it.

It is a **separate gate from static analysis.** SonarQube and its equivalents
analyse the code in the repository; they do not know that a package you depend
on has a published CVE. A green Sonar gate says nothing at all about this one.

## The command, per stack

Use the project's own if it defines one — a `security` or `audit` script, or an
audit step already in `.github/workflows/*.yml`. Otherwise:

| Stack | Command | Notes |
|---|---|---|
| Node / TypeScript | `npm audit --audit-level=high` | `pnpm audit --audit-level high`, `yarn npm audit --severity high`. Match the lockfile. |
| Python | `pip-audit` | Reads the active environment or `-r requirements.txt`. `uv` has no audit of its own. |
| Go | `govulncheck ./...` | Reports only vulnerabilities your code can actually reach. A finding here is close to always real. |
| Rust | `cargo audit` | Needs `cargo-audit` installed. `cargo deny check advisories` where the project already uses it. |
| .NET | `dotnet list package --vulnerable --include-transitive` | Exit code is 0 even with findings — read the output, not the status. |
| Dart / Flutter | `osv-scanner --lockfile=pubspec.lock` | Dart ships no first-party audit. Without `osv-scanner` the gate is **absent**. |

**yarn 1 is the exception.** Its `audit` exit code is a bitmask of the
severities found - 1 info, 2 low, 4 moderate, 8 high, 16 critical - summed. It
accepts `--level high`, but whether that narrows the exit code or only the
printed report is undocumented and has not been confirmed here, so a low
advisory may fail the gate. Run `osv-scanner` against `yarn.lock` instead; the
plugin's gate runner reports the yarn-1 audit as absent rather than risk failing
on advisories it was told to ignore, because a gate people learn to switch off
is worse than one they know is missing.

Any stack, as a fallback: `osv-scanner` against the lockfile.

## Reading the result

- **Not installed is absent, not passing.** `pip-audit: command not found` is a
  gate that did not run. Report it as absent and say what would install it.
- **No lockfile is absent too.** Auditing a resolved-on-the-fly tree measures
  today's registry, not what will be deployed.
- **`dotnet list package` is the exception to exit-code-is-truth.** It returns 0
  with vulnerabilities listed. Parse the output.
- A dev-only dependency is still a real finding — the CI runner it executes on
  usually holds more credentials than production does.

## A finding with no fix

This is the case that produces bad decisions under time pressure. In order:

1. **Is it reachable?** `govulncheck` answers this directly; elsewhere find the
   call path yourself. Unreachable is a real mitigation — but say *unreachable*,
   with the reason, not "false positive".
2. **Is there a patched version?** Take it. A minor bump in a transitive
   dependency is cheaper than the conversation about why you did not.
3. **Can it be overridden?** `overrides` / `resolutions` / a `replace` directive
   pins the transitive package without waiting for the parent to release.
4. **Otherwise it is an accepted risk, and that is the user's call.** Record
   what it is, why it cannot be fixed now, what the exposure is, and when it
   gets revisited.

Never suppress it to make the gate green. `npm audit --audit-level=critical` to
hide a high, an `--ignore-vuln` added quietly, or a `.trivyignore` line with no
comment converts a known risk into an unknown one — which is the only change
that actually makes the system less safe.

## Lockfile discipline

- The lockfile is part of the change. A dependency bump with no lockfile diff
  did not happen; a lockfile diff with no dependency change needs explaining.
- Install with the lockfile authoritative: `npm ci`, `pnpm install --frozen-lockfile`,
  `cargo build --locked`, `go mod verify`.
- A regenerated lockfile touching hundreds of packages inside a feature branch
  is not a detail. Split it into its own commit so it can be reverted alone.
