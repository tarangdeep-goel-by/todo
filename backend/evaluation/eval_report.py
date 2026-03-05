#!/usr/bin/env python3
"""Generate HTML report from eval results JSON."""

import json
import sys
from pathlib import Path


def generate_html(data: dict) -> str:
    """Generate HTML report from eval results dict."""
    summary = data["summary"]
    overall = summary["overall"]
    cases = data["cases"]
    by_cat = summary["by_category"]
    by_diff = summary["by_difficulty"]
    by_mode = summary.get("by_failure_mode", {})

    passed = overall["passed"]
    total = overall["total"]
    pct = overall["accuracy"] * 100

    # Color based on accuracy
    if pct >= 90:
        bar_color = "#22c55e"
    elif pct >= 70:
        bar_color = "#eab308"
    else:
        bar_color = "#ef4444"

    # Category rows
    cat_rows = ""
    for cat in sorted(by_cat.keys()):
        c = by_cat[cat]
        cat_pct = c["accuracy"] * 100
        cat_rows += f'<tr><td>{cat}</td><td>{c["passed"]}/{c["total"]}</td><td>{cat_pct:.1f}%</td></tr>\n'

    # Difficulty rows
    diff_rows = ""
    for diff in ["easy", "medium", "hard"]:
        if diff in by_diff:
            d = by_diff[diff]
            d_pct = d["accuracy"] * 100
            diff_rows += f'<tr><td>{diff}</td><td>{d["passed"]}/{d["total"]}</td><td>{d_pct:.1f}%</td></tr>\n'

    # Failure mode rows
    mode_rows = ""
    for mode in sorted(by_mode.keys()):
        mode_rows += f'<tr><td>{mode}</td><td>{by_mode[mode]}</td></tr>\n'

    # Failed case details
    failed_html = ""
    for case in cases:
        if case["passed"]:
            continue
        mode = case.get("failure_mode", "?")
        judge = case.get("judge_result", {})
        judge_html = ""
        if judge:
            j_status = "PASS" if judge.get("judge_passed") else "FAIL"
            judge_html = f'<div class="judge">Judge: {j_status} — {_esc(judge.get("judge_response", ""))}</div>'

        checks_html = ""
        for c in case.get("checks", []):
            mark = "pass" if c["passed"] else "fail"
            checks_html += f'<span class="check {mark}">{c["field"]}_{c["operator"]}: {_esc(str(c["actual"]))}</span> '

        failed_html += f"""<details>
<summary><span class="fail-id">{case["id"]}</span> <span class="mode">[{mode}]</span> {_esc(case.get("failure_reason", "")[:100])}</summary>
<div class="detail">
<p><strong>Input:</strong> {_esc(case["transcription"])}</p>
<p><strong>Expected:</strong> {case["expected_action_count"]} actions | <strong>Got:</strong> {case["actual_action_count"]}</p>
<p><strong>Checks:</strong> {checks_html}</p>
<pre>{_esc(json.dumps(case["actual_actions"], indent=2))}</pre>
{judge_html}
</div>
</details>
"""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Eval Report — {data.get("model", "unknown")}</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: -apple-system, system-ui, sans-serif; background: #f8f9fa; color: #1a1a1a; padding: 2rem; max-width: 960px; margin: 0 auto; }}
h1 {{ font-size: 1.5rem; margin-bottom: 0.5rem; }}
.meta {{ color: #666; margin-bottom: 2rem; font-size: 0.875rem; }}
.bar {{ background: #e5e7eb; border-radius: 8px; height: 32px; margin-bottom: 2rem; overflow: hidden; }}
.bar-fill {{ height: 100%; background: {bar_color}; display: flex; align-items: center; padding-left: 12px; color: white; font-weight: 600; font-size: 0.875rem; }}
table {{ width: 100%; border-collapse: collapse; margin-bottom: 1.5rem; }}
th, td {{ padding: 6px 12px; text-align: left; border-bottom: 1px solid #e5e7eb; font-size: 0.875rem; }}
th {{ font-weight: 600; color: #666; }}
h2 {{ font-size: 1.1rem; margin: 1.5rem 0 0.75rem; }}
details {{ margin-bottom: 4px; }}
summary {{ cursor: pointer; padding: 6px 8px; background: #fff; border: 1px solid #e5e7eb; border-radius: 4px; font-size: 0.8rem; }}
summary:hover {{ background: #f3f4f6; }}
.detail {{ padding: 12px; background: #fff; border: 1px solid #e5e7eb; border-top: 0; font-size: 0.8rem; }}
.detail pre {{ background: #f3f4f6; padding: 8px; border-radius: 4px; overflow-x: auto; font-size: 0.75rem; margin-top: 8px; }}
.fail-id {{ font-weight: 600; }}
.mode {{ color: #9333ea; }}
.check {{ display: inline-block; padding: 1px 6px; border-radius: 3px; font-size: 0.75rem; margin: 1px; }}
.check.pass {{ background: #dcfce7; color: #166534; }}
.check.fail {{ background: #fee2e2; color: #991b1b; }}
.judge {{ margin-top: 8px; padding: 6px 8px; background: #fef3c7; border-radius: 4px; font-size: 0.8rem; }}
</style>
</head>
<body>
<h1>Brain Dump Eval Report</h1>
<div class="meta">Model: {data.get("model", "?")} | Cases: {total} | Tree: {data.get("task_tree_size", "?")} tasks | {data.get("timestamp", "")}</div>

<div class="bar"><div class="bar-fill" style="width:{pct}%">{passed}/{total} ({pct:.1f}%)</div></div>

<h2>By Category</h2>
<table><tr><th>Category</th><th>Score</th><th>Accuracy</th></tr>{cat_rows}</table>

<h2>By Difficulty</h2>
<table><tr><th>Difficulty</th><th>Score</th><th>Accuracy</th></tr>{diff_rows}</table>

{"<h2>By Failure Mode</h2><table><tr><th>Mode</th><th>Count</th></tr>" + mode_rows + "</table>" if mode_rows else ""}

<h2>Failed Cases ({total - passed})</h2>
{failed_html if failed_html else "<p>All cases passed!</p>"}

</body>
</html>"""


def _esc(text: str) -> str:
    """HTML-escape text."""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def main():
    if len(sys.argv) < 2:
        print("Usage: python eval_report.py <results.json> [output.html]")
        sys.exit(1)

    input_path = sys.argv[1]
    with open(input_path) as f:
        data = json.load(f)

    html = generate_html(data)

    if len(sys.argv) >= 3:
        output_path = sys.argv[2]
    else:
        output_path = str(Path(input_path).with_suffix(".html"))

    with open(output_path, "w") as f:
        f.write(html)

    print(f"Report: {output_path}")


if __name__ == "__main__":
    main()
