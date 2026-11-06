---
description: Verify quality gates, sync upstream changes, and self-upgrade Agent Team across Claude Code, Antigravity, and Codex.
argument-hint: [--pull] [--skip-tests]
---

Run self-upgrade and synchronization for Agent Team: **$ARGUMENTS**

Execute the upgrade workflow:

1. **Verify Integrity & Quality Gates**:
   Run the test suites to ensure that no regression or broken rule is installed.
2. **Synchronize Platforms**:
   - **Antigravity**: Rebuild and transpile the plugin to `~/.gemini/config/plugins/agent-team`.
   - **Codex**: Export skills to `~/.agents/skills` for OpenAI Codex runners.
   - **Claude Code**: Validate that the manifest, commands, agents, and hooks in `plugins/agent-team` are in sync.
3. **Execution**:
   Run `${CLAUDE_PLUGIN_ROOT}/scripts/upgrade.sh $ARGUMENTS` and report the updated version and platform readiness to the user.
