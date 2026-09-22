#!/usr/bin/env python3
"""Unit tests for System One Fast Router (fast_router.py)."""

import unittest
from unittest.mock import patch, MagicMock
import os
import sys

# Add parent directory to path to import fast_router
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
import fast_router
from fast_router import RouteDecision, TierEnum, get_gemini_api_key, route_request


class TestFastRouter(unittest.TestCase):

    def test_pydantic_schema_validation(self):
        """Verify that RouteDecision correctly parses and validates structured data."""
        data = {
            "tier": "QUICK",
            "confidence": 0.95,
            "reason": "Single file typo fix",
            "parallel_safe": False,
            "suggested_agents": ["implementer"]
        }
        decision = RouteDecision.model_validate(data)
        self.assertEqual(decision.tier, TierEnum.QUICK)
        self.assertAlmostEqual(decision.confidence, 0.95)
        self.assertFalse(decision.parallel_safe)
        self.assertEqual(decision.suggested_agents, ["implementer"])

    def test_invalid_tier_fails_validation(self):
        """Verify that an invalid tier raises ValidationError."""
        data = {
            "tier": "UNKNOWN_TIER",
            "confidence": 0.95,
            "reason": "Test",
            "parallel_safe": False,
            "suggested_agents": []
        }
        with self.assertRaises(Exception):
            RouteDecision.model_validate(data)

    def test_get_api_key_from_explicit_argument(self):
        """Verify explicit argument takes precedence."""
        self.assertEqual(get_gemini_api_key("explicit-key-123"), "explicit-key-123")

    @patch.dict(os.environ, {"GEMINI_API_KEY": "env-gemini-key"})
    def test_get_api_key_from_env(self):
        """Verify retrieval from environment variable."""
        self.assertEqual(get_gemini_api_key(), "env-gemini-key")

    @patch("requests.post")
    def test_route_request_success(self, mock_post):
        """Verify that route_request correctly parses Gemini API response."""
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {
                                "text": '{"tier":"FEATURE","confidence":0.88,"reason":"New endpoint touching 3 files","parallel_safe":true,"suggested_agents":["backend-agent","frontend-agent"]}'
                            }
                        ]
                    }
                }
            ]
        }
        mock_post.return_value = mock_response

        decision = route_request("Add user avatar upload API and UI", api_key="fake-key")
        self.assertEqual(decision.tier, TierEnum.FEATURE)
        self.assertAlmostEqual(decision.confidence, 0.88)
        self.assertTrue(decision.parallel_safe)
        self.assertEqual(decision.suggested_agents, ["backend-agent", "frontend-agent"])


if __name__ == "__main__":
    unittest.main()
