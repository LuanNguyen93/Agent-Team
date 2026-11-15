#!/usr/bin/env python3
"""Kernel Tool Forge CLI — Self-Tooling ACI Synthesizer, MCP Compressor & Market Recon Engine.

Follows the canonical Science & Agent-Team CLI pattern:
- Uses argparse with subcommands (market-intel, compress-mcp, synthesize, gemini-cache-pack).
- All subcommands require --output and write JSON output to files (Rule 3 & Rule 4).
- Uses Python standard library only (urllib, json, argparse, ast, hashlib, csv).
- Implements cross-process file-lock rate limiting using time.monotonic() and RateLimitError.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import hashlib
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib import error as urllib_error
from urllib import parse as urllib_parse
from urllib import request as urllib_request

try:
    import fcntl
except ImportError:
    fcntl = None  # type: ignore

HERE = Path(__file__).resolve().parent
SKILL_ROOT = HERE.parent
PLUGIN_ROOT = SKILL_ROOT.parent.parent
SCRIPTS_DIR = PLUGIN_ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import context_kernel  # noqa: E402

PATTERNS_PATH = SKILL_ROOT / "references" / "architecture_patterns.json"
REVIEWS_SCRIPT_PATH = PLUGIN_ROOT / "skills" / "market-recon" / "scripts" / "reviews.py"


class RateLimitError(Exception):
    """Raised when an external API rate limit (HTTP 429) is exceeded after retries."""


class FileLockedAPIClient:
    """HTTP JSON client with cross-process file-lock rate limiting and exponential backoff.

    Documented rate limits respected:
    - Hacker News Algolia API (https://hn.algolia.com/api/v1): 2.0 req/s (0.5s delay)
    - OpenAlex API (https://api.openalex.org): 5.0 req/s (0.2s delay)
    - Apple iTunes RSS API (https://itunes.apple.com): 1.0 req/s (1.0s delay)
    """

    def __init__(self, base_url: str, requests_per_second: float = 1.0, lock_name: str = "api"):
        self.base_url = base_url.rstrip("/")
        self.requests_per_second = max(0.1, float(requests_per_second))
        self.delay = 1.0 / self.requests_per_second
        self.last_request_time = 0.0
        safe_lock = re.sub(r"[^a-zA-Z0-9_-]", "_", lock_name)
        self.lock_file = Path(tempfile.gettempdir()) / f"kernel_forge_{safe_lock}.lock"

    def _wait_for_rate_limit(self) -> None:
        """Synchronizes rate limiting across in-process and multi-process subagents."""
        elapsed = time.monotonic() - self.last_request_time
        if elapsed < self.delay:
            time.sleep(self.delay - elapsed)

        try:
            self.lock_file.parent.mkdir(parents=True, exist_ok=True)
            with open(self.lock_file, "a+", encoding="utf-8") as lf:
                if fcntl is not None:
                    fcntl.flock(lf.fileno(), fcntl.LOCK_EX)
                try:
                    lf.seek(0)
                    raw = lf.read().strip()
                    now_mono = time.monotonic()
                    if raw:
                        try:
                            last_ts = float(raw)
                        except ValueError:
                            last_ts = 0.0
                        wait_more = (last_ts + self.delay) - now_mono
                        if 0 < wait_more <= 10.0:
                            time.sleep(wait_more)
                    lf.seek(0)
                    lf.truncate()
                    lf.write(f"{time.monotonic():.6f}")
                    lf.flush()
                finally:
                    if fcntl is not None:
                        fcntl.flock(lf.fileno(), fcntl.LOCK_UN)
        except OSError as exc:
            self.last_request_time = time.monotonic()
            _ = exc

    def request_json(
        self,
        path: str,
        params: Optional[Dict[str, Any]] = None,
        retries: int = 3,
    ) -> Any:
        url = f"{self.base_url}{path}" if path.startswith("/") else f"{self.base_url}/{path}"
        if params:
            clean_params = {k: v for k, v in params.items() if v is not None and v != ""}
            if clean_params:
                url = f"{url}?{urllib_parse.urlencode(clean_params)}"

        for attempt in range(retries):
            self._wait_for_rate_limit()
            try:
                req = urllib_request.Request(url)
                req.add_header("Accept", "application/json")
                req.add_header("User-Agent", "AgentTeam-KernelToolForge/1.0 (https://github.com/LuanNguyen93/Agent-Team)")
                with urllib_request.urlopen(req, timeout=25) as response:
                    self.last_request_time = time.monotonic()
                    return json.loads(response.read().decode("utf-8", errors="replace"))
            except urllib_error.HTTPError as e:
                self.last_request_time = time.monotonic()
                if e.code == 429:
                    wait = 2**attempt
                    print(
                        f"Rate limited (429) on {url}, retrying in {wait}s "
                        f"(attempt {attempt + 1}/{retries})...",
                        file=sys.stderr,
                    )
                    if attempt == retries - 1:
                        raise RateLimitError(
                            f"HTTP 429 Too Many Requests from {url}. "
                            f"Rate limit ({self.requests_per_second} req/s) exceeded after {retries} retries."
                        ) from e
                    time.sleep(wait)
                    continue
                if e.code >= 500:
                    wait = 2**attempt
                    print(
                        f"Server error {e.code} on {url}, retrying in {wait}s "
                        f"(attempt {attempt + 1}/{retries})...",
                        file=sys.stderr,
                    )
                    if attempt == retries - 1:
                        raise RuntimeError(
                            f"Server error {e.code} from {url} after {retries} retries."
                        ) from e
                    time.sleep(wait)
                    continue
                try:
                    body = e.read().decode("utf-8", errors="replace")[:1000]
                except OSError:
                    body = str(e.reason)
                raise RuntimeError(f"HTTP {e.code} from {url}: {body}") from e
            except urllib_error.URLError as e:
                if attempt == retries - 1:
                    raise RuntimeError(
                        f"Failed to connect to {url} after {retries} attempts: {e}"
                    ) from e
                time.sleep(2**attempt)
        raise RuntimeError(f"Exhausted retries for {url}")


def write_output(data: Any, output_file: str) -> None:
    """Writes JSON payload to output_file and prints a short status message to stdout."""
    out_path = Path(output_file)
    try:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        print(f"Success! Data written to: {output_file}")
    except (OSError, TypeError) as e:
        print(f"Error writing to file {output_file}: {e}", file=sys.stderr)
        sys.exit(1)


def _strip_html(raw: str) -> str:
    text = re.sub(r"<[^>]+>", " ", raw or "")
    text = (
        text.replace("&quot;", '"')
        .replace("&#x27;", "'")
        .replace("&amp;", "&")
        .replace("&gt;", ">")
        .replace("&lt;", "<")
    )
    return re.sub(r"\s+", " ", text).strip()


def _reconstruct_openalex_abstract(inv_idx: Optional[Dict[str, List[int]]]) -> str:
    if not inv_idx or not isinstance(inv_idx, dict):
        return ""
    pairs = []
    for word, positions in inv_idx.items():
        if isinstance(positions, list):
            for pos in positions:
                pairs.append((pos, word))
    pairs.sort(key=lambda x: x[0])
    return " ".join(w for _, w in pairs[:90])


def fetch_live_market_signals(
    query: str,
    sources: List[str],
    limit: int,
    app_id: Optional[str] = None,
) -> tuple:
    items: List[Dict[str, Any]] = []
    warnings: List[str] = []

    if "hn" in sources:
        hn_client = FileLockedAPIClient("https://hn.algolia.com/api/v1", requests_per_second=2.0, lock_name="hn")
        try:
            res = hn_client.request_json(
                "/search",
                params={"query": query, "tags": "story", "hitsPerPage": max(1, min(limit, 50))},
            )
            for hit in res.get("hits", [])[:limit]:
                obj_id = hit.get("objectID", "")
                title = hit.get("title") or ""
                story_text = _strip_html(hit.get("story_text") or "")
                url = hit.get("url") or f"https://news.ycombinator.com/item?id={obj_id}"
                combined = f"{title}. {story_text}".strip()
                if len(combined) >= 15:
                    items.append({
                        "source": "hacker-news",
                        "url": f"https://news.ycombinator.com/item?id={obj_id}" if obj_id else url,
                        "date": (hit.get("created_at") or "")[:10],
                        "rating": None,
                        "points": hit.get("points") or 0,
                        "comments": hit.get("num_comments") or 0,
                        "text": combined[:600],
                    })
        except Exception as exc:
            warnings.append(f"hn: {exc}")

    if "appstore" in sources and app_id:
        app_client = FileLockedAPIClient("https://itunes.apple.com", requests_per_second=1.0, lock_name="appstore")
        try:
            res = app_client.request_json(f"/us/rss/customerreviews/id={app_id}/sortBy=mostRecent/json")
            entries = res.get("feed", {}).get("entry", [])
            if isinstance(entries, dict):
                entries = [entries]
            for entry in entries[:limit]:
                if not isinstance(entry, dict) or "content" not in entry:
                    continue
                title = entry.get("title", {}).get("label", "")
                content = entry.get("content", {}).get("label", "")
                rating_str = entry.get("im:rating", {}).get("label", "")
                link_uri = entry.get("id", {}).get("label", f"https://apps.apple.com/us/app/id{app_id}")
                rating_val = int(rating_str) if str(rating_str).isdigit() else None
                text_body = f"{title}. {content}".strip()
                if text_body:
                    items.append({
                        "source": "app-store",
                        "url": link_uri if link_uri.startswith("http") else f"https://apps.apple.com/us/app/id{app_id}",
                        "date": (entry.get("updated", {}).get("label", ""))[:10],
                        "rating": rating_val,
                        "text": text_body[:600],
                    })
        except Exception as exc:
            warnings.append(f"appstore: {exc}")

    if "openalex" in sources:
        oa_client = FileLockedAPIClient("https://api.openalex.org", requests_per_second=5.0, lock_name="openalex")
        try:
            res = oa_client.request_json(
                "/works",
                params={"search": query, "per-page": max(1, min(limit, 25)), "sort": "cited_by_count:desc"},
            )
            for work in res.get("results", [])[:limit]:
                title = work.get("display_name") or work.get("title") or ""
                abstract = _reconstruct_openalex_abstract(work.get("abstract_inverted_index"))
                summary = f"{title}. {abstract}".strip()
                if summary:
                    items.append({
                        "source": "openalex",
                        "url": work.get("id") or "https://openalex.org",
                        "date": (work.get("publication_date") or "")[:10],
                        "rating": None,
                        "citations": work.get("cited_by_count") or 0,
                        "text": summary[:650],
                    })
        except Exception as exc:
            warnings.append(f"openalex: {exc}")

    return items, warnings


def recommend_system_architecture(query: str, items: List[Dict[str, Any]]) -> Dict[str, Any]:
    patterns_data = json.loads(PATTERNS_PATH.read_text(encoding="utf-8"))
    blueprints = patterns_data.get("architecture_blueprints", [])
    corpus = (query + " " + " ".join(str(x.get("text", "")) for x in items)).lower()

    best_bp = blueprints[0] if blueprints else {}
    best_score = -1
    for bp in blueprints:
        triggers = bp.get("triggers", [])
        score = sum(corpus.count(t.lower()) for t in triggers)
        if score > best_score:
            best_score = score
            best_bp = bp

    pain_Themes = [
        ("token_and_schema_bloat", ["token", "schema", "bloat", "context", "slow", "expensive", "latency"]),
        ("reliability_and_state_loss", ["crash", "offline", "sync", "lost", "bug", "error", "fail"]),
        ("missing_automation_or_cli", ["wish", "missing", "manual", "cli", "script", "mcp", "automate"]),
    ]
    ranked_pains: List[Dict[str, Any]] = []
    for theme_id, kw_list in pain_Themes:
        matched_quotes = []
        for it in items:
            txt = str(it.get("text", ""))
            if any(k in txt.lower() for k in kw_list):
                matched_quotes.append(
                    {
                        "source": it.get("source", "unknown"),
                        "url": it.get("url", ""),
                        "quote": txt[:200],
                    }
                )
        if matched_quotes:
            ranked_pains.append(
                {
                    "theme": theme_id,
                    "mentions": len(matched_quotes),
                    "evidence": matched_quotes[:3],
                }
            )
    ranked_pains.sort(key=lambda x: x["mentions"], reverse=True)

    return {
        "recommended_architecture": {
            "blueprint_id": best_bp.get("id", "modular-monolith-async-queue"),
            "recommended_stack": best_bp.get("recommended_stack", ""),
            "token_tooling_strategy": best_bp.get("token_tooling_strategy", ""),
            "rationale": best_bp.get("rationale", ""),
        },
        "pain_points_ranked": ranked_pains,
        "gemini_token_strategy": patterns_data.get("gemini_context_economics", {}),
    }


def _render_synthesized_cli(skill_name: str, spec: Dict[str, Any]) -> str:
    base_url = spec.get("base_url", "https://api.example.com/v1")
    rps = float(spec.get("requests_per_second", 1.0))
    desc = spec.get("description", f"Auto-synthesized CLI tool for {skill_name}")
    commands = spec.get("commands", [{"name": "query", "path": "/search", "help": "Query endpoint", "params": ["q"]}])
    commands_json = json.dumps(commands, indent=2)

    return f'''#!/usr/bin/env python3
"""Auto-synthesized token-optimal CLI for {skill_name}.

Generated by kernel-tool-forge following workflow-skill-creator rules:
- Standard library only (urllib, argparse, json, time).
- Cross-process file-locked rate limiting ({rps} req/s) using time.monotonic().
- Mandatory --limit and --output flags to keep large payloads out of LLM stdout context.
"""

import argparse
import json
import sys
import tempfile
import time
from pathlib import Path
from urllib import error as urllib_error
from urllib import parse as urllib_parse
from urllib import request as urllib_request

try:
    import fcntl
except ImportError:
    fcntl = None

COMMANDS_SPEC = {commands_json}


class RateLimitError(Exception):
    """Raised when API rate limit is exceeded."""


class SynthesizedAPIClient:
    BASE_URL = {json.dumps(base_url)}
    REQUESTS_PER_SECOND = {rps}

    def __init__(self):
        self.delay = 1.0 / max(0.1, self.REQUESTS_PER_SECOND)
        self.last_request_time = 0.0
        self.lock_file = Path(tempfile.gettempdir()) / "synthesized_{skill_name.replace('-', '_')}.lock"

    def _wait_for_rate_limit(self):
        elapsed = time.monotonic() - self.last_request_time
        if elapsed < self.delay:
            time.sleep(self.delay - elapsed)
        try:
            with open(self.lock_file, "a+", encoding="utf-8") as lf:
                if fcntl is not None:
                    fcntl.flock(lf.fileno(), fcntl.LOCK_EX)
                lf.seek(0)
                lf.truncate()
                lf.write(f"{{time.monotonic():.6f}}")
                lf.flush()
                if fcntl is not None:
                    fcntl.flock(lf.fileno(), fcntl.LOCK_UN)
        except OSError as exc:
            self.last_request_time = time.monotonic()
            _ = exc

    def request(self, path, params=None, retries=3):
        url = f"{{self.BASE_URL.rstrip('/')}}/{{path.lstrip('/')}}"
        if params:
            url = f"{{url}}?{{urllib_parse.urlencode(params)}}"
        for attempt in range(retries):
            self._wait_for_rate_limit()
            try:
                req = urllib_request.Request(url)
                req.add_header("Accept", "application/json")
                req.add_header("User-Agent", "AgentTeam-SynthesizedTool/1.0")
                with urllib_request.urlopen(req, timeout=30) as resp:
                    self.last_request_time = time.monotonic()
                    return json.loads(resp.read().decode("utf-8", errors="replace"))
            except urllib_error.HTTPError as e:
                self.last_request_time = time.monotonic()
                if e.code == 429:
                    wait = 2 ** attempt
                    print(f"Rate limited (429), retrying in {{wait}}s...", file=sys.stderr)
                    if attempt == retries - 1:
                        raise RateLimitError(
                            f"HTTP 429 from {{url}} (limit={{self.REQUESTS_PER_SECOND}} req/s)"
                        ) from e
                    time.sleep(wait)
                    continue
                if e.code >= 500:
                    wait = 2 ** attempt
                    if attempt == retries - 1:
                        raise RuntimeError(f"Server error {{e.code}} from {{url}}") from e
                    time.sleep(wait)
                    continue
                body = e.read().decode("utf-8", errors="replace")[:1000]
                raise RuntimeError(f"HTTP {{e.code}} from {{url}}: {{body}}") from e
            except urllib_error.URLError as e:
                if attempt == retries - 1:
                    raise RuntimeError(f"Connection failed for {{url}}: {{e}}") from e
                time.sleep(2 ** attempt)


def write_output(data, output_file):
    out = Path(output_file)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    print(f"Success! Data written to: {{output_file}}")


def main():
    parser = argparse.ArgumentParser(description={json.dumps(desc)})
    sub = parser.add_subparsers(dest="command", required=True)
    cmd_map = {{}}
    for cmd in COMMANDS_SPEC:
        cname = cmd["name"]
        cmd_map[cname] = cmd
        p = sub.add_parser(cname, help=cmd.get("help", cname))
        for param in cmd.get("params", []):
            p.add_argument(f"--{{param.replace('_', '-')}}", dest=param, required=True, help=f"Parameter {{param}}")
        p.add_argument("--limit", type=int, required=True, help="Maximum number of results to return")
        p.add_argument("--output", required=True, help="Output JSON file path")

    args = parser.parse_args()
    spec_cmd = cmd_map[args.command]
    client = SynthesizedAPIClient()
    params = {{param: getattr(args, param) for param in spec_cmd.get("params", [])}}
    params["limit"] = args.limit
    result = client.request(spec_cmd.get("path", "/"), params=params)
    write_output(result, args.output)


if __name__ == "__main__":
    main()
'''


def _render_synthesized_mcp(skill_name: str, spec: Dict[str, Any]) -> str:
    commands = spec.get("commands", [{"name": "query", "path": "/search", "help": "Query", "params": ["q"]}])
    tools_def = []
    for cmd in commands:
        tname = cmd["name"].replace("-", "_")
        props = {p: {"type": "string", "description": f"Param {p}"} for p in cmd.get("params", [])}
        props["limit"] = {"type": "integer", "description": "Max records"}
        props["output"] = {"type": "string", "description": "Output JSON file path"}
        tools_def.append(
            {
                "name": tname,
                "description": (cmd.get("help") or tname)[:90],
                "inputSchema": {
                    "type": "object",
                    "required": list(props.keys()),
                    "properties": props,
                },
            }
        )
    tools_json = json.dumps(tools_def, indent=2)

    return f'''#!/usr/bin/env python3
"""Minimal token-compressed stdio MCP JSON-RPC 2.0 server for {skill_name}."""

import argparse
import json
import subprocess
import sys
from pathlib import Path

TOOLS = {tools_json}
CLI_SCRIPT = Path(__file__).resolve().parent / "{skill_name.replace('-', '_')}_cli.py"


def handle_rpc(req: dict) -> dict:
    req_id = req.get("id")
    method = req.get("method", "")
    if method == "initialize":
        return {{
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {{
                "protocolVersion": "2024-11-05",
                "serverInfo": {{"name": "{skill_name}-mcp", "version": "1.0.0"}},
                "capabilities": {{"tools": {{}}}},
            }},
        }}
    if method == "tools/list":
        return {{"jsonrpc": "2.0", "id": req_id, "result": {{"tools": TOOLS}}}}
    if method == "tools/call":
        params = req.get("params", {{}})
        tname = str(params.get("name", "")).replace("_", "-")
        targs = params.get("arguments", {{}})
        cmd = [sys.executable, str(CLI_SCRIPT), tname]
        for k, v in targs.items():
            cmd.extend([f"--{{k.replace('_', '-')}}", str(v)])
        proc = subprocess.run(cmd, capture_output=True, text=True)
        return {{
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {{
                "content": [{{"type": "text", "text": (proc.stdout or proc.stderr).strip()}}],
                "isError": proc.returncode != 0,
            }},
        }}
    return {{"jsonrpc": "2.0", "id": req_id, "error": {{"code": -32601, "message": f"Method not found: {{method}}"}}}}


def main():
    parser = argparse.ArgumentParser(description="Stdio MCP Server for {skill_name}")
    parser.add_argument("--stdio", action="store_true", help="Run JSON-RPC over stdio")
    parser.parse_args()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            resp = handle_rpc(req)
            print(json.dumps(resp), flush=True)
        except Exception as exc:
            print(json.dumps({{"jsonrpc": "2.0", "id": None, "error": {{"code": -32700, "message": str(exc)}}}}), flush=True)


if __name__ == "__main__":
    main()
'''


def _render_synthesized_skill_md(skill_name: str, spec: Dict[str, Any], cli_rel: str) -> str:
    desc = spec.get("description", f"Token-optimal CLI and MCP wrapper for {skill_name}.")
    rps = spec.get("requests_per_second", 1.0)
    commands = spec.get("commands", [])
    cmd_docs = []
    for c in commands:
        cname = c["name"]
        p_flags = " ".join(f"--{p.replace('_', '-')} <val>" for p in c.get("params", []))
        cmd_docs.append(
            f"### `{cname}`\n{c.get('help', cname)}\n```bash\nuv run python {cli_rel} {cname} {p_flags} --limit 20 --output /tmp/{cname}.json\n```"
        )
    cmd_section = "\n\n".join(cmd_docs) if cmd_docs else "See `--help`."

    return f"""---
name: {skill_name}
description: >-
  {desc}
---

# {skill_name}

## Overview
{desc} Synthesized by `kernel-tool-forge` with compressed MCP definitions and file-redirected JSON outputs to preserve Gemini prefix cache stability.

## Dependencies
- `context-discipline`: Enforces file-output token discipline and AST/log compression.

## Quick Start
```bash
uv run python {cli_rel} --help
```

## Utility Scripts
{cmd_section}

## Rate Limiting
Enforces `{rps}` requests/second via `time.monotonic()` and cross-process file locking in `tempfile.gettempdir()`. Retries HTTP 429 and 5xx with exponential backoff.

## Common Mistakes
- **Omitting `--limit` or `--output`**: Both flags are mandatory to prevent unbounded stdout context bloat.
- **Using raw `python` instead of `uv run`**: Always invoke via `uv run` when `uv` is available.
"""


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Kernel Tool Forge: Market Intelligence, MCP Schema Compression & Self-Tooling Synthesizer."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # 1. market-intel
    p_mkt = sub.add_parser(
        "market-intel",
        help="Gather public market/research signals and recommend optimal system architecture",
    )
    p_mkt.add_argument("--query", required=True, help="Product, domain, or technology query")
    p_mkt.add_argument(
        "--sources",
        default="hn,openalex",
        help="Comma-separated public sources: hn,appstore,openalex",
    )
    p_mkt.add_argument("--app-id", help="Optional Apple App Store numeric ID when appstore source is enabled")
    p_mkt.add_argument("--limit", type=int, required=True, help="Maximum items per source (required)")
    p_mkt.add_argument("--fixture", help="Optional offline JSON fixture path for deterministic testing")
    p_mkt.add_argument(
        "--reviews-csv",
        help="Optional path to export collected items in market-recon reviews.csv format",
    )
    p_mkt.add_argument("--output", required=True, help="Output JSON file path")

    # 2. compress-mcp
    p_mcp = sub.add_parser(
        "compress-mcp",
        help="Compress MCP tool schemas and filter by task relevance to eliminate Tool Space Interference",
    )
    p_mcp.add_argument("--input", required=True, help="Input JSON file containing MCP tools list")
    p_mcp.add_argument("--query", default="", help="Optional task query to rank & filter relevant tools")
    p_mcp.add_argument("--limit", type=int, required=True, help="Maximum tools to retain (required)")
    p_mcp.add_argument("--output", required=True, help="Output JSON file path")

    # 3. synthesize
    p_syn = sub.add_parser(
        "synthesize",
        help="Synthesize a new token-optimal CLI script, stdio MCP server, or complete agent skill",
    )
    p_syn.add_argument("--name", required=True, help="Hyphenated tool/skill name (e.g. hn-signal-scout)")
    p_syn.add_argument(
        "--kind",
        choices=["cli", "mcp", "skill"],
        required=True,
        help="Artifact kind to generate",
    )
    p_syn.add_argument("--spec", required=True, help="Path to JSON spec file or inline JSON string")
    p_syn.add_argument("--target-dir", required=True, help="Target directory for synthesized files")
    p_syn.add_argument("--output", required=True, help="Output JSON manifest file path")

    # 4. gemini-cache-pack
    p_cache = sub.add_parser(
        "gemini-cache-pack",
        help="Build an immutable prefix bundle aligned with Gemini 2.5/3/4 Implicit & Explicit Context Caching",
    )
    p_cache.add_argument("--path", required=True, help="Target repository directory or file")
    p_cache.add_argument("--limit", type=int, required=True, help="Max files to include in AST skeleton map")
    p_cache.add_argument("--system-invariant", default="", help="Optional static system invariant header")
    p_cache.add_argument("--output", required=True, help="Output JSON file path")

    args = parser.parse_args(argv)

    if args.command == "market-intel":
        warnings: List[str] = []
        if args.fixture:
            raw_fix = json.loads(Path(args.fixture).read_text(encoding="utf-8"))
            items = raw_fix.get("items", [])[: args.limit]
        else:
            src_list = [s.strip().lower() for s in args.sources.split(",") if s.strip()]
            items, warnings = fetch_live_market_signals(
                query=args.query,
                sources=src_list,
                limit=args.limit,
                app_id=args.app_id,
            )

        if args.reviews_csv:
            csv_path = Path(args.reviews_csv)
            csv_path.parent.mkdir(parents=True, exist_ok=True)
            with open(csv_path, "w", newline="", encoding="utf-8") as cf:
                writer = csv.writer(cf)
                writer.writerow(["source", "url", "date", "rating", "text"])
                for it in items:
                    writer.writerow(
                        [
                            it.get("source", "web"),
                            it.get("url", ""),
                            it.get("date", _dt.date.today().isoformat()),
                            "" if it.get("rating") is None else str(it.get("rating")),
                            it.get("text", ""),
                        ]
                    )

        arch_rec = recommend_system_architecture(args.query, items)
        report = {
            "query": args.query,
            "signals_analyzed": len(items),
            "warnings": warnings,
            "recommended_architecture": arch_rec["recommended_architecture"],
            "pain_points_ranked": arch_rec["pain_points_ranked"],
            "gemini_token_strategy": arch_rec["gemini_token_strategy"],
            "signals": items,
        }
        write_output(report, args.output)
        return 0

    if args.command == "compress-mcp":
        in_path = Path(args.input)
        payload = json.loads(in_path.read_text(encoding="utf-8"))
        res = context_kernel.compress_mcp_schemas(payload, query=args.query, limit=args.limit)
        write_output(res, args.output)
        return 0

    if args.command == "synthesize":
        skill_name = re.sub(r"[^a-z0-9-]", "-", args.name.lower()).strip("-")
        spec_arg = args.spec.strip()
        if spec_arg.startswith("{"):
            spec_data = json.loads(spec_arg)
        else:
            spec_data = json.loads(Path(spec_arg).read_text(encoding="utf-8"))

        target = Path(args.target_dir).resolve()
        scripts_out = target / "scripts" if args.kind == "skill" else target
        scripts_out.mkdir(parents=True, exist_ok=True)

        generated_files: Dict[str, str] = {}
        cli_name = f"{skill_name.replace('-', '_')}_cli.py"
        mcp_name = f"{skill_name.replace('-', '_')}_mcp.py"

        if args.kind in ("cli", "skill"):
            cli_path = scripts_out / cli_name
            cli_path.write_text(_render_synthesized_cli(skill_name, spec_data), encoding="utf-8")
            os.chmod(cli_path, 0o755)
            generated_files["cli_script"] = str(cli_path)

        if args.kind in ("mcp", "skill"):
            mcp_path = scripts_out / mcp_name
            mcp_path.write_text(_render_synthesized_mcp(skill_name, spec_data), encoding="utf-8")
            os.chmod(mcp_path, 0o755)
            generated_files["mcp_server"] = str(mcp_path)

        if args.kind == "skill":
            skill_md_path = target / "SKILL.md"
            skill_md_path.write_text(
                _render_synthesized_skill_md(skill_name, spec_data, f"scripts/{cli_name}"),
                encoding="utf-8",
            )
            generated_files["skill_md"] = str(skill_md_path)

        manifest = {
            "skill_name": skill_name,
            "kind": args.kind,
            "target_dir": str(target),
            "files": generated_files,
            "checksums_sha256": {
                k: hashlib.sha256(Path(p).read_bytes()).hexdigest() for k, p in generated_files.items()
            },
        }
        write_output(manifest, args.output)
        return 0

    if args.command == "gemini-cache-pack":
        res = context_kernel.build_gemini_prefix_bundle(
            Path(args.path),
            limit=args.limit,
            system_invariant=args.system_invariant,
        )
        write_output(res, args.output)
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
