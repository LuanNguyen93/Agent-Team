---
description: Generate a daily or weekly multi-job progress report with an executive portfolio table, isolated copy-paste standup blocks per job, and optional Obsidian Second-Brain archiving.
argument-hint: [--period daily|weekly] [--workspace <path>...] [--vault <dir>]
---

Generate a multi-job progress report for: **$ARGUMENTS**

1. Load the `pulse-report` skill and run `"${CLAUDE_PLUGIN_ROOT}/skills/pulse-report/scripts/pulse_report.py" $ARGUMENTS` (defaulting to `--period daily` when no arguments are passed, and `--vault docs/brain` if `docs/brain` exists in the current workspace).
2. Present the **Executive Portfolio Overview** table and the **Isolated Per-Job Copy-Paste Standup Blocks** directly to the user so they can copy-paste each job's update into its respective channel without cross-job leakage.
3. Highlight any job that has uncommitted working-tree changes, unticked `- [ ]` tasks, or pending must-have features in `docs/features.csv`.
