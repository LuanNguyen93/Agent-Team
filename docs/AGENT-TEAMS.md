# Agent teams (advanced, opt-in)

Agent teams run teammates as independent Claude Code sessions with a shared task
list and direct messaging, rather than as subagents reporting to one lead. This
plugin works without them. Turn them on deliberately.

## Enable

```json
// settings.json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
```

The feature is experimental and disabled by default.

## When it earns its cost

| Good fit | Why |
|---|---|
| Parallel review | Security, performance, and test-coverage lenses at once, then challenging each other |
| Competing hypotheses | Several theories investigated simultaneously beats anchoring on the first plausible one |
| New modules | Each teammate owns a separate set of files |

| Poor fit | Why |
|---|---|
| Sequential work | Coordination overhead with no parallelism to gain |
| Same-file edits | Teammates are not isolated in worktrees; they overwrite each other |
| QUICK fixes | The team costs more than the task |

Token use scales roughly linearly with teammate count. Start with 3–5.

## The one thing that will surprise you

**`skills` and `mcpServers` in a subagent definition are ignored when it runs as
a teammate.** The agent still runs — just without its doctrine, silently.

Every agent in this plugin therefore carries a `Step 0: load these skills via
the Skill tool` instruction in its body. Keep that instruction if you write new
agents, or they will behave differently as teammates than as subagents.

Teammates do load `CLAUDE.md` and project skills normally, the same as a regular
session. What they do not inherit is the lead's conversation history — so put
the task-specific context in the spawn prompt.

## Enforcement still applies

`TaskCompleted`, `TaskCreated`, and `TeammateIdle` hooks all fire for teammates.
The gate hook in this plugin blocks a teammate from marking a task complete
while the suite is red, exactly as it does for the lead.

## Known limitations

- `/resume` and `/rewind` do not restore in-process teammates
- Teammates sometimes fail to mark tasks complete, blocking dependents
- One team per session; teammates cannot spawn their own teammates
- All teammates start with the lead's permission mode
- Split panes need tmux or iTerm2; in-process mode works anywhere

## Avoiding file conflicts

Teammates are not isolated in worktrees. Partition the work so each teammate
owns a different set of files, or you will get overwrites rather than merges.
