# ADR-0003: Mode is derived from the scanner's own location on disk, not by hunting for install markers

- **Status**: accepted
- **Date**: 2026-08-13
- **Deciders**: `architect`, resolving brief.md Open Question 2 / PRD FR-2

## Context

The PRD's proposed rule probes the run root for a plugin marker, and failing
that, looks for "a directory named `agent-team` under a plugin cache/install
location reachable from the root". Investigating what that would actually mean:

[observed] Installed plugins live at
`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. On this machine
that directory holds **three** versions of `agent-team` simultaneously
(`0.1.0`, `0.2.0`, `0.2.1`).
[observed] `~/.claude/plugins/installed_plugins.json` records the authoritative
`installPath`, `version` and `scope` per plugin, as an **array** per plugin key —
a plugin can be installed at user scope and local scope at once.
[observed] `~/.claude/settings.json` carries `enabledPlugins`.

So the "hunt for the install" approach requires the bash scanner to parse two
JSON files without `jq`, disambiguate multiple versions, and disambiguate
multiple scopes — three new failure modes, all of them silent, all of them
producing a *plausible but wrong* root.

Meanwhile [observed] this repo's existing hook scripts already solve root
resolution the simple way:
`DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
(`scripts/gate-task-complete.sh:111`, `scripts/run-gates.sh:236`).

The insight that collapses the problem: the scanner ships **inside** the plugin
it scans. The maintainer runs the copy in their checkout; a user runs the copy in
their plugin cache. In both cases the tree to scan is the script's own parent —
it never has to be found.

## Decision

**Plugin root** (what gets scanned) resolves by this chain, first hit wins, and
the resolved absolute path is always printed in the JSON's `root` and in the
TUI header:

1. `--plugin-root <path>` flag
2. `$CLAUDE_PLUGIN_ROOT` (set by Claude Code when it invokes plugin scripts)
3. `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` — the script's own plugin root

There is no fourth step. The chain cannot fail to produce a path, so
"cannot find the plugin" is not a state that exists.

**Mode** is then derived from that resolved root by two filesystem probes — no
JSON parsing, no globbing, no version selection:

| Signal | Probe |
|---|---|
| `SOURCE` | `<pluginRoot>/../../.claude-plugin/marketplace.json` exists **and** `<pluginRoot>/../../.git` exists (file or directory) |
| `INSTALLED` | the absolute `<pluginRoot>` path contains the path segment sequence `plugins/cache/` under a `.claude` directory |

| SOURCE | INSTALLED | Mode |
|---|---|---|
| yes | no | `maintainer` |
| no | yes | `user` |
| yes | yes | **ambiguous** — refuse |
| no | no | **undetermined** — refuse |

`--mode maintainer|user` overrides the derivation unconditionally, including in
both refusing cases. Any other `--mode` value is a usage error: exit 2, no scan
(FR-2). When mode is ambiguous or undetermined and no `--mode` is given, the
scanner exits 2 with a message naming both probe results and the resolved root,
and the TUI shows that message and blocks every read and edit action (FR-2).

**Project root** (user mode only; the `.agent-team.json` edit target) is a
*separate* axis: `--path` if given, else the current working directory walked
upward to the nearest directory containing `.git` or `.agent-team.json`, else
the current working directory itself. It is displayed alongside the mode. It is
never derived from the plugin root, and in maintainer mode it is not used at all
— maintainer mode has no `.agent-team.json` (brief.md constraint 5).

## Options considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| **Self-location + two probes (chosen)** | No JSON parsing in bash; no version or scope ambiguity; matches existing script precedent; the scanned tree is provably the one the script shipped with | The user must invoke the installed copy's script (by path, or via `$CLAUDE_PLUGIN_ROOT`) rather than a global `agent-team-tui` on PATH | — |
| Parse `installed_plugins.json` for `installPath` | Authoritative; knows version and scope | Hand-rolled JSON parsing without `jq` over a file whose formatting we do not control; array-per-plugin means picking a scope; a wrong pick silently scans the wrong tree | Three silent failure modes to solve a problem self-location does not have |
| Glob `~/.claude/plugins/cache/*/agent-team/*/` | No JSON parsing | [observed] three versions coexist here; needs a version-ordering rule (`sort -V` is not guaranteed in Git Bash) and would show a version the user is not running | Would routinely display a stale version as if it were live |
| Probe the run root for `plugins/agent-team/.claude-plugin/plugin.json` (PRD's literal proposal) | Simple for maintainer mode | Only answers maintainer mode; leaves user mode to one of the rejected options above; and fails when run from inside `plugins/agent-team/` | Half a rule |

## Consequences

### Positive
- Mode detection is two `test -e` calls. It is trivially testable by creating
  directories in a fixture, and it behaves identically on all three platforms.
- The single most dangerous error — editing the wrong tree — is structurally
  hard, because the tree is the one the running script lives in.
- Fail-closed is cheap here, so we take it in both directions (FR-2 ambiguity and
  undetermined cases both block rather than guess).

### Negative
- **Invocation is by path, not by name.** `agent-team-tui` is not installed onto
  the user's `PATH` — the user runs
  `~/.claude/plugins/cache/agent-team/agent-team/<version>/tui/agent-team-tui`,
  or a slash command that expands `${CLAUDE_PLUGIN_ROOT}`. That is less
  convenient than a global command and we are accepting it.
- If a user copies the `tui/` directory out of the plugin, self-location points
  at a tree that is not a plugin, and mode becomes `undetermined`. Correct, but
  it will read as a bug the first time.
- The `INSTALLED` probe is a path-shape heuristic. A user who relocates their
  `.claude` directory in an unusual way gets `undetermined` and must pass
  `--mode`. We prefer that to guessing.

### What this makes harder later
A future "scan an arbitrary plugin at an arbitrary path" feature does not fit
this rule — `--plugin-root` exists as the escape hatch, but mode derivation for a
tree that is neither this checkout nor an install will land in `undetermined`.
Also, if Claude Code ever changes its cache layout, the `INSTALLED` probe breaks;
the failure is loud (`undetermined`, blocked, message printed) rather than a
wrong scan, which is the trade we wanted.
