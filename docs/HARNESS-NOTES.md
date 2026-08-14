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

## 12. A version that does not change is a plugin that never updates

`claude plugin validate` passes on a tree whose content has moved far ahead of
its `version`. The installer does not compare contents — it keys off the version
in `plugin.json`. Content added under an already-installed version is content no
installation ever receives.

**Measured on this repository.** `ai-engineering`, `context-discipline` and
`security-discipline` were added to `plugins/agent-team/skills/` without a
version bump. The installed cache stayed at `0.2.1` (commit `2c20144`) with
**15 skills**, while the tree had 18.

The failure is quieter than it first looks, and the shape of it matters:

- The installed copy is **internally consistent**. Its agents were frozen at the
  same commit, so none of them references the three missing skills. Nothing
  asked for a skill that was not there; nothing could have raised.
- What was lost is everything committed after `2c20144` — three skills and every
  agent revision that referenced them. Sessions kept running a plugin many
  commits behind the tree, with no signal anywhere that they were.
- That is the reason this is worth a note. A broken install announces itself. An
  install that is merely *old* behaves perfectly and silently withholds every
  improvement made since.

The check that catches it is `scripts/tests/plugin-shipping.test.sh`: if plugin
content changed since the commit that last touched `plugin.json`, the version
must differ. It also asserts that frontmatter `skills:` and the Step 0 load list
name the same set, because section 2 means doctrine can arrive by either path
and a disagreement between them is invisible at runtime.

Two habits follow: bump the version in the same commit that adds a skill or an
agent, and confirm what is actually installed rather than what is in the tree —

```bash
ls ~/.claude/plugins/cache/agent-team/agent-team/*/skills
```

## 13. Context size is only recoverable from the transcript

Nothing in the hook environment reports how large the context has become. The
number exists only in the transcript the harness writes: each assistant record
carries a `usage` block, and the newest one describes the request that just went
out — `cache_read + cache_creation + input` is what that request had to carry.

`scripts/context-size.js` reads it back, and both context hooks are built on it.
Two things it has to survive, and does:

- **`transcript_path` may be absent from the payload.** The fallback is the
  newest `.jsonl` under `CLAUDE_PROJECT_DIR`.
- **On Git Bash, MSYS rewrites POSIX paths in `argv` but not in stdin.** A path
  that works as `--transcript /tmp/x` fails when the same string arrives inside
  a JSON payload. Tests must pass a native path (`cygpath -m`) or they test the
  rewrite instead of the code.

## 14. The non-blocking delivery contract differs per hook event

**Measured on this repository**, in `scripts/delegation-nudge.sh`. Plain
`stdout` with `exit 0` on a `PreToolUse` hook is **not** delivered to Claude —
the hook can run, fire, and even burn a one-time state flag, while the agent
never sees a single character of it. `exit 2` does reach Claude (per section 1)
but takes the blocking path, denying the tool call — wrong for a hook whose
whole point is to never block.

The non-blocking channel that reaches Claude on `PreToolUse` is a JSON object
on stdout with `exit 0`:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"..."}}
```

This is *not* a general rule for every hook event — it is specific to
`PreToolUse`. `scripts/context-budget.sh` (`hooks/hooks.json:3-14`, registered
under `UserPromptSubmit`) reaches Claude with a plain `cat <<EOF` to stdout and
no envelope, and that is correct for `UserPromptSubmit`, where plain stdout
*is* the documented delivery mechanism. Do not read it as an envelope
precedent — it is the counterexample that shows the contract is per-event, not
uniform: check `hooks/hooks.json` for which event a hook is registered under
before assuming which delivery shape applies.

`delegation-nudge.sh` used plain stdout on `PreToolUse` and shipped as a
silent no-op until this was caught by strengthening its test from "output is
non-empty" to actually parsing the JSON and checking
`hookSpecificOutput.additionalContext`. A test that only checks for non-empty
output cannot tell a delivered nudge from one shouted into a channel nobody
reads.
