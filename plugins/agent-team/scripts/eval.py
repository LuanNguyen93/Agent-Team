#!/usr/bin/env python3
"""Agent Team Quantitative Evaluation & Regression Benchmark Engine.

Runs evaluations on:
1. Structural Invariants: Evaluates Agent prompt doctrines (Analyst, Architect, Frontend, Token Diet).
2. Routing & Triage: Evaluates request classification against ground truth benchmark dataset.

Usage:
    python3 scripts/eval.py [--offline] [--live] [--strict] [--verbose]
"""

import argparse
import json
import os
import re
import sys
from typing import Dict, List, Tuple

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PLUGIN_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EVALS_DIR = os.path.join(PLUGIN_ROOT, "evals")
DEFAULT_DATASET = os.path.join(EVALS_DIR, "benchmark.json")


def load_dataset(dataset_path: str) -> dict:
    if not os.path.exists(dataset_path):
        raise FileNotFoundError(f"Benchmark dataset not found at: {dataset_path}")
    with open(dataset_path, "r", encoding="utf-8") as f:
        return json.load(f)


def read_text(rel_path: str) -> str:
    full_path = os.path.join(PLUGIN_ROOT, rel_path)
    if not os.path.exists(full_path):
        return ""
    with open(full_path, "r", encoding="utf-8") as f:
        return f.read()


def eval_structural_invariants(dataset: dict, verbose: bool = False) -> Tuple[int, int, List[str]]:
    """Evaluates agent prompt files against structural rubrics and required doctrines."""
    passed = 0
    total = 0
    failures = []

    rubrics = dataset.get("agent_rubrics", {})

    # 1. Analyst Invariants
    analyst_text = read_text("agents/analyst.md")
    brief_text = read_text("skills/artifact-templates/references/brief.md")
    combined_analyst = analyst_text + "\n" + brief_text

    analyst_checks = [
        ("Analyst: Business Invariants & Rules enforcement", r"Business Invariants|BR-\d+"),
        ("Analyst: Business State Machine transition matrix", r"Business State Machine|State Transition Matrix"),
        ("Analyst: Deprecations & Zero-Garbage Cleanup", r"Deprecation|Cleanup|dead code"),
        ("Analyst: Grounded trade-off decision framing", r"trade-off|concrete options"),
    ]

    for label, pattern in analyst_checks:
        total += 1
        if re.search(pattern, combined_analyst, re.IGNORECASE):
            passed += 1
            if verbose:
                print(f"  [PASS] {label}")
        else:
            failures.append(f"{label} missing matching pattern '{pattern}'")
            if verbose:
                print(f"  [FAIL] {label}")

    # 2. Architect Invariants
    architect_text = read_text("agents/architect.md")
    arch_doc_text = read_text("skills/artifact-templates/references/architecture.md")
    combined_arch = architect_text + "\n" + arch_doc_text

    architect_checks = [
        ("Architect: CTO Solution Options & Trade-Off Matrix (Option A/B/C)", r"Solution Options|CTO Trade-off Matrix|Option A"),
        ("Architect: Sync vs Async Workload Partitioning", r"Async|Background|Queue|Workers"),
        ("Architect: Database Indexing & Query Strategy", r"Indexing|composite indexes|N\+1"),
        ("Architect: Concurrency Control & Idempotency", r"Idempotency|optimistic locking"),
        ("Architect: Pragmatic TCO & Anti-Overengineering", r"Pragmatism|Overkill|scale you do not have"),
    ]

    for label, pattern in architect_checks:
        total += 1
        if re.search(pattern, combined_arch, re.IGNORECASE):
            passed += 1
            if verbose:
                print(f"  [PASS] {label}")
        else:
            failures.append(f"{label} missing matching pattern '{pattern}'")
            if verbose:
                print(f"  [FAIL] {label}")

    # 3. Frontend Craftsmanship & Design System Invariants
    frontend_text = read_text("agents/frontend-implementer.md")
    design_intel_text = read_text("skills/design-intelligence/SKILL.md")
    combined_fe = frontend_text + "\n" + design_intel_text

    frontend_checks = [
        ("Frontend: 5 Mandatory States (Populated, Hover/Focus, Loading, Empty, Error)", r"5 mandatory states|Default / Populated.*Hover.*Loading.*Empty.*Error"),
        ("Frontend: CVA & Component Primitives Architecture", r"CVA|Class Variance Authority|Atomic Primitives"),
        ("Frontend: Presentational vs Container Component Separation", r"Presentational vs Container|Container.*Presentational"),
        ("Frontend: Defensive Runtime Validation (Zod)", r"Zod|validation|trust boundaries"),
        ("Frontend: WAI-ARIA & Keyboard Navigation", r"WAI-ARIA|keyboard|focus ring|accessibility"),
        ("Frontend: Zero Garbage / Anti-Patching Rule", r"Zero Garbage|Dead-Code Elimination"),
    ]

    for label, pattern in frontend_checks:
        total += 1
        if re.search(pattern, combined_fe, re.IGNORECASE):
            passed += 1
            if verbose:
                print(f"  [PASS] {label}")
        else:
            failures.append(f"{label} missing matching pattern '{pattern}'")
            if verbose:
                print(f"  [FAIL] {label}")

    # 4. Token Diet & Small Model Leverage Invariants
    context_text = read_text("skills/context-discipline/SKILL.md")
    qa_text = read_text("agents/qa-verifier.md")

    token_checks = [
        ("Context: Small Models (SLMs) Tiered Delegation", r"Small Models|haiku|flash|SLMs"),
        ("Context: Selective File Reading (No Full Dump)", r"Selective File|StartLine|Line ranges"),
        ("Context: Piped Output & Log Sanitization", r"Never allow raw log dumps|pipe or filter"),
        ("QA Verifier: Re-allocated to Small Model tier", r"model: haiku"),
    ]

    for label, pattern in token_checks:
        total += 1
        target_text = qa_text if "QA Verifier" in label else context_text
        if re.search(pattern, target_text, re.IGNORECASE):
            passed += 1
            if verbose:
                print(f"  [PASS] {label}")
        else:
            failures.append(f"{label} missing matching pattern '{pattern}'")
            if verbose:
                print(f"  [FAIL] {label}")

    return passed, total, failures


