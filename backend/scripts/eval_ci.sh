#!/usr/bin/env bash
# CI gate for brain dump eval — fails if accuracy drops below threshold.
# Usage: ./scripts/eval_ci.sh [threshold]
# Default threshold: 80%

set -euo pipefail

THRESHOLD="${1:-80}"
CONTAINER="todo-backend"
RESULTS_FILE="/tmp/eval_ci_results.json"

echo "=== Brain Dump Eval CI ==="
echo "Threshold: ${THRESHOLD}%"
echo ""

# Run eval inside container
docker exec "$CONTAINER" python evaluation/run_eval.py \
    --output "$RESULTS_FILE" \
    --html 2>&1

# Extract accuracy
ACCURACY=$(docker exec "$CONTAINER" python -c "
import json
with open('$RESULTS_FILE') as f:
    data = json.load(f)
print(data['summary']['overall']['accuracy'] * 100)
")

echo ""
echo "Accuracy: ${ACCURACY}%"
echo "Threshold: ${THRESHOLD}%"

# Compare
PASS=$(python3 -c "print('yes' if float('$ACCURACY') >= float('$THRESHOLD') else 'no')")

if [ "$PASS" = "yes" ]; then
    echo "PASSED"
    exit 0
else
    echo "FAILED — accuracy ${ACCURACY}% below threshold ${THRESHOLD}%"
    exit 1
fi
