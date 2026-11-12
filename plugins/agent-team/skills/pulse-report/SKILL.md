---
name: pulse-report
description: Generates evidence-backed Daily and Weekly progress reports across multiple concurrent jobs/projects in one zero-token pass, producing both an Executive Portfolio Overview for you and strictly isolated, copy-paste-ready standup blocks per job.
when_to_use: When the user asks for a daily standup, weekly status report, multi-job progress summary, or wants to review what was completed, what is pending, and what is blocked across one or multiple repositories. Do NOT use as a substitute for running quality gates.
---

# Multi-Job Daily & Weekly Pulse Reporting

When you juggle multiple jobs, clients, or repositories concurrently, status reporting breaks down in three ways:
1. **Context Switching Tax**: Trying to remember at 9 AM or Friday afternoon what you shipped in Job A vs Job B vs Job C.
2. **Cross-Job Information Leakage**: Accidentally mixing terminology, branch names, or tasks from one job into another job's standup.
3. **Narrative Guessing**: Writing vague updates ("worked on backend") instead of concrete `[observed]` deliverables backed by commits, ticked checkboxes (`- [x]`), and feature parity rows.

This skill eliminates all three with a single deterministic CLI pass (`scripts/pulse_report.py`).

## 1. Zero-Token Multi-Job Aggregation (`pulse_report.py`)

Run `pulse_report.py` across one or more workspace directories (or configure `~/.agent-team-jobs.json` once so every run scans all your jobs automatically):

```bash
# Single current workspace — Daily standup (last 24 hours):
python3 "${CLAUDE_PLUGIN_ROOT}/skills/pulse-report/scripts/pulse_report.py" --period daily

# Multiple concurrent jobs — Weekly executive rollup + per-job copy-paste standups, archived to Obsidian:
python3 "${CLAUDE_PLUGIN_ROOT}/skills/pulse-report/scripts/pulse_report.py" \
  --workspace /path/to/job-alpha \
  --workspace /path/to/job-beta \
  --period weekly \
  --vault docs/brain
```

### Multi-Job Registry (`~/.agent-team-jobs.json`)
To avoid typing `--workspace` every day, create `~/.agent-team-jobs.json` (or `.agent-team-jobs.json` in your main hub):

```json
{
  "jobs": [
    { "name": "Job-A-FinTech", "path": "D:/Work/JobA-Backend" },
    { "name": "Job-B-SaaS", "path": "D:/Work/JobB-Web" },
    { "name": "Agent-Team-Core", "path": "D:/Data/Plugins/Agent-Team" }
  ]
}
```

## 2. Strict Per-Job Isolation & Radical Honesty

1. **Zero Cross-Contamination**: Each job is rendered in its own fenced `Copy-Paste Standup / Status Block` containing only that repository's commits, ticked `- [x]` tasks, pending `- [ ]` tasks, and uncommitted file count. You can copy-paste each block directly into that job's Slack, Teams, Jira, or Linear channel.
2. **Evidence-Only (`[observed]`)**: Nothing is fabricated. If a job had 0 commits and 0 newly ticked checkboxes in the window, the report states that plainly so you know where attention is needed.
3. **Second-Brain Compounding**: Passing `--vault docs/brain` (or your Obsidian vault path) automatically archives `pulse-daily-YYYY-MM-DD.md` or `pulse-weekly-YYYY-MM-DD.md` with Obsidian YAML frontmatter and `[[00-MOC]]` links.
