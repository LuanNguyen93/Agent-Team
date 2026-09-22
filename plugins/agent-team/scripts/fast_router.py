#!/usr/bin/env python3
"""
System One Fast Router for Agent Team Workflow using Gemini Flash.

Classifies incoming development requests into QUICK, FEATURE, or PROJECT
with schema-constrained output and a confidence score.

Standard library only: this ships inside a plugin and runs on whatever Python
the user has, so it cannot assume `requests` or `pydantic` are installed.

Exit codes: 0 routed, 1 routing failed, 2 no API key (absent, not a result).
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass, field
from typing import List, Optional

TIERS = ("QUICK", "FEATURE", "PROJECT")

# Agents that exist in this plugin. Anything else the model suggests is dropped,
# because a suggestion that is followed spawns a subagent_type that is not there.
KNOWN_AGENTS = (
    "analyst", "pm", "architect", "ux-designer", "planner", "implementer",
    "backend-implementer", "frontend-implementer", "reviewer", "qa-verifier",
    "debugger",
)


@dataclass
class RouteDecision:
    tier: str
    confidence: float
    reason: str
    parallel_safe: bool
    suggested_agents: List[str] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict) -> "RouteDecision":
        tier = str(data.get("tier", "")).upper()
        if tier not in TIERS:
            raise ValueError(f"unknown tier: {data.get('tier')!r}")
        try:
            confidence = float(data.get("confidence", 0.0))
        except (TypeError, ValueError):
            confidence = 0.0
        # A model that answers 85 meant 0.85; one that answers 1.2 meant "sure".
        if confidence > 1.0:
            confidence = confidence / 100.0 if confidence <= 100.0 else 1.0
        confidence = min(max(confidence, 0.0), 1.0)
        agents = [a for a in data.get("suggested_agents") or [] if a in KNOWN_AGENTS]
        return cls(
            tier=tier,
            confidence=confidence,
            reason=str(data.get("reason", "")).strip(),
            parallel_safe=bool(data.get("parallel_safe", False)),
            suggested_agents=agents,
        )


ROUTER_SYSTEM_INSTRUCTION = f"""
You are the System One routing engine for an Agent Team software engineering pipeline.
Classify the incoming task into one of three tiers. Ask these in order; the first yes wins:

1. PROJECT: does it need new architecture, a new data model or migration, or more than one epic?
   Example: "Build real-time chat with WebSockets and a redis cluster".
2. FEATURE: does it add or change observable behaviour a user could describe?
   File count does not decide this: a new validation rule in one file is still FEATURE.
   Example: "Add export to CSV button on orders table", "Reject emails without a TLD at signup".
3. QUICK: everything else - bug fix, typo, dependency bump, rename, refactor with no behaviour change.
   Example: "Fix typo in login button text", "Handle null in date formatter".

Rules:
- When torn between two tiers, pick the smaller one.
- confidence is a number between 0.0 and 1.0.
- parallel_safe is true ONLY if backend and frontend work can be decoupled behind a contract.
- suggested_agents may only contain: {", ".join(KNOWN_AGENTS)}.
"""

RESPONSE_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "tier": {"type": "STRING", "enum": list(TIERS)},
        "confidence": {"type": "NUMBER", "minimum": 0.0, "maximum": 1.0},
        "reason": {"type": "STRING"},
        "parallel_safe": {"type": "BOOLEAN"},
        "suggested_agents": {
            "type": "ARRAY",
            "items": {"type": "STRING", "enum": list(KNOWN_AGENTS)},
        },
    },
    "required": ["tier", "confidence", "reason", "parallel_safe", "suggested_agents"],
}


def _read_dotenv_key(path: str) -> Optional[str]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith(("GEMINI_API_KEY=", "GOOGLE_API_KEY=")):
                    return line.split("=", 1)[1].strip().strip("'\"") or None
    except OSError:
        pass
    return None


def get_gemini_api_key(explicit_key: Optional[str] = None) -> Optional[str]:
    """Retrieve the key from the argument, the environment, or the project's .env.

    Only the project directory's own .env is read. Walking upward from here
    would, once installed, walk out of the plugin cache into the user's home.
    """
    if explicit_key:
        return explicit_key

    for env_var in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
        key = os.getenv(env_var)
        if key:
            return key

    project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
    return _read_dotenv_key(os.path.join(project_dir, ".env"))


def _post_json(url: str, payload: dict, headers: dict, timeout: float) -> dict:
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST"
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def route_request(
    prompt: str,
    api_key: str,
    model: str = "gemini-2.5-flash",
    timeout: float = 10.0,
) -> RouteDecision:
    """Call Gemini with a structured-output schema to classify the prompt."""
    # The key goes in a header, never the URL: URLs end up in error messages,
    # and error messages end up in an agent's transcript.
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    headers = {"Content-Type": "application/json", "x-goog-api-key": api_key}
    payload = {
        "contents": [{"parts": [{"text": f"Task request to classify:\n{prompt}"}]}],
        "systemInstruction": {"parts": [{"text": ROUTER_SYSTEM_INSTRUCTION}]},
        "generationConfig": {
            "temperature": 0.0,
            "responseMimeType": "application/json",
            "responseSchema": RESPONSE_SCHEMA,
        },
    }

    try:
        data = _post_json(url, payload, headers, timeout)
    except urllib.error.HTTPError as err:
        body = err.read().decode("utf-8", "replace")[:500]
        raise RuntimeError(f"Gemini API error (status {err.code}): {body}") from None
    except (urllib.error.URLError, TimeoutError, OSError) as err:
        reason = getattr(err, "reason", err)
        raise RuntimeError(f"Gemini API unreachable: {reason}") from None

    try:
        raw_text = data["candidates"][0]["content"]["parts"][0]["text"]
        return RouteDecision.from_dict(json.loads(raw_text))
    except (KeyError, IndexError, TypeError, ValueError) as err:
        raise RuntimeError(f"Failed to parse structured response from Gemini: {err}") from None


def format_line(decision: RouteDecision) -> str:
    """The announce line workflow-router expects, which tier-scan.js recognises."""
    agents = ",".join(decision.suggested_agents) or "-"
    parallel = "parallel" if decision.parallel_safe else "serial"
    return (
        f"`{decision.tier}` — {decision.reason} "
        f"(confidence {decision.confidence:.2f}, {parallel}, agents: {agents})"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="System One Router using Gemini Flash")
    parser.add_argument("request", nargs="?", help="Task request string to classify")
    parser.add_argument("--model", default="gemini-2.5-flash", help="Gemini model to use")
    parser.add_argument("--api-key", help="Gemini/Google API key (or set GEMINI_API_KEY)")
    parser.add_argument("--format", choices=["json", "line"], default="json")
    args = parser.parse_args()

    # The announce line carries an em dash; a Windows console on cp1252 would
    # otherwise raise UnicodeEncodeError after a successful route.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

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
            "fast_router: absent - GEMINI_API_KEY or GOOGLE_API_KEY is not set.\n"
            "Set it in the environment, pass --api-key, or add it to the project's .env.\n"
        )
        sys.exit(2)

    try:
        decision = route_request(request_text, api_key=api_key, model=args.model)
    except RuntimeError as e:
        sys.stderr.write(f"Routing failed: {e}\n")
        sys.exit(1)

    if args.format == "json":
        print(json.dumps(asdict(decision), indent=2))
    else:
        print(format_line(decision))


if __name__ == "__main__":
    main()
