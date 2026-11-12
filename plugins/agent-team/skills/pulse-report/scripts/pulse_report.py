#!/usr/bin/env python3
"""
Multi-Job Daily & Weekly Pulse Report Aggregator for Agent Team.

Solves the multi-job / multi-project progress reporting gap:
1. Scans one or more workspaces (or a `~/.agent-team-jobs.json` / `.agent-team.json`
   registry) in a single zero-token pass.
2. Extracts real `[observed]` evidence per job:
   - Git commits in the time window (`daily` = 24h / `weekly` = 7d / custom `--since`)
   - Uncommitted working-tree file counts
   - Completed `- [x]` and pending `- [ ]` tasks across `docs/tasks.md`,
     `docs/plan.md`, `docs/brief.md`, `docs/prd.md`, `docs/stories/*.md`
   - Feature parity progress in `docs/features.csv`
   - Distilled Second-Brain notes in `docs/brain/*.md`
3. Generates:
   - Executive Portfolio Summary table across all jobs
   - Strictly isolated per-job Copy-Paste Standup / Weekly blocks (so Job A's
     context never leaks into Job B's client/standup report)
   - Optional Obsidian Second-Brain pulse note (`--vault <dir>`)

Standard library only.
"""

import argparse
import csv
import datetime
import glob
import json
import os
import re
import subprocess
import sys
from typing import Dict, List, Optional

CHECKBOX_RE = re.compile(r"^(\s*[-*]\s+\[)([ xX])(\]\s+)(.+)$")

TASK_PATTERNS = (
    "docs/tasks.md",
    "docs/plan.md",
    "docs/brief.md",
    "docs/prd.md",
    "docs/stories/*.md",
    "TODO.md",
    "TASKS.md",
)


def today_iso() -> str:
    return datetime.date.today().isoformat()


def load_jobs_config(config_path: Optional[str] = None) -> List[Dict[str, str]]:
    """Load workspace list from config JSON if present."""
    candidates = []
    if config_path:
        candidates.append(config_path)
    candidates.extend([
        os.path.join(os.getcwd(), ".agent-team-jobs.json"),
        os.path.expanduser("~/.agent-team-jobs.json"),
    ])
    for path in candidates:
        if path and os.path.isfile(path):
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    data = json.load(fh)
                jobs = data.get("jobs") or data.get("workspaces") or []
                out = []
                for item in jobs:
                    if isinstance(item, str):
                        out.append({"name": os.path.basename(os.path.abspath(item)), "path": os.path.abspath(item)})
                    elif isinstance(item, dict) and item.get("path"):
                        p = os.path.abspath(os.path.expanduser(item["path"]))
                        name = item.get("name") or os.path.basename(p)
                        out.append({"name": name, "path": p, "role": item.get("role", "")})
                if out:
                    return out
            except (OSError, ValueError):
                continue
    return []


def _git_commits(ws_path: str, since_expr: str, author: Optional[str] = None) -> List[Dict[str, str]]:
    cmd = ["git", "-C", ws_path, "log", f"--since={since_expr}", "--pretty=format:%h|%ad|%s", "--date=short"]
    if author:
        cmd.append(f"--author={author}")
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if res.returncode != 0 or not res.stdout.strip():
            return []
        commits = []
        for line in res.stdout.strip().splitlines():
            parts = line.split("|", 2)
            if len(parts) == 3:
                commits.append({"hash": parts[0], "date": parts[1], "subject": parts[2]})
        return commits
    except (OSError, subprocess.SubprocessError):
        return []


def _git_branch_and_dirty(ws_path: str) -> Dict[str, object]:
    branch = "none"
    dirty_count = 0
    try:
        b_res = subprocess.run(
            ["git", "-C", ws_path, "branch", "--show-current"],
            capture_output=True, text=True, timeout=5
        )
        if b_res.returncode == 0 and b_res.stdout.strip():
            branch = b_res.stdout.strip()
        s_res = subprocess.run(
            ["git", "-C", ws_path, "status", "--porcelain"],
            capture_output=True, text=True, timeout=5
        )
        if s_res.returncode == 0 and s_res.stdout.strip():
            dirty_count = len([ln for ln in s_res.stdout.splitlines() if ln.strip()])
    except (OSError, subprocess.SubprocessError):
        return {"branch": branch, "dirty_files": dirty_count}
    return {"branch": branch, "dirty_files": dirty_count}


