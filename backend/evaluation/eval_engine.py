"""
Shared eval engine for intent detection and brain dump eval harnesses.

Provides:
- Tree context builder (build_tree_context / _build_subtree)
- Check engine (CheckResult, _resolve_field, _apply_check, check_entry_result, match_entries)
- Console reporters (print_header, print_case_result, print_summary)
- JSON persistence (build_summary, save_results)
"""

import json
import os
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple


# ──────────────────────────────────────────────
# 1. Tree context builder
# ──────────────────────────────────────────────

def build_tree_context(tasks: List[Dict], user_id: str = "eval-user", compressed: bool = False) -> str:
    """
    Build readable task tree string for Gemini context.
    Replicates TaskService.build_full_tree_context() format exactly.

    Args:
        tasks: List of task dicts
        user_id: User ID
        compressed: If True, omit UUIDs for token reduction
    """
    categories: Dict[str, List[Dict]] = {}
    for task in tasks:
        cat = task["category"]
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(task)

    if compressed:
        return _build_compressed_tree(categories)

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


def _build_compressed_tree(categories: Dict[str, List[Dict]]) -> str:
    """Build compressed tree without UUIDs."""
    tree_str = ""
    for category, cat_tasks in sorted(categories.items()):
        tree_str += f"{category.upper()}:\n"
        top_level = [t for t in cat_tasks if t["parent_id"] is None]
        for task in top_level:
            status_tag = " [done]" if task["status"] == "completed" else ""
            tree_str += f"- {task['title']}{status_tag}\n"
            tree_str += _build_compressed_subtree(cat_tasks, task["id"], indent=1)
        tree_str += "\n"
    return tree_str


def _build_compressed_subtree(tasks: List[Dict], parent_id: str, indent: int = 0) -> str:
    """Recursively build compressed tree string."""
    result = ""
    children = [t for t in tasks if t["parent_id"] == parent_id]
    for child in children:
        status_tag = " [done]" if child["status"] == "completed" else ""
        result += "  " * indent + f"- {child['title']}{status_tag}\n"
        result += _build_compressed_subtree(tasks, child["id"], indent + 1)
    return result


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


def check_entry_result(
    actual_entry: Dict,
    expected: Dict,
    type_field: str = "intent",
    params_field: Optional[str] = "parameters",
    search_engine: Optional[str] = None,
) -> List[CheckResult]:
    """
    Run all checks for a single expected entry against an actual entry.

    Args:
        actual_entry: The actual LLM output dict
        expected: The expected entry with type field and checks
        type_field: Key for the type/action field (e.g. "intent" or "action")
        params_field: Key for nested params (e.g. "parameters"), or None if fields are at top level
        search_engine: If set, merge mode-specific checks (checks_fuzzy or checks_pg_native)
    """
    results = []

    # Check type field (intent or action)
    if type_field in expected:
        actual_type = actual_entry.get(type_field, "UNKNOWN")
        results.append(CheckResult(
            type_field, "exact", expected[type_field], actual_type,
            str(actual_type).upper() == str(expected[type_field]).upper()
        ))

    # Merge shared + mode-specific checks
    checks = dict(expected.get("checks", {}))
    if search_engine:
        mode_checks = expected.get(f"checks_{search_engine}", {})
        checks.update(mode_checks)

    # Resolve params: either nested under params_field or at top level
    if params_field:
        params = actual_entry.get(params_field, {})
    else:
        params = actual_entry

    for check_key, expected_value in checks.items():
        # Special case: confidence is always at top level
        if check_key.startswith("confidence_"):
            operator = check_key.split("_", 1)[1]
            actual_value = actual_entry.get("confidence")
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


