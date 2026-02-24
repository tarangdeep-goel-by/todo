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
from typing import Any, Dict, List, Optional, Tuple

# Add parent directory to path so we can import backend modules
backend_dir = Path(__file__).parent.parent
sys.path.insert(0, str(backend_dir))

from services.gemini_service import GeminiService


# ──────────────────────────────────────────────
# 1. Tree context builder
# ──────────────────────────────────────────────

def build_tree_context(tasks: List[Dict], user_id: str = "eval-user") -> str:
    """
    Build readable task tree string for Gemini context.
    Replicates TaskService.build_full_tree_context() format exactly.
    """
    # Group tasks by category
    categories: Dict[str, List[Dict]] = {}
    for task in tasks:
        cat = task["category"]
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(task)

    tree_str = f"User: {user_id}\n\n"

    for category, cat_tasks in sorted(categories.items()):
        tree_str += f"{category.upper()} TASKS:\n"
        top_level = [t for t in cat_tasks if t["parent_id"] is None]
        for task in top_level:
            status_tag = " [COMPLETED]" if task["status"] == "completed" else ""
            tree_str += f"├── {task['title']} (id: {task['id']}){status_tag}\n"
            tree_str += _build_subtree(cat_tasks, task["id"], indent=1)
        tree_str += "\n"

    return tree_str


def _build_subtree(tasks: List[Dict], parent_id: str, indent: int = 0) -> str:
    """Recursively build tree string with indentation."""
    result = ""
    children = [t for t in tasks if t["parent_id"] == parent_id]

    for child in children:
        status_tag = " [COMPLETED]" if child["status"] == "completed" else ""
        result += "  " * indent + f"├── {child['title']} (id: {child['id']}){status_tag}\n"
        result += _build_subtree(tasks, child["id"], indent + 1)

    return result


# ──────────────────────────────────────────────
# 2. Check engine
# ──────────────────────────────────────────────

class CheckResult:
    """Result of a single check."""
    def __init__(self, field: str, operator: str, expected: Any, actual: Any, passed: bool):
        self.field = field
        self.operator = operator
        self.expected = expected
        self.actual = actual
        self.passed = passed

    def __repr__(self):
        status = "✓" if self.passed else "✗"
        return f"{self.field}_{self.operator}({self.expected!r}): {status}  actual={self.actual!r}"


def _resolve_field(params: Dict, dotted_path: str) -> Any:
    """Resolve a dotted field path like 'changes.category' from params dict."""
    parts = dotted_path.split(".")
    current = params
    for part in parts:
        if isinstance(current, dict):
            current = current.get(part)
        else:
            return None
    return current


def _apply_check(actual_value: Any, operator: str, expected_value: Any) -> bool:
    """Apply a single check operator."""
    if operator == "exact":
        if actual_value is None and expected_value is None:
            return True
        if actual_value is None or expected_value is None:
            return False
        return str(actual_value).lower() == str(expected_value).lower()

    elif operator == "contains":
        if actual_value is None:
            return False
        return str(expected_value).lower() in str(actual_value).lower()

    elif operator == "in":
        if actual_value is None:
            return False
        return str(actual_value).lower() in [str(v).lower() for v in expected_value]

    elif operator == "gte":
        if actual_value is None:
            return False
        return float(actual_value) >= float(expected_value)

    elif operator == "lte":
        if actual_value is None:
            return False
        return float(actual_value) <= float(expected_value)

    elif operator == "null":
        if expected_value:
            return actual_value is None
        else:
            return actual_value is not None

    elif operator == "not_null":
        if expected_value:
            return actual_value is not None
        else:
            return actual_value is None

    return False


def check_intent_result(actual_intent: Dict, expected: Dict) -> List[CheckResult]:
    """Run all checks for a single expected intent against an actual intent."""
    results = []

    # Check intent type
    if "intent" in expected:
        actual_type = actual_intent.get("intent", "UNKNOWN")
        results.append(CheckResult(
            "intent", "exact", expected["intent"], actual_type,
            str(actual_type).upper() == str(expected["intent"]).upper()
        ))

    # Check all field_operator pairs in checks
    checks = expected.get("checks", {})
    params = actual_intent.get("parameters", {})

    for check_key, expected_value in checks.items():
        # Special case: confidence is at top level, not in parameters
        if check_key.startswith("confidence_"):
            operator = check_key.split("_", 1)[1]
            actual_value = actual_intent.get("confidence")
            passed = _apply_check(actual_value, operator, expected_value)
            results.append(CheckResult("confidence", operator, expected_value, actual_value, passed))
            continue

        # Parse field_operator from key (last _ segment is operator)
        # Handle dotted fields: "changes.category_exact" -> field="changes.category", op="exact"
        parts = check_key.rsplit("_", 1)
        if len(parts) != 2:
            continue

        field_path, operator = parts

        # Handle operators with underscores like "not_null"
        if operator == "null" and field_path.endswith("_not"):
            field_path = field_path[:-4]  # Remove "_not"
            operator = "not_null"

        actual_value = _resolve_field(params, field_path)
        passed = _apply_check(actual_value, operator, expected_value)
        results.append(CheckResult(field_path, operator, expected_value, actual_value, passed))

    return results


