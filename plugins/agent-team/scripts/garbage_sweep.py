#!/usr/bin/env python3
"""
Docs & Code Garbage Sweep and SSOT Lifecycle Manager for Agent Team.

Enforces Big-Tech (Stripe / Linear / Uber) engineering hygiene across two axes:

1. Documentation Single Source of Truth (SSOT):
   - Exactly ONE active canonical artifact per stage at `docs/` root:
     `brief.md`, `prd.md`, `architecture.md`, `ui-spec.md`, `design-system.md`, `plan.md`, `tasks.md`.
   - Any phase-specific or superseded variant (`brief-*.md`, `prd-*.md`,
     `architecture-*.md`, `ui-spec-*.md`, `plan-*.md`) is flagged as a
     competing variant and can be automatically stamped `Status: Superseded`
     and moved into `docs/archive/` (`--archive-stale-docs`).

2. Code Zero-Garbage & Anti-Patch-on-Patch Gate:
   - Python AST analysis for unused imports and backup/legacy symbol suffixes
     (`_old`, `_v2`, `_backup`, `_temp`, `_deprecated`, `_copy`).
   - Cross-language detection (`.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.rs`, `.go`)
     for backup function/class names and multi-line commented-out code blocks
     left behind during iterative bug fixing.

Standard library only.
"""

import argparse
import ast
import datetime
import json
import os
import re
import sys
from typing import Dict, List

CANONICAL_PREFIXES = (
    ("brief-", "brief.md"),
    ("prd-", "prd.md"),
    ("architecture-", "architecture.md"),
    ("ui-spec-", "ui-spec.md"),
    ("design-system-", "design-system.md"),
    ("plan-", "plan.md"),
    ("tasks-", "tasks.md"),
)

BACKUP_SYMBOL_RE = re.compile(
    r"\b(?:def|class|function|const|let|fn)\s+([A-Za-z0-9_]+(?:_old|_v2|_backup|_temp|_deprecated|_copy|_legacy|_new))\b"
)

CODE_COMMENT_LINE_RE = re.compile(
    r"^\s*(?:#|//)\s*(?:def\s+\w+|class\s+\w+|function\s+\w+|if\s+.+[:{]|for\s+.+[:{]|return\s+.+|const\s+\w+\s*=|let\s+\w+\s*=)"
)

IGNORE_DIRS = {
    ".git", "node_modules", "target", "dist", "build", "__pycache__",
    ".venv", "venv", "vendor", "archive",
}

CODE_EXTS = (".py", ".ts", ".tsx", ".js", ".jsx", ".rs", ".go")


def today_iso() -> str:
    return datetime.date.today().isoformat()


def scan_docs(workspace: str) -> Dict[str, object]:
    docs_dir = os.path.join(workspace, "docs")
    competing: List[Dict[str, str]] = []
    if not os.path.isdir(docs_dir):
        return {"docs_dir": docs_dir, "competing_variants": competing}

    for fn in sorted(os.listdir(docs_dir)):
        full = os.path.join(docs_dir, fn)
        if not os.path.isfile(full) or not fn.lower().endswith(".md"):
            continue
        low = fn.lower()
        for prefix, canonical in CANONICAL_PREFIXES:
            if low.startswith(prefix) and low != canonical:
                competing.append({
                    "file": f"docs/{fn}",
                    "canonical": f"docs/{canonical}",
                    "reason": f"Competing phase/draft variant of canonical SSOT docs/{canonical}",
                })
                break

    return {"docs_dir": docs_dir, "competing_variants": competing}


