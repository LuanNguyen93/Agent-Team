#!/usr/bin/env python3
"""
Database Architecture & Data Engineering Mechanical Gate for Agent Team.

Enforces the Industrial Database Architecture Laws across `.sql`, `.prisma`,
and production source files (`.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.go`, `.rs`):

1. `float_money_column`:
   - Monetary columns (`amount`, `price`, `balance`, `cost`, `total`, `fee`,
     `payout`, `revenue`, `salary`, `tax`, `subtotal`) declared with IEEE-754
     floating-point types across SQL (`FLOAT`, `REAL`, `DOUBLE PRECISION`),
     Prisma (`Float`), Drizzle/TypeORM (`real`, `doublePrecision`, `float`),
     SQLAlchemy/Django (`Float`, `FloatField`), and Go/GORM (`float32`, `float64`).
2. `naive_timestamp`:
   - SQL `TIMESTAMP WITHOUT TIME ZONE`, `DATETIME`, or bare `TIMESTAMP` without
     `WITH TIME ZONE` / `TIMESTAMPTZ`.
3. `unbounded_select_star`:
   - `SELECT * FROM <table_name>` in SQL or application queries (unless
     `-- allow-select-star` is present on the line).
4. `offset_pagination_hazard`:
   - `OFFSET <number or param>` pagination instead of Keyset/Seek cursor
     pagination (unless `-- allow-offset` is present on the line).
5. `soft_delete_unique_hazard`:
   - SQL `CREATE TABLE` combining `deleted_at` with an inline or table-level
     `UNIQUE` constraint instead of a partial unique index
     (`CREATE UNIQUE INDEX ... WHERE deleted_at IS NULL`).
6. `non_concurrent_index_or_lock_hazard`:
   - In migration files (when `--strict` or `strict_migrations=True`), bare
     `CREATE [UNIQUE] INDEX` without `CONCURRENTLY` or `ALTER TABLE ... DROP COLUMN`
     without `-- expand-contract`.
7. `query_in_loop_hazard`:
   - Executing DB/ORM queries inside `for` / `while` loops (`N+1` waterfall hazard)
     unless annotated with `allow-query-in-loop`.

Zero third-party dependencies (Python 3 standard library only).
"""

from __future__ import annotations

import argparse
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
    "evals",
}

DB_EXTENSIONS = {".sql", ".prisma", ".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs"}

MONEY_NAMES = (
    r"(?:amount|price|balance|cost|total|subtotal|fee|payout|revenue|salary|tax|"
    r"credit|debit|charge|refund)"
)

SQL_FLOAT_MONEY_RE = re.compile(
    rf"\b\w*{MONEY_NAMES}\w*\s+(?:FLOAT\d*|REAL|DOUBLE\s+PRECISION)\b",
    re.IGNORECASE,
)

PRISMA_FLOAT_MONEY_RE = re.compile(
    rf"^\s*\w*{MONEY_NAMES}\w*\s+Float\b",
    re.IGNORECASE,
)

ORM_PY_FLOAT_MONEY_RE = re.compile(
    rf"\b\w*{MONEY_NAMES}\w*\s*=\s*(?:Column|mapped_column|models\.FloatField)\s*\([^)]*\b(?:Float|FloatField)\b"
    rf"|\b\w*{MONEY_NAMES}\w*\s*:\s*Mapped\[float\]",
    re.IGNORECASE,
)

ORM_TS_FLOAT_MONEY_RE = re.compile(
    rf"\b\w*{MONEY_NAMES}\w*\s*:\s*(?:real|doublePrecision|float)\s*\(",
    re.IGNORECASE,
)

TYPEORM_FLOAT_DECORATOR_RE = re.compile(
    r"@Column\s*\(\s*\{[^}]*\btype\s*:\s*['\"](?:float|double|real|double precision)['\"]",
    re.IGNORECASE,
)

MONEY_IDENT_RE = re.compile(rf"\b\w*{MONEY_NAMES}\w*\b", re.IGNORECASE)

ORM_GO_FLOAT_MONEY_RE = re.compile(
    rf"^\s*\w*{MONEY_NAMES}\w*\s+(?:\*)?float(?:32|64)\b",
    re.IGNORECASE,
)

ORM_QUERY_CALL_RE = re.compile(
    r"(?:\bawait\s+(?:db|prisma|tx|client|conn|repo)\s*\."
    r"|\b(?:session|db|conn|cursor)\.(?:execute|query|scalar|scalars|get)\s*\("
    r"|\.\s*objects\.(?:filter|get|all|create|update)\s*\("
    r"|\bdb\.(?:Where|First|Find|Exec|Raw)\s*\()",
)