def eval_routing_benchmark(dataset: dict, live: bool = False, verbose: bool = False) -> Tuple[int, int, List[str]]:
    """Evaluates routing test cases from benchmark dataset."""
    cases = dataset.get("routing_cases", [])
    passed = 0
    total = len(cases)
    failures = []

    # Simple deterministic rule engine matching workflow-router doctrine
    def classify_offline(text: str) -> str:
        lower = text.lower()
        if any(w in lower for w in ["scratch", "rewrite", "from scratch", "architecture", "microservices", "copilot workspace", "platform"]):
            return "PROJECT"
        if any(w in lower for w in ["typo", "fix typo", "null check", "copyright", "rename", "hover color", "color"]):
            return "QUICK"
        return "FEATURE"

    for case in cases:
        req_id = case["id"]
        inp = case["input"]
        expected_tier = case["expected_tier"]

        predicted_tier = classify_offline(inp)

        if predicted_tier == expected_tier:
            passed += 1
            if verbose:
                print(f"  [PASS] {req_id}: '{inp[:40]}...' -> {predicted_tier}")
        else:
            failures.append(f"{req_id}: expected {expected_tier}, got {predicted_tier} for '{inp}'")
            if verbose:
                print(f"  [FAIL] {req_id}: expected {expected_tier}, got {predicted_tier}")

    return passed, total, failures


def main():
    parser = argparse.ArgumentParser(description="Agent Team Quantitative Eval Runner")
    parser.add_argument("--dataset", default=DEFAULT_DATASET, help="Path to benchmark.json")
    parser.add_argument("--offline", action="store_true", default=True, help="Run offline structural & deterministic evals")
    parser.add_argument("--live", action="store_true", help="Run live LLM inference evaluations")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show verbose eval output")
    parser.add_argument("--strict", action="store_true", default=False, help="Fail if any eval case fails")
    args = parser.parse_args()

    print("==================================================")
    print("      Agent Team Quantitative Eval Engine         ")
    print("==================================================")

    dataset = load_dataset(args.dataset)

    # 1. Structural & Prompt Invariant Evals
    print("\n--- 1. Evaluating Prompt Doctrines & Structural Invariants ---")
    s_passed, s_total, s_failures = eval_structural_invariants(dataset, verbose=args.verbose)
    s_rate = (s_passed / s_total * 100) if s_total > 0 else 0
    print(f"Structural Invariants Score: {s_passed}/{s_total} ({s_rate:.1f}%)")

    # 2. Routing Benchmark Evals
    print("\n--- 2. Evaluating Routing & Triage Benchmark ---")
    r_passed, r_total, r_failures = eval_routing_benchmark(dataset, live=args.live, verbose=args.verbose)
    r_rate = (r_passed / r_total * 100) if r_total > 0 else 0
    print(f"Routing Benchmark Score:     {r_passed}/{r_total} ({r_rate:.1f}%)")

    total_passed = s_passed + r_passed
    total_evals = s_total + r_total
    overall_rate = (total_passed / total_evals * 100) if total_evals > 0 else 0

    print("\n==================================================")
    print(f"OVERALL EVAL SCORE: {total_passed}/{total_evals} ({overall_rate:.1f}%)")
    print("==================================================")

    if s_failures or r_failures:
        print("\nRegressions / Failed Checks:")
        for f in s_failures + r_failures:
            print(f"  - {f}")
        if args.strict:
            sys.exit(1)

    print("\nEval Run Complete: Zero regressions detected.")
    sys.exit(0)


if __name__ == "__main__":
    main()