def archive_competing_docs(workspace: str) -> List[Dict[str, str]]:
    """Stamp competing doc variants as Superseded and move them to docs/archive/."""
    doc_report = scan_docs(workspace)
    variants: List[Dict[str, str]] = doc_report["competing_variants"]  # type: ignore
    if not variants:
        return []

    archive_dir = os.path.join(workspace, "docs", "archive")
    os.makedirs(archive_dir, exist_ok=True)
    moved: List[Dict[str, str]] = []
    today = today_iso()

    for item in variants:
        src_path = os.path.join(workspace, item["file"])
        fn = os.path.basename(src_path)
        dst_path = os.path.join(archive_dir, fn)
        try:
            with open(src_path, "r", encoding="utf-8") as fh:
                content = fh.read()
        except OSError:
            continue

        banner = (
            f"> **Status**: Superseded by `{item['canonical']}` on {today} "
            f"(archived for historical reference only — do not use as active spec).\n\n"
        )
        if "Status: Superseded" not in content and "**Status**: Superseded" not in content:
            content = f"<!-- Status: Superseded by {item['canonical']} ({today}) -->\n" + banner + content

        with open(dst_path, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.remove(src_path)
        moved.append({"from": item["file"], "to": f"docs/archive/{fn}", "superseded_by": item["canonical"]})

    return moved


def _scan_python_ast(file_path: str, rel_path: str, source: str) -> List[Dict[str, object]]:
    findings: List[Dict[str, object]] = []
    try:
        tree = ast.parse(source, filename=file_path)
    except SyntaxError:
        return findings

    imported_names: Dict[str, int] = {}
    used_names = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                bound = alias.asname or alias.name.split(".")[0]
                imported_names[bound] = node.lineno
        elif isinstance(node, ast.ImportFrom):
            if node.module == "__future__":
                continue
            for alias in node.names:
                if alias.name == "*":
                    continue
                bound = alias.asname or alias.name
                imported_names[bound] = node.lineno
        elif isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
            used_names.add(node.id)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            if re.search(r"(?:_old|_v2|_backup|_temp|_deprecated|_copy|_legacy)$", node.name):
                findings.append({
                    "file": rel_path,
                    "line": node.lineno,
                    "kind": "backup_symbol_suffix",
                    "detail": f"Symbol '{node.name}' carries a patch/backup suffix; delete dead version instead of keeping two copies",
                })

    # Also check type annotations or string references for imported names
    for name, lineno in imported_names.items():
        if name not in used_names and not re.search(rf"\b{re.escape(name)}\b", source.split("\n", lineno)[-1]):
            findings.append({
                "file": rel_path,
                "line": lineno,
                "kind": "unused_import",
                "detail": f"Unused import '{name}'",
            })

    return findings


def scan_code(workspace: str) -> Dict[str, object]:
    findings: List[Dict[str, object]] = []

    for root, dirs, files in os.walk(workspace):
        dirs[:] = [d for d in sorted(dirs) if d not in IGNORE_DIRS]
        for fn in sorted(files):
            if not fn.endswith(CODE_EXTS):
                continue
            # Skip test files when checking for intentional fixtures
            if fn.startswith("test_") or fn.endswith(".test.ts") or fn.endswith(".spec.ts"):
                continue
            full_path = os.path.join(root, fn)
            rel_path = os.path.relpath(full_path, workspace).replace("\\", "/")
            try:
                with open(full_path, "r", encoding="utf-8") as fh:
                    source = fh.read()
            except OSError:
                continue

            if fn.endswith(".py"):
                findings.extend(_scan_python_ast(full_path, rel_path, source))
            else:
                for lineno, line in enumerate(source.splitlines(), start=1):
                    m = BACKUP_SYMBOL_RE.search(line)
                    if m:
                        findings.append({
                            "file": rel_path,
                            "line": lineno,
                            "kind": "backup_symbol_suffix",
                            "detail": f"Symbol '{m.group(1)}' carries a patch/backup suffix",
                        })

            # Detect multi-line commented-out code blocks (>= 3 consecutive code-shaped comment lines)
            consec = 0
            start_line = 0
            for lineno, line in enumerate(source.splitlines(), start=1):
                if CODE_COMMENT_LINE_RE.match(line):
                    if consec == 0:
                        start_line = lineno
                    consec += 1
                else:
                    if consec >= 2:
                        findings.append({
                            "file": rel_path,
                            "line": start_line,
                            "kind": "commented_out_code",
                            "detail": f"Commented-out code block ({consec} code lines starting at line {start_line}); delete dead code cleanly",
                        })
                    consec = 0
            if consec >= 2:
                findings.append({
                    "file": rel_path,
                    "line": start_line,
                    "kind": "commented_out_code",
                    "detail": f"Commented-out code block ({consec} code lines starting at line {start_line}); delete dead code cleanly",
                })

    return {"workspace": workspace, "findings": findings}


def main() -> None:
    parser = argparse.ArgumentParser(description="Docs SSOT & Code Zero-Garbage Sweep")
    parser.add_argument("workspace", nargs="?", default=".", help="Workspace root directory")
    parser.add_argument("--archive-stale-docs", action="store_true", help="Move competing doc variants to docs/archive/ with Status: Superseded")
    parser.add_argument("--strict", action="store_true", help="Exit 1 if any competing doc variant or code garbage finding remains")
    parser.add_argument("--json", action="store_true", help="Output JSON report")
    args = parser.parse_args()

    ws = os.path.abspath(args.workspace)
    archived = []
    if args.archive_stale_docs:
        archived = archive_competing_docs(ws)

    doc_report = scan_docs(ws)
    code_report = scan_code(ws)

    result = {
        "workspace": ws,
        "archived_docs": archived,
        "competing_doc_variants": doc_report["competing_variants"],
        "code_garbage_findings": code_report["findings"],
    }

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if archived:
            print(f"Archived {len(archived)} superseded doc variant(s) to docs/archive/:")
            for a in archived:
                print(f"  - {a['from']} -> {a['to']} (Superseded by {a['superseded_by']})")
        variants = doc_report["competing_variants"]
        findings = code_report["findings"]
        print(
            f"Garbage Sweep: {len(variants)} competing doc variant(s), "
            f"{len(findings)} code garbage finding(s)."
        )
        for v in variants:
            print(f"  [DOC-SPRAWL] {v['file']} competes with {v['canonical']}")
        for f in findings:
            print(f"  [CODE-GARBAGE] {f['file']}:{f['line']} ({f['kind']}) — {f['detail']}")

    has_issues = bool(doc_report["competing_variants"] or code_report["findings"])
    if args.strict and has_issues:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
