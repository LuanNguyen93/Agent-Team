---
name: kernel-tool-forge
description: >-
  Synthesizes token-optimal CLI scripts, MCP JSON-RPC servers, and agent skills on-demand, compresses MCP tool schemas to eliminate Tool Space Interference, structures Gemini prefix-stable context caches, and runs live public market and research reconnaissance (Hacker News, Apple App Store RSS, OpenAlex) to recommend optimal system architectures.
when_to_use: >-
  Use when designing or upgrading agent tools, compressing bloated MCP schemas, optimizing Gemini context caching, synthesizing new CLI/MCP wrappers on the fly, or running market and scientific reconnaissance before choosing a system architecture.
---

# Kernel Tool Forge (Self-Tooling ACI & Market Recon Kernel)

## Overview

`kernel-tool-forge` operationalizes 2025–2026 research on **Gemini 2.5/3/4 Context Caching**, **MCP Schema Compression (ScaleMCP / Tool Space Interference elimination)**, **Self-Tooling Agents (STA)**, and **Evidence-Based Market Reconnaissance** into one unified kernel skill:

1. **Prefix-Stable Gemini Caching (`gemini-cache-pack`)**: Separates immutable static prefixes ($\ge 4,096$ tokens: system invariants + AST repository skeleton map) from mutable tail turns (tool outputs redirected to files), maximizing 75%–90% implicit cache savings and avoiding micro-turn cache invalidation ($>2,050$ token batch awareness).
2. **Dynamic MCP Schema Compression (`compress-mcp`)**: Strips verbose prose, examples, and redundant JSON Schema metadata while ranking top-$K$ tools for the active query, cutting schema overhead by 80%–95%.
3. **Self-Tooling Synthesis (`synthesize`)**: Dynamically generates zero-dependency Python stdlib CLI tools (`argparse` + `urllib` + `time.monotonic()` file-locked rate limiting + mandatory `--output`), lightweight stdio MCP JSON-RPC 2.0 servers, or complete `SKILL.md` bundles.
4. **Market & Research Intelligence (`market-intel`)**: Queries public Hacker News Algolia, Apple App Store Customer Reviews RSS, and OpenAlex scholarly works to rank real user pain points, export `reviews.csv` for `market-recon`, and map domain signals to the most token- and cost-efficient system architecture.

## Dependencies

Following Rule 1 of `workflow-skill-creator`, this skill integrates with and references existing installed skills rather than reimplementing their workflows:

- **`market-recon`**: Used after `market-intel --reviews-csv docs/reviews.csv` to run `scripts/reviews.py` for verbatim review ranking (`docs/feedback.md`), screen/flow decomposition (`S01..Snn`, `F01..Fnn` in `docs/recon.md`), and feature parity tracking (`docs/features.csv`).
- **`context-discipline`**: Governs scope boundaries (`.agent-team.json`), subagent folding, and surgical AST extraction via `scripts/context_kernel.py`.
- **`literature-search-openalex`**: Referenced when deeper bibliometric citation graphs, author h-index lookups, or full-text PDF downloads are needed beyond rapid architectural reconnaissance.

## Quick Start

```bash
# 1. Run live market + scholarly recon and get an architecture recommendation
uv run python plugins/agent-team/skills/kernel-tool-forge/scripts/kernel_forge.py market-intel \
  --query "MCP agent token optimization" \
  --sources hn,openalex \
  --limit 10 \
  --reviews-csv /tmp/reviews.csv \
  --output /tmp/market_intel.json

# 2. Compress a bloated MCP tools/list schema file by 80-95%
uv run python plugins/agent-team/skills/kernel-tool-forge/scripts/kernel_forge.py compress-mcp \
  --input /tmp/raw_mcp_tools.json \
  --query "issue search" \
  --limit 5 \
  --output /tmp/compressed_mcp.json

# 3. Synthesize a new CLI + MCP server + SKILL.md on the fly
uv run python plugins/agent-team/skills/kernel-tool-forge/scripts/kernel_forge.py synthesize \
  --name hn-signal-scout \
  --kind skill \
  --spec '{"base_url":"https://hn.algolia.com/api/v1","requests_per_second":2,"description":"Fetch HN stories","commands":[{"name":"search-stories","path":"/search","help":"Search HN","params":["query"]}]}' \
  --target-dir /tmp/hn-signal-scout \
  --output /tmp/synthesis_manifest.json

# 4. Pack an immutable Gemini prefix cache bundle for the current repository
uv run python plugins/agent-team/skills/kernel-tool-forge/scripts/kernel_forge.py gemini-cache-pack \
  --path plugins/agent-team/scripts \
  --limit 25 \
  --output /tmp/gemini_prefix.json
```

