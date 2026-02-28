#!/usr/bin/env python3
"""
Eval harness for LLM intent detection in the todo agent pipeline.

Usage:
    python evaluation/run_eval.py                          # Full run
    python evaluation/run_eval.py --filter-category ADD    # One intent type
    python evaluation/run_eval.py --filter-id add_01       # Single case
    python evaluation/run_eval.py --no-llm                 # Dry-run (mock responses)
"""

import argparse
import asyncio
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

# Add parent directory to path so we can import backend modules
backend_dir = Path(__file__).parent.parent
sys.path.insert(0, str(backend_dir))

from evaluation.eval_engine import (
    build_tree_context,
    match_entries,
    print_header,
    print_case_result,
    print_summary,
    build_summary,
    save_results,
)
from services.gemini_service import GeminiService


# ──────────────────────────────────────────────
# Main eval loop
# ──────────────────────────────────────────────

async def run_eval(
    cases: List[Dict],
    tree_context: str,
    gemini: Optional[GeminiService],
    no_llm: bool = False,
) -> List[Dict]:
    """Run all eval cases and return results."""
    results = []

    for i, case in enumerate(cases):
        case_id = case["id"]
        transcription = case["transcription"]
        expected_count = case["expected_intent_count"]
        expected_intents = case["expected_intents"]

        start = time.time()

        if no_llm:
            actual_intents = [{"intent": "UNKNOWN", "confidence": 0.5, "parameters": {}}]
        else:
            try:
                actual_intents = await gemini.detect_intent(transcription, tree_context)
            except Exception as e:
                actual_intents = [{"intent": "ERROR", "confidence": 0.0, "parameters": {"error": str(e)}}]
            # Rate limiting
            await asyncio.sleep(0.5)

        latency_ms = int((time.time() - start) * 1000)

        # Check intent count
        count_match = len(actual_intents) == expected_count

        # Match and check intents
        matches = match_entries(
            actual_intents,
            expected_intents,
            type_field="intent",
            content_field="title",
            params_field="parameters",
        )

        all_checks = []
        for actual, expected, checks in matches:
            all_checks.extend(checks)

        all_passed = count_match and all(c.passed for c in all_checks)

        # Build failure reason
        failure_reason = None
        if not all_passed:
            reasons = []
            if not count_match:
                reasons.append(f"intent count: expected {expected_count}, got {len(actual_intents)}")
            for c in all_checks:
                if not c.passed:
                    reasons.append(str(c))
            failure_reason = "; ".join(reasons)

        result = {
            "id": case_id,
            "category": case["category"],
            "difficulty": case["difficulty"],
            "transcription": transcription,
            "passed": all_passed,
            "latency_ms": latency_ms,
            "expected_intent_count": expected_count,
            "actual_intent_count": len(actual_intents),
            "actual_intents": actual_intents,
            "checks": [
                {
                    "field": c.field,
                    "operator": c.operator,
                    "expected": c.expected,
                    "actual": c.actual,
                    "passed": c.passed,
                }
                for c in all_checks
            ],
            "failure_reason": failure_reason,
        }
        results.append(result)

        # Print per-case result
        print_case_result(i + 1, len(cases), result, matches, count_key="expected_intent_count")

    return results


# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────

async def main():
    parser = argparse.ArgumentParser(description="Todo Agent Intent Detection Eval")
    parser.add_argument("--eval-config", default="evaluation/eval_config.json",
                        help="Path to eval config JSON")
    parser.add_argument("--task-tree", default="evaluation/task_tree.json",
                        help="Path to task tree JSON")
    parser.add_argument("--output", default=None,
                        help="Output results JSON path (default: auto-timestamped)")
    parser.add_argument("--no-llm", action="store_true",
                        help="Skip Gemini calls, mock UNKNOWN responses")
    parser.add_argument("--filter-category", default=None,
                        help="Run only cases of this intent category (ADD, COMPLETE, etc.)")
    parser.add_argument("--filter-id", default=None,
                        help="Run single case by ID")

    args = parser.parse_args()

    # Load task tree
    with open(args.task_tree) as f:
        tasks = json.load(f)

    # Load eval config
    with open(args.eval_config) as f:
        config = json.load(f)

    cases = config["cases"]

    # Apply filters
    if args.filter_category:
        cases = [c for c in cases if c["category"].upper() == args.filter_category.upper()]
    if args.filter_id:
        cases = [c for c in cases if c["id"] == args.filter_id]

    if not cases:
        print("No cases match the filter criteria.")
        sys.exit(1)

    # Build tree context
    tree_context = build_tree_context(tasks)

    # Init Gemini
    model_name = "gemini-2.5-flash-lite"
    gemini = None
    if not args.no_llm:
        api_key = os.environ.get("GEMINI_API_KEY")
        if not api_key:
            print("ERROR: GEMINI_API_KEY environment variable not set")
            sys.exit(1)
        gemini = GeminiService(api_key)
        model_name = "gemini-2.5-flash-lite"

    # Output path
    if args.output:
        output_path = args.output
    else:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_path = f"evaluation/results/eval_{timestamp}.json"

    # Print header
    print_header("TODO AGENT EVAL — Intent Detection", model_name, len(cases), len(tasks))

    # Run eval
    results = await run_eval(cases, tree_context, gemini, no_llm=args.no_llm)

    # Summary
    summary = build_summary(results)
    print_summary(results, model_name)

    # Save
    save_results(results, summary, output_path, model_name, len(tasks))


if __name__ == "__main__":
    asyncio.run(main())