PY_LOOP_HEADER_RE = re.compile(r"^(\s*)(?:async\s+)?(?:for|while)\s+.+:\s*(?:#.*)?$")
BRACE_LOOP_HEADER_RE = re.compile(
    r"^\s*(?:for\s*\(|while\s*\(|for\s+await\s*\(|for\s+[a-zA-Z0-9_,\s:=]+\s+range\s+)"
)

NAIVE_TIMESTAMP_RE = re.compile(
    r"\b(?:TIMESTAMP\s+WITHOUT\s+TIME\s+ZONE|DATETIME)\b"
    r"|\bTIMESTAMP\b(?!\s+WITH\s+TIME\s+ZONE|\s*\(\d+\)\s+WITH\s+TIME\s+ZONE)",
    re.IGNORECASE,
)

SELECT_STAR_RE = re.compile(
    r"\bSELECT\s+\*\s+FROM\s+[a-zA-Z_][a-zA-Z0-9_.]*",
    re.IGNORECASE,
)

OFFSET_PAGINATION_RE = re.compile(
    r"\bLIMIT\s+(?:\d+|\$\d+|\?|:[\w]+)\s+OFFSET\s+(?:\d+|\$\d+|\?|:[\w]+)\b"
    r"|\bOFFSET\s+(?:[1-9]\d*|\$\d+|\?|:[\w]+)\b",
    re.IGNORECASE,
)

CREATE_TABLE_BLOCK_RE = re.compile(
    r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_.]+)\s*\((.*?)\)\s*;",
    re.IGNORECASE | re.DOTALL,
)

NON_CONCURRENT_INDEX_RE = re.compile(
    r"^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?!CONCURRENTLY\b)",
    re.IGNORECASE,
)

DROP_COLUMN_RE = re.compile(
    r"\bALTER\s+TABLE\s+\S+\s+DROP\s+COLUMN\b",
    re.IGNORECASE,
)


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


def is_migration_file(rel_path: str) -> bool:
    parts = [p.lower() for p in Path(rel_path).parts]
    return "migrations" in parts or "migration" in parts


def _scan_sql_schema_line(
    line: str, rel_path: str, line_no: int, is_mig: bool, strict_migrations: bool
) -> List[Dict[str, object]]:
    findings: List[Dict[str, object]] = []
    stripped = line.strip()
    if stripped.startswith("--") or stripped.startswith("/*") or stripped.startswith("*"):
        return findings

    if SQL_FLOAT_MONEY_RE.search(line):
        findings.append(
            {
                "kind": "float_money_column",
                "file": rel_path,
                "line": line_no,
                "message": (
                    "Monetary column uses floating-point type (`FLOAT`/`REAL`/`DOUBLE PRECISION`). "
                    "Use integer minor units (`BIGINT` cents) or `NUMERIC(19, 4)`."
                ),
            }
        )

    # Ignore SQL function expressions like CURRENT_TIMESTAMP or CLOCK_TIMESTAMP
    cleaned_ts = re.sub(r"\b(?:CURRENT_TIMESTAMP|CLOCK_TIMESTAMP|STATEMENT_TIMESTAMP|TRANSACTION_TIMESTAMP)\b", "", line, flags=re.IGNORECASE)
    if NAIVE_TIMESTAMP_RE.search(cleaned_ts):
        findings.append(
            {
                "kind": "naive_timestamp",
                "file": rel_path,
                "line": line_no,
                "message": (
                    "Naive `TIMESTAMP` / `DATETIME` without time zone detected. "
                    "Use `TIMESTAMPTZ` (`TIMESTAMP WITH TIME ZONE` in UTC)."
                ),
            }
        )

    if strict_migrations and is_mig:
        if NON_CONCURRENT_INDEX_RE.search(line) and "-- allow-non-concurrent" not in line:
            findings.append(
                {
                    "kind": "non_concurrent_index_or_lock_hazard",
                    "file": rel_path,
                    "line": line_no,
                    "message": (
                        "Migration runs `CREATE INDEX` without `CONCURRENTLY`, blocking table writes. "
                        "Use `CREATE [UNIQUE] INDEX CONCURRENTLY`."
                    ),
                }
            )
        if DROP_COLUMN_RE.search(line) and "-- expand-contract" not in line:
            findings.append(
                {
                    "kind": "non_concurrent_index_or_lock_hazard",
                    "file": rel_path,
                    "line": line_no,
                    "message": (
                        "Destructive `ALTER TABLE ... DROP COLUMN` without `-- expand-contract` confirmation."
                    ),
                }
            )

    return findings


