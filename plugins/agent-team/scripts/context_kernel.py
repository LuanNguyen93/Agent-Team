#!/usr/bin/env python3
"""
Agent-Computer Interface (ACI) Context Kernel for Agent Team.

Implements token-reduction mechanisms grounded in software engineering research:
1. AST Skeletonization (RepoGraph arXiv:2410.04652 / Aider RepoMap):
   Compresses source files by eliding function/method bodies while preserving
   structural signatures, docstrings (first line), and exact [Lstart-Lend] spans.
2. Surgical AST Symbol Extraction (AutoCodeRover ISSTA 2024):
   Retrieves only the exact AST node (class/function) requested by name.
3. Observation / Log Folding (SWE-agent NeurIPS 2024 ACI Kernel):
   Compresses verbose test/build logs into compact failure-only capsules.

Zero third-party dependencies (Python standard library only).
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

GEMINI_IMPLICIT_CACHE_MIN_TOKENS = 4096
GEMINI_TURN_BATCH_MIN_TOKENS = 2050

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
}

CODE_EXTENSIONS = {".py", ".ts", ".tsx", ".js", ".jsx", ".rs", ".go"}

REGEX_SIG_PATTERNS = [
    re.compile(
        r"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?"
        r"(?:function|class|interface|type|enum)\s+([A-Za-z_][A-Za-z0-9_]*)"
    ),
    re.compile(
        r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:async\s*)?\("
    ),
    re.compile(r"^\s*(?:pub\s+)?(?:async\s+)?(?:fn|struct|enum|trait)\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*func\s+(?:\([^)]+\)\s*)?([A-Za-z_][A-Za-z0-9_]*)"),
]


@dataclass
class SymbolSkeleton:
    name: str
    kind: str
    signature: str
    start_line: int
    end_line: int
    docstring_summary: str = ""


@dataclass
class FileSkeleton:
    file: str
    total_lines: int
    raw_tokens_est: int
    skeleton_tokens_est: int
    reduction_pct: float
    symbols: List[SymbolSkeleton]


def estimate_tokens(text: str) -> int:
    """Rough token estimator (~4 chars per token)."""
    if not text:
        return 0
    return max(1, (len(text) + 3) // 4)


def _format_arg(arg: ast.arg) -> str:
    if arg.annotation:
        try:
            return f"{arg.arg}: {ast.unparse(arg.annotation)}"
        except Exception:
            return arg.arg
    return arg.arg


def _format_py_signature(node: ast.AST) -> str:
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        prefix = "async def" if isinstance(node, ast.AsyncFunctionDef) else "def"
        args = [_format_arg(a) for a in node.args.args]
        if node.args.vararg:
            args.append(f"*{_format_arg(node.args.vararg)}")
        if node.args.kwarg:
            args.append(f"**{_format_arg(node.args.kwarg)}")
        ret = ""
        if node.returns:
            try:
                ret = f" -> {ast.unparse(node.returns)}"
            except Exception:
                ret = ""
        return f"{prefix} {node.name}({', '.join(args)}){ret}"
    if isinstance(node, ast.ClassDef):
        bases = []
        for b in node.bases:
            try:
                bases.append(ast.unparse(b))
            except Exception:
                bases.append("?")
        base_str = f"({', '.join(bases)})" if bases else ""
        return f"class {node.name}{base_str}"
    return ""


def skeletonize_python_file(file_path: Path, rel_path: str) -> Optional[FileSkeleton]:
    try:
        source = file_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    lines = source.splitlines()
    raw_tokens = estimate_tokens(source)
    try:
        tree = ast.parse(source, filename=str(file_path))
    except SyntaxError:
        return skeletonize_generic_file(file_path, rel_path)

    symbols: List[SymbolSkeleton] = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            doc = ast.get_docstring(node) or ""
            doc_first = doc.splitlines()[0].strip() if doc else ""
            symbols.append(
                SymbolSkeleton(
                    name=node.name,
                    kind="function",
                    signature=_format_py_signature(node),
                    start_line=node.lineno,
                    end_line=getattr(node, "end_lineno", node.lineno),
                    docstring_summary=doc_first,
                )
            )
        elif isinstance(node, ast.ClassDef):
            doc = ast.get_docstring(node) or ""
            doc_first = doc.splitlines()[0].strip() if doc else ""
            symbols.append(
                SymbolSkeleton(
                    name=node.name,
                    kind="class",
                    signature=_format_py_signature(node),
                    start_line=node.lineno,
                    end_line=getattr(node, "end_lineno", node.lineno),
                    docstring_summary=doc_first,
                )
            )
            for item in node.body:
                if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    mdoc = ast.get_docstring(item) or ""
                    mdoc_first = mdoc.splitlines()[0].strip() if mdoc else ""
                    symbols.append(
                        SymbolSkeleton(
                            name=f"{node.name}.{item.name}",
                            kind="method",
                            signature="  " + _format_py_signature(item),
                            start_line=item.lineno,
                            end_line=getattr(item, "end_lineno", item.lineno),
                            docstring_summary=mdoc_first,
                        )
                    )

    rendered = render_file_skeleton_text(rel_path, len(lines), symbols)
    skel_tokens = estimate_tokens(rendered)
    reduction = round((1.0 - (skel_tokens / max(1, raw_tokens))) * 100.0, 1)
    return FileSkeleton(
        file=rel_path,
        total_lines=len(lines),
        raw_tokens_est=raw_tokens,
        skeleton_tokens_est=skel_tokens,
        reduction_pct=max(0.0, reduction),
        symbols=symbols,
    )


def skeletonize_generic_file(file_path: Path, rel_path: str) -> Optional[FileSkeleton]:
    try:
        source = file_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    lines = source.splitlines()
    raw_tokens = estimate_tokens(source)
    symbols: List[SymbolSkeleton] = []

    for idx, line in enumerate(lines, start=1):
        for pat in REGEX_SIG_PATTERNS:
            m = pat.match(line)
            if m:
                sym_name = m.group(1)
                sig = line.strip().rstrip("{:").strip()
                symbols.append(
                    SymbolSkeleton(
                        name=sym_name,
                        kind="symbol",
                        signature=sig,
                        start_line=idx,
                        end_line=idx,
                    )
                )
                break

    rendered = render_file_skeleton_text(rel_path, len(lines), symbols)
    skel_tokens = estimate_tokens(rendered)
    reduction = round((1.0 - (skel_tokens / max(1, raw_tokens))) * 100.0, 1)
    return FileSkeleton(
        file=rel_path,
        total_lines=len(lines),
        raw_tokens_est=raw_tokens,
        skeleton_tokens_est=skel_tokens,
        reduction_pct=max(0.0, reduction),
        symbols=symbols,
    )


def render_file_skeleton_text(
    rel_path: str, total_lines: int, symbols: List[SymbolSkeleton]
) -> str:
    out = [f"# {rel_path} ({total_lines} lines)"]
    for s in symbols:
        doc_part = f"  # {s.docstring_summary}" if s.docstring_summary else ""
        out.append(f"  [L{s.start_line}-L{s.end_line}] {s.signature}: ...{doc_part}")
    return "\n".join(out)


def build_skeleton(target: Path, root: Path) -> List[FileSkeleton]:
    results: List[FileSkeleton] = []
    if target.is_file():
        rel = str(target.relative_to(root)).replace("\\", "/")
        skel = (
            skeletonize_python_file(target, rel)
            if target.suffix == ".py"
            else skeletonize_generic_file(target, rel)
        )
        if skel:
            results.append(skel)
        return results

    for dirpath, dirnames, filenames in os.walk(target):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fname in sorted(filenames):
            fpath = Path(dirpath) / fname
            if fpath.suffix not in CODE_EXTENSIONS:
                continue
            rel = str(fpath.relative_to(root)).replace("\\", "/")
            skel = (
                skeletonize_python_file(fpath, rel)
                if fpath.suffix == ".py"
                else skeletonize_generic_file(fpath, rel)
            )
            if skel:
                results.append(skel)
    return results


def extract_symbol_source(file_path: Path, symbol_name: str) -> Optional[dict]:
    """Surgical AST Node Retrieval (AutoCodeRover style): returns exact symbol lines."""
    try:
        source = file_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    lines = source.splitlines()
    raw_tokens = estimate_tokens(source)

    if file_path.suffix == ".py":
        try:
            tree = ast.parse(source, filename=str(file_path))
            for node in ast.walk(tree):
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                    if node.name == symbol_name:
                        start = node.lineno
                        end = getattr(node, "end_lineno", start)
                        snippet_lines = [
                            f"{ln}: {lines[ln - 1]}" for ln in range(start, end + 1)
                        ]
                        snippet = "\n".join(snippet_lines)
                        snip_tokens = estimate_tokens(snippet)
                        return {
                            "file": str(file_path).replace("\\", "/"),
                            "symbol": symbol_name,
                            "start_line": start,
                            "end_line": end,
                            "raw_file_tokens": raw_tokens,
                            "extracted_tokens": snip_tokens,
                            "reduction_pct": round(
                                (1.0 - (snip_tokens / max(1, raw_tokens))) * 100.0, 1
                            ),
                            "source": snippet,
                        }
        except SyntaxError:
            tree = None

    # Fallback line-window search for non-Python or syntax errors
    pattern = re.compile(rf"\b{re.escape(symbol_name)}\b")
    for idx, line in enumerate(lines, start=1):
        if pattern.search(line):
            start = max(1, idx - 2)
            end = min(len(lines), idx + 35)
            snippet_lines = [f"{ln}: {lines[ln - 1]}" for ln in range(start, end + 1)]
            snippet = "\n".join(snippet_lines)
            snip_tokens = estimate_tokens(snippet)
            return {
                "file": str(file_path).replace("\\", "/"),
                "symbol": symbol_name,
                "start_line": start,
                "end_line": end,
                "raw_file_tokens": raw_tokens,
                "extracted_tokens": snip_tokens,
                "reduction_pct": round(
                    (1.0 - (snip_tokens / max(1, raw_tokens))) * 100.0, 1
                ),
                "source": snippet,
            }
    return None


def compress_log_output(raw_log: str, max_failure_lines: int = 40) -> dict:
    """SWE-agent ACI Observation Masking: drops passing noise, retains failure capsule."""
    lines = raw_log.splitlines()
    raw_tokens = estimate_tokens(raw_log)

    failure_Start_re = re.compile(
        r"(FAIL|ERROR|Traceback \(most recent call last\)|AssertionError|Exception:|panic:|FAIL\s+)",
        re.IGNORECASE,
    )
    summary_re = re.compile(
        r"(Ran \d+ tests|passed|failed|error|OK\b|FAILED\b|Test Suites:|Tests:)",
        re.IGNORECASE,
    )

    failure_blocks: List[str] = []
    summaries: List[str] = []
    capturing = 0

    for line in lines:
        if summary_re.search(line) and len(line.strip()) < 160:
            summaries.append(line.strip())
        if failure_Start_re.search(line):
            capturing = 12
        if capturing > 0:
            if len(failure_blocks) < max_failure_lines:
                failure_blocks.append(line)
            capturing -= 1

    compressed_parts: List[str] = []
    if failure_blocks:
        compressed_parts.append("=== FAILURE CAPSULE ===")
        compressed_parts.extend(failure_blocks)
    if summaries:
        compressed_parts.append("=== SUMMARY ===")
        # Deduplicate preserving order
        seen = set()
        for s in summaries[-8:]:
            if s not in seen:
                seen.add(s)
                compressed_parts.append(s)
    if not compressed_parts and lines:
        compressed_parts.append("=== TAIL SUMMARY ===")
        compressed_parts.extend(lines[-5:])

    compressed_text = "\n".join(compressed_parts)
    comp_tokens = estimate_tokens(compressed_text)
    reduction = round((1.0 - (comp_tokens / max(1, raw_tokens))) * 100.0, 1)

    return {
        "raw_lines": len(lines),
        "compressed_lines": len(compressed_parts),
        "raw_tokens_est": raw_tokens,
        "compressed_tokens_est": comp_tokens,
        "reduction_pct": max(0.0, reduction),
        "output": compressed_text,
    }


def _first_sentence(text: str, max_chars: int = 110) -> str:
    clean = re.sub(r"\s+", " ", (text or "").strip())
    if not clean:
        return ""
    first = re.split(r"(?<=[.!?])\s+", clean)[0]
    if len(first) <= max_chars:
        return first
    return first[: max_chars - 3].rstrip() + "..."


def compress_mcp_schemas(
    tools_payload: Any,
    query: str = "",
    limit: int = 20,
) -> Dict[str, Any]:
    """ScaleMCP / Tool Space Interference eliminator: strips schema bloat & filters tools."""
    if isinstance(tools_payload, dict):
        raw_tools = tools_payload.get("tools", [])
    elif isinstance(tools_payload, list):
        raw_tools = tools_payload
    else:
        raw_tools = []

    raw_json = json.dumps(raw_tools)
    raw_tokens = estimate_tokens(raw_json)
    query_terms = [t.lower() for t in re.findall(r"[a-zA-Z0-9_-]+", query or "") if len(t) > 1]

    scored: List[tuple] = []
    for idx, t in enumerate(raw_tools):
        if not isinstance(t, dict):
            continue
        name = str(t.get("name", f"tool_{idx}"))
        desc = str(t.get("description", ""))
        haystack = f"{name} {desc}".lower()
        score = sum(3 if term in name.lower() else 1 for term in query_terms if term in haystack)
        scored.append((score, -idx, t))

    if query_terms:
        scored.sort(key=lambda x: (x[0], x[1]), reverse=True)

    selected = [item[2] for item in scored[: max(1, limit)]]
    compressed_tools: List[Dict[str, Any]] = []

    for t in selected:
        name = str(t.get("name", ""))
        short_desc = _first_sentence(str(t.get("description", "")), max_chars=95)
        schema = t.get("inputSchema") or t.get("parameters") or {}
        props = schema.get("properties", {}) if isinstance(schema, dict) else {}
        req_set = set(schema.get("required", [])) if isinstance(schema, dict) else set()
        compact_params: Dict[str, str] = {}
        if isinstance(props, dict):
            for pname, pmeta in props.items():
                if not isinstance(pmeta, dict):
                    compact_params[pname] = "any"
                    continue
                ptype = str(pmeta.get("type", "any"))
                req_marker = "*" if pname in req_set else ""
                pdesc = _first_sentence(str(pmeta.get("description", "")), max_chars=45)
                compact_params[pname] = f"{ptype}{req_marker}" + (f": {pdesc}" if pdesc else "")

        compressed_tools.append(
            {
                "name": name,
                "desc": short_desc,
                "params": compact_params,
            }
        )

    comp_json = json.dumps(compressed_tools, separators=(",", ":"))
    comp_tokens = estimate_tokens(comp_json)
    reduction = round((1.0 - (comp_tokens / max(1, raw_tokens))) * 100.0, 1)

    return {
        "tools_input": len(raw_tools),
        "tools_retained": len(compressed_tools),
        "raw_tokens_est": raw_tokens,
        "compressed_tokens_est": comp_tokens,
        "reduction_pct": max(0.0, reduction),
        "tools": compressed_tools,
    }


def build_gemini_prefix_bundle(
    target: Path,
    limit: int = 50,
    system_invariant: str = "",
) -> Dict[str, Any]:
    """Constructs an immutable static prefix aligned with Gemini 2.5/3/4 Context Caching."""
    resolved = target.resolve()
    root = resolved if resolved.is_dir() else resolved.parent
    skels = build_skeleton(resolved, root)[: max(1, limit)]

    prefix_blocks: List[str] = ["=== GEMINI IMMUTABLE STATIC PREFIX ==="]
    if system_invariant:
        prefix_blocks.append(f"[SYSTEM INVARIANTS]\n{system_invariant.strip()}")

    prefix_blocks.append("[REPOSITORY AST SKELETON MAP]")
    for s in skels:
        prefix_blocks.append(render_file_skeleton_text(s.file, s.total_lines, s.symbols))

    static_prefix = "\n\n".join(prefix_blocks)
    prefix_tokens = estimate_tokens(static_prefix)
    raw_tokens = sum(s.raw_tokens_est for s in skels) + estimate_tokens(system_invariant)
    reduction = round((1.0 - (prefix_tokens / max(1, raw_tokens))) * 100.0, 1)
    cache_hash = hashlib.sha256(static_prefix.encode("utf-8")).hexdigest()

    return {
        "cache_key_sha256": cache_hash,
        "files_included": len(skels),
        "raw_tokens_est": raw_tokens,
        "prefix_tokens_est": prefix_tokens,
        "reduction_pct": max(0.0, reduction),
        "gemini_implicit_cache_min_tokens": GEMINI_IMPLICIT_CACHE_MIN_TOKENS,
        "gemini_turn_batch_min_tokens": GEMINI_TURN_BATCH_MIN_TOKENS,
        "implicit_cache_eligible": prefix_tokens >= GEMINI_IMPLICIT_CACHE_MIN_TOKENS,
        "static_prefix": static_prefix,
    }


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="ACI Context Kernel: AST Skeletonization, Surgical Extraction & Log Compression."
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_skel = sub.add_parser("skeleton", help="Generate compact AST skeleton for file or directory")
    p_skel.add_argument("path", help="File or directory path")
    p_skel.add_argument("--json", action="store_true", help="Output JSON")

    p_ext = sub.add_parser("extract", help="Surgically extract a single AST symbol by name")
    p_ext.add_argument("file", help="Path to source file")
    p_ext.add_argument("symbol", help="Function or class name to extract")
    p_ext.add_argument("--json", action="store_true", help="Output JSON")

    p_log = sub.add_parser("compress-log", help="Compress verbose test/build logs from stdin or file")
    p_log.add_argument("--file", help="Optional log file path (reads stdin if omitted)")
    p_log.add_argument("--json", action="store_true", help="Output JSON")

    p_mcp = sub.add_parser("compress-mcp", help="Compress MCP tool schemas to prevent Tool Space Interference")
    p_mcp.add_argument("input", help="Path to MCP tools JSON file")
    p_mcp.add_argument("--query", default="", help="Optional task keyword filter")
    p_mcp.add_argument("--limit", type=int, default=20, help="Max tools to retain")
    p_mcp.add_argument("--json", action="store_true", help="Output JSON")

    p_pref = sub.add_parser("prefix-pack", help="Build Gemini prefix-stable context cache bundle")
    p_pref.add_argument("path", help="Directory or file path")
    p_pref.add_argument("--limit", type=int, default=50, help="Max files in prefix")
    p_pref.add_argument("--json", action="store_true", help="Output JSON")

    args = parser.parse_args(argv)

    if args.cmd == "skeleton":
        target = Path(args.path).resolve()
        root = target if target.is_dir() else target.parent
        skels = build_skeleton(target, root)
        total_raw = sum(s.raw_tokens_est for s in skels)
        total_skel = sum(s.skeleton_tokens_est for s in skels)
        overall_red = round((1.0 - (total_skel / max(1, total_raw))) * 100.0, 1)

        if args.json:
            print(
                json.dumps(
                    {
                        "files_scanned": len(skels),
                        "raw_tokens_est": total_raw,
                        "skeleton_tokens_est": total_skel,
                        "reduction_pct": max(0.0, overall_red),
                        "files": [asdict(s) for s in skels],
                    },
                    indent=2,
                )
            )
        else:
            for s in skels:
                print(render_file_skeleton_text(s.file, s.total_lines, s.symbols))
            print(
                f"\n[ACI Kernel Skeleton] files={len(skels)} | "
                f"raw_tokens~={total_raw} -> skeleton_tokens~={total_skel} "
                f"(saved {max(0.0, overall_red)}%)"
            )
        return 0

    if args.cmd == "extract":
        fpath = Path(args.file).resolve()
        res = extract_symbol_source(fpath, args.symbol)
        if not res:
            print(f"Symbol '{args.symbol}' not found in {args.file}", file=sys.stderr)
            return 1
        if args.json:
            print(json.dumps(res, indent=2))
        else:
            print(
                f"# {res['file']} :: {res['symbol']} [L{res['start_line']}-L{res['end_line']}] "
                f"(tokens: {res['extracted_tokens']} vs full file {res['raw_file_tokens']} "
                f"| saved {res['reduction_pct']}%)"
            )
            print(res["source"])
        return 0

    if args.cmd == "compress-log":
        if args.file:
            raw_log = Path(args.file).read_text(encoding="utf-8", errors="replace")
        else:
            raw_log = sys.stdin.read()
        res = compress_log_output(raw_log)
        if args.json:
            print(json.dumps(res, indent=2))
        else:
            print(res["output"])
            print(
                f"\n[ACI Log Kernel] lines: {res['raw_lines']} -> {res['compressed_lines']} | "
                f"tokens: {res['raw_tokens_est']} -> {res['compressed_tokens_est']} "
                f"(saved {res['reduction_pct']}%)"
            )
        return 0

    if args.cmd == "compress-mcp":
        payload = json.loads(Path(args.input).read_text(encoding="utf-8", errors="replace"))
        res = compress_mcp_schemas(payload, query=args.query, limit=args.limit)
        if args.json:
            print(json.dumps(res, indent=2))
        else:
            for t in res["tools"]:
                print(f"- {t['name']}: {t['desc']} | params={json.dumps(t['params'])}")
            print(
                f"\n[ACI MCP Kernel] tools: {res['tools_input']} -> {res['tools_retained']} | "
                f"tokens: {res['raw_tokens_est']} -> {res['compressed_tokens_est']} "
                f"(saved {res['reduction_pct']}%)"
            )
        return 0

    if args.cmd == "prefix-pack":
        res = build_gemini_prefix_bundle(Path(args.path), limit=args.limit)
        if args.json:
            print(json.dumps(res, indent=2))
        else:
            print(res["static_prefix"])
            print(
                f"\n[Gemini Cache Prefix] sha256={res['cache_key_sha256'][:12]} | "
                f"files={res['files_included']} | tokens={res['prefix_tokens_est']} "
                f"(saved {res['reduction_pct']}% | implicit_cache_ready={res['implicit_cache_eligible']})"
            )
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
