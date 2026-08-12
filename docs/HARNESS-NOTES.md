# Harness notes

Constraints verified against the Claude Code documentation while building this
plugin. Recorded here so the same traps are not re-entered later.

## 1. Hooks enforce; skills only ask

The docs are explicit: an instruction in a skill or `CLAUDE.md` is a request,
not a guarantee. Only a hook is enforcement.

This is why the quality gates live in `hooks/hooks.json` and not only in the
`quality-gates` skill. The skill explains the discipline; the `TaskCompleted`
hook makes it mandatory by exiting 2 when a gate fails, which blocks completion
and returns the failure output to the agent as feedback.

Blocking hook events available for this kind of work:

| Event | Exit 2 effect |
|---|---|
| `TaskCompleted` | Task cannot be marked complete |
| `TaskCreated` | Task is not created |
| `TeammateIdle` | Teammate keeps working instead of going idle |
| `PreToolUse` | Tool call is blocked |
| `Stop` / `SubagentStop` | Turn does not end |

Exit 2 takes precedence over a JSON `permissionDecision: allow`.

## 2. The `skills` frontmatter field is dropped for agent-team teammates

From the agent teams documentation: the `skills` and `mcpServers` fields in a
subagent definition are **not applied** when that definition runs as a teammate.

This fails silently — the agent runs, just without its doctrine. Every agent
here therefore does both: declares `skills:` in frontmatter for the subagent
path, and carries a "Step 0: load these skills via the Skill tool" instruction
in its body for the teammate path.

## 3. Plugin subagents ignore three fields

`hooks`, `mcpServers`, and `permissionMode` are ignored in agent frontmatter
when the agent comes from a plugin, for security reasons. No agent here uses
them. Plugin-level `hooks/hooks.json` is a separate mechanism and does work.

## 4. `paths` auto-activates a skill

`react-performance` sets `paths` globs so it loads only when JS/TS files are in
play, rather than costing context on every session.

## 5. `disable-model-invocation` also blocks preloading

Setting it hides the skill from Claude entirely, including preloading into
subagents. Correct for `/ship`, which should only run when the user says so.
Wrong for any doctrine skill.

## 6. Description length cap

`description` plus `when_to_use` is truncated at 1,536 characters in the skill
listing. Put the key use case first. All ten skills here are well under.

## 7. Directory layout is strict

Only `plugin.json` goes in `.claude-plugin/`. Everything else — `agents/`,
`skills/`, `commands/`, `hooks/`, `scripts/` — must sit at the plugin root.
`marketplace.json` goes in `.claude-plugin/` at the **repository** root.

## 8. Names cannot contain a colon

`:` is reserved for plugin-scoped identifiers. An agent file whose `name`
contains one is not loaded, and the error only appears in the debug log.

Agents in a plugin subfolder get the folder in their scoped id:
`agents/review/security.md` becomes `agent-team:review:security`.

## 9. Live reload is partial

Editing a `SKILL.md` takes effect immediately. Changes to `agents/`,
`hooks/`, or `.mcp.json` need `/reload-plugins` or a restart.

## 10. Validate rather than eyeball

`claude plugin validate ./plugins/agent-team` checks `plugin.json`, skill and
agent frontmatter, and `hooks/hooks.json`.