def gather_job(ws_path: str, name: Optional[str] = None, since_expr: str = "24 hours ago", author: Optional[str] = None) -> Dict[str, object]:
    abs_path = os.path.abspath(ws_path)
    job_name = name or os.path.basename(abs_path)
    git_meta = _git_branch_and_dirty(abs_path)
    commits = _git_commits(abs_path, since_expr, author=author)

    checked_tasks: List[Dict[str, str]] = []
    unchecked_tasks: List[Dict[str, str]] = []

    for pat in TASK_PATTERNS:
        for fpath in sorted(glob.glob(os.path.join(abs_path, pat))):
            if not os.path.isfile(fpath):
                continue
            rel = os.path.relpath(fpath, abs_path).replace("\\", "/")
            try:
                with open(fpath, "r", encoding="utf-8") as fh:
                    for lineno, line in enumerate(fh, start=1):
                        m = CHECKBOX_RE.match(line.rstrip("\r\n"))
                        if not m:
                            continue
                        state = m.group(2)
                        text = m.group(4).strip()
                        entry = {"file": rel, "line": str(lineno), "text": text}
                        if state in ("x", "X"):
                            checked_tasks.append(entry)
                        else:
                            unchecked_tasks.append(entry)
            except OSError:
                continue

    csv_done: List[str] = []
    csv_pending_must: List[str] = []
    for csv_rel in ("docs/features.csv", "replica/features.csv"):
        csv_path = os.path.join(abs_path, csv_rel)
        if os.path.isfile(csv_path):
            try:
                with open(csv_path, "r", newline="", encoding="utf-8-sig") as fh:
                    for row in csv.DictReader(fh):
                        feat = (row.get("feature") or "").strip()
                        if not feat:
                            continue
                        clone = (row.get("clone") or "no").strip().lower()
                        prio = (row.get("priority") or "").strip().lower()
                        orig = (row.get("original") or "yes").strip().lower()
                        if clone in ("yes", "done"):
                            csv_done.append(feat)
                        elif orig not in ("no", "n", "false") and clone != "skip" and prio in ("must", "p0"):
                            csv_pending_must.append(feat)
            except OSError:
                continue

    brain_notes: List[str] = []
    brain_dir = os.path.join(abs_path, "docs", "brain")
    if os.path.isdir(brain_dir):
        for fn in sorted(os.listdir(brain_dir)):
            if fn.endswith(".md") and fn.lower() != "00-moc.md":
                brain_notes.append(os.path.splitext(fn)[0])

    return {
        "name": job_name,
        "path": abs_path,
        "branch": git_meta["branch"],
        "dirty_files": git_meta["dirty_files"],
        "commits": commits,
        "checked_tasks": checked_tasks,
        "unchecked_tasks": unchecked_tasks,
        "csv_done": csv_done,
        "csv_pending_must": csv_pending_must,
        "brain_notes": brain_notes,
    }


def gather_multi_job(
    workspaces: Optional[List[str]] = None,
    period: str = "daily",
    since: Optional[str] = None,
    author: Optional[str] = None,
    config_path: Optional[str] = None,
) -> Dict[str, object]:
    since_expr = since or ("7 days ago" if period == "weekly" else "24 hours ago")
    job_specs: List[Dict[str, str]] = []

    if workspaces:
        for w in workspaces:
            p = os.path.abspath(os.path.expanduser(w))
            job_specs.append({"name": os.path.basename(p), "path": p})
    else:
        job_specs = load_jobs_config(config_path)
        if not job_specs:
            p = os.path.abspath(".")
            job_specs.append({"name": os.path.basename(p), "path": p})

    jobs_data = [
        gather_job(spec["path"], name=spec.get("name"), since_expr=since_expr, author=author)
        for spec in job_specs
    ]

    return {
        "date": today_iso(),
        "period": period,
        "since": since_expr,
        "total_jobs": len(jobs_data),
        "jobs": jobs_data,
    }


