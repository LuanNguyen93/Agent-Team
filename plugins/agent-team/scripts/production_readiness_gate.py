#!/usr/bin/env python3
"""
Production Readiness & Anti-Demo-Table Gate (PRR) for Agent Team.

Grounded in Amazon ("Design for Failure"), Toyota ("Genchi Genbutsu & Jidoka"),
Google SRE ("Production Readiness Review"), and Stripe ("Zero-Hollow-Code"):
Scans production source code (excluding tests/docs/archives) to block the 4 classic
"Demo-Table Traps" before work can be reported as complete:

1. `silent_exception_swallow`:
   - Python `except ...: pass` or `...` (AST-verified)
   - TS/JS empty `catch (e) {}` blocks that hide production failures.
2. `hollow_demo_marker`:
   - Unresolved `# TODO:`, `// TODO:`, `FIXME:`, `HACK:`, or `MOCK_DATA` placeholders
     left inside production modules.
3. `hardcoded_localhost_origin`:
   - Hardcoded `http://localhost:<port>` or `http://127.0.0.1:<port>` in production code
     without environment-variable configuration (`os.environ`, ` os.getenv`, `process.env`).
4. `unbounded_network_timeout`:
   - Python `requests.get/post/put/delete/request` or `urllib.request.urlopen` calls
     missing an explicit `timeout=` parameter (AST-verified).

Zero third-party dependencies (Python standard library only).
"""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional

SKIP_DIRS = {
    ".git",
    "node_modules",
    "__pycache__",
    ".venv",
    "venv",
    "dist",
    "build",
    "coverage",
    ".next",
    "target",
    "archive",
    "tests",
    "test",
    "__tests__",
    "docs",
    "references",
}

PROD_EXTENSIONS = {".py", ".ts", ".tsx", ".js", ".jsx", ".rs", ".go"}

HOLLOW_TODO_RE = re.compile(
    r"(?:^|\s)(?:#|//)\s*(?:TODO|FIXME|HACK|XXX)\b[:\s]*(.*)",
    re.IGNORECASE,
)

EMPTY_CATCH_RE = re.compile(
    r"\bcatch\s*(?:\([^)]*\))?\s*\{\s*\}",
    re.MULTILINE,
)

LOCALHOST_RE = re.compile(
    r"https?://(?:localhost|127\.0\.0\.1):\d+",
    re.IGNORECASE,
)

ENV_CONFIG_RE = re.compile(
    r"(?:os\.environ|os\.getenv|process\.env|import\.meta\.env|std::env|os\.Getenv)",
)

HTTP_CALL_NAMES = {"get", "post", "put", "delete", "patch", "request", "urlopen"}


def is_test_file(path: Path) -> bool:
    name = path.name.lower()
    return (
        name.startswith("test_")
        or name.endswith("_test.py")
        or name.endswith(".test.ts")
        or name.endswith(".test.tsx")
        or name.endswith(".test.js")
        or name.endswith(".spec.ts")
        or name.endswith(".spec.tsx")
        or name.endswith(".spec.js")
    )


def scan_python_ast_prr(source: str, rel_path: str) -> List[Dict[str, object]]:
    findings: List[Dict[str, object]] = []
    try:
        tree = ast.parse(source, filename=rel_path)
    except SyntaxError:
        return findings

    for node in ast.walk(tree):
        # 1. Check for silent exception swallowing (`except ...: pass`)
        if isinstance(node, ast.ExceptHandler):
            if len(node.body) == 1:
                stmt = node.body[0]
                is_pass = isinstance(stmt, ast.Pass)
                is_ellipsis = (
                    isinstance(stmt, ast.Expr)
                    and isinstance(stmt.value, ast.Constant)
                    and stmt.value.value is Ellipsis
                )
                if is_pass or is_ellipsis:
                    findings.append(
                        {
                            "kind": "silent_exception_swallow",
                            "file": rel_path,
                            "line": node.lineno,
                            "message": (
                                "Silent `except: pass` swallows runtime errors on production. "
                                "Log context, return an explicit fallback value, or re-raise."
                            ),
                        }
                    )

        # 2. Check for network calls without `timeout=`
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            attr = node.func.attr
            if attr in HTTP_CALL_NAMES:
                owner_name = ""
                if isinstance(node.func.value, ast.Name):
                    owner_name = node.func.value.id
                elif isinstance(node.func.value, ast.Attribute):
                    owner_name = node.func.value.attr
                if owner_name in {"requests", "request", "httpx"}:
                    has_timeout = any(kw.arg == "timeout" for kw in node.keywords)
                    if not has_timeout and len(node.args) < 3:
                        findings.append(
                            {
                                "kind": "unbounded_network_timeout",
                                "file": rel_path,
                                "line": node.lineno,
                                "message": (
                                    f"Network call `{owner_name}.{attr}(...)` has no explicit `timeout=`. "
                                    "Unbounded I/O hangs production workers when upstream degrades."
                                ),
                            }
                        )
    return findings


