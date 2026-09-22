#!/usr/bin/env python3
"""
System One Fast Router for Agent Team Workflow using Gemini Flash.

Classifies incoming development requests into QUICK, FEATURE, or PROJECT
with strict schema validation, low latency (<300ms), and confidence scoring.
"""

import sys
import os
import json
import argparse
from typing import List, Optional
from enum import Enum
import requests
from pydantic import BaseModel, Field


class TierEnum(str, Enum):
    QUICK = "QUICK"
    FEATURE = "FEATURE"
    PROJECT = "PROJECT"


class RouteDecision(BaseModel):
    tier: TierEnum = Field(
        description="Classified tier: QUICK (bug fix, typo, single file), FEATURE (new user behavior, 2-15 files), PROJECT (new architecture, migration, many files)"
    )
    confidence: float = Field(
        ge=0.0,
        le=1.0,
        description="Confidence score between 0.0 and 1.0"
    )
    reason: str = Field(
        description="Concise rationale for why this tier was chosen"
    )
    parallel_safe: bool = Field(
        description="Whether backend and frontend work can proceed in parallel"
    )
    suggested_agents: List[str] = Field(
        description="List of subagent names to involve (e.g., implementer, backend-agent, frontend-agent, qa-agent, architect)"
    )


ROUTER_SYSTEM_INSTRUCTION = """
You are the System One routing engine for an Agent Team software engineering pipeline.
Your job is to rapidly and reliably classify the incoming task into one of three tiers:

1. PROJECT:
   - Requires new system architecture, new data models/database migrations, multi-subsystem changes, or multiple epics.
   - Example: "Build real-time chat with WebSockets and redis cluster", "Migrate auth system from session cookies to Cognito".

2. FEATURE:
   - Adds or changes user-observable behavior across multiple files (typically 2-15 files).
   - Has clear scope but touches API, UI, or multiple modules.
   - Example: "Add export to CSV button on orders table", "Implement reset password flow with email token".

3. QUICK:
   - Bug fix, typo fix, dependency bump, small refactor, single-file or single-function tweak.
   - Does not alter system architecture or broad user workflows.
   - Example: "Fix typo in login button text", "Handle null pointer in date formatter", "Update package version".

Classification Rule:
- When torn between two tiers, pick the smaller one.
- Set parallel_safe to true ONLY if backend API and frontend UI can be cleanly decoupled with a contract.
"""


def get_gemini_api_key(explicit_key: Optional[str] = None) -> Optional[str]:
    """Retrieve Gemini API key from arguments, environment, or .env file."""
    if explicit_key:
        return explicit_key

    for env_var in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
        key = os.getenv(env_var)
        if key:
            return key

    # Check .env file in parent directories
    current_dir = os.path.abspath(os.path.dirname(__file__))
    while True:
        dotenv_path = os.path.join(current_dir, ".env")
        if os.path.isfile(dotenv_path):
            try:
                with open(dotenv_path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("#") or not line:
                            continue
                        if line.startswith("GEMINI_API_KEY=") or line.startswith("GOOGLE_API_KEY="):
                            _, val = line.split("=", 1)
                            return val.strip().strip("'\"")
            except Exception:
                pass
        parent = os.path.dirname(current_dir)
        if parent == current_dir:
            break
        current_dir = parent

    return None


def route_request(
    prompt: str,
    api_key: str,
    model: str = "gemini-2.5-flash",
    timeout: float = 10.0
) -> RouteDecision:
    """Call Gemini Flash API with structured output schema to classify the prompt."""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"

    # JSON Schema definition for Gemini Structured Outputs
    response_schema = {
        "type": "OBJECT",
        "properties": {
            "tier": {
                "type": "STRING",
                "enum": ["QUICK", "FEATURE", "PROJECT"]
            },
            "confidence": {
                "type": "NUMBER"
            },
            "reason": {
                "type": "STRING"
            },
            "parallel_safe": {
                "type": "BOOLEAN"
            },
            "suggested_agents": {
                "type": "ARRAY",
                "items": {
                    "type": "STRING"
                }
            }
        },
        "required": ["tier", "confidence", "reason", "parallel_safe", "suggested_agents"]
    }

    payload = {
        "contents": [
            {
                "parts": [
                    {"text": f"Task request to classify:\n{prompt}"}
                ]
            }
        ],
        "systemInstruction": {
            "parts": [
                {"text": ROUTER_SYSTEM_INSTRUCTION}
            ]
        },
        "generationConfig": {
            "temperature": 0.0,
            "responseMimeType": "application/json",
            "responseSchema": response_schema
        }
    }

    headers = {"Content-Type": "application/json"}
    resp = requests.post(url, headers=headers, json=payload, timeout=timeout)

    if resp.status_code != 200:
        raise RuntimeError(f"Gemini API error (status {resp.status_code}): {resp.text}")

    data = resp.json()
    try:
        raw_text = data["candidates"][0]["content"]["parts"][0]["text"]
        return RouteDecision.model_validate_json(raw_text)
    except (KeyError, IndexError, ValueError) as err:
        raise RuntimeError(f"Failed to parse structured response from Gemini: {err}\nRaw: {data}")


def main():
    parser = argparse.ArgumentParser(description="System One Router using Gemini Flash")
    parser.add_argument("request", nargs="?", help="Task request string to classify")
    parser.add_argument("--model", default="gemini-2.5-flash", help="Gemini model to use (default: gemini-2.5-flash)")
    parser.add_argument("--api-key", help="Gemini/Google API key (or set GEMINI_API_KEY env var)")
    parser.add_argument("--format", choices=["json", "line"], default="json", help="Output format (json or single line)")
    args = parser.parse_args()

    request_text = args.request
    if not request_text:
        if not sys.stdin.isatty():
            request_text = sys.stdin.read().strip()
        else:
            parser.print_help()
            sys.exit(1)

    api_key = get_gemini_api_key(args.api_key)
    if not api_key:
        sys.stderr.write(
            "Error: GEMINI_API_KEY or GOOGLE_API_KEY is not set.\n"
            "Set it via environment variable, --api-key argument, or in a .env file.\n"
        )
        sys.exit(2)

    try:
        decision = route_request(request_text, api_key=api_key, model=args.model)
        if args.format == "json":
            print(decision.model_dump_json(indent=2))
        else:
            agents = ",".join(decision.suggested_agents)
            parallel = "PARALLEL" if decision.parallel_safe else "SERIAL"
            print(f"{decision.tier.value} {decision.confidence:.2f} {parallel} [{agents}] - {decision.reason}")
    except Exception as e:
        sys.stderr.write(f"Routing failed: {e}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