def _scan_soft_delete_tables(source: str, rel_path: str) -> List[Dict[str, object]]:
    findings: List[Dict[str, object]] = []
    for match in CREATE_TABLE_BLOCK_RE.finditer(source):
        table_name = match.group(1)
        body = match.group(2)
        if not re.search(r"\bdeleted_at\b", body, re.IGNORECASE):
            continue
        # Flag plain UNIQUE on non-id/non-idempotency columns inside a soft-deleted table
        has_plain_unique = False
        for raw_line in body.splitlines():
            line = raw_line.strip()
            if line.startswith("--"):
                continue
            if re.search(r"\bUNIQUE\b", line, re.IGNORECASE) and not re.search(
                r"\bidempotency_key\b|\bPRIMARY\s+KEY\b", line, re.IGNORECASE
            ):
                has_plain_unique = True
                break
        if has_plain_unique:
            line_no = source[: match.start()].count("\n") + 1
            findings.append(
                {
                    "kind": "soft_delete_unique_hazard",
                    "file": rel_path,
                    "line": line_no,
                    "message": (
                        f"Table `{table_name}` combines `deleted_at` with a plain `UNIQUE` constraint, "
                        "preventing re-creation of soft-deleted records. Use a partial unique index "
                        "`CREATE UNIQUE INDEX ... WHERE deleted_at IS NULL`."
                    ),
                }
            )
    return findings


def _scan_orm_float_money_line(
    line: str, next_line: str, rel_path: str, line_no: int, suffix: str
) -> List[Dict[str, object]]:
    findings: List[Dict[str, object]] = []
    if suffix == ".py" and ORM_PY_FLOAT_MONEY_RE.search(line):
        findings.append(
            {
                "kind": "float_money_column",
                "file": rel_path,
                "line": line_no,
                "message": (
                    "Python ORM monetary field uses floating-point (`Float`/`FloatField`). "
                    "Use integer minor units (`BigInteger`) or exact `Numeric(19, 4)`."
                ),
            }
        )
    elif suffix in {".ts", ".tsx", ".js", ".jsx"}:
        if ORM_TS_FLOAT_MONEY_RE.search(line) or (
            TYPEORM_FLOAT_DECORATOR_RE.search(line)
            and (MONEY_IDENT_RE.search(line) or MONEY_IDENT_RE.search(next_line))
        ):
            findings.append(
                {
                    "kind": "float_money_column",
                    "file": rel_path,
                    "line": line_no,
                    "message": (
                        "JS/TS ORM monetary field uses IEEE-754 float (`float`/`doublePrecision`/`real`). "
                        "Use `bigint` minor units or `numeric(19, 4)`."
                    ),
                }
            )
    elif suffix == ".go" and ORM_GO_FLOAT_MONEY_RE.search(line):
        findings.append(
            {
                "kind": "float_money_column",
                "file": rel_path,
                "line": line_no,
                "message": (
                    "Go struct monetary field uses `float32`/`float64`. "
                    "Use `int64` minor units or exact decimal."
                ),
            }
        )
    return findings


def _scan_query_in_loop(lines: List[str], rel_path: str, suffix: str) -> List[Dict[str, object]]:
    if suffix not in {".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs"}:
        return []
    findings: List[Dict[str, object]] = []
    if suffix == ".py":
        loop_indent: Optional[int] = None
        for idx, line in enumerate(lines, start=1):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            indent = len(line) - len(line.lstrip())
            if loop_indent is not None and indent <= loop_indent:
                loop_indent = None
            m = PY_LOOP_HEADER_RE.match(line)
            if m:
                loop_indent = len(m.group(1))
                continue
            if (
                loop_indent is not None
                and ORM_QUERY_CALL_RE.search(line)
                and "allow-query-in-loop" not in line
            ):
                findings.append(
                    {
                        "kind": "query_in_loop_hazard",
                        "file": rel_path,
                        "line": idx,
                        "message": (
                            "Database/ORM query executed inside a loop (N+1 waterfall hazard). "
                            "Batch-fetch with `WHERE id IN (...)`, `selectinload`, or bulk `JOIN`."
                        ),
                    }
                )
    else:
        in_loop = False
        loop_opened = False
        loop_brace_depth = 0
        brace_depth = 0
        for idx, line in enumerate(lines, start=1):
            stripped = line.strip()
            if not stripped or stripped.startswith(("//", "/*", "*")):
                continue
            if BRACE_LOOP_HEADER_RE.search(line):
                in_loop = True
                loop_opened = False
                loop_brace_depth = brace_depth
            if (
                in_loop
                and ORM_QUERY_CALL_RE.search(line)
                and "allow-query-in-loop" not in line
            ):
                findings.append(
                    {
                        "kind": "query_in_loop_hazard",
                        "file": rel_path,
                        "line": idx,
                        "message": (
                            "Database/ORM query executed inside a loop (N+1 waterfall hazard). "
                            "Batch-fetch with `WHERE id IN (...)`, `include`/`preload`, or DataLoader."
                        ),
                    }
                )
            open_count = line.count("{")
            close_count = line.count("}")
            if in_loop and open_count > 0:
                loop_opened = True
            brace_depth += open_count - close_count
            if in_loop and loop_opened and brace_depth <= loop_brace_depth:
                in_loop = False
                loop_opened = False
    return findings


