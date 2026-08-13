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

## 2. Teammate skills: docs say dropped, observation says loaded

The agent teams documentation states that the `skills` and `mcpServers` fields
in a subagent definition are **not applied** when it runs as a teammate.

**Measured on v2.1.228, that did not reproduce.** A teammate spawned with the
`reviewer` agent type reported `quality-gates` fully present in its context,
arriving pre-injected in its first user message rather than through a Skill tool
call it made itself.

Do not rely on either behaviour. Every agent here declares `skills:` in
frontmatter *and* carries a "Step 0: load these skills via the Skill tool"
instruction in its body, so the doctrine arrives on whichever path holds.

## 2b. An explicit `tools:` allowlist starves a teammate of coordination tools

The documentation says team coordination tools such as `SendMessage` and the
task-management tools "are always available to a teammate even when `tools`
restricts other tools".

**Measured, that did not hold.** With `tools: Read, Grep, Glob, Bash, Skill` on
the `reviewer` agent, a teammate had exactly those five and no `SendMessage` —
it could not talk to its peers at all. In a separate run, teammates reported
`TaskList`/`TaskUpdate`/`TaskGet` missing and the lead had to drive the shared
task list itself.

Removing the allowlist restored `SendMessage`. The task-management tools were
still not observed on the teammate, so the lead remains the one driving tasks.

This is why no agent here declares `tools:`. The only tool constraint left is
`disallowedTools` on `planner` and `reviewer`, which removes Edit and Write
outright and was verified to hold in team mode.

## 3. Plugin subagents ignore three fields

`hooks`, `mcpServers`, and `permissionMode` are ignored in agent frontmatter
when the agent comes from a plugin, for security reasons. No agent here uses
them. Plugin-level `hooks/hooks.json` is a separate mechanism and does work.

## 4. `paths` auto-activates a skill

`react-performance` and `backend-discipline` set `paths` globs so each loads
only when matching files are in play — `.tsx`/`.jsx` for the first, server and
migration paths for the second — rather than costing context on every session.

## 5. `disable-model-invocation` also blocks preloading

Setting it hides the skill from Claude entirely, including preloading into
subagents. Correct for `/ship`, which should only run when the user says so.
Wrong for any doctrine skill.

## 6. Description length cap

`description` plus `when_to_use` is truncated at 1,536 characters in the skill
listing. Put the key use case first. All fifteen skills here are well under.

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

## 11. `TaskCompleted` does not cover inline work, and `Stop` is not a safe substitute

Verified against https://code.claude.com/docs/en/hooks.md while designing (and
then withdrawing) an inline tier below QUICK.

- `TaskCompleted` fires only when a task created through the `TaskCreate` tool
  is marked completed. It does **not** fire for plain main-context work that
  edits files and ends the turn without ever creating a Task. Any design that
  assumes "the `TaskCompleted` gate hook will catch it" is wrong for inline
  work — it covers task-based work only.
- A plugin `Stop` hook is automatically converted to `SubagentStop` and so
  fires at the completion of **every** spawned subagent, not once per user
  request. A naive `Stop`-hook gate therefore runs the full gate suite once
  per agent, not once per turn. The `agent_id` field is present only inside a
  subagent invocation, so it is the way to distinguish a main-thread `Stop`
  from a subagent's.
- `stop_hook_active` is **not** a documented field on the `Stop` payload —
  checked directly against the docs above; do not assume it exists as a
  re-entrancy guard.
- The `Stop` hook's blocking contract has two distinct paths that are not
  interchangeable: stdout JSON `{"continue": false, "stopReason": ...}` stops
  the session for the **user**, and `stopReason` is explicitly not shown to
  Claude. Exit code 2 with output on stderr is what feeds text back to the
  model and continues the conversation. Picking the wrong one silently loses
  the feedback loop a gate hook depends on.

A MICRO/inline tier was designed against the wrong assumption (that
`TaskCompleted` already gated it) and was withdrawn once the `Stop` hook's
real behaviour — fires per subagent, not per turn — made the fix cost more
than the ceremony it removed. Do not silently re-propose it without solving
per-turn-not-per-subagent detection first.
