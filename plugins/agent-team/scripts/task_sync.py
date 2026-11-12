#!/usr/bin/env python3
"""
Deterministic Task & Checklist State Synchronizer for Agent Team.

Solves the "Stale Task List / Unticked Checkboxes" failure mode across
all harnesses (Claude Code, Antigravity, Codex):
1. Audits active task lists (`docs/tasks.md`, `docs/plan.md`, `docs/brief.md`,
   `docs/prd.md`, `docs/stories/*.md`, `TODO.md`) and `docs/features.csv`
   for unchecked `- [ ]` items or unfinished `must` rows.
2. Atomically ticks `- [ ]` -> `- [x]` with `[observed: <evidence>]` without
   requiring full-file LLM rewrites.
3. Updates `docs/features.csv` (`clone` column -> `yes` / `partial`) with
   evidence notes.

Standard library only.
"""

import argparse
import csv
import glob
import json
import os
import re
import sys
from typing import Dict, List, Optional

CHECKBOX_RE = re.compile(r"^(\s*[-*]\s+\[)([ xX])(\]\s+)(.+)$")

DEFAULT_TASK_GLOBS = (
    "docs/tasks.md",
    "docs/plan.md",
    "docs/brief.md",
    "docs/prd.md",
    "docs/stories/*.md",
    "TODO.md",
    "TASKS.md",
)


def discover_task_files(workspace: str, explicit_files: Optional[List[str]] = None) -> List[str]:
    if explicit_files:
        return [f for f in explicit_files if os.path.isfile(f)]
    found: List[str] = []
    for pattern in DEFAULT_TASK_GLOBS:
        full_pattern = os.path.join(workspace, pattern)
        for path in sorted(glob.glob(full_pattern)):
            if os.path.isfile(path) and path not in found:
                found.append(path)
    return found


def audit_markdown_file(path: str, rel_root: str) -> Dict[str, object]:
    checked = 0
    unchecked = 0
    unchecked_items: List[Dict[str, object]] = []
    rel_path = os.path.relpath(path, rel_root).replace("\\", "/")

    with open(path, "r", encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, start=1):
            m = CHECKBOX_RE.match(line.rstrip("\r\n"))
            if not m:
                continue
            state = m.group(2)
            text = m.group(4).strip()
            if state in ("x", "X"):
                checked += 1
            else:
                unchecked += 1
                unchecked_items.append({
                    "file": rel_path,
                    "line": lineno,
                    "text": text,
                })
    return {
        "file": rel_path,
        "checked": checked,
        "unchecked": unchecked,
        "unchecked_items": unchecked_items,
    }


def audit_workspace(workspace: str, explicit_files: Optional[List[str]] = None) -> Dict[str, object]:
    files = discover_task_files(workspace, explicit_files)
    total_checked = 0
    total_unchecked = 0
    all_unchecked: List[Dict[str, object]] = []
    per_file: List[Dict[str, object]] = []

    for f in files:
        res = audit_markdown_file(f, workspace)
        total_checked += int(res["checked"])
        total_unchecked += int(res["unchecked"])
        all_unchecked.extend(res["unchecked_items"])
        per_file.append(res)

    csv_must_remaining = 0
    csv_unchecked_rows: List[Dict[str, str]] = []
    for csv_rel in ("docs/features.csv", "replica/features.csv"):
        csv_path = os.path.join(workspace, csv_rel)
        if os.path.isfile(csv_path):
            with open(csv_path, newline="", encoding="utf-8-sig") as fh:
                reader = csv.DictReader(fh)
                for row in reader:
                    prio = (row.get("priority") or "").strip().lower()
                    orig = (row.get("original") or "yes").strip().lower()
                    clone = (row.get("clone") or "no").strip().lower()
                    feat = (row.get("feature") or "").strip()
                    if not feat or orig in ("no", "n", "false") or clone == "skip":
                        continue
                    if prio in ("must", "p0") and clone not in ("yes", "done"):
                        csv_must_remaining += 1
                        csv_unchecked_rows.append({"file": csv_rel, "feature": feat, "clone": clone})

    total = total_checked + total_unchecked
    return {
        "workspace": workspace,
        "total_checkboxes": total,
        "checked_checkboxes": total_checked,
        "unchecked_checkboxes": total_unchecked,
        "unchecked_items": all_unchecked,
        "csv_must_Remaining": csv_must_remaining,
        "csv_unchecked_rows": csv_unchecked_rows,
        "files": per_file,
    }