def render_markdown(data: Dict[str, object]) -> str:
    period_title = str(data.get("period", "daily")).capitalize()
    date_str = str(data.get("date", today_iso()))
    jobs: List[Dict[str, object]] = data.get("jobs", [])  # type: ignore

    lines: List[str] = [
        f"# Multi-Job {period_title} Pulse Report ({date_str})",
        "",
        f"> **Window**: `{data.get('since')}` · **Active Jobs Scanned**: `{len(jobs)}` · **Confidence**: `[observed]`",
        "",
        "## 1. Executive Portfolio Overview",
        "",
        "| Job / Project | Branch | Commits | Tasks `[x]` | Pending `[ ]` | Must-Have CSV Left | Brain Notes | Working Tree |",
        "|---|---|---:|---:|---:|---:|---:|---|",
    ]

    for j in jobs:
        dirty = j["dirty_files"]
        wt_status = f"{dirty} modified" if dirty else "clean"
        lines.append(
            f"| **{j['name']}** | `{j['branch']}` | {len(j['commits'])} | "
            f"{len(j['checked_tasks'])} | {len(j['unchecked_tasks'])} | "
            f"{len(j['csv_pending_must'])} | {len(j['brain_notes'])} | {wt_status} |"
        )

    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 2. Isolated Per-Job Standups (Copy-Paste Ready)")
    lines.append("")

    for j in jobs:
        lines.append(f"## Job: `{j['name']}`")
        lines.append(f"- **Path**: `{j['path']}` (`{j['branch']}`)")
        lines.append("")
        lines.append("### Copy-Paste Standup / Status Block")
        lines.append("```markdown")
        lines.append(f"**[{j['name']}] {period_title} Progress Update ({date_str})**")
        lines.append("✅ **Completed (Observed Evidence)**:")
        if j["commits"] or j["checked_tasks"] or j["csv_done"]:
            for c in j["commits"][:10]:
                lines.append(f"  - Commit `{c['hash']}` ({c['date']}): {c['subject']}")
            for t in j["checked_tasks"][:10]:
                lines.append(f"  - [x] {t['text']} ({t['file']}:{t['line']})")
            for feat in j["csv_done"][:10]:
                lines.append(f"  - [Feature Done] {feat}")
        else:
            lines.append("  - No new commits or ticked checkboxes recorded in this window.")

        lines.append("🔜 **Next / In Progress**:")
        if j["unchecked_tasks"] or j["csv_pending_must"]:
            for t in j["unchecked_tasks"][:5]:
                lines.append(f"  - [ ] {t['text']} ({t['file']}:{t['line']})")
            for feat in j["csv_pending_must"][:5]:
                lines.append(f"  - [Must-Have Pending] {feat}")
        else:
            lines.append("  - All tracked checklist items and must-have features are complete.")

        lines.append("⚠️ **Risks / Uncommitted Work**:")
        if j["dirty_files"]:
            lines.append(f"  - {j['dirty_files']} uncommitted file(s) in working tree.")
        else:
            lines.append("  - None (working tree clean).")
        lines.append("```")

        if j["brain_notes"]:
            lines.append("")
            lines.append("**Distilled Second-Brain Notes**: " + ", ".join(f"`[[{n}]]`" for n in j["brain_notes"]))
        lines.append("")

    return "\n".join(lines)


def write_to_vault(vault_dir: str, data: Dict[str, object], md_body: str) -> str:
    os.makedirs(vault_dir, exist_ok=True)
    period = str(data.get("period", "daily")).lower()
    date_str = str(data.get("date", today_iso()))
    note_id = f"pulse-{period}-{date_str}"
    note_path = os.path.join(vault_dir, f"{note_id}.md")

    frontmatter = (
        "---\n"
        f"id: {note_id}\n"
        f"title: \"Multi-Job {period.capitalize()} Pulse ({date_str})\"\n"
        "type: pattern\n"
        "domain: operations\n"
        "confidence: observed\n"
        "verified_by: \"pulse_report.py\"\n"
        f"created: {date_str}\n"
        f"updated: {date_str}\n"
        "tags:\n"
        "  - agent-team\n"
        "  - pulse-report\n"
        f"  - {period}\n"
        "---\n\n"
    )
    with open(note_path, "w", encoding="utf-8") as fh:
        fh.write(frontmatter + md_body + "\n\n## Graph Links\n\n- [[00-MOC]]\n")
    return note_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Multi-Job Daily & Weekly Pulse Report Generator")
    parser.add_argument("--workspace", "-w", action="append", default=[], help="Workspace path to include (repeatable)")
    parser.add_argument("--config", help="Path to .agent-team-jobs.json registry")
    parser.add_argument("--period", choices=["daily", "weekly"], default="daily", help="Reporting window")
    parser.add_argument("--since", help="Custom git log --since expression (overrides --period)")
    parser.add_argument("--author", help="Filter git commits by author")
    parser.add_argument("--vault", help="Optional Obsidian vault or docs/brain directory to archive the report")
    parser.add_argument("--out", help="Optional file path to write the Markdown report")
    parser.add_argument("--json", action="store_true", help="Output structured JSON instead of Markdown")
    args = parser.parse_args()

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    data = gather_multi_job(
        workspaces=args.workspace or None,
        period=args.period,
        since=args.since,
        author=args.author,
        config_path=args.config,
    )

    if args.json:
        output = json.dumps(data, indent=2)
    else:
        output = render_markdown(data)

    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(output)

    if args.vault:
        md_text = output if not args.json else render_markdown(data)
        write_to_vault(args.vault, data, md_text)

    print(output)


if __name__ == "__main__":
    main()