def scan_file_db(
    source: str, rel_path: str, suffix: str, strict_migrations: bool = False
) -> List[Dict[str, object]]:
    findings: List[Dict[str, object]] = []
    lines = source.splitlines()
    is_mig = is_migration_file(rel_path)

    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith(("#", "//", "--", "/*", "*")):
            continue

        next_line = lines[idx] if idx < len(lines) else ""
        if suffix == ".sql":
            findings.extend(_scan_sql_schema_line(line, rel_path, idx, is_mig, strict_migrations))
        elif suffix == ".prisma":
            if PRISMA_FLOAT_MONEY_RE.search(line):
                findings.append(
                    {
                        "kind": "float_money_column",
                        "file": rel_path,
                        "line": idx,
                        "message": (
                            "Prisma monetary field uses `Float`. Use `BigInt` (minor units) or `Decimal`."
                        ),
                    }
                )
        else:
            findings.extend(_scan_orm_float_money_line(line, next_line, rel_path, idx, suffix))

        # Query-level checks across SQL and application code
        if SELECT_STAR_RE.search(line) and "allow-select-star" not in line:
            findings.append(
                {
                    "kind": "unbounded_select_star",
                    "file": rel_path,
                    "line": idx,
                    "message": (
                        "`SELECT * FROM ...` fetches all columns and breaks Index-Only Scans. "
                        "Project explicit columns."
                    ),
                }
            )

        if OFFSET_PAGINATION_RE.search(line) and "allow-offset" not in line:
            findings.append(
                {
                    "kind": "offset_pagination_hazard",
                    "file": rel_path,
                    "line": idx,
                    "message": (
                        "`OFFSET` pagination degrades linearly O(N) on large tables. "
                        "Use Keyset / Seek pagination (`WHERE (created_at, id) < ($1, $2)`)."
                    ),
                }
            )

    if suffix == ".sql":
        findings.extend(_scan_soft_delete_tables(source, rel_path))
    else:
        findings.extend(_scan_query_in_loop(lines, rel_path, suffix))

    return findings


def scan_workspace_db(workspace: Path, strict_migrations: bool = False) -> Dict[str, object]:
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
                if fpath.suffix in DB_EXTENSIONS and not is_test_file(fpath):
                    files_to_scan.append(fpath)

    for fpath in files_to_scan:
        if fpath.name == "db_architecture_gate.py":
            continue
        try:
            source = fpath.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = str(fpath.relative_to(root)).replace("\\", "/")
        findings.extend(
            scan_file_db(source, rel, fpath.suffix, strict_migrations=strict_migrations)
        )

    return {
        "workspace": str(workspace).replace("\\", "/"),
        "files_scanned": len(files_to_scan),
        "finding_count": len(findings),
        "findings": findings,
    }


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Database Architecture & Data Engineering Mechanical Gate."
    )
    parser.add_argument("workspace", nargs="?", default=".", help="Workspace or file path")
    parser.add_argument("--json", action="store_true", help="Output JSON report")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Enforce strict zero-downtime migration checks and exit 1 on any finding",
    )

    args = parser.parse_args(argv)
    ws = Path(args.workspace).resolve()
    report = scan_workspace_db(ws, strict_migrations=args.strict)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(
            f"Database Architecture Gate: scanned {report['files_scanned']} file(s), "
            f"{report['finding_count']} defect(s)."
        )
        for f in report["findings"]:
            print(f"  - [{f['kind']}] {f['file']}:{f['line']} — {f['message']}")

    if args.strict and report["finding_count"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