def match_intents(
    actual_list: List[Dict],
    expected_list: List[Dict]
) -> List[Tuple[Optional[Dict], Dict, List[CheckResult]]]:
    """
    Match expected intents to actual intents.
    Returns list of (actual_intent_or_None, expected_intent, check_results).

    Strategy:
    1. Match by intent type first.
    2. For same-type duplicates, use title_contains check scores to find best pairing.
    """
    matched = []
    used_actual = set()

    for expected in expected_list:
        exp_type = expected.get("intent", "").upper()

        # Find candidates of same type
        candidates = []
        for i, actual in enumerate(actual_list):
            if i in used_actual:
                continue
            if actual.get("intent", "").upper() == exp_type:
                candidates.append((i, actual))

        if not candidates:
            # No match found — try any unmatched
            for i, actual in enumerate(actual_list):
                if i not in used_actual:
                    candidates.append((i, actual))
                    break

        if not candidates:
            # Nothing left to match
            matched.append((None, expected, [
                CheckResult("intent", "exact", exp_type, "MISSING", False)
            ]))
            continue

        # If multiple same-type candidates, score by title_contains
        if len(candidates) > 1:
            title_check = expected.get("checks", {}).get("title_contains", "")
            if title_check:
                best_idx = None
                best_score = -1
                for i, actual in candidates:
                    actual_title = (actual.get("parameters", {}).get("title") or "").lower()
                    score = 1 if title_check.lower() in actual_title else 0
                    if score > best_score:
                        best_score = score
                        best_idx = i
                if best_idx is not None:
                    candidates = [(best_idx, actual_list[best_idx])]

        idx, actual = candidates[0]
        used_actual.add(idx)
        checks = check_intent_result(actual, expected)
        matched.append((actual, expected, checks))

    return matched


# ──────────────────────────────────────────────
# 3. Main eval loop
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
        matches = match_intents(actual_intents, expected_intents)

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
        print_case_result(i + 1, len(cases), result, matches)

    return results


# ──────────────────────────────────────────────
# 4. Console reporter
# ──────────────────────────────────────────────

def print_header(model: str, case_count: int, tree_size: int):
    """Print eval header."""
    print()
    print("=" * 60)
    print(f"  TODO AGENT EVAL — Intent Detection")
    print(f"  Model: {model} | Cases: {case_count} | Tree: {tree_size} tasks")
    print("=" * 60)
    print()


def print_case_result(num: int, total: int, result: Dict, matches: List):
    """Print single case result."""
    status = "PASS" if result["passed"] else "FAIL"
    status_color = "\033[92m" if result["passed"] else "\033[91m"
    reset = "\033[0m"

    print(f"[{num}/{total}] {result['id']}  {status_color}{status}{reset}  ({result['latency_ms']}ms)")

    if result["expected_intent_count"] > 1:
        count_ok = result["actual_intent_count"] == result["expected_intent_count"]
        count_mark = "✓" if count_ok else "✗"
        print(f"  Intent count: {result['expected_intent_count']} {count_mark}")

    for idx, (actual, expected, checks) in enumerate(matches):
        if result["expected_intent_count"] > 1:
            prefix = f"  [{idx}] "
        else:
            prefix = "  "

        for check in checks:
            mark = "✓" if check.passed else "✗"
            print(f"{prefix}{check}")

    if not result["passed"]:
        print(f"  → {result['failure_reason']}")
    print()


