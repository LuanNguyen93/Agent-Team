#!/usr/bin/env python3
"""Unit tests for System One Fast Router (fast_router.py)."""

import json
import os
import re
import sys
import tempfile
import unittest
from unittest.mock import patch

# Add parent directory to path to import fast_router
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
import fast_router
from fast_router import RouteDecision, format_line, get_gemini_api_key, route_request

# Same pattern tier-scan.js uses to recognise a tier announcement.
TIER_RE = re.compile(r"`(QUICK|FEATURE|PROJECT)`\s*[-–—]", re.IGNORECASE)


def gemini_reply(decision: dict) -> dict:
    return {"candidates": [{"content": {"parts": [{"text": json.dumps(decision)}]}}]}


class TestRouteDecision(unittest.TestCase):

    def test_valid_decision_parses(self):
        decision = RouteDecision.from_dict({
            "tier": "QUICK", "confidence": 0.95, "reason": "Single file typo fix",
            "parallel_safe": False, "suggested_agents": ["implementer"],
        })
        self.assertEqual(decision.tier, "QUICK")
        self.assertAlmostEqual(decision.confidence, 0.95)
        self.assertFalse(decision.parallel_safe)
        self.assertEqual(decision.suggested_agents, ["implementer"])

    def test_invalid_tier_fails(self):
        with self.assertRaises(ValueError):
            RouteDecision.from_dict({"tier": "UNKNOWN_TIER", "confidence": 0.9})

    def test_out_of_range_confidence_is_clamped_not_fatal(self):
        self.assertAlmostEqual(RouteDecision.from_dict({"tier": "QUICK", "confidence": 85}).confidence, 0.85)
        self.assertEqual(RouteDecision.from_dict({"tier": "QUICK", "confidence": 1000}).confidence, 1.0)
        self.assertEqual(RouteDecision.from_dict({"tier": "QUICK", "confidence": -0.3}).confidence, 0.0)

    def test_unknown_agents_are_dropped(self):
        decision = RouteDecision.from_dict({
            "tier": "FEATURE", "confidence": 0.9,
            "suggested_agents": ["backend-agent", "backend-implementer", "qa-agent"],
        })
        self.assertEqual(decision.suggested_agents, ["backend-implementer"])

    def test_line_format_is_recognised_by_tier_scan(self):
        line = format_line(RouteDecision("FEATURE", 0.88, "New endpoint", True, ["planner"]))
        self.assertRegex(line, TIER_RE)


class TestApiKey(unittest.TestCase):

    def test_explicit_argument_wins(self):
        self.assertEqual(get_gemini_api_key("explicit-key-123"), "explicit-key-123")

    @patch.dict(os.environ, {"GEMINI_API_KEY": "env-gemini-key"})
    def test_from_env(self):
        self.assertEqual(get_gemini_api_key(), "env-gemini-key")

    def test_from_project_dotenv(self):
        with tempfile.TemporaryDirectory() as project:
            with open(os.path.join(project, ".env"), "w", encoding="utf-8") as f:
                f.write("# comment\nGEMINI_API_KEY='dotenv-key'\n")
            env = {k: v for k, v in os.environ.items() if k not in ("GEMINI_API_KEY", "GOOGLE_API_KEY")}
            env["CLAUDE_PROJECT_DIR"] = project
            with patch.dict(os.environ, env, clear=True):
                self.assertEqual(get_gemini_api_key(), "dotenv-key")


class TestRouteRequest(unittest.TestCase):

    @patch("fast_router._post_json")
    def test_success(self, mock_post):
        mock_post.return_value = gemini_reply({
            "tier": "FEATURE", "confidence": 0.88, "reason": "New endpoint touching 3 files",
            "parallel_safe": True, "suggested_agents": ["backend-implementer", "frontend-implementer"],
        })
        decision = route_request("Add user avatar upload API and UI", api_key="fake-key")
        self.assertEqual(decision.tier, "FEATURE")
        self.assertTrue(decision.parallel_safe)
        self.assertEqual(decision.suggested_agents, ["backend-implementer", "frontend-implementer"])

    @patch("fast_router._post_json")
    def test_key_is_sent_in_header_not_url(self, mock_post):
        mock_post.return_value = gemini_reply({"tier": "QUICK", "confidence": 0.9})
        route_request("fix typo", api_key="secret-key")
        url, _payload, headers, _timeout = mock_post.call_args[0]
        self.assertNotIn("secret-key", url)
        self.assertEqual(headers["x-goog-api-key"], "secret-key")

    @patch("fast_router._post_json")
    def test_network_error_does_not_leak_key(self, mock_post):
        mock_post.side_effect = fast_router.urllib.error.URLError("timed out")
        with self.assertRaises(RuntimeError) as ctx:
            route_request("fix typo", api_key="secret-key")
        self.assertNotIn("secret-key", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