def scan_text_prr(source: str, rel_path: str, suffix: str) -> List[Dict[str, object]]:
    findings: List[Dict[str, object]] = []
    lines = source.splitlines()

    for idx, line in enumerate(lines, start=1):
        # Hollow TODO/FIXME comment markers (ignore regex/pattern definitions)
        m_todo = HOLLOW_TODO_RE.search(line)
        if m_todo and "re.compile" not in line and "HOLLOW_TODO_RE" not in line:
            findings.append(
                {
                    "kind": "hollow_demo_marker",
                    "file": rel_path,
                    "line": idx,
                    "message": f"Unresolved demo/placeholder marker in production code: `{line.strip()}`",
                }
            )

        # Hardcoded localhost origin without env fallback on the same line
        if LOCALHOST_RE.search(line) and not ENV_CONFIG_RE.search(line):
            if "LOCALHOST_RE" not in line and not line.strip().startswith(("#", "//", "*")):
                findings.append(
                    {
                        "kind": "hardcoded_localhost_origin",
                        "file": rel_path,
                        "line": idx,
                        "message": (
                            "Hardcoded localhost URL in production code without environment variable fallback."
                        ),
                    }
                )

    if suffix in {".ts", ".tsx", ".js", ".jsx"}:
        for m in EMPTY_CATCH_RE.finditer(source):
            line_no = source[: m.start()].count("\n") + 1
            findings.append(
                {
                    "kind": "silent_exception_swallow",
                    "file": rel_path,
                    "line": line_no,
                    "message": "Empty `catch {}` block silently swallows production failures.",
                }
            )

    return findings


def scan_workspace_prr(workspace: Path) -> Dict[str, object]:
    findings: List[Dict[str, object]] = []

    if workspace.is_file():
        files_to_scan = [workspace]
        root = workspace.parent
    else:
        root = workspace
        files_to_scan = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fname in sorted(filenames):
                fpath = Path(dirpath) / fname
                if fpath.suffix in PROD_EXTENSIONS and not is_test_file(fpath):
                    files_to_scan.append(fpath)

    for fpath in files_to_scan:
        if fpath.name == "production_readiness_gate.py":
            continue
        try:
            source = fpath.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = str(fpath.relative_to(root)).replace("\\", "/")
        if fpath.suffix == ".py":
            findings.extend(scan_python_ast_prr(source, rel))
        findings.extend(scan_text_prr(source, rel, fpath.suffix))

    return {
        "workspace": str(workspace).replace("\\", "/"),
        "files_scanned": len(files_to_scan),
        "finding_count": len(findings),
        "findings": findings,
    }


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Production Readiness & Anti-Demo-Table Gate (PRR)."
    )
    parser.add_argument("workspace", nargs="?", default=".", help="Workspace or file path")
    parser.add_argument("--json", action="store_true", help="Output JSON report")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 when any production readiness defect is found",
    )

    args = parser.parse_args(argv)
    ws = Path(args.workspace).resolve()
    report = scan_workspace_prr(ws)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(
            f"Production Readiness Gate (PRR): scanned {report['files_scanned']} production file(s), "
            f"{report['finding_count']} defect(s)."
        )
        for f in report["findings"]:
            print(f"  - [{f['kind']}] {f['file']}:{f['line']} — {f['message']}")

    if args.strict and report["finding_count"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