def match_entries(
    actual_list: List[Dict],
    expected_list: List[Dict],
    type_field: str = "intent",
    content_field: str = "title",
    params_field: Optional[str] = "parameters",
    search_engine: Optional[str] = None,
) -> List[Tuple[Optional[Dict], Dict, List[CheckResult]]]:
    """
    Match expected entries to actual entries.
    Returns list of (actual_entry_or_None, expected_entry, check_results).

    Args:
        actual_list: List of actual LLM output dicts
        expected_list: List of expected entries with checks
        type_field: Key for the type/action field (e.g. "intent" or "action")
        content_field: Key used for disambiguation when multiple same-type entries exist
        params_field: Key for nested params, or None if fields are at top level
        search_engine: If set, merge mode-specific checks (checks_fuzzy or checks_pg_native)
    """
    matched = []
    used_actual = set()

    for expected in expected_list:
        exp_type = expected.get(type_field, "").upper()

        # Find candidates of same type
        candidates = []
        for i, actual in enumerate(actual_list):
            if i in used_actual:
                continue
            if actual.get(type_field, "").upper() == exp_type:
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
                CheckResult(type_field, "exact", exp_type, "MISSING", False)
            ]))
            continue

        # If multiple same-type candidates, score by content_contains check
        if len(candidates) > 1:
            # Look for content_contains check to disambiguate
            content_check = expected.get("checks", {}).get(f"{content_field}_contains", "")
            if content_check:
                best_idx = None
                best_score = -1
                for i, actual in candidates:
                    if params_field:
                        actual_content = (actual.get(params_field, {}).get(content_field) or "").lower()
                    else:
                        actual_content = (actual.get(content_field) or "").lower()
                    score = 1 if content_check.lower() in actual_content else 0
                    if score > best_score:
                        best_score = score
                        best_idx = i
                if best_idx is not None:
                    candidates = [(best_idx, actual_list[best_idx])]

        idx, actual = candidates[0]
        used_actual.add(idx)
        checks = check_entry_result(actual, expected, type_field=type_field, params_field=params_field, search_engine=search_engine)
        matched.append((actual, expected, checks))

    return matched


# ──────────────────────────────────────────────
# 3. Console reporter
# ──────────────────────────────────────────────

def print_header(title: str, model: str, case_count: int, tree_size: int):
    """Print eval header."""
    print()
    print("=" * 60)
    print(f"  {title}")
    print(f"  Model: {model} | Cases: {case_count} | Tree: {tree_size} tasks")
    print("=" * 60)
    print()


def print_case_result(num: int, total: int, result: Dict, matches: List, count_key: str = "expected_intent_count"):
    """Print single case result."""
    status = "PASS" if result["passed"] else "FAIL"
    status_color = "\033[92m" if result["passed"] else "\033[91m"
    reset = "\033[0m"

    print(f"[{num}/{total}] {result['id']}  {status_color}{status}{reset}  ({result['latency_ms']}ms)")

    expected_count = result[count_key]
    actual_count_key = count_key.replace("expected_", "actual_")

    if expected_count > 1:
        count_ok = result[actual_count_key] == expected_count
        count_mark = "✓" if count_ok else "✗"
        print(f"  Count: {expected_count} {count_mark}")

    for idx, (actual, expected, checks) in enumerate(matches):
        if expected_count > 1:
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

    # By category
    print("By Category:")
    by_cat: Dict[str, List[bool]] = {}
    for r in results:
        cat = r["category"]
        if cat not in by_cat:
            by_cat[cat] = []
        by_cat[cat].append(r["passed"])

    for cat in sorted(by_cat.keys()):
        vals = by_cat[cat]
        p = sum(vals)
        t = len(vals)
        pct = (p / t * 100) if t else 0
        print(f"  {cat:<20} {p:>2}/{t:<2} ({pct:.1f}%)")
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
            print(f"  {diff:<20} {p:>2}/{t:<2} ({pct:.1f}%)")
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
# 4. JSON persistence
# ──────────────────────────────────────────────

def build_summary(results: List[Dict]) -> Dict:
    """Build summary statistics from results."""
    total = len(results)
    passed = sum(1 for r in results if r["passed"])

    # By category
    by_cat: Dict[str, Dict] = {}
    for r in results:
        cat = r["category"]
        if cat not in by_cat:
            by_cat[cat] = {"passed": 0, "total": 0}
        by_cat[cat]["total"] += 1
        if r["passed"]:
            by_cat[cat]["passed"] += 1
    for cat in by_cat:
        t = by_cat[cat]["total"]
        p = by_cat[cat]["passed"]
        by_cat[cat]["accuracy"] = round(p / t, 4) if t else 0

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
        "by_category": by_cat,
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