def tick_item(file_path: str, match_text: str, evidence: str = "") -> bool:
    """Atomically tick a matching `- [ ]` line to `- [x]` and append `[observed: evidence]`."""
    if not os.path.isfile(file_path):
        return False

    needle = match_text.strip().lower()
    if not needle:
        return False

    with open(file_path, "r", encoding="utf-8") as fh:
        lines = fh.readlines()

    changed = False
    new_lines: List[str] = []
    for line in lines:
        stripped = line.rstrip("\r\n")
        ending = line[len(stripped):] or "\n"
        m = CHECKBOX_RE.match(stripped)
        if m and m.group(2) == " " and needle in m.group(4).lower():
            prefix, _, bracket_space, item_text = m.groups()
            ev_suffix = f" (`[observed: {evidence.strip()}]`)" if evidence and evidence.strip() else ""
            if ev_suffix and "[observed:" in item_text:
                ev_suffix = ""
            new_lines.append(f"{prefix}x{bracket_space}{item_text}{ev_suffix}{ending}")
            changed = True
        else:
            new_lines.append(line)

    if changed:
        with open(file_path, "w", encoding="utf-8") as fh:
            fh.writelines(new_lines)
    return changed


def tick_csv_feature(
    csv_path: str,
    feature_match: str,
    status: str = "yes",
    evidence: str = "",
) -> bool:
    """Atomically update a row's `clone` status in docs/features.csv."""
    if not os.path.isfile(csv_path):
        return False

    needle = feature_match.strip().lower()
    if not needle:
        return False

    with open(csv_path, "r", newline="", encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        fieldnames = reader.fieldnames
        if not fieldnames:
            return False
        rows = list(reader)

    changed = False
    for row in rows:
        feat = (row.get("feature") or "").strip()
        if needle in feat.lower():
            row["clone"] = status
            if evidence and "notes" in row:
                old_note = (row.get("notes") or "").strip()
                tag = f"[observed: {evidence.strip()}]"
                if tag not in old_note:
                    row["notes"] = f"{old_note} {tag}".strip()
            changed = True

    if changed:
        with open(csv_path, "w", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)
    return changed


def main() -> None:
    parser = argparse.ArgumentParser(description="Deterministic Task & Checklist State Synchronizer")
    parser.add_argument("workspace", nargs="?", default=".", help="Workspace root directory")
    parser.add_argument("--file", action="append", default=[], help="Specific markdown file(s) to target")
    parser.add_argument("--tick", help="Substring of markdown checkbox item to mark [x]")
    parser.add_argument("--tick-csv", help="Substring of feature in docs/features.csv to mark done")
    parser.add_argument("--status", default="yes", choices=["yes", "partial", "no", "skip"], help="CSV status")
    parser.add_argument("--evidence", default="", help="Verification command or test that proved completion")
    parser.add_argument("--require-all-checked", action="store_true", help="Exit 1 if any checkbox or must-have CSV row is unchecked")
    parser.add_argument("--json", action="store_true", help="Output audit report as JSON")
    args = parser.parse_args()

    ws = os.path.abspath(args.workspace)

    if args.tick:
        targets = args.file if args.file else discover_task_files(ws)
        any_updated = False
        for t in targets:
            if tick_item(t, args.tick, evidence=args.evidence):
                any_updated = True
                print(f"Ticked [x] '{args.tick}' in {t}")
        if not any_updated:
            sys.stderr.write(f"task_sync: no unchecked item matching '{args.tick}' found.\n")
            sys.exit(1)
        sys.exit(0)

    if args.tick_csv:
        csv_targets = args.file if args.file else [
            os.path.join(ws, "docs", "features.csv"),
            os.path.join(ws, "replica", "features.csv"),
        ]
        any_csv = False
        for c in csv_targets:
            if tick_csv_feature(c, args.tick_csv, status=args.status, evidence=args.evidence):
                any_csv = True
                print(f"Updated CSV feature '{args.tick_csv}' -> {args.status} in {c}")
        if not any_csv:
            sys.stderr.write(f"task_sync: no CSV feature matching '{args.tick_csv}' found.\n")
            sys.exit(1)
        sys.exit(0)

    report = audit_workspace(ws, args.file or None)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(
            f"Task Sync Audit: {report['checked_checkboxes']}/{report['total_checkboxes']} checkboxes [x] "
            f"({report['unchecked_checkboxes']} remaining), "
            f"{report['csv_must_Remaining']} CSV must-have(s) remaining."
        )
        for item in report["unchecked_items"][:20]:
            print(f"  - [ ] {item['file']}:{item['line']} — {item['text']}")
        for row in report["csv_unchecked_rows"][:10]:
            print(f"  - [CSV must] {row['file']} — {row['feature']} (clone={row['clone']})")

    if args.require_all_checked and (report["unchecked_checkboxes"] > 0 or report["csv_must_Remaining"] > 0):
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
