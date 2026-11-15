import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

from _load import ROOT  # noqa: E402

SKILL_DIR = Path(ROOT) / "skills" / "kernel-tool-forge"
SCRIPT_PATH = SKILL_DIR / "scripts" / "kernel_forge.py"
SKILL_MD_PATH = SKILL_DIR / "SKILL.md"


class TestKernelToolForge(unittest.TestCase):
    def test_skill_files_and_frontmatter_exist(self):
        self.assertTrue(SKILL_MD_PATH.is_file(), f"Missing {SKILL_MD_PATH}")
        self.assertTrue(SCRIPT_PATH.is_file(), f"Missing {SCRIPT_PATH}")
        text = SKILL_MD_PATH.read_text(encoding="utf-8")
        lines = text.splitlines()
        self.assertLessEqual(len(lines), 500, "SKILL.md must be <= 500 lines")
        self.assertTrue(text.startswith("---\nname: kernel-tool-forge\n"))
        self.assertIn("## Overview", text)
        self.assertIn("## Dependencies", text)
        self.assertIn("## Quick Start", text)
        self.assertIn("## Utility Scripts", text)
        self.assertIn("## Rate Limiting", text)
        self.assertIn("## Common Mistakes", text)
        # Rule 1: Must reference existing skills
        self.assertIn("market-recon", text)
        self.assertIn("context-discipline", text)
        self.assertIn("literature-search-openalex", text)

    def test_cli_compress_mcp_subcommand_writes_file_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            in_file = Path(tmp) / "raw_mcp.json"
            out_file = Path(tmp) / "compressed_mcp.json"
            raw_tools = {
                "tools": [
                    {
                        "name": f"github_issue_action_{i}",
                        "description": "Manages GitHub repository issues and pull requests with extensive metadata. " * 15,
                        "inputSchema": {
                            "type": "object",
                            "required": ["repo", "issue_number"],
                            "properties": {
                                "repo": {"type": "string", "description": "Repository full name owner/repo. " * 8},
                                "issue_number": {"type": "integer", "description": "Issue number ID. " * 8},
                            },
                        },
                    }
                    for i in range(12)
                ]
            }
            in_file.write_text(json.dumps(raw_tools), encoding="utf-8")
            proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "compress-mcp",
                    "--input",
                    str(in_file),
                    "--query",
                    "github issue",
                    "--limit",
                    "4",
                    "--output",
                    str(out_file),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
            self.assertIn("Success! Data written to:", proc.stdout)
            self.assertTrue(out_file.is_file())
            data = json.loads(out_file.read_text(encoding="utf-8"))
            self.assertEqual(data["tools_retained"], 4)
            self.assertGreater(data["reduction_pct"], 75.0)

    def test_cli_synthesize_generates_working_cli_mcp_and_skill(self):
        with tempfile.TemporaryDirectory() as tmp:
            spec_file = Path(tmp) / "spec.json"
            out_manifest = Path(tmp) / "manifest.json"
            target_dir = Path(tmp) / "generated_tool"
            spec = {
                "base_url": "https://hn.algolia.com/api/v1",
                "requests_per_second": 2,
                "description": "Search Hacker News stories for technical market signals.",
                "commands": [
                    {
                        "name": "search-stories",
                        "path": "/search",
                        "help": "Search stories by query",
                        "params": ["query"],
                    }
                ],
            }
            spec_file.write_text(json.dumps(spec), encoding="utf-8")

            # 1. Synthesize full skill (which includes CLI script + MCP server + SKILL.md)
            proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "synthesize",
                    "--name",
                    "hn-signal-scout",
                    "--kind",
                    "skill",
                    "--spec",
                    str(spec_file),
                    "--target-dir",
                    str(target_dir),
                    "--output",
                    str(out_manifest),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
            manifest = json.loads(out_manifest.read_text(encoding="utf-8"))
            self.assertEqual(manifest["skill_name"], "hn-signal-scout")
            gen_cli = Path(manifest["files"]["cli_script"])
            gen_mcp = Path(manifest["files"]["mcp_server"])
            gen_skill = Path(manifest["files"]["skill_md"])
            self.assertTrue(gen_cli.is_file())
            self.assertTrue(gen_mcp.is_file())
            self.assertTrue(gen_skill.is_file())

            # Verify generated CLI --help runs cleanly and requires --limit and --output
            help_proc = subprocess.run(
                [sys.executable, str(gen_cli), "search-stories", "--help"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(help_proc.returncode, 0, help_proc.stderr)
            self.assertIn("--limit", help_proc.stdout)
            self.assertIn("--output", help_proc.stdout)

            # Verify generated MCP server responds to JSON-RPC initialize & tools/list
            rpc_input = (
                json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
                + "\n"
                + json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
                + "\n"
            )
            mcp_proc = subprocess.run(
                [sys.executable, str(gen_mcp), "--stdio"],
                input=rpc_input,
                capture_output=True,
                text=True,
            )
            self.assertEqual(mcp_proc.returncode, 0, mcp_proc.stderr)
            rpc_lines = [json.loads(line) for line in mcp_proc.stdout.strip().splitlines() if line.strip()]
            self.assertEqual(len(rpc_lines), 2)
            self.assertEqual(rpc_lines[0]["id"], 1)
            tools_list = rpc_lines[1]["result"]["tools"]
            self.assertTrue(any(t["name"] == "search_stories" for t in tools_list))

    def test_cli_market_intel_offline_fixture_and_architecture_advisor(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture_file = Path(tmp) / "fixture_signals.json"
            reviews_csv = Path(tmp) / "reviews.csv"
            out_file = Path(tmp) / "market_report.json"

            fixture_data = {
                "items": [
                    {
                        "source": "hacker-news",
                        "url": "https://news.ycombinator.com/item?id=400001",
                        "date": "2026-10-15",
                        "rating": 2,
                        "text": "The MCP tool schemas are way too slow and expensive. Loading 20 servers eats 25k tokens before the agent writes a line of code. Wish there was automatic schema compression and local CLI synthesis.",
                    },
                    {
                        "source": "app-store",
                        "url": "https://itunes.apple.com/us/review?id=400002",
                        "date": "2026-10-20",
                        "rating": 1,
                        "text": "App crashes on offline sync and loses state when switching tabs. Too expensive subscription for broken reliability.",
                    },
                    {
                        "source": "openalex",
                        "url": "https://openalex.org/W400003",
                        "date": "2026-09-12",
                        "rating": None,
                        "text": "Prefix-stable context caching and AST skeletonization reduce multi-turn agent token consumption by 84% without accuracy loss.",
                    },
                ]
            }
            fixture_file.write_text(json.dumps(fixture_data), encoding="utf-8")

            proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "market-intel",
                    "--query",
                    "MCP agent token optimization local-first",
                    "--limit",
                    "10",
                    "--fixture",
                    str(fixture_file),
                    "--reviews-csv",
                    str(reviews_csv),
                    "--output",
                    str(out_file),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
            self.assertTrue(out_file.is_file())
            self.assertTrue(reviews_csv.is_file())

            report = json.loads(out_file.read_text(encoding="utf-8"))
            self.assertIn("recommended_architecture", report)
            self.assertIn("pain_points_ranked", report)
            self.assertIn("gemini_token_strategy", report)
            self.assertIn("hydrogen_flash_pro_tiering", report["gemini_token_strategy"])
            tiering = report["gemini_token_strategy"]["hydrogen_flash_pro_tiering"]
            self.assertIn("flash", tiering["tier_1_triage_and_gates"].lower())
            self.assertIn("hydrogen", tiering["tier_2_core_execution"].lower())
            self.assertIn("pro", tiering["tier_3_architecture_and_rca"].lower())
            self.assertGreaterEqual(report["signals_analyzed"], 3)


if __name__ == "__main__":
    unittest.main()