def print_summary(results: List[Dict], model: str):
    """Print aggregate summary."""
    print()
    print("─" * 12 + " SUMMARY " + "─" * 12)
    print()

    total = len(results)
    passed = sum(1 for r in results if r["passed"])
    pct = (passed / total * 100) if total else 0
    print(f"Overall:     {passed}/{total} ({pct:.1f}%)")
    print()

    # By intent category
    print("By Intent:")
    by_intent: Dict[str, List[bool]] = {}
    for r in results:
        cat = r["category"]
        if cat not in by_intent:
            by_intent[cat] = []
        by_intent[cat].append(r["passed"])

    for cat in sorted(by_intent.keys()):
        vals = by_intent[cat]
        p = sum(vals)
        t = len(vals)
        pct = (p / t * 100) if t else 0
        print(f"  {cat:<12} {p:>2}/{t:<2} ({pct:.1f}%)")
    print()

    # By difficulty
    print("By Difficulty:")
    by_diff: Dict[str, List[bool]] = {}
    for r in results:
        diff = r["difficulty"]
        if diff not in by_diff:
            by_diff[diff] = []
        by_diff[diff].append(r["passed"])

    for diff in ["easy", "medium", "hard"]:
        if diff in by_diff:
            vals = by_diff[diff]
            p = sum(vals)
            t = len(vals)
            pct = (p / t * 100) if t else 0
            print(f"  {diff:<12} {p:>2}/{t:<2} ({pct:.1f}%)")
    print()

    # Latency stats
    latencies = [r["latency_ms"] for r in results]
    if latencies:
        latencies_sorted = sorted(latencies)
        mean = sum(latencies) / len(latencies)
        p50 = latencies_sorted[len(latencies_sorted) // 2]
        p95_idx = min(int(len(latencies_sorted) * 0.95), len(latencies_sorted) - 1)
        p95 = latencies_sorted[p95_idx]
        print(f"Latency:")
        print(f"  mean={int(mean)}ms  p50={p50}ms  p95={p95}ms")
    print()

    # Failed cases
    failed = [r for r in results if not r["passed"]]
    if failed:
        print("Failed:")
        for r in failed:
            print(f"  {r['id']}: {r['failure_reason']}")
        print()


# ──────────────────────────────────────────────
# 5. JSON saver
# ──────────────────────────────────────────────

def build_summary(results: List[Dict]) -> Dict:
    """Build summary statistics from results."""
    total = len(results)
    passed = sum(1 for r in results if r["passed"])

    # By intent
    by_intent: Dict[str, Dict] = {}
    for r in results:
        cat = r["category"]
        if cat not in by_intent:
            by_intent[cat] = {"passed": 0, "total": 0}
        by_intent[cat]["total"] += 1
        if r["passed"]:
            by_intent[cat]["passed"] += 1
    for cat in by_intent:
        t = by_intent[cat]["total"]
        p = by_intent[cat]["passed"]
        by_intent[cat]["accuracy"] = round(p / t, 4) if t else 0

    # By difficulty
    by_diff: Dict[str, Dict] = {}
    for r in results:
        diff = r["difficulty"]
        if diff not in by_diff:
            by_diff[diff] = {"passed": 0, "total": 0}
        by_diff[diff]["total"] += 1
        if r["passed"]:
            by_diff[diff]["passed"] += 1
    for diff in by_diff:
        t = by_diff[diff]["total"]
        p = by_diff[diff]["passed"]
        by_diff[diff]["accuracy"] = round(p / t, 4) if t else 0

    # Latency
    latencies = sorted(r["latency_ms"] for r in results)
    perf = {}
    if latencies:
        perf = {
            "min": latencies[0],
            "max": latencies[-1],
            "mean": int(sum(latencies) / len(latencies)),
            "p50": latencies[len(latencies) // 2],
            "p95": latencies[min(int(len(latencies) * 0.95), len(latencies) - 1)],
        }

    return {
        "overall": {
            "passed": passed,
            "total": total,
            "accuracy": round(passed / total, 4) if total else 0,
        },
        "by_intent": by_intent,
        "by_difficulty": by_diff,
        "performance": {"latency_ms": perf},
    }


def save_results(results: List[Dict], summary: Dict, output_path: str, model: str, tree_size: int):
    """Save results and summary to JSON file."""
    output = {
        "timestamp": datetime.now().isoformat(),
        "model": model,
        "task_tree_size": tree_size,
        "case_count": len(results),
        "cases": results,
        "summary": summary,
    }

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    with open(output_path, "w") as f:
        json.dump(output, f, indent=2, default=str)

    print(f"Results saved to: {output_path}")


# ──────────────────────────────────────────────
# 6. Main
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
    print_header(model_name, len(cases), len(tasks))

    # Run eval
    results = await run_eval(cases, tree_context, gemini, no_llm=args.no_llm)

    # Summary
    summary = build_summary(results)
    print_summary(results, model_name)

    # Save
    save_results(results, summary, output_path, model_name, len(tasks))


if __name__ == "__main__":
    asyncio.run(main())