## Utility Scripts

All subcommands in `scripts/kernel_forge.py` write structured JSON to `--output` and print only a short confirmation line to `stdout` (Rule 4: Default to File Output).

### `market-intel`
Queries public market and research APIs, ranks pain points, exports optional `reviews.csv` for `market-recon/scripts/reviews.py`, and recommends an optimal system architecture from `references/architecture_patterns.json`.
- `--query <str>` (required): Product, competitor, or technical topic.
- `--sources <str>` (optional, default `hn,openalex`): Comma-separated list of `hn`, `appstore`, `openalex`.
- `--app-id <str>` (optional): Apple App Store ID when `appstore` is included in `--sources`.
- `--limit <int>` (required): Max items per source.
- `--reviews-csv <path>` (optional): Writes `source,url,date,rating,text` CSV for `market-recon`.
- `--output <path>` (required): Output JSON file path.

### `compress-mcp`
Eliminates Tool Space Interference (TSI) by filtering and compressing MCP tool schemas. Also available directly on the core ACI kernel via `python3 plugins/agent-team/scripts/context_kernel.py compress-mcp`.
- `--input <path>` (required): Path to JSON file containing MCP `tools` array.
- `--query <str>` (optional): Task keyword filter to rank and retain matching tools.
- `--limit <int>` (required): Max tools to keep.
- `--output <path>` (required): Output JSON file path.

### `synthesize`
Self-Tooling Agent (STA) generator that emits a standalone Python CLI script (`<name>_cli.py`), a stdio MCP JSON-RPC 2.0 server (`<name>_mcp.py`), and/or a complete `SKILL.md`.
- `--name <str>` (required): Hyphenated tool or skill name.
- `--kind <cli|mcp|skill>` (required): Artifact bundle to generate.
- `--spec <path|json>` (required): JSON specification with `base_url`, `requests_per_second`, `description`, and `commands`.
- `--target-dir <path>` (required): Destination directory.
- `--output <path>` (required): Output JSON manifest path.

### `gemini-cache-pack`
Constructs a deterministic, SHA256-keyed static prefix combining system invariants and AST skeletons from `context_kernel.py` to maximize Gemini Implicit/Explicit Context Caching.
- `--path <path>` (required): Target directory or file.
- `--limit <int>` (required): Max files to skeletonize.
- `--system-invariant <str>` (optional): Static system prompt rules to front-load.
- `--output <path>` (required): Output JSON bundle path.

## Rate Limiting

`scripts/kernel_forge.py` and every CLI tool it synthesizes enforce strict cross-process rate limiting via `time.monotonic()` and `fcntl.flock` lockfiles in `tempfile.gettempdir()`:

| Service | Documented Limit | Enforced Client Rate |
|---|---|---|
| Hacker News Algolia API | ~2.7 req/s (10,000/hr) | `2.0 req/s` (`0.5s` delay) |
| OpenAlex API | `10.0 req/s` | `5.0 req/s` (`0.2s` delay) |
| Apple Customer Reviews RSS | ~20 req/min | `1.0 req/s` (`1.0s` delay) |
| Default Synthesized Tool | 1.0 req/s fallback | `1.0 req/s` (`1.0s` delay) |

On HTTP `429` or `5xx`, the client logs retry progress to `stderr` and applies exponential backoff (`2**attempt` seconds), raising `RateLimitError` if retries are exhausted. On HTTP `4xx`, it reads and includes up to 1,000 characters of the response body for self-correction.

## Common Mistakes

1. **Dumping raw API or MCP payloads to `stdout`**: Never print multi-kilobyte JSON to `stdout`. Always pass `--output /tmp/result.json` and inspect only the required fields.
2. **Mutating the static prefix mid-session**: Injecting dynamic timestamps or tool outputs at the top of the prompt invalidates Gemini's 4,096-token implicit cache prefix. Keep the AST skeleton and system invariants at the front and append dynamic tool outputs at the tail.
3. **Loading all MCP servers unfiltered**: Passing >20 raw MCP tool schemas degrades tool-calling accuracy. Run `compress-mcp` first or synthesize a lightweight CLI script via `synthesize`.
