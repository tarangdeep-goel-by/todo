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
    classify_failure_mode,
    print_header,
    print_case_result,
    print_summary,
    build_summary,
    save_results,
)
from services.gemini_service import GeminiService
from services.intent_prefilter import prefilter


# ──────────────────────────────────────────────
# LLM Judge for subjective cases
# ──────────────────────────────────────────────

JUDGE_PROMPT = """You are evaluating a task management AI that extracts actions from voice/text input.

Given the user's input and the AI's response, judge whether the response is REASONABLE.

User input: "{transcription}"

Expected actions (human-labeled): {expected}

Actual AI response: {actual}

Task tree context is available to the AI (it knows all existing tasks).

Evaluate:
1. Did the AI produce the right NUMBER of actions?
2. Are the action TYPES reasonable? (add/complete/edit/delete/move/breakdown)
3. Did it target the right TASKS?
4. Are the field values reasonable?

A response can be correct even if it differs from the expected label — ambiguous inputs may have multiple valid interpretations.

Respond with EXACTLY one line in this format:
PASS: <brief reason>
or
FAIL: <brief reason>"""


async def run_llm_judge(
    case: Dict,
    result: Dict,
    gemini: "GeminiService",
) -> Dict:
    """Run LLM judge on a single case. Returns judge verdict dict."""
    import google.generativeai as genai

    prompt = JUDGE_PROMPT.format(
        transcription=case["transcription"],
        expected=json.dumps(case["expected_actions"], indent=2),
        actual=json.dumps(result["actual_actions"], indent=2),
    )

    try:
        model = genai.GenerativeModel("gemini-2.5-flash-lite")
        response = model.generate_content(prompt)
        text = response.text.strip()

        passed = text.upper().startswith("PASS")
        return {
            "judge_passed": passed,
            "judge_response": text,
        }
    except Exception as e:
        return {
            "judge_passed": None,
            "judge_response": f"ERROR: {e}",
        }


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
    task_tree: Optional[List[Dict]] = None,
) -> List[Dict]:
    """Run all eval cases and return results."""
    results = []

    for i, case in enumerate(cases):
        case_id = case["id"]
        transcription = case["transcription"]
        expected_count = case["expected_action_count"]
        expected_actions = case["expected_actions"]

        start = time.time()

        prefilter_fired = False
        if no_llm:
            actual_actions = [{"action": "unknown", "content": "", "confidence": 0.5}]
        else:
            # Try pre-filter first (catches gibberish)
            prefilter_result = None if no_prefilter else prefilter(transcription)
            if prefilter_result is not None:
                prefilter_fired = True
                # Convert prefilter result to brain dump format
                actual_actions = [{"action": "unknown", "content": "", "confidence": 0.1}]
            else:
                try:
                    actual_actions = await gemini.detect_brain_dump(transcription, tree_context, task_tree=task_tree)
                except Exception as e:
                    actual_actions = [{"action": "error", "content": "", "confidence": 0.0}]
                # Rate limiting — only for actual LLM calls
                await asyncio.sleep(0.5)

        latency_ms = int((time.time() - start) * 1000)

        # Check action count (-1 = skip count check)
        count_match = expected_count == -1 or len(actual_actions) == expected_count

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
            "failure_mode": classify_failure_mode(result={
                "passed": all_passed,
                "expected_action_count": expected_count,
                "actual_action_count": len(actual_actions),
                "checks": [{"field": c.field, "passed": c.passed} for c in all_checks],
                "category": case["category"],
                "transcription": transcription,
            }, prefilter_fired=prefilter_fired),
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
    parser.add_argument("--with-judge", action="store_true",
                        help="Run LLM judge on cases tagged with judge=true")
    parser.add_argument("--html", action="store_true",
                        help="Generate HTML report alongside JSON results")

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

    # Build tree context — same for both search engines
    search_engine = os.environ.get("SEARCH_ENGINE", "fuzzy")
    tree_context = build_tree_context(tasks)
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
    results = await run_eval(cases, tree_context, gemini, no_llm=args.no_llm, search_engine=search_engine, no_prefilter=args.no_prefilter, task_tree=tasks)

    # LLM Judge pass (optional)
    if args.with_judge and not args.no_llm:
        judge_cases = [(i, c) for i, c in enumerate(cases) if c.get("judge")]
        if judge_cases:
            print(f"\n{'─' * 12} LLM JUDGE {'─' * 12}")
            print(f"Running judge on {len(judge_cases)} tagged cases...\n")
            judge_passed = 0
            for idx, case in judge_cases:
                verdict = await run_llm_judge(case, results[idx], gemini)
                results[idx]["judge_result"] = verdict
                status = "\033[92mPASS\033[0m" if verdict["judge_passed"] else "\033[91mFAIL\033[0m"
                print(f"  {case['id']}: {status} — {verdict['judge_response'][:80]}")
                if verdict["judge_passed"]:
                    judge_passed += 1
                await asyncio.sleep(0.3)
            print(f"\n  Judge: {judge_passed}/{len(judge_cases)} passed\n")

    # Summary
    summary = build_summary(results)
    print_summary(results, model_name)

    # Save
    save_results(results, summary, output_path, model_name, len(tasks))

    # HTML report
    if args.html:
        from evaluation.eval_report import generate_html
        html_path = output_path.replace(".json", ".html")
        with open(output_path) as f:
            report_data = json.load(f)
        with open(html_path, "w") as f:
            f.write(generate_html(report_data))
        print(f"HTML report: {html_path}")


if __name__ == "__main__":
    asyncio.run(main())
