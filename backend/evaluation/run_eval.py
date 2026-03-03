#!/usr/bin/env python3
"""
Eval harness for brain dump action detection in the todo agent pipeline.

Usage:
    python evaluation/run_eval.py                          # Full run
    python evaluation/run_eval.py --filter-category ADD    # One action type
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
from services.intent_prefilter import prefilter


# ──────────────────────────────────────────────
# Main eval loop
# ──────────────────────────────────────────────

async def run_eval(
    cases: List[Dict],
    tree_context: str,
    gemini: Optional[GeminiService],
    no_llm: bool = False,
    search_engine: str = "fuzzy",
    no_prefilter: bool = False,
) -> List[Dict]:
    """Run all eval cases and return results."""
    results = []

    for i, case in enumerate(cases):
        case_id = case["id"]
        transcription = case["transcription"]
        expected_count = case["expected_action_count"]
        expected_actions = case["expected_actions"]

        start = time.time()

        if no_llm:
            actual_actions = [{"action": "unknown", "content": "", "confidence": 0.5}]
        else:
            # Try pre-filter first (catches gibberish)
            prefilter_result = None if no_prefilter else prefilter(transcription)
            if prefilter_result is not None:
                # Convert prefilter result to brain dump format
                actual_actions = [{"action": "unknown", "content": "", "confidence": 0.1}]
            else:
                try:
                    actual_actions = await gemini.detect_brain_dump(transcription, tree_context)
                except Exception as e:
                    actual_actions = [{"action": "error", "content": "", "confidence": 0.0}]
                # Rate limiting — only for actual LLM calls
                await asyncio.sleep(0.5)

        latency_ms = int((time.time() - start) * 1000)

        # Check action count
        count_match = len(actual_actions) == expected_count

        # Match and check actions
        matches = match_entries(
            actual_actions,
            expected_actions,
            type_field="action",
            content_field="content",
            params_field=None,  # brain dump fields are at top level
            search_engine=search_engine,
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
                reasons.append(f"action count: expected {expected_count}, got {len(actual_actions)}")
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
            "expected_action_count": expected_count,
            "actual_action_count": len(actual_actions),
            "actual_actions": actual_actions,
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
        print_case_result(i + 1, len(cases), result, matches, count_key="expected_action_count")

    return results


# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────

async def main():
    parser = argparse.ArgumentParser(description="Todo Agent Brain Dump Eval")
    parser.add_argument("--eval-config", default="evaluation/eval_config.json",
                        help="Path to eval config JSON")
    parser.add_argument("--task-tree", default="evaluation/task_tree.json",
                        help="Path to task tree JSON")
    parser.add_argument("--output", default=None,
                        help="Output results JSON path (default: auto-timestamped)")
    parser.add_argument("--no-llm", action="store_true",
                        help="Skip Gemini calls, mock UNKNOWN responses")
    parser.add_argument("--filter-category", default=None,
                        help="Run only cases of this action category (ADD, COMPLETE, etc.)")
    parser.add_argument("--filter-id", default=None,
                        help="Run single case by ID")
    parser.add_argument("--search-engine", default=None,
                        help="Override SEARCH_ENGINE (fuzzy or pg_native)")
    parser.add_argument("--no-prefilter", action="store_true",
                        help="Skip intent pre-filter, send everything to LLM")

    args = parser.parse_args()

    # Override search engine if specified
    if args.search_engine:
        os.environ["SEARCH_ENGINE"] = args.search_engine

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

    # Build tree context — compressed when pg_native
    search_engine = os.environ.get("SEARCH_ENGINE", "fuzzy")
    compressed = search_engine == "pg_native"
    tree_context = build_tree_context(tasks, compressed=compressed)
    if compressed:
        print(f"  Using compressed tree ({len(tree_context)} chars)")
    else:
        print(f"  Using full tree ({len(tree_context)} chars)")

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
    print_header("TODO AGENT EVAL — Brain Dump Detection", model_name, len(cases), len(tasks))

    # Run eval
    results = await run_eval(cases, tree_context, gemini, no_llm=args.no_llm, search_engine=search_engine, no_prefilter=args.no_prefilter)

    # Summary
    summary = build_summary(results)
    print_summary(results, model_name)

    # Save
    save_results(results, summary, output_path, model_name, len(tasks))


if __name__ == "__main__":
    asyncio.run(main())
