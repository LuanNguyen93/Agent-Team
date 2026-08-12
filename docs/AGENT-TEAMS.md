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

## What testing actually found

**Do not declare a `tools:` allowlist on an agent you may run as a teammate.**
The documentation says coordination tools always survive a `tools` restriction.
They do not. With an allowlist, a teammate had no `SendMessage` and could not
talk to its peers; removing the allowlist restored it. No agent in this plugin
declares `tools:` for this reason.

The task-management tools were still absent from the teammate afterwards, so the
**lead drives the shared task list**, not the teammates.

**Skills did arrive.** The docs say `skills:` is ignored for teammates; measured
on v2.1.228, a `reviewer` teammate had `quality-gates` fully in context. Since
the two disagree, every agent here declares `skills:` *and* instructs itself to
load them via the Skill tool. Keep both if you write new agents.

**Read-only held.** A `reviewer` teammate had no Edit or Write.

**Peer review did real work.** In a two-teammate run over the same file, one
finding — a credential-free admin bypass — was invisible to the security pass
and surfaced only from the correctness reading, and five duplicate findings were
reconciled before reporting.

**Claude may quietly use subagents instead.** Asking for "three teammates to
review in parallel" produced parallel *subagents*, with no team directory and no
mailboxes. Only an explicit "create an agent team" produced
`~/.claude/teams/<id>/inboxes/*.json`. Check for that directory if you need to
know which one you got.

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
